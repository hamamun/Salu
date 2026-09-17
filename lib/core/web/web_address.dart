/// Address-bar semantics for SALU's built-in browser (web.md · the
/// address bar is LOCKED to Edge/Chrome behaviour).
///
/// Pure functions only — no Flutter, no I/O — so the classification rules
/// are unit-testable (`test/web_address_test.dart`). Google is the only
/// search engine SALU navigates to (web.md · address bar lock).
class WebAddress {
  WebAddress._();

  /// Upper bound on any one address-bar input, matching the URL cap the
  /// Open-URL modal already enforces (`UrlLibraryService.looksLikeUrl`).
  static const int maxInputLength = 2048;

  /// Where Enter sends the current tab: a typed URL navigates as-is,
  /// anything else becomes a Google results page (web.md · lock (2)).
  static String navigateTarget(String raw) => urlFrom(raw) ?? searchUrl(raw);

  /// Returns the navigable URL [raw] already spells, or `null` when the
  /// input reads as a search query instead.
  ///
  /// Chrome/Edge rules, kept small and predictable:
  /// · empty, multi-word, or over-long input → search;
  /// · an explicit `http` / `https` / `ftp` scheme with a host → navigate;
  ///   any other scheme (or a scheme without a host) → search;
  /// · a bare host — dotted TLD, `localhost`, an IPv4 literal, optionally
  ///   with `:port`, path and query — navigates over `https`;
  /// · anything else is a query.
  static String? urlFrom(String raw) {
    final String text = raw.trim();
    if (text.isEmpty ||
        text.length > maxInputLength ||
        _hasWhitespace.hasMatch(text)) {
      return null;
    }

    final RegExpMatch? schemeMatch = _schemePattern.matchAsPrefix(text);
    if (schemeMatch != null) {
      final String scheme = schemeMatch.group(1)!.toLowerCase();
      if (scheme != 'http' && scheme != 'https' && scheme != 'ftp') {
        return null;
      }
      final Uri? uri = Uri.tryParse(text);
      if (uri == null || uri.host.isEmpty) return null;
      return text;
    }

    // Bare authority — everything before the first path/query/fragment
    // separator is the host[:port] candidate.
    final RegExpMatch? cut = _authorityEnd.firstMatch(text);
    final int end = cut?.start ?? text.length;
    final String authority = text.substring(0, end);
    if (authority.isEmpty) return null;
    if (authority.contains('@')) return null; // user:pass@ never navigates

    String host = authority;
    final int colon = host.indexOf(':');
    if (colon > 0) {
      final String port = host.substring(colon + 1);
      if (!_digits.hasMatch(port) || port.length > 5) return null;
      host = host.substring(0, colon);
    }
    if (host.isEmpty || host.endsWith('-') || host.startsWith('-')) {
      return null;
    }
    if (host == 'localhost' || _isIpv4(host)) return 'https://$text';

    // A dotted host with an all-letter TLD reads as a domain.
    final int lastDot = host.lastIndexOf('.');
    if (lastDot <= 0 || lastDot == host.length - 1) return null;
    final String tld = host.substring(lastDot + 1);
    if (!_tld.hasMatch(tld)) return null;
    for (final String label in host.split('.')) {
      if (label.isEmpty || label.startsWith('-')) return null;
    }
    return 'https://$text';
  }

  /// Google's results page for [query] — the single search engine (lock).
  static String searchUrl(String query) =>
      'https://www.google.com/search?q=${Uri.encodeComponent(query.trim())}';

  /// Host without the leading `www.` — the label shown in tab tooltips
  /// and empty-title rows.
  static String hostOf(String url) {
    final String host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    if (host.startsWith('www.')) return host.substring(4);
    return host.isNotEmpty ? host : url;
  }

  /// A short human label for [url] when no page title exists yet: the
  /// query for a Google results page (what Chrome shows), the host for
  /// everything else.
  static String labelFor(String url) {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) return url;
    final String host = uri.host.toLowerCase();
    if (host == 'google.com' ||
        host == 'www.google.com' ||
        host.endsWith('.google.com')) {
      final String? q = uri.queryParameters['q'];
      if (q != null && q.trim().isNotEmpty) return q.trim();
    }
    return hostOf(url);
  }

  /// Chrome-style canonical form used for "is this page already saved /
  /// already the same visit?" comparisons: lowercase host, no scheme, no
  /// trailing slash, query kept, fragment dropped.
  static String canonical(String url) {
    final Uri? uri = Uri.tryParse(url.trim());
    if (uri == null || uri.host.isEmpty) return url.trim().toLowerCase();
    String path = uri.path.isEmpty ? '/' : uri.path;
    if (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    final String query =
        uri.hasQuery && uri.query.isNotEmpty ? '?${uri.query}' : '';
    return '${uri.host.toLowerCase()}$path$query';
  }

  /// Whether two URLs point at the same page (same rules as [canonical]).
  static bool samePage(String a, String b) => canonical(a) == canonical(b);

  static final RegExp _hasWhitespace = RegExp(r'\s');
  static final RegExp _schemePattern =
      RegExp(r'^([a-zA-Z][a-zA-Z0-9+.\-]*):');
  static final RegExp _authorityEnd = RegExp(r'[/?#]');
  static final RegExp _digits = RegExp(r'^\d+$');
  static final RegExp _tld = RegExp(r'^[a-zA-Z]{2,}$');
  static final RegExp _ipv4 = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');

  static bool _isIpv4(String host) {
    if (!_ipv4.hasMatch(host)) return false;
    for (final String part in host.split('.')) {
      final int octet = int.tryParse(part) ?? -1;
      if (octet < 0 || octet > 255) return false;
    }
    return true;
  }
}
