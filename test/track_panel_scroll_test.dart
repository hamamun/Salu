import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/panel_service.dart';
import 'package:salu/core/player_service.dart';
import 'package:salu/ui/panels/track_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PlayerService.installNotifierOnlyForTesting();
  final PlayerService player = PlayerService.instance;
  final PanelService panels = PanelService.instance;

  TrackSurface subtitles(int selected, {int count = 35, bool local = false}) {
    final List<MpvTrack> tracks = List<MpvTrack>.generate(
      count,
      (int i) => MpvTrack(
        id: '${i + 1}',
        type: 'sub',
        title: 'Subtitle ${i + 1}',
        selected: i + 1 == selected,
        external: local,
      ),
    );
    return local
        ? TrackSurface(localSubs: tracks)
        : TrackSurface(embeddedSubs: tracks);
  }

  Future<void> openPanel(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Stack(children: <Widget>[TrackPanel()])),
    ));
    panels.trackPanelOpen.value = true;
    await tester.pumpAndSettle();
  }

  ScrollController controller(WidgetTester tester) =>
      tester.widget<ListView>(find.byType(ListView)).controller!;

  void expectVisible(WidgetTester tester, String label) {
    final Rect viewport = tester.getRect(find.byType(ListView));
    final Finder text = find.text(label);
    expect(text, findsOneWidget);
    final Rect rowText = tester.getRect(text);
    expect(rowText.top, greaterThanOrEqualTo(viewport.top));
    expect(rowText.bottom, lessThanOrEqualTo(viewport.bottom));
    expect(text.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  }

  setUp(() {
    panels.closeAll();
    player.currentPath.value = 'C:/movie.mkv';
    player.trackSurface.value = TrackSurface.empty;
  });

  tearDown(() {
    panels.closeAll();
    player.trackSurface.value = TrackSurface.empty;
  });

  testWidgets('opening and reopening reveals subtitle 15 without fighting scroll',
      (WidgetTester tester) async {
    player.trackSurface.value = subtitles(15);
    await openPanel(tester);
    expectVisible(tester, 'Subtitle 15');
    expect(controller(tester).position.viewportDimension, 5 * 28);

    // Browsing elsewhere is allowed, including across repeated mpv snapshots.
    controller(tester).jumpTo(0);
    player.trackSurface.value = subtitles(15);
    await tester.pumpAndSettle();
    expect(controller(tester).offset, 0);

    panels.closeTrackPanel();
    await tester.pumpAndSettle();
    panels.trackPanelOpen.value = true;
    await tester.pumpAndSettle();
    expectVisible(tester, 'Subtitle 15');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('remote selection snapshots reveal last, first, and Off rows',
      (WidgetTester tester) async {
    player.trackSurface.value = subtitles(15);
    await openPanel(tester);
    // Remote selection refreshes this same mpv trackSurface notifier.
    player.trackSurface.value = subtitles(35);
    await tester.pumpAndSettle();
    expectVisible(tester, 'Subtitle 35');
    player.trackSurface.value = subtitles(1);
    await tester.pumpAndSettle();
    expectVisible(tester, 'Subtitle 1');
    player.trackSurface.value = subtitles(0);
    await tester.pumpAndSettle();
    expectVisible(tester, 'Off');
    expect(controller(tester).offset, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('selection changed while closed is visible on next opening',
      (WidgetTester tester) async {
    player.trackSurface.value = subtitles(15);
    await openPanel(tester);
    panels.closeTrackPanel();
    await tester.pumpAndSettle();
    player.trackSurface.value = subtitles(30);
    await tester.pumpAndSettle();
    panels.trackPanelOpen.value = true;
    await tester.pumpAndSettle();
    expectVisible(tester, 'Subtitle 30');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('short lists and replacement local tracks remain safe',
      (WidgetTester tester) async {
    player.trackSurface.value = subtitles(35);
    await openPanel(tester);
    player.trackSurface.value = subtitles(2, count: 3);
    await tester.pumpAndSettle();
    expect(find.byType(ListView), findsNothing);
    expect(find.text('Subtitle 2').hitTestable(), findsOneWidget);
    player.trackSurface.value = subtitles(20, local: true);
    await tester.pumpAndSettle();
    expectVisible(tester, 'Subtitle 20');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
