import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/shortcuts/shortcut_registry.dart';

void main() {
  group('ShortcutRegistry (shortcut.md §4.0)', () {
    test('every entry has a combo and a unique id', () {
      final Set<String> ids = <String>{};
      for (final ShortcutEntry e in ShortcutRegistry.entries) {
        expect(e.combos, isNotEmpty, reason: e.id);
        expect(ids.add(e.id), isTrue, reason: 'duplicate id ${e.id}');
        expect(e.id.startsWith(switch (e.scope) {
          ShortcutScope.player => 'player.',
          ShortcutScope.mini => 'mini.',
          ShortcutScope.web => 'web.',
          ShortcutScope.dialog => 'dialog.',
        }), isTrue, reason: e.id);
      }
    });

    test('no combo means two things in one mode (dialogs excepted)', () {
      for (final ShortcutScope scope in <ShortcutScope>[
        ShortcutScope.player,
        ShortcutScope.mini,
        ShortcutScope.web,
      ]) {
        final Map<ShortcutCombo, String> seen = <ShortcutCombo, String>{};
        for (final ShortcutEntry e in ShortcutRegistry.forScope(scope)) {
          for (final ShortcutCombo c in e.combos) {
            final String? other = seen[c];
            expect(other, isNull, reason: '$c in ${e.id} and $other');
            seen[c] = e.id;
          }
        }
      }
    });

    test('match is exact about modifiers', () {
      ShortcutEntry? m(LogicalKeyboardKey k,
              {bool ctrl = false, bool shift = false, bool alt = false}) =>
          ShortcutRegistry.match(ShortcutScope.player, k,
              ctrl: ctrl, shift: shift, alt: alt);
      expect(m(LogicalKeyboardKey.space)?.id, 'player.playPause');
      expect(m(LogicalKeyboardKey.keyS)?.id, 'player.stop');
      expect(m(LogicalKeyboardKey.keyS, shift: true)?.id, 'player.shuffle');
      expect(m(LogicalKeyboardKey.keyM)?.id, 'player.mute');
      expect(m(LogicalKeyboardKey.keyM, ctrl: true)?.id, 'player.mini');
      expect(m(LogicalKeyboardKey.digit7)?.id, 'player.jumpPercent');
      expect(m(LogicalKeyboardKey.keyQ), isNull);
    });

    test('the same key reads per mode (§1.1)', () {
      const ShortcutCombo ctrlL =
          ShortcutCombo(LogicalKeyboardKey.keyL, ctrl: true);
      final Map<ShortcutScope, ShortcutEntry?> across =
          ShortcutRegistry.across(ctrlL, except: ShortcutScope.player);
      expect(across.keys, isNot(contains(ShortcutScope.player)));
      expect(across[ShortcutScope.web]?.id, 'web.address');
      expect(across[ShortcutScope.mini], isNull);
    });

    test('Alt-Peek chips match the §4.2 anchor table', () {
      String? p(ShortcutAnchor a) =>
          ShortcutRegistry.chipLegend(ShortcutScope.player, a);
      expect(p(ShortcutAnchor.openMedia), 'Ctrl+O');
      expect(p(ShortcutAnchor.playlist), 'Ctrl+L');
      expect(p(ShortcutAnchor.playPause), 'Space');
      expect(p(ShortcutAnchor.stop), 'S');
      expect(p(ShortcutAnchor.previous), 'PgUp');
      expect(p(ShortcutAnchor.next), 'PgDn');
      expect(p(ShortcutAnchor.seekBack), '←');
      expect(p(ShortcutAnchor.seekForward), '→');
      expect(p(ShortcutAnchor.sound), '↑ ↓ · M');
      expect(p(ShortcutAnchor.timeline), '0–9 · Home · End');
      expect(p(ShortcutAnchor.tune), 'Ctrl+E');
      expect(p(ShortcutAnchor.fetch), 'Ctrl+Shift+F');
      expect(p(ShortcutAnchor.fullscreen), 'F · F11');

      String? w(ShortcutAnchor a) =>
          ShortcutRegistry.chipLegend(ShortcutScope.web, a);
      expect(w(ShortcutAnchor.webNewTab), 'Ctrl+T');
      expect(w(ShortcutAnchor.webCloseTab), 'Ctrl+W');
      expect(w(ShortcutAnchor.webAddress), 'Ctrl+L');
      expect(w(ShortcutAnchor.webHistory), 'Ctrl+H');
      expect(w(ShortcutAnchor.webDownloads), 'Ctrl+J');
      expect(w(ShortcutAnchor.webFavourite), 'Ctrl+D');
      expect(w(ShortcutAnchor.webHub), 'Ctrl+Shift+O');
      expect(w(ShortcutAnchor.webBack), 'Alt+←');
      expect(w(ShortcutAnchor.webForward), 'Alt+→');

      // Nothing rides a player anchor in web mode, and vice versa.
      expect(w(ShortcutAnchor.playPause), isNull);
      expect(p(ShortcutAnchor.webNewTab), isNull);
    });
  });
}
