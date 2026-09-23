import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../drop_handler.dart';
import '../media_utils.dart';

const int remoteFsMaxScan = 2000;
const int remoteFsDefaultPage = 200;
const Set<String> remoteFsSystemFolderNames = <String>{
  'windows',
  'program files',
  'program files (x86)',
  'programdata',
  r'$recycle.bin',
  'system volume information',
  'appdata',
  'node_modules',
  'windowsapps',
};

class RemoteFsException implements Exception {
  const RemoteFsException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => '$code: $message';
}

@immutable
class RemoteFsEntry {
  const RemoteFsEntry({
    required this.name,
    required this.path,
    required this.directory,
    this.size,
    this.modified,
    this.extension,
  });

  final String name;
  final String path;
  final bool directory;
  final int? size;
  final DateTime? modified;
  final String? extension;

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'path': path,
        'directory': directory,
        if (size != null) 'size': size,
        if (modified != null) 'modified': modified!.millisecondsSinceEpoch,
        if (extension != null) 'ext': extension,
      };
}

class RemoteFsPlaces {
  const RemoteFsPlaces({required this.places});
  final List<Map<String, Object?>> places;
  List<Map<String, Object?>> toJson() => places;
}

class RemoteFsListResult {
  const RemoteFsListResult({
    required this.path,
    required this.from,
    required this.count,
    required this.total,
    required this.entries,
    required this.truncated,
  });

  final String path;
  final int from;
  final int count;
  final int total;
  final List<RemoteFsEntry> entries;
  final bool truncated;

  Map<String, Object?> toJson() => <String, Object?>{
        'path': path,
        'from': from,
        'count': count,
        'total': total,
        'truncated': truncated,
        'entries': entries.map((RemoteFsEntry e) => e.toJson()).toList(),
      };
}

/// One local drive letter as the Win32 table sees it.
///
/// [root] is the letter's root (`C:\`), [medium] the protocol value the
/// phone already understands (`fixed` / `removable` / `optical` / `ram`),
/// and [name] the display name the label pass filled in — `null` until it
/// answers (the bare letter is the budgeted-out fallback), `''` for a
/// letter whose volume carries no label.
class DriveInfo {
  const DriveInfo({required this.root, required this.medium, this.name});

  final String root;
  final String medium;
  final String? name;

  @override
  String toString() => 'DriveInfo($root $medium ${name ?? '<unlabelled>'})';
}

/// Read-only file-system adapter used by authenticated, explicit phone
/// requests. There is intentionally no write/delete/rename API in this
/// class. It never reads file bytes.
///
/// Drive enumeration reads the Win32 drive **table** (kernel32's
/// `GetLogicalDrives` + `GetDriveTypeW`) — in-memory queries that never
/// touch a drive or a network, instant in any network state. Letters of
/// type `DRIVE_REMOTE` (and any UNC path) are dropped from the table
/// BEFORE any file-system call can happen, so a disconnected mapped drive
/// can never stall the answer (the 2026-09-22 `fs_places` hang,
/// pc_part.md §1–§3). Only the surviving LOCAL letters ever get a volume
/// label — and that read runs off the handler isolate with a 2 s budget,
/// so a sleeping USB disk can freeze at most the budget, never the window.
class RemoteFsService {
  RemoteFsService._();
  static final RemoteFsService instance = RemoteFsService._();

  // ── Drive table (Win32, in-memory only) ────────────────────────────────

  /// Win32 drive types (kernel32 `GetDriveTypeW`).
  static const int driveTypeNoRoot = 1; // DRIVE_NO_ROOT_DIR
  static const int driveTypeRemovable = 2; // DRIVE_REMOVABLE
  static const int driveTypeFixed = 3; // DRIVE_FIXED
  static const int driveTypeRemote = 4; // DRIVE_REMOTE — never yielded
  static const int driveTypeCdrom = 5; // DRIVE_CDROM
  static const int driveTypeRamdisk = 6; // DRIVE_RAMDISK

  /// The one translation: Win32 type → the protocol's `medium` string
  /// (the phone already understands these). `DRIVE_REMOTE` (4) and
  /// `DRIVE_NO_ROOT_DIR` (1) have no row on purpose — they are dropped,
  /// never yielded (pc_part.md §3.1).
  static const Map<int, String> mediumByType = <int, String>{
    driveTypeFixed: 'fixed',
    driveTypeRemovable: 'removable',
    driveTypeCdrom: 'optical',
    driveTypeRamdisk: 'ram',
  };

  /// The pure, table-driven core (pc_part.md §3.1): every letter present
  /// in [mask] is classified by [typeOf] (the `GetDriveTypeW` answer for
  /// that root) and kept only when its type has a `medium` row. Nothing
  /// in this seam may touch the file system — that is the whole point:
  /// network letters never reach a label read (pc_part.md §6).
  static List<DriveInfo> classifyDrives(
    int mask,
    int Function(String root) typeOf,
  ) {
    final List<DriveInfo> out = <DriveInfo>[];
    for (int i = 0; i < 26; i++) {
      if (mask & (1 << i) == 0) continue;
      final String root = '${String.fromCharCode(65 + i)}:\\';
      final String? medium = mediumByType[typeOf(root)];
      if (medium == null) continue;
      out.add(DriveInfo(root: root, medium: medium));
    }
    return out;
  }

  /// The surviving local letters, from the in-memory drive table.
  ///
  /// Microseconds on any machine, in any network state: two kernel32
  /// table reads, no drive contact. Non-Windows answers empty (no drive
  /// letters exist there — the feature stays honest, explicit paths
  /// still work, per the old comment).
  static List<DriveInfo> localDrives() {
    if (!Platform.isWindows) return const <DriveInfo>[];
    final _Win32 w = _Win32.instance;
    return classifyDrives(w.getLogicalDrives(), w.driveType);
  }

  /// The label pass — the ONLY part of a places() answer that may touch a
  /// drive (pc_part.md §3.2): each surviving letter's volume name via
  /// `GetVolumeInformationW`. A letter the call cannot answer (no media,
  /// not ready — an empty card slot, an empty DVD tray) is skipped
  /// entirely, matching Explorer's default of hiding empty drives. A
  /// `DRIVE_REMOTE` letter never reaches this pass: the filter ran first,
  /// always.
  ///
  /// [labelOf] is the seam: production hands it [volumeLabel], tests a
  /// fake (pc_part.md §6).
  static List<DriveInfo> readLabels(
    List<DriveInfo> letters,
    String? Function(String root) labelOf,
  ) {
    final List<DriveInfo> out = <DriveInfo>[];
    for (final DriveInfo letter in letters) {
      final String? label = labelOf(letter.root);
      if (label == null) continue; // not ready — hidden, like Explorer
      out.add(DriveInfo(
        root: letter.root,
        medium: letter.medium,
        name: label,
      ));
    }
    return out;
  }

  /// [readLabels] on a child isolate: the only code path that may block on
  /// a disk, so it is the only one that runs off the handler isolate
  /// (pc_part.md §3.3). The caller budgets it with a timeout.
  static Future<List<DriveInfo>> labelledDrives(List<DriveInfo> letters) {
    return Isolate.run(() => readLabels(letters, volumeLabel));
  }

  /// The display name of a labelled (or budgeted-out) drive, Explorer's
  /// way (pc_part.md §3.2): `Data (D:)` with a label, `Local Disk (C:)` /
  /// `Removable Disk (E:)` / `Disc Drive (F:)` / `RAM Disk (R:)` without
  /// one, and the bare letter when the label budget ran out.
  static String driveDisplayName(DriveInfo drive) {
    final String letter = drive.root.substring(0, 2); // "C:"
    final String? label = drive.name;
    if (label == null) return letter;
    if (label.isNotEmpty) return '$label ($letter)';
    return '${_fallbackDiskName(drive.medium)} ($letter)';
  }

  static String _fallbackDiskName(String medium) => switch (medium) {
        'removable' => 'Removable Disk',
        'optical' => 'Disc Drive',
        'ram' => 'RAM Disk',
        _ => 'Local Disk',
      };

  /// The network guard every place answer goes through (pc_part.md
  /// §3.4–§3.5): a UNC path, or a path whose root letter is a network
  /// drive (corporate folder redirection, a Desktop on a NAS), is dropped
  /// BEFORE any file-system call. [remoteRoots] answers the one question
  /// Windows keeps in memory — "is this letter `DRIVE_REMOTE`?" — so the
  /// share itself is never probed.
  static bool isNetworkBacked(
    String path,
    bool Function(String root) remoteRoots,
  ) {
    final String value = path.trim();
    if (value.startsWith(r'\\') || value.startsWith('//')) return true;
    if (value.length >= 2 && value.codeUnitAt(1) == 0x3A) {
      // "X:" — a drive-letter root.
      final int letter = value.codeUnitAt(0);
      final bool isLetter = (letter >= 0x41 && letter <= 0x5A) ||
          (letter >= 0x61 && letter <= 0x7A);
      if (isLetter) return remoteRoots('${String.fromCharCode(letter)}:\\');
    }
    return false;
  }

  /// The one question the drive table keeps: is this letter
  /// `DRIVE_REMOTE`? An in-memory mount-table read — instant in any
  /// network state. Non-Windows: no letters, no network roots.
  static bool isRemoteRoot(String root) {
    if (!Platform.isWindows) return false;
    return _Win32.instance.driveType(root) == driveTypeRemote;
  }

  /// `GetVolumeInformationW` for one local root: the volume label, or
  /// `null` when the call fails (no media / not ready — the drive stays
  /// hidden, Explorer's default). Never called for a `DRIVE_REMOTE`
  /// letter: the filter runs first, always (pc_part.md §3.2).
  static String? volumeLabel(String root) {
    if (!Platform.isWindows) return null;
    final _Win32 w = _Win32.instance;
    final Pointer<Utf16> nativeRoot = root.toNativeUtf16();
    final Pointer<Utf16> buffer = calloc<Uint16>(260).cast<Utf16>();
    try {
      final int ok = w.getVolumeInformationW(nativeRoot, buffer, 260);
      if (ok == 0) return null;
      return buffer.toDartString();
    } finally {
      calloc.free(nativeRoot);
      calloc.free(buffer);
    }
  }

  /// The byte layout of a Windows GUID as shell32 receives it: the first
  /// three fields little-endian, the last eight as printed.
  ///
  /// `{374DE290-123F-4565-9164-39C4925E467B}` →
  /// `90 E2 4D 37 · 3F 12 · 65 45 · 91 64 39 C4 92 5E 46 7B`.
  static List<int> guidBytes(String guid) {
    final String hex = guid.replaceAll(RegExp(r'[{}\-\s]'), '');
    if (hex.length != 32) {
      throw ArgumentError.value(guid, 'guid', 'not a 128-bit GUID');
    }
    final int d1 = int.parse(hex.substring(0, 8), radix: 16);
    final int d2 = int.parse(hex.substring(8, 12), radix: 16);
    final int d3 = int.parse(hex.substring(12, 16), radix: 16);
    final List<int> out = <int>[
      d1 & 0xFF,
      (d1 >> 8) & 0xFF,
      (d1 >> 16) & 0xFF,
      (d1 >> 24) & 0xFF,
      d2 & 0xFF,
      (d2 >> 8) & 0xFF,
      d3 & 0xFF,
      (d3 >> 8) & 0xFF,
    ];
    for (int i = 16; i < 32; i += 2) {
      out.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return out;
  }

  // ── The places answer ──────────────────────────────────────────────────

  /// How long a computed drive list stays fresh: a burst of `fs_places`
  /// calls (the phone opening the Files tab) costs one label pass, not N.
  static const Duration _driveCacheTtl = Duration(seconds: 5);

  /// The label pass's budget: a sleeping USB disk can stall at most this
  /// long, and then the letters still answer, bare (pc_part.md §3.3).
  static const Duration _labelBudget = Duration(seconds: 2);

  static DateTime? _driveCacheAt;
  static List<Map<String, Object?>>? _driveCache;
  static Future<List<DriveInfo>>? _driveInFlight;

  /// The places the phone's Files tab opens with (pc_part.md §3): the
  /// local drives (table + labels, off the handler isolate, cached), the
  /// Now-playing folder and the four quick places (known folders, never
  /// guessed).
  ///
  /// Network-backed places are dropped before any I/O — a disconnected
  /// mapped drive, a redirected folder, a Desktop on a NAS: the table
  /// answers, the share is never probed (§3.4–§3.5).
  Future<RemoteFsPlaces> places({String? nowPlayingPath}) async {
    final List<Map<String, Object?>> result = <Map<String, Object?>>[];
    result.addAll(await _drivePlaces());

    final String? current = nowPlayingPath;
    if (current != null && current.isNotEmpty && !current.contains('://')) {
      // The same network guard as the drives: a file playing from a
      // network drive (or a UNC path) gets no chip, and no I/O at all —
      // checking the table, never probing the path.
      final String parent = p.dirname(current);
      if (!isNetworkBacked(parent, isRemoteRoot) &&
          Directory(parent).existsSync()) {
        result.add(<String, Object?>{
          'name': 'Now playing',
          'path': parent,
          'kind': 'now_playing',
        });
      }
    }

    final String? home = _homeDirectory();
    for (final String name in _quickPlaceNames) {
      final Map<String, Object?>? chip = _quickPlace(name, home);
      if (chip != null) result.add(chip);
    }
    return RemoteFsPlaces(
        places: List<Map<String, Object?>>.unmodifiable(result));
  }

  /// The drive rows of [places]: the letters come from the in-memory
  /// table (microseconds); the labels come from the budgeted child-
  /// isolate pass, and on timeout the letters still answer, bare
  /// (pc_part.md §3.3). The result is cached ~5 s.
  Future<List<Map<String, Object?>>> _drivePlaces() async {
    final DateTime? cachedAt = _driveCacheAt;
    final List<Map<String, Object?>>? cached = _driveCache;
    if (cachedAt != null &&
        cached != null &&
        DateTime.now().difference(cachedAt) < _driveCacheTtl) {
      return cached;
    }
    final List<DriveInfo> letters = localDrives();
    if (letters.isEmpty) return const <Map<String, Object?>>[];
    Future<List<DriveInfo>>? inFlight = _driveInFlight;
    inFlight ??= _driveInFlight = labelledDrives(letters).timeout(
      _labelBudget,
      onTimeout: () => letters,
    );
    try {
      final List<DriveInfo> labelled = await inFlight;
      _driveCacheAt = DateTime.now();
      _driveCache = _drivePlaceMaps(labelled);
      return _driveCache!;
    } finally {
      if (identical(_driveInFlight, inFlight)) _driveInFlight = null;
    }
  }

  static List<Map<String, Object?>> _drivePlaceMaps(List<DriveInfo> drives) =>
      <Map<String, Object?>>[
        for (final DriveInfo d in drives)
          <String, Object?>{
            'name': driveDisplayName(d),
            'path': d.root,
            'kind': 'drive',
            'medium': d.medium,
          },
      ];

  // ── Quick places (known folders, never guesses) ────────────────────────

  /// The four quick places, in the order the phone already sees them.
  static const List<String> _quickPlaceNames = <String>[
    'Downloads',
    'Videos',
    'Music',
    'Desktop',
  ];

  /// KNOWNFOLDERIDs for the quick places (pc_part.md §3.4) — where
  /// Windows (and the user, Properties → Location) actually keeps them,
  /// not a `join(USERPROFILE, name)` guess.
  static const Map<String, String> _knownFolderGuids = <String, String>{
    'Desktop': r'{B4BFCC3A-DB2C-424C-B029-7FE99A87C641}',
    'Downloads': r'{374DE290-123F-4565-9164-39C4925E467B}',
    'Music': r'{4BD8D571-6D19-48D3-BE97-422220080E43}',
    'Videos': r'{18989B1D-99B5-455B-841C-AB7C74E4DDFC}',
  };

  /// The pure part of one quick place (pc_part.md §3.4). [knownPath] is
  /// `SHGetKnownFolderPath`'s answer; when it is `null` (off Windows, or
  /// the API failed) today's `join(home, name)` guess stands. A
  /// network-backed resolution is skipped silently — the table is
  /// consulted, the path is never probed. [exists] is the one instant
  /// local probe the place still gets.
  static Map<String, Object?>? quickPlaceFor({
    required String name,
    String? knownPath,
    String? home,
    required bool Function(String root) remoteRoots,
    required bool Function(String path) exists,
  }) {
    String? path = knownPath;
    if (path == null || path.isEmpty) {
      if (home == null) return null;
      path = p.join(home, name);
    }
    if (isNetworkBacked(path, remoteRoots)) return null;
    if (!exists(path)) return null;
    return <String, Object?>{
      'name': name,
      'path': path,
      'kind': name.toLowerCase(),
    };
  }

  /// One quick place, resolved (pc_part.md §3.4): the known-folder API —
  /// the folder where Windows (and the user, Properties → Location)
  /// actually keeps it — with today's `join(USERPROFILE, name)` guess as
  /// the API's fallback. A network-backed resolution is skipped silently
  /// (the table is consulted, the path never probed); a local one still
  /// gets the one instant existence check.
  Map<String, Object?>? _quickPlace(String name, String? home) {
    final String? known =
        Platform.isWindows ? knownFolderPath(name) : null;
    return quickPlaceFor(
      name: name,
      knownPath: known,
      home: home,
      remoteRoots: isRemoteRoot,
      exists: (String path) => Directory(path).existsSync(),
    );
  }

  /// `SHGetKnownFolderPath` (shell32) for one of the quick places: the
  /// resolved path, or `null` when the API fails (the caller falls back
  /// to the USERPROFILE guess). The COM-allocated answer is released.
  static String? knownFolderPath(String name) {
    final String? guid = _knownFolderGuids[name];
    if (guid == null) return null;
    final _Win32 w = _Win32.instance;
    final List<int> bytes = guidBytes(guid);
    final Pointer<Uint8> nativeGuid = calloc<Uint8>(16);
    for (int i = 0; i < 16; i++) {
      nativeGuid[i] = bytes[i];
    }
    final Pointer<Pointer<Utf16>> out = calloc<Pointer<Utf16>>();
    try {
      final int hr = w.shGetKnownFolderPath(nativeGuid, 0, 0, out);
      if ((hr & 0x80000000) != 0) return null; // FAILED(hr)
      final Pointer<Utf16> path = out.value;
      if (path == nullptr) return null;
      final String value = path.toDartString();
      w.coTaskMemFree(path.cast());
      return value;
    } finally {
      calloc.free(out);
      calloc.free(nativeGuid);
    }
  }

  // ── Listing (unchanged read-only rules) ────────────────────────────────

  RemoteFsListResult list(
    String path, {
    int from = 0,
    int count = remoteFsDefaultPage,
    String filter = 'media',
    bool showSystem = false,
  }) {
    final Directory directory = _validatedDirectory(path);
    final int start = from < 0 ? 0 : from;
    final int pageSize = count.clamp(1, remoteFsDefaultPage).toInt();
    final String wanted = <String>{'media', 'subs', 'all'}.contains(filter)
        ? filter
        : 'media';
    final List<FileSystemEntity> scanned = <FileSystemEntity>[];
    bool truncated = false;
    try {
      int seen = 0;
      for (final FileSystemEntity entity in directory.listSync(followLinks: false)) {
        if (seen >= remoteFsMaxScan) {
          truncated = true;
          break;
        }
        seen++;
        final String name = p.basename(entity.path);
        final bool isDirectory = entity is Directory;
        if (!showSystem && isDirectory && isSystemFolderName(name)) continue;
        // Folders pass every filter: in subtitle mode the user still
        // descends into directories; media/all just keep them.
        if (!isDirectory && !_acceptFile(entity.path, wanted)) continue;
        scanned.add(entity);
      }
    } on FileSystemException catch (error) {
      throw RemoteFsException('path_not_found', error.message);
    }
    scanned.sort(_compareEntities);
    final int total = scanned.length;
    final List<RemoteFsEntry> page = <RemoteFsEntry>[];
    for (int i = start; i < total && page.length < pageSize; i++) {
      final FileSystemEntity entity = scanned[i];
      final FileStat stat = FileStat.statSync(entity.path);
      final bool dir = entity is Directory;
      page.add(RemoteFsEntry(
        name: p.basename(entity.path),
        path: entity.path,
        directory: dir,
        size: dir ? null : stat.size,
        modified: stat.modified,
        extension: dir ? null : p.extension(entity.path).replaceFirst('.', '').toLowerCase(),
      ));
    }
    return RemoteFsListResult(
      path: directory.path,
      from: start,
      count: page.length,
      total: total,
      entries: List<RemoteFsEntry>.unmodifiable(page),
      truncated: truncated || start + page.length < total,
    );
  }

  /// Expands a requested folder into media paths without returning bytes.
  List<String> collectMediaInFolder(String path) {
    final Directory directory = _validatedDirectory(path);
    return DropHandler.scanFolderForMedia(directory.path);
  }

  Directory _validatedDirectory(String raw) {
    final String path = _normalize(raw);
    if (path.isEmpty || _isUnc(path)) {
      throw const RemoteFsException('path_not_found', 'That folder or file is no longer there.');
    }
    final Directory directory = Directory(path);
    if (!directory.existsSync()) {
      throw const RemoteFsException('path_not_found', 'That folder or file is no longer there.');
    }
    if (directory.statSync().type != FileSystemEntityType.directory) {
      throw const RemoteFsException('not_a_directory', 'That path is not a folder.');
    }
    return directory;
  }

  String validateFile(String raw, {bool subtitles = false}) {
    final String path = _normalize(raw);
    if (path.isEmpty || _isUnc(path)) {
      throw const RemoteFsException('path_not_found', 'That folder or file is no longer there.');
    }
    final File file = File(path);
    if (!file.existsSync()) {
      throw const RemoteFsException('path_not_found', 'That folder or file is no longer there.');
    }
    if (file.statSync().type != FileSystemEntityType.file) {
      throw const RemoteFsException('not_a_directory', 'That path is not a folder.');
    }
    if (subtitles && !MediaUtils.isSubtitle(path)) {
      throw const RemoteFsException('path_not_found', 'That is not a subtitle file.');
    }
    return file.path;
  }

  static bool isSystemFolderName(String name) =>
      remoteFsSystemFolderNames.contains(name.toLowerCase());

  static bool _acceptFile(String path, String filter) {
    switch (filter) {
      case 'subs':
        return MediaUtils.isSubtitle(path);
      case 'all':
        return MediaUtils.isMedia(path) ||
            MediaUtils.isSubtitle(path) ||
            MediaUtils.isPlaylist(path);
      case 'media':
      default:
        return MediaUtils.isMedia(path) || MediaUtils.isPlaylist(path);
    }
  }

  static int _compareEntities(FileSystemEntity a, FileSystemEntity b) {
    final bool ad = a is Directory;
    final bool bd = b is Directory;
    if (ad != bd) return ad ? -1 : 1;
    return MediaUtils.naturalPathCompare(p.basename(a.path), p.basename(b.path));
  }

  static String _normalize(String raw) {
    final String value = raw.trim();
    if (value.isEmpty) return '';
    return p.normalize(value);
  }

  static bool _isUnc(String path) => path.startsWith('\\\\') || path.startsWith('//');

  static String? _homeDirectory() {
    final String? home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'];
    return home == null || home.isEmpty ? null : home;
  }
}

/// The kernel32 / shell32 / ole32 surface this file uses: in-memory drive-
/// table reads and one COM known-folder query. Opened lazily and Windows
/// only — every caller gates on [Platform.isWindows] first, so the
/// libraries are never loaded elsewhere. Each isolate opens its own copy
/// (the label pass runs on a child isolate, and a [DynamicLibrary] handle
/// is not shared across isolates).
class _Win32 {
  _Win32()
      : _kernel32 = DynamicLibrary.open('kernel32.dll'),
        _shell32 = DynamicLibrary.open('shell32.dll'),
        _ole32 = DynamicLibrary.open('ole32.dll') {
    _getLogicalDrives = _kernel32
        .lookupFunction<Int32 Function(), int Function()>(
            'GetLogicalDrives');
    _getDriveTypeW = _kernel32.lookupFunction<Int32 Function(Pointer<Utf16>),
        int Function(Pointer<Utf16>)>('GetDriveTypeW');
    _getVolumeInformationW = _kernel32.lookupFunction<
        Int32 Function(
            Pointer<Utf16>, Pointer<Utf16>, Uint32, Pointer<Uint32>,
            Pointer<Uint32>, Pointer<Uint32>, Pointer<Utf16>, Uint32),
        int Function(
            Pointer<Utf16>, Pointer<Utf16>, int, Pointer<Uint32>,
            Pointer<Uint32>, Pointer<Uint32>, Pointer<Utf16>, int)>(
        'GetVolumeInformationW');
    _shGetKnownFolderPath = _shell32.lookupFunction<
        Int32 Function(Pointer<Uint8>, Uint32, IntPtr, Pointer<Pointer<Utf16>>),
        int Function(
            Pointer<Uint8>, int, int, Pointer<Pointer<Utf16>>)>(
        'SHGetKnownFolderPath');
    _coTaskMemFree = _ole32.lookupFunction<Void Function(Pointer<Void>),
        void Function(Pointer<Void>)>('CoTaskMemFree');
  }

  static _Win32? _instance;
  static _Win32 get instance => _instance ??= _Win32();

  final DynamicLibrary _kernel32;
  final DynamicLibrary _shell32;
  final DynamicLibrary _ole32;

  late final int Function() _getLogicalDrives;
  late final int Function(Pointer<Utf16>) _getDriveTypeW;
  late final int Function(Pointer<Utf16>, Pointer<Utf16>, int,
      Pointer<Uint32>, Pointer<Uint32>, Pointer<Uint32>, Pointer<Utf16>,
      int) _getVolumeInformationW;
  late final int Function(Pointer<Uint8>, int, int,
      Pointer<Pointer<Utf16>>) _shGetKnownFolderPath;
  late final void Function(Pointer<Void>) _coTaskMemFree;

  /// The bitmask of present drive letters (in-memory; instant).
  int getLogicalDrives() => _getLogicalDrives();

  /// The kind of one letter (mount table; instant even for a dead network
  /// mapping). One of [RemoteFsService.driveType*].
  int driveType(String root) {
    final Pointer<Utf16> native = root.toNativeUtf16();
    try {
      return _getDriveTypeW(native);
    } finally {
      calloc.free(native);
    }
  }

  /// The volume label of one local root: nonzero on success. Never called
  /// for a `DRIVE_REMOTE` letter (the filter runs first, always).
  int getVolumeInformationW(Pointer<Utf16> root, Pointer<Utf16> label,
          int labelSize) =>
      _getVolumeInformationW(root, label, labelSize, nullptr, nullptr,
          nullptr, nullptr, 0);

  /// [guid] is the 16-byte GUID layout (see
  /// [RemoteFsService.guidBytes]); [out] receives the COM-allocated
  /// answer. Returns the HRESULT — call [RemoteFsService.knownFolderPath]
  /// rather than this directly.
  int shGetKnownFolderPath(Pointer<Uint8> guid, int flags, int token,
          Pointer<Pointer<Utf16>> out) =>
      _shGetKnownFolderPath(guid, flags, token, out);

  void coTaskMemFree(Pointer<Void> pointer) => _coTaskMemFree(pointer);
}
