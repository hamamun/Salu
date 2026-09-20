import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/remote/remote_pairing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pairing codes are read off a screen and typed by a human, so this file
/// exists to pin the two rules that make that bearable: the alphabet avoids
/// ambiguous glyphs, and normalization forgives everything else.
///
/// The second rule was broken until 2026-09-20 — see the regression group at
/// the bottom, which is the reason `normalizePairingCode` no longer uses a raw
/// character-class regex.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the alphabet', () {
    test('has no glyph that reads as another', () {
      for (final String glyph in <String>['0', 'O', '1', 'I', 'L']) {
        expect(
          remotePairingAlphabet.contains(glyph),
          isFalse,
          reason: '"$glyph" is ambiguous on a screen and on a keyboard',
        );
      }
    });

    test('a generated code is eight characters, all from the alphabet', () {
      for (int i = 0; i < 200; i++) {
        final String code = generatePairingCode();
        expect(code.length, 8);
        for (final int unit in code.codeUnits) {
          expect(remotePairingAlphabet.contains(String.fromCharCode(unit)), isTrue);
        }
      }
    });
  });

  group('formatPairingCode', () {
    test('splits 4+4 for reading aloud', () {
      expect(formatPairingCode('7K4MQP2X'), '7K4M-QP2X');
    });

    test('is idempotent and tolerates what a user types', () {
      expect(formatPairingCode('7k4m-qp2x'), '7K4M-QP2X');
      expect(formatPairingCode(' 7K4M-QP2X '), '7K4M-QP2X');
    });
  });

  group('normalizePairingCode', () {
    test('drops dashes, spaces, case and any stray character', () {
      const String canonical = '7K4MQP2X';
      for (final String typed in <String>[
        '7K4M-QP2X',
        '7k4m-qp2x',
        '7K4M QP2X',
        ' 7k4m qp2x ',
        '7K4M–QP2X', // en dash, from a phone keyboard's autocorrect
        '7K4M.QP2X',
      ]) {
        expect(normalizePairingCode(typed), canonical, reason: 'typed: $typed');
      }
    });
  });

  group('RemotePairing.accepts', () {
    test('accepts its own code in every shape a user can produce', () {
      final RemotePairing pairing = RemotePairing();
      pairing.openPanel();
      final String code = pairing.code;

      expect(pairing.accepts(code), isTrue);
      expect(pairing.accepts(code.toLowerCase()), isTrue);
      expect(pairing.accepts(formatPairingCode(code)), isTrue);
      expect(pairing.accepts(' $code '), isTrue);
      expect(pairing.accepts('XXXX-XXXX'), isFalse);
    });

    test('rotating closes the old code and opening the panel does not', () {
      final RemotePairing pairing = RemotePairing();
      pairing.openPanel();
      final String first = pairing.code;
      pairing.openPanel();
      expect(pairing.code, first, reason: 'a scan in progress must not be sabotaged');

      pairing.pairedSuccessfully();
      expect(pairing.code, isNot(first), reason: 'A5: one code, one pairing');

      final String second = pairing.code;
      pairing.closePanel();
      expect(pairing.code, isNot(second), reason: 'A5: closing the panel rotates');
      expect(pairing.accepts(second), isFalse);
    });
  });

  group('device tokens', () {
    test('are 32 random bytes, base64url, unpadded, and never repeat', () {
      final String a = generateDeviceToken();
      final String b = generateDeviceToken();
      expect(a, isNot(b));
      expect(a.length, 43); // 32 bytes → 43 base64url chars with padding removed
      expect(a.contains('='), isFalse);
      expect(a.contains('+'), isFalse);
      expect(a.contains('/'), isFalse);
    });

    test('the store keeps hashes, never the token itself', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final RemoteDeviceStore store = RemoteDeviceStore();
      await store.load();

      const String token = 'a-token-that-must-not-be-stored';
      await store.remember(
        id: 'abc123',
        name: 'Pixel 7',
        platform: 'android',
        token: token,
      );

      final RemoteDevice? found = store.find('abc123');
      expect(found, isNotNull);
      expect(found!.tokenHash, hashDeviceToken(token));
      expect(found.tokenHash, isNot(token));

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(RemoteDeviceStore.preferencesKey), isNot(contains(token)));

      expect(store.findByToken(token)?.id, 'abc123');
      expect(store.findByToken('some other token'), isNull);

      await store.forget('abc123');
      expect(store.find('abc123'), isNull);
      expect(store.findByToken(token), isNull, reason: 'a forgotten phone gets bad_token');
    });
  });

  // ── the regression that made a random code in 31 unpairable ────────────────
  group('regression: the raw-string character class', () {
    test('a code containing S survives normalization', () {
      // The old body was `code.replaceAll(RegExp(r'[-\\s]'), '').toUpperCase()`.
      // In a raw string that class is `-`, backslash and the letter `s` — so it
      // stripped S from the *candidate* while the stored code kept it, and any
      // code containing an S could never be accepted. It looked like flakiness
      // because only ~1 code in 31 was affected.
      expect(normalizePairingCode('SALU2345'), 'SALU2345');
      expect(normalizePairingCode('7K4M-SP2X'), '7K4MSP2X');
      expect(normalizePairingCode('salu2345'), 'SALU2345');
    });

    test('every code the generator can produce is acceptable to itself', () {
      // Belt and braces: 4000 generated codes, each re-read in the worst way a
      // human could present it.
      for (int i = 0; i < 4000; i++) {
        final String code = generatePairingCode();
        expect(normalizePairingCode(formatPairingCode(code)), code);
        expect(normalizePairingCode(code.toLowerCase()), code);
      }
    });
  });
}
