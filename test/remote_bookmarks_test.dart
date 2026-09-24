import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/remote/remote_command_handler.dart';
import 'package:salu/core/remote/remote_protocol.dart';
import 'package:salu/core/web/web_favourites_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Add-only bookmarks (pc_part.md C4 · remote.md §17.14.4): an append adds
/// one entry at the top level of the store `web_bookmarks_get` reads; the
/// same page twice adds one; nothing else in the store changes; a full
/// store answers `no_web_bookmarks` (the phone then saves into SALU's list
/// and says so); and there is no verb that can rename or delete.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  final WebFavouritesService store = WebFavouritesService.instance;

  setUp(() {
    store.favourites.value = const <WebFavourite>[];
  });

  Future<RemoteCommandResponse> add(Map<String, Object?> args) =>
      RemoteCommandHandler().handle(
        RemoteCommand(id: 1, verb: 'web_bookmark_add', args: args),
      );

  test('an append adds exactly one top-level entry', () async {
    final RemoteCommandResponse reply = await add(<String, Object?>{
      'url': 'https://www.youtube.com/watch?v=abc',
      'name': 'A video',
    });
    expect(reply.ok, isTrue);
    expect(store.favourites.value, hasLength(1));
    final WebFavourite f = store.favourites.value.single;
    expect(f.name, 'A video');
    expect(f.url, 'https://www.youtube.com/watch?v=abc');
    expect(f.folder, isEmpty);
    final Map<String, Object?> entry =
        reply.result!['entry']! as Map<String, Object?>;
    expect(entry['folder'], '');
  });

  test('the same URL twice adds one', () async {
    await add(<String, Object?>{'url': 'https://example.com/page'});
    final RemoteCommandResponse again =
        await add(<String, Object?>{'url': 'https://EXAMPLE.com/page/'});
    expect(again.ok, isTrue);
    expect(store.favourites.value, hasLength(1));
  });

  test('nothing else in the store changes', () async {
    store.favourites.value = const <WebFavourite>[
      WebFavourite(name: 'Mine', url: 'https://mine.example', folder: 'Work'),
    ];
    await add(<String, Object?>{'url': 'https://new.example', 'name': 'New'});
    final List<WebFavourite> list = store.favourites.value;
    expect(list, hasLength(2));
    expect(list.first.name, 'Mine');
    expect(list.first.folder, 'Work');
    expect(list.last.name, 'New');
  });

  test('a bare host gets its scheme; a query is invalid_arguments', () async {
    final RemoteCommandResponse ok =
        await add(<String, Object?>{'url': 'youtube.com'});
    expect(ok.ok, isTrue);
    expect(store.favourites.value.single.url, 'https://youtube.com');
    final RemoteCommandResponse bad =
        await add(<String, Object?>{'url': 'not a url'});
    expect(bad.code, RemoteErrorCode.invalidArguments);
    final RemoteCommandResponse missing = await add(<String, Object?>{});
    expect(missing.code, RemoteErrorCode.invalidArguments);
  });

  test('a full store answers no_web_bookmarks and changes nothing', () async {
    store.favourites.value = <WebFavourite>[
      for (int i = 0; i < WebFavouritesService.maxEntries; i++)
        WebFavourite(name: 'n$i', url: 'https://s$i.example'),
    ];
    final RemoteCommandResponse reply =
        await add(<String, Object?>{'url': 'https://one-more.example'});
    expect(reply.code, RemoteErrorCode.noWebBookmarks);
    expect(store.favourites.value, hasLength(WebFavouritesService.maxEntries));
  });

  test('there is no rename/delete verb', () async {
    for (final String verb in <String>[
      'web_bookmark_remove',
      'web_bookmark_rename',
      'web_bookmark_delete',
    ]) {
      final RemoteCommandResponse reply = await RemoteCommandHandler()
          .handle(RemoteCommand(id: 2, verb: verb));
      expect(reply.code, RemoteErrorCode.unknownCommand, reason: verb);
    }
  });
}
