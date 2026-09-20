import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/info_collector.dart';
import 'package:salu/core/m3u/channel_mapper.dart';
import 'package:salu/core/m3u/channel_metadata.dart';
import 'package:salu/core/m3u/m3u_parser.dart';
import 'package:salu/core/mpv_metadata.dart';
import 'package:salu/core/player_service.dart';
import 'package:salu/core/queue_item.dart';

InfoCollector collector(Map<String, String> properties, {int? size}) =>
    InfoCollector(
      read: (String key) async => properties[key] ?? '',
      fileSize: (_) async => size,
    );
String? value(InfoSnapshot info, String group, String label) {
  for (final InfoRow row in info.groups[group] ?? <InfoRow>[]) {
    if (row.label == label) return row.value;
  }
  return null;
}

const TrackSurface audio = TrackSurface(
  audio: <MpvTrack>[
    MpvTrack(
      id: '1',
      type: 'audio',
      codec: 'aac',
      channels: '2.0',
      lang: 'eng',
      selected: true,
    ),
    MpvTrack(id: '2', type: 'audio', codec: 'ac3', lang: 'jpn'),
  ],
);

void main() {
  test(
    'local audio: identity, selected Sound, local file and SALU only',
    () async {
      final InfoSnapshot info = await collector(<String, String>{
        'metadata': jsonEncode(<String, String>{
          'TITLE': 'A song',
          'ARTIST': 'Singer',
          'ALBUM': 'Record',
          'DATE': '2026-09-19',
          'TRACK': '04/12',
          'DISCNUMBER': '1',
          'TOTALDISCS': '2',
          'COMMENT': 'Never show me',
          'Id3v2 PRIV:peak': 'binary',
          'lyrics': 'Never show lyrics',
          'musicbrainz_trackid': 'private-id',
        }),
        'audio-params/samplerate': '44100',
        'audio-bitrate': '320000',
        'file-format': 'mp3',
      }, size: 1048576)
          .collect(
        const InfoContext(
          path: 'C:/song.mp3',
          tracks: audio,
          queueIndex: 3,
          queueLength: 12,
          resumedFrom: Duration(minutes: 12, seconds: 34),
          eq: 'Rock',
        ),
      );
      expect(info.local, isTrue);
      expect(info.groups.keys, <String>[
        'Identity',
        'Sound',
        'Clock & file',
        'SALU',
      ]);
      expect(value(info, 'Identity', 'Title'), 'A song');
      expect(value(info, 'Identity', 'Year'), '2026');
      expect(value(info, 'Identity', 'Track'), '4 of 12');
      expect(value(info, 'Identity', 'Disc'), '1 of 2');
      expect(value(info, 'Sound', 'Codec'), 'aac');
      expect(value(info, 'Sound', 'Language'), 'English');
      expect(value(info, 'Sound', 'Sample rate'), '44.1 kHz');
      expect(value(info, 'Sound', 'Bitrate'), '320 kb/s');
      expect(value(info, 'Clock & file', 'File size'), '1 MiB');
      expect(value(info, 'SALU', 'Queue'), '4 of 12');
      expect(value(info, 'SALU', 'Played from'), 'resumed 12:34');
      expect(value(info, 'SALU', 'EQ'), 'Rock');
      expect(
        info.groups.values
            .expand((rows) => rows)
            .any((row) => row.value.contains('Never show')),
        isFalse,
      );
      expect(value(info, 'SALU', 'Subtitles'), isNull);
    },
  );

  test(
    'SDR video has Picture, no Colour; PQ colour has engine provenance',
    () async {
      const InfoContext c = InfoContext(
        path: 'C:/film.mkv',
        width: 3840,
        height: 2160,
        decoder: 'd3d11va',
      );
      final Map<String, String> props = <String, String>{
        'container-fps': '23.976',
        'video-codec': 'hevc',
        'current-tracks/video/codec-profile': 'Main 10',
        'video-bitrate': '',
        'demux-bitrate': '12000000',
        'target-trc': 'bt.1886',
      };
      InfoSnapshot info = await collector(props).collect(c);
      expect(value(info, 'Picture', 'Resolution'), '3840 × 2160');
      expect(value(info, 'Picture', 'Frame rate'), '23.976 fps');
      expect(value(info, 'Picture', 'Codec'), 'hevc · Main 10');
      expect(value(info, 'Picture', 'Decoder'), 'd3d11va');
      expect(value(info, 'Picture', 'Bitrate'), '12 Mb/s');
      expect(value(info, 'Picture', 'Colour'), isNull);
      props['target-trc'] = 'pq';
      props['target-prim'] = 'bt.2020';
      info = await collector(props).collect(c);
      expect(value(info, 'Picture', 'Colour'), 'bt.2020 · pq');
    },
  );

  test('missing, malformed, zero and throwing properties disappear', () async {
    final InfoSnapshot info = await InfoCollector(
      read: (String key) async {
        if (key == 'audio-bitrate') return 'NaN';
        if (key == 'audio-params/samplerate') return '0';
        if (key == 'file-size') return '-1';
        throw StateError('unavailable');
      },
      fileSize: (_) async => 0,
    ).collect(const InfoContext(path: 'C:/song.flac', tracks: audio));
    expect(value(info, 'Identity', 'Title'), 'song');
    expect(value(info, 'Sound', 'Bitrate'), isNull);
    expect(value(info, 'Sound', 'Sample rate'), isNull);
    expect(info.groups.containsKey('Clock & file'), isFalse);
    expect(info.groups.containsKey('SALU'), isFalse);
    expect(
      info.probes['audio-bitrate'],
      isTrue,
    ); // answered, but invalid numeric truth
  });

  test('fallbacks keep going after invalid numeric answers', () async {
    final InfoSnapshot info = await collector(<String, String>{
      'audio-params/samplerate': 'N/A',
      'audio-samplerate': '48000',
      'audio-bitrate': '0',
      'demux-bitrate': '96000',
    }).collect(const InfoContext(path: 'C:/audio.wav', tracks: audio));
    expect(value(info, 'Sound', 'Sample rate'), '48 kHz');
    expect(value(info, 'Sound', 'Bitrate'), '96 kb/s');
  });

  test(
    'no selected audio track means no Sound despite engine properties',
    () async {
      final InfoSnapshot info = await collector(<String, String>{
        'audio-codec': 'aac',
      }).collect(const InfoContext(path: 'C:/silent.mkv'));
      expect(info.groups.containsKey('Sound'), isFalse);
    },
  );

  test(
    'stream has no clocks/file; host strips credentials, buffering is conditional',
    () async {
      const String url =
          'https://user:secret@example.org/live/token?password=hidden';
      final Map<String, String> properties = <String, String>{
        'media-title': url,
        'file-size': '999',
        'hls-bitrate': '2000000',
        'demuxer-cache-duration': '2.5',
      };
      final InfoSnapshot info = await collector(properties).collect(
        const InfoContext(
          path: url,
          title: url,
          buffering: true,
          item: QueueItem(
            url,
            name: 'Station',
            group: 'News',
            language: 'Bangla',
            languageSource: MetadataSource.channelId,
            country: 'Bangladesh',
            countrySource: MetadataSource.channelId,
          ),
        ),
      );
      expect(info.local, isFalse);
      expect(info.groups.containsKey('Clock & file'), isFalse);
      expect(value(info, 'Stream', 'Provider'), 'example.org');
      expect(value(info, 'Stream', 'Language'), 'Bangla · from the tvg-id');
      expect(value(info, 'Stream', 'Country'), 'Bangladesh · from the tvg-id');
      expect(value(info, 'Stream', 'Bitrate'), '2 Mb/s');
      expect(value(info, 'Stream', 'Buffered'), '2.5 s');
      expect(
        info.groups.values
            .expand((rows) => rows)
            .any((row) => row.value.contains('secret')),
        isFalse,
      );
      final InfoSnapshot receiving = await collector(
        properties,
      ).collect(const InfoContext(path: url));
      expect(value(receiving, 'Stream', 'Buffered'), isNull);
      expect(receiving.probes.keys.any((key) => key == 'file-size'), isFalse);
    },
  );

  test('subtitle delay requires selection and includes its sign', () async {
    final InfoSnapshot info = await collector(<String, String>{}).collect(
      const InfoContext(
        path: 'C:/film.mkv',
        subDelay: -.4,
        tracks: TrackSurface(
          embeddedSubs: <MpvTrack>[
            MpvTrack(id: '3', type: 'sub', selected: true),
          ],
        ),
      ),
    );
    expect(value(info, 'SALU', 'Subtitles'), '-0.4 s');
  });

  test('channel provenance survives mapping and canonical URL copies', () {
    final QueueItem item = ChannelMapper().map(
      const M3uEntry(
        url: 'https://example.org/live',
        title: 'ATN',
        attributes: <String, String>{'tvg-id': 'ATN.bd@SD'},
      ),
    )!;
    expect(item.countrySource, MetadataSource.channelId);
    expect(item.languageSource, MetadataSource.countryLanguage);
    final QueueItem copy = item.withUrl('https://example.org/other');
    expect(copy.countrySource, item.countrySource);
    expect(copy.languageSource, item.languageSource);
  });

  test(
    'shared metadata reader supports list, JSON and uppercase by-key',
    () async {
      Future<Map<String, String>> read(Map<String, String> properties) =>
          MpvMetadataReader((key) async => properties[key] ?? '').readTags();
      expect(
        await read(<String, String>{
          'metadata/list/count': '1',
          'metadata/list/0/key': 'TITLE',
          'metadata/by-key/TITLE': 'Listed',
        }),
        <String, String>{'TITLE': 'Listed'},
      );
      expect(
        await read(<String, String>{'metadata': '{"title":"JSON"}'}),
        <String, String>{'title': 'JSON'},
      );
      expect(
        await read(<String, String>{'metadata/by-key/DISC': '2'}),
        <String, String>{'DISC': '2'},
      );
    },
  );

  test('invalid or empty titles fall back instead of removing Identity',
      () async {
    final InfoSnapshot info = await collector(<String, String>{
      'metadata': '{"title":"bad\\u0000title"}',
      'media-title': 'bad\u0000title',
    }).collect(const InfoContext(path: 'C:/honest.mp3', title: '  '));
    expect(value(info, 'Identity', 'Title'), 'honest');
    final InfoSnapshot tagged = await collector(<String, String>{
      'metadata/by-key/TITLE': 'unknown',
    }).collect(const InfoContext(path: 'C:/honest.mp3'));
    expect(value(tagged, 'Identity', 'Title'), 'unknown');
  });

  test('file URIs describe local media, not a stream', () async {
    final InfoSnapshot info = await collector(<String, String>{}, size: 1024)
        .collect(const InfoContext(path: 'file:///C:/song.wav', tracks: audio));
    expect(info.local, isTrue);
    expect(value(info, 'Clock & file', 'File size'), '1 KiB');
    expect(info.groups.containsKey('Stream'), isFalse);
  });

  test('safe text and numeric formatting never invent placeholders', () {
    expect(infoText('binary\u0000bytes'), isNull);
    expect(infoText('  \n first line\nsecond'), 'first line');
    expect(infoText(List<String>.filled(300, 'x').join())!.length, 160);
    expect(infoCount('04/00', '12'), '4 of 12');
    expect(infoCount('0', '12'), isNull);
    expect(infoFileSize(0), isNull);
    expect(infoBitrate('Infinity'), isNull);
    expect(infoBitrate('-1'), isNull);
  });
}
