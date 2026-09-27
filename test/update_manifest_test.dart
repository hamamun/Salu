import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/updater/update_manifest.dart';

/// The updater's model half (updater.md §3 step 2, §8): version comparison
/// across the three feeds' shapes, the `versions.json` / `manifest.json`
/// document, and the check table's flag rules.

void main() {
  group('compareUpdateVersions', () {
    test('numeric segments compare as numbers, not text', () {
      // The pair updater.md §4's own example implies — and the one a
      // string compare gets backwards:
      expect(
          compareUpdateVersions('1.0.1210.39', '1.0.864.35') > 0, isTrue,
          reason: '1210 > 864 even though "1210" < "864" as text');
      expect(compareUpdateVersions('1.0.3065.39', '1.0.1210.39') > 0, isTrue);
      expect(compareUpdateVersions('1.0.864.35', '1.0.3065.39') < 0, isTrue);
    });

    test('equal versions compare equal', () {
      expect(compareUpdateVersions('1.0.1210.39', '1.0.1210.39'), 0);
      expect(compareUpdateVersions('2026.08.19', '2026.08.19'), 0);
    });

    test('date-like versions order by date', () {
      expect(compareUpdateVersions('2024.09.20', '2024.08.06') > 0, isTrue);
      expect(compareUpdateVersions('2026.08.19', '2025.12.31') > 0, isTrue);
    });

    test('the libmpv build tags order as plain numbers', () {
      expect(compareUpdateVersions('20250101', '20241021') > 0, isTrue);
      expect(compareUpdateVersions('20241021', '20241021'), 0);
    });

    test('a leading v is ignored', () {
      expect(compareUpdateVersions('v1.2.3', '1.2.3'), 0);
      expect(compareUpdateVersions('v1.2.4', '1.2.3') > 0, isTrue);
    });

    test('a pre-release sorts below the plain release', () {
      expect(
          compareUpdateVersions('1.0.3065.39-rc.1', '1.0.3065.39') < 0, isTrue);
      expect(
          compareUpdateVersions('1.0.3065.39', '1.0.3065.39-rc.1') > 0, isTrue);
      expect(
          compareUpdateVersions('1.0.3065.39-rc.1', '1.0.3065.39-rc.2') < 0,
          isTrue);
    });

    test('a longer version outranks its shorter equal prefix', () {
      expect(compareUpdateVersions('1.0.1', '1.0') > 0, isTrue);
      expect(compareUpdateVersions('1.0', '1.0.0'), 0);
    });

    test('build metadata never affects precedence', () {
      expect(compareUpdateVersions('1.2.3+42', '1.2.3'), 0);
    });
  });

  group('UpdateManifest', () {
    test('round-trips through JSON', () {
      final UpdateManifest original = UpdateManifest(<UpdateComponent, String>{
        UpdateComponent.webView2Loader: '1.0.3065.39',
        UpdateComponent.mpvEngine: '20241021',
        UpdateComponent.ytDlp: '2026.08.19',
      });
      final UpdateManifest parsed =
          UpdateManifest.tryParse(original.toJsonString());
      expect(parsed.components, original.components);
    });

    test('records each component\'s target file with its version', () {
      final String json = const UpdateManifest(<UpdateComponent, String>{
        UpdateComponent.ytDlp: '2026.08.19',
      }).toJsonString();
      expect(json, contains('yt-dlp.exe'));
      expect(json, contains('2026.08.19'));
      expect(json, contains('ytdlp'));
    });

    test('copyWith overrides only the staged components', () {
      final UpdateManifest merged =
          const UpdateManifest(<UpdateComponent, String>{
        UpdateComponent.webView2Loader: '1.0.1210.39',
        UpdateComponent.mpvEngine: '20241021',
      }).copyWith(<UpdateComponent, String>{
        UpdateComponent.ytDlp: '2026.08.19',
      });
      expect(merged.components[UpdateComponent.webView2Loader], '1.0.1210.39');
      expect(merged.components[UpdateComponent.mpvEngine], '20241021');
      expect(merged.components[UpdateComponent.ytDlp], '2026.08.19');
    });

    test('malformed stores degrade to empty, never throw', () {
      expect(UpdateManifest.tryParse('').components, isEmpty);
      expect(UpdateManifest.tryParse('not json').components, isEmpty);
      expect(UpdateManifest.tryParse('[]').components, isEmpty);
      expect(UpdateManifest.tryParse('{"components": 3}').components, isEmpty);
      expect(
        UpdateManifest.tryParse('{"components": {"ytdlp": {"file": "x"}}}')
            .components,
        isEmpty,
      );
    });

    test('unknown keys and foreign noise are ignored', () {
      final UpdateManifest parsed = UpdateManifest.tryParse('''
      {
        "schema": 1,
        "extra": true,
        "components": {
          "webview2": {"file": "WebView2Loader.dll", "version": " 1.0.3065.39 "},
          "future_thing": {"file": "x.dll", "version": "9"},
          "mpv": {"file": "libmpv-2.dll", "version": ""}
        }
      }
      ''');
      expect(parsed.components, <UpdateComponent, String>{
        UpdateComponent.webView2Loader: '1.0.3065.39',
      });
    });
  });

  group('check table flags', () {
    ComponentStatus status({
      String? installed,
      String latest = '2.0.0',
    }) {
      final bool available =
          installed == null || compareUpdateVersions(latest, installed) > 0;
      return ComponentStatus(
        component: UpdateComponent.mpvEngine,
        installed: installed,
        latest: latest,
        downloadUrl: 'https://example.test/file',
        updateAvailable: available,
      );
    }

    test('a newer remote flags an update', () {
      expect(status(installed: '1.0.0').updateAvailable, isTrue);
    });

    test('the same version is current', () {
      expect(status(installed: '2.0.0').updateAvailable, isFalse);
    });

    test('a newer local (pin ahead of the feed) is current', () {
      expect(status(installed: '3.0.0').updateAvailable, isFalse);
    });

    test('an untracked install is offered the update', () {
      expect(status(installed: null).updateAvailable, isTrue);
    });

    test('pendingUpdates collects exactly the flagged rows', () {
      final UpdateCheckResult result = UpdateCheckResult(
        ok: true,
        checkedAt: DateTime.fromMillisecondsSinceEpoch(1000),
        components: <ComponentStatus>[
          status(installed: '2.0.0'),
          status(installed: '1.0.0'),
        ],
      );
      expect(result.hasUpdates, isTrue);
      expect(result.pendingUpdates, hasLength(1));
      expect(result.pendingUpdates.single.fromVersion, '1.0.0');
      expect(result.pendingUpdates.single.toVersion, '2.0.0');
      expect(result.pendingUpdates.single.fileName, 'libmpv-2.dll');
    });

    test('a failed check claims nothing', () {
      final UpdateCheckResult result = UpdateCheckResult(
        ok: false,
        checkedAt: DateTime.fromMillisecondsSinceEpoch(1000),
      );
      expect(result.hasUpdates, isFalse);
      expect(result.pendingUpdates, isEmpty);
    });
  });

  group('display text', () {
    test('byte sizes match the modal copy\'s units', () {
      expect(formatUpdateBytes(999), '999 B');
      expect(formatUpdateBytes(2800), '2.8 KB');
      expect(formatUpdateBytes(1200 * 1000), '1.2 MB');
      expect(formatUpdateBytes(2800 * 1000), '2.8 MB');
      expect(formatUpdateBytes(1500 * 1000 * 1000), '1.5 GB');
    });

    test('last-checked phrasing walks from Just now to the date', () {
      final DateTime now = DateTime(2026, 9, 26, 12);
      expect(formatLastChecked(now, now), 'Just now');
      expect(formatLastChecked(now, now.subtract(const Duration(minutes: 5))),
          '5 min ago');
      expect(
          formatLastChecked(now, now.subtract(const Duration(hours: 3))),
          '3 h ago');
      expect(
          formatLastChecked(now, DateTime(2026, 9, 25, 23)),
          'Yesterday');
      expect(formatLastChecked(now, DateTime(2026, 9, 20, 9)), '6 days ago');
      expect(formatLastChecked(now, DateTime(2026, 7, 4, 9)), '4 Jul 2026');
    });
  });
}
