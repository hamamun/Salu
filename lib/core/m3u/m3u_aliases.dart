/// Small ISO-3166 / ISO-639 alias tables (playlist_imp.md §10.2, §10.2a rev.
/// 2026-09-09).
///
/// `tvg-country` is usually a code (`UK`, `GB`, `US`), `tvg-language` a word
/// or a code; without a map the group heads fragment into `UK` / `GB` /
/// `United Kingdom`. Recognised aliases share one canonical group name.
/// Unrecognised values are kept exactly as written (whole — a compound
/// value such as `English;Spanish` is one key, never split; §10.2).
///
/// Two lookup shapes, because two very different callers use them:
///
/// - [normaliseCountry] / [normaliseLanguage] / [countryForToken] /
///   [languageForToken] accept **anything** the table knows — a two-letter
///   code included. They are for *structured* text: a tag value, a bracketed
///   tag, a `CC |` head, a `?lang=` parameter.
/// - [countryInText] / [languageInText] / [countryNameForToken] /
///   [languageNameForToken] accept **names only** (a canonical name, a
///   multi-letter alias, a demonym). They are for *free-text* scans of a
///   group title or a channel label, where a bare `IN` or `MY` is part of a
///   name far more often than it is Assamese or Burmese.
///
/// Nothing here looks anything up outside the playlist (§10.2a).
library;

/// Canonical name → its aliases (codes and spellings), all matched
/// case-insensitively against the trimmed value. First column is the
/// canonical display name; the canonical name itself is an alias too.
const List<List<String>> _countryTable = <List<String>>[
  <String>['Afghanistan', 'af', 'afg'],
  <String>['Albania', 'al', 'alb'],
  <String>['Algeria', 'dz', 'dza'],
  <String>['Andorra', 'ad', 'and'],
  <String>['Angola', 'ao', 'ago'],
  <String>['Argentina', 'ar', 'arg'],
  <String>['Armenia', 'am', 'arm'],
  <String>['Aruba', 'aw', 'abw'],
  <String>['Australia', 'au', 'aus'],
  <String>['Austria', 'at', 'aut'],
  <String>['Azerbaijan', 'az', 'aze'],
  <String>['Bahamas', 'bs', 'bhs'],
  <String>['Bahrain', 'bh', 'bhr'],
  <String>['Bangladesh', 'bd', 'bgd'],
  <String>['Barbados', 'bb', 'brb'],
  <String>['Belarus', 'by', 'blr'],
  <String>['Belgium', 'be', 'bel'],
  <String>['Belize', 'bz', 'blz'],
  <String>['Bermuda', 'bm', 'bmu'],
  <String>['Bhutan', 'bt', 'btn'],
  <String>['Bolivia', 'bo', 'bol'],
  <String>['Bosnia and Herzegovina', 'ba', 'bih', 'bosnia'],
  <String>['Botswana', 'bw', 'bwa'],
  <String>['Brazil', 'br', 'bra', 'brasil'],
  <String>['Brunei', 'bn', 'brn', 'brunei darussalam'],
  <String>['Bulgaria', 'bg', 'bgr'],
  <String>['Burkina Faso', 'bf', 'bfa'],
  <String>['Burundi', 'bi', 'bdi'],
  <String>['Cabo Verde', 'cv', 'cpv', 'cape verde'],
  <String>['Cambodia', 'kh', 'khm'],
  <String>['Cameroon', 'cm', 'cmr'],
  <String>['Canada', 'ca', 'can'],
  <String>['Cayman Islands', 'ky', 'cym'],
  <String>['Chad', 'td', 'tcd'],
  <String>['Chile', 'cl', 'chl'],
  <String>['China', 'cn', 'chn'],
  <String>['Colombia', 'co', 'col'],
  <String>['Comoros', 'km', 'com'],
  <String>['Congo', 'cg', 'cog'],
  <String>['Cook Islands', 'ck', 'cok'],
  <String>['Costa Rica', 'cr', 'cri'],
  <String>['Croatia', 'hr', 'hrv'],
  <String>['Cuba', 'cu', 'cub'],
  <String>['Curaçao', 'cw', 'cuw', 'curacao'],
  <String>['Cyprus', 'cy', 'cyp'],
  <String>['Czechia', 'cz', 'cze', 'czech republic'],
  <String>['Democratic Republic of the Congo', 'cd', 'cod', 'dr congo', 'congo dr'],
  <String>['Denmark', 'dk', 'dnk'],
  <String>['Djibouti', 'dj', 'dji'],
  <String>['Dominica', 'dm', 'dma'],
  <String>['Dominican Republic', 'do', 'dom'],
  <String>['Ecuador', 'ec', 'ecu'],
  <String>['Egypt', 'eg', 'egy'],
  <String>['El Salvador', 'sv', 'slv'],
  <String>['Equatorial Guinea', 'gq', 'gnq'],
  <String>['Eritrea', 'er', 'eri'],
  <String>['Estonia', 'ee', 'est'],
  <String>['Eswatini', 'sz', 'swz', 'swaziland'],
  <String>['Ethiopia', 'et', 'eth'],
  <String>['Falkland Islands', 'fk', 'flk'],
  <String>['Faroe Islands', 'fo', 'fro'],
  <String>['Fiji', 'fj', 'fji'],
  <String>['Finland', 'fi', 'fin'],
  <String>['France', 'fr', 'fra'],
  <String>['French Guiana', 'gf', 'guf'],
  <String>['French Polynesia', 'pf', 'pyf'],
  <String>['Gabon', 'ga', 'gab'],
  <String>['Gambia', 'gm', 'gmb'],
  <String>['Georgia', 'ge', 'geo'],
  <String>['Germany', 'de', 'deu', 'deutschland'],
  <String>['Ghana', 'gh', 'gha'],
  <String>['Gibraltar', 'gi', 'gib'],
  <String>['Greece', 'gr', 'grc'],
  <String>['Greenland', 'gl', 'grl'],
  <String>['Grenada', 'gd', 'grd'],
  <String>['Guadeloupe', 'gp', 'glp'],
  <String>['Guam', 'gu', 'gum'],
  <String>['Guatemala', 'gt', 'gtm'],
  <String>['Guinea', 'gn', 'gin'],
  <String>['Guinea-Bissau', 'gw', 'gnb'],
  <String>['Guyana', 'gy', 'guy'],
  <String>['Haiti', 'ht', 'hti'],
  <String>['Honduras', 'hn', 'hnd'],
  <String>['Hong Kong', 'hk', 'hkg'],
  <String>['Hungary', 'hu', 'hun'],
  <String>['Iceland', 'is', 'isl'],
  <String>['India', 'in', 'ind'],
  <String>['Indonesia', 'id', 'idn'],
  <String>['Iran', 'ir', 'irn'],
  <String>['Iraq', 'iq', 'irq'],
  <String>['Ireland', 'ie', 'irl'],
  <String>['Isle of Man', 'im', 'imn'],
  <String>['Israel', 'il', 'isr'],
  <String>['Italy', 'it', 'ita', 'italia'],
  <String>['Jamaica', 'jm', 'jam'],
  <String>['Japan', 'jp', 'jpn'],
  <String>['Jersey', 'je', 'jey'],
  <String>['Jordan', 'jo', 'jor'],
  <String>['Kazakhstan', 'kz', 'kaz'],
  <String>['Kenya', 'ke', 'ken'],
  <String>['Kiribati', 'ki', 'kir'],
  <String>['Kosovo', 'xk', 'xkk'],
  <String>['Kuwait', 'kw', 'kwt'],
  <String>['Laos', 'la', 'lao'],
  <String>['Latvia', 'lv', 'lva'],
  <String>['Lebanon', 'lb', 'lbn'],
  <String>['Lesotho', 'ls', 'lso'],
  <String>['Liberia', 'lr', 'lbr'],
  <String>['Libya', 'ly', 'lby'],
  <String>['Liechtenstein', 'li', 'lie'],
  <String>['Lithuania', 'lt', 'ltu'],
  <String>['Luxembourg', 'lu', 'lux'],
  <String>['Macau', 'mo', 'mac', 'macao'],
  <String>['Madagascar', 'mg', 'mdg'],
  <String>['Malawi', 'mw', 'mwi'],
  <String>['Malaysia', 'my', 'mys'],
  <String>['Maldives', 'mv', 'mdv'],
  <String>['Mali', 'ml', 'mli'],
  <String>['Malta', 'mt', 'mlt'],
  <String>['Marshall Islands', 'mh', 'mhl'],
  <String>['Martinique', 'mq', 'mtq'],
  <String>['Mauritania', 'mr', 'mrt'],
  <String>['Mauritius', 'mu', 'mus'],
  <String>['Mexico', 'mx', 'mex', 'méxico'],
  <String>['Micronesia', 'fm', 'fsm'],
  <String>['Moldova', 'md', 'mda'],
  <String>['Monaco', 'mc', 'mco'],
  <String>['Mongolia', 'mn', 'mng'],
  <String>['Montenegro', 'me', 'mne'],
  <String>['Morocco', 'ma', 'mar'],
  <String>['Mozambique', 'mz', 'moz'],
  <String>['Myanmar', 'mm', 'mmr', 'burma'],
  <String>['Namibia', 'na', 'nam'],
  <String>['Nauru', 'nr', 'nru'],
  <String>['Nepal', 'np', 'npl'],
  <String>['Netherlands', 'nl', 'nld', 'the netherlands', 'holland'],
  <String>['New Caledonia', 'nc', 'ncl'],
  <String>['New Zealand', 'nz', 'nzl'],
  <String>['Nicaragua', 'ni', 'nic'],
  <String>['Niger', 'ne', 'ner'],
  <String>['Nigeria', 'ng', 'nga'],
  <String>['North Korea', 'kp', 'prk', 'democratic people\'s republic of korea'],
  <String>['North Macedonia', 'mk', 'mkd', 'macedonia'],
  <String>['Norway', 'no', 'nor'],
  <String>['Oman', 'om', 'omn'],
  <String>['Pakistan', 'pk', 'pak'],
  <String>['Palau', 'pw', 'plw'],
  <String>['Palestine', 'ps', 'pse'],
  <String>['Panama', 'pa', 'pan'],
  <String>['Papua New Guinea', 'pg', 'png'],
  <String>['Paraguay', 'py', 'pry'],
  <String>['Peru', 'pe', 'per'],
  <String>['Philippines', 'ph', 'phl'],
  <String>['Poland', 'pl', 'pol', 'polska'],
  <String>['Portugal', 'pt', 'prt'],
  <String>['Puerto Rico', 'pr', 'pri'],
  <String>['Qatar', 'qa', 'qat'],
  <String>['Romania', 'ro', 'rou', 'românia'],
  <String>['Russia', 'ru', 'rus', 'russian federation'],
  <String>['Rwanda', 'rw', 'rwa'],
  <String>['Réunion', 're', 'reu', 'reunion'],
  <String>['Saint Kitts and Nevis', 'kn', 'kna'],
  <String>['Saint Lucia', 'lc', 'lca'],
  <String>['Saint Vincent and the Grenadines', 'vc', 'vct'],
  <String>['Samoa', 'ws', 'wsm'],
  <String>['San Marino', 'sm', 'smr'],
  <String>['Saudi Arabia', 'sa', 'sau', 'ksa'],
  <String>['Senegal', 'sn', 'sen'],
  <String>['Serbia', 'rs', 'srb'],
  <String>['Seychelles', 'sc', 'syc'],
  <String>['Sierra Leone', 'sl', 'sle'],
  <String>['Singapore', 'sg', 'sgp'],
  <String>['Sint Maarten', 'sx', 'sxm'],
  <String>['Slovakia', 'sk', 'svk'],
  <String>['Slovenia', 'si', 'svn'],
  <String>['Solomon Islands', 'sb', 'slb'],
  <String>['Somalia', 'so', 'som'],
  <String>['South Africa', 'za', 'zaf'],
  <String>['South Korea', 'kr', 'kor', 'korea', 'republic of korea'],
  <String>['South Sudan', 'ss', 'ssd'],
  <String>['Spain', 'es', 'esp', 'españa'],
  <String>['Sri Lanka', 'lk', 'lka'],
  <String>['Sudan', 'sd', 'sdn'],
  <String>['Suriname', 'sr', 'sur'],
  <String>['Sweden', 'se', 'swe'],
  <String>['Switzerland', 'ch', 'che'],
  <String>['Syria', 'sy', 'syr'],
  <String>['São Tomé and Príncipe', 'st', 'stp'],
  <String>['Taiwan', 'tw', 'twn'],
  <String>['Tajikistan', 'tj', 'tjk'],
  <String>['Tanzania', 'tz', 'tza'],
  <String>['Thailand', 'th', 'tha'],
  <String>['Timor-Leste', 'tl', 'tls', 'east timor'],
  <String>['Togo', 'tg', 'tgo'],
  <String>['Tonga', 'to', 'ton'],
  <String>['Trinidad and Tobago', 'tt', 'tto'],
  <String>['Tunisia', 'tn', 'tun'],
  <String>['Turkey', 'tr', 'tur', 'türkiye', 'turkiye'],
  <String>['Turkmenistan', 'tm', 'tkm'],
  <String>['Tuvalu', 'tv', 'tuv'],
  <String>['Uganda', 'ug', 'uga'],
  <String>['Ukraine', 'ua', 'ukr'],
  <String>['United Arab Emirates', 'ae', 'are', 'uae'],
  <String>['United Kingdom', 'gb', 'gbr', 'uk', 'great britain', 'britain'],
  <String>['United States', 'us', 'usa', 'united states of america'],
  <String>['Uruguay', 'uy', 'ury'],
  <String>['Uzbekistan', 'uz', 'uzb'],
  <String>['Vanuatu', 'vu', 'vut'],
  <String>['Vatican City', 'va', 'vat', 'holy see'],
  <String>['Venezuela', 've', 'ven'],
  <String>['Vietnam', 'vn', 'vnm', 'viet nam'],
  <String>['Yemen', 'ye', 'yem'],
  <String>['Zambia', 'zm', 'zmb'],
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

/// Country **demonyms** that are not also language names — `Bangladeshi`,
/// `Indian`, `Pakistani`, `British`, `American`. Playlists are full of them
/// (`group-title="Bangladeshi"`), and without them a whole national section
/// has no country.
///
/// Deliberately absent: every word that is also a language alias
/// (`Spanish`, `German`, `Turkish`, `Korean`, `Nepali`, `Filipino`…). Those
/// answer *language* and never country, so a label can never be claimed by
/// both tables at once.
const Map<String, String> _countryDemonyms = <String, String>{
  'afghan': 'Afghanistan',
  'algerian': 'Algeria',
  'argentinian': 'Argentina',
  'argentine': 'Argentina',
  'australian': 'Australia',
  'austrian': 'Austria',
  'bahraini': 'Bahrain',
  'bangladeshi': 'Bangladesh',
  'belgian': 'Belgium',
  'bolivian': 'Bolivia',
  'brazilian': 'Brazil',
  'brasileiro': 'Brazil',
  'cambodian': 'Cambodia',
  'cameroonian': 'Cameroon',
  'canadian': 'Canada',
  'chilean': 'Chile',
  'colombian': 'Colombia',
  'costa rican': 'Costa Rica',
  'cuban': 'Cuba',
  'cypriot': 'Cyprus',
  'dominican': 'Dominican Republic',
  'ecuadorian': 'Ecuador',
  'egyptian': 'Egypt',
  'salvadoran': 'El Salvador',
  'ethiopian': 'Ethiopia',
  'ghanaian': 'Ghana',
  'guatemalan': 'Guatemala',
  'honduran': 'Honduras',
  'indian': 'India',
  'iranian': 'Iran',
  'iraqi': 'Iraq',
  'israeli': 'Israel',
  'jamaican': 'Jamaica',
  'jordanian': 'Jordan',
  'kenyan': 'Kenya',
  'kuwaiti': 'Kuwait',
  'lebanese': 'Lebanon',
  'libyan': 'Libya',
  'luxembourgish': 'Luxembourg',
  'malaysian': 'Malaysia',
  'mexican': 'Mexico',
  'moldovan': 'Moldova',
  'montenegrin': 'Montenegro',
  'moroccan': 'Morocco',
  'new zealander': 'New Zealand',
  'kiwi': 'New Zealand',
  'nigerian': 'Nigeria',
  'omani': 'Oman',
  'pakistani': 'Pakistan',
  'palestinian': 'Palestine',
  'panamanian': 'Panama',
  'paraguayan': 'Paraguay',
  'peruvian': 'Peru',
  'philippine': 'Philippines',
  'puerto rican': 'Puerto Rico',
  'qatari': 'Qatar',
  'saudi': 'Saudi Arabia',
  'senegalese': 'Senegal',
  'singaporean': 'Singapore',
  'south african': 'South Africa',
  'sri lankan': 'Sri Lanka',
  'sudanese': 'Sudan',
  'swiss': 'Switzerland',
  'syrian': 'Syria',
  'taiwanese': 'Taiwan',
  'tanzanian': 'Tanzania',
  'tunisian': 'Tunisia',
  'ugandan': 'Uganda',
  'emirati': 'United Arab Emirates',
  'british': 'United Kingdom',
  'brit': 'United Kingdom',
  'scottish': 'United Kingdom',
  'american': 'United States',
  'uruguayan': 'Uruguay',
  'venezuelan': 'Venezuela',
  'yemeni': 'Yemen',
  'zimbabwean': 'Zimbabwe',
};

/// Canonical country → the ONE language its broadcasters overwhelmingly
/// use. Deliberately short: a multilingual country (India, Canada,
/// Switzerland, Belgium, South Africa, Sri Lanka, Singapore, Spain…) is
/// absent, because guessing Hindi for every Indian channel would be a
/// fabrication, not a grouping. Used only as the last resort, and only when
/// the caller opts in (§10.2a rule 5).
const Map<String, String> _countryPrimaryLanguage = <String, String>{
  'Albania': 'Albanian',
  'Algeria': 'Arabic',
  'Andorra': 'Catalan',
  'Angola': 'Portuguese',
  'Argentina': 'Spanish',
  'Armenia': 'Armenian',
  'Australia': 'English',
  'Austria': 'German',
  'Azerbaijan': 'Azerbaijani',
  'Bahamas': 'English',
  'Bahrain': 'Arabic',
  'Bangladesh': 'Bangla',
  'Barbados': 'English',
  'Belarus': 'Belarusian',
  'Belize': 'English',
  'Bolivia': 'Spanish',
  'Bosnia and Herzegovina': 'Bosnian',
  'Brazil': 'Portuguese',
  'Brunei': 'Malay',
  'Bulgaria': 'Bulgarian',
  'Cambodia': 'Khmer',
  'Chile': 'Spanish',
  'China': 'Chinese',
  'Colombia': 'Spanish',
  'Costa Rica': 'Spanish',
  'Croatia': 'Croatian',
  'Cuba': 'Spanish',
  'Czechia': 'Czech',
  'Denmark': 'Danish',
  'Dominican Republic': 'Spanish',
  'Ecuador': 'Spanish',
  'Egypt': 'Arabic',
  'El Salvador': 'Spanish',
  'Estonia': 'Estonian',
  'Ethiopia': 'Amharic',
  'Fiji': 'English',
  'Finland': 'Finnish',
  'France': 'French',
  'Georgia': 'Georgian',
  'Germany': 'German',
  'Gibraltar': 'English',
  'Greece': 'Greek',
  'Guatemala': 'Spanish',
  'Guyana': 'English',
  'Honduras': 'Spanish',
  'Hungary': 'Hungarian',
  'Iceland': 'Icelandic',
  'Iran': 'Persian',
  'Iraq': 'Arabic',
  'Ireland': 'English',
  'Isle of Man': 'English',
  'Israel': 'Hebrew',
  'Italy': 'Italian',
  'Japan': 'Japanese',
  'Jersey': 'English',
  'Jordan': 'Arabic',
  'Kazakhstan': 'Kazakh',
  'Kuwait': 'Arabic',
  'Laos': 'Lao',
  'Latvia': 'Latvian',
  'Lebanon': 'Arabic',
  'Libya': 'Arabic',
  'Lithuania': 'Lithuanian',
  'Macau': 'Chinese',
  'Malta': 'Maltese',
  'Mexico': 'Spanish',
  'Moldova': 'Romanian',
  'Monaco': 'French',
  'Mongolia': 'Mongolian',
  'Morocco': 'Arabic',
  'Mozambique': 'Portuguese',
  'Myanmar': 'Burmese',
  'Netherlands': 'Dutch',
  'New Zealand': 'English',
  'Nicaragua': 'Spanish',
  'North Korea': 'Korean',
  'North Macedonia': 'Macedonian',
  'Norway': 'Norwegian',
  'Oman': 'Arabic',
  'Pakistan': 'Urdu',
  'Palestine': 'Arabic',
  'Panama': 'Spanish',
  'Paraguay': 'Spanish',
  'Peru': 'Spanish',
  'Poland': 'Polish',
  'Portugal': 'Portuguese',
  'Qatar': 'Arabic',
  'Romania': 'Romanian',
  'Russia': 'Russian',
  'San Marino': 'Italian',
  'Saudi Arabia': 'Arabic',
  'Serbia': 'Serbian',
  'Slovakia': 'Slovak',
  'Slovenia': 'Slovenian',
  'Somalia': 'Somali',
  'South Korea': 'Korean',
  'Suriname': 'Dutch',
  'Sweden': 'Swedish',
  'Syria': 'Arabic',
  'Taiwan': 'Chinese',
  'Tajikistan': 'Tajik',
  'Thailand': 'Thai',
  'Trinidad and Tobago': 'English',
  'Tunisia': 'Arabic',
  'Turkey': 'Turkish',
  'Turkmenistan': 'Turkmen',
  'Ukraine': 'Ukrainian',
  'United Arab Emirates': 'Arabic',
  'United Kingdom': 'English',
  'United States': 'English',
  'Uruguay': 'Spanish',
  'Uzbekistan': 'Uzbek',
  'Venezuela': 'Spanish',
  'Vietnam': 'Vietnamese',
  'Yemen': 'Arabic',
};

/// Aliases shorter than this are codes, not spellings — they stay out of the
/// free-text scans (`as` for Assamese, `or` for Odia, `my` for Burmese would
/// otherwise light up inside ordinary English words). Canonical names are
/// always accepted whatever their length, so `Lao` and `Thai` still scan.
const int _nameAliasMinLength = 4;

/// The longest canonical/alias phrase in either table
/// (`united states of america`) — bounds the scan's window.
const int _maxPhraseWords = 4;

Map<String, String> _build(List<List<String>> table,
    {Map<String, String>? extra}) {
  final Map<String, String> out = <String, String>{};
  for (final List<String> row in table) {
    final String canonical = row.first;
    out[canonical.toLowerCase()] = canonical;
    for (int i = 1; i < row.length; i++) {
      // Lowercased here — not by table discipline — so a future alias
      // with capitals can never silently miss (`_normalise` looks up the
      // lowercased value).
      out[row[i].toLowerCase()] = canonical;
    }
  }
  if (extra != null) {
    extra.forEach((String alias, String canonical) {
      out[alias.toLowerCase()] = canonical;
    });
  }
  return out;
}

/// The same table, names only: canonical names plus aliases of
/// [_nameAliasMinLength] or more. This is what a free-text scan may match.
Map<String, String> _buildNames(List<List<String>> table,
    {Map<String, String>? extra}) {
  final Map<String, String> out = <String, String>{};
  for (final List<String> row in table) {
    final String canonical = row.first;
    out[canonical.toLowerCase()] = canonical;
    for (int i = 1; i < row.length; i++) {
      final String alias = row[i];
      if (alias.length < _nameAliasMinLength) continue;
      out[alias.toLowerCase()] = canonical;
    }
  }
  if (extra != null) {
    extra.forEach((String alias, String canonical) {
      out[alias.toLowerCase()] = canonical;
    });
  }
  return out;
}

final Map<String, String> _countries =
    _build(_countryTable, extra: _countryDemonyms);
final Map<String, String> _languages = _build(_languageTable);
final Map<String, String> _countryNames =
    _buildNames(_countryTable, extra: _countryDemonyms);
final Map<String, String> _languageNames = _buildNames(_languageTable);

/// Word boundaries that keep letters of every script (and the apostrophe in
/// `Bob's`) while splitting `US | News`, `IN: SONY TEN 2` and `24/7` into
/// words. Digits stay inside a word so `1080p` is one token, never a code.
final RegExp _wordBreak = RegExp(r"[^\p{L}\p{N}']+", unicode: true);

/// Multi-value tag separators. A top-level constant, not a per-call
/// `RegExp('[;,]')` — this runs for every attribute of every channel, and a
/// 50 000-channel list must not allocate 100 000 matchers (§10.10).
final RegExp _tagSplitter = RegExp('[;,]');

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

/// The first usable value of a multi-value tag: `"US;CA"` → `US`,
/// `"English; Spanish"` → `English`. One channel sits in one group, so a
/// compound tag groups by its primary value instead of fragmenting the
/// heads into `US;CA` / `US` / `CA` (§10.2a rev. 2026-09-09, M8).
/// `null` when nothing but separators is left (`";"`, `" , "`).
String? firstTagValue(String? value) {
  if (value == null) return null;
  for (final String part in value.split(_tagSplitter)) {
    final String s = part.trim();
    if (s.isNotEmpty) return s;
  }
  return null;
}

/// Canonical country when [token] is *exactly* one known country — code
/// (`BD`), name (`Bangladesh`) or demonym (`Bangladeshi`). For structured
/// positions: a tag value, a `BD |` head, a `(BD)` bracket.
String? countryForToken(String? token) {
  if (token == null) return null;
  final String s = token.trim();
  if (s.isEmpty) return null;
  return _countries[s.toLowerCase()];
}

/// Canonical country when [token] is a country *name* or demonym — a
/// two-letter code never counts here, so a free-text scan can't read the
/// `in` of a name as India.
String? countryNameForToken(String? token) {
  if (token == null) return null;
  final String s = token.trim();
  if (s.isEmpty) return null;
  return _countryNames[s.toLowerCase()];
}

/// Two-letter language codes that may be read from a *label*: the ones that
/// are not also a country code. `(EN)` is English because no country is
/// `EN`; `(UK)` stays the United Kingdom and never becomes Ukrainian,
/// `(CA)` never Catalan, `MY | News` never Burmese. Computed from the two
/// tables, so adding a country automatically protects its code.
final Set<String> _labelSafeLanguageCodes = _buildLabelSafeLanguageCodes();

Set<String> _buildLabelSafeLanguageCodes() {
  final Set<String> codes = <String>{};
  for (final List<String> row in _languageTable) {
    for (final String alias in row) {
      if (_isCode(alias)) codes.add(alias.toLowerCase());
    }
  }
  for (final List<String> row in _countryTable) {
    for (final String alias in row) {
      if (_isCode(alias)) codes.remove(alias.toLowerCase());
    }
  }
  return codes;
}

/// Two ASCII letters — the shape of an ISO code. (`中文` is two UTF-16 code
/// units but is a *name*, and must not be treated as a code.)
bool _isCode(String s) {
  if (s.length != 2) return false;
  for (int i = 0; i < 2; i++) {
    final int c = s.codeUnitAt(i);
    if (!((c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A))) return false;
  }
  return true;
}

/// Canonical language for a two-letter code found in a label, or `null`
/// when that code is also a country code — there the country reading wins.
String? languageCodeForLabel(String? token) {
  if (token == null) return null;
  final String s = token.trim().toLowerCase();
  if (s.length != 2 || !_labelSafeLanguageCodes.contains(s)) return null;
  return _languages[s];
}

/// Canonical language when [token] is *exactly* one known language — code
/// (`bn`) or name (`Bangla`). For a tag value or a `?lang=` parameter,
/// where a code cannot be anything else.
String? languageForToken(String? token) {
  if (token == null) return null;
  final String s = token.trim();
  if (s.isEmpty) return null;
  return _languages[s.toLowerCase()];
}

/// Canonical language when [token] is a language *name* — a code never
/// counts here (`my` inside a name is not Burmese).
String? languageNameForToken(String? token) {
  if (token == null) return null;
  final String s = token.trim();
  if (s.isEmpty) return null;
  return _languageNames[s.toLowerCase()];
}

/// The first country name/demonym [text] contains, longest phrase first
/// (`"Bangladeshi News"` → Bangladesh, `"Republic of Korea TV"` → South
/// Korea). Names only — see [countryNameForToken].
String? countryInText(String? text) => _scan(text, _countryNames);

/// The first language name [text] contains, longest phrase first
/// (`"Hindi Movies"` → Hindi, `"Bahasa Indonesia TV"` → Indonesian).
String? languageInText(String? text) => _scan(text, _languageNames);

/// The one dominant broadcast language of [country] (canonical name or any
/// of its aliases); `null` for a multilingual country or an unknown one.
/// The weakest evidence in the set — a grouping of last resort, never a
/// fact about the channel (§10.2a rule 5).
String? primaryLanguageOf(String? country) {
  if (country == null) return null;
  final String? canonical = _countries[country.trim().toLowerCase()];
  if (canonical == null) return null;
  return _countryPrimaryLanguage[canonical];
}

/// Longest-phrase-first lookup over the words of [text]. A phrase is at
/// most [_maxPhraseWords] words; the earliest position wins inside a length.
String? _scan(String? text, Map<String, String> table) {
  if (text == null) return null;
  final List<String> words = text
      .toLowerCase()
      .split(_wordBreak)
      .where((String w) => w.isNotEmpty)
      .toList(growable: false);
  if (words.isEmpty) return null;
  for (int span = _maxPhraseWords; span >= 1; span--) {
    for (int i = 0; i + span <= words.length; i++) {
      final String? hit = table[words.sublist(i, i + span).join(' ')];
      if (hit != null) return hit;
    }
  }
  return null;
}
