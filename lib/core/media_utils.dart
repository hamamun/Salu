import 'package:path/path.dart' as p;

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

  static const Set<String> playlistExtensions = <String>{
    '.m3u', '.m3u8',
  };

  static String _ext(String path) => p.extension(path).toLowerCase();

  static bool isVideo(String path) => videoExtensions.contains(_ext(path));

  static bool isAudio(String path) => audioExtensions.contains(_ext(path));

  static bool isMedia(String path) => isVideo(path) || isAudio(path);

  static bool isSubtitle(String path) =>
      subtitleExtensions.contains(_ext(path));

  static bool isPlaylist(String path) =>
      playlistExtensions.contains(_ext(path));

  /// Display name for a media path — the file name without its extension.
  static String displayName(String path) => p.basenameWithoutExtension(path);

  // ── Canonical spelling ────────────────────────────────────────────────
  //
  // The same local file reaches SALU spelled three ways: the picker and the
  // shell hand over `C:\media\a.mp4`, mpv reports `file:///C:/media/a.mp4`,
  // and a queue restored from Undo may hold either. Resume memory, the stop
  // memory and every "is this the same file?" comparison are STRING
  // comparisons, so all of them are only honest if one spelling is written
  // down everywhere. That spelling is decided here, once.

  /// One or more backslashes, in a constant: a large folder load must not
  /// compile it per item.
  static final RegExp _backslashes = RegExp(r'\\+');

  /// The canonical form of a media source: forward slashes (one per
  /// separator, however many the shell emitted), no `file://` scheme, no
  /// leading `/` before a drive letter. A UNC root keeps its `//` — a share
  /// path is not a drive path.
  ///
  /// Streams are returned UNTOUCHED: a URL has no path to normalize, and its
  /// spelling is a key of its own (the URL library, favourites), so it must
  /// never be rewritten.
  static String canonicalPath(String path) {
    // Streams: nothing to normalize.
    if (path.contains('://') && !path.startsWith('file://')) return path;
    // Already canonical — no backslashes to fold, no scheme to strip, no
    // URI residue to trim. This runs on every position tick, so it is worth
    // answering without touching the string.
    if (!path.contains(_backslashes) && !path.contains('://') &&
        !path.startsWith('/')) {
      return path;
    }
    // A path that STARTS with a backslash is a UNC root (`\\server\share`):
    // the fold would collapse its doubled leading slash, so put it back.
    final bool unc = path.startsWith(_backslashes);
    String s = path.replaceAll(_backslashes, '/');
    if (unc && s.startsWith('/') && !s.startsWith('//')) s = '/$s';
    const String scheme = 'file://';
    if (s.startsWith('$scheme/')) {
      // `file:///C:/x` — the extra slash is the empty host.
      s = s.substring(scheme.length + 1);
    } else if (s.startsWith(scheme)) {
      s = s.substring(scheme.length);
    }
    // "/C:/x/y.mkv" (URI residue) → "C:/x/y.mkv".
    if (s.length >= 3 &&
        s.startsWith('/') &&
        s.codeUnitAt(1) >= 0x41 &&
        s.codeUnitAt(1) <= 0x7A &&
        s.codeUnitAt(2) == 0x3A) {
      s = s.substring(1);
    }
    return s;
  }

  // ── Ordering ───────────────────────────────────────────────────────────
  //
  // WHY THIS EXISTS: the shell does not hand SALU the files in the order
  // the user is looking at. Explorer's multi-select (and the Open dialog's
  // result array) STARTS AT THE ITEM THAT WAS GRABBED or clicked first and
  // then wraps around — pick ten files, drag them by the sixth, and the
  // array arrives as 6,7,8,9,10,1,2,3,4,5. A queue built verbatim from that
  // array "starts from the middle", which is exactly what a folder of media
  // must never do. So every local batch is re-ordered here into the one
  // order that matches the folder view: Name, case-insensitive, with digit
  // runs read as numbers ("ep2" before "ep10").

  /// The order of a local batch: folder first, then the file name, both
  /// natural — so files from one folder stay together and in the order the
  /// folder shows them. The full path breaks any tie: the result is a total
  /// order, reproducible on every run.
  static int naturalPathCompare(String a, String b) {
    final int byDir = _naturalCompare(p.dirname(a), p.dirname(b));
    if (byDir != 0) return byDir;
    final int byName = _naturalCompare(p.basename(a), p.basename(b));
    if (byName != 0) return byName;
    return a.toLowerCase().compareTo(b.toLowerCase());
  }

  /// Sorts [paths] in place into [naturalPathCompare] order. A no-op below
  /// two entries, so single picks keep their identity.
  static void sortNatural(List<String> paths) {
    if (paths.length < 2) return;
    paths.sort(naturalPathCompare);
  }

  /// Case-insensitive comparison where a run of digits counts as one
  /// number, however long (compared by length then digits — no int
  /// overflow, no cap on the episode number).
  static int _naturalCompare(String left, String right) {
    final String a = left.toLowerCase();
    final String b = right.toLowerCase();
    int i = 0;
    int j = 0;
    while (i < a.length && j < b.length) {
      final int ca = a.codeUnitAt(i);
      final int cb = b.codeUnitAt(j);
      final bool digitA = ca >= 0x30 && ca <= 0x39;
      final bool digitB = cb >= 0x30 && cb <= 0x39;
      if (digitA && digitB) {
        int ea = i;
        int eb = j;
        while (ea < a.length && _isDigit(a.codeUnitAt(ea))) {
          ea++;
        }
        while (eb < b.length && _isDigit(b.codeUnitAt(eb))) {
          eb++;
        }
        // Ignore leading zeros when measuring, keep them to break ties.
        int sa = i;
        int sb = j;
        while (sa < ea - 1 && a.codeUnitAt(sa) == 0x30) {
          sa++;
        }
        while (sb < eb - 1 && b.codeUnitAt(sb) == 0x30) {
          sb++;
        }
        final int lenA = ea - sa;
        final int lenB = eb - sb;
        if (lenA != lenB) return lenA - lenB;
        final int byDigits =
            a.substring(sa, ea).compareTo(b.substring(sb, eb));
        if (byDigits != 0) return byDigits;
        final int byZeros = (sa - i) - (sb - j);
        if (byZeros != 0) return byZeros;
        i = ea;
        j = eb;
        continue;
      }
      if (ca != cb) return ca - cb;
      i++;
      j++;
    }
    final int restA = a.length - i;
    final int restB = b.length - j;
    if (restA != restB) return restA - restB;
    // Same text, different case — stable, and never "equal" by accident.
    return left.compareTo(right);
  }

  static bool _isDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;
}
