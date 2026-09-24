import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/remote/remote_web_focus_bridge.dart';

/// `web_key` + `web_focus_get` (pc_part.md A3 · remote.md §17.13.5): the
/// focus order and its filters, the caret-owning text-field rule, Enter
/// clicks vs submits, Escape's element → page → dialog order, and the ack's
/// `{label,tag,index,count,editable}` payload shape.
void main() {
  group('the focus order (A3.1)', () {
    test('walks the page\'s own tab-order selectors', () {
      final String body = RemoteWebFocusScripts.orderBody;
      expect(
        body,
        contains(
            "'a[href], button, input, select, textarea, [tabindex]'"),
      );
    });

    test('filters to visible, enabled, non-negative-tabindex elements', () {
      final String body = RemoteWebFocusScripts.orderBody;
      expect(body, contains('if (el.disabled) return false;'));
      expect(body, contains('Number(tab) < 0'));
      expect(body, contains('getComputedStyle(el).visibility'));
      expect(body, contains('getComputedStyle(el).display'));
    });
  });

  group('the key semantics (A3.2–A3.4)', () {
    test('where a text field has focus, the arrows belong to the caret', () {
      final String key = RemoteWebFocusScripts.key('ArrowDown');
      expect(key, contains('isEditable'));
      expect(key, contains('The arrows belong to the caret'));
      expect(key, contains('return __saluDescribe(el, list);'));
    });

    test('Enter clicks the element', () {
      final String key = RemoteWebFocusScripts.key('Enter');
      expect(key, contains('el.click()'));
    });

    test('Enter submits a text field\'s form', () {
      final String key = RemoteWebFocusScripts.key('Enter');
      expect(key, contains('f.requestSubmit'));
    });

    test('Escape leaves element → page → dialog in that order', () {
      final String key = RemoteWebFocusScripts.key('Escape');
      final int exitFullscreen = key.indexOf('exitFullscreen');
      final int dialogs = key.indexOf('dialog[open]');
      expect(exitFullscreen, isNonNegative);
      expect(dialogs, greaterThan(exitFullscreen));
    });
  });

  group('the ring is part of the feature (A3.5)', () {
    test('every key script carries the ring injection', () {
      expect(RemoteWebFocusScripts.key('ArrowUp'), contains('__saluRing('));
      expect(RemoteWebFocusScripts.key('ArrowUp'), contains('__saluRing(next)'));
      expect(RemoteWebFocusScripts.key('Enter'), contains('__saluRingCss'));
    });
  });

  group('the ack payload (A3.6)', () {
    test('parses the phone\'s shape and renders the Subscribe line', () {
      final RemoteWebFocusResult r = RemoteWebFocusResult.fromScript(
        <String, Object?>{
          'found': true,
          'label': 'Subscribe',
          'tag': 'button',
          'index': 3,
          'count': 120,
          'editable': false,
        },
      );
      expect(r.found, isTrue);
      expect(r.label, 'Subscribe');
      expect(r.tag, 'button');
      expect(r.index, 3);
      expect(r.count, 120);
      expect(r.editable, isFalse);
      expect(r.line, 'Subscribe · BUTTON · 4 of 120');
    });

    test('editable:true is carried so the phone\'s line changes', () {
      final RemoteWebFocusResult r = RemoteWebFocusResult.fromScript(
          <String, Object?>{'found': true, 'editable': true, 'count': 5, 'index': 0});
      expect(r.editable, isTrue);
      expect(r.toJson()['editable'], isTrue);
    });

    test('nothing focused is the honest body seat, not a fake one', () {
      final RemoteWebFocusResult r = RemoteWebFocusResult.fromScript(
        <String, Object?>{
          'found': true,
          'label': '',
          'tag': 'body',
          'index': -1,
          'count': 0,
          'editable': false,
        },
      );
      expect(r.tag, 'body');
      expect(r.line, isEmpty);
    });

    test('a broken injection is found:false', () {
      expect(RemoteWebFocusResult.fromScript(null).found, isFalse);
      expect(RemoteWebFocusResult.fromScript('garbage').found, isFalse);
    });
  });
}
