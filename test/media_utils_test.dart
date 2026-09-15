import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/media_utils.dart';

/// The engine's spelling of a local file is not always SALU's spelling:
/// on Windows media_kit hands mpv the `\\?\C:\…` long-path form
/// (`safe_local_storage.addPrefix`), and mpv's `path` property reports
/// exactly what it was given. One file must still collapse to one key
/// ("is this the row that is playing?" — playlist_imp.md §5), which is
/// what the audio canvas' tag gate compares with.
void main() {
  group('MediaUtils.canonicalPath — one file, one spelling', () {
    test('windows long-path prefix collapses to the plain path', () {
      expect(
        MediaUtils.canonicalPath(r'\\?\C:\Music\Album\song.mp3'),
        'C:/Music/Album/song.mp3',
      );
      expect(
        MediaUtils.canonicalPath('//?/C:/Music/song.mp3'),
        'C:/Music/song.mp3',
      );
    });

    test('the long-path UNC form keeps its network root', () {
      expect(
        MediaUtils.canonicalPath(r'\\?\UNC\server\share\song.mp3'),
        '//server/share/song.mp3',
      );
    });

    test('backslashes and URI residue still collapse', () {
      expect(MediaUtils.canonicalPath(r'C:\Music\song.mp3'), 'C:/Music/song.mp3');
      expect(MediaUtils.canonicalPath('/C:/Music/song.mp3'), 'C:/Music/song.mp3');
    });

    test('a `://` spelling is a key of its own — stream or file URI', () {
      // A URL is never rewritten (playlist_imp.md §5); a `file://` URI is
      // unwrapped by `ChannelSource.localPath` before it gets here.
      expect(
        MediaUtils.canonicalPath('https://host/live/stream.mp3'),
        'https://host/live/stream.mp3',
      );
      expect(
        MediaUtils.canonicalPath('file:///C:/Music/song.mp3'),
        'file:///C:/Music/song.mp3',
      );
    });
  });

  group('MediaUtils.samePath — the engine spelling vs ours', () {
    test('the long-path spelling names the same file as the queued path', () {
      expect(
        MediaUtils.samePath(r'\\?\C:\Music\song.mp3', r'C:\Music\song.mp3'),
        isTrue,
      );
      expect(
        MediaUtils.samePath('//?/C:/Music/song.mp3', 'C:/Music/song.mp3'),
        isTrue,
      );
      expect(
        MediaUtils.samePath(r'\\?\UNC\srv\share\song.mp3', r'\\srv\share\song.mp3'),
        isTrue,
      );
    });

    test('a file URI meets the plain path on equal terms', () {
      expect(
        MediaUtils.samePath('file:///C:/Music/song.mp3', r'C:\Music\song.mp3'),
        isTrue,
      );
    });

    test('different files never match', () {
      expect(MediaUtils.samePath(r'C:\Music\a.mp3', r'C:\Music\b.mp3'), isFalse);
      expect(
        MediaUtils.samePath(r'C:\One\song.mp3', r'C:\Two\song.mp3'),
        isFalse,
      );
    });

    test('a stream URL is only ever the very same URL', () {
      expect(
        MediaUtils.samePath('https://host/A.mp3', 'https://host/a.mp3'),
        isFalse,
      );
      expect(
        MediaUtils.samePath('https://host/a.mp3', 'https://host/a.mp3'),
        isTrue,
      );
    });

    test('case differences are one file on Windows only', () {
      // The Windows filesystem is case-insensitive and the engine may
      // report a case SALU never typed; elsewhere a case is a real
      // difference.
      expect(
        MediaUtils.samePath(r'C:\Music\SONG.MP3', r'C:\Music\song.mp3'),
        Platform.isWindows,
      );
    });
  });
}
