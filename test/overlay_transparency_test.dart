import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/panel_service.dart';
import 'package:salu/core/player_service.dart';
import 'package:salu/core/settings_service.dart';
import 'package:salu/theme/app_theme.dart';
import 'package:salu/theme/themed_app.dart';
import 'package:salu/ui/mini/mini_progress.dart';
import 'package:salu/ui/osc/media_timeline.dart';
import 'package:salu/ui/osc/volume_bar.dart';
import 'package:salu/ui/osd/osd_controller.dart';
import 'package:salu/ui/panels/track_panel.dart';
import 'package:salu/ui/widgets/glass_capsule.dart';
import 'package:salu/ui/widgets/settings_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A [Canvas] that only remembers what colour each shape was asked to wear.
/// The mini bar's edge meter is a `CustomPainter`, so the only honest way to
/// assert on it is to let it paint and read the colours back.
class _ColourCanvas implements Canvas {
  final List<Color> drawn = <Color>[];

  @override
  void drawRRect(RRect r, Paint paint) => drawn.add(paint.color);

  @override
  void drawRect(Rect r, Paint paint) => drawn.add(paint.color);

  @override
  void drawCircle(Offset c, double radius, Paint paint) =>
      drawn.add(paint.color);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// [MiniSeekLine]'s title-line sink. Nothing subscribes in these tests.
void _noop(String _) {}

class _TintProbe extends StatelessWidget {
  const _TintProbe();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: <Widget>[
        Text(
          'foreground',
          style: TextStyle(color: context.palette.textPrimary),
        ),
        GlassCapsule(radius: 10, child: const Text('glass')),
        ColoredBox(
          key: const ValueKey<String>('surface'),
          color: context.overlayTint(context.palette.surface),
          child: const Text('surface'),
        ),
      ],
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PlayerService.installNotifierOnlyForTesting();
  final SettingsService settings = SettingsService.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await settings.load();
  });

  test(
    'restores before first frame, clamps invalid values, defaults to 0',
    () async {
      expect(settings.overlayTransparency.value, 0);
      SharedPreferences.setMockInitialValues(<String, Object>{
        'appearance_overlay_transparency': 80,
      });
      await settings.load();
      expect(
        settings.overlayTransparency.value,
        SettingsService.maxOverlayTransparency,
      );
      SharedPreferences.setMockInitialValues(<String, Object>{
        'appearance_overlay_transparency': -20,
      });
      await settings.load();
      expect(settings.overlayTransparency.value, 0);
      SharedPreferences.setMockInitialValues(<String, Object>{
        'appearance_overlay_transparency': 'bad',
      });
      await settings.load();
      expect(settings.overlayTransparency.value, 0);
    },
  );

  test('drag applies live; release saves and restores', () async {
    await settings.setOverlayTransparency(20, persist: false);
    expect(settings.overlayTransparency.value, 20);
    expect(
      (await SharedPreferences.getInstance()).getInt(
        'appearance_overlay_transparency',
      ),
      isNull,
    );
    await settings.setOverlayTransparency(25);
    expect(
      (await SharedPreferences.getInstance()).getInt(
        'appearance_overlay_transparency',
      ),
      25,
    );
    settings.overlayTransparency.value = 0;
    await settings.load();
    expect(settings.overlayTransparency.value, 25);
    await settings.setOverlayTransparency(900);
    expect(
      settings.overlayTransparency.value,
      SettingsService.maxOverlayTransparency,
    );
    await settings.setOverlayTransparency(0);
    expect(settings.overlayTransparency.value, 0);
  });

  test('immediate reset then Undo persists the latest value', () async {
    final Future<void> reset = settings.setOverlayTransparency(0);
    final Future<void> undo = settings.setOverlayTransparency(30);
    await Future.wait(<Future<void>>[reset, undo]);
    expect(settings.overlayTransparency.value, 30);
    expect(
      (await SharedPreferences.getInstance()).getInt(
        'appearance_overlay_transparency',
      ),
      30,
    );
  });

  testWidgets('only surface tint changes in both themes, not foreground', (
    tester,
  ) async {
    await tester.pumpWidget(const SaluThemedApp(home: _TintProbe()));
    final before = tester.widget<Container>(
      find
          .ancestor(of: find.text('glass'), matching: find.byType(Container))
          .first,
    );
    expect(before.decoration, isA<BoxDecoration>());
    expect(
      (before.decoration! as BoxDecoration).color,
      AppPalette.saluDefault.glass,
    );
    await settings.setOverlayTransparency(40);
    await tester.pumpAndSettle();
    final after = tester.widget<Container>(
      find
          .ancestor(of: find.text('glass'), matching: find.byType(Container))
          .first,
    );
    expect(
      (after.decoration! as BoxDecoration).color!.a,
      closeTo(AppPalette.saluDefault.glass.a * 0.6, 0.005),
    );
    expect(
      tester.widget<Text>(find.text('foreground')).style!.color,
      AppPalette.saluDefault.textPrimary,
    );
    expect(
      Theme.of(tester.element(find.text('foreground'))).scaffoldBackgroundColor,
      AppPalette.saluDefault.background,
    );
    await settings.setThemeMode(SaluThemeMode.light);
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.text('foreground')).style!.color,
      AppPalette.light.textPrimary,
    );
    expect(
      tester
          .widget<ColoredBox>(find.byKey(const ValueKey<String>('surface')))
          .color
          .a,
      closeTo(0.6, 0.005),
    );
  });

  testWidgets('seek and volume bars tint with the surfaces, labels do not', (
    tester,
  ) async {
    await tester.pumpWidget(
      const SaluThemedApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            child: Column(
              children: <Widget>[MediaTimeline(), VolumeBar(readOnly: true)],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final AppPalette palette = Theme.of(
      tester.element(find.byType(MediaTimeline)),
    ).extension<AppPalette>()!;

    Finder paintIn(Type bar) => find.descendant(
      of: find.byType(bar),
      matching: find.byType(ColoredBox),
    );
    // Idle bars paint exactly their track (+ fill for the volume bar);
    // no hover, so no ruler ticks, playhead or chip are on screen.
    expect(find.byType(MediaTimeline), findsOneWidget);
    expect(paintIn(MediaTimeline), findsOneWidget);
    expect(paintIn(VolumeBar), findsNWidgets(2));

    // 0 % leaves both bars on their exact original colours.
    expect(
      tester.widget<ColoredBox>(paintIn(MediaTimeline)).color,
      palette.barTrack,
    );
    expect(
      tester.widget<ColoredBox>(paintIn(VolumeBar).first).color,
      palette.barTrack,
    );
    expect(
      tester.widget<ColoredBox>(paintIn(VolumeBar).last).color,
      palette.barFill,
    );

    await settings.setOverlayTransparency(40);
    await tester.pumpAndSettle();

    // The track and the fill lose exactly the set fraction of their alpha,
    // so the bars fade with the panels around them.
    expect(
      tester.widget<ColoredBox>(paintIn(MediaTimeline)).color.a,
      closeTo(palette.barTrack.a * 0.6, 0.005),
    );
    expect(
      tester.widget<ColoredBox>(paintIn(VolumeBar).first).color.a,
      closeTo(palette.barTrack.a * 0.6, 0.005),
    );
    expect(
      tester.widget<ColoredBox>(paintIn(VolumeBar).last).color.a,
      closeTo(palette.barFill.a * 0.6, 0.005),
    );

    // The values riding inside the now see-through bars stay opaque.
    for (final Text readout in tester.widgetList<Text>(
      find.text('00:00:00'),
    )) {
      expect(readout.style!.color, palette.textPrimary);
    }
    expect(
      tester.widget<Text>(find.text('100%')).style!.color,
      palette.iconIdle,
    );
  });

  testWidgets('mini bar edge meter tints its track and fill, not the head', (
    tester,
  ) async {
    await tester.pumpWidget(
      const SaluThemedApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: MiniSeekLine(onSwap: _noop),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    MiniProgressStrip strip() => tester
        .widget<CustomPaint>(
          find
              .descendant(
                of: find.byType(MiniSeekLine),
                matching: find.byType(CustomPaint),
              )
              .last,
        )
        .painter! as MiniProgressStrip;

    final AppPalette palette = Theme.of(
      tester.element(find.byType(MiniSeekLine)),
    ).extension<AppPalette>()!;

    // Let the painter run for real: the track, the fill and (while a
    // scrub is up) the head tick are the only three colours it wears.
    List<Color> paintedAt(int transparency) {
      final _ColourCanvas canvas = _ColourCanvas();
      MiniProgressStrip(
        palette: palette,
        overlay: OverlayAppearance(transparency),
        frac: 0.4,
        head: true,
      ).paint(canvas, const Size(400, 20));
      return canvas.drawn;
    }

    List<Color> solid = paintedAt(0);
    expect(
      solid,
      <Color>[palette.barTrack, palette.barFill, palette.barThumb],
    );

    // 40 %: both surfaces lose the set fraction of their alpha; the head
    // tick is a foreground and keeps its full opacity.
    List<Color> faded = paintedAt(40);
    expect(faded[0].a, closeTo(palette.barTrack.a * 0.6, 0.005));
    expect(faded[1].a, closeTo(palette.barFill.a * 0.6, 0.005));
    expect(faded[2], palette.barThumb);

    // The widget hands the painter the LIVE rule, so the meter follows the
    // setting — and the repaint gate compares by VALUE, so it repaints
    // exactly when the percentage moves, not on every theme rebuild.
    expect(strip().overlay, const OverlayAppearance(0));
    expect(
      OverlayAppearance(40) == const OverlayAppearance(40),
      isTrue,
      reason: 'the repaint gate must compare by value, not identity',
    );
    await settings.setOverlayTransparency(40);
    await tester.pumpAndSettle();
    expect(strip().overlay, const OverlayAppearance(40));
  });

  testWidgets('subtitle-delay bar tints, its detent and value do not', (
    tester,
  ) async {
    addTearDown(PanelService.instance.closeAll);
    final PlayerService player = PlayerService.instance;
    addTearDown(() {
      player.currentPath.value = null;
      player.trackSurface.value = TrackSurface.empty;
      player.subDelay.value = 0;
    });
    player.currentPath.value = 'C:/movie.mkv';
    player.trackSurface.value = const TrackSurface(
      embeddedSubs: <MpvTrack>[
        MpvTrack(id: '1', type: 'sub', title: 'Subtitle 1', selected: true),
      ],
    );
    // Off the detent, so the fill is on screen and can be checked too.
    player.subDelay.value = 2.5;

    await tester.pumpWidget(
      const SaluThemedApp(
        home: Scaffold(body: Stack(children: <Widget>[TrackPanel()])),
      ),
    );
    PanelService.instance.trackPanelOpen.value = true;
    await tester.pumpAndSettle();

    // The sync row only exists once a subtitle is actually selected.
    expect(find.text('+2.5 s'), findsOneWidget);
    final Finder bar = find.ancestor(
      of: find.text('+2.5 s'),
      matching: find.byWidgetPredicate(
        (Widget w) =>
            w is ClipRRect && w.borderRadius == BorderRadius.circular(4),
      ),
    );
    final Finder paintInBar = find.descendant(
      of: bar,
      matching: find.byType(ColoredBox),
    );
    // track, fill, centre detent.
    expect(paintInBar, findsNWidgets(3));

    final AppPalette palette = Theme.of(
      tester.element(find.text('+2.5 s')),
    ).extension<AppPalette>()!;
    final Color detent = palette.resolve(
      const Color(0x40FFFFFF),
      const Color(0x40242428),
    );
    List<Color> colours() => tester
        .widgetList<ColoredBox>(paintInBar)
        .map((ColoredBox b) => b.color)
        .toList();

    List<Color> solid = colours();
    expect(solid[0], palette.barTrack);
    expect(solid[1], palette.barFill);
    expect(solid[2], detent);

    await settings.setOverlayTransparency(40);
    await tester.pumpAndSettle();

    List<Color> faded = colours();
    expect(faded[0].a, closeTo(palette.barTrack.a * 0.6, 0.005));
    expect(faded[1].a, closeTo(palette.barFill.a * 0.6, 0.005));
    expect(faded[2], detent, reason: 'the detent marks where 0 lives');
    expect(
      tester.widget<Text>(find.text('+2.5 s')).style!.color,
      palette.iconIdle,
    );
  });

  testWidgets('Appearance control, group reset/Undo and master reset', (
    tester,
  ) async {
    addTearDown(OsdController.instance.dismiss);
    await tester.pumpWidget(
      const SaluThemedApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 700,
              height: 700,
              child: SettingsDialog(initialTab: SettingsTab.appearance),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('0%'), findsOneWidget);
    expect(
      find.byTooltip('0% original · higher is more see-through'),
      findsOneWidget,
    );
    final slider = find.byType(Slider);
    await tester.drag(slider, const Offset(65, 0));
    await tester.pumpAndSettle();
    expect(settings.overlayTransparency.value, greaterThan(0));
    expect(find.text('${settings.overlayTransparency.value}%'), findsOneWidget);
    final previous = settings.overlayTransparency.value;
    await tester.tap(find.byTooltip('Reset Overlay transparency to defaults'));
    await tester.pumpAndSettle();
    expect(settings.overlayTransparency.value, 0);
    (OsdController.instance.current.value! as OsdUndoCard).onUndo();
    await tester.pumpAndSettle();
    expect(settings.overlayTransparency.value, previous);
    await tester.tap(find.byTooltip('Reset all settings'));
    await tester.pumpAndSettle();
    expect(settings.overlayTransparency.value, 0);
    (OsdController.instance.current.value! as OsdUndoCard).onUndo();
    await tester.pumpAndSettle();
    expect(settings.overlayTransparency.value, previous);
  });
}
