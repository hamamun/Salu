import 'dart:io';

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

/// Read-only file-system adapter used by authenticated, explicit phone
/// requests. There is intentionally no write/delete/rename API in this
/// class. It never reads file bytes.
class RemoteFsService {
  RemoteFsService._();
  static final RemoteFsService instance = RemoteFsService._();

  RemoteFsPlaces places({String? nowPlayingPath}) {
    final List<Map<String, Object?>> result = <Map<String, Object?>>[];
    for (final Directory drive in _drives()) {
      result.add(<String, Object?>{
        'name': drive.path,
        'path': drive.path,
        'kind': 'drive',
      });
    }
    final String? current = nowPlayingPath;
    if (current != null && current.isNotEmpty && !current.contains('://')) {
      final String parent = p.dirname(current);
      if (Directory(parent).existsSync()) {
        result.add(<String, Object?>{
          'name': 'Now playing',
          'path': parent,
          'kind': 'now_playing',
        });
      }
    }
    final String? home = _homeDirectory();
    final Map<String, String> names = <String, String>{
      'Downloads': 'Downloads',
      'Videos': 'Videos',
      'Music': 'Music',
      'Desktop': 'Desktop',
    };
    if (home != null) {
      for (final MapEntry<String, String> item in names.entries) {
        final String path = p.join(home, item.value);
        if (Directory(path).existsSync()) {
          result.add(<String, Object?>{
            'name': item.key,
            'path': path,
            'kind': item.key.toLowerCase(),
          });
        }
      }
    }
    return RemoteFsPlaces(places: List<Map<String, Object?>>.unmodifiable(result));
  }

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
        if (!isDirectory && !_acceptFile(entity.path, wanted)) continue;
        if (isDirectory && wanted == 'subs') {
          // Subtitle mode still lets the user descend into folders.
        }
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

  static Iterable<Directory> _drives() sync* {
    for (int i = 0; i < 26; i++) {
      final String drive = '${String.fromCharCode(65 + i)}:${Platform.pathSeparator}';
      final Directory directory = Directory(drive);
      if (directory.existsSync()) yield directory;
    }
    // Linux/macOS builds have no drive letters; the feature still remains
    // useful for explicit paths and the places list stays honest.
  }

  static String? _homeDirectory() {
    final String? home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'];
    return home == null || home.isEmpty ? null : home;
  }
}
