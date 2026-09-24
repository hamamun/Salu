import 'dart:async';

/// Pure JavaScript builders for the active page's own media element. Every
/// command re-finds the element, so a navigation can never leave a stale DOM
/// handle behind. Top-document querySelectorAll deliberately cannot cross a
/// cross-origin iframe; that is the honest `found:false` result the phone
/// needs.
///
/// The wire units (pc_part.md A1 · remote.md §17.4, fixed 2026-09-23) are
/// converted here, at the bridge's edge, so JavaScript's seconds and 0–1
/// never reach the socket: `position`/`duration`/`to`/`delta` are milliseconds
/// and `volume`/`percent` are integer percent 0–100. `NaN`/`Infinity` (live
/// streams, unloaded elements) are sanitized to `0` + `seekable:false` because
/// `jsonEncode` throws on either; a write target outside `[0, duration]` is
/// clamped ("the end"/"the start"), never rejected.
///
/// The builders/parsers below are deliberately pure Dart (string-in,
/// string-out) so `test/remote_web_media_test.dart` can assert them without
/// a WebView. Production runs them through [RemoteWebMediaBridge], which is
/// the thin adapter around the callback BrowserScreen owns.
abstract final class RemoteWebMediaScripts {
  /// The shared find expression A2 specifies (pc_part.md · remote.md
  /// §17.11), in this order: a playing, audible/visible element with a real
  /// box outranks everything; then the largest `videoWidth × videoHeight`
  /// (box size, then duration as fallbacks); zero-box sub-2-second elements
  /// (ident bumpers, looping backgrounds) and hidden/preview-league
  /// elements cannot be the programme. `picked` describes the winner for the
  /// PC's log (`tag`, box, duration, paused) so an argument about which
  /// element a site exposed ends in one log line.
  static const String findBody = r'''
  var list = Array.prototype.slice.call(document.querySelectorAll('video, audio'));
  var best = null, bestScore = -1, bestTie = -1, bestPaused = true;
  list.forEach(function (el) {
    if (!el.paused) {
      // A not-paused, live element can outrank by being the one already on
      // stage — but it must still be audible/visible.
      try {
        var r = el.getBoundingClientRect();
        var audible = !!((el.muted !== undefined) ? (!el.muted && el.volume > 0) : true);
        if (r.width > 0 && r.height > 0 && audible) {
          var sc = (el.videoWidth || 0) * (el.videoHeight || 0);
          if (!sc) sc = (r.width * r.height);
          if (sc > bestScore) {
            bestScore = sc; best = el; bestPaused = false; bestTie = 0;
          }
        }
      } catch (e) {}
    }
  });
  list.forEach(function (el) {
    try {
      var r = el.getBoundingClientRect();
      var visible = r.width > 0 && r.height > 0 &&
        getComputedStyle(el).display !== 'none' &&
        getComputedStyle(el).visibility !== 'hidden' &&
        getComputedStyle(el).opacity !== '0';
      var dur = isFinite(el.duration) ? el.duration : 0;
      if (!visible) return;            // zero box / hidden — not the programme
      if (dur > 0 && dur < 2) return;  // ident bumper / looping background
      var area = (el.videoWidth || 0) * (el.videoHeight || 0);
      if (!area) area = (r.width * r.height);
      if (!area) area = dur;
      if (area < 0) area = 0;
      var paused = !!el.paused;
      if (paused && best && !bestPaused) return; // a playing one already won
      var tie = paused ? 1 : 0;
      if (!best || area > bestScore || (area === bestScore && tie < bestTie)) {
        bestScore = area; bestTie = tie; best = el; bestPaused = paused;
      }
    } catch (e) {}
  });
''';

  static const String describe = r'''
  var desc = null;
  if (best) {
    try {
      var r = best.getBoundingClientRect();
      desc = {tag: best.tagName.toLowerCase(),
              box: Math.round(r.width) + 'x' + Math.round(r.height),
              duration: isFinite(best.duration) ? best.duration : null,
              paused: !!best.paused};
    } catch (e) {}
  }
''';

  static const String find = '(function () {\n'
      '  try {\n'
      '    $findBody\n'
      '    return !!best;\n'
      '  } catch (e) { return false; }\n'
      '})()';

  /// `web_media_get`'s read script. Returns the wire-shaped reply direct
  /// from the page (`found:false` when there is no reachable element), with
  /// `unit`/`volumeUnit`/`seekable` so the phone never has to measure, and
  /// `el` for the PC log (never serialized onto the wire by Dart).
  static String read() => '(function () {\n'
      '  try {\n'
      '    $findBody\n'
      '    $describe\n'
      '    if (!best) return {found:false};\n'
      '    var pos = (isFinite(best.currentTime) ? best.currentTime : 0);\n'
      '    var dur = (isFinite(best.duration) ? best.duration : 0);\n'
      '    var vol = (isFinite(best.volume) ? best.volume : 1);\n'
      '    var holder = best.parentElement || best;\n'
      '    return {found:true, playing:!best.paused,\n'
      '      position:Math.round(pos * 1000), duration:Math.round(dur * 1000),\n'
      '      volume:Math.round(vol * 100), muted:!!best.muted,\n'
      '      seekable:!(isFinite(dur) && dur > 0) ? false : true,\n'
      '      unit:"ms", volumeUnit:"percent",\n'
      '      canFull:!!(best.webkitSupportsFullscreen || holder.requestFullscreen),\n'
      '      el:desc};\n'
      '  } catch (e) { return {found:false}; }\n'
      '})()';

  /// `web_media_toggle`: play/pause the picked element.
  static String toggle() => _write(r'''
    if (el.paused) { var p = el.play(); if (p) p.catch(function(){}); }
    else el.pause();
    return true;
  ''');

  /// `web_media_seek`. [to] is absolute milliseconds, [delta] relative — a
  /// delta-seek reads the page's own clock at apply time, clamped, so "−10 s
  /// twice in a beat" lands 20 s back, exactly where the page was, not where
  /// the caller once thought it was.
  static String seek({double? to, double? delta}) => _write(r'''
    var next = ($express);
    if (isFinite(next)) {
      var d = isFinite(el.duration) ? el.duration : Infinity;
      var max = isFinite(d) && d > 0 ? d : Infinity;
      el.currentTime = Math.max(0, Math.min(next, max));
    }
    return true;
  '''.replaceAll(r'($express)', to != null
      ? '(${to / 1000})'
      : '(el.currentTime + (${(delta ?? 0) / 1000}))'));

  /// `web_media_volume`: integer percent 0–100 → `el.volume` 0–1.
  static String volume(double percent) => _write('''
    el.volume = Math.max(0, Math.min(1, ($percent) / 100));
    return true;
  ''');

  static String mute(bool on) => _write('el.muted = ${on ? 'true' : 'false'}; '
      'return true;');

  static String fullscreen() => r'''(function () {
    try {
      var list = Array.prototype.slice.call(document.querySelectorAll('video, audio'));
      var el = list.length ? list[0] : null;
      if (!el) return false;
      var holder = el.parentElement || el;
      if (document.fullscreenElement) {
        var p = document.exitFullscreen(); if (p) p.catch(function(){});
      } else if (el.webkitSupportsFullscreen && el.webkitEnterFullscreen) {
        el.webkitEnterFullscreen();
      } else if (holder.requestFullscreen) {
        var q = holder.requestFullscreen(); if (q) q.catch(function(){});
      } else return false;
      return true;
    } catch (e) { return false; }
  })()''';

  static String _write(String body) => '(function () {\n'
      '  try {\n'
      '    $findBody\n'
      '    var el = best;\n'
      '    if (!el) return false;\n'
      '    $body\n'
      '  } catch (e) { return false; }\n'
      '})()';
}

/// One `web_media_get` answer in wire units (milliseconds + percent). The
/// unit conversion and the `NaN`/`Infinity` sanitization both live in the
/// script; this parser is a pure guard that anything unexpected collapses to
/// the plain `not found` shape instead of crashing the phone's clock.
class RemoteWebMediaResult {
  const RemoteWebMediaResult({
    required this.found,
    this.playing = false,
    this.position = 0,
    this.duration = 0,
    this.volume = 100,
    this.muted = false,
    this.canFull = false,
    this.seekable = false,
  });

  final bool found;
  final bool playing;

  /// Milliseconds, integer — `(el.currentTime * 1000).round()` at the edge.
  final int position;
  final int duration;

  /// Integer percent 0–100 — `(el.volume * 100).round()` at the edge.
  final int volume;
  final bool muted;
  final bool canFull;

  /// `duration.isFinite && duration > 0` — the one pair the phone reads to
  /// grey its seek bar and ±10 s buttons (live streams answer `false`).
  final bool seekable;

  Map<String, Object?> toJson() => <String, Object?>{
        'found': found,
        'playing': playing,
        'position': position,
        'duration': duration,
        'volume': volume,
        'muted': muted,
        'canFull': canFull,
        'seekable': seekable,
        'unit': 'ms',
        'volumeUnit': 'percent',
      };

  factory RemoteWebMediaResult.fromScript(Object? raw) {
    if (raw is! Map || raw['found'] != true) {
      return const RemoteWebMediaResult(found: false);
    }
    // NaN/Infinity can be authored by a page's own script (the read script
    // sanitizes them first), so the Dart edge defends too: either becomes 0
    // here rather than dying in `jsonEncode` on the way out.
    int number(Object? value) {
      if (value is num) {
        if (!value.isFinite) return 0;
        return value.round();
      }
      return 0;
    }

    return RemoteWebMediaResult(
      found: true,
      playing: raw['playing'] == true,
      position: number(raw['position']),
      duration: number(raw['duration']),
      volume: number(raw['volume']).clamp(0, 100).toInt(),
      muted: raw['muted'] == true,
      canFull: raw['canFull'] == true,
      seekable: raw['seekable'] == true,
    );
  }
}

/// A one-liner for the PC's log: when the read reply carries an `el`
/// description, the site's own element choice is one `debugPrint` away
/// (pc_part.md A2.5 — one line ends every argument about which element a
/// site exposed).
String remoteWebMediaElLog(Map<String, Object?> json) {
  final Object? raw = json['el'];
  if (raw is! Map) return '';
  final Object? tag = raw['tag'];
  final Object? box = raw['box'];
  final Object? duration = raw['duration'];
  final Object? paused = raw['paused'];
  final String body = <String>[
    if (tag is String) 'tag=$tag',
    if (box is String) 'box=$box',
    if (duration is num) 'duration=$duration',
    if (paused is bool) 'paused=$paused',
  ].join(' ');
  return body.isEmpty ? '' : ' ($body)';
}

/// Thin adapter around a callback owned by BrowserScreen. The callback is
/// deliberately injectable so script construction stays unit-testable and
/// the bridge never creates a second WebView or navigation path.
class RemoteWebMediaBridge {
  RemoteWebMediaBridge({this.executeScript});

  Future<Object?> Function(String script)? executeScript;

  Future<RemoteWebMediaResult> get() async {
    final Future<Object?> Function(String)? run = executeScript;
    if (run == null) return const RemoteWebMediaResult(found: false);
    try {
      final Object? result = await run(RemoteWebMediaScripts.read())
          .timeout(const Duration(seconds: 2));
      final RemoteWebMediaResult parsed = RemoteWebMediaResult.fromScript(result);
      return parsed;
    } catch (_) {
      return const RemoteWebMediaResult(found: false);
    }
  }

  Future<bool> write(String script) async {
    final Future<Object?> Function(String)? run = executeScript;
    if (run == null) return false;
    try {
      final Object? result =
          await run(script).timeout(const Duration(seconds: 2));
      return result == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> toggle() => write(RemoteWebMediaScripts.toggle());
  Future<bool> seek({double? to, double? delta}) =>
      write(RemoteWebMediaScripts.seek(to: to, delta: delta));
  Future<bool> volume(double percent) =>
      write(RemoteWebMediaScripts.volume(percent));
  Future<bool> mute(bool on) => write(RemoteWebMediaScripts.mute(on));
  Future<bool> fullscreen() => write(RemoteWebMediaScripts.fullscreen());
}
