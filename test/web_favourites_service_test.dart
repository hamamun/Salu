import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/web/web_favourites_service.dart';
import 'package:salu/core/web/web_suggestions.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The 15-slot Web Bookmark store (web.md · key function 9): saved
/// instantly, deduped by page identity, removable with an Undo path.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final WebFavouritesService svc = WebFavouritesService.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // Reset the live list between cases (test-only poke; the widget layer
    // goes through add/remove/update).
    for (int i = svc.favourites.value.length - 1; i >= 0; i--) {
      svc.removeAt(i);
    }
  });

  group('the cap', () {
    test('15 save, the 16th refuses, isFull answers first', () {
      for (int i = 0; i < WebFavouritesService.maxEntries; i++) {
        expect(svc.add(url: 'https://cap.test/p$i', name: 'P$i'), isTrue);
      }
      expect(svc.isFull, isTrue);
      expect(svc.add(url: 'https://cap.test/over'), isFalse);
      expect(svc.favourites.value.length, 15);
    });

    test('a re-save of the SAME page is a silent success', () {
      expect(svc.add(url: 'https://a.test/x', name: 'X'), isTrue);
      expect(svc.add(url: 'https://a.test/x/'), isTrue); // same page
      expect(svc.favourites.value.length, 1);
    });
  });

  group('the flows', () {
    test('add → findFor → update (Rename / Change folder)', () {
      svc.add(url: 'https://s.test/page', name: 'Old');
      expect(svc.findFor('https://s.test/page')?.name, 'Old');
      svc.update(0, name: 'New', folder: 'Reading');
      final WebFavourite e = svc.findFor('https://s.test/page/')!;
      expect(e.name, 'New');
      expect(e.folder, 'Reading');
    });

    test('removeAt hands back the entry — that is the Undo token', () {
      svc.add(url: 'https://u.test/1', name: 'One');
      final WebFavourite? removed = svc.removeAt(0);
      expect(removed?.name, 'One');
      expect(svc.favourites.value, isEmpty);
      svc.insertAt(0, removed!);
      expect(svc.favourites.value.single.url, 'https://u.test/1');
    });

    test('an unnamed save takes the page label (host or Google query)', () {
      svc.add(url: 'https://host.test/somewhere');
      expect(svc.favourites.value.single.name, 'host.test');
    });

    test('folders list sorted, unique, unsorted excluded', () {
      svc.add(url: 'https://f.test/1', name: 'a', folder: 'Work');
      svc.add(url: 'https://f.test/2', name: 'b', folder: 'Fun');
      svc.add(url: 'https://f.test/3', name: 'c', folder: 'Work');
      svc.add(url: 'https://f.test/4', name: 'd');
      expect(svc.folders, <String>['Fun', 'Work']);
    });
  });

  test('suggest matches name or URL', () {
    svc.add(url: 'https://golang.test/doc', name: 'Go tour');
    final List<WebSuggestion> hits = svc.suggest('go');
    expect(hits.length, 1);
    expect(hits.single.kind, WebSuggestionKind.favourite);
    expect(svc.suggest('zzz'), isEmpty);
  });

  test('an instant save means persisted immediately', () async {
    svc.add(url: 'https://p.test/page', name: 'P');
    await svc.flush();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('web_favourites'), contains('https://p.test/page'));
  });
}
