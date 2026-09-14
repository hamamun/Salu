import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/audio_display_service.dart';

void main() {
  group('AudioCanvasMode.resolve — the three-mode table (lrc.md L15)', () {
    test('lyrics win over everything', () {
      expect(
        AudioDisplayService.resolve(
          isLocalAudio: true,
          lyricsAvailable: true,
          lyricsShown: true,
          visualizerOn: true,
        ),
        AudioCanvasMode.lyrics,
      );
      expect(
        AudioDisplayService.resolve(
          isLocalAudio: true,
          lyricsAvailable: true,
          lyricsShown: true,
          visualizerOn: false,
        ),
        AudioCanvasMode.lyrics,
      );
    });

    test('visualizer wins when lyrics are off', () {
      expect(
        AudioDisplayService.resolve(
          isLocalAudio: true,
          lyricsAvailable: true,
          lyricsShown: false,
          visualizerOn: true,
        ),
        AudioCanvasMode.visualizer,
      );
      expect(
        AudioDisplayService.resolve(
          isLocalAudio: true,
          lyricsAvailable: false,
          lyricsShown: true,
          visualizerOn: true,
        ),
        AudioCanvasMode.visualizer,
      );
    });

    test('metadata is the fallback when both toggles are off', () {
      expect(
        AudioDisplayService.resolve(
          isLocalAudio: true,
          lyricsAvailable: true,
          lyricsShown: false,
          visualizerOn: false,
        ),
        AudioCanvasMode.metadata,
      );
      expect(
        AudioDisplayService.resolve(
          isLocalAudio: true,
          lyricsAvailable: false,
          lyricsShown: false,
          visualizerOn: false,
        ),
        AudioCanvasMode.metadata,
      );
    });

    test('video / non-audio never enters the audio canvas', () {
      expect(
        AudioDisplayService.resolve(
          isLocalAudio: false,
          lyricsAvailable: true,
          lyricsShown: true,
          visualizerOn: true,
        ),
        AudioCanvasMode.none,
      );
    });
  });
}
