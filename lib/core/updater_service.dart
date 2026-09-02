import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Outcome of a component update check.
class UpdateResult {
  const UpdateResult({
    required this.success,
    required this.message,
    this.version,
    this.updated = false,
  });

  final bool success;
  final String message;
  final String? version;

  /// True when a new binary was actually downloaded.
  final bool updated;
}

/// Keeps SALU's external binaries fresh (Phase 5 · Step 6).
///
/// SALU leans on `yt-dlp` to resolve web streams and on the WebView2 loader
/// for the built-in browser (Phase 6). Both must be updatable in-app so a
/// site change never leaves the user with a broken player.
class UpdaterService {
  UpdaterService._();

  static final UpdaterService instance = UpdaterService._();

  static const String _ytDlpLatestApi =
      'https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest';
  static const String _ytDlpAssetName = 'yt-dlp.exe';

  static const String _webView2LoaderNupkg =
      'https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2';

  /// Where downloaded components live: `%APPDATA%/SALU/bin`.
  Future<Directory> componentsDirectory() async {
    final Directory support = await getApplicationSupportDirectory();
    final Directory bin = Directory(p.join(support.path, 'bin'));
    if (!bin.existsSync()) {
      bin.createSync(recursive: true);
    }
    return bin;
  }

  /// Absolute path of the local yt-dlp binary (may not exist yet).
  Future<String> ytDlpPath() async {
    final Directory dir = await componentsDirectory();
    return p.join(dir.path, _ytDlpAssetName);
  }

  /// The version string SALU last downloaded, read from a marker file.
  Future<String?> installedYtDlpVersion() async {
    try {
      final Directory dir = await componentsDirectory();
      final File marker = File(p.join(dir.path, 'yt-dlp.version'));
      if (!marker.existsSync()) return null;
      final String value = marker.readAsStringSync().trim();
      return value.isEmpty ? null : value;
    } catch (_) {
      return null;
    }
  }

  /// Downloads the newest `yt-dlp.exe` from GitHub releases when the local
  /// copy is missing or out of date.
  Future<UpdateResult> updateYtDlp({
    void Function(double progress)? onProgress,
  }) async {
    if (!Platform.isWindows) {
      return const UpdateResult(
        success: false,
        message: 'yt-dlp updates are only supported on Windows',
      );
    }
    try {
      final http.Response release = await http
          .get(Uri.parse(_ytDlpLatestApi), headers: <String, String>{
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'SALU-Player',
      }).timeout(const Duration(seconds: 20));

      if (release.statusCode != 200) {
        return UpdateResult(
          success: false,
          message: 'GitHub returned ${release.statusCode}',
        );
      }

      final Map<String, dynamic> json =
          jsonDecode(release.body) as Map<String, dynamic>;
      final String latest = (json['tag_name'] as String?)?.trim() ?? '';
      final List<dynamic> assets =
          (json['assets'] as List<dynamic>?) ?? const <dynamic>[];

      final String? installed = await installedYtDlpVersion();
      final String target = await ytDlpPath();
      if (installed == latest && File(target).existsSync()) {
        return UpdateResult(
          success: true,
          message: 'yt-dlp is up to date ($latest)',
          version: latest,
        );
      }

      String? downloadUrl;
      for (final dynamic asset in assets) {
        if (asset is Map && asset['name'] == _ytDlpAssetName) {
          downloadUrl = asset['browser_download_url'] as String?;
          break;
        }
      }
      if (downloadUrl == null) {
        return const UpdateResult(
          success: false,
          message: 'yt-dlp.exe missing from the latest release',
        );
      }

      await _download(downloadUrl, target, onProgress: onProgress);

      final Directory dir = await componentsDirectory();
      File(p.join(dir.path, 'yt-dlp.version')).writeAsStringSync(latest);

      return UpdateResult(
        success: true,
        message: 'yt-dlp updated to $latest',
        version: latest,
        updated: true,
      );
    } catch (error) {
      debugPrint('[SALU] yt-dlp update failed: $error');
      return UpdateResult(success: false, message: 'Update failed: $error');
    }
  }

  /// Fetches the newest `WebView2Loader.dll` linker package.
  ///
  /// The loader ships inside the official NuGet package; SALU downloads it,
  /// pulls the x64 DLL out of the archive and drops it next to the other
  /// components so the Phase 6 browser always links against a current build.
  Future<UpdateResult> updateWebView2Loader({
    void Function(double progress)? onProgress,
  }) async {
    if (!Platform.isWindows) {
      return const UpdateResult(
        success: false,
        message: 'WebView2 updates are only supported on Windows',
      );
    }
    try {
      final Directory dir = await componentsDirectory();
      final String archive = p.join(dir.path, 'webview2.nupkg');
      await _download(_webView2LoaderNupkg, archive, onProgress: onProgress);

      final bool extracted = await _extractWebView2Loader(archive, dir.path);
      try {
        File(archive).deleteSync();
      } catch (_) {
        // Leaving the archive behind is harmless.
      }

      if (!extracted) {
        return const UpdateResult(
          success: false,
          message: 'Could not extract WebView2Loader.dll',
        );
      }
      return const UpdateResult(
        success: true,
        message: 'WebView2 loader updated',
        updated: true,
      );
    } catch (error) {
      debugPrint('[SALU] WebView2 update failed: $error');
      return UpdateResult(success: false, message: 'Update failed: $error');
    }
  }

  /// Unpacks `WebView2Loader.dll` (x64) from the downloaded NuGet archive
  /// using the PowerShell that ships with Windows — no extra dependency.
  Future<bool> _extractWebView2Loader(
      String archivePath, String destination) async {
    final String temp = p.join(destination, '_wv2_extract');
    final String zipPath = '$archivePath.zip';
    try {
      File(archivePath).copySync(zipPath);
      final ProcessResult unzip = await Process.run('powershell', <String>[
        '-NoProfile',
        '-Command',
        "Expand-Archive -LiteralPath '$zipPath' -DestinationPath '$temp' -Force",
      ]);
      if (unzip.exitCode != 0) return false;

      final Directory tempDir = Directory(temp);
      if (!tempDir.existsSync()) return false;

      File? loader;
      for (final FileSystemEntity entity
          in tempDir.listSync(recursive: true, followLinks: false)) {
        if (entity is File &&
            p.basename(entity.path).toLowerCase() == 'webview2loader.dll' &&
            entity.path.toLowerCase().contains('x64')) {
          loader = entity;
          break;
        }
      }
      if (loader == null) return false;
      loader.copySync(p.join(destination, 'WebView2Loader.dll'));
      return true;
    } catch (error) {
      debugPrint('[SALU] WebView2 extraction failed: $error');
      return false;
    } finally {
      try {
        final Directory tempDir = Directory(temp);
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        final File zip = File(zipPath);
        if (zip.existsSync()) zip.deleteSync();
      } catch (_) {
        // Cleanup is best effort.
      }
    }
  }

  /// Streams [url] into [destination], reporting 0–1 progress when the
  /// server advertises a content length.
  Future<void> _download(
    String url,
    String destination, {
    void Function(double progress)? onProgress,
  }) async {
    final http.Client client = http.Client();
    try {
      final http.StreamedResponse response =
          await client.send(http.Request('GET', Uri.parse(url))
            ..headers['User-Agent'] = 'SALU-Player');
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode} for $url');
      }

      final File temp = File('$destination.part');
      final IOSink sink = temp.openWrite();
      final int? total = response.contentLength;
      int received = 0;
      await for (final List<int> chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total != null && total > 0) {
          onProgress?.call(received / total);
        }
      }
      await sink.flush();
      await sink.close();

      final File target = File(destination);
      if (target.existsSync()) target.deleteSync();
      temp.renameSync(destination);
      onProgress?.call(1);
    } finally {
      client.close();
    }
  }
}
