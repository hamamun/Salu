import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/channel_favourites_service.dart';
import 'package:salu/core/channel_grouping.dart';
import 'package:salu/core/queue_service.dart';

/// Builds a channel with the given display identity + grouping metadata.
/// (`tvgId`/`tvgName` default off so most tests exercise name identity.)
QueueItem _ch(
  String url,
  String name, {
  String? tvgId,
  String? tvgName,
  String? group,
  String? language,
  String? country,
}) =>
    QueueItem(
      url,
      name: name,
      tvgId: tvgId,
      tvgName: tvgName,
      group: group,
      language: language,
      country: country,
    );

List<int> _all(int n) => List<int>.generate(n, (int i) => i);

void main() {
  group('ChannelGrouping.buildGroups', () {
    test('category keeps the provider first-appearance order', () {
      final List<QueueItem> items = <QueueItem>[
        _ch('u0', 'A', group: 'Sports'),
        _ch('u1', 'B', group: 'News'),
        _ch('u2', 'C', group: 'Sports'),
        _ch('u3', 'D', group: 'Movies'),
      ];
      final List<ChannelGroup> groups =
          ChannelGrouping.buildGroups(items, _all(4), ChannelGroupMode.category);
      expect(groups.map((ChannelGroup g) => g.label),
          <String>['Sports', 'News', 'Movies']);
      expect(groups[0].indexes, <int>[0, 2]);
      expect(groups[1].indexes, <int>[1]);
    });

    test('language and country sort alphabetically, case-insensitively', () {
      final List<QueueItem> items = <QueueItem>[
        _ch('u0', 'A', language: 'urdu', country: 'PK'),
        _ch('u1', 'B', language: 'English', country: 'us'),
        _ch('u2', 'C', language: 'arabic', country: 'AE'),
      ];
      final List<ChannelGroup> langs = ChannelGrouping.buildGroups(
          items, _all(3), ChannelGroupMode.language);
      expect(langs.map((ChannelGroup g) => g.label),
          <String>['arabic', 'English', 'urdu']);
      final List<ChannelGroup> countries = ChannelGrouping.buildGroups(
          items, _all(3), ChannelGroupMode.country);
      expect(countries.map((ChannelGroup g) => g.label),
          <String>['AE', 'PK', 'us']);
    });

    test('the missing-data group is labelled Unknown and sorted last', () {
      final List<QueueItem> items = <QueueItem>[
        _ch('u0', 'A'),
        _ch('u1', 'B', group: 'News'),
        _ch('u2', 'C', group: 'News'),
      ];
      final List<ChannelGroup> groups =
          ChannelGrouping.buildGroups(items, _all(3), ChannelGroupMode.category);
      expect(groups.map((ChannelGroup g) => g.label), <String>['News', 'Unknown']);
      expect(groups.last.unknown, isTrue);
      expect(groups.last.indexes, <int>[0]);
      // ... even in an alphabetical mode, where 'Unknown' would sort mid-list.
      final List<QueueItem> langs = <QueueItem>[
        _ch('u0', 'A'),
        _ch('u1', 'B', language: 'Zulu'),
      ];
      final List<ChannelGroup> lg = ChannelGrouping.buildGroups(
          langs, _all(2), ChannelGroupMode.language);
      expect(lg.map((ChannelGroup g) => g.label), <String>['Zulu', 'Unknown']);
    });

    test('a literal group named Unknown stays distinct from the bucket', () {
      final List<QueueItem> items = <QueueItem>[
        _ch('u0', 'A', group: 'Unknown'),
        _ch('u1', 'B'),
      ];
      final List<ChannelGroup> groups =
          ChannelGrouping.buildGroups(items, _all(2), ChannelGroupMode.category);
      expect(groups.length, 2);
      expect(groups[0].label, 'Unknown');
      expect(groups[0].unknown, isFalse);
      expect(groups[1].unknown, isTrue);
      expect(groups[0].key == groups[1].key, isFalse);
    });

    test('empty groups vanish — only present values appear', () {
      final List<QueueItem> items = <QueueItem>[
        _ch('u0', 'A', group: 'News'),
        _ch('u1', 'B', group: 'Sports'),
      ];
      // A filtered view holding only row 1 shows only Sports.
      final List<ChannelGroup> groups = ChannelGrouping.buildGroups(
          items, <int>[1], ChannelGroupMode.category);
      expect(groups.length, 1);
      expect(groups.single.label, 'Sports');
    });

    test('flat builds no groups', () {
      final List<QueueItem> items = <QueueItem>[_ch('u0', 'A', group: 'X')];
      expect(ChannelGrouping.buildGroups(items, _all(1), ChannelGroupMode.flat),
          isEmpty);
    });
  });

  group('ChannelGrouping.availability', () {
    test('flat is always available; metadata modes need one value', () {
      expect(
        ChannelGrouping.availability(<QueueItem>[_ch('u0', 'A')]),
        <ChannelGroupMode, bool>{
          ChannelGroupMode.flat: true,
          ChannelGroupMode.category: false,
          ChannelGroupMode.language: false,
          ChannelGroupMode.country: false,
        },
      );
      final List<QueueItem> items = <QueueItem>[
        _ch('u0', 'A', language: 'en'),
        _ch('u1', 'B', country: 'US'),
      ];
      final Map<ChannelGroupMode, bool> avail =
          ChannelGrouping.availability(items);
      expect(avail[ChannelGroupMode.flat], isTrue);
      expect(avail[ChannelGroupMode.category], isFalse);
      expect(avail[ChannelGroupMode.language], isTrue);
      expect(avail[ChannelGroupMode.country], isTrue);
    });

    test('short-circuits once every mode is proven', () {
      // 50 000 rows, all three metadata kinds on row 0 — availability
      // must not walk the list (no timing assert; the loop breaks).
      final List<QueueItem> items = List<QueueItem>.generate(
        50000,
        (int i) => i == 0
            ? _ch('u0', 'A', group: 'g', language: 'l', country: 'c')
            : _ch('u$i', 'N$i'),
      );
      final Map<ChannelGroupMode, bool> avail =
          ChannelGrouping.availability(items);
      expect(avail.values, everyElement(isTrue));
    });
  });

  group('ChannelGrouping.descriptors', () {
    final List<QueueItem> items = <QueueItem>[
      _ch('u0', 'A', group: 'Sports'),
      _ch('u1', 'B', group: 'News'),
      _ch('u2', 'C', group: 'Sports'),
    ];

    test('flat lists one row per filtered index, real queue indexes', () {
      final List<ChannelDescriptor> descs = ChannelGrouping.descriptors(
        items: items,
        filtered: <int>[2, 0],
        mode: ChannelGroupMode.flat,
        openGroupKey: null,
        flattened: false,
      );
      expect(descs.length, 2);
      expect(descs[0], isA<ChannelRowDescriptor>());
      expect((descs[0] as ChannelRowDescriptor).index, 2);
      expect((descs[1] as ChannelRowDescriptor).index, 0);
    });

    test('a search flattens whatever the mode is', () {
      final List<ChannelDescriptor> descs = ChannelGrouping.descriptors(
        items: items,
        filtered: <int>[0, 1],
        mode: ChannelGroupMode.category,
        openGroupKey: 'category\x00News',
        flattened: true,
      );
      expect(descs, hasLength(2));
      expect(descs.every((ChannelDescriptor d) => d is ChannelRowDescriptor),
          isTrue);
    });

    test('grouped lists heads + the open group rows only', () {
      final String? sports =
          ChannelGrouping.keyFor(items, 0, ChannelGroupMode.category);
      final List<ChannelDescriptor> descs = ChannelGrouping.descriptors(
        items: items,
        filtered: _all(3),
        mode: ChannelGroupMode.category,
        openGroupKey: sports,
        flattened: false,
      );
      // Sports head + its 2 rows, then the News head, collapsed.
      expect(descs, hasLength(4));
      expect(descs[0], isA<GroupHeadDescriptor>());
      expect((descs[0] as GroupHeadDescriptor).expanded, isTrue);
      expect((descs[1] as ChannelRowDescriptor).index, 0);
      expect((descs[2] as ChannelRowDescriptor).index, 2);
      expect((descs[3] as GroupHeadDescriptor).expanded, isFalse);
    });

    test('a stale open key opens nothing', () {
      final List<ChannelDescriptor> descs = ChannelGrouping.descriptors(
        items: items,
        filtered: _all(3),
        mode: ChannelGroupMode.category,
        openGroupKey: 'category\x00Gone',
        flattened: false,
      );
      expect(descs, hasLength(2)); // the two heads, both collapsed
      expect(
          descs.every((ChannelDescriptor d) =>
              d is GroupHeadDescriptor && !d.expanded),
          isTrue);
    });
  });

  group('ChannelGrouping.keyFor', () {
    final List<QueueItem> items = <QueueItem>[
      _ch('u0', 'A', group: 'Sports'),
      _ch('u1', 'B'),
    ];

    test('names the value group and the missing bucket distinctly', () {
      final String? sports =
          ChannelGrouping.keyFor(items, 0, ChannelGroupMode.category);
      final String? missing =
          ChannelGrouping.keyFor(items, 1, ChannelGroupMode.category);
      expect(sports, isNotNull);
      expect(missing, isNotNull);
      expect(sports == missing, isFalse);
    });

    test('flat and out-of-range indexes key to null', () {
      expect(ChannelGrouping.keyFor(items, 0, ChannelGroupMode.flat), isNull);
      expect(ChannelGrouping.keyFor(items, 9, ChannelGroupMode.category), isNull);
      expect(ChannelGrouping.keyFor(items, -1, ChannelGroupMode.category), isNull);
    });
  });

  group('favourites keys (M11/M12)', () {
    test('channel key is id → tvg-name → name, never the URL or row', () {
      expect(ChannelFavouritesService.channelKey(_ch('u', 'A')), 'A');
      expect(
          ChannelFavouritesService.channelKey(
              _ch('u', 'A', tvgName: 'B')), 'B');
      expect(
          ChannelFavouritesService.channelKey(
              _ch('u', 'A', tvgName: 'B', tvgId: 'C')),
          'C');
    });

    test('playlist key is the host — never the credentialed full URL', () {
      expect(
        ChannelFavouritesService.playlistKeyForSource(
            'http://user:pass@provider.tv:8080/get.php?x=1'),
        'host:provider.tv',
      );
      expect(
        ChannelFavouritesService.playlistKeyForSource(
            'https://EXAMPLE.com/list.m3u'),
        'host:example.com',
      );
    });

    test('local files key by their own path — never a shared bucket', () {
      final String a = ChannelFavouritesService.playlistKeyForSource(
          r'C:\lists\a.m3u');
      final String b = ChannelFavouritesService.playlistKeyForSource(
          r'C:\lists\b.m3u');
      expect(a.startsWith('file:'), isTrue);
      expect(a == b, isFalse);
    });
  });

  group('scale smoke (§10.10c)', () {
    test('50 000 rows group + flatten without incident', () {
      final List<QueueItem> items = List<QueueItem>.generate(
        50000,
        (int i) => _ch('u$i', 'N$i',
            group: 'G${i % 97}', language: 'L${i % 13}'),
      );
      final List<ChannelGroup> groups = ChannelGrouping.buildGroups(
          items, _all(50000), ChannelGroupMode.category);
      expect(groups.length, 97);
      final String? open =
          ChannelGrouping.keyFor(items, 1234, ChannelGroupMode.category);
      final List<ChannelDescriptor> descs = ChannelGrouping.descriptors(
        items: items,
        filtered: _all(50000),
        mode: ChannelGroupMode.category,
        openGroupKey: open,
        flattened: false,
      );
      // 97 heads + the open group's rows.
      expect(descs.length, greaterThan(97));
      final List<ChannelDescriptor> flat = ChannelGrouping.descriptors(
        items: items,
        filtered: _all(50000),
        mode: ChannelGroupMode.flat,
        openGroupKey: null,
        flattened: false,
      );
      expect(flat, hasLength(50000));
    });
  });

  group('ChannelGrouping.membersOf', () {
    final List<QueueItem> items = <QueueItem>[
      _ch('u0', 'AAA', group: 'News'),
      _ch('u1', 'M1', group: 'Music'),
      _ch('u2', 'N2', group: 'News'),
      _ch('u3', 'M2', group: 'Music'),
      _ch('u4', 'M3', group: 'Music'),
    ];

    test('returns the open group in raw list order', () {
      final String? music =
          ChannelGrouping.keyFor(items, 1, ChannelGroupMode.category);
      expect(
          ChannelGrouping.membersOf(items, ChannelGroupMode.category, music!),
          <int>[1, 3, 4]);
      final String? news =
          ChannelGrouping.keyFor(items, 0, ChannelGroupMode.category);
      expect(
          ChannelGrouping.membersOf(items, ChannelGroupMode.category, news!),
          <int>[0, 2]);
    });

    test('flat and stale keys yield no members (raw stepping resumes)', () {
      expect(
          ChannelGrouping.membersOf(items, ChannelGroupMode.flat, 'x'),
          isEmpty);
      expect(
          ChannelGrouping.membersOf(
              items, ChannelGroupMode.category, 'category\u0000Nope'),
          isEmpty);
    });
  });

  group('ChannelGrouping.stepTarget', () {
    // Raw order: News AAA(0), Music M1(1), News N2(2), Music M2(3).
    const List<int> music = <int>[1, 3];
    const int count = 4;

    test('steps within the open group, never leaving it', () {
      expect(
          ChannelGrouping.stepTarget(
              members: music, from: 1, direction: 1, count: count),
          3);
      expect(
          ChannelGrouping.stepTarget(
              members: music, from: 3, direction: -1, count: count),
          1);
    });

    test('group edges park — they never wrap or escape the group', () {
      expect(
          ChannelGrouping.stepTarget(
              members: music, from: 3, direction: 1, count: count),
          isNull);
      expect(
          ChannelGrouping.stepTarget(
              members: music, from: 1, direction: -1, count: count),
          isNull);
    });

    test('from outside the group, Next takes its first, Prev its last', () {
      // Playing news AAA(0) while browsing Music: Next enters at M1.
      expect(
          ChannelGrouping.stepTarget(
              members: music, from: 0, direction: 1, count: count),
          1);
      // Previous enters from the other edge, at M2.
      expect(
          ChannelGrouping.stepTarget(
              members: music, from: 0, direction: -1, count: count),
          3);
    });

    test('no open group steps plain raw order (flat behaviour)', () {
      expect(
          ChannelGrouping.stepTarget(
              members: const <int>[], from: 1, direction: 1, count: count),
          2);
      expect(
          ChannelGrouping.stepTarget(
              members: const <int>[], from: 1, direction: -1, count: count),
          0);
      // Head and tail park, never wrap.
      expect(
          ChannelGrouping.stepTarget(
              members: const <int>[], from: 3, direction: 1, count: count),
          isNull);
      expect(
          ChannelGrouping.stepTarget(
              members: const <int>[], from: 0, direction: -1, count: count),
          isNull);
    });
  });
}
