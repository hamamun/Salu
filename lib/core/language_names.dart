/// ISO 639 code → readable language name (cc.md §7 file 9).
///
/// mpv reports track languages as **codes** (`en`, `jpn`, `hin` — ISO
/// 639-1/-2); the track panel (§6.3) and the search window (§6.5) must
/// show real names. One shared table, so the two surfaces can never
/// disagree about what `jpn` spells out.
///
/// Coverage: the Settings preferred-language list (§2.2), the D14 mock's
/// language set, and every widely-used code for the display-side lookups
/// (mpv may label a track with anything). Anything unknown falls back to
/// the uppercased code itself — an honest label, never invented words.
class LanguageNames {
  LanguageNames._();

  /// The Settings → Subtitles preferred-language list (§2.2 — curated,
  /// "more later", exactly this order).
  static const Map<String, String> preferred = <String, String>{
    'en': 'English',
    'bn': 'Bangla',
    'hi': 'Hindi',
    'ur': 'Urdu',
    'ar': 'Arabic',
    'es': 'Spanish',
    'fr': 'French',
    'de': 'German',
    'pt': 'Portuguese',
    'tr': 'Turkish',
    'id': 'Indonesian',
  };

  /// ISO 639-2 (three-letter) → ISO 639-1 normalized code. mpv track
  /// labels use these (and mpv passes OpenSubtitles' own two-letter
  /// codes straight through for external files).
  static const Map<String, String> _iso639_2to1 = <String, String>{
    'eng': 'en', 'ben': 'bn', 'hin': 'hi', 'urd': 'ur', 'ara': 'ar',
    'spa': 'es', 'fre': 'fr', 'fra': 'fr', 'ger': 'de', 'deu': 'de',
    'por': 'pt', 'tur': 'tr', 'ind': 'id', 'vie': 'vi', 'jpn': 'ja',
    'chi': 'zh', 'zho': 'zh', 'kor': 'ko', 'ita': 'it', 'rus': 'ru',
    'pol': 'pl', 'dut': 'nl', 'nld': 'nl', 'swe': 'sv', 'nor': 'no',
    'nob': 'nb', 'nno': 'nn', 'dan': 'da', 'fin': 'fi', 'gre': 'el',
    'ell': 'el', 'heb': 'he', 'tha': 'th', 'tam': 'ta', 'tel': 'te',
    'mar': 'mr', 'guj': 'gu', 'pan': 'pa', 'kan': 'kn', 'mal': 'ml',
    'tgl': 'tl', 'cze': 'cs', 'ces': 'cs', 'slk': 'sk', 'hun': 'hu',
    'rum': 'ro', 'ron': 'ro', 'bul': 'bg', 'ukr': 'uk', 'per': 'fa',
    'fas': 'fa', 'may': 'ms', 'msa': 'ms', 'ice': 'is', 'isl': 'is',
    'alb': 'sq', 'sqi': 'sq', 'hrv': 'hr', 'srp': 'sr', 'slo': 'sl',
    'slv': 'sl', 'cat': 'ca', 'baq': 'eu', 'eus': 'eu', 'glg': 'gl',
  };

  /// Displayable names keyed by normalized ISO 639-1 code. Starts from
  /// the curated list; grows with everything SALU may legitimately show.
  static const Map<String, String> _names = <String, String>{
    ...preferred,
    'vi': 'Vietnamese',
    'ja': 'Japanese',
    'zh': 'Chinese',
    'ko': 'Korean',
    'it': 'Italian',
    'ru': 'Russian',
    'pl': 'Polish',
    'nl': 'Dutch',
    'sv': 'Swedish',
    'nb': 'Norwegian',
    'no': 'Norwegian',
    'nn': 'Norwegian Nynorsk',
    'da': 'Danish',
    'fi': 'Finnish',
    'el': 'Greek',
    'he': 'Hebrew',
    'th': 'Thai',
    'ta': 'Tamil',
    'te': 'Telugu',
    'mr': 'Marathi',
    'gu': 'Gujarati',
    'pa': 'Punjabi',
    'kn': 'Kannada',
    'ml': 'Malayalam',
    'tl': 'Filipino',
    'cs': 'Czech',
    'sk': 'Slovak',
    'hu': 'Hungarian',
    'ro': 'Romanian',
    'bg': 'Bulgarian',
    'uk': 'Ukrainian',
    'fa': 'Persian',
    'ms': 'Malay',
    'is': 'Icelandic',
    'sq': 'Albanian',
    'hr': 'Croatian',
    'sr': 'Serbian',
    'sl': 'Slovenian',
    'ca': 'Catalan',
    'eu': 'Basque',
    'gl': 'Galician',
  };

  /// Normalizes any mpv / API code to an ISO 639-1 code when we know a
  /// mapping (`jpn` → `ja`); unknown codes pass through lowercased.
  static String normalize(String? code) {
    final String c = (code ?? '').trim().toLowerCase();
    if (c.isEmpty) return '';
    return _iso639_2to1[c] ?? c;
  }

  /// The readable name for a code (`jpn` → Japanese, `en` → English).
  /// Unknown / untagged languages return `null` so callers can fall back
  /// to the track's own title, never to invented words (§6.3).
  static String? nameOf(String? code) {
    final String normalized = normalize(code);
    if (normalized.isEmpty) return null;
    return _names[normalized];
  }
}
