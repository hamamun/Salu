import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/channel_grouping.dart';
import 'package:salu/core/channel_view_service.dart';
import 'package:salu/core/panel_service.dart';
import 'package:salu/core/player_service.dart';
import 'package:salu/core/queue_service.dart';
import 'package:salu/core/shortcuts/shortcut_registry.dart';
import 'package:salu/core/ui_lock.dart';
import 'package:salu/theme/app_theme.dart';
import 'package:salu/ui/panels/playlist_panel.dart';
import 'package:salu/ui/widgets/alt_peek.dart';
import 'package:salu/ui/widgets/salu_icon_button.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PlayerService.installNotifierOnlyForTesting();

  final QueueService queue = QueueService.instance;
  final ChannelViewService view = ChannelViewService.instance;
  final PlayerService player = PlayerService.instance;

  final List<QueueItem> channels = <QueueItem>[
    const QueueItem('http://h/1', name: 'Alpha', group: 'News', country: 'BD'),
    const QueueItem('http://h/2', name: 'Beta', group: 'Sports', country: 'US'),
    const QueueItem('http://h/3', name: 'Gamma', group: 'News', country: 'BD'),
    const QueueItem('http://h/4', name: 'Delta', group: 'Sports', country: 'US'),
  ];

  setUp(() {
    queue.clear();
    view.reset();
    player.repeatMode.value = RepeatMode.off;
    player.shuffleOn.value = false;
    AltPeek.instance.debugSetVisible(false);
    PanelService.instance.closePlaylist();
    while (ChromeLock.instance.isLocked) {
      ChromeLock.instance.release();
    }
  });

  test('applyMode does not touch queue order or the playing index', () {
    queue.setItems(channels, 1);
    final List<String> before =
        queue.items.value.map((QueueItem item) => item.label).toList();
    final String revision = queue.contentRevision;

    view.applyMode(
      ChannelGroupMode.category,
      items: queue.items.value,
      playingIndex: queue.index.value,
    );

    expect(view.groupMode.value, ChannelGroupMode.category);
    expect(
      view.openGroup.value,
      ChannelGrouping.keyFor(channels, 1, ChannelGroupMode.category),
    );
    expect(queue.index.value, 1);
    expect(
      queue.items.value.map((QueueItem item) => item.label).toList(),
      before,
    );
    expect(queue.contentRevision, revision);
    // Sports is not the queue head. Grouped Previous parks inside the group.
    expect(player.hasPreviousItem, isFalse);
    expect(player.hasNextItem, isTrue);
  });

  test('grouped stepping parks at the group edge with the panel closed', () {
    queue.setItems(channels, 2);
    view.applyMode(
      ChannelGroupMode.category,
      items: queue.items.value,
      playingIndex: 2,
    );
    expect(player.hasNextItem, isFalse);
    expect(player.hasPreviousItem, isTrue);
    view.searching.value = true;
    expect(player.hasNextItem, isTrue);
  });

  testWidgets('local playlist header controls answer Alt-Peek while locked',
      (WidgetTester tester) async {
    queue.setItems(
      const <QueueItem>[QueueItem.local('/music/one.mp3')],
      0,
    );
    PanelService.instance.playlistOpen.value = true;
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: const Scaffold(
        body: Stack(children: <Widget>[PlaylistPanel()]),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 250));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
    });

    // The open playlist holds ChromeLock. The panel's own controls must
    // bypass that lock so the key tip is not hidden along with other UI.
    expect(ChromeLock.instance.isLocked, isTrue);
    final TestGesture mouse =
        await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    final Finder repeat = find.byTooltip('Repeat off');
    await mouse.moveTo(tester.getCenter(repeat));
    await tester.pump();
    AltPeek.instance.debugSetVisible(true);
    await tester.pumpAndSettle();
    expect(find.text('R'), findsOneWidget);
    expect(find.text('Repeat off'), findsNothing);

    await mouse.moveTo(tester.getCenter(find.byTooltip('Shuffle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(
      find.text('Shift+S · Alt+S · Ctrl+Shift+S'),
      findsOneWidget,
    );
    expect(find.text('Shuffle'), findsNothing);

    AltPeek.instance.debugSetVisible(false);
    await tester.pumpAndSettle();
    await mouse.removePointer();
  });

  testWidgets('M3U playlist header controls answer Alt-Peek while locked',
      (WidgetTester tester) async {
    queue.setItems(channels, 0);
    PanelService.instance.playlistOpen.value = true;
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: const Scaffold(
        body: Stack(children: <Widget>[PlaylistPanel()]),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 250));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
    });

    expect(ChromeLock.instance.isLocked, isTrue);
    final TestGesture mouse =
        await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byTooltip('Group by')));
    await tester.pump();
    AltPeek.instance.debugSetVisible(true);
    await tester.pumpAndSettle();
    expect(find.text('Ctrl+G'), findsOneWidget);
    expect(find.text('Group by'), findsNothing);

    await mouse.moveTo(tester.getCenter(find.byTooltip('Favourites')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('Ctrl+D'), findsOneWidget);
    expect(find.text('Favourites'), findsNothing);

    await mouse.moveTo(tester.getCenter(find.byType(TextField)));
    await tester.pumpAndSettle();
    expect(find.text('Ctrl+F'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'sports');
    await tester.pump();
    final Finder clearSearch = find.byWidgetPredicate(
      (Widget widget) =>
          widget is AltPeekAnchor && widget.scope == ShortcutScope.dialog,
    );
    expect(clearSearch, findsOneWidget);
    expect(find.text('Ctrl+F'), findsOneWidget);
    expect(find.text('Esc'), findsNothing);

    await mouse.moveTo(tester.getCenter(clearSearch));
    await tester.pumpAndSettle();
    expect(find.text('Esc'), findsOneWidget);
    expect(find.text('Ctrl+F'), findsNothing);

    AltPeek.instance.debugSetVisible(false);
    await tester.pumpAndSettle();
    await mouse.removePointer();
  });

  testWidgets('a remote mode change updates the open and closed panel once',
      (WidgetTester tester) async {
    queue.setItems(channels, 0);
    PanelService.instance.playlistOpen.value = true;
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
    });
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: const Scaffold(
        body: Stack(children: <Widget>[PlaylistPanel()]),
      ),
    ));
    await tester.pump();

    ChannelGrouping.descriptorBuildsForTest = 0;
    view.applyMode(
      ChannelGroupMode.category,
      items: queue.items.value,
      playingIndex: 0,
    );
    await tester.pump();

    expect(ChannelGrouping.descriptorBuildsForTest, 1);
    expect(find.text('News'), findsWidgets);
    expect(find.text('Sports'), findsWidgets);
    expect(find.text('Alpha'), findsWidgets);

    PanelService.instance.closePlaylist();
    await tester.pump();
    ChannelGrouping.descriptorBuildsForTest = 0;
    view.applyMode(
      ChannelGroupMode.country,
      items: queue.items.value,
      playingIndex: 0,
    );
    await tester.pump();
    expect(ChannelGrouping.descriptorBuildsForTest, 1);
    expect(find.text('BD'), findsWidgets);
    expect(find.text('US'), findsWidgets);

    PanelService.instance.playlistOpen.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('BD'), findsWidgets);

    await tester.ensureVisible(find.byTooltip('Group by'));
    await tester.tap(find.byTooltip('Group by'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    view.applyMode(
      ChannelGroupMode.category,
      items: queue.items.value,
      playingIndex: 0,
    );
    await tester.pump();
    expect(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is SaluIconButton &&
            widget.tooltip == 'Category' &&
            widget.active,
      ),
      findsOneWidget,
    );

    // While the pill owns focus, 3 selects Country (Flat=1, Category=2,
    // Country=3, Language=4) without colliding with Player seek digits.
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.pump();
    expect(view.groupMode.value, ChannelGroupMode.country);
    expect(PanelService.instance.groupPillOpen.value, isFalse);
  });
}
