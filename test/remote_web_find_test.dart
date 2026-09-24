import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/remote/remote_web_media_bridge.dart';

/// The element pick's acceptance (pc_part.md A2 · remote.md §17.11): the
/// find script refuses to nominate an element that cannot be the programme —
/// a hidden clip, a zero box, a sub-2-second bumper — and stays a top-only
/// search so a cross-origin iframe answers `found:false` rather than a guess.
void main() {
  group('the find script (A2)', () {
    test('a playing, audible, visible element outranks everything', () {
      expect(RemoteWebMediaScripts.findBody, contains('if (!el.paused)'));
      expect(RemoteWebMediaScripts.findBody, contains('audible'));
    });

    test('hidden and zero-box elements cannot be the programme', () {
      final String body = RemoteWebMediaScripts.findBody;
      expect(body, contains("getComputedStyle(el).display !== 'none'"));
      expect(body, contains("getComputedStyle(el).visibility !== 'hidden'"));
      expect(body, contains("getComputedStyle(el).opacity !== '0'"));
      expect(body, contains('if (!visible) return;'));
    });

    test('ident bumpers and looping backgrounds are ignored', () {
      expect(RemoteWebMediaScripts.findBody,
          contains('if (dur > 0 && dur < 2) return;'));
    });

    test('the find script exits a cross-origin iframe honestly', () {
      // Top document only — `querySelectorAll` never descends into another
      // origin's frame, so no reachable element means `found:false`, never a
      // guess (A2's own rule, "do not improve it into a guess").
      expect(RemoteWebMediaScripts.find,
          contains('return !!best;'));
      expect(RemoteWebMediaScripts.find,
          contains('catch (e) { return false; }'));
    });
  });

  group('the read script reports found:false for an out-of-reach player', () {
    test('with no element nominated the answer is the honest found:false', () {
      final String read = RemoteWebMediaScripts.read();
      expect(read, contains('if (!best) return {found:false};'));
      expect(read, contains('catch (e) { return {found:false}; }'));
    });
  });
}
