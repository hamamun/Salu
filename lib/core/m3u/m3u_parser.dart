/// SALU's channel-directory parser (playlist_imp.md §10.0 / §10.16, M-2).
///
/// Pure Dart, incremental, line-state driven: text arrives in chunks (a
/// download, a file read) and complete entries come out as soon as their
/// URL line has been seen — nothing waits for the end of the file. The
/// parser holds only the current partial line and the pending `#EXTINF`;
/// it never keeps the source text.
///
/// This is the M3U *directory* parser (what channels exist). A channel's
/// own HLS segment manifest is mpv's job — see [M3uDirectoryParser.isHls].
///
/// Rules (all verified by `test/m3u_parser_test.dart`):
/// - a UTF-8 BOM before the first line is stripped (§10.16 patch 3);
/// - CRLF and LF both work; blank lines and unknown `#` lines are skipped;
/// - `#EXTM3U` is optional;
/// - attributes parse quoted (`k="v"`, `k='v'`) and unquoted (`k=v`);
/// - the title is everything after the first comma *outside quotes*, so a
///   name containing commas survives (and so does a quoted attribute value
///   containing one);
/// - `#EXTGRP:` may precede or follow that entry's `#EXTINF` (it applies to
///   the next URL and is consumed by it);
/// - an `#EXTINF` with no following URL is dropped, never fused with the
///   next entry; junk between `#EXTINF` and its URL does not mis-pair them;
/// - a URL line with no `#EXTINF` is still an entry (its label falls back
///   through the point-2 chain in `ChannelMapper`);
/// - blank attribute values stay as written here (`""`) — the mapper turns
///   blanks into `null` (§10.16 patch 2) so this layer stays a faithful
///   reader.
library;

/// One raw directory entry — exactly what the file said, nothing derived.
class M3uEntry {
  const M3uEntry({
    required this.url,
    this.title,
    this.attributes = const <String, String>{},
    this.extgrp,
  });

  /// The URL / path line (trimmed, as written — resolution against the
  /// playlist's base happens in the mapper).
  final String url;

  /// Text after the attribute comma, trimmed; `null` when the entry had no
  /// `#EXTINF` line.
  final String? title;

  /// `#EXTINF` attributes with lower-cased keys (`tvg-id`, `group-title`…).
  final Map<String, String> attributes;

  /// The entry's `#EXTGRP:` value, if any (trimmed; may be blank).
  final String? extgrp;

  String? operator [](String key) => attributes[key];

  @override
  String toString() => 'M3uEntry(${title ?? '<no title>'})';
}

/// Incremental M3U directory parser. Feed it decoded text with [feed],
/// collect entries from the returned lists, call [finish] once at the end.
class M3uDirectoryParser {
  M3uDirectoryParser();

  final StringBuffer _carry = StringBuffer();
  bool _first = true;

  // Pending `#EXTINF` (title + attributes) waiting for its URL.
  String? _pendingTitle;
  Map<String, String>? _pendingAttrs;
  bool _hasPendingInf = false;
  String? _pendingGrp;

  int _emitted = 0;
  bool _isHls = false;

  /// Entries produced so far.
  int get emitted => _emitted;

  /// `true` once an `#EXT-X-…` tag was seen *before any entry* — the text
  /// is an HLS media/master manifest (video segments or variants), not a
  /// channel directory. The caller hands the source to mpv instead
  /// (§10.0). Set only while [emitted] is zero; later `#EXT-X-` lines in a
  /// real directory are ignored like any unknown tag.
  bool get isHls => _isHls;

  /// Parses [chunk] (may end mid-line) and returns the entries completed
  /// by it (often empty). Stops producing once [isHls] is set.
  List<M3uEntry> feed(String chunk) {
    if (_isHls || chunk.isEmpty) return const <M3uEntry>[];
    String text = chunk;
    if (_first) {
      _first = false;
      if (text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF) {
        text = text.substring(1);
      }
    }
    final List<M3uEntry> out = <M3uEntry>[];
    int start = 0;
    final int n = text.length;
    for (int i = 0; i < n; i++) {
      if (text.codeUnitAt(i) == 0x0A) {
        String line;
        if (_carry.isNotEmpty) {
          _carry.write(text.substring(start, i));
          line = _carry.toString();
          _carry.clear();
        } else {
          line = text.substring(start, i);
        }
        start = i + 1;
        _line(line, out);
        if (_isHls) return out;
      }
    }
    if (start < n) _carry.write(text.substring(start));
    return out;
  }

  /// Flushes a final unterminated line. Call exactly once after the last
  /// [feed]; a pending `#EXTINF` with no URL is dropped here.
  List<M3uEntry> finish() {
    if (_isHls) return const <M3uEntry>[];
    final List<M3uEntry> out = <M3uEntry>[];
    if (_carry.isNotEmpty) {
      final String line = _carry.toString();
      _carry.clear();
      _line(line, out);
    }
    _dropPending();
    return out;
  }

  void _dropPending() {
    _pendingTitle = null;
    _pendingAttrs = null;
    _hasPendingInf = false;
    _pendingGrp = null;
  }

  void _line(String raw, List<M3uEntry> out) {
    // Trim CR and surrounding whitespace once, here.
    final String line = raw.trim();
    if (line.isEmpty) return;

    if (line.codeUnitAt(0) == 0x23 /* # */) {
      if (_startsWithIgnoreCase(line, '#EXTINF:')) {
        // A new #EXTINF supersedes an unpaired one (dropped, never fused).
        _pendingTitle = null;
        _pendingAttrs = null;
        _parseExtinf(line.substring(8));
        _hasPendingInf = true;
      } else if (_startsWithIgnoreCase(line, '#EXTGRP:')) {
        _pendingGrp = line.substring(8).trim();
      } else if (_emitted == 0 &&
          !_hasPendingInf &&
          _startsWithIgnoreCase(line, '#EXT-X-')) {
        // Segment/variant manifest, not a directory (see [isHls]). A
        // directory that carries stray #EXT-X- lines after a pending
        // #EXTINF or after entries is still a directory.
        _isHls = true;
        _dropPending();
      }
      // #EXTM3U, #EXTVLCOPT, #KODIPROP, #PLAYLIST, comments: ignored.
      return;
    }

    // Anything else is the entry's URL / path line.
    out.add(M3uEntry(
      url: line,
      title: _pendingTitle,
      attributes: _pendingAttrs ?? const <String, String>{},
      extgrp: _pendingGrp,
    ));
    _emitted++;
    _dropPending();
  }

  /// `body` = everything after `#EXTINF:` — `-1 k="v" k2=v,Title`.
  void _parseExtinf(String body) {
    final int n = body.length;
    int i = 0;
    // Skip the duration token (up to the first space or comma).
    while (i < n) {
      final int c = body.codeUnitAt(i);
      if (c == 0x2C /* , */ || c == 0x20 || c == 0x09) break;
      i++;
    }
    // Attributes until the first comma outside quotes. A quote only opens
    // a value directly after `=` (so an apostrophe inside an unquoted
    // value — `tvg-name=Bob's` — cannot swallow the rest of the line).
    Map<String, String>? attrs;
    int? titleAt;
    int quote = 0;
    int j = i;
    while (j < n) {
      final int c = body.codeUnitAt(j);
      if (quote != 0) {
        if (c == quote) quote = 0;
      } else if ((c == 0x22 || c == 0x27) &&
          j > 0 &&
          body.codeUnitAt(j - 1) == 0x3D) {
        quote = c;
      } else if (c == 0x2C) {
        titleAt = j;
        break;
      }
      j++;
    }
    final String attrText = body.substring(i, titleAt ?? n);
    if (attrText.trim().isNotEmpty) attrs = _parseAttributes(attrText);
    _pendingAttrs = attrs;
    _pendingTitle =
        titleAt == null ? null : body.substring(titleAt + 1).trim();
  }

  /// `k="v" k2='v' k3=v` → lower-cased keys. Tolerates stray text.
  static Map<String, String> _parseAttributes(String s) {
    final Map<String, String> out = <String, String>{};
    final int n = s.length;
    int i = 0;
    while (i < n) {
      // Skip separators.
      while (i < n && _isSpace(s.codeUnitAt(i))) {
        i++;
      }
      if (i >= n) break;
      // Key: up to '=' or whitespace.
      final int keyStart = i;
      while (i < n && s.codeUnitAt(i) != 0x3D && !_isSpace(s.codeUnitAt(i))) {
        i++;
      }
      final String key = s.substring(keyStart, i);
      if (i >= n || s.codeUnitAt(i) != 0x3D) {
        // A bare token without '=' — junk; skip it.
        continue;
      }
      i++; // '='
      if (i >= n) {
        out[key.toLowerCase()] = '';
        break;
      }
      final int c = s.codeUnitAt(i);
      String value;
      if (c == 0x22 || c == 0x27) {
        final int close = s.indexOf(String.fromCharCode(c), i + 1);
        if (close < 0) {
          value = s.substring(i + 1);
          i = n;
        } else {
          value = s.substring(i + 1, close);
          i = close + 1;
        }
      } else {
        final int valueStart = i;
        while (i < n && !_isSpace(s.codeUnitAt(i))) {
          i++;
        }
        value = s.substring(valueStart, i);
      }
      if (key.isNotEmpty) out[key.toLowerCase()] = value;
    }
    return out;
  }

  static bool _isSpace(int c) => c == 0x20 || c == 0x09;

  static bool _startsWithIgnoreCase(String s, String prefix) {
    if (s.length < prefix.length) return false;
    for (int i = 0; i < prefix.length; i++) {
      int a = s.codeUnitAt(i);
      final int b = prefix.codeUnitAt(i);
      if (a >= 0x61 && a <= 0x7A) a -= 0x20;
      if (a != b) return false;
    }
    return true;
  }
}
