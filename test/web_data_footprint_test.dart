import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/web/web_data_control.dart';

void main() {
  group('WebDataControlService formatting & footprint', () {
    test('formatBytes formats zero and boundary values cleanly', () {
      expect(WebDataControlService.formatBytes(0), '0 B');
      expect(WebDataControlService.formatBytes(-50), '0 B');
      expect(WebDataControlService.formatBytes(512), '512 B');
      expect(WebDataControlService.formatBytes(1024), '1 KB');
      expect(WebDataControlService.formatBytes(1536), '1.5 KB');
      expect(WebDataControlService.formatBytes(1048576), '1 MB');
      expect(WebDataControlService.formatBytes(15728640), '15 MB');
      expect(WebDataControlService.formatBytes(1073741824), '1 GB');
    });

    test('WebDataFootprint returns expected labels', () {
      const WebDataFootprint emptyFp = WebDataFootprint(
        historyCount: 0,
        historyBytes: 0,
        cookiesBytes: 0,
        cacheBytes: 0,
      );
      expect(emptyFp.historyLabel, 'None');
      expect(emptyFp.cookiesLabel, 'None');
      expect(emptyFp.cacheLabel, 'None');

      const WebDataFootprint populatedFp = WebDataFootprint(
        historyCount: 1,
        historyBytes: 120,
        cookiesBytes: 4096,
        cacheBytes: 25000000,
      );
      expect(populatedFp.historyLabel, '1 item');
      expect(populatedFp.cookiesLabel, '4 KB');
      expect(populatedFp.cacheLabel, '24 MB');

      const WebDataFootprint multipleHistory = WebDataFootprint(
        historyCount: 42,
      );
      expect(multipleHistory.historyLabel, '42 items');
    });

    test('WebDataFootprint reports cleaned stores while a purge is queued',
        () {
      // A pending purge promises the locked stores to the next startup, so
      // the measurement zeroes them and the dialog explains the queue.
      const WebDataFootprint fp = WebDataFootprint(
        historyCount: 0,
        cookiesBytes: 0,
        cacheBytes: 0,
        profilePurgePending: true,
      );
      expect(fp.cookiesLabel, 'None');
      expect(fp.cacheLabel, 'None');
      expect(fp.profilePurgePending, isTrue);

      const WebDataFootprint measured = WebDataFootprint();
      expect(measured.profilePurgePending, isFalse);
    });
  });

  group('WebDataControlService profile store classification', () {
    test('cache stores are recognised by name, wherever they sit', () {
      for (final String name in <String>[
        'cache',
        'Cache',
        'Code Cache',
        'GPUCache',
        'ShaderCache',
        'DawnCache',
      ]) {
        expect(
          WebDataControlService.classifyProfileEntry(name.toLowerCase(),
              isDirectory: true),
          WebProfileStoreKind.cache,
          reason: name,
        );
      }
    });

    test('cookies & site-data stores are recognised by name', () {
      for (final String name in <String>[
        'local storage',
        'Session Storage',
        'IndexedDB',
        'databases',
        'Service Worker',
        'Shared Storage',
      ]) {
        expect(
          WebDataControlService.classifyProfileEntry(name.toLowerCase(),
              isDirectory: true),
          WebProfileStoreKind.siteData,
          reason: name,
        );
      }
      for (final String file in <String>[
        'Cookies',
        'Cookies-journal',
        'Cookies-wal',
        'Cookies-shm',
      ]) {
        expect(
          WebDataControlService.classifyProfileEntry(file.toLowerCase(),
              isDirectory: false),
          WebProfileStoreKind.siteData,
          reason: file,
        );
      }
    });

    test('runtime internals and look-alikes never count as browsing data',
        () {
      // Whole-profile leftovers that once inflated the "cookies" badge.
      for (final String name in <String>[
        'Crashpad',
        'ComponentExtensions',
        'SmartScreen',
        'Default',
        'EBWebView',
        'CacheStorage', // Service Worker cache lives inside site data
      ]) {
        expect(
          WebDataControlService.classifyProfileEntry(name.toLowerCase(),
              isDirectory: true),
          WebProfileStoreKind.none,
          reason: name,
        );
      }
      for (final String file in <String>[
        'Preferences',
        'Local State',
        'History',
        'cache', // a bare FILE named cache is not a store
      ]) {
        expect(
          WebDataControlService.classifyProfileEntry(file.toLowerCase(),
              isDirectory: false),
          WebProfileStoreKind.none,
          reason: file,
        );
      }
    });
  });
}
