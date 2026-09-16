import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/window_state_service.dart';
import 'package:salu/ui/mini/mini_feedback.dart';
import 'package:salu/ui/mini/mini_metrics.dart';
import 'package:salu/ui/osd/osd_controller.dart';

/// The mini bar's own guarantees (mini.md — FINAL v5).
///
/// Everything here is deliberately pure: the metrics arithmetic, the §6
/// feedback copy and the §2 geometry maths — the three pieces that decide
/// what the bar says and where it lands. Nothing touches a window, a
/// player or a plugin, so the suite runs anywhere `flutter test` runs,
/// even on a machine with no media and no second monitor.
///
/// An edit that moves a gap, renames a line or breaks the off-screen clamp
/// has to argue with this file first.
void main() {
  group('MiniMetrics — the row closes at 488 (§2 · §3 · §11 v5)', () {
    test('the fixed parts plus the title add up to the window width', () {
      // §3: the title keeps its full ~141 px — it is the one part the v5
      // trim never touched, and the only width the constants cannot state
      // (the title is the row's Expanded child, not a number).
      const double title = 141;

      const double row = MiniMetrics.outerPadding * 2 +
          MiniMetrics.saluBox +
          MiniMetrics.iconGap +
          (MiniMetrics.hitWidth * 2 + MiniMetrics.inGroupGap) * 3 +
          MiniMetrics.betweenGroupsGap * 2 +
          MiniMetrics.beforeSoundGap +
          MiniMetrics.hitWidth +
          MiniMetrics.inGroupGap +
          MiniMetrics.wheelBox +
          MiniMetrics.titleLeftMargin +
          title +
          MiniMetrics.titleRightMargin +
          MiniMetrics.hitWidth +
          MiniMetrics.restoreTrailingGap;

      expect(row, MiniMetrics.windowWidth);
      expect(row, 488);
    });

    test('the v5 numbers are pinned', () {
      expect(MiniMetrics.windowWidth, 488);
      expect(MiniMetrics.windowHeight, 32);
      expect(MiniMetrics.cornerRadius, 8);

      expect(MiniMetrics.hitWidth, 26);
      expect(MiniMetrics.hitHeight, 30);
      expect(MiniMetrics.markSize, 18);

      expect(MiniMetrics.inGroupGap, 5);
      expect(MiniMetrics.betweenGroupsGap, 11);
      expect(MiniMetrics.beforeSoundGap, 20);

      expect(MiniMetrics.outerPadding, 4);
      expect(MiniMetrics.saluBox, 25);
      expect(MiniMetrics.saluGlyph, 19);
      expect(MiniMetrics.iconGap, 8);
      expect(MiniMetrics.titleLeftMargin, 8);
      expect(MiniMetrics.titleRightMargin, 4);
      expect(MiniMetrics.restoreTrailingGap, 2);

      expect(MiniMetrics.wheelBox, 22);
      expect(MiniMetrics.wheelDial, 20);

      expect(MiniMetrics.seekHeight, 2);
      expect(MiniMetrics.seekTop, 2);
      expect(MiniMetrics.seekInset, 7);
      expect(MiniMetrics.seekHeadSize, 6);
    });

    test('the trim\'s hard floors stand (§11 v5)', () {
      // "Shrink the space, never the glyphs" — the two floors the change
      // log names are properties, not tastes.
      expect(MiniMetrics.hitWidth >= 26, isTrue);
      expect(MiniMetrics.inGroupGap >= 5, isTrue);
      // §10: the seek line's invisible hit zone is at least 8 px tall.
      expect(MiniMetrics.seekHitHeight >= 8, isTrue);
      // §6: the swap holds for about 1.2 s.
      expect(MiniMetrics.swapHold, const Duration(milliseconds: 1200));
    });

    test('the window contract and the row agree on one size', () {
      expect(MiniMetrics.windowSize.width, MiniMetrics.windowWidth);
      expect(MiniMetrics.windowSize.height, MiniMetrics.windowHeight);
      expect(WindowStateService.miniWindowSize, MiniMetrics.windowSize);
    });
  });

  group('miniSwapText — the §6 lines, and only those', () {
    test('volume speaks through the deck\'s card', () {
      expect(
        miniSwapText(
          const OsdVolumeCard(muted: false),
          volume: 45.0,
          muted: false,
        ),
        'Volume 45 %',
      );
      // The line rounds the way the full window's readout does.
      expect(
        miniSwapText(
          const OsdVolumeCard(muted: false),
          volume: 44.6,
          muted: false,
        ),
        'Volume 45 %',
      );
      expect(
        miniSwapText(
          const OsdVolumeCard(muted: true),
          volume: 45.0,
          muted: true,
        ),
        'Muted',
      );
      // One spelling for the wheel and the keys both.
      expect(volumeSwapText(0.0, false), 'Volume 0 %');
      expect(volumeSwapText(100.0, true), 'Muted');
    });

    test('a seek step becomes sign · unit · clock', () {
      // The deck writes `+15s  01:12:34`; §6 asks for `+15 s · 01:12:34`.
      expect(
        miniSwapText(
          const OsdTransportCard(
            mark: OsdMark.seekForward,
            text: '+15s  01:12:34',
          ),
          volume: 50.0,
          muted: false,
        ),
        '+15 s · 01:12:34',
      );
      expect(
        miniSwapText(
          const OsdTransportCard(mark: OsdMark.seekBack, text: '-3s  00:00:20'),
          volume: 50.0,
          muted: false,
        ),
        '-3 s · 00:00:20',
      );
      // An unexpected shape is passed through, never swallowed.
      expect(
        miniSwapText(
          const OsdTransportCard(mark: OsdMark.seekBack, text: 'not a step'),
          volume: 50.0,
          muted: false,
        ),
        'not a step',
      );
    });

    test('an item change speaks the deck\'s own label', () {
      // The channel's display name in channel mode, the file's name
      // otherwise — the deck already chose; the bar must not re-spell it.
      expect(
        miniSwapText(
          const OsdTransportCard(mark: OsdMark.next, text: 'Channel One'),
          volume: 50.0,
          muted: false,
        ),
        'Channel One',
      );
      expect(
        miniSwapText(
          const OsdTransportCard(mark: OsdMark.previous, text: 'Track Two'),
          volume: 50.0,
          muted: false,
        ),
        'Track Two',
      );
    });

    test('play/pause has no line of its own', () {
      // The mark's own `>` ↔ `II` swap is the feedback there.
      expect(
        miniSwapText(
          const OsdTransportCard(mark: OsdMark.play, text: 'ignored'),
          volume: 50.0,
          muted: false,
        ),
        isNull,
      );
      expect(
        miniSwapText(
          const OsdTransportCard(mark: OsdMark.pause, text: 'ignored'),
          volume: 50.0,
          muted: false,
        ),
        isNull,
      );
    });

    test('the subtitle offset stays spoken while the bar has focus', () {
      expect(
        miniSwapText(
          const OsdSubDelayCard(delay: 0.4),
          volume: 50.0,
          muted: false,
        ),
        'sub +0.4 s',
      );
      expect(
        miniSwapText(
          const OsdSubDelayCard(delay: -1.0),
          volume: 50.0,
          muted: false,
        ),
        'sub -1.0 s',
      );
    });

    test('cards with no place in a 32 px bar never become a line', () {
      // The resume toast's card belongs to a canvas that does not exist
      // here; §6 gives the bar no sentence for it.
      expect(
        miniSwapText(
          const OsdResumeCard(position: Duration.zero),
          volume: 50.0,
          muted: false,
        ),
        isNull,
      );
      expect(
        miniSwapText(
          const OsdTuneCard(part: 'Audio', value: 'Pop'),
          volume: 50.0,
          muted: false,
        ),
        isNull,
      );
    });
  });

  group('clampMiniPoint — the bar stays in reach (§2)', () {
    const ui.Size bar = ui.Size(488, 32);

    test('an empty display list leaves the point alone', () {
      // A failed screen query must be a no-op, never a wrong move.
      expect(
        WindowStateService.clampMiniPoint(
          const ui.Offset(10, 10),
          boxes: const <ui.Rect>[],
        ),
        const ui.Offset(10, 10),
      );
    });

    test('a point past the bottom-right corner is pulled back', () {
      const ui.Rect screen = ui.Rect.fromLTWH(0, 0, 1920, 1080);
      expect(
        WindowStateService.clampMiniPoint(
          const ui.Offset(1900, 1070),
          boxes: const <ui.Rect>[screen],
        ),
        const ui.Offset(1432, 1048), // 1920 − 488, 1080 − 32
      );
    });

    test('a point above or left of the screen lands on its corner', () {
      const ui.Rect screen = ui.Rect.fromLTWH(0, 0, 1920, 1080);
      expect(
        WindowStateService.clampMiniPoint(
          const ui.Offset(-40, -12),
          boxes: const <ui.Rect>[screen],
        ),
        ui.Offset.zero,
      );
    });

    test('a display smaller than the bar pins the bar to its corner', () {
      // max(left, right − w) is what keeps the maths from asking for a
      // negative range here.
      const ui.Rect tiny = ui.Rect.fromLTWH(0, 0, 300, 20);
      expect(
        WindowStateService.clampMiniPoint(
          const ui.Offset(250, 10),
          boxes: const <ui.Rect>[tiny],
        ),
        ui.Offset.zero,
      );
    });

    test('a monitor left of the primary keeps its own coordinates', () {
      const ui.Rect primary = ui.Rect.fromLTWH(0, 0, 1920, 1080);
      const ui.Rect left = ui.Rect.fromLTWH(-1280, 0, 1280, 1024);

      // Parked on the left monitor: nearest-centre keeps it there instead
      // of dragging it home to the primary.
      expect(
        WindowStateService.clampMiniPoint(
          const ui.Offset(-700, 300),
          boxes: const <ui.Rect>[primary, left],
        ),
        const ui.Offset(-700, 300),
      );

      // Hanging over that monitor's right edge — the wall is −488, not the
      // primary's left edge at 0.
      expect(
        WindowStateService.clampMiniPoint(
          const ui.Offset(-200, 300),
          boxes: const <ui.Rect>[primary, left],
        ),
        const ui.Offset(-488, 300),
      );
    });

    test('a narrower window is clamped inside the same screen', () {
      const ui.Rect screen = ui.Rect.fromLTWH(0, 0, 1920, 1080);
      expect(
        WindowStateService.clampMiniPoint(
          const ui.Offset(1900, 10),
          boxes: const <ui.Rect>[screen],
          windowSize: bar,
        ),
        const ui.Offset(1432, 10),
      );
    });
  });

  group('FullWindowGeometry — what must come back exactly (§4)', () {
    test('a round trip keeps every field', () {
      const FullWindowGeometry geometry = FullWindowGeometry(
        position: ui.Offset(120, 64),
        size: ui.Size(1280, 720),
        maximized: true,
      );
      final FullWindowGeometry? decoded =
          FullWindowGeometry.decode(geometry.encode());
      expect(decoded, isNotNull);
      final FullWindowGeometry back = decoded!;
      expect(back.position, const ui.Offset(120, 64));
      expect(back.size, const ui.Size(1280, 720));
      expect(back.maximized, isTrue);
      expect(back.fullscreen, isFalse);
    });

    test('a fullscreen memory survives the trip too', () {
      const FullWindowGeometry geometry = FullWindowGeometry(
        position: ui.Offset.zero,
        size: ui.Size(1920, 1080),
        fullscreen: true,
      );
      final FullWindowGeometry? decoded =
          FullWindowGeometry.decode(geometry.encode());
      expect(decoded, isNotNull);
      final FullWindowGeometry back = decoded!;
      expect(back.fullscreen, isTrue);
      expect(back.maximized, isFalse);
    });

    test('unreadable memory reads as no memory', () {
      expect(FullWindowGeometry.decode(null), isNull);
      expect(FullWindowGeometry.decode('not json'), isNull);
      expect(FullWindowGeometry.decode('{"x":1,"y":2}'), isNull);
      expect(FullWindowGeometry.decode('{"x":1,"y":2,"w":0,"h":720}'), isNull);
    });

    test('the mini point\'s own shape', () {
      expect(
        WindowStateService.encodePoint(const ui.Offset(-1280, 12)),
        '{"x":-1280.0,"y":12.0}',
      );
    });
  });
}
