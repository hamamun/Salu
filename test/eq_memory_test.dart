import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/tune/eq_memory.dart';

/// The Auto EQ learning map's data policy (eq_imp.md §5) — the part that has
/// to be true because it is the one thing SALU keeps *about the person*, not
/// about a file:
///
///   · it grows with kinds of content, never with plays;
///   · 500 entries maximum, the least-recently-used one evicted;
///   · anything untouched for 90 days is gone at app start;
///   · a tap in Settings wipes it, and the Undo toast puts the exact
///     snapshot back.
///
/// All of that is pure Dart on purpose (the service owns the disk write), so
/// all of it is checkable here.
void main() {
  final DateTime now = DateTime.utc(2026, 3, 1, 12);

  group('the map itself', () {
    test('an unknown key answers nothing, and teaching makes it known', () {
      final EqMemory m = EqMemory.empty();
      expect(m.isEmpty, isTrue);
      expect(m.presetFor('audio|jazz'), isNull);
      m.teach('audio|jazz', 'jazz', now: now);
      expect(m.presetFor('audio|jazz'), 'jazz');
      expect(m.length, 1);
      expect(m.entryFor('audio|jazz')?.usedAtMs, now.millisecondsSinceEpoch);
    });

    test('a kept choice replaces the old one and refreshes its time', () {
      final EqMemory m = EqMemory.empty();
      m.teach('audio|jazz', 'jazz', now: now.subtract(const Duration(days: 5)));
      m.teach('audio|jazz', 'blues', now: now);
      expect(m.length, 1);
      expect(m.presetFor('audio|jazz'), 'blues');
      expect(m.entryFor('audio|jazz')?.usedAtMs, now.millisecondsSinceEpoch);
    });

    test('a pick only touches the time — it never rewrites the choice', () {
      final EqMemory m = EqMemory.empty();
      m.teach('video|the news', 'documentary', now: now);
      final int before = m.entryFor('video|the news')!.usedAtMs;
      m.touch('video|the news', now: now.add(const Duration(days: 1)));
      expect(m.presetFor('video|the news'), 'documentary');
      expect(m.entryFor('video|the news')!.usedAtMs,
          greaterThan(before));
      // A key nobody taught is not created by a touch.
      m.touch('audio|unknown', now: now);
      expect(m.presetFor('audio|unknown'), isNull);
    });
  });

  group('the LRU cap (§5)', () {
    test('500 entries is the ceiling — the oldest ask goes first', () {
      final EqMemory m = EqMemory.empty();
      for (int i = 0; i <= EqMemory.maxEntries; i++) {
        m.teach('audio|g$i', 'pop',
            now: now.add(Duration(minutes: i)));
      }
      expect(m.length, EqMemory.maxEntries);
      expect(m.presetFor('audio|g0'), isNull);
      expect(m.presetFor('audio|g1'), 'pop');
      expect(m.presetFor('audio|g${EqMemory.maxEntries}'), 'pop');
    });

    test('reading a key does not save it from eviction, touching does', () {
      final EqMemory m = EqMemory.empty();
      for (int i = 0; i < EqMemory.maxEntries; i++) {
        m.teach('video|s$i', 'movie', now: now.add(Duration(minutes: i)));
      }
      // The oldest entry is refreshed, then the map grows by one: the one
      // that leaves is now the *second* oldest.
      m.touch('video|s0', now: now + const Duration(hours: 1));
      m.teach('video|new', 'documentary', now: now + const Duration(hours: 2));
      expect(m.length, EqMemory.maxEntries);
      expect(m.presetFor('video|s0'), 'movie');
      expect(m.presetFor('video|s1'), isNull);
      expect(m.presetFor('video|new'), 'documentary');
    });
  });

  group('the 90-day prune (§5)', () {
    test('stale taste is dropped, fresh taste stays', () {
      final EqMemory m = EqMemory.empty();
      m.teach('a', 'pop', now: now.subtract(const Duration(days: 91)));
      m.teach('b', 'rock', now: now.subtract(const Duration(days: 89)));
      m.teach('c', 'jazz', now: now.subtract(const Duration(days: 90)));
      final int gone = m.pruneStale(now: now);
      expect(gone, 2); // 91 days and exactly 90 are both "or longer"
      expect(m.keys.toList(), <String>['b']);
    });

    test('an empty map prunes to nothing, twice over', () {
      final EqMemory m = EqMemory.empty();
      expect(m.pruneStale(now: now), 0);
      m.teach('a', 'pop', now: now);
      expect(m.pruneStale(now: now), 0);
      expect(m.length, 1);
    });
  });

  group('the wire format', () {
    test('encode → decode is the same map, entries and times included', () {
      final EqMemory m = EqMemory.empty();
      m.teach('audio|jazz', 'jazz', now: now);
      m.teach('video|the news', 'documentary', now: now);
      final EqMemory back = EqMemory.decode(m.encode());
      expect(back.length, 2);
      expect(back.presetFor('audio|jazz'), 'jazz');
      expect(back.entryFor('video|the news')?.usedAtMs,
          now.millisecondsSinceEpoch);
    });

    test('the blob is small — about 100 bytes an entry, as promised', () {
      final EqMemory m = EqMemory.empty();
      for (int i = 0; i < 20; i++) {
        m.teach('audio|genre $i', 'lounge', now: now);
      }
      final int bytes = utf8.encode(m.encode()).length;
      expect(bytes ~/ 20, lessThan(160));
    });

    test('garbage decodes to an empty map, never a throw', () {
      for (final Object? raw in <Object?>[
        null,
        '',
        'nope',
        '{',
        '[]',
        '{"audio|jazz": "just a string"}',
        '{"audio|jazz": [null, null]}',
        '{"": ["pop", 1]}',
        jsonEncode(<String, Object?>{'audio|jazz': 7}),
      ]) {
        expect(EqMemory.decode(raw).isEmpty, isTrue, reason: '$raw');
      }
      // A half-good blob keeps the good rows.
      final EqMemory mixed = EqMemory.decode(jsonEncode(
          <String, List<Object>>{'audio|rock': <Object>['rock', 1]}));
      expect(mixed.presetFor('audio|rock'), 'rock');
      // A row whose TIME is unreadable still keeps the choice, at 0 — and a
      // zero clock means the next app start prunes it as stale. A broken
      // stamp never deletes what a person chose, and never lasts.
      final EqMemory stale =
          EqMemory.decode('{"audio|jazz": ["pop","soon"]}');
      expect(stale.presetFor('audio|jazz'), 'pop');
      expect(stale.pruneStale(), 1);
      expect(stale.isEmpty, isTrue);
      // The older map shape (`{"preset": …, "used": …}`) still loads.
      expect(
        EqMemory.decode('{"audio|blues": {"preset": "blues", "used": 5}}')
            .presetFor('audio|blues'),
        'blues',
      );
    });
  });

  group('clear and undo (the Settings row)', () {
    test('a snapshot survives a clear and restores exactly', () {
      final EqMemory m = EqMemory.empty();
      m.teach('a', 'pop', now: now);
      m.teach('b', 'rock', now: now);
      final Map<String, EqMemoryEntry> previous = m.snapshot();
      m.clear();
      expect(m.isEmpty, isTrue);
      m.restore(previous);
      expect(m.length, 2);
      expect(m.presetFor('a'), 'pop');
      expect(m.presetFor('b'), 'rock');
    });

    test('a restored oversized map is capped again, not trusted', () {
      final EqMemory m = EqMemory.empty();
      final Map<String, EqMemoryEntry> big = <String, EqMemoryEntry>{};
      for (int i = 0; i < EqMemory.maxEntries + 5; i++) {
        big['k$i'] = EqMemoryEntry(presetKey: 'pop', usedAtMs: i);
      }
      m.restore(big);
      expect(m.length, EqMemory.maxEntries);
      expect(m.presetFor('k0'), isNull); // the oldest by time went first
    });

    test('removing one entry leaves the rest', () {
      final EqMemory m = EqMemory.empty();
      m.teach('a', 'pop', now: now);
      m.teach('b', 'rock', now: now);
      m.remove('a');
      expect(m.keys.toList(), <String>['b']);
      m.remove('nothing here');
      expect(m.length, 1);
    });
  });
}
