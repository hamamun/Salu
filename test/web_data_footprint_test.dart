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
  });
}
