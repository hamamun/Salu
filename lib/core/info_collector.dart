import 'dart:io';

import 'package:media_kit/media_kit.dart';

import 'clock_format.dart';
import 'language_names.dart';
import 'm3u/channel_metadata.dart';
import 'media_utils.dart';
import 'mpv_metadata.dart';
import 'player_service.dart';
import 'queue_service.dart';
import 'tune/tune_presets.dart';
import 'tune_service.dart';

/// Frozen playback facts. Clocks are deliberately absent: the view reads the
/// existing position/duration notifiers, never the engine on a clock tick.
class InfoSnapshot {
  const InfoSnapshot(this.groups, {this.local = false, this.probes = const {}});
  final Map<String, List<InfoRow>> groups;
  final bool local;

  /// Property names and availability only — never tag values or stream URLs.
  final Map<String, bool> probes;
}

class InfoRow {
  const InfoRow(this.label, this.value);
  final String label;
  final String value;
}

/// Capture app state before awaiting the engine. A generation guard in the
/// panel controller discards a pass overtaken by a media/selection change.
class InfoContext {
  const InfoContext({
    required this.path,
    this.title,
    this.item,
    this.width = 0,
    this.height = 0,
    this.decoder,
    this.tracks = TrackSurface.empty,
    this.queueIndex = -1,
    this.queueLength = 0,
    this.resumedFrom,
    this.eq,
    this.subDelay = 0,
    this.buffering = false,
  });
  final String path;
  final String? title;
  final QueueItem? item;
  final int width, height, queueIndex, queueLength;
  final String? decoder, eq;
  final TrackSurface tracks;
  final Duration? resumedFrom;
  final double subDelay;
  final bool buffering;

  bool get local =>
      !(item?.isChannel ?? false) &&
      (!path.contains('://') || Uri.tryParse(path)?.scheme == 'file');

  factory InfoContext.current() {
    final PlayerService p = PlayerService.instance;
    final QueueService q = QueueService.instance;
    final TuneService t = TuneService.instance;
    return InfoContext(
      path: p.currentPath.value ?? '',
      title: p.currentTitle.value,
      item: q.current,
      width: p.videoWidth.value,
      height: p.videoHeight.value,
      decoder: p.activeHwdec.value,
      tracks: p.trackSurface.value,
      queueIndex: q.index.value,
      queueLength: q.items.value.length,
      resumedFrom: p.resumedFrom.value,
      eq: t.eq.value.isFlat
          ? null
          : TunePresets.matchCurve(t.eq.value, t.fileKind.value)?.label ??
              'Custom',
      subDelay: p.subDelay.value,
      buffering: p.isBuffering.value,
    );
  }
}

/// One bounded, defensive pass. No observers, polling or timers. Injected
/// property/stat readers make unavailable properties and races testable without
/// loading libmpv (the Windows build remains the final property-name check).
class InfoCollector {
  InfoCollector({
    Future<String> Function(String)? read,
    Future<int?> Function(String)? fileSize,
  })  : _read = read ?? _nativeRead,
        _fileSize = fileSize ?? _stat;

  final Future<String> Function(String) _read;
  final Future<int?> Function(String) _fileSize;

  static Future<String> _nativeRead(String name) async {
    try {
      final PlatformPlayer? platform = PlayerService.instance.player.platform;
      return platform is NativePlayer ? await platform.getProperty(name) : '';
    } catch (_) {
      return '';
    }
  }

  static Future<int?> _stat(String path) async {
    try {
      final Uri? uri = Uri.tryParse(path);
      final File file =
          uri != null && uri.scheme == 'file' ? File.fromUri(uri) : File(path);
      final FileStat stat = await file.stat();
      return stat.type == FileSystemEntityType.file && stat.size > 0
          ? stat.size
          : null;
    } catch (_) {
      return null;
    }
  }

  Future<InfoSnapshot> collect(InfoContext c) async {
    final Map<String, bool> probes = <String, bool>{};
    final Map<String, String> cache = <String, String>{};
    Future<String> read(String name) async {
      if (cache.containsKey(name)) return cache[name]!;
      String value;
      try {
        value = (await _read(name)).trim();
      } catch (_) {
        value = '';
      }
      if (!name.startsWith('metadata') &&
          <String>['N/A', 'unknown', '(unavailable)', 'null', 'auto']
              .contains(value)) {
        value = '';
      }
      if ((name.endsWith('demux-channels') || name.endsWith('channel-count')) &&
          value == '0') {
        value = '';
      }
      cache[name] = value;
      // Tags aren't the uncertain technical names; avoid huge/log-sensitive maps.
      if (!name.startsWith('metadata')) probes[name] = value.isNotEmpty;
      return value;
    }

    Future<String?> first(List<String> keys, {bool positive = false}) async {
      for (final String key in keys) {
        final String value = await read(key);
        if (value.isNotEmpty && (!positive || _number(value) != null)) {
          return value;
        }
      }
      return null;
    }

    final Map<String, String> tags = await MpvMetadataReader(read).readTags();
    String? tag(List<String> names) {
      for (final String name in names) {
        for (final MapEntry<String, String> e in tags.entries) {
          if (e.key.toLowerCase() == name) {
            final String? text = infoText(e.value);
            if (text != null) return text;
          }
        }
      }
      return null;
    }

    final Map<String, List<InfoRow>> groups = <String, List<InfoRow>>{};
    void add(String group, String label, String? value) {
      final String? text = infoText(value);
      if (text != null) {
        (groups[group] ??= <InfoRow>[]).add(InfoRow(label, text));
      }
    }

    final String? mediaTitle = infoText(await first(<String>['media-title']));
    // A stream's URL basename can contain an account token even without a
    // scheme. Only use its host/playlist label as the untagged fallback.
    final Uri? stream = c.local ? null : Uri.tryParse(c.path);
    final String fallback = c.local
        ? infoText(c.title) ?? c.item?.label ?? MediaUtils.displayName(c.path)
        : c.item?.name ?? stream?.host ?? '';
    final bool urlTitle = mediaTitle?.contains('://') == true ||
        (stream != null &&
            stream.hasQuery &&
            mediaTitle?.contains(stream.query) == true);
    final String? safeMediaTitle = urlTitle ? null : mediaTitle;
    add(
      'Identity',
      'Title',
      tag(<String>['title', 'tit2', '©nam', 'inam']) ??
          safeMediaTitle ??
          fallback,
    );
    add(
      'Identity',
      'Artist',
      tag(<String>['artist', 'tpe1', '©art', 'author', 'iart']),
    );
    add(
      'Identity',
      'Album',
      tag(<String>['album', 'talb', '©alb', 'wm/albumtitle']),
    );
    final String? date = tag(<String>[
      'date',
      'year',
      'originaldate',
      'tdrc',
      'tyer',
      '©day',
      'wm/year',
    ]);
    add(
      'Identity',
      'Year',
      date == null ? null : RegExp(r'\d{4}').firstMatch(date)?.group(0),
    );
    add(
      'Identity',
      'Genre',
      tag(<String>['genre', 'tcon', '©gen', 'wm/genre']),
    );
    add(
      'Identity',
      'Track',
      infoCount(
        tag(<String>[
          'track',
          'tracknumber',
          'trck',
          'trkn',
          'wm/tracknumber',
          'partnumber',
        ]),
        tag(<String>['totaltracks', 'tracktotal', 'trackc']),
      ),
    );
    add(
      'Identity',
      'Disc',
      infoCount(
        tag(<String>['disc', 'discnumber', 'tpos', 'disk', 'wm/partofset']),
        tag(<String>['totaldiscs', 'disctotal']),
      ),
    );

    if (c.width > 0 &&
        c.height > 0 &&
        !(c.local && MediaUtils.isAudio(c.path))) {
      add('Picture', 'Resolution', '${c.width} × ${c.height}');
      final String? fps = await first(<String>[
        'container-fps',
        'estimated-vf-fps',
      ], positive: true);
      add(
        'Picture',
        'Frame rate',
        fps == null ? null : '${_decimal(_number(fps)!)} fps',
      );
      final String? codec = await first(<String>[
        'video-codec',
        'current-tracks/video/codec-desc',
        'current-tracks/video/codec',
      ]);
      final String? profile = await first(<String>[
        'current-tracks/video/codec-profile',
      ]);
      add(
        'Picture',
        'Codec',
        codec == null
            ? null
            : profile == null
                ? codec
                : '$codec · $profile',
      );
      add(
        'Picture',
        'Decoder',
        c.decoder ?? await first(<String>['hwdec-current']),
      );
      add(
        'Picture',
        'Bitrate',
        infoBitrate(
          await first(<String>[
            'video-bitrate',
            'current-tracks/video/demux-bitrate',
            'demux-bitrate',
          ], positive: true),
        ),
      );
      // Output colour, only when the transfer really reports HDR/PQ/HLG.
      final String? trc = await first(<String>[
        'target-trc',
        'video-out-params/gamma',
        'video-params/gamma',
      ]);
      if (trc != null &&
          RegExp(
            r'pq|hlg|smpte2084|arib-std-b67|hdr',
            caseSensitive: false,
          ).hasMatch(trc)) {
        final String? prim = await first(<String>[
          'target-prim',
          'video-out-params/primaries',
          'video-params/primaries',
        ]);
        add(
          'Picture',
          'Colour',
          <String>[if (prim != null) prim, trc].join(' · '),
        );
      }
    }
    final Iterable<MpvTrack> selected = c.tracks.audio.where(
      (MpvTrack t) => t.selected,
    );
    if (selected.isNotEmpty) {
      final MpvTrack track = selected.first;
      add(
        'Sound',
        'Codec',
        infoText(track.codec) ??
            await first(<String>[
              'current-tracks/audio/codec-desc',
              'audio-codec-name',
              'audio-codec',
            ]),
      );
      add(
        'Sound',
        'Channels',
        (track.channels == '0' ? null : infoText(track.channels)) ??
            await first(<String>[
              'current-tracks/audio/demux-channels',
              'audio-params/channel-count',
              'demux-channels',
            ]),
      );
      final String? rate = await first(<String>[
        'audio-params/samplerate',
        'audio-samplerate',
      ], positive: true);
      add(
        'Sound',
        'Sample rate',
        rate == null ? null : '${_decimal(_number(rate)! / 1000)} kHz',
      );
      add(
        'Sound',
        'Bitrate',
        infoBitrate(
          await first(<String>[
            'audio-bitrate',
            'current-tracks/audio/demux-bitrate',
            'demux-bitrate',
          ], positive: true),
        ),
      );
      add('Sound', 'Language', LanguageNames.nameOf(track.lang));
    }
    if (c.local) {
      final String? size = await first(<String>['file-size'], positive: true);
      int? bytes = size == null ? null : _number(size)?.round();
      if (bytes == null) {
        try {
          bytes = await _fileSize(c.path);
        } catch (_) {
          /* no row */
        }
      }
      add('Clock & file', 'File size', infoFileSize(bytes));
      add('Clock & file', 'Container', await first(<String>['file-format']));
    }
    if (c.queueLength > 1 &&
        c.queueIndex >= 0 &&
        c.queueIndex < c.queueLength) {
      add('SALU', 'Queue', '${c.queueIndex + 1} of ${c.queueLength}');
    }
    if (c.resumedFrom != null && c.resumedFrom! > Duration.zero) {
      add(
        'SALU',
        'Played from',
        'resumed ${formatClockCompact(c.resumedFrom!)}',
      );
    }
    add('SALU', 'EQ', c.eq);
    if (!c.tracks.offIsMarked && c.subDelay.isFinite) {
      add(
        'SALU',
        'Subtitles',
        '${c.subDelay >= 0 ? '+' : ''}${c.subDelay.toStringAsFixed(1)} s',
      );
    }
    if (!c.local) {
      add('Stream', 'Provider', Uri.tryParse(c.path)?.host);
      add('Stream', 'Group', c.item?.group);
      add(
        'Stream',
        'Language',
        infoProvenance(c.item?.language, c.item?.languageSource),
      );
      add(
        'Stream',
        'Country',
        infoProvenance(c.item?.country, c.item?.countrySource),
      );
      add(
        'Stream',
        'Bitrate',
        infoBitrate(
          await first(<String>[
            'demux-bitrate',
            'hls-bitrate',
            'current-tracks/video/hls-bitrate',
          ], positive: true),
        ),
      );
      if (c.buffering) {
        final String? buffered = await first(<String>[
          'demuxer-cache-duration',
        ], positive: true);
        add(
          'Stream',
          'Buffered',
          buffered == null ? null : '${_decimal(_number(buffered)!)} s',
        );
      }
    }
    return InfoSnapshot(
      Map<String, List<InfoRow>>.unmodifiable(
        groups.map(
          (String key, List<InfoRow> value) => MapEntry<String, List<InfoRow>>(
            key,
            List<InfoRow>.unmodifiable(value),
          ),
        ),
      ),
      local: c.local,
      probes: Map<String, bool>.unmodifiable(probes),
    );
  }
}

/// A bounded single line. Binary/control payloads are not displayable facts.
String? infoText(String? raw) {
  if (raw == null) return null;
  if (RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f\ufffd]').hasMatch(raw)) {
    return null;
  }
  final String value = raw
      .replaceAll('\t', ' ')
      .split(RegExp(r'[\r\n]'))
      .map((String s) => s.trim())
      .firstWhere((String s) => s.isNotEmpty, orElse: () => '');
  return value.isEmpty
      ? null
      : value.substring(0, value.length.clamp(0, 160).toInt());
}

String? infoCount(String? raw, String? rawTotal) {
  if (raw == null) return null;
  final RegExpMatch? match = RegExp(
    r'^(\d+)\s*(?:(?:/|of)\s*(\d+))?',
    caseSensitive: false,
  ).firstMatch(raw);
  final int n = int.tryParse(match?.group(1) ?? '') ?? 0;
  if (n <= 0) return null;
  int total = int.tryParse(match?.group(2) ?? '') ?? 0;
  if (total <= 0) total = int.tryParse(rawTotal ?? '') ?? 0;
  return total > 0 ? '$n of $total' : '$n';
}

double? _number(String? raw) {
  final double? n = double.tryParse(raw ?? '');
  return n != null && n.isFinite && n > 0 ? n : null;
}

String _decimal(double n) =>
    n.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');
String? infoBitrate(String? raw) {
  final double? n = _number(raw);
  return n == null
      ? null
      : n >= 1000000
          ? '${_decimal(n / 1000000)} Mb/s'
          : '${_decimal(n / 1000)} kb/s';
}

String? infoFileSize(int? bytes) {
  if (bytes == null || bytes <= 0) return null;
  if (bytes >= 1073741824) return '${_decimal(bytes / 1073741824)} GiB';
  if (bytes >= 1048576) return '${_decimal(bytes / 1048576)} MiB';
  if (bytes >= 1024) return '${_decimal(bytes / 1024)} KiB';
  return '$bytes B';
}

String? infoProvenance(String? value, MetadataSource? source) {
  if (value == null) return null;
  final String? origin = switch (source) {
    MetadataSource.attribute => 'from the playlist tag',
    MetadataSource.group => 'from the group',
    MetadataSource.channelId => 'from the tvg-id',
    MetadataSource.name => 'from the channel name',
    MetadataSource.url => 'from the URL',
    MetadataSource.countryLanguage => 'from the country',
    null => null,
  };
  return origin == null ? value : '$value · $origin';
}
