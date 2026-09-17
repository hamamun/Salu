import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../settings_service.dart';

/// One per-site pop-up rule — Chrome/Edge's "Pop-ups and redirects"
/// Allowed / Blocked lists, kept to exact hosts (no patterns, no
/// wildcards), so the site panel, the badge and the policy can never
/// disagree about a name.
@immutable
class WebPopupException {
  const WebPopupException({required this.host, required this.allow});

  /// Lowercase host, `www.` stripped — the key [WebPopupService.keyFor]
  /// answers with for any URL or bare host.
  final String host;

  /// true = this site may open pop-ups; false = it may not, even when the
  /// global default says otherwise.
  final bool allow;

  Map<String, Object?> toJson() => <String, Object?>{
        'host': host,
        'allow': allow,
      };

  static WebPopupException? fromJson(Object? raw) {
    if (raw is! Map<String, Object?>) return null;
    final Object? host = raw['host'];
    final Object? allow = raw['allow'];
    if (host is! String || host.isEmpty) return null;
    if (allow is! bool) return null;
    return WebPopupException(host: host, allow: allow);
  }
}

/// Who may open pop-ups (web.md · pop-ups lock, 2026-09-17 cut).
///
/// The global default lives in [SettingsService] (`webPopupDefault` —
/// Block unless the viewer says otherwise); the per-site overrides live
/// here, persisted instantly like every other SALU list. On top of both
/// sit the "for this visit" memories: ad-boom clones rotate domains too
/// fast for permanent rules, so a visit-only decision evaporates with the
/// browsing session instead of rotting in the list.
class WebPopupService {
  WebPopupService._internal();

  static final WebPopupService instance = WebPopupService._internal();

  static const String _prefsKey = 'web_popup_exceptions';

  /// Upper bound on the persisted rules (bounds the prefs blob; the visit
  /// memories are a session's dust and stay uncounted).
  static const int maxExceptions = 200;

  /// The persisted per-site rules, alphabetical by host.
  final ValueNotifier<List<WebPopupException>> exceptions =
      ValueNotifier<List<WebPopupException>>(const <WebPopupException>[]);

  /// "For this visit" memories — never persisted, cleared by [endSession].
  final Set<String> _visitAllow = <String>{};
  final Set<String> _visitBlock = <String>{};

  bool _loaded = false;
  Future<void> _lastWrite = Future<void>.value();

  /// Reads the persisted rules once (safe to call repeatedly).
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return;
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) return;
      exceptions.value = decoded
          .map((Object? e) => WebPopupException.fromJson(
              e is Map ? e.cast<String, Object?>() : e))
          .whereType<WebPopupException>()
          .take(maxExceptions)
          .toList(growable: false);
    } catch (_) {
      // Corrupt prefs — start clean, silently.
      exceptions.value = const <WebPopupException>[];
    }
  }

  Future<void> _persist() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode(exceptions.value
            .map((WebPopupException e) => e.toJson())
            .toList(growable: false)),
      );
    } catch (_) {
      // In-memory state is already correct; persistence is best-effort.
    }
  }

  void _set(List<WebPopupException> next) {
    next.sort((WebPopupException a, WebPopupException b) =>
        a.host.compareTo(b.host));
    exceptions.value = List<WebPopupException>.unmodifiable(next);
    _lastWrite = _persist();
  }

  /// Completes the pending write — the close guard's bookkeeping.
  Future<void> flush() => _lastWrite;

  /// The policy key for [raw] — a URL or a bare host, lowercased, `www.`
  /// stripped. `''` when there is no host to rule about.
  static String keyFor(String? raw) {
    final String text = (raw ?? '').trim().toLowerCase();
    if (text.isEmpty) return '';
    final String parsed = Uri.tryParse(text)?.host.toLowerCase() ?? '';
    if (parsed.isNotEmpty) return _stripWww(parsed);
    // A bare host (`example.com`) parses with no host of its own — take it
    // as-is when it reads as one, reject the rest.
    if (text.contains(RegExp(r'[\s/:?#@]'))) return '';
    return _stripWww(text);
  }

  static String _stripWww(String host) =>
      host.startsWith('www.') ? host.substring(4) : host;

  /// The persisted rule for [url]'s site, if one was ever made.
  WebPopupException? findFor(String? url) {
    final String key = keyFor(url);
    if (key.isEmpty) return null;
    for (final WebPopupException e in exceptions.value) {
      if (e.host == key) return e;
    }
    return null;
  }

  /// The visit-only memory for [url]: true / false, or null when this
  /// visit said nothing about the site.
  bool? visitState(String? url) {
    final String key = keyFor(url);
    if (key.isEmpty) return null;
    if (_visitBlock.contains(key)) return false;
    if (_visitAllow.contains(key)) return true;
    return null;
  }

  /// Whether [pageUrl]'s site may open pop-ups right now: the visit memory
  /// wins, then the site rule, then the global default.
  bool resolve(String? pageUrl) {
    final bool? visit = visitState(pageUrl);
    if (visit != null) return visit;
    final WebPopupException? rule = findFor(pageUrl);
    if (rule != null) return rule.allow;
    return SettingsService.instance.webPopupDefault.value ==
        WebPopupDefault.allow;
  }

  /// Remembers [allow] for [url]'s site, permanently. A permanent rule
  /// clears any visit memory for the host — the newest decision wins.
  void setFor(String? url, bool allow) {
    final String key = keyFor(url);
    if (key.isEmpty) return;
    _visitAllow.remove(key);
    _visitBlock.remove(key);
    final List<WebPopupException> list =
        List<WebPopupException>.of(exceptions.value);
    list.removeWhere((WebPopupException e) => e.host == key);
    if (list.length >= maxExceptions) return;
    list.add(WebPopupException(host: key, allow: allow));
    _set(list);
  }

  /// Forgets [url]'s site entirely — rule and visit memory alike.
  void removeFor(String? url) {
    final String key = keyFor(url);
    if (key.isEmpty) return;
    _visitAllow.remove(key);
    _visitBlock.remove(key);
    final List<WebPopupException> list =
        List<WebPopupException>.of(exceptions.value);
    list.removeWhere((WebPopupException e) => e.host == key);
    _set(list);
  }

  /// Lets [url]'s site open pop-ups until the browsing session ends —
  /// the ad-boom answer: no permanent rule for a disposable domain.
  void allowVisit(String? url) {
    final String key = keyFor(url);
    if (key.isEmpty) return;
    _visitBlock.remove(key);
    _visitAllow.add(key);
  }

  /// Holds [url]'s site back until the browsing session ends, even under
  /// an Allow default or rule.
  void blockVisit(String? url) {
    final String key = keyFor(url);
    if (key.isEmpty) return;
    _visitAllow.remove(key);
    _visitBlock.add(key);
  }

  /// The browsing session ended (the browser surface tore down) — the
  /// visit memories evaporate. The persisted rules stay exactly as made.
  void endSession() {
    _visitAllow.clear();
    _visitBlock.clear();
  }
}
