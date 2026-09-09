/// Channel grouping metadata — the same-file evidence pass
/// (playlist_imp.md §10.2a rev. 2026-09-09, M58).
///
/// A playlist that only carries `group-title` used to leave Language and
/// Country dimmed and dead: the two modes read `tvg-language` /
/// `tvg-country`, and a great many real lists never write them. This pass
/// reads the *rest of the same entry* — the group text, the `tvg-id`'s
/// region suffix, the channel's own label, the stream URL's query string —
/// in a fixed order of decreasing trust, and only ever fills a field the
/// playlist left blank:
///
/// 1. the entry's own `tvg-country` / `tvg-language` (unchanged behaviour);
/// 2. the entry's `group-title` / `#EXTGRP` (`Bangladeshi`, `US | News`,
///    `Hindi Movies`, `News | UK`);
/// 3. the `tvg-id`'s region suffix (`ATNBangla.bd@SD` → Bangladesh) — the
///    only country iptv-org's generated playlists carry;
/// 4. the channel's label (`IN: SONY TEN 2`, `Eye 95 America (US)`,
///    `Madani TV Bangla`, `India Today`);
/// 5. the stream URL's query string (`?country=bd`, `?lang=hi`);
/// 6. a country with one dominant broadcast language → that language.
///
/// Every rule reads text the playlist supplied. Nothing here calls a
/// provider API, an EPG or the network. Rule 3 is the one place a channel
/// ID is read — and only its ISO suffix, never its name: iptv-org's
/// 14 000+ ids are `Name.cc` / `Name.cc@Variant` and carry no other
/// country, while `.tv` is measured as a stream-site TLD rather than
/// Tuvalu (see [_tldAmbiguousCodes]).
///
/// Pure Dart, no I/O, unit-testable — see `test/channel_metadata_test.dart`.
library;

import 'm3u_aliases.dart';

/// Where a grouping value came from. Diagnostics and tests only — the queue
/// record carries the value, never its provenance.
enum MetadataSource {
  /// The playlist said so: `tvg-country` / `tvg-language`.
  attribute,

  /// Read from the entry's `group-title` / `#EXTGRP`.
  group,

  /// Read from the `tvg-id`'s ISO region suffix (`ATNBangla.bd@SD`).
  channelId,

  /// Read from the channel's own label.
  name,

  /// Read from the stream URL's query string.
  url,

  /// The country's one dominant language — the weakest rule (§10.2a rule 6).
  countryLanguage,
}

/// The grouping metadata of one channel: two nullable values plus where
/// each came from.
class ChannelMetadata {
  const ChannelMetadata({
    this.country,
    this.countrySource,
    this.language,
    this.languageSource,
    this.groupWithoutCountry,
  });

  /// Canonical country name, or `null` when nothing in the entry says.
  final String? country;

  /// Which rule produced [country] (`null` with a `null` country).
  final MetadataSource? countrySource;

  /// Canonical language name, or `null` when nothing in the entry says.
  final String? language;

  /// Which rule produced [language] (`null` with a `null` language).
  final MetadataSource? languageSource;

  /// The group text with a `US |` / `| UK` country part removed, when the
  /// country came from that group (`US | News` → `News`). `null` when there
  /// is nothing to strip — a whole-label country (`Albania`, `Bangladeshi`)
  /// keeps its category exactly as the provider wrote it.
  final String? groupWithoutCountry;

  /// No grouping metadata at all — both modes stay dimmed for this channel.
  static const ChannelMetadata none = ChannelMetadata();

  @override
  String toString() => 'ChannelMetadata('
      'country: ${country ?? '-'}'
      '${countrySource == null ? '' : '/${countrySource!.name}'}, '
      'language: ${language ?? '-'}'
      '${languageSource == null ? '' : '/${languageSource!.name}'}'
      '${groupWithoutCountry == null ? '' : ', group: $groupWithoutCountry'})';
}

/// Rule 5 (country → its one dominant language) is on by default: for a
/// single-country list it is the difference between a working Language mode
/// and a dimmed one. Flip this to `false` to keep language strictly to what
/// the playlist spelled out.
const bool defaultLanguageFromCountry = true;

/// Query keys that carry a country. Lower-cased — keys are matched
/// case-insensitively.
const Set<String> _countryParams = <String>{
  'country',
  'countries',
  'countrycode',
  'cty',
  'cc',
  'region',
  'geo',
  'nation',
};

/// Query keys that carry a language.
const Set<String> _languageParams = <String>{
  'lang',
  'langs',
  'language',
  'languages',
  'lng',
  'audio',
  'audiolang',
  'audiolanguage',
};

/// Single-character separators between a country head/tail and the rest of
/// a label. A space-delimited hyphen (`US - News`) is rewritten to `|`
/// first, so a hyphen *inside* a word (`Al-Jazeera`) never splits it.
const Set<int> _separatorChars = <int>{
  0x7C, // |
  0x3A, // :
  0xB7, // ·
  0x2022, // •
  0x2013, // –
  0x2014, // —
  0x3E, // >
  0xBB, // »
  0x2F, // /
};

final RegExp _spacedHyphen = RegExp(r'\s+-\s+');

/// Two-letter codes better known as a generic TLD than as a country inside
/// a channel ID. Measured on 16 021 real `tvg-id`s (iptv-org + Free-TV,
/// 2026-09-09): **every** `.tv` suffix in the wild was a stream-site TLD —
/// `Toronto360.tv` is Canada, `Lasestrellas.tv` Mexico, `TaiwanPlus.tv`
/// Taiwan — never Tuvalu, so `.tv` must not group them there. `.is`,
/// `.me`, `.la`, `.ws`, `.mq`, `.sx`, `.gp` and `.cw` were checked the same
/// way and *are* the country (`RUV.is` Iceland, `TVCG1.me` Montenegro,
/// `BrianTV.la` Laos), so they stay. Codes the country table does not carry
/// (`io`, `fm`…) never match anyway; listing them keeps the rule honest if
/// a country is added later.
const Set<String> _tldAmbiguousCodes = <String>{
  'tv', 'to', 'io', 'fm', 'cc', 'cx', 'sh', 'ms', 'pn', 'tk', 'nu',
  'gs', 'hm', 'tf', 'bv', 'sj', 'aq', 'um', 'su',
};

/// The country of a `tvg-id`'s ISO region suffix: `ATNBangla.bd@SD` →
/// Bangladesh, `AamarBangla.in@SD` → India, `BBCNews.uk` → United Kingdom.
///
/// Only the suffix is read, and only when it is a two-letter country code
/// that is not also a common TLD ([_tldAmbiguousCodes]). The name part of
/// an ID is never decoded — `ZeeCinema` says nothing about a country — and
/// an ID with no code suffix (`Discovery`, `X123`) yields nothing.
String? countryFromChannelId(String? tvgId) {
  if (tvgId == null) return null;
  String id = tvgId.trim();
  if (id.isEmpty) return null;
  final int at = id.indexOf('@');
  if (at >= 0) id = id.substring(0, at);
  final int dot = id.lastIndexOf('.');
  if (dot < 0 || dot == id.length - 1) return null;
  final String tail = id.substring(dot + 1);
  if (!_isCode(tail)) return null;
  final String code = tail.toLowerCase();
  if (_tldAmbiguousCodes.contains(code)) return null;
  return countryForToken(code);
}

/// A bracketed tag: `(US)`, `[Bangladesh]`, `{UK}` — at most 32 chars.
final RegExp _brackets = RegExp(r'[\(\[\{]([^\)\]\}]{1,32})[\)\]\}]');

/// Fills the grouping fields one entry's text can support. [group] is the
/// entry's already-resolved category (`group-title` → `#EXTGRP`), [name]
/// its display label, [url] its resolved stream address.
///
/// A field the playlist supplied is never overwritten; a field nothing
/// supports stays `null` and the channel groups under `Unknown`.
ChannelMetadata inferChannelMetadata({
  required String? tvgCountry,
  required String? tvgLanguage,
  required String? tvgId,
  required String? group,
  required String? name,
  required String url,
  bool languageFromCountry = defaultLanguageFromCountry,
}) {
  String? country;
  MetadataSource? countrySource;
  String? language;
  MetadataSource? languageSource;
  String? groupWithoutCountry;

  // 1 · The playlist's own tags — unchanged §10.2 behaviour, except that a
  //     multi-value tag now groups by its primary value (`US;CA` → United
  //     States) instead of becoming its own head.
  final String? countryTag = firstTagValue(tvgCountry);
  if (countryTag != null) {
    country = normaliseCountry(countryTag);
    countrySource = MetadataSource.attribute;
  }
  final String? languageTag = firstTagValue(tvgLanguage);
  if (languageTag != null) {
    language = normaliseLanguage(languageTag);
    languageSource = MetadataSource.attribute;
  }

  // 2 · The same entry's group text — the tag the #EXTGRP fallback already
  //     taught SALU to read (§10.2a rule 4). When the country came out of a
  //     separated head or tail (`US | News`), that part leaves the category:
  //     it is a country, not a genre, and the Country mode now owns it.
  if (group != null && group.isNotEmpty) {
    if (country == null) {
      final ({String value, String? remainder})? hit =
          _countryHit(group, wholeAllowed: true);
      if (hit != null) {
        country = hit.value;
        countrySource = MetadataSource.group;
        groupWithoutCountry = hit.remainder;
      }
    }
    if (language == null) {
      language = languageFromLabel(group, wholeAllowed: true);
      if (language != null) languageSource = MetadataSource.group;
    }
  }

  // 3 · The `tvg-id`'s ISO region suffix — the only country an iptv-org
  //     playlist carries (`ATNBangla.bd@SD`). Never the name part of the ID.
  if (country == null) {
    country = countryFromChannelId(tvgId);
    if (country != null) countrySource = MetadataSource.channelId;
  }

  // 4 · The channel's own label. A whole label is never read as a *code* —
  //     a channel named `IN` or `BD` is not a country — but a country name
  //     inside it still counts (`India Today`, `Eye 95 America (US)`).
  if (name != null && name.isNotEmpty) {
    if (country == null) {
      country = countryFromLabel(name, wholeAllowed: false);
      if (country != null) countrySource = MetadataSource.name;
    }
    if (language == null) {
      language = languageFromLabel(name, wholeAllowed: false);
      if (language != null) languageSource = MetadataSource.name;
    }
  }

  // 5 · The stream URL's query string — the provider wrote it, so it is
  //     still same-file evidence. Only ever a *known* code or name.
  if (country == null || language == null) {
    final ({String? country, String? language}) hints = _urlHints(url);
    if (country == null && hints.country != null) {
      country = hints.country;
      countrySource = MetadataSource.url;
    }
    if (language == null && hints.language != null) {
      language = hints.language;
      languageSource = MetadataSource.url;
    }
  }

  // 6 · The last resort: a country with one dominant broadcast language.
  if (language == null && languageFromCountry && country != null) {
    language = primaryLanguageOf(country);
    if (language != null) languageSource = MetadataSource.countryLanguage;
  }

  if (country == null && language == null) return ChannelMetadata.none;
  return ChannelMetadata(
    country: country,
    countrySource: countrySource,
    language: language,
    languageSource: languageSource,
    groupWithoutCountry: country == null ? null : groupWithoutCountry,
  );
}

/// Country evidence in a group title or a channel label, strongest shape
/// first. [wholeAllowed] says whether the *entire* [label] may stand for a
/// country **code**: `group-title="BD"` is Bangladesh, a channel merely
/// named `BD` is not evidence. Country names count in both.
String? countryFromLabel(String? label, {required bool wholeAllowed}) =>
    _countryHit(label, wholeAllowed: wholeAllowed)?.value;

/// Language evidence in a group title or a channel label — same shapes as
/// [countryFromLabel], but a two-letter code in a label counts only when it
/// **cannot** be a country code ([languageCodeForLabel]). `(EN)` is English;
/// `Sky News (UK)` is the United Kingdom and never Ukrainian, `Eawaz TV
/// (CA)` is Canada and never Catalan, `MY | News` is Malaysia and never
/// Burmese. Any code is still believed where it cannot be anything else:
/// `tvg-language="bn"`, `?lang=bn`. Spelled-out names always count —
/// `(Urdu)`, `Hindi Movies`, `العربية`.
String? languageFromLabel(String? label, {required bool wholeAllowed}) =>
    _fromLabel(label,
            wholeAllowed: wholeAllowed,
            codesInLabel: true,
            of: _languageOf,
            inText: languageInText)
        ?.value;

({String value, String? remainder})? _fromLabel(
  String? label, {
  required bool wholeAllowed,
  required bool codesInLabel,
  required String? Function(String? candidate, {required bool allowCodes}) of,
  required String? Function(String? text) inText,
}) {
  if (label == null) return null;
  final String trimmed = label.trim();
  if (trimmed.isEmpty) return null;
  // Only pay for the rewrite when a hyphen is even present — this runs for
  // every label of every channel (§10.10).
  final String text =
      trimmed.contains('-') ? trimmed.replaceAll(_spacedHyphen, ' | ') : trimmed;

  // (a) A bracketed tag — `(US)`, `[Bangladesh]`. Inside brackets a bare
  //     country code is deliberate, but only as the bracket's whole
  //     content: `(in HD)` must not become India. The rest of the label is
  //     untouched: a bracket is a tag, not a category of its own.
  for (final RegExpMatch match in _brackets.allMatches(text)) {
    final String inner = match.group(1) ?? '';
    final String? exact = of(inner, allowCodes: codesInLabel);
    if (exact != null) return (value: exact, remainder: null);
    final String? scanned = inText(inner);
    if (scanned != null) return (value: scanned, remainder: null);
  }

  // (b) A head or a tail around a separator — `US | News`, `IN: SONY TEN 2`,
  //     `News | UK`, `Hindi Movies | HD`. With one separator the head and the
  //     tail are the two halves; with several, the outermost pair is read.
  //     What is left of the label comes back as `remainder`.
  final int first = _firstSeparator(text);
  if (first >= 0) {
    final String? head = of(text.substring(0, first), allowCodes: codesInLabel);
    if (head != null) {
      return (
        value: head,
        remainder: text.substring(first + 1).trim(),
      );
    }
    final int last = _lastSeparator(text);
    final String? tail = of(text.substring(last + 1), allowCodes: codesInLabel);
    if (tail != null) {
      return (value: tail, remainder: text.substring(0, last).trim());
    }
  }

  // (c) The whole label — a group title that *is* the country. Nothing is
  //     left to keep, so the caller keeps the original.
  if (wholeAllowed) {
    final String? whole = of(text, allowCodes: codesInLabel);
    if (whole != null) return (value: whole, remainder: null);
  }

  // (d) A name anywhere in the text — `Bangladeshi`, `Hindi Movies`.
  final String? scanned = inText(text);
  return scanned == null ? null : (value: scanned, remainder: null);
}

/// [countryFromLabel] with the leftover label — what the category becomes
/// once a `US |` / `| UK` country part is taken out.
({String value, String? remainder})? _countryHit(String? label,
        {required bool wholeAllowed}) =>
    _fromLabel(label,
        wholeAllowed: wholeAllowed,
        codesInLabel: true,
        of: _countryOf,
        inText: countryInText);

String? _countryOf(String? candidate, {required bool allowCodes}) {
  if (candidate == null) return null;
  final String c = candidate.trim();
  if (c.isEmpty) return null;
  if (allowCodes && _isCode(c)) return countryForToken(c);
  return countryNameForToken(c);
}

/// Language lookup for a label: a name anywhere, a code only when that code
/// cannot be a country ([languageCodeForLabel]).
String? _languageOf(String? candidate, {required bool allowCodes}) {
  if (candidate == null) return null;
  final String c = candidate.trim();
  if (c.isEmpty) return null;
  if (allowCodes) {
    final String? code = languageCodeForLabel(c);
    if (code != null) return code;
  }
  return languageNameForToken(c);
}

/// Two letters, both of them letters — the shape of an ISO code.
bool _isCode(String s) {
  if (s.length != 2) return false;
  for (int i = 0; i < 2; i++) {
    final int c = s.codeUnitAt(i);
    final bool letter = (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);
    if (!letter) return false;
  }
  return true;
}

int _firstSeparator(String text) {
  for (int i = 0; i < text.length; i++) {
    if (_separatorChars.contains(text.codeUnitAt(i))) return i;
  }
  return -1;
}

int _lastSeparator(String text) {
  for (int i = text.length - 1; i >= 0; i--) {
    if (_separatorChars.contains(text.codeUnitAt(i))) return i;
  }
  return -1;
}

({String? country, String? language}) _urlHints(String url) {
  // No `?`, no query — the common case for a stream URL, and the parse is
  // skipped rather than done and thrown away (§10.10).
  if (!url.contains('?')) return (country: null, language: null);
  final Uri? uri = Uri.tryParse(url.trim());
  if (uri == null || !uri.hasQuery) return (country: null, language: null);
  String? country;
  String? language;
  uri.queryParameters.forEach((String key, String value) {
    final String k = key.toLowerCase();
    if (country == null && _countryParams.contains(k)) {
      country = _countryOf(firstTagValue(value), allowCodes: true);
    } else if (language == null && _languageParams.contains(k)) {
      language = languageForToken(firstTagValue(value));
    }
  });
  return (country: country, language: language);
}
