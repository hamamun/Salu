import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/browser_service.dart';
import 'package:salu/core/info_collector.dart';
import 'package:salu/core/info_controller.dart';
import 'package:salu/core/panel_service.dart';
import 'package:salu/core/player_service.dart';
import 'package:salu/core/queue_service.dart';
import 'package:salu/core/ui_lock.dart';
import 'package:salu/core/window_state_service.dart';
import 'package:salu/theme/app_theme.dart';
import 'package:salu/ui/osc/open_media_control.dart';
import 'package:salu/ui/osc/right_menu.dart';
import 'package:salu/ui/panels/info_panel.dart';
import 'package:salu/ui/panels/playlist_panel.dart';
import 'package:salu/ui/panels/track_panel.dart';
import 'package:salu/ui/panels/tune_panel.dart';
import 'package:salu/ui/screens/home_screen.dart';
import 'package:salu/ui/widgets/glass_capsule.dart';
import 'package:salu/ui/widgets/salu_icon_button.dart';
import 'package:salu/ui/widgets/salu_marks.dart';
import 'package:salu/ui/widgets/settings_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

final PanelService panels = PanelService.instance;
final PlayerService player = PlayerService.instance;

Future<void> secondary(WidgetTester tester, Offset point) async {
  final TestGesture gesture = await tester.startGesture(
    point,
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryButton,
  );
  await gesture.up();
  await tester.pumpAndSettle();
}

class Harness extends StatelessWidget {
  const Harness({
    super.key,
    required this.anchor,
    required this.onPicture,
    required this.onSettings,
    this.info,
    this.panel,
  });
  final ValueNotifier<Offset> anchor;
  final VoidCallback onPicture, onSettings;
  final InfoController? info;
  final Widget? panel;
  @override
  Widget build(BuildContext context) => MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              RightMenuTarget(
                anchor: anchor,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onPicture,
                  child: const ColoredBox(color: AppColors.background),
                ),
              ),
              const Positioned(left: 0, top: 100, child: OpenMediaControl()),
              RightMenu(anchor: anchor, onSettings: onSettings),
              if (panel != null) panel!,
              if (info != null) InfoPanel(controller: info),
            ],
          ),
        ),
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PlayerService.installNotifierOnlyForTesting();
  setUp(() {
    panels.closeAll();
    player.hasMedia.value = false;
    player.currentPath.value = null;
    player.transportState.value = TransportState.idle;
    player.shuffleOn.value = false;
    player.repeatMode.value = RepeatMode.off;
    player.trackSurface.value = TrackSurface.empty;
    player.position.value = Duration.zero;
    player.duration.value = Duration.zero;
    QueueService.instance.items.value = const <QueueItem>[];
    QueueService.instance.index.value = -1;
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('one-popup world includes direct writes, every panel and the pill', () {
    final List<ValueNotifier<bool>> popups = <ValueNotifier<bool>>[
      panels.playlistOpen,
      panels.trackPanelOpen,
      panels.tunePanelOpen,
      panels.infoOpen,
      panels.rightMenuOpen,
      panels.openPillOpen,
    ];
    for (final ValueNotifier<bool> a in popups) {
      for (final ValueNotifier<bool> b in popups) {
        a.value = true;
        b.value = true;
        expect(popups.where((p) => p.value).length, 1);
        expect(b.value, isTrue);
      }
    }
    panels.closeAll();
    expect(panels.handleSecondaryClick(), isTrue);
    expect(panels.rightMenuOpen.value, isTrue);
    expect(panels.handleSecondaryClick(), isFalse);
    expect(panels.anyOpen, isFalse);
  });

  test('strip placement clamps all edges and flips above bottom', () {
    for (final bool channel in <bool>[false, true]) {
      final Size strip = Size(RightMenu.widthFor(channel), 42);
      for (final Offset cursor in <Offset>[
        const Offset(4, 4),
        const Offset(796, 4),
        const Offset(4, 596),
        const Offset(796, 596),
      ]) {
        final Offset at = RightMenu.placement(
          cursor,
          const Size(800, 600),
          strip,
        );
        expect(at.dx, greaterThanOrEqualTo(12));
        expect(at.dy, greaterThanOrEqualTo(12));
        expect(at.dx + strip.width, lessThanOrEqualTo(788));
        expect(at.dy + strip.height, lessThanOrEqualTo(588));
        if (cursor.dy > 500) expect(at.dy + strip.height, lessThan(cursor.dy));
      }
    }
  });

  testWidgets(
    'secondary toggles; outside primary dismisses without transport; clean primary plays',
    (tester) async {
      final ValueNotifier<Offset> anchor = ValueNotifier<Offset>(Offset.zero);
      int transport = 0;
      await tester.pumpWidget(
        Harness(
          anchor: anchor,
          onPicture: () => transport++,
          onSettings: () {},
        ),
      );
      await secondary(tester, const Offset(400, 300));
      expect(find.byType(GlassCapsule), findsOneWidget);
      expect(ChromeLock.instance.isLocked, isTrue);
      expect(transport, 0);
      await secondary(tester, const Offset(700, 400));
      expect(panels.rightMenuOpen.value, isFalse);
      expect(ChromeLock.instance.isLocked, isFalse);
      await secondary(tester, const Offset(400, 300));
      await tester.tapAt(const Offset(700, 400));
      await tester.pumpAndSettle();
      expect(panels.rightMenuOpen.value, isFalse);
      expect(transport, 0);
      await tester.tapAt(const Offset(700, 400));
      expect(transport, 1);
      await tester.pumpWidget(const SizedBox());
      anchor.dispose();
    },
  );

  testWidgets(
    'toggles stay open, repeat-one keeps shuffle but quiets its mark',
    (tester) async {
      player.hasMedia.value = true;
      player.currentPath.value = 'C:/song.mp3';
      player.transportState.value = TransportState.playing;
      final ValueNotifier<Offset> anchor = ValueNotifier<Offset>(Offset.zero);
      await tester.pumpWidget(
        Harness(anchor: anchor, onPicture: () {}, onSettings: () {}),
      );
      await secondary(tester, const Offset(400, 300));
      await tester.tap(find.byKey(const ValueKey<String>('Shuffle')));
      await tester.pumpAndSettle();
      expect(player.shuffleOn.value, isTrue);
      expect(panels.rightMenuOpen.value, isTrue);
      expect(
        tester.widget<ShuffleMark>(find.byType(ShuffleMark)).quiet,
        isFalse,
      );
      for (int n = 0; n < 2; n++) {
        await tester.tap(find.byKey(const ValueKey<String>('Repeat')));
        await tester.pumpAndSettle();
      }
      expect(player.repeatMode.value, RepeatMode.one);
      expect(tester.widget<RepeatMark>(find.byType(RepeatMark)).bead, isTrue);
      expect(
        tester.widget<ShuffleMark>(find.byType(ShuffleMark)).quiet,
        isTrue,
      );
      expect(player.shuffleOn.value, isTrue);
      expect(panels.rightMenuOpen.value, isTrue);
      await tester.pumpWidget(const SizedBox());
      expect(ChromeLock.instance.isLocked, isFalse);
      anchor.dispose();
    },
  );

  testWidgets(
    'idle and stopped Info is inert; channel removes both toggles and reserves no fake Remote',
    (tester) async {
      final ValueNotifier<Offset> anchor = ValueNotifier<Offset>(Offset.zero);
      await tester.pumpWidget(
        Harness(anchor: anchor, onPicture: () {}, onSettings: () {}),
      );
      await secondary(tester, const Offset(400, 300));
      final Finder infoButton = find.descendant(
        of: find.byKey(const ValueKey<String>('Info')),
        matching: find.byType(SaluIconButton),
      );
      expect(tester.widget<SaluIconButton>(infoButton).enabled, isFalse);
      await tester.tap(infoButton);
      await tester.pump();
      expect(panels.infoOpen.value, isFalse);
      player.hasMedia.value = true;
      player.currentPath.value = 'C:/song.mp3';
      player.transportState.value = TransportState.stopped;
      await tester.pump();
      expect(tester.widget<SaluIconButton>(infoButton).enabled, isFalse);
      QueueService.instance.items.value = const <QueueItem>[
        QueueItem('https://example.org', name: 'News'),
      ];
      await tester.pumpAndSettle();
      expect(find.byType(ShuffleMark), findsNothing);
      expect(find.byType(RepeatMark), findsNothing);
      expect(
        find.descendant(
          of: find.byType(RightMenu),
          matching: find.byType(SaluIconButton),
        ),
        findsNWidgets(2),
      );
      expect(tester.getSize(find.byType(GlassCapsule)), const Size(82, 42));
      await tester.pumpWidget(const SizedBox());
      anchor.dispose();
    },
  );

  testWidgets('Esc and settings door release lock; callback sees closed menu', (
    tester,
  ) async {
    final ValueNotifier<Offset> anchor = ValueNotifier<Offset>(Offset.zero);
    int settings = 0;
    await tester.pumpWidget(
      Harness(
        anchor: anchor,
        onPicture: () {},
        onSettings: () {
          expect(panels.rightMenuOpen.value, isFalse);
          expect(ChromeLock.instance.isLocked, isFalse);
          settings++;
        },
      ),
    );
    await secondary(tester, const Offset(400, 300));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(panels.rightMenuOpen.value, isFalse);
    expect(ChromeLock.instance.isLocked, isFalse);
    await secondary(tester, const Offset(400, 300));
    await tester.tap(find.byKey(const ValueKey<String>('Settings')));
    await tester.pumpAndSettle();
    expect(settings, 1);
    await tester.pumpWidget(const SizedBox());
    anchor.dispose();
  });

  for (final (String, Widget, ValueNotifier<bool>) panel
      in <(String, Widget, ValueNotifier<bool>)>[
    ('Playlist', const PlaylistPanel(), panels.playlistOpen),
    ('Tracks', const TrackPanel(), panels.trackPanelOpen),
    ('Tune', const TunePanel(), panels.tunePanelOpen),
  ]) {
    testWidgets('${panel.$1}: secondary click closes only the open panel', (
      tester,
    ) async {
      final ValueNotifier<Offset> anchor = ValueNotifier<Offset>(Offset.zero);
      await tester.pumpWidget(
        Harness(
          anchor: anchor,
          onPicture: () {},
          onSettings: () {},
          panel: panel.$2,
        ),
      );
      panel.$3.value = true;
      await tester.pumpAndSettle();
      await secondary(tester, const Offset(20, 500));
      expect(panel.$3.value, isFalse);
      expect(panels.rightMenuOpen.value, isFalse);
      await tester.pumpWidget(const SizedBox());
      expect(ChromeLock.instance.isLocked, isFalse);
      anchor.dispose();
    });
  }

  testWidgets('Info door, geometry, clock ticks, stop and pill exclusivity', (
    tester,
  ) async {
    final ValueNotifier<Offset> anchor = ValueNotifier<Offset>(Offset.zero);
    int reads = 0;
    final InfoController info = InfoController(
      open: panels.infoOpen,
      changes: <Listenable>[player.currentPath],
      context: () => InfoContext(path: player.currentPath.value ?? ''),
      collector: InfoCollector(
        read: (key) async {
          reads++;
          return key == 'metadata/list/count' ? '0' : '';
        },
        fileSize: (_) async => null,
      ),
    );
    await tester.pumpWidget(
      Harness(anchor: anchor, onPicture: () {}, onSettings: () {}, info: info),
    );
    player.currentPath.value = 'C:/song.mp3';
    player.hasMedia.value = true;
    player.transportState.value = TransportState.playing;
    player.duration.value = const Duration(seconds: 120);
    await secondary(tester, const Offset(400, 300));
    await tester.tap(find.byKey(const ValueKey<String>('Info')));
    await tester.pumpAndSettle();
    expect(panels.rightMenuOpen.value, isFalse);
    expect(panels.infoOpen.value, isTrue);
    expect(ChromeLock.instance.isLocked, isTrue);
    expect(
      tester.getSize(find.byKey(const ValueKey<String>('info-panel-surface'))),
      const Size(322, 452),
    );
    expect(
      tester.getTopLeft(
        find.byKey(const ValueKey<String>('info-panel-surface')),
      ),
      const Offset(0, 148),
    );
    final int frozenReads = reads;
    player.position.value = const Duration(seconds: 10);
    await tester.pump();
    expect(find.text('00:10'), findsOneWidget);
    expect(find.text('01:50'), findsOneWidget);
    expect(reads, frozenReads);
    await tester.tap(find.byType(OpenMediaControl));
    await tester.pumpAndSettle();
    expect(panels.infoOpen.value, isFalse);
    expect(panels.openPillOpen.value, isTrue);
    panels.openInfo();
    await tester.pumpAndSettle();
    expect(panels.openPillOpen.value, isFalse);
    expect(panels.infoOpen.value, isTrue);
    player.currentPath.value = 'C:/next.mp3';
    await tester.pumpAndSettle();
    expect(panels.infoOpen.value, isTrue);
    expect(find.text('next'), findsOneWidget);
    player.transportState.value = TransportState.stopped;
    await tester.pumpAndSettle();
    expect(panels.infoOpen.value, isFalse);
    expect(ChromeLock.instance.isLocked, isFalse);
    await tester.pumpWidget(const SizedBox());
    info.dispose();
    anchor.dispose();
  });

  testWidgets('Info width clamps at a hypothetical smaller window', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(300, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final InfoController info = InfoController(
      open: panels.infoOpen,
      changes: <Listenable>[],
      context: () => const InfoContext(path: 'song.mp3'),
      collector: InfoCollector(
        read: (_) async => '',
        fileSize: (_) async => null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: InfoPanel(controller: info)),
      ),
    );
    panels.openInfo();
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey<String>('info-panel-surface'))),
      const Size(276, 452),
    );
    await tester.pumpWidget(const SizedBox());
    info.dispose();
  });

  testWidgets('real HomeScreen gates Web/mini and Settings opens General', (
    tester,
  ) async {
    // No media is loaded, so the real home can mount without a native player.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      (_) async => false,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('desktop_drop'),
      (_) async => null,
    );
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark, home: const HomeScreen()),
    );
    await tester.pumpAndSettle();
    await secondary(tester, const Offset(400, 400));
    expect(panels.rightMenuOpen.value, isTrue);
    await tester.tap(find.byKey(const ValueKey<String>('Settings')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SettingsDialog>(find.byType(SettingsDialog)).initialTab,
      SettingsTab.general,
    );
    await secondary(tester, const Offset(10, 300));
    expect(find.byType(SettingsDialog), findsNothing);
    await secondary(tester, const Offset(400, 400));
    BrowserService.instance.mode.value = SaluMode.web;
    await tester.pumpAndSettle();
    expect(find.byType(RightMenuTarget), findsNothing);
    expect(panels.rightMenuOpen.value, isFalse);
    await secondary(tester, const Offset(400, 400));
    expect(panels.rightMenuOpen.value, isFalse);
    WindowStateService.instance.mode.value = WindowMode.mini;
    await tester.pumpAndSettle();
    expect(find.byType(RightMenu), findsNothing);
    expect(find.byType(InfoPanel), findsNothing);
    await secondary(tester, const Offset(400, 20));
    expect(panels.rightMenuOpen.value, isFalse);
    await tester.pumpWidget(const SizedBox());
    WindowStateService.instance.mode.value = WindowMode.full;
    BrowserService.instance.mode.value = SaluMode.player;
    expect(ChromeLock.instance.isLocked, isFalse);
  });
}
