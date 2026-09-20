import 'dart:convert';

/// Shared unfiltered metadata reader: list → JSON → by-key/uppercase.
class MpvMetadataReader {
  const MpvMetadataReader(this.read);
  final Future<String> Function(String) read;

  Future<Map<String, String>> readTags() async {
    final String countRaw = await read('metadata/list/count');
    final int count = int.tryParse(countRaw) ?? -1;
    if (count < 0) return _readTagMapFallback();
    final Map<String, String> tags = <String, String>{};
    for (int i = 0; i < count; i++) {
      final String key = await read('metadata/list/$i/key');
      if (key.isEmpty) continue;
      // Two independent documented routes to the value: the list entry
      // itself, then the exact key (`metadata/by-key/<key>` is a plain
      // string property). Either one landing is enough to show the tag.
      String value = await read('metadata/list/$i/value');
      if (value.isEmpty) value = await read('metadata/by-key/$key');
      if (value.isEmpty) continue;
      tags[key] = value;
    }
    if (tags.isEmpty && count > 0) return _readTagMapFallback();
    return tags;
  }

  /// The list route is unavailable (an engine build without
  /// `metadata/list/*`) or answered nothing although mpv counts entries:
  /// the JSON string form first, then one probe per common tag.
  Future<Map<String, String>> _readTagMapFallback() async {
    final Map<String, String> viaJson = await _readTagJson();
    if (viaJson.isNotEmpty) return viaJson;
    return _probeTags();
  }

  /// The string form of `metadata`, decoded when the engine hands back a
  /// JSON object (`{"Title":"…","Artist":"…"}`). Empty when there is
  /// nothing to decode — including the documented case where the raw
  /// string is unavailable.
  Future<Map<String, String>> _readTagJson() async {
    final String raw = await read('metadata');
    final String text = raw.trim();
    if (!text.startsWith('{')) return <String, String>{};
    try {
      final Object? decoded = jsonDecode(text);
      if (decoded is! Map) return <String, String>{};
      final Map<String, String> tags = <String, String>{};
      for (final MapEntry<Object?, Object?> entry in decoded.entries) {
        final String key = entry.key.toString();
        final String value = entry.value?.toString() ?? '';
        if (key.isNotEmpty && value.isNotEmpty) tags[key] = value;
      }
      return tags;
    } catch (_) {
      return <String, String>{};
    }
  }

  /// Last-resort net, when neither the list route nor the JSON string
  /// form answered: the tag names every common container writes (mpv's
  /// `--display-tags` default set, plus the usual Vorbis comment / MP4
  /// atoms), one `metadata/by-key/<key>` probe each — a plain string
  /// property, so it answers `''` when the file has no such tag.
  static const List<String> _probeKeys = <String>[
    'title',
    'artist',
    'album',
    'album_artist',
    'albumartist',
    'genre',
    'date',
    'year',
    'originaldate',
    'track',
    'tracknumber',
    'disc',
    'discnumber',
    'totaltracks',
    'totaldiscs',
    'composer',
    'writer',
    'lyricist',
    'performer',
    'conductor',
    'arranger',
    'remixer',
    'comment',
    'description',
    'publisher',
    'organization',
    'label',
    'catalog_number',
    'barcode',
    'isrc',
    'copyright',
    'language',
    'encoder',
    'encoded_by',
    'engineer',
    'mixer',
    'bpm',
    'key',
    'mood',
    'grouping',
    'work',
    'compilation',
    'media',
    'website',
  ];

  Future<Map<String, String>> _probeTags() async {
    final Map<String, String> tags = <String, String>{};
    for (final String key in _probeKeys) {
      final String value = await read('metadata/by-key/$key');
      if (value.isNotEmpty) {
        tags[key] = value;
        continue;
      }
      // ID3v2 keeps tags lowercased, a FLAC/Ogg Vorbis comment keeps them
      // uppercased — probe both spellings rather than bet on the lookup's
      // case rule.
      final String upper = key.toUpperCase();
      if (upper == key) continue;
      final String upperValue = await read('metadata/by-key/$upper');
      if (upperValue.isNotEmpty) tags[upper] = upperValue;
    }
    return tags;
  }
}
