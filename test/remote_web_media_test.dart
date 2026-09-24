import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/remote/remote_web_media_bridge.dart';

/// The web-media bridge's units + element pick (pc_part.md A1/A2 · remote.md
/// §17.4/§17.11): the wire unit is milliseconds and integer percent, not
/// JavaScript's seconds and 0–1; `NaN`/`Infinity` become `0` +
/// `seekable:false`; a write target clamps instead of being rejected; and the
/// find script prefers a playing, audible, visible element over a larger
/// hidden one while ignoring sub-2-second ident bumpers and zero-box clips.
void main() {
  group('units flow through the generated scripts (A1)', () {
    test('the read script converts seconds to ms and volume to percent', () {
      final String read = RemoteWebMediaScripts.read();
      expect(read, contains('position:Math.round(pos * 1000)'));
      expect(read, contains('duration:Math.round(dur * 1000)'));
      expect(read, contains('volume:Math.round(vol * 100)'));
      expect(read, contains('unit:"ms"'));
      expect(read, contains('volumeUnit:"percent"'));
    });

    test('the read script sanitizes non-finite duration to 0 + unseekable',
        () {
      final String read = RemoteWebMediaScripts.read();
      expect(
        read,
        contains(
            'seekable:!(isFinite(dur) && dur > 0) ? false : true'),
      );
    });

    test('an absolute seek converts to seconds at the edge', () {
      final String seek = RemoteWebMediaScripts.seek(to: 60000);
      // 60000 ms → 60 s inside the script, never millis past the duration.
      expect(seek, contains('(60.0)'));
    });

    test('a delta seek is relative to the live page clock', () {
      final String seek = RemoteWebMediaScripts.seek(delta: -10000);
      expect(seek, contains('el.currentTime + (-10.0)'));
    });

    test('a write target clamps, never rejects', () {
      final String seek = RemoteWebMediaScripts.seek(to: 999999999);
      expect(seek, contains('Math.max(0, Math.min(next, max))'));
    });

    test('volume writes percent / 100', () {
      final String script = RemoteWebMediaScripts.volume(10);
      expect(script, contains('/ 100'));
      expect(script, contains('Math.max(0, Math.min(1'));
      expect(script, contains('(10.0) / 100'));
    });
  });

  group('the result parser defends the wire (A1.1)', () {
    test('a non-finite number becomes 0, not an exception', () {
      final RemoteWebMediaResult result = RemoteWebMediaResult.fromScript(
        <String, Object?>{
          'found': true,
          'position': double.nan,
          'duration': double.infinity,
          'volume': 100,
          'seekable': true,
        },
      );
      expect(result.position, 0);
      expect(result.duration, 0);
      expect(result.volume, 100);
    });

    test('a full reply round-trips the shop shape', () {
      final RemoteWebMediaResult result = RemoteWebMediaResult.fromScript(
        <String, Object?>{
          'found': true,
          'playing': false,
          'position': 754000,
          'duration': 2712000,
          'volume': 100,
          'muted': false,
          'canFull': true,
          'seekable': true,
          'unit': 'ms',
          'volumeUnit': 'percent',
        },
      );
      expect(result.toJson(), <String, Object?>{
        'found': true,
        'playing': false,
        'position': 754000,
        'duration': 2712000,
        'volume': 100,
        'muted': false,
        'canFull': true,
        'seekable': true,
        // §17.14.1 (2026-09-24): the element's fullscreen state NOW.
        'fullscreen': false,
        'unit': 'ms',
        'volumeUnit': 'percent',
      });
    });

    test('a volume above the 0–1 old dialect clamps to 100 anyway', () {
      // A page that already answered a percent-dialect read must never be
      // re-divided: the parser clamps, it never re-scales (the script is the
      // one place the conversion happens).
      final RemoteWebMediaResult result = RemoteWebMediaResult.fromScript(
        <String, Object?>{'found': true, 'volume': 100000},
      );
      expect(result.volume, 100);
    });

    test('a non-map answer is the honest not-found shape', () {
      final RemoteWebMediaResult result =
          RemoteWebMediaResult.fromScript(<String, Object?>{});
      expect(result.found, isFalse);
      expect(result.toJson()['found'], isFalse);
    });
  });

  group('the element pick (A2)', () {
    test('a playing visible element is preferred over a larger hidden one', () {
      // The find body scores visible-programme elements first: a playing
      // one carries a `bestPaused = false` marker, which the mirror rejects
      // for any larger-but-hidden element by design.
      final String body = RemoteWebMediaScripts.findBody;
      expect(body, contains('if (!el.paused)'));
      expect(body, contains('if (!visible) return;'));
      expect(body, contains('if (dur > 0 && dur < 2) return;'));
      expect(body, contains('getComputedStyle(el).display !== \'none\''));
    });

    test('the find script is a top-document only search', () {
      expect(RemoteWebMediaScripts.find,
          contains("document.querySelectorAll('video, audio')"));
    });

    test('the read script describes the winner for the PC log (A2.5)', () {
      final String read = RemoteWebMediaScripts.read();
      expect(read, contains('el:desc'));
      expect(read, contains('tag: best.tagName.toLowerCase()'));
      expect(read, contains('box: Math.round(r.width)'));
    });
  });

  group('a log one-liner for the el description (A2.5)', () {
    test('maps a described element to a single line', () {
      final String line = remoteWebMediaElLog(<String, Object?>{
        'el': <String, Object?>{
          'tag': 'video',
          'box': '1280x720',
          'duration': 2712.0,
          'paused': false,
        },
      });
      expect(line, ' (tag=video box=1280x720 duration=2712.0 paused=false)');
    });

    test('stays empty when there is no description (never crashes the log)',
        () {
      expect(remoteWebMediaElLog(<String, Object?>{'found': true}), '');
      expect(remoteWebMediaElLog(<String, Object?>{'el': 'video'}), '');
    });
  });
}
