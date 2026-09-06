import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'queue_service.dart';

/// The four grouping modes of channel lists (playlist_imp.md §10.2 / M4).
enum GroupMode { flat, category, language, country }

/// Channel-list view state: grouping mode, the accordion's open group,
/// per-playlist memory — the player-process truth the loose window only
/// mirrors (§4.8).
///
/// Everything here is derived from the QUEUE's data, never an independent
/// mode flag: switching sources is just `setQueue(...)`, and this service
/// re-evaluates availability, auto-picks the mode and resets the
/// accordion whenever the queue changes identity.
class ChannelService {
  ChannelService._() {
    // Auto-pick & reset when a whole new list arrives; follow the playing
    // channel through index changes (§10.5).
    QueueService.instance.items.addListener(_onItemsChanged);
    QueueService.instance.index.addListener(_onIndexChanged);
  }

  static final ChannelService instance = ChannelService._();

  static const String _prefsKey = 'm3u_group_modes';

  /// The head used for entries carrying no tag for the mode — always
  /// sorted last (§10.2).
  static const String uncategorized = 'Uncategorized';

  /// Above this share of tagged entries, auto-pick picks category (§10.2).
  static const double autoPickCoverage = 0.6;

  /// Current grouping mode (flat = a plain list).
  final ValueNotifier<GroupMode> groupMode =
      ValueNotifier<GroupMode>(GroupMode.flat);

  /// The accordion's open group head (null = everything collapsed — the
  /// map of the playlist, which is the point of grouping).
  final ValueNotifier<String?> openGroup = ValueNotifier<String?>(null);

  /// Favourites-only browse mode (§10.3). Keeps the group heads — only a
  /// search flattens.
  final ValueNotifier<bool> favouritesOnly = ValueNotifier<bool>(false);

  /// The playlist the current queue came from (favourites and the mode
  /// memory are keyed by HOST, not the full URL — providers rotate
  /// credentials, M12).
  String? currentHost;

  /// Signature of the queue the view state was built for — a content
  /// change (reload, new list) re-runs auto-pick.
  int _queueSignature = -1;

  /// Per-host remembered modes, hydrated once.
  Map<String, String> _rememberedModes = <String, String>{};
  bool _loaded = false;

  /// §10.5 — the open group follows the playing channel ONLY while the
  /// open group is already the playing one. Deliberately opening another
  /// group must survive an auto-advance (never fight the user).
  bool _followPlaying = true;

  // ── Hydration & host switching ───────────────────────────────────────

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return;
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map) {
        _rememberedModes = decoded.map(
          (Object? k, Object? v) =>
              MapEntry(k.toString(), v?.toString() ?? ''),
        );
      }
    } catch (_) {
      _rememberedModes = <String, String>{};
    }
  }

  /// The m3u load path announces the list's origin (host key) here.
  void notePlaylistHost(String? host) {
    currentHost = host;
  }

  Future<void> _persistMode() async {
    final String? host = currentHost;
    if (host == null) return;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      _rememberedModes[host] = groupMode.value.name;
      await prefs.setString(_prefsKey, jsonEncode(_rememberedModes));
    } catch (_) {
      // Best-effort persistence.
    }
  }

  // ── Availability & auto-pick (§10.2 / M6 / M7) ───────────────────────

  /// Whether [mode] has any tags in [items] (unavailable modes are
  /// dimmed, never hidden).
  bool modeAvailable(GroupMode mode, List<QueueItem> items) =>
      modeAvailableStatic(mode, items);

  /// The pure form (also used by the loose window's mirrored store).
  static bool modeAvailableStatic(GroupMode mode, List<QueueItem> items) {
    switch (mode) {
      case GroupMode.flat:
        return true;
      case GroupMode.category:
        return items.any((QueueItem i) => _has(i.group));
      case GroupMode.language:
        return items.any((QueueItem i) => _has(i.language));
      case GroupMode.country:
        return items.any((QueueItem i) => _has(i.country));
    }
  }

  static bool _has(String? v) => v != null && v.trim().isNotEmpty;

  /// The share of entries carrying `group-title`.
  double _categoryCoverage(List<QueueItem> items) {
    if (items.isEmpty) return 0;
    final int tagged = items.where((QueueItem i) => _has(i.group)).length;
    return tagged / items.length;
  }

  // ── Queue watching: auto-pick & accordion rules ──────────────────────

  void _onItemsChanged() {
    final List<QueueItem> items = QueueService.instance.items.value;
    final bool channel = QueueService.instance.isChannelList;

    // Not a channel list: the view state resets quietly; local mode is
    // untouched. An EMPTY queue keeps whatever view state a channel list
    // had — a clear followed by Undo must restore the same view (the
    // playlist did not change identity by being emptied for 5 s).
    if (!channel) {
      _queueSignature = -1;
      if (items.isEmpty) return;
      if (groupMode.value != GroupMode.flat) {
        groupMode.value = GroupMode.flat;
      }
      if (openGroup.value != null) openGroup.value = null;
      if (favouritesOnly.value) favouritesOnly.value = false;
      _followPlaying = true;
      return;
    }

    // The list's identity is its FIRST URL: a fresh fetch re-runs
    // auto-pick, while progressive append-chunks (same first URL) just
    // extend the view without resetting it (M2 progressive mount).
    final int signature = items.first.url.hashCode;
    if (signature == _queueSignature) return;
    _queueSignature = signature;
    if (favouritesOnly.value) favouritesOnly.value = false;

    // A fresh channel list: the mode comes from memory or from the
    // file's own tag coverage (M6).
    final String? remembered = currentHost == null
        ? null
        : _rememberedModes[currentHost!];
    GroupMode? mode = remembered == null
        ? null
        : GroupMode.values.asNameMap()[remembered];
    if (mode != null && mode != GroupMode.flat && !modeAvailable(mode, items)) {
      mode = GroupMode.flat;
    }
    groupMode.value = mode ??
        (_categoryCoverage(items) > autoPickCoverage
            ? GroupMode.category
            : GroupMode.flat);

    // All collapsed by default; only the playing channel's group is
    // open. Nothing playing → nothing open (M17/M18).
    _followPlaying = true;
    openGroup.value = _playingGroupKey();
  }

  void _onIndexChanged() {
    if (!QueueService.instance.isChannelList) return;
    if (_followPlaying) {
      final String? want = _playingGroupKey();
      if (openGroup.value != want) openGroup.value = want;
    }
  }

  /// The group head of the playing (or parked) item — null with nothing
  /// playing and in flat mode.
  String? _playingGroupKey() {
    if (groupMode.value == GroupMode.flat) return null;
    final QueueService queue = QueueService.instance;
    final int i = queue.index.value;
    if (i < 0 || i >= queue.items.value.length) return null;
    return groupKeyOf(queue.items.value[i], groupMode.value);
  }

  // ── Mutations ────────────────────────────────────────────────────────

  /// The group-by pill picked a mode. Switching modes re-indexes in SALU
  /// only — it never touches the engine (M45), so playback can't be
  /// interrupted.
  void setGroupMode(GroupMode mode, List<QueueItem> items) {
    if (groupMode.value == mode) return;
    groupMode.value = mode;
    _followPlaying = true;
    openGroup.value =
        mode == GroupMode.flat ? null : _playingGroupKey();
    _persistMode();
  }

  void toggleFavouritesOnly() {
    favouritesOnly.value = !favouritesOnly.value;
  }

  /// The accordion rule (§10.5): exactly one group open at a time; a
  /// deliberate user toggle pins the view (auto-advance may not steal it)
  /// unless the user opened the PLAYING group itself.
  void setOpenGroup(String? group, {required bool user}) {
    openGroup.value = group;
    if (user) {
      _followPlaying =
          group != null && group == _playingGroupKey();
    }
  }

  // ── Keys & normalization (§10.2) ─────────────────────────────────────

  /// The group head for [item] under [mode]. Multi-value fields are NOT
  /// split this phase (M8) — the whole string is one key.
  static String groupKeyOf(QueueItem item, GroupMode mode) {
    switch (mode) {
      case GroupMode.flat:
        return '';
      case GroupMode.category:
        return _has(item.group) ? item.group!.trim() : uncategorized;
      case GroupMode.language:
        return _has(item.language)
            ? normalizeLanguage(item.language!)
            : uncategorized;
      case GroupMode.country:
        return _has(item.country)
            ? normalizeCountry(item.country!)
            : uncategorized;
    }
  }

  /// Orders the heads for [mode]: category keeps the playlist's own
  /// first-appearance order; language and country are alphabetical;
  /// Uncategorized is always last.
  static List<String> orderGroupKeys(Iterable<String> seen, GroupMode mode) {
    final List<String> keys = seen.toList();
    if (mode == GroupMode.language || mode == GroupMode.country) {
      keys.sort((String a, String b) =>
          a.toLowerCase().compareTo(b.toLowerCase()));
    }
    if (keys.remove(ChannelService.uncategorized)) {
      keys.add(ChannelService.uncategorized);
    }
    return keys;
  }

  /// Normalise a `tvg-country` value (usually a code: UK, GB, US) so the
  /// heads do not fragment (§10.2). Unknown values pass through trimmed.
  static String normalizeCountry(String raw) {
    final String key = raw.trim();
    return _countryNames[key.toUpperCase()] ?? key;
  }

  /// Normalise a `tvg-language` value (usually a word, sometimes a code).
  static String normalizeLanguage(String raw) {
    final String key = raw.trim();
    return _languageNames[key.toLowerCase()] ??
        (key.isEmpty
            ? key
            : key[0].toUpperCase() + key.substring(1));
  }

  static const Map<String, String> _countryNames = <String, String>{
    'AF': 'Afghanistan', 'AL': 'Albania', 'DZ': 'Algeria', 'AD': 'Andorra',
    'AO': 'Angola', 'AR': 'Argentina', 'AM': 'Armenia', 'AW': 'Aruba',
    'AU': 'Australia', 'AT': 'Austria', 'AZ': 'Azerbaijan', 'BH': 'Bahrain',
    'BD': 'Bangladesh', 'BY': 'Belarus', 'BE': 'Belgium', 'BO': 'Bolivia',
    'BA': 'Bosnia and Herzegovina', 'BR': 'Brazil', 'BG': 'Bulgaria',
    'KH': 'Cambodia', 'CM': 'Cameroon', 'CA': 'Canada', 'CL': 'Chile',
    'CN': 'China', 'CO': 'Colombia', 'CR': 'Costa Rica', 'HR': 'Croatia',
    'CU': 'Cuba', 'CY': 'Cyprus', 'CZ': 'Czechia', 'DK': 'Denmark',
    'DO': 'Dominican Republic', 'EC': 'Ecuador', 'EG': 'Egypt',
    'SV': 'El Salvador', 'EE': 'Estonia', 'FI': 'Finland', 'FR': 'France',
    'GE': 'Georgia', 'DE': 'Germany', 'GH': 'Ghana', 'GR': 'Greece',
    'HK': 'Hong Kong', 'HU': 'Hungary', 'IS': 'Iceland', 'IN': 'India',
    'ID': 'Indonesia', 'IR': 'Iran', 'IQ': 'Iraq', 'IE': 'Ireland',
    'IL': 'Israel', 'IT': 'Italy', 'CI': 'Ivory Coast', 'JM': 'Jamaica',
    'JP': 'Japan', 'JO': 'Jordan', 'KZ': 'Kazakhstan', 'KE': 'Kenya',
    'KR': 'South Korea', 'KW': 'Kuwait', 'LV': 'Latvia', 'LB': 'Lebanon',
    'LT': 'Lithuania', 'LU': 'Luxembourg', 'MO': 'Macau', 'MY': 'Malaysia',
    'MT': 'Malta', 'MX': 'Mexico', 'MD': 'Moldova', 'MA': 'Morocco',
    'NL': 'Netherlands', 'NZ': 'New Zealand', 'NG': 'Nigeria',
    'MK': 'North Macedonia', 'NO': 'Norway', 'PK': 'Pakistan',
    'PS': 'Palestine', 'PA': 'Panama', 'PE': 'Peru', 'PH': 'Philippines',
    'PL': 'Poland', 'PT': 'Portugal', 'PR': 'Puerto Rico', 'QA': 'Qatar',
    'RO': 'Romania', 'RU': 'Russia', 'SA': 'Saudi Arabia', 'RS': 'Serbia',
    'SG': 'Singapore', 'SK': 'Slovakia', 'SI': 'Slovenia',
    'ZA': 'South Africa', 'ES': 'Spain', 'SE': 'Sweden',
    'CH': 'Switzerland', 'SY': 'Syria', 'TW': 'Taiwan', 'TH': 'Thailand',
    'TN': 'Tunisia', 'TR': 'Turkey', 'UA': 'Ukraine',
    'AE': 'United Arab Emirates', 'UK': 'United Kingdom',
    'GB': 'United Kingdom', 'US': 'United States', 'USA': 'United States',
    'UY': 'Uruguay', 'VE': 'Venezuela', 'VN': 'Vietnam', 'YE': 'Yemen',
    'INT': 'International',
  };

  static const Map<String, String> _languageNames = <String, String>{
    'ar': 'Arabic', 'ara': 'Arabic', 'az': 'Azerbaijani',
    'be': 'Belarusian', 'bg': 'Bulgarian', 'bn': 'Bengali',
    'ca': 'Catalan', 'cs': 'Czech', 'da': 'Danish', 'de': 'German',
    'ger': 'German', 'deu': 'German', 'el': 'Greek', 'en': 'English',
    'eng': 'English', 'es': 'Spanish', 'spa': 'Spanish', 'et': 'Estonian',
    'fa': 'Persian', 'fi': 'Finnish', 'fr': 'French', 'fre': 'French',
    'fra': 'French', 'he': 'Hebrew', 'hi': 'Hindi', 'hr': 'Croatian',
    'hu': 'Hungarian', 'hy': 'Armenian', 'id': 'Indonesian',
    'it': 'Italian', 'ita': 'Italian', 'ja': 'Japanese', 'ka': 'Georgian',
    'kk': 'Kazakh', 'ko': 'Korean', 'lt': 'Lithuanian', 'lv': 'Latvian',
    'mk': 'Macedonian', 'ms': 'Malay', 'nl': 'Dutch', 'dut': 'Dutch',
    'nld': 'Dutch', 'no': 'Norwegian', 'pl': 'Polish', 'pt': 'Portuguese',
    'por': 'Portuguese', 'ro': 'Romanian', 'ru': 'Russian',
    'rus': 'Russian', 'sk': 'Slovak', 'sl': 'Slovenian', 'sq': 'Albanian',
    'sr': 'Serbian', 'sv': 'Swedish', 'swe': 'Swedish', 'ta': 'Tamil',
    'te': 'Telugu', 'th': 'Thai', 'tr': 'Turkish', 'uk': 'Ukrainian',
    'ur': 'Urdu', 'vi': 'Vietnamese', 'zh': 'Chinese', 'chi': 'Chinese',
    'zho': 'Chinese',
  };
}
