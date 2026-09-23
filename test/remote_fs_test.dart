import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:salu/core/remote/remote_fs_service.dart';

/// The `fs_places` drive scan (pc_part.md §1–§9) — the contract that keeps
/// a disconnected mapped drive from stalling the phone's Files tab:
///
///  · the letters and their kinds come from the Win32 drive TABLE
///    ([RemoteFsService.classifyDrives] fed a fake table — no I/O in
///    sight), with `DRIVE_REMOTE` and `DRIVE_NO_ROOT_DIR` letters dropped
///    before any label read could happen;
///  · a label read that fails (no media) hides the drive, and an empty
///    label falls back to Explorer's names;
///  · network-backed places (UNC, or a `DRIVE_REMOTE` root) are skipped
///    silently — the table is consulted, the path never probed;
///  · and the read-only listing rules the phone already relies on: the
///    media/subs filters, the system-folder hide, paging, path
///    validation — and no write API.
void main() {
  // The one fake table the whole group shares: A..Z all present, C fixed,
  // E removable, F cdrom, R ramdisk; W and Z network, N no root, the rest
  // unknown.
  int _fakeTypeOf(String root) => switch (root) {
        'C:\\' => RemoteFsService.driveTypeFixed,
        'E:\\' => RemoteFsService.driveTypeRemovable,
        'F:\\' => RemoteFsService.driveTypeCdrom,
        'R:\\' => RemoteFsService.driveTypeRamdisk,
        'W:\\' => RemoteFsService.driveTypeRemote,
        'Z:\\' => RemoteFsService.driveTypeRemote,
        'N:\\' => RemoteFsService.driveTypeNoRoot,
        _ => 0, // DRIVE_UNKNOWN
      };

  group('classifyDrives — the table-driven scan (pc_part §3.1)', () {
    test('keeps exactly the local letters, with the right medium', () {
      const int mask = (1 << 26) - 1; // A..Z all present
      final List<DriveInfo> drives =
          RemoteFsService.classifyDrives(mask, _fakeTypeOf);
      expect(drives.map((DriveInfo d) => d.root),
          <String>[r'C:\', r'E:\', r'F:\', r'R:\']);
      expect(drives.map((DriveInfo d) => d.medium),
          <String>['fixed', 'removable', 'optical', 'ram']);
    });

    test('only letters in the mask are asked about', () {
      const int mask = (1 << 0) | (1 << 2) | (1 << 22); // A, C, W
      final List<String> asked = <String>[];
      int typeOf(String root) {
        asked.add(root);
        return RemoteFsService.driveTypeFixed;
      }
      final List<DriveInfo> drives =
          RemoteFsService.classifyDrives(mask, typeOf);
      expect(asked, <String>[r'A:\', r'C:\', r'W:\']);
      expect(drives.map((DriveInfo d) => d.root),
          <String>[r'A:\', r'C:\', r'W:\']);
    });

    test('an empty mask classifies nothing and asks nothing', () {
      bool asked = false;
      final List<DriveInfo> drives =
          RemoteFsService.classifyDrives(0, (_) {
        asked = true;
        return 0;
      });
      expect(drives, isEmpty);
      expect(asked, isFalse);
    });
  });

  group('readLabels — the only pass that may touch a drive (pc_part §3.2)',
      () {
    test('network letters never reach a label read', () {
      const int mask = (1 << 26) - 1;
      final List<DriveInfo> classified =
          RemoteFsService.classifyDrives(mask, _fakeTypeOf);
      final List<String> read = <String>[];
      final List<DriveInfo> labelled = RemoteFsService.readLabels(
        classified,
        (String root) {
          read.add(root);
          return '';
        },
      );
      // W:/Z:/N: were dropped from the table row — no label read is ever
      // attempted for them.
      expect(read, <String>[r'C:\', r'E:\', r'F:\', r'R:\']);
      expect(labelled.map((DriveInfo d) => d.root),
          <String>[r'C:\', r'E:\', r'F:\', r'R:\']);
    });

    test('a letter the call cannot answer is hidden entirely', () {
      const List<DriveInfo> letters = <DriveInfo>[
        DriveInfo(root: r'C:\', medium: 'fixed'),
        DriveInfo(root: r'D:\', medium: 'fixed'),
      ];
      // D: answers not-ready (an empty card slot / DVD tray).
      final List<DriveInfo> labelled = RemoteFsService.readLabels(
        letters,
        (String root) => root == r'D:\' ? null : '',
      );
      expect(labelled.map((DriveInfo d) => d.root), <String>[r'C:\']);
    });
  });

  group('driveDisplayName — the Explorer-style names (pc_part §3.2)', () {
    test('a label wins, the letter in parentheses', () {
      expect(
        RemoteFsService.driveDisplayName(
            const DriveInfo(root: r'D:\', medium: 'fixed', name: 'Data')),
        'Data (D:)',
      );
    });

    test('an empty label falls back per medium', () {
      expect(
        RemoteFsService.driveDisplayName(
            const DriveInfo(root: r'C:\', medium: 'fixed', name: '')),
        'Local Disk (C:)',
      );
      expect(
        RemoteFsService.driveDisplayName(
            const DriveInfo(root: r'E:\', medium: 'removable', name: '')),
        'Removable Disk (E:)',
      );
      expect(
        RemoteFsService.driveDisplayName(
            const DriveInfo(root: r'F:\', medium: 'optical', name: '')),
        'Disc Drive (F:)',
      );
      expect(
        RemoteFsService.driveDisplayName(
            const DriveInfo(root: r'R:\', medium: 'ram', name: '')),
        'RAM Disk (R:)',
      );
    });

    test('an unlabelled letter (the label budget ran out) is the bare letter',
        () {
      expect(
        RemoteFsService.driveDisplayName(
            const DriveInfo(root: r'C:\', medium: 'fixed')),
        'C:',
      );
    });
  });

  group('isNetworkBacked — the table answers, the path is never probed', () {
    test('a UNC path is network-backed, whatever the letters say', () {
      expect(
          RemoteFsService.isNetworkBacked(r'\\server\share\Videos', (_) => false),
          isTrue);
      expect(
          RemoteFsService.isNetworkBacked('//server/share/Videos', (_) => false),
          isTrue);
    });

    test('a DRIVE_REMOTE root is network-backed', () {
      bool remoteRoots(String root) => root == r'D:\';
      expect(RemoteFsService.isNetworkBacked(r'D:\Media\Videos', remoteRoots),
          isTrue);
      expect(
          RemoteFsService.isNetworkBacked(r'd:\media\videos', remoteRoots),
          isTrue);
      expect(
          RemoteFsService.isNetworkBacked(r'C:\Users\me\Videos', remoteRoots),
          isFalse);
    });

    test('a plain local path is not', () {
      expect(RemoteFsService.isNetworkBacked('/home/user/Videos', (_) => true),
          isFalse);
      expect(RemoteFsService.isNetworkBacked('relative/path', (_) => true),
          isFalse);
      expect(RemoteFsService.isNetworkBacked('Videos', (_) => true), isFalse);
    });
  });

  group('guidBytes — the shell32 layout (pc_part §3.4)', () {
    test('the Downloads KNOWNFOLDERID lays out little-endian first three fields',
        () {
      expect(
        RemoteFsService.guidBytes(r'{374DE290-123F-4565-9164-39C4925E467B}'),
        <int>[
          0x90, 0xE2, 0x4D, 0x37, // 374DE290
          0x3F, 0x12, // 123F
          0x65, 0x45, // 4565
          0x91, 0x64, 0x39, 0xC4, 0x92, 0x5E, 0x46, 0x7B,
        ],
      );
    });

    test('all four quick-place GUIDs are 16 bytes', () {
      const List<String> guids = <String>[
        r'{B4BFCC3A-DB2C-424C-B029-7FE99A87C641}',
        r'{374DE290-123F-4565-9164-39C4925E467B}',
        r'{4BD8D571-6D19-48D3-BE97-422220080E43}',
        r'{18989B1D-99B5-455B-841C-AB7C74E4DDFC}',
      ];
      for (final String guid in guids) {
        expect(RemoteFsService.guidBytes(guid), hasLength(16),
            reason: guid);
      }
    });

    test('a malformed guid is rejected', () {
      expect(() => RemoteFsService.guidBytes('{nope}'), throwsArgumentError);
      expect(() => RemoteFsService.guidBytes(''), throwsArgumentError);
    });
  });

  group('quickPlaceFor — known folders, never guesses (pc_part §3.4)', () {
    test('a UNC resolution is skipped — even though it "exists"', () {
      final Map<String, Object?>? chip = RemoteFsService.quickPlaceFor(
        name: 'Videos',
        knownPath: r'\\server\share\Videos',
        home: '/home/user',
        remoteRoots: (String root) => false,
        exists: (String path) => true,
      );
      expect(chip, isNull);
    });

    test('a DRIVE_REMOTE root is skipped — the table answers, no probe', () {
      final List<String> probed = <String>[];
      final Map<String, Object?>? chip = RemoteFsService.quickPlaceFor(
        name: 'Desktop',
        knownPath: r'D:\Desktop',
        home: '/home/user',
        remoteRoots: (String root) => root == r'D:\',
        exists: (String path) {
          probed.add(path);
          return true;
        },
      );
      expect(chip, isNull);
      expect(probed, isEmpty); // the network path is never probed
    });

    test('a local known-folder answer wins over the home guess', () {
      // Relocated Videos (Properties → Location) — the chip follows.
      final Map<String, Object?>? chip = RemoteFsService.quickPlaceFor(
        name: 'Videos',
        knownPath: p.join('/media', 'D', 'Media', 'Videos'),
        home: '/home/user',
        remoteRoots: (String root) => false,
        exists: (String path) => path == p.join('/media', 'D', 'Media', 'Videos'),
      );
      expect(chip, isNotNull);
      expect(chip!['name'], 'Videos');
      expect(chip['path'], p.join('/media', 'D', 'Media', 'Videos'));
      expect(chip['kind'], 'videos');
    });

    test('an API failure falls back to the home guess + probe', () {
      final Map<String, Object?>? chip = RemoteFsService.quickPlaceFor(
        name: 'Music',
        knownPath: null,
        home: '/home/user',
        remoteRoots: (String root) => false,
        exists: (String path) => path == p.join('/home/user', 'Music'),
      );
      expect(chip, isNotNull);
      expect(chip!['path'], p.join('/home/user', 'Music'));
      expect(chip['kind'], 'music');
    });

    test('a missing local folder yields no chip', () {
      expect(
        RemoteFsService.quickPlaceFor(
          name: 'Downloads',
          knownPath: null,
          home: '/home/user',
          remoteRoots: (String root) => false,
          exists: (String path) => false,
        ),
        isNull,
      );
    });
  });

  group('places() — the phone Files-tab answer', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTempAsync('salu_remote_fs');
    });

    tearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } on FileSystemException {}
    });

    test('a UNC now-playing path is skipped without any I/O', () async {
      // In the platform's own spelling, so dirname keeps the share.
      final String uncVideo = Platform.isWindows
          ? r'\\server\share\movie.mkv'
          : '//server/share/movie.mkv';
      final RemoteFsPlaces places =
          await RemoteFsService.instance.places(nowPlayingPath: uncVideo);
      final List<Map<String, Object?>> now = places.places
          .where((Map<String, Object?> place) => place['kind'] == 'now_playing')
          .toList();
      expect(now, isEmpty);
    });

    test('a stream URL never becomes a place', () async {
      final RemoteFsPlaces places = await RemoteFsService.instance.places(
          nowPlayingPath: 'http://host:8080/chan/1');
      final List<Map<String, Object?>> now = places.places
          .where((Map<String, Object?> place) => place['kind'] == 'now_playing')
          .toList();
      expect(now, isEmpty);
    });

    test('a local now-playing path adds its parent folder', () async {
      final File video = File(p.join(tmp.path, 'movie.mkv'))
        ..writeAsStringSync('x');
      final RemoteFsPlaces places =
          await RemoteFsService.instance.places(nowPlayingPath: video.path);
      final List<Map<String, Object?>> now = places.places
          .where((Map<String, Object?> place) => place['kind'] == 'now_playing')
          .toList();
      expect(now, hasLength(1));
      expect(now.first['path'], tmp.path);
      expect(now.first['name'], 'Now playing');
    });

    test('drive places carry the medium field, quick places do not', () async {
      // Off-Windows the table has no letters — the answer stays honest
      // (no fake drives) and nothing network-shaped can appear.
      final RemoteFsPlaces places =
          await RemoteFsService.instance.places();
      for (final Map<String, Object?> place in places.places) {
        if (place['kind'] == 'drive') {
          expect(place['medium'], isNotNull);
        } else {
          expect(place.containsKey('medium'), isFalse);
        }
      }
    });
  });

  group('list() — the read-only listing rules', () {
    late Directory tmp;
    late File video;
    late File audio;
    late File subtitle;
    late File playlist;
    late File other;

    setUp(() async {
      tmp = await Directory.systemTemp.createTempAsync('salu_remote_fs_list');
      Directory(p.join(tmp.path, 'System Volume Information')).createSync();
      Directory(p.join(tmp.path, 'windows')).createSync();
      Directory(p.join(tmp.path, 'Season 1')).createSync();
      video = File(p.join(tmp.path, 'Show.S01E01.mkv'))
        ..writeAsStringSync('x');
      audio = File(p.join(tmp.path, 'track.mp3'))..writeAsStringSync('x');
      subtitle = File(p.join(tmp.path, 'Show.S01E01.srt'))
        ..writeAsStringSync('x');
      playlist = File(p.join(tmp.path, 'list.m3u'))
        ..writeAsStringSync('#EXTM3U');
      other = File(p.join(tmp.path, 'notes.txt'))..writeAsStringSync('x');
    });

    tearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } on FileSystemException {}
    });

    test('the media filter keeps media + playlists, drops subs and text', () {
      final RemoteFsListResult result =
          RemoteFsService.instance.list(tmp.path);
      final Set<String> names =
          result.entries.map((RemoteFsEntry e) => e.name).toSet();
      expect(
          names,
          containsAll(
              <String>['Season 1', 'Show.S01E01.mkv', 'track.mp3', 'list.m3u']));
      expect(names, isNot(contains('Show.S01E01.srt')));
      expect(names, isNot(contains('notes.txt')));
    });

    test('the subs filter keeps subtitles and lets the user descend into folders',
        () {
      final RemoteFsListResult result =
          RemoteFsService.instance.list(tmp.path, filter: 'subs');
      final Set<String> names =
          result.entries.map((RemoteFsEntry e) => e.name).toSet();
      expect(names, contains('Show.S01E01.srt'));
      expect(names, contains('Season 1'));
      expect(names, isNot(contains('Show.S01E01.mkv')));
    });

    test('system folders are hidden unless showSystem asks for them', () {
      final Set<String> hidden =
          RemoteFsService.instance.list(tmp.path)
              .entries
              .map((RemoteFsEntry e) => e.name)
              .toSet();
      expect(hidden, isNot(contains('windows')));
      expect(hidden, isNot(contains('System Volume Information')));
      final Set<String> shown =
          RemoteFsService.instance.list(tmp.path, showSystem: true)
              .entries
              .map((RemoteFsEntry e) => e.name)
              .toSet();
      expect(
          shown, containsAll(<String>['windows', 'System Volume Information']));
    });

    test('directories sort before files', () {
      final List<RemoteFsEntry> entries =
          RemoteFsService.instance.list(tmp.path, filter: 'all').entries;
      expect(entries, isNotEmpty);
      expect(entries.first.directory, isTrue);
    });

    test('paging hands out a slice, the rest stays honest', () {
      for (int i = 0; i < 5; i++) {
        File(p.join(tmp.path, 'pad$i.mkv')).writeAsStringSync('x');
      }
      final RemoteFsListResult first =
          RemoteFsService.instance.list(tmp.path, from: 0, count: 3);
      final RemoteFsListResult second =
          RemoteFsService.instance.list(tmp.path, from: 3, count: 3);
      expect(first.count, 3);
      expect(second.count, 3);
      expect(first.total, second.total);
      expect(first.truncated, isTrue);
      final Set<String> names1 =
          first.entries.map((RemoteFsEntry e) => e.name).toSet();
      final Set<String> names2 =
          second.entries.map((RemoteFsEntry e) => e.name).toSet();
      expect(names1.intersection(names2), isEmpty);
    });

    test('a UNC path is refused without reaching the network', () {
      expect(
        () => RemoteFsService.instance.list(r'\\server\share'),
        throwsA(isA<RemoteFsException>()),
      );
    });

    test('a missing path is a normal answer, not a crash', () {
      RemoteFsException? error;
      try {
        RemoteFsService.instance.list(p.join(tmp.path, 'gone'));
      } on RemoteFsException catch (e) {
        error = e;
      }
      expect(error, isNotNull);
      expect(error!.code, 'path_not_found');
    });

    test('reading never writes: the list APIs leave the tree untouched', () {
      final int entriesBefore = tmp.listSync(recursive: true).length;
      RemoteFsService.instance.list(tmp.path);
      RemoteFsService.instance.list(tmp.path, filter: 'subs');
      RemoteFsService.instance.list(tmp.path, filter: 'all', showSystem: true);
      expect(tmp.listSync(recursive: true).length, entriesBefore);
    });
  });
}
