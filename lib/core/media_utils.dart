import 'package:path/path.dart' as p;

/// Central knowledge of which file types SALU understands.
class MediaUtils {
  MediaUtils._();

  static const Set<String> videoExtensions = <String>{
    '.mp4', '.mkv', '.avi', '.mov', '.wmv', '.flv', '.webm', '.m4v',
    '.mpg', '.mpeg', '.ts', '.m2ts', '.mts', '.vob', '.3gp', '.ogv',
    '.rm', '.rmvb', '.asf', '.divx',
  };

  static const Set<String> audioExtensions = <String>{
    '.mp3', '.flac', '.m4a', '.aac', '.ogg', '.opus', '.wav', '.wma',
    '.alac', '.aiff', '.ape', '.dsf', '.mka',
  };

  static const Set<String> subtitleExtensions = <String>{
    '.srt', '.ass', '.ssa', '.sub', '.vtt',
  };

  static const Set<String> playlistExtensions = <String>{
    '.m3u', '.m3u8',
  };

  static String _ext(String path) => p.extension(path).toLowerCase();

  static bool isVideo(String path) => videoExtensions.contains(_ext(path));

  static bool isAudio(String path) => audioExtensions.contains(_ext(path));

  static bool isMedia(String path) => isVideo(path) || isAudio(path);

  static bool isSubtitle(String path) =>
      subtitleExtensions.contains(_ext(path));

  static bool isPlaylist(String path) =>
      playlistExtensions.contains(_ext(path));

  /// Display name for a media path — the file name without its extension.
  static String displayName(String path) => p.basenameWithoutExtension(path);

  /// Formats a duration as `h:mm:ss` or `m:ss` depending on length.
  static String formatDuration(Duration d) {
    final int hours = d.inHours;
    final int minutes = d.inMinutes.remainder(60);
    final int seconds = d.inSeconds.remainder(60);
    final String mm = minutes.toString().padLeft(2, '0');
    final String ss = seconds.toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$mm:$ss' : '$minutes:$ss';
  }
}
