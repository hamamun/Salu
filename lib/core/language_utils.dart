/// Language helpers shared by the OpenSubtitles search (Phase 7) and the
/// Settings language picker.
class LanguageUtils {
  LanguageUtils._();

  /// ISO-639-1 code → human language name (the set offered on OpenSubtitles).
  static const Map<String, String> names = <String, String>{
    'sq': 'Albanian',
    'ar': 'Arabic',
    'hy': 'Armenian',
    'af': 'Afrikaans',
    'be': 'Belarusian',
    'bs': 'Bosnian',
    'bg': 'Bulgarian',
    'ca': 'Catalan',
    'zh': 'Chinese',
    'hr': 'Croatian',
    'cs': 'Czech',
    'da': 'Danish',
    'nl': 'Dutch',
    'en': 'English',
    'et': 'Estonian',
    'fi': 'Finnish',
    'fr': 'French',
    'gl': 'Galician',
    'ka': 'Georgian',
    'de': 'German',
    'el': 'Greek',
    'he': 'Hebrew',
    'hi': 'Hindi',
    'hu': 'Hungarian',
    'is': 'Icelandic',
    'id': 'Indonesian',
    'ga': 'Irish',
    'it': 'Italian',
    'ja': 'Japanese',
    'kk': 'Kazakh',
    'ko': 'Korean',
    'lv': 'Latvian',
    'lt': 'Lithuanian',
    'mk': 'Macedonian',
    'ms': 'Malay',
    'no': 'Norwegian',
    'nb': 'Norwegian Bokmål',
    'nn': 'Norwegian Nynorsk',
    'fa': 'Persian',
    'pl': 'Polish',
    'pt': 'Portuguese',
    'ro': 'Romanian',
    'ru': 'Russian',
    'sr': 'Serbian',
    'sk': 'Slovak',
    'sl': 'Slovenian',
    'es': 'Spanish',
    'sv': 'Swedish',
    'th': 'Thai',
    'tr': 'Turkish',
    'uk': 'Ukrainian',
    'ur': 'Urdu',
    'vi': 'Vietnamese',
  };

  /// Languages offered in the Settings dropdown (plus "all languages").
  static const List<String> commonCodes = <String>[
    'en', 'ar', 'de', 'es', 'fr', 'it', 'nl', 'pl', 'pt', 'ro',
    'ru', 'sr', 'sv', 'tr', 'zh', 'ja', 'ko', 'cs', 'da', 'el',
  ];

  /// Codes without a country of their own get one so a flag can be drawn.
  static const Map<String, String> _flagCountry = <String, String>{
    'en': 'US',
    'ar': 'SA',
    'zh': 'CN',
    'pt': 'PT',
    'fa': 'IR',
    'he': 'IL',
    'ms': 'MY',
    'nb': 'NO',
    'nn': 'NO',
    'sr': 'RS',
    'ur': 'PK',
    'es': 'ES',
  };

  static String displayName(String code) {
    final String primary = _primary(code);
    return names[primary] ?? code.toUpperCase();
  }

  /// Two-letter country code for a language (e.g. `en` → `US`,
  /// `pt-br` → `BR`). Empty when it cannot be derived.
  static String countryCode(String code) {
    final String lower = code.toLowerCase();
    final int sep = lower.indexOf(RegExp(r'[-_]'));
    if (sep > 0 && lower.length - sep == 3) {
      return lower.substring(sep + 1);
    }
    final String primary = _primary(code);
    return _flagCountry[primary] ??
        (primary.length == 2 ? primary : '');
  }

  /// Emoji flag for a language code — renders as country letters on Windows
  /// (Segoe UI Emoji ships no flag glyphs), so the modal also draws a chip.
  static String flagEmoji(String code) {
    final String cc = countryCode(code).toUpperCase();
    if (cc.length != 2) return '🌐';
    final int a = 'A'.codeUnitAt(0);
    final String out = String.fromCharCode(0x1F1E6 + cc.codeUnitAt(0) - a) +
        String.fromCharCode(0x1F1E6 + cc.codeUnitAt(1) - a);
    return out;
  }

  static String _primary(String code) =>
      code.toLowerCase().split(RegExp(r'[-_]')).first;
}
