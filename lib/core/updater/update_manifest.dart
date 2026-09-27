/// SALU's component & engine updater — the model half (updater.md).
///
/// This file is deliberately pure (no `dart:io`, no HTTP): version
/// comparison, the `versions.json` / `manifest.json` shape, and the
/// check-result models the modal renders. Everything here is decided once
/// and shared by the clients, the coordinator and the swap script's view of
/// "what is installed".
library;

import 'dart:convert';

/// The three external runtime binaries the updater owns (updater.md §1).
enum UpdateComponent {
  /// `WebView2Loader.dll` — the WebView2 connector (NuGet).
  webView2Loader,

  /// `libmpv-2.dll` — the media playback engine (media-kit's libmpv builds).
  mpvEngine,

  /// `yt-dlp.exe` — the stream parser & extractor (GitHub).
  ytDlp,
}

/// File names, feed keys and display labels for each component.
extension UpdateComponentInfo on UpdateComponent {
  /// The exact file name swapped into the installation root.
  String get fileName => switch (this) {
        UpdateComponent.webView2Loader => 'WebView2Loader.dll',
        UpdateComponent.mpvEngine => 'libmpv-2.dll',
        UpdateComponent.ytDlp => 'yt-dlp.exe',
      };

  /// The key this component stores under in `versions.json` / `manifest.json`.
  String get key => switch (this) {
        UpdateComponent.webView2Loader => 'webview2',
        UpdateComponent.mpvEngine => 'mpv',
        UpdateComponent.ytDlp => 'ytdlp',
      };

  /// The name shown in the updater table (updater.md §8's component column).
  String get label => switch (this) {
        UpdateComponent.webView2Loader => 'WebView2Loader',
        UpdateComponent.mpvEngine => 'MPV Engine',
        UpdateComponent.ytDlp => 'yt-dlp',
      };
}

/// Compares two component version strings, `a` vs `b`:
/// negative, zero or positive — the [List.sort] contract.
///
/// Handles every shape the three feeds actually produce:
/// * dotted numeric (`1.0.1210.39`, `1.0.3065.39`) — segments compare
///   **numerically**, so `1.0.3065.39` > `1.0.1210.39` > `1.0.864.35`
///   (a pure string compare gets that last pair backwards);
/// * date-like (`2024.09.20`, or the libmpv build tag `20241021`);
/// * a leading `v` is ignored;
/// * a `-prerelease` suffix sorts **below** the same version without one
///   (semver rule) — which is what "filter out pre-release tags" leans on.
int compareUpdateVersions(String a, String b) {
  final _Version va = _Version.parse(a);
  final _Version vb = _Version.parse(b);
  final int main = _compareSegments(va.main, vb.main);
  if (main != 0) return main;
  // Equal main parts: a pre-release is older than the plain release.
  if (va.pre.isEmpty && vb.pre.isEmpty) return 0;
  if (va.pre.isEmpty) return 1;
  if (vb.pre.isEmpty) return -1;
  return va.pre.compareTo(vb.pre);
}

/// The parsed shape of a version string: main segments + optional
/// pre-release tag (`1.0.3065.39-rc.1` → main `1.0.3065.39`, pre `rc.1`).
class _Version {
  const _Version(this.main, this.pre);

  final List<String> main;
  final String pre;

  static _Version parse(String raw) {
    String s = raw.trim();
    if (s.isEmpty) return const _Version(<String>[], '');
    if (s[0] == 'v' || s[0] == 'V') s = s.substring(1);
    // Build metadata never affects precedence (semver) — drop it.
    final int plus = s.indexOf('+');
    if (plus >= 0) s = s.substring(0, plus);
    String pre = '';
    final int dash = s.indexOf('-');
    if (dash >= 0) {
      pre = s.substring(dash + 1);
      s = s.substring(0, dash);
    }
    return _Version(s.isEmpty ? <String>[] : s.split('.'), pre);
  }
}

int _compareSegments(List<String> a, List<String> b) {
  final int n = a.length > b.length ? a.length : b.length;
  for (int i = 0; i < n; i++) {
    final String sa = i < a.length ? a[i] : '0';
    final String sb = i < b.length ? b[i] : '0';
    final bool na = _isNumeric(sa);
    final bool nb = _isNumeric(sb);
    if (na && nb) {
      final int d = _parseLenient(sa).compareTo(_parseLenient(sb));
      if (d != 0) return d;
    } else if (na != nb) {
      // A bare number outranks a lettered segment — arbitrary but stable.
      return na ? 1 : -1;
    } else {
      final int d = sa.compareTo(sb);
      if (d != 0) return d;
    }
  }
  return 0;
}

bool _isNumeric(String s) => s.isNotEmpty && s.codeUnits.every(
      (int c) => c >= 0x30 && c <= 0x39,
    );

int _parseLenient(String s) => int.tryParse(s) ?? 0;

/// The `versions.json` (installed state) / `manifest.json` (staged state)
/// document — one shared shape, because the swap script promotes the staged
/// manifest to the installed store verbatim (updater.md §6, step 4).
///
/// The map is always the COMPLETE component picture: a manifest that stages
/// only `yt-dlp.exe` still records the WebView2 and mpv versions in force,
/// so the promoted file never forgets what an untouched component runs.
class UpdateManifest {
  const UpdateManifest(this.components);

  /// Versions per component. A missing key means "untracked" — no store
  /// entry and no shipped baseline SALU can honestly claim.
  final Map<UpdateComponent, String> components;

  /// The store's shape version — reserved for migrations.
  static const int schemaVersion = 1;

  UpdateManifest copyWith(Map<UpdateComponent, String> overrides) {
    return UpdateManifest(<UpdateComponent, String>{
      ...components,
      ...overrides,
    });
  }

  /// Serializes to the on-disk JSON. Written by the updater into
  /// `%TEMP%\salu_update\manifest.json` and promoted to `versions.json`.
  String toJsonString() {
    final Map<String, Object> out = <String, Object>{
      'schema': schemaVersion,
      'components': <String, Object>{
        for (final MapEntry<UpdateComponent, String> e in components.entries)
          e.key.key: <String, Object>{
            'file': e.key.fileName,
            'version': e.value,
          },
      },
    };
    return jsonEncode(out);
  }

  /// Parses a store document. Hand-edited, truncated or foreign JSON
  /// degrades to the empty manifest (`const UpdateManifest({})`) — the
  /// shipped baselines then stand in, which is exactly the pre-first-update
  /// state SALU already handles. Never throws.
  static UpdateManifest tryParse(String source) {
    try {
      final Object? doc = jsonDecode(source);
      if (doc is! Map<String, Object?>) return const UpdateManifest({});
      final Object? rawComponents = doc['components'];
      if (rawComponents is! Map<String, Object?>) {
        return const UpdateManifest({});
      }
      final Map<UpdateComponent, String> out = <UpdateComponent, String>{};
      for (final UpdateComponent component in UpdateComponent.values) {
        final Object? entry = rawComponents[component.key];
        if (entry is! Map<String, Object?>) continue;
        final Object? version = entry['version'];
        if (version is String && version.trim().isNotEmpty) {
          out[component] = version.trim();
        }
      }
      return UpdateManifest(out);
    } catch (_) {
      return const UpdateManifest({});
    }
  }
}

/// One component as the check found it: what SALU believes is installed
/// (`installed`, `null` when untracked), what the feed offers (`latest`),
/// and whether the modal should flag an upgrade arrow.
class ComponentStatus {
  const ComponentStatus({
    required this.component,
    required this.installed,
    required this.latest,
    required this.downloadUrl,
    required this.updateAvailable,
    this.checksumUrl,
  });

  final UpdateComponent component;

  /// The version in force — `null` when neither `versions.json` nor a
  /// shipped baseline knows it (yt-dlp before the first update).
  final String? installed;

  /// The newest stable version the upstream feed reports.
  final String latest;

  /// Where the new file comes from (`.nupkg` / `.7z` / `yt-dlp.exe`).
  final String downloadUrl;

  /// The release's `SHA2-256SUMS` asset, when the feed publishes one
  /// (yt-dlp does). `null` = verify by size + PE guard only.
  final String? checksumUrl;

  /// True when [latest] is newer than [installed], or when the installed
  /// version is unknown — SALU cannot claim currency it cannot prove.
  final bool updateAvailable;

  /// The pending update this row represents.
  ComponentUpdate toUpdate() {
    return ComponentUpdate(
      component: component,
      fromVersion: installed,
      toVersion: latest,
      downloadUrl: downloadUrl,
      checksumUrl: checksumUrl,
    );
  }
}

/// A component that will be downloaded and staged (updater.md §3, step 3).
class ComponentUpdate {
  const ComponentUpdate({
    required this.component,
    required this.fromVersion,
    required this.toVersion,
    required this.downloadUrl,
    this.checksumUrl,
  });

  final UpdateComponent component;

  /// Version being replaced — `null` when untracked.
  final String? fromVersion;

  /// Version being staged.
  final String toVersion;

  final String downloadUrl;
  final String? checksumUrl;

  /// The file this update lands as in `%TEMP%\salu_update\`.
  String get fileName => component.fileName;
}

/// The answer one [UpdaterService.check] round produced (updater.md §3,
/// steps 1–2). [ok] false means a feed could not be reached — the modal's
/// quiet "Unable to connect to update servers" state (updater.md §8,
/// State 4), with existing files left untouched.
class UpdateCheckResult {
  const UpdateCheckResult({
    required this.ok,
    required this.checkedAt,
    this.components = const <ComponentStatus>[],
  });

  /// False = at least one feed failed; nothing is claimed about versions.
  final bool ok;

  /// When the round ran (drives "Last checked: …").
  final DateTime checkedAt;

  /// One row per component, table order. Empty when [ok] is false.
  final List<ComponentStatus> components;

  /// True when any row carries an upgrade arrow.
  bool get hasUpdates => components.any((ComponentStatus c) => c.updateAvailable);

  /// The rows that actually need downloading.
  List<ComponentUpdate> get pendingUpdates => <ComponentUpdate>[
        for (final ComponentStatus c in components)
          if (c.updateAvailable) c.toUpdate(),
      ];
}

/// Byte/speed/size text for the downloading state (updater.md §8, State
/// 2C: "1.2 MB / 2.8 MB"). Binary-ish units, one decimal — the same
/// rounding the browser's download shelf shows.
String formatUpdateBytes(int bytes) {
  if (bytes < 1000) return '$bytes B';
  if (bytes < 1000 * 1000) {
    return '${(bytes / 1000).toStringAsFixed(1)} KB';
  }
  if (bytes < 1000 * 1000 * 1000) {
    return '${(bytes / (1000 * 1000)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1000 * 1000 * 1000)).toStringAsFixed(1)} GB';
}

/// "Last checked: …" text (updater.md §8's up-to-date state). Recent
/// checks name the moment, older ones the day, oldest the full date.
String formatLastChecked(DateTime now, DateTime last) {
  final Duration ago = now.difference(last);
  if (ago.inMinutes < 1) return 'Just now';
  if (ago.inHours < 1) return '${ago.inMinutes} min ago';
  final DateTime today = DateTime(now.year, now.month, now.day);
  final DateTime thatDay = DateTime(last.year, last.month, last.day);
  final int days = today.difference(thatDay).inDays;
  if (days <= 0) return '${ago.inHours} h ago';
  if (days == 1) return 'Yesterday';
  if (days < 30) return '$days days ago';
  const List<String> months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${last.day} ${months[last.month - 1]} ${last.year}';
}
