import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/info_collector.dart';
import 'package:salu/core/info_controller.dart';
import 'package:salu/core/panel_service.dart';
import 'package:salu/core/player_service.dart';
import 'package:salu/core/ui_lock.dart';
import 'package:salu/theme/app_theme.dart';
import 'package:salu/ui/panels/info_panel.dart';
import 'package:salu/ui/widgets/salu_marks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PlayerService.installNotifierOnlyForTesting();

  testWidgets(
    'presence rules: local audio, video, stream and unknown duration',
    (tester) async {
      Future<void> render(
        InfoSnapshot snapshot, {
        Duration duration = Duration.zero,
      }) =>
          tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark,
              home: Scaffold(
                body: SizedBox(
                  width: 322,
                  child: InfoRows(
                    snapshot: snapshot,
                    position: const Duration(seconds: 5),
                    duration: duration,
                  ),
                ),
              ),
            ),
          );
      const Map<String, List<InfoRow>> identity = <String, List<InfoRow>>{
        'Identity': <InfoRow>[InfoRow('Title', 'Song')],
        'Sound': <InfoRow>[InfoRow('Codec', 'flac')],
      };
      await render(const InfoSnapshot(identity, local: true));
      expect(find.text('IDENTITY'), findsOneWidget);
      expect(find.text('SOUND'), findsOneWidget);
      expect(find.text('CLOCK & FILE'), findsOneWidget);
      expect(find.text('PICTURE'), findsNothing);
      expect(find.text('STREAM'), findsNothing);
      expect(find.text('SALU'), findsNothing);
      expect(find.text('Position'), findsOneWidget);
      expect(find.text('Duration'), findsNothing);
      expect(find.text('Remaining'), findsNothing);
      await render(
        const InfoSnapshot(<String, List<InfoRow>>{
          ...identity,
          'Picture': <InfoRow>[InfoRow('Resolution', '1920 × 1080')],
        }, local: true),
        duration: const Duration(seconds: 20),
      );
      expect(find.text('PICTURE'), findsOneWidget);
      expect(find.text('00:15'), findsOneWidget);
      await render(
        const InfoSnapshot(<String, List<InfoRow>>{
          ...identity,
          'Stream': <InfoRow>[InfoRow('Provider', 'example.org')],
        }),
      );
      expect(find.text('STREAM'), findsOneWidget);
      expect(find.text('CLOCK & FILE'), findsNothing);
      expect(find.text('Position'), findsNothing);
      expect(find.text('N/A'), findsNothing);
    },
  );

  for (final String path in <String>[
    'Escape',
    'outside',
    'close mark',
    'secondary',
    'dispose',
  ]) {
    testWidgets('Info $path dismisses without transport and releases chrome', (
      tester,
    ) async {
      final PanelService panels = PanelService.instance;
      panels.closeAll();
      final InfoController info = InfoController(
        open: panels.infoOpen,
        changes: <Listenable>[],
        context: () => const InfoContext(path: 'C:/song.mp3'),
        collector: InfoCollector(
          read: (key) async => key == 'metadata/list/count' ? '0' : '',
          fileSize: (_) async => null,
        ),
      );
      int transport = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => transport++,
                  child: const SizedBox.expand(),
                ),
                InfoPanel(controller: info),
              ],
            ),
          ),
        ),
      );
      panels.openInfo();
      await tester.pumpAndSettle();
      expect(ChromeLock.instance.isLocked, isTrue);
      switch (path) {
        case 'Escape':
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        case 'outside':
          await tester.tapAt(const Offset(700, 400));
        case 'close mark':
          await tester.tap(find.byType(CloseMark));
        case 'secondary':
          await tester.tapAt(const Offset(100, 400), buttons: kSecondaryButton);
        case 'dispose':
          await tester.pumpWidget(const SizedBox());
      }
      await tester.pumpAndSettle();
      expect(ChromeLock.instance.isLocked, isFalse);
      expect(transport, 0);
      if (path != 'dispose') expect(panels.infoOpen.value, isFalse);
      await tester.pumpWidget(const SizedBox());
      info.dispose();
      panels.closeAll();
    });
  }
}
