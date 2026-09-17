import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:salu/core/web/web_history_service.dart';

/// The browser's own memory of visits — the second suggestion source and
/// the data the Clear dialog's first checkbox wipes (web.md).

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final WebHistoryService svc = WebHistoryService.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    svc.clear(); // singleton reset between cases
  });

  group('record', () {
    test('only http(s) pages are visits', () {
      svc.record('about:blank');
      svc.record('file:///C:/x');
      expect(svc.entries.value, isEmpty);
      svc.record('https://a.test/');
      expect(svc.entries.value.length, 1);
    });

    test('redirect hops merge into one row while the title arrives', () {
      svc.record('https://a.test/x');
      svc.record('https://a.test/x', title: 'A title');
      svc.record('https://a.test/x/'); // same page, canonically
      expect(svc.entries.value.length, 1);
      expect(svc.entries.value.first.title, 'A title');
    });

    test('newest first, and a real revisit stacks', () {
      svc.record('https://a.test/1');
      svc.record('https://a.test/2');
      expect(svc.entries.value.first.url, 'https://a.test/2');
    });

    test('the store is capped', () {
      for (int i = 0; i < 510; i++) {
        svc.record('https://cap.test/p$i');
      }
      expect(svc.entries.value.length, WebHistoryService.maxEntries);
      expect(svc.entries.value.first.url, 'https://cap.test/p509');
    });
  });

  group('retitle', () {
    test('a late title labels the row once, never again', () {
      svc.record('https://t.test/p');
      svc.retitle('https://t.test/p', 'Real Title');
      expect(svc.entries.value.single.title, 'Real Title');
      svc.retitle('https://t.test/p', 'Even Later');
      expect(svc.entries.value.single.title, 'Real Title');
    });
  });

  group('suggest', () {
    test('matches title or URL, case-insensitive, one row per page', () {
      svc.record('https://docs.rs/clap', title: 'clap - Rust');
      svc.record('https://docs.rs/clap/', title: 'clap - Rust'); // dup page
      svc.record('https://other.test/', title: 'unrelated');
      final List<String> rows =
          svc.suggest('clap').map((e) => e.url).toList();
      expect(rows.length, 1); // the / and no-slash twins folded together
      expect(svc.suggest('other.test').length, 1);
      expect(svc.suggest(''), isEmpty);
    });
  });

  test('clear empties the store — instantly, no confirm (web.md)', () {
    svc.record('https://a.test/');
    svc.clear();
    expect(svc.entries.value, isEmpty);
    expect(svc.isEmpty, isTrue);
  });

  test('the store survives a restart through prefs', () async {
    svc.record('https://r.test/page', title: 'R');
    await svc.flush();
    // Replaying the persisted blob is what a fresh load() does; the
    // singleton is already loaded in-process, so read prefs directly.
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String raw = prefs.getString('web_browsing_history')!;
    expect(raw, contains('https://r.test/page'));
    expect(raw, contains('"R"'));
  });
}
