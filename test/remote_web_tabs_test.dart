import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/browser_service.dart';
import 'package:salu/core/remote/remote_command_handler.dart';
import 'package:salu/core/remote/remote_protocol.dart';
import 'package:salu/core/web/web_favourites_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The tab-strip mirror, its verbs and its wire discipline (pc_part.md A4/
/// A5 · remote.md §17.13.2–§17.13.4): the service holds a mirror (not the
/// controllers), the screen is the one write path, a stale index answers
/// `tab_not_found` (never closes the wrong page), a negative index answers
/// `invalid_arguments`, and the 8 KB frame rule is honoured — at most 50 tab
/// rows / 200 bookmarks, 80-char titles, 180-char urls, `count` always the
/// truth.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  final BrowserService service = BrowserService.instance;

  WebTabMirror tab({
    String? title,
    String? url,
    bool loading = false,
    bool hasMedia = false,
  }) =>
      WebTabMirror(
        title: title,
        url: url,
        active: false,
        loading: loading,
        hasMedia: hasMedia,
      );

  tearDown(() {
    service.clearRemoteWebMirror();
    service.setRemoteHandlers();
    service.setTabHandler(null);
    service.mode.value = SaluMode.player;
  });

  group('the mirror (A4)', () {
    test('mirrors a strip without owning anything but the fields', () {
      final ValueNotifier<List<WebTabMirror>> mirrored = service.mirrorTabs(
        <WebTabMirror>[
          tab(title: 'News', url: 'https://n.example', hasMedia: true),
          tab(title: 'Mail', url: 'https://m.example'),
        ],
        1,
      );
      expect(mirrored.value, hasLength(2));
      expect(mirrored.value.first.hasMedia, isTrue);
      expect(mirrored.value.first.active, isFalse);
      expect(mirrored.value.last.active, isTrue);
      // `active` is recomputed from the screen's index — a stale caller
      // cannot smuggle a wrong flag in.
      expect(mirrored.value.last.hasMedia, isFalse);
      expect(service.webTabCount.value, 2);
    });

    test('a rebuilt mirror tracks add/remove/select', () {
      service.mirrorTabs(<WebTabMirror>[tab(title: 'A')], 0);
      service.mirrorTabs(
        <WebTabMirror>[tab(title: 'A'), tab(title: 'B')],
        1,
      );
      expect(service.webTabs.value.map((WebTabMirror t) => t.title),
          <String?>['A', 'B']);
      service.mirrorTabs(<WebTabMirror>[tab(title: 'B'), tab(title: 'C')], 0);
      expect(service.webTabs.value.map((WebTabMirror t) => t.title),
          <String?>['B', 'C']);
      expect(service.webTabs.value.first.active, isTrue);
      expect(service.webTabCount.value, 2);
    });
  });

  group('the verbs (A4 · §17.13.2)', () {
    RemoteCommandHandler handler() {
      // The screen's own select/close/add, faked as the one write path.
      service.setTabHandler((String action, int? index, String? url) async {
        final List<WebTabMirror> tabs = service.webTabs.value.toList();
        if (action == 'activate') {
          if (index == null || index < tabs.length) {
            service.mirrorTabs(
              <WebTabMirror>[
                for (int i = 0; i < tabs.length; i++)
                  WebTabMirror(
                    title: tabs[i].title,
                    url: tabs[i].url,
                    active: i == index,
                    loading: tabs[i].loading,
                    hasMedia: tabs[i].hasMedia,
                  ),
              ],
              index ?? 0,
            );
            return 'ok';
          }
          return 'tab_not_found';
        }
        if (action == 'close') {
          if (index == null || index >= tabs.length) return 'tab_not_found';
          return 'ok';
        }
        return 'ok'; // 'new'
      });
      return RemoteCommandHandler();
    }

    test('web_tabs_get mirrors the strip with index/active/count', () async {
      service.mode.value = SaluMode.web;
      service.mirrorTabs(
        <WebTabMirror>[
          tab(title: 'A', url: 'https://a.example'),
          tab(title: 'B', url: 'https://b.example'),
        ],
        0,
      );
      final RemoteCommandHandler h = handler();
      final RemoteCommandResponse reply = await h.handle(
        const RemoteCommand(id: 1, verb: 'web_tabs_get'),
      );
      expect(reply.ok, isTrue);
      final Map<String, Object?> result = reply.result!;
      expect(result['type'], 'web_tabs_result');
      expect(result['count'], 2);
      expect((result['tabs']! as List<Object?>), hasLength(2));
      expect(((result['tabs']! as List<Object?>).last! as Map<String, Object?>)['title'],
          'B');
      expect(result['active'], 0);
    });

    test('a stale index answers tab_not_found, never the wrong page',
        () async {
      service.mode.value = SaluMode.web;
      service.mirrorTabs(<WebTabMirror>[tab(title: 'Only')], 0);
      final RemoteCommandHandler h = handler();
      final RemoteCommandResponse reply = await h.handle(
        const RemoteCommand(id: 2, verb: 'web_tab_close', args: <String, Object?>{
          'index': 7,
        }),
      );
      expect(reply.ok, isFalse);
      expect(reply.code, RemoteErrorCode.tabNotFound);
    });

    test('a negative index answers invalid_arguments', () async {
      service.mode.value = SaluMode.web;
      service.mirrorTabs(<WebTabMirror>[tab(title: 'Only')], 0);
      final RemoteCommandHandler h = handler();
      final RemoteCommandResponse reply = await h.handle(
        const RemoteCommand(id: 3, verb: 'web_tab_close', args: <String, Object?>{
          'index': -1,
        }),
      );
      expect(reply.ok, isFalse);
      expect(reply.code, RemoteErrorCode.invalidArguments);
    });

    test('tabs verbs answer no_web_tabs when the browser is not open',
        () async {
      final RemoteCommandHandler h = handler();
      final RemoteCommandResponse reply = await h.handle(
        const RemoteCommand(id: 4, verb: 'web_tabs_get'),
      );
      expect(reply.ok, isFalse);
      expect(reply.code, RemoteErrorCode.noWebTabs);
    });
  });

  group('the 8 KB frame rule (A4 §17.13.3)', () {
    test('200 tabs encode under 8 KB and cap at 50 rows with honest count',
        () async {
      service.mode.value = SaluMode.web;
      service.mirrorTabs(
        <WebTabMirror>[
          for (int i = 0; i < 200; i++)
            tab(
              title: 'Tab $i',
              url: 'https://example.com/page/$i',
              loading: i == 0,
            ),
        ],
        0,
      );
      final RemoteCommandHandler h = RemoteCommandHandler();
      final RemoteCommandResponse reply = await h.handle(
        const RemoteCommand(id: 5, verb: 'web_tabs_get'),
      );
      final Map<String, Object?> result = reply.result!;
      expect(result['count'], 200);
      final List<Object?> rows = result['tabs']! as List<Object?>;
      expect(rows.length, 50);
      final int bytes = utf8.encode(jsonEncode(result)).length;
      expect(bytes, lessThan(8192));
    });
  });

  group('the bookmark mirror (A5 · §17.13.4)', () {
    test('read-only: there is no remote bookmark verb on the write side', () async {
      // The only bookmark verb is `web_bookmarks_get`; anything else in the
      // command table is an unknown command — the phone cannot mutate the
      // PC's bookmark bar through this protocol.
      final RemoteCommandHandler h = RemoteCommandHandler();
      final RemoteCommandResponse reply = await h.handle(
        const RemoteCommand(
          id: 7,
          verb: 'web_bookmark_add',
          args: <String, Object?>{'url': 'https://x.example'},
        ),
      );
      expect(reply.ok, isFalse);
      expect(reply.code, RemoteErrorCode.unknownCommand);
    });

    test('bookmarks answer read-only with 80/180 truncation, under 8 KB',
        () async {
      service.mode.value = SaluMode.web;
      final WebFavouritesService favs = WebFavouritesService.instance;
      for (int i = favs.favourites.value.length - 1; i >= 0; i--) {
        favs.removeAt(i);
      }
      // The PC's own store caps at 15 entries; the wire discipline (titles
      // 80 / urls 180, one-level folder, 8 KB frame) is what travels.
      favs.add(
        url: 'https://fav.example/${List.filled(400, 'p').join()}',
        name: 'The ${List.filled(300, 't').join()} title',
        folder: 'Reading',
      );
      final RemoteCommandHandler h = RemoteCommandHandler();
      final RemoteCommandResponse reply = await h.handle(
        const RemoteCommand(id: 6, verb: 'web_bookmarks_get'),
      );
      expect(reply.ok, isTrue);
      final Map<String, Object?> result = reply.result!;
      expect(result['type'], 'web_bookmarks_result');
      final List<Object?> rows = result['entries']! as List<Object?>;
      expect(rows.length, 1);
      final Map<String, Object?> row = rows.first! as Map<String, Object?>;
      expect((row['name']! as String).length, lessThanOrEqualTo(80));
      expect((row['url']! as String).length, lessThanOrEqualTo(180));
      expect(row['folder'], 'Reading');
      expect(utf8.encode(jsonEncode(result)).length, lessThan(8192));
    });
  });
}
