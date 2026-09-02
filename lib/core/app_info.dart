import 'dart:io';

import 'package:flutter/foundation.dart';

import 'player_service.dart';

/// Central branding + credits constants (Phase 9).
///
/// One source of truth for the version string shown in Settings, the About
/// modal, the remote server's hello message, and every external link.
class AppInfo {
  AppInfo._();

  static const String name = 'SALU';
  static const String version = '1.0.0';
  static const String buildNumber = '1';
  static const String tagline = 'An IINA-inspired media player for Windows.';

  static String get fullVersion => 'Version $version';

  // Official links (About modal / Settings).
  static const String repositoryUrl = 'https://github.com/hamamun/Salu';
  static const String opensubtitlesUrl = 'https://www.opensubtitles.com';
  static const String opensubtitlesKeyUrl =
      'https://www.opensubtitles.com/en/developers/new-access';
  static const String mpvUrl = 'https://mpv.io';
  static const String ytDlpUrl = 'https://github.com/yt-dlp/yt-dlp';
  static const String mediaKitUrl = 'https://github.com/media-kit/media-kit';
  static const String flutterUrl = 'https://flutter.dev';

  /// Opens [url] in the system default browser. Flutter exposes no built-in
  /// equivalent on Windows without pulling in another plugin, so — like the
  /// updater's PowerShell trick — we go straight through `cmd`.
  static Future<void> openExternal(String url) async {
    try {
      if (Platform.isWindows) {
        await Process.run('cmd', <String>['/C', 'start', '', url]);
      } else if (Platform.isMacOS) {
        await Process.run('open', <String>[url]);
      } else {
        await Process.run('xdg-open', <String>[url]);
      }
    } catch (error) {
      debugPrint('[SALU] could not open "$url": $error');
    }
  }

  /// The live `mpv` build backing media_kit, read from the running engine
  /// (e.g. `0.39.0`). Null while the engine isn't up yet.
  static Future<String?> mpvEngineVersion() async {
    try {
      final String? raw = await PlayerService.instance.getMpvProperty('mpv-version');
      if (raw == null || raw.isEmpty) return null;
      return raw.replaceFirst(RegExp(r'^mpv\s*'), '').trim();
    } catch (_) {
      return null;
    }
  }
}
