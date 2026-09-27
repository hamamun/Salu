import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/updater/nuget_client.dart';

import 'updater_test_support.dart';

/// The NuGet half (updater.md §4): highest-stable selection out of the
/// flat-container index, package URL shape, and `.nupkg` unzipping — the
/// ZIP reader's STORED + DEFLATE + CRC paths, all against real archive
/// bytes from the test builder.

void main() {
  group('pickHighestStable', () {
    test('takes the highest stable, not the last entry', () {
      // Registration order usually ascends — but not always; the pick is
      // computed either way.
      const String index = '{"versions": ["1.0.3065.39", "1.0.1210.39", "1.0.864.35"]}';
      expect(NugetClient.pickHighestStable(index), '1.0.3065.39');
    });

    test('filters pre-release tags (updater.md §4 step 1)', () {
      const String index = '{"versions": ["1.0.2903.40", "1.0.3065.39-rc", "1.0.3065.39-prerelease"]}';
      expect(NugetClient.pickHighestStable(index), '1.0.2903.40');
    });

    test('handles the doc\'s own example list', () {
      const String index = '''
      {
        "versions": [
          "1.0.864.35",
          "1.0.1210.39",
          "1.0.2903.40",
          "1.0.3065.39"
        ]
      }''';
      expect(NugetClient.pickHighestStable(index), '1.0.3065.39');
    });

    test('numeric ordering beats lexicographic', () {
      const String index = '{"versions": ["1.0.864.35", "1.0.1210.39"]}';
      expect(NugetClient.pickHighestStable(index), '1.0.1210.39');
    });

    test('empty or malformed feeds answer null', () {
      expect(NugetClient.pickHighestStable('{"versions": []}'), isNull);
      expect(NugetClient.pickHighestStable('not json'), isNull);
      expect(NugetClient.pickHighestStable('{"versions": ["1.0.1-rc"]}'), isNull);
      expect(NugetClient.pickHighestStable('{}'), isNull);
    });
  });

  group('packageUrlFor', () {
    test('follows the flat-container shape with lowercased parts', () {
      expect(
        NugetClient.packageUrlFor('1.0.3065.39').toString(),
        'https://api.nuget.org/v3-flatcontainer/microsoft.web.webview2/'
        '1.0.3065.39/microsoft.web.webview2.1.0.3065.39.nupkg',
      );
    });

    test('lowercases the version the way the container demands', () {
      expect(
        NugetClient.packageUrlFor('1.0.3065.39-RC').toString(),
        contains('/1.0.3065.39-rc/microsoft.web.webview2.1.0.3065.39-rc.nupkg'),
      );
    });
  });

  group('extractLoaderDll', () {
    test('pulls the x64 loader out of a deflated package', () {
      final List<int> dll = fakePeImage();
      final List<int> nupkg = buildFakeNupkg(loaderDll: dll);
      expect(NugetClient.extractLoaderDll(nupkg), dll);
    });

    test('pulls the x64 loader out of a stored package too', () {
      final List<int> dll = fakePeImage();
      final List<int> nupkg = buildFakeNupkg(loaderDll: dll, deflate: false);
      expect(NugetClient.extractLoaderDll(nupkg), dll);
    });

    test('never answers the x86 decoy\'s bytes', () {
      final List<int> dll = fakePeImage();
      final List<int> nupkg = buildFakeNupkg(loaderDll: dll);
      final List<int>? extracted = NugetClient.extractLoaderDll(nupkg);
      expect(extracted, isNotNull);
      expect(extracted, dll);
      // The decoy is a different image — equality is the check.
      expect(extracted, isNot(fakePeImage(machine: 0x014c)));
    });

    test('a package without the loader answers null', () {
      final List<int> nupkg = buildFakeNupkg(includeLoader: false);
      expect(NugetClient.extractLoaderDll(nupkg), isNull);
    });

    test('garbage bytes answer null, never throw', () {
      expect(NugetClient.extractLoaderDll(<int>[1, 2, 3]), isNull);
      expect(NugetClient.extractLoaderDll(<int>[]), isNull);
      expect(NugetClient.extractLoaderDll('MZ hello'.codeUnits), isNull);
    });

    test('a corrupted entry fails the ZIP CRC check', () {
      final List<int> dll = fakePeImage();
      // Single-entry archive: local header (30) + name, then the payload.
      final List<int> nupkg = buildZipArchive(<String, List<int>>{
        NugetClient.dllEntryPath: dll,
      });
      final int dataStart = 30 + NugetClient.dllEntryPath.length;
      final List<int> corrupted = List<int>.of(nupkg);
      corrupted[dataStart + 4] ^= 0xFF;
      expect(
        NugetClient.extractLoaderDll(corrupted),
        isNull,
        reason: 'a payload that fails its stored CRC-32 must be refused',
      );
    });
  });
}
