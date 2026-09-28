import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/shortcuts/shortcut_registry.dart';

void main() {
  group('SaluShortcuts (shortcut.md §4.0)', () {
    test('every entry has a combo and a unique id', () {
      final Set<String> ids = <String>{};
      for (final ShortcutEntry e in SaluShortcuts.entries) {
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
        for (final ShortcutEntry e in SaluShortcuts.forScope(scope)) {
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
          SaluShortcuts.match(ShortcutScope.player, k,
              ctrl: ctrl, shift: shift, alt: alt);
      expect(m(LogicalKeyboardKey.space)?.id, 'player.playPause');
      expect(m(LogicalKeyboardKey.keyS)?.id, 'player.stop');
      expect(m(LogicalKeyboardKey.keyS, shift: true)?.id, 'player.shuffle');
      expect(m(LogicalKeyboardKey.keyS, ctrl: true, shift: true)?.id,
          'player.shuffle');
      expect(m(LogicalKeyboardKey.keyR)?.id, 'player.repeat');
      expect(
        SaluShortcuts.forAnchor(
          ShortcutScope.player,
          ShortcutAnchor.playlistShuffle,
        ).single.id,
        'player.shuffle',
      );
      expect(
        SaluShortcuts.forAnchor(
          ShortcutScope.player,
          ShortcutAnchor.playlistRepeat,
        ).single.id,
        'player.repeat',
      );
      final Iterable<String> playerShelfIds = SaluShortcuts.rideless(
        ShortcutScope.player,
      ).map((ShortcutEntry e) => e.id);
      expect(playerShelfIds, isNot(contains('player.shuffle')));
      expect(playerShelfIds, isNot(contains('player.repeat')));
      expect(
        SaluShortcuts.byId('player.shuffle')?.keys,
        'Shift+S / Alt+S / Ctrl+Shift+S',
      );
      expect(m(LogicalKeyboardKey.keyM)?.id, 'player.mute');
      expect(m(LogicalKeyboardKey.keyM, ctrl: true)?.id, 'player.mini');
      expect(m(LogicalKeyboardKey.digit7)?.id, 'player.jumpPercent');
      expect(m(LogicalKeyboardKey.keyG, ctrl: true)?.id, 'player.groupBy');
      expect(m(LogicalKeyboardKey.keyD, ctrl: true)?.id, 'player.playlistFavourites');
      expect(
        SaluShortcuts.match(
          ShortcutScope.player,
          LogicalKeyboardKey.delete,
          ctrl: true,
          shift: true,
          alt: false,
        )?.id,
        'player.clearPlaylist',
      );
      expect(m(LogicalKeyboardKey.keyQ), isNull);
      expect(
        SaluShortcuts.match(ShortcutScope.dialog, LogicalKeyboardKey.digit1,
            ctrl: false, shift: false, alt: false)?.id,
        'dialog.groupFlat',
      );
      expect(
        SaluShortcuts.byId('dialog.groupCountry')?.guard,
        ShortcutGuard.groupByPillOpen,
      );
      expect(
        SaluShortcuts.byId('dialog.groupBy.escape')?.guard,
        ShortcutGuard.groupByPillOpen,
      );
      expect(
        SaluShortcuts.match(ShortcutScope.player, LogicalKeyboardKey.keyE,
            ctrl: false, shift: false, alt: false, meta: true)?.id,
        'player.tune',
      );
      expect(
        SaluShortcuts.match(ShortcutScope.player, LogicalKeyboardKey.arrowUp,
            ctrl: false, shift: false, alt: false, meta: true)?.id,
        'player.tuneNudge',
      );
      expect(
        SaluShortcuts.match(ShortcutScope.player, LogicalKeyboardKey.arrowUp,
            ctrl: false, shift: false, alt: true, meta: true)?.id,
        'player.tuneFocus',
      );
    });

    test('Web normal and cache-bypassing reloads are distinct', () {
      ShortcutEntry? web(
        LogicalKeyboardKey key, {
        bool ctrl = false,
        bool shift = false,
      }) =>
          SaluShortcuts.match(
            ShortcutScope.web,
            key,
            ctrl: ctrl,
            shift: shift,
            alt: false,
          );

      expect(web(LogicalKeyboardKey.f5)?.id, 'web.reload');
      expect(web(LogicalKeyboardKey.keyR, ctrl: true)?.id, 'web.reload');
      expect(web(LogicalKeyboardKey.f5, ctrl: true)?.id, 'web.hardReload');
      expect(
        web(LogicalKeyboardKey.keyR, ctrl: true, shift: true)?.id,
        'web.hardReload',
      );
    });

    test('the same key reads per mode (§1.1)', () {
      const ShortcutCombo ctrlL =
          ShortcutCombo(LogicalKeyboardKey.keyL, ctrl: true);
      final Map<ShortcutScope, ShortcutEntry?> across =
          SaluShortcuts.across(ctrlL, except: ShortcutScope.player);
      expect(across.keys, isNot(contains(ShortcutScope.player)));
      expect(across[ShortcutScope.web]?.id, 'web.address');
      expect(across[ShortcutScope.mini], isNull);
    });

    test('Alt-Peek chips match the §4.2 anchor table', () {
      String? p(ShortcutAnchor a) =>
          SaluShortcuts.chipLegend(ShortcutScope.player, a);
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
      expect(p(ShortcutAnchor.tune), 'Ctrl+E · Cmd+E');
      expect(p(ShortcutAnchor.playlistRepeat), 'R');
      expect(
        p(ShortcutAnchor.playlistShuffle),
        'Shift+S · Alt+S · Ctrl+Shift+S',
      );
      expect(p(ShortcutAnchor.playlistGroupBy), 'Ctrl+G');
      expect(p(ShortcutAnchor.playlistSearch), 'Ctrl+F');
      expect(p(ShortcutAnchor.playlistFavourites), 'Ctrl+D');
      expect(p(ShortcutAnchor.playlistClear), 'Ctrl+Shift+Delete');
      expect(p(ShortcutAnchor.fetch), 'Ctrl+Shift+F');
      expect(p(ShortcutAnchor.fullscreen), 'F · F11');

      String? w(ShortcutAnchor a) =>
          SaluShortcuts.chipLegend(ShortcutScope.web, a);
      expect(w(ShortcutAnchor.webNewTab), 'Ctrl+T');
      expect(w(ShortcutAnchor.webCloseTab), 'Ctrl+W');
      expect(w(ShortcutAnchor.webAddress), 'Ctrl+L');
      expect(w(ShortcutAnchor.webHistory), 'Ctrl+H');
      expect(w(ShortcutAnchor.webDownloads), 'Ctrl+J');
      expect(w(ShortcutAnchor.webFavourite), 'Ctrl+D');
      expect(w(ShortcutAnchor.webHub), 'Ctrl+Shift+O');
      expect(
        SaluShortcuts.match(ShortcutScope.web, LogicalKeyboardKey.backspace,
            ctrl: true, shift: true, alt: false)?.id,
        'web.clearData',
      );
      expect(w(ShortcutAnchor.webBack), 'Alt+←');
      expect(w(ShortcutAnchor.webForward), 'Alt+→');

      // Nothing rides a player anchor in web mode, and vice versa.
      expect(w(ShortcutAnchor.playPause), isNull);
      expect(p(ShortcutAnchor.webNewTab), isNull);
    });
  });
}
