import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/settings_service.dart';

/// The persisted-password scramble (cc.md D13 AMENDED, owner 2026-09-13).
///
/// These are the guarantees the Settings → Subtitles password field silently
/// depends on: what goes in must come back out byte-for-byte on the next
/// launch (or every restart is the "`/download` is dead" bug all over again),
/// what lands in the prefs file must not be the password, and anything
/// corrupt must degrade to the signed-out state rather than throw during
/// `SettingsService.load()` — which runs before the first frame.
void main() {
  group('SubtitleScramble round-trip', () {
    test('a plain ASCII password comes back exactly', () {
      const String password = 'hunter2';
      expect(
        SubtitleScramble.decode(SubtitleScramble.encode(password)),
        password,
      );
    });

    test('the awkward shapes a real password can have come back exactly', () {
      const List<String> passwords = <String>[
        ' leading and trailing ', // NOT trimmed on purpose — it is literal
        'p@ss!w0rd#\$%&*()_+-=[]{};:,.<>?/|~`^',
        'CorrectHorseBatteryStaple99',
        'p@ss <word> & "quotes"', // XML-hostile characters
        'বাংলা পাসওয়ার্ড', // non-ASCII → utf8 must survive the trip
        'mixed 😀 emoji', // a 4-byte code point
        'a', // one byte
        '0123456789' * 12, // long
      ];
      for (final String password in passwords) {
        expect(
          SubtitleScramble.decode(SubtitleScramble.encode(password)),
          password,
          reason: 'round-trip failed for a ${password.length}-char password',
        );
      }
    });

    test('an empty password round-trips to empty (signed out)', () {
      expect(SubtitleScramble.decode(SubtitleScramble.encode('')), '');
    });
  });

  group('SubtitleScramble.encode', () {
    test('the stored blob never contains the password itself', () {
      const String password = 'SuperSecret123';
      final String stored = SubtitleScramble.encode(password);
      expect(stored.contains(password), isFalse);
      expect(stored.contains('Super'), isFalse);
      expect(stored.contains('Secret'), isFalse);
    });

    test('the blob is base64 — safe inside the prefs XML on Windows', () {
      final String stored =
          SubtitleScramble.encode('p@ss <word> & "quotes" \u0001\u0002');
      expect(RegExp(r'^[A-Za-z0-9+/=]*$').hasMatch(stored), isTrue);
      expect(
        SubtitleScramble.decode(stored),
        'p@ss <word> & "quotes" \u0001\u0002',
      );
    });

    test('the same password never stores the same blob twice', () {
      // The 8-byte nonce in front of each blob is what stops the keystream
      // being reused — so two identical passwords (and two passwords
      // sharing a prefix) share nothing in the file.
      const String password = 'abcdef-repeated';
      final String a = SubtitleScramble.encode(password);
      final String b = SubtitleScramble.encode(password);
      expect(a, isNot(b));
      expect(SubtitleScramble.decode(a), password);
      expect(SubtitleScramble.decode(b), password);
    });

    test('passwords sharing a prefix do not share a blob prefix', () {
      final String a = SubtitleScramble.encode('abcdef-one');
      final String b = SubtitleScramble.encode('abcdef-two');
      expect(a, isNot(b));
      expect(SubtitleScramble.decode(a), 'abcdef-one');
      expect(SubtitleScramble.decode(b), 'abcdef-two');
    });
  });

  group('SubtitleScramble.decode', () {
    test('an empty stored value decodes to empty, never throws', () {
      expect(SubtitleScramble.decode(''), '');
    });

    test('corrupt or hand-edited prefs degrade to empty, never throw', () {
      const List<String> junk = <String>[
        'not-base64-at-all!!', // not base64
        '###', // not base64
        'aGVsbG8=', // valid base64, shorter than the nonce
        'AAAA', // valid base64, shorter than the nonce
        'AAAAAAAAAAA=', // nonce-length but never scrambled by SALU
      ];
      for (final String stored in junk) {
        expect(
          () => SubtitleScramble.decode(stored),
          returnsNormally,
          reason: 'decode("$stored") threw',
        );
      }
      expect(SubtitleScramble.decode('not-base64-at-all!!'), '');
      expect(SubtitleScramble.decode('aGVsbG8='), '');
    });

    test('the salt is a fixed, documented constant', () {
      // Changing it silently signs every viewer out on their next launch —
      // the safe failure, but it must never happen by accident.
      expect(SubtitleScramble.salt, 'SALU-subtitle-password-v1');
    });
  });
}
