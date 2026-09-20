import 'dart:async';

/// Pure JavaScript builders for the active page's own media element. Every
/// command re-finds the element, so a navigation can never leave a stale DOM
/// handle behind. Top-document querySelectorAll deliberately cannot cross a
/// cross-origin iframe; that is the honest `found:false` result the phone
/// needs.
abstract final class RemoteWebMediaScripts {
  static const String find = r'''(function () {
    try {
      var list = Array.prototype.slice.call(document.querySelectorAll('video, audio'));
      var best = null;
      var score = -1;
      list.forEach(function (el) {
        var area = (el.videoWidth || 0) * (el.videoHeight || 0);
        if (!area) area = (isFinite(el.duration) ? el.duration : 0);
        if (area > score) { score = area; best = el; }
      });
      return !!best;
    } catch (e) { return false; }
  })()''';

  static const String read = r'''(function () {
    try {
      var list = Array.prototype.slice.call(document.querySelectorAll('video, audio'));
      var el = null;
      var score = -1;
      list.forEach(function (x) {
        var area = (x.videoWidth || 0) * (x.videoHeight || 0);
        if (!area) area = (isFinite(x.duration) ? x.duration : 0);
        if (area > score) { score = area; el = x; }
      });
      if (!el) return {found:false};
      var holder = el.parentElement || el;
      return {found:true, playing:!el.paused, position:el.currentTime || 0,
        duration:isFinite(el.duration) ? el.duration : 0, volume:el.volume,
        muted:!!el.muted,
        canFull:!!(el.webkitSupportsFullscreen || holder.requestFullscreen)};
    } catch (e) { return {found:false}; }
  })()''';

  static String toggle() => _write('''
    if (el.paused) { var p = el.play(); if (p) p.catch(function(){}); }
    else el.pause();
  ''');

  static String seek({double? to, double? delta}) => _write('''
    var target = ${to == null ? 'el.currentTime + (${delta ?? 0})' : '(${to})'};
    if (isFinite(target)) el.currentTime = Math.max(0, target);
  ''');

  static String volume(double percent) => _write('''
    el.volume = Math.max(0, Math.min(1, (${percent}) / 100));
  ''');

  static String mute(bool on) => _write('el.muted = ${on ? 'true' : 'false'};');

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

  static String _write(String body) => '''(function () {
    try {
      var list = Array.prototype.slice.call(document.querySelectorAll('video, audio'));
      var el = null; var score = -1;
      list.forEach(function (x) {
        var area = (x.videoWidth || 0) * (x.videoHeight || 0);
        if (!area) area = (isFinite(x.duration) ? x.duration : 0);
        if (area > score) { score = area; el = x; }
      });
      if (!el) return false;
      $body
      return true;
    } catch (e) { return false; }
  })()''';
}

class RemoteWebMediaResult {
  const RemoteWebMediaResult({
    required this.found,
    this.playing = false,
    this.position = 0,
    this.duration = 0,
    this.volume = 100,
    this.muted = false,
    this.canFull = false,
  });

  final bool found;
  final bool playing;
  final double position;
  final double duration;
  final double volume;
  final bool muted;
  final bool canFull;

  Map<String, Object?> toJson() => <String, Object?>{
        'found': found,
        'playing': playing,
        'position': position,
        'duration': duration,
        'volume': volume,
        'muted': muted,
        'canFull': canFull,
      };

  factory RemoteWebMediaResult.fromScript(Object? raw) {
    if (raw is! Map || raw['found'] != true) return const RemoteWebMediaResult(found: false);
    double number(Object? value) => value is num ? value.toDouble() : 0;
    return RemoteWebMediaResult(
      found: true,
      playing: raw['playing'] == true,
      position: number(raw['position']),
      duration: number(raw['duration']),
      volume: number(raw['volume']) * (number(raw['volume']) <= 1 ? 100 : 1),
      muted: raw['muted'] == true,
      canFull: raw['canFull'] == true,
    );
  }
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
      final Object? result =
          await run(RemoteWebMediaScripts.read).timeout(const Duration(seconds: 2));
      return RemoteWebMediaResult.fromScript(result);
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
