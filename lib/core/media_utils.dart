import 'dart:io';

import 'package:path/path.dart' as p;

/// The two playable kinds SALU distinguishes (autoload_imp.md §1 lock
/// 4): a folder scan never mixes them — a picked video queues videos,
/// a picked track queues tracks.
enum MediaKind { video, audio }

/// Central knowledge of which file types SALU understands.
class MediaUtils {
  MediaUtils._();

  static const Set<String> videoExtensions = <String>{
    '.mp4', '.mkv', '.avi', '.mov', '.wmv', '.flv', '.webm', '.m4v',
    '.mpg', '.mpeg', '.ts', '.m2ts', '.mts', '.vob', '.3gp', '.ogv',
    '.rm', '.rmvb', '.asf', '.divx',
  };

  static const Set<String> audioExtensions = <String>{
    '.mp3', '.flac', '.m4a', '.aac', '.ogg', '.opus', '.wav', '.wma',
    '.alac', '.aiff', '.ape', '.dsf', '.mka',
  };

  static const Set<String> subtitleExtensions = <String>{
    '.srt', '.ass', '.ssa', '.sub', '.vtt',
  };

  /// Sidecar lyrics (lrc.md L7 / L25). `.lrc` ONLY — never a subtitle
  /// spelling, never mixed into [subtitleExtensions]. `.lyr` is a
  /// different karaoke format and is out of scope for v1.
  static const Set<String> lyricExtensions = <String>{
    '.lrc',
  };

  static const Set<String> playlistExtensions = <String>{
    '.m3u', '.m3u8',
  };

  static String _ext(String path) => p.extension(path).toLowerCase();

  static bool isVideo(String path) => videoExtensions.contains(_ext(path));

  static bool isAudio(String path) => audioExtensions.contains(_ext(path));

  static bool isMedia(String path) => isVideo(path) || isAudio(path);

  static bool isSubtitle(String path) =>
      subtitleExtensions.contains(_ext(path));

  static bool isLyrics(String path) => lyricExtensions.contains(_ext(path));

  static bool isPlaylist(String path) =>
      playlistExtensions.contains(_ext(path));

  /// Display name for a media path — the file name without its extension.
  static String displayName(String path) => p.basenameWithoutExtension(path);

  // ── Canonical spellings (playlist_imp.md §5) ─────────────────────────

  /// ONE canonical spelling of a local path so resume memory, stop memory
  /// and the "is this the row that was playing?" checks never disagree:
  /// forward slashes, no leading `/` before a drive letter, and no Windows
  /// long-path prefix (`\\?\`). Streams / URLs (`://`) are returned
  /// untouched — a URL's spelling is a key of its own and must never be
  /// rewritten (`ChannelSource.localPath` unwraps a `file://` URI for the
  /// same reason, and [samePath] peels one before comparing).
  ///
  /// The long-path prefix is not a cosmetic detail: on Windows media_kit
  /// hands mpv the `\\?\C:\…` spelling (`safe_local_storage.addPrefix`)
  /// and mpv's `path` property reports exactly what it was given, so the
  /// prefix has to collapse away or the engine's spelling of a file would
  /// never equal SALU's.
  static String canonicalPath(String path) {
    if (path.contains('://')) return path;
    String s = path.replaceAll('\\', '/');
    // `\\?\C:\a.mp3` → `C:/a.mp3`; the UNC form keeps its network root:
    // `\\?\UNC\srv\share\a.mp3` → `//srv/share/a.mp3`.
    if (s.toUpperCase().startsWith('//?/UNC/')) {
      s = '//${s.substring(8)}';
    } else {
      while (s.startsWith('//?/')) {
        s = s.substring(4);
      }
    }
    const String scheme = 'file://';
    if (s.startsWith('$scheme/')) {
      s = s.substring(scheme.length + 1);
    } else if (s.startsWith(scheme)) {
      s = s.substring(scheme.length);
    }
    // "/C:/x/y.mkv" (URI residue) → "C:/x/y.mkv".
    if (s.length >= 3 &&
        s.startsWith('/') &&
        _isAsciiLetter(s.codeUnitAt(1)) &&
        s.codeUnitAt(2) == 0x3A) {
      s = s.substring(1);
    }
    return s;
  }

  static bool _isAsciiLetter(int code) =>
      (code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A);

  /// Do two spellings name the same local file?
  ///
  /// Both sides collapse to one spelling first, `file://` peeled off —
  /// `\\?\C:\a.mp3`, `file:///C:/a.mp3` and `C:/a.mp3` are one file, which
  /// is exactly the question the audio canvas asks when it compares the
  /// engine's `path` with the file SALU queued. On Windows a difference in
  /// case is still a match, because the filesystem is case-insensitive and
  /// the engine can report a spelling SALU never typed. A stream URL is
  /// only ever equal to the very same URL — its case is part of the key.
  static bool samePath(String a, String b) {
    final String ca = _localSpelling(a);
    final String cb = _localSpelling(b);
    if (ca == cb) return true;
    if (ca.contains('://') || cb.contains('://')) return false;
    return Platform.isWindows && ca.toLowerCase() == cb.toLowerCase();
  }

  /// [canonicalPath] with a `file://` scheme peeled first: a file URI is a
  /// local file, not a URL, and has to meet the plain path on equal terms.
  static String _localSpelling(String path) {
    const String scheme = 'file://';
    if (path.startsWith(scheme)) {
      final String rest = path.substring(scheme.length);
      final bool drive = rest.length >= 2 &&
          _isAsciiLetter(rest.codeUnitAt(0)) &&
          rest.codeUnitAt(1) == 0x3A;
      if (rest.startsWith('/') || drive) return canonicalPath(rest);
    }
    return canonicalPath(path);
  }

  static bool _isDigit(int code) => code >= 0x30 && code <= 0x39;

  // ── Natural ordering (playlist_imp.md §5 — one gesture = one block) ──

  /// Natural, case-insensitive string compare: digit runs count as numbers
  /// (`ep2` before `ep10`), digits sort before letters, everything else is
  /// compared case-insensitively.
  static int naturalCompare(String a, String b) {
    int i = 0, j = 0;
    while (i < a.length && j < b.length) {
      final int ra = a.codeUnitAt(i);
      final int rb = b.codeUnitAt(j);
      final bool da = _isDigit(ra);
      final bool db = _isDigit(rb);
      if (da && db) {
        final int si = i, sj = j;
        while (i < a.length && _isDigit(a.codeUnitAt(i))) {
          i++;
        }
        while (j < b.length && _isDigit(b.codeUnitAt(j))) {
          j++;
        }
        // Compare as arbitrary precision — digit runs may exceed 64 bits.
        final BigInt na = BigInt.parse(a.substring(si, i));
        final BigInt nb = BigInt.parse(b.substring(sj, j));
        if (na > nb) return 1;
        if (na < nb) return -1;
        continue; // equal numbers — keep scanning the rest
      }
      if (da != db) return da ? -1 : 1; // digits before letters
      final int la = _lower(ra);
      final int lb = _lower(rb);
      if (la != lb) return la < lb ? -1 : 1;
      i++;
      j++;
    }
    if (i < a.length) return 1;
    if (j < b.length) return -1;
    return 0;
  }

  static int _lower(int code) =>
      (code >= 0x41 && code <= 0x5A) ? code + 32 : code;

  /// Path compare for a queue block: folder first (natural), then the file
  /// name (natural) — the order the folder shows it.
  static int naturalPathCompare(String a, String b) {
    final String ca = canonicalPath(a);
    final String cb = canonicalPath(b);
    final int dir = naturalCompare(p.dirname(ca), p.dirname(cb));
    if (dir != 0) return dir;
    return naturalCompare(p.basename(ca), p.basename(cb));
  }

  /// Sorts a local batch into the folder's own order (folder first, then
  /// the name, both natural). Used at every local boundary — the shell's
  /// multi-select array order is never trusted.
  static List<String> sortForQueue(List<String> paths) =>
      List<String>.of(paths)..sort(naturalPathCompare);
}
