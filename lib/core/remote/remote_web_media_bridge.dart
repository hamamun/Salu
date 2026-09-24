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
      '      fullscreen:!!(document.fullscreenElement || document.webkitFullscreenElement ||\n'
      '        best.webkitDisplayingFullscreen),\n'
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

  /// Whether the page has an element in fullscreen **right now** — the
  /// read-back of the one fullscreen seat (pc_part.md C1.1). An injected
  /// `requestFullscreen()` that WebView2 refused (no user activation) fails
  /// silently, so reading the document back is the only way to know.
  static const String fullscreenState = '(function () {\n'
      '  try {\n'
      '    if (document.fullscreenElement || document.webkitFullscreenElement) return true;\n'
      '    var v = document.querySelectorAll(\'video\');\n'
      '    for (var i = 0; i < v.length; i++) { if (v[i].webkitDisplayingFullscreen) return true; }\n'
      '    return false;\n'
      '  } catch (e) { return false; }\n'
      '})()';

  /// Leaves element fullscreen, whichever API put the page there.
  static const String exitFullscreen = '(function () {\n'
      '  try {\n'
      '    if (document.fullscreenElement && document.exitFullscreen) {\n'
      '      var p = document.exitFullscreen(); if (p) p.catch(function(){});\n'
      '    } else if (document.webkitFullscreenElement && document.webkitExitFullscreen) {\n'
      '      document.webkitExitFullscreen();\n'
      '    }\n'
      '    var v = document.querySelectorAll(\'video\');\n'
      '    for (var i = 0; i < v.length; i++) {\n'
      '      if (v[i].webkitDisplayingFullscreen && v[i].webkitExitFullscreen) v[i].webkitExitFullscreen();\n'
      '    }\n'
      '    return true;\n'
      '  } catch (e) { return false; }\n'
      '})()';

  /// The CSS selectors of a player's **own** fullscreen control, most
  /// specific first (pc_part.md C1.2). YouTube's button says "Full screen"
  /// with a space, which is why both spellings are listed; a label that
  /// says "exit" is skipped (that is the other direction).
  static const List<String> fullscreenControlSelectors = <String>[
    '.ytp-fullscreen-button',
    '[aria-label*="fullscreen" i]',
    '[aria-label*="full screen" i]',
    '[title*="fullscreen" i]',
    '[title*="full screen" i]',
    '[data-title-no-tooltip*="full screen" i]',
    '.fullscreen-button',
    '.vjs-fullscreen-control',
    '.jw-icon-fullscreen',
    '[data-plyr="fullscreen"]',
    'button[class*="fullscreen" i]',
  ];

  /// The fullscreen **plan** (pc_part.md C1 · remote.md §17.14.1), step 1
  /// and the survey for step 2, in one round trip:
  ///
  /// 1. find the programme element (the shared [findBody]); none →
  ///    `{found:false}` and the PC falls back to the SALU window;
  /// 2. already fullscreen → `{found:true, fullscreen:true}`;
  /// 3. ask the player's container for fullscreen (the injected call — it
  ///    works on pages that allow it; WebView2 refuses it without a user
  ///    gesture, silently);
  /// 4. locate the player's **own** fullscreen control — the selectors
  ///    above, searched outward from the element through its ancestors,
  ///    then the rightmost button in the bottom-right strip of the player
  ///    (the conventional seat of a fullscreen control; the left half is
  ///    where play/pause lives, so it is never a candidate) — and answer its
  ///    centre in **device pixels of the view** (`CSS px ×
  ///    devicePixelRatio`, which already includes the page zoom), so the
  ///    host can fire a real click there if step 3 did not take.
  static String fullscreenPlan() {
    final String selectors = fullscreenControlSelectors
        .map((String s) => "'${s.replaceAll("'", r"\'")}'")
        .join(', ');
    return '(function () {\n'
        '  try {\n'
        '    $findBody\n'
        '    if (!best) return {found:false};\n'
        '    if (document.fullscreenElement || document.webkitFullscreenElement ||\n'
        '        best.webkitDisplayingFullscreen) return {found:true, fullscreen:true};\n'
        '    var vr = best.getBoundingClientRect();\n'
        '    if (vr.bottom < 0 || vr.top > innerHeight || vr.right < 0 || vr.left > innerWidth) {\n'
        '      try { best.scrollIntoView({block:\'center\'}); } catch (e) {}\n'
        '      vr = best.getBoundingClientRect();\n'
        '    }\n'
        '    var holder = best.closest ? (best.closest(\'.html5-video-player, .video-js, .jwplayer, .plyr, [data-player]\') ||\n'
        '      best.parentElement || best) : (best.parentElement || best);\n'
        '    var requested = false;\n'
        '    try {\n'
        '      var req = holder.requestFullscreen || holder.webkitRequestFullscreen;\n'
        '      if (req) { var q = req.call(holder); if (q && q.catch) q.catch(function(){}); requested = true; }\n'
        '    } catch (e) {}\n'
        '    function shown(b) {\n'
        '      var r = b.getBoundingClientRect();\n'
        '      return r.width > 0 && r.height > 0 && r.bottom > 0 && r.right > 0 &&\n'
        '        r.left < innerWidth && r.top < innerHeight;\n'
        '    }\n'
        '    function exits(b) {\n'
        '      var t = ((b.getAttribute(\'aria-label\') || \'\') + \' \' + (b.getAttribute(\'title\') || \'\')).toLowerCase();\n'
        '      return t.indexOf(\'exit\') >= 0;\n'
        '    }\n'
        '    var sels = [$selectors];\n'
        '    var btn = null, via = null, scope = best;\n'
        '    for (var depth = 0; depth < 10 && !btn; depth++) {\n'
        '      scope = scope.parentElement; if (!scope) break;\n'
        '      for (var i = 0; i < sels.length && !btn; i++) {\n'
        '        var hits = scope.querySelectorAll(sels[i]);\n'
        '        for (var j = 0; j < hits.length; j++) {\n'
        '          if (shown(hits[j]) && !exits(hits[j])) { btn = hits[j]; via = sels[i]; break; }\n'
        '        }\n'
        '      }\n'
        '    }\n'
        '    if (!btn) {\n'
        '      scope = best;\n'
        '      for (var up = 0; up < 4 && !btn; up++) {\n'
        '        scope = scope.parentElement; if (!scope) break;\n'
        '        var all = scope.querySelectorAll(\'button, [role="button"]\');\n'
        '        var right = -1;\n'
        '        for (var k = 0; k < all.length; k++) {\n'
        '          var r = all[k].getBoundingClientRect();\n'
        '          if (!shown(all[k]) || exits(all[k])) continue;\n'
        '          var cx = r.left + r.width / 2, cy = r.top + r.height / 2;\n'
        '          if (cx < vr.left + vr.width * 0.5 || cx > vr.right) continue;\n'
        '          if (cy < vr.top + vr.height * 0.75 || cy > vr.bottom + 8) continue;\n'
        '          if (r.right > right) { right = r.right; btn = all[k]; via = \'strip\'; }\n'
        '        }\n'
        '      }\n'
        '    }\n'
        '    var control = null;\n'
        '    if (btn) {\n'
        '      var br = btn.getBoundingClientRect();\n'
        '      var dpr = window.devicePixelRatio || 1;\n'
        '      control = {x: Math.round((br.left + br.width / 2) * dpr),\n'
        '                 y: Math.round((br.top + br.height / 2) * dpr), via: via};\n'
        '    }\n'
        '    return {found:true, fullscreen:false, requested:requested, control:control};\n'
        '  } catch (e) { return {found:false}; }\n'
        '})()';
  }

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
    this.fullscreen = false,
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

  /// Whether the element is **in** fullscreen right now (added 2026-09-24,
  /// remote.md §17.14.1) — `canFull` only means *possible*. The phone's
  /// fullscreen mark reads this so the icon is never a guess.
  final bool fullscreen;

  RemoteWebMediaResult withFullscreen(bool on) => RemoteWebMediaResult(
        found: found,
        playing: playing,
        position: position,
        duration: duration,
        volume: volume,
        muted: muted,
        canFull: canFull,
        seekable: seekable,
        fullscreen: on,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'found': found,
        'playing': playing,
        'position': position,
        'duration': duration,
        'volume': volume,
        'muted': muted,
        'canFull': canFull,
        'seekable': seekable,
        'fullscreen': fullscreen,
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
      fullscreen: raw['fullscreen'] == true,
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

/// What the one fullscreen seat did — the `web_fullscreen` ack's
/// `{fullscreen, target}` (remote.md §17.14.1). `target` names what went
/// (or left) fullscreen: `page` = the page's own player, `window` = the
/// SALU window.
class RemoteFullscreenOutcome {
  const RemoteFullscreenOutcome({
    required this.fullscreen,
    required this.target,
  });

  final bool fullscreen;
  final String target;

  Map<String, Object?> toJson() => <String, Object?>{
        'fullscreen': fullscreen,
        'target': target,
      };

  @override
  String toString() => 'RemoteFullscreenOutcome($fullscreen, $target)';
}

/// The fullscreen **plan** behind `web_fullscreen` (pc_part.md C1 ·
/// remote.md §17.14.1). One verb, and the PC picks the target, in this
/// order — never another:
///
/// 1. **The page's player**, when the page has a reachable one: the plan
///    script asks the player's container for fullscreen and reads back
///    whether it took. WebView2 refuses an injected `requestFullscreen()`
///    that carries no user activation, silently — so when the read-back
///    says no, the host fires a **real** click on the player's *own*
///    fullscreen control ([pageClick] → the composition controller's
///    `SendMouseInput`, the same path a physical mouse over the view
///    takes). A real click *is* a gesture; that is the YouTube fix.
/// 2. **The SALU window**, only when the page has no reachable player (or
///    every page-side attempt was refused — a seat that does nothing is
///    the one outcome worse than the window).
/// 3. **`on:false` always leaves** — element fullscreen first, then the
///    window.
///
/// Every seam is injected so the order is unit-testable without a WebView
/// or a window (`test/remote_web_fullscreen_test.dart`). The host's own
/// `ContainsFullScreenElementChanged` wiring (WebTab → BrowserService
/// `setWebFullscreen`) is what makes an element's fullscreen fill the
/// screen; [pageFullscreen] reads that same truth.
class RemoteWebFullscreen {
  RemoteWebFullscreen({
    required this.executeScript,
    required this.pageClick,
    required this.pageFullscreen,
    required this.exitPage,
    required this.windowFullscreen,
    required this.setWindowFullscreen,
    this.poll = const Duration(milliseconds: 100),
    this.injectedWait = const Duration(milliseconds: 400),
    this.clickWait = const Duration(milliseconds: 1000),
    this.scriptTimeout = const Duration(milliseconds: 900),
  });

  /// The active tab's `executeScript`, or null outside Web mode.
  final Future<Object?> Function(String script)? executeScript;

  /// A real click in the active view at device-pixel coordinates. Returns
  /// false when no view can take it (no tab, not started, an older host).
  final Future<bool> Function(double x, double y)? pageClick;

  /// The host's own reading: a page element owns the screen right now.
  final bool Function() pageFullscreen;

  /// The host's own leave: the document exits fullscreen and the window
  /// hand-off is released (BrowserScreen's `_releasePageFullscreen`).
  final Future<void> Function() exitPage;

  final bool Function() windowFullscreen;
  final Future<void> Function(bool on) setWindowFullscreen;

  final Duration poll;
  final Duration injectedWait;
  final Duration clickWait;
  final Duration scriptTimeout;

  /// [on] null = toggle (what the phone sends): anything fullscreen now →
  /// leave; nothing → enter.
  Future<RemoteFullscreenOutcome> run({bool? on}) async {
    final bool pageNow = pageFullscreen() || await _elementFullscreen();
    final bool windowNow = windowFullscreen();
    final bool want = on ?? !(pageNow || windowNow);

    if (!want) return _leave(pageNow);

    if (pageNow) {
      return const RemoteFullscreenOutcome(fullscreen: true, target: 'page');
    }

    final Map<Object?, Object?>? plan = await _plan();
    if (plan != null && plan['found'] == true) {
      if (plan['fullscreen'] == true) {
        return const RemoteFullscreenOutcome(fullscreen: true, target: 'page');
      }
      // Step 1's read-back: did the injected request take?
      if (plan['requested'] == true && await _waitForPage(injectedWait)) {
        return const RemoteFullscreenOutcome(fullscreen: true, target: 'page');
      }
      // Step 2: a real click on the player's own control.
      final Object? control = plan['control'];
      final Future<bool> Function(double, double)? click = pageClick;
      if (control is Map && click != null) {
        final Object? x = control['x'];
        final Object? y = control['y'];
        if (x is num && y is num && x.isFinite && y.isFinite) {
          bool clicked = false;
          try {
            clicked = await click(x.toDouble(), y.toDouble());
          } catch (_) {
            clicked = false;
          }
          if (clicked && await _waitForPage(clickWait)) {
            return const RemoteFullscreenOutcome(
                fullscreen: true, target: 'page');
          }
        }
      }
    }

    // Step 3: the page has no reachable player (or refused every attempt)
    // — the SALU window, the honest last choice.
    if (!windowFullscreen()) {
      try {
        await setWindowFullscreen(true);
      } catch (_) {}
    }
    return RemoteFullscreenOutcome(
      fullscreen: windowFullscreen(),
      target: 'window',
    );
  }

  Future<RemoteFullscreenOutcome> _leave(bool pageNow) async {
    if (pageNow) {
      try {
        await exitPage();
      } catch (_) {}
    }
    if (windowFullscreen()) {
      try {
        await setWindowFullscreen(false);
      } catch (_) {}
    }
    return RemoteFullscreenOutcome(
      fullscreen: false,
      target: pageNow ? 'page' : 'window',
    );
  }

  Future<Map<Object?, Object?>?> _plan() async {
    final Future<Object?> Function(String)? run = executeScript;
    if (run == null) return null;
    try {
      final Object? raw = await run(RemoteWebMediaScripts.fullscreenPlan())
          .timeout(scriptTimeout);
      return raw is Map ? raw : null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _elementFullscreen() async {
    final Future<Object?> Function(String)? run = executeScript;
    if (run == null) return false;
    try {
      final Object? raw = await run(RemoteWebMediaScripts.fullscreenState)
          .timeout(scriptTimeout);
      return raw == true;
    } catch (_) {
      return false;
    }
  }

  /// Polls the host's truth and the document's until either says the page
  /// is fullscreen, or [limit] runs out.
  Future<bool> _waitForPage(Duration limit) async {
    final Stopwatch clock = Stopwatch()..start();
    while (true) {
      if (pageFullscreen() || await _elementFullscreen()) return true;
      if (clock.elapsed >= limit) return false;
      await Future<void>.delayed(poll);
    }
  }
}
