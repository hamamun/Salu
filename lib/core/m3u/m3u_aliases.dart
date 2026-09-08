/// Small ISO-3166 / ISO-639 alias tables (playlist_imp.md §10.2).
///
/// `tvg-country` is usually a code (`UK`, `GB`, `US`), `tvg-language` a word
/// or a code; without a map the group heads fragment into `UK` / `GB` /
/// `United Kingdom`. Recognised aliases share one canonical group name.
/// Unrecognised values are kept exactly as written (whole — a compound
/// value such as `English;Spanish` is one key, never split; §10.2).
///
/// This is alias *normalisation* of playlist-supplied text only — nothing
/// here guesses a country or language from an ID, name or URL (§10.2a).
library;

/// Canonical name → its aliases (codes and spellings), all matched
/// case-insensitively against the trimmed value. First column is the
/// canonical display name; the canonical name itself is an alias too.
const List<List<String>> _countryTable = <List<String>>[
  <String>['Afghanistan', 'af', 'afg'],
  <String>['Albania', 'al', 'alb'],
  <String>['Algeria', 'dz', 'dza'],
  <String>['Argentina', 'ar', 'arg'],
  <String>['Armenia', 'am', 'arm'],
  <String>['Australia', 'au', 'aus'],
  <String>['Austria', 'at', 'aut'],
  <String>['Azerbaijan', 'az', 'aze'],
  <String>['Bahrain', 'bh', 'bhr'],
  <String>['Bangladesh', 'bd', 'bgd'],
  <String>['Belarus', 'by', 'blr'],
  <String>['Belgium', 'be', 'bel'],
  <String>['Bolivia', 'bo', 'bol'],
  <String>['Bosnia and Herzegovina', 'ba', 'bih', 'bosnia'],
  <String>['Brazil', 'br', 'bra', 'brasil'],
  <String>['Bulgaria', 'bg', 'bgr'],
  <String>['Cambodia', 'kh', 'khm'],
  <String>['Cameroon', 'cm', 'cmr'],
  <String>['Canada', 'ca', 'can'],
  <String>['Chile', 'cl', 'chl'],
  <String>['China', 'cn', 'chn'],
  <String>['Colombia', 'co', 'col'],
  <String>['Costa Rica', 'cr', 'cri'],
  <String>['Croatia', 'hr', 'hrv'],
  <String>['Cuba', 'cu', 'cub'],
  <String>['Cyprus', 'cy', 'cyp'],
  <String>['Czechia', 'cz', 'cze', 'czech republic'],
  <String>['Denmark', 'dk', 'dnk'],
  <String>['Dominican Republic', 'do', 'dom'],
  <String>['Ecuador', 'ec', 'ecu'],
  <String>['Egypt', 'eg', 'egy'],
  <String>['El Salvador', 'sv', 'slv'],
  <String>['Estonia', 'ee', 'est'],
  <String>['Ethiopia', 'et', 'eth'],
  <String>['Finland', 'fi', 'fin'],
  <String>['France', 'fr', 'fra'],
  <String>['Georgia', 'ge', 'geo'],
  <String>['Germany', 'de', 'deu', 'deutschland'],
  <String>['Ghana', 'gh', 'gha'],
  <String>['Greece', 'gr', 'grc'],
  <String>['Guatemala', 'gt', 'gtm'],
  <String>['Honduras', 'hn', 'hnd'],
  <String>['Hong Kong', 'hk', 'hkg'],
  <String>['Hungary', 'hu', 'hun'],
  <String>['Iceland', 'is', 'isl'],
  <String>['India', 'in', 'ind'],
  <String>['Indonesia', 'id', 'idn'],
  <String>['Iran', 'ir', 'irn'],
  <String>['Iraq', 'iq', 'irq'],
  <String>['Ireland', 'ie', 'irl'],
  <String>['Israel', 'il', 'isr'],
  <String>['Italy', 'it', 'ita', 'italia'],
  <String>['Jamaica', 'jm', 'jam'],
  <String>['Japan', 'jp', 'jpn'],
  <String>['Jordan', 'jo', 'jor'],
  <String>['Kazakhstan', 'kz', 'kaz'],
  <String>['Kenya', 'ke', 'ken'],
  <String>['Kuwait', 'kw', 'kwt'],
  <String>['Latvia', 'lv', 'lva'],
  <String>['Lebanon', 'lb', 'lbn'],
  <String>['Libya', 'ly', 'lby'],
  <String>['Lithuania', 'lt', 'ltu'],
  <String>['Luxembourg', 'lu', 'lux'],
  <String>['Malaysia', 'my', 'mys'],
  <String>['Malta', 'mt', 'mlt'],
  <String>['Mexico', 'mx', 'mex', 'méxico'],
  <String>['Moldova', 'md', 'mda'],
  <String>['Montenegro', 'me', 'mne'],
  <String>['Morocco', 'ma', 'mar'],
  <String>['Nepal', 'np', 'npl'],
  <String>['Netherlands', 'nl', 'nld', 'the netherlands', 'holland'],
  <String>['New Zealand', 'nz', 'nzl'],
  <String>['Nigeria', 'ng', 'nga'],
  <String>['North Macedonia', 'mk', 'mkd', 'macedonia'],
  <String>['Norway', 'no', 'nor'],
  <String>['Oman', 'om', 'omn'],
  <String>['Pakistan', 'pk', 'pak'],
  <String>['Palestine', 'ps', 'pse'],
  <String>['Panama', 'pa', 'pan'],
  <String>['Paraguay', 'py', 'pry'],
  <String>['Peru', 'pe', 'per'],
  <String>['Philippines', 'ph', 'phl'],
  <String>['Poland', 'pl', 'pol', 'polska'],
  <String>['Portugal', 'pt', 'prt'],
  <String>['Puerto Rico', 'pr', 'pri'],
  <String>['Qatar', 'qa', 'qat'],
  <String>['Romania', 'ro', 'rou', 'românia'],
  <String>['Russia', 'ru', 'rus', 'russian federation'],
  <String>['Saudi Arabia', 'sa', 'sau', 'ksa'],
  <String>['Senegal', 'sn', 'sen'],
  <String>['Serbia', 'rs', 'srb'],
  <String>['Singapore', 'sg', 'sgp'],
  <String>['Slovakia', 'sk', 'svk'],
  <String>['Slovenia', 'si', 'svn'],
  <String>['Somalia', 'so', 'som'],
  <String>['South Africa', 'za', 'zaf'],
  <String>['South Korea', 'kr', 'kor', 'korea', 'republic of korea'],
  <String>['Spain', 'es', 'esp', 'españa'],
  <String>['Sri Lanka', 'lk', 'lka'],
  <String>['Sudan', 'sd', 'sdn'],
  <String>['Sweden', 'se', 'swe'],
  <String>['Switzerland', 'ch', 'che'],
  <String>['Syria', 'sy', 'syr'],
  <String>['Taiwan', 'tw', 'twn'],
  <String>['Tanzania', 'tz', 'tza'],
  <String>['Thailand', 'th', 'tha'],
  <String>['Tunisia', 'tn', 'tun'],
  <String>['Turkey', 'tr', 'tur', 'türkiye', 'turkiye'],
  <String>['Uganda', 'ug', 'uga'],
  <String>['Ukraine', 'ua', 'ukr'],
  <String>['United Arab Emirates', 'ae', 'are', 'uae'],
  <String>['United Kingdom', 'gb', 'gbr', 'uk', 'great britain', 'britain'],
  <String>['United States', 'us', 'usa', 'united states of america'],
  <String>['Uruguay', 'uy', 'ury'],
  <String>['Uzbekistan', 'uz', 'uzb'],
  <String>['Venezuela', 've', 'ven'],
  <String>['Vietnam', 'vn', 'vnm', 'viet nam'],
  <String>['Yemen', 'ye', 'yem'],
  <String>['Zimbabwe', 'zw', 'zwe'],
];

/// Canonical language name → ISO 639-1 / 639-2 codes and spellings.
/// `Bangla` follows the approved preview (design/iptv-channel-preview).
const List<List<String>> _languageTable = <List<String>>[
  <String>['Afrikaans', 'af', 'afr'],
  <String>['Albanian', 'sq', 'sqi', 'alb'],
  <String>['Amharic', 'am', 'amh'],
  <String>['Arabic', 'ar', 'ara', 'العربية'],
  <String>['Armenian', 'hy', 'hye', 'arm'],
  <String>['Assamese', 'as', 'asm'],
  <String>['Azerbaijani', 'az', 'aze', 'azeri'],
  <String>['Bangla', 'bn', 'ben', 'bengali', 'বাংলা'],
  <String>['Basque', 'eu', 'eus', 'baq'],
  <String>['Belarusian', 'be', 'bel'],
  <String>['Bosnian', 'bs', 'bos'],
  <String>['Bulgarian', 'bg', 'bul'],
  <String>['Burmese', 'my', 'mya', 'bur'],
  <String>['Catalan', 'ca', 'cat', 'català'],
  <String>['Chinese', 'zh', 'zho', 'chi', '中文'],
  <String>['Croatian', 'hr', 'hrv', 'hrvatski'],
  <String>['Czech', 'cs', 'ces', 'cze', 'čeština'],
  <String>['Danish', 'da', 'dan', 'dansk'],
  <String>['Dutch', 'nl', 'nld', 'dut', 'nederlands'],
  <String>['English', 'en', 'eng'],
  <String>['Estonian', 'et', 'est'],
  <String>['Filipino', 'tl', 'tgl', 'fil', 'tagalog'],
  <String>['Finnish', 'fi', 'fin', 'suomi'],
  <String>['French', 'fr', 'fra', 'fre', 'français', 'francais'],
  <String>['Galician', 'gl', 'glg'],
  <String>['Georgian', 'ka', 'kat', 'geo'],
  <String>['German', 'de', 'deu', 'ger', 'deutsch'],
  <String>['Greek', 'el', 'ell', 'gre', 'ελληνικά'],
  <String>['Gujarati', 'gu', 'guj'],
  <String>['Hausa', 'ha', 'hau'],
  <String>['Hebrew', 'he', 'heb', 'עברית'],
  <String>['Hindi', 'hi', 'hin', 'हिन्दी'],
  <String>['Hungarian', 'hu', 'hun', 'magyar'],
  <String>['Icelandic', 'is', 'isl', 'ice'],
  <String>['Igbo', 'ig', 'ibo'],
  <String>['Indonesian', 'id', 'ind', 'bahasa indonesia'],
  <String>['Irish', 'ga', 'gle'],
  <String>['Italian', 'it', 'ita', 'italiano'],
  <String>['Japanese', 'ja', 'jpn', '日本語'],
  <String>['Kannada', 'kn', 'kan'],
  <String>['Kazakh', 'kk', 'kaz'],
  <String>['Khmer', 'km', 'khm'],
  <String>['Korean', 'ko', 'kor', '한국어'],
  <String>['Kurdish', 'ku', 'kur'],
  <String>['Kyrgyz', 'ky', 'kir'],
  <String>['Lao', 'lo'],
  <String>['Latvian', 'lv', 'lav'],
  <String>['Lithuanian', 'lt', 'lit'],
  <String>['Macedonian', 'mk', 'mkd', 'mac'],
  <String>['Malay', 'ms', 'msa', 'may', 'bahasa melayu'],
  <String>['Malayalam', 'ml', 'mal'],
  <String>['Maltese', 'mt', 'mlt'],
  <String>['Marathi', 'mr', 'mar'],
  <String>['Mongolian', 'mn', 'mon'],
  <String>['Nepali', 'ne', 'nep'],
  <String>['Norwegian', 'no', 'nor', 'nb', 'nob', 'nn', 'nno', 'norsk'],
  <String>['Odia', 'or', 'ori', 'oriya'],
  <String>['Pashto', 'ps', 'pus'],
  <String>['Persian', 'fa', 'fas', 'per', 'farsi', 'فارسی'],
  <String>['Polish', 'pl', 'pol', 'polski'],
  <String>['Portuguese', 'pt', 'por', 'português', 'portugues'],
  <String>['Punjabi', 'pa', 'pan'],
  <String>['Romanian', 'ro', 'ron', 'rum', 'română'],
  <String>['Russian', 'ru', 'rus', 'русский'],
  <String>['Serbian', 'sr', 'srp', 'srpski'],
  <String>['Sindhi', 'sd', 'snd'],
  <String>['Sinhala', 'si', 'sin', 'sinhalese'],
  <String>['Slovak', 'sk', 'slk', 'slo'],
  <String>['Slovenian', 'sl', 'slv'],
  <String>['Somali', 'so', 'som'],
  <String>['Spanish', 'es', 'spa', 'español', 'espanol'],
  <String>['Swahili', 'sw', 'swa'],
  <String>['Swedish', 'sv', 'swe', 'svenska'],
  <String>['Tajik', 'tg', 'tgk'],
  <String>['Tamil', 'ta', 'tam', 'தமிழ்'],
  <String>['Telugu', 'te', 'tel'],
  <String>['Thai', 'th', 'tha', 'ไทย'],
  <String>['Tibetan', 'bo', 'bod', 'tib'],
  <String>['Turkish', 'tr', 'tur', 'türkçe', 'turkce'],
  <String>['Turkmen', 'tk', 'tuk'],
  <String>['Ukrainian', 'uk', 'ukr', 'українська'],
  <String>['Urdu', 'ur', 'urd', 'اردو'],
  <String>['Uyghur', 'ug', 'uig'],
  <String>['Uzbek', 'uz', 'uzb'],
  <String>['Vietnamese', 'vi', 'vie', 'tiếng việt'],
  <String>['Welsh', 'cy', 'cym', 'wel'],
  <String>['Yoruba', 'yo', 'yor'],
  <String>['Zulu', 'zu', 'zul'],
];

Map<String, String> _build(List<List<String>> table) {
  final Map<String, String> out = <String, String>{};
  for (final List<String> row in table) {
    final String canonical = row.first;
    out[canonical.toLowerCase()] = canonical;
    for (int i = 1; i < row.length; i++) {
      out[row[i]] = canonical;
    }
  }
  return out;
}

final Map<String, String> _countries = _build(_countryTable);
final Map<String, String> _languages = _build(_languageTable);

String? _normalise(String? value, Map<String, String> aliases) {
  if (value == null) return null;
  final String s = value.trim();
  if (s.isEmpty) return null;
  return aliases[s.toLowerCase()] ?? s;
}

/// `tvg-country` → canonical country name, or the trimmed original when
/// unrecognised; `null` when missing/blank.
String? normaliseCountry(String? value) => _normalise(value, _countries);

/// `tvg-language` → canonical language name, or the trimmed original when
/// unrecognised; `null` when missing/blank.
String? normaliseLanguage(String? value) => _normalise(value, _languages);
