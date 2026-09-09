import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/channel_grouping.dart';
import 'package:salu/core/m3u/channel_mapper.dart';
import 'package:salu/core/m3u/channel_metadata.dart';
import 'package:salu/core/m3u/m3u_aliases.dart';
import 'package:salu/core/m3u/m3u_parser.dart';
import 'package:salu/core/queue_item.dart';

List<M3uEntry> parseAll(String text) {
  final M3uDirectoryParser p = M3uDirectoryParser();
  final List<M3uEntry> out = <M3uEntry>[];
  out.addAll(p.feed(text));
  out.addAll(p.finish());
  return out;
}

List<QueueItem> mapAll(String text, {Uri? base}) {
  final ChannelMapper m = ChannelMapper(base: base);
  return parseAll(text).map(m.map).whereType<QueueItem>().toList();
}

/// The whole entry as one call — the same shape `ChannelMapper.map` uses.
ChannelMetadata infer({
  String? tvgCountry,
  String? tvgLanguage,
  String? tvgId,
  String? group,
  String? name,
  String url = 'http://h/stream.m3u8',
  bool languageFromCountry = defaultLanguageFromCountry,
}) =>
    inferChannelMetadata(
      tvgCountry: tvgCountry,
      tvgLanguage: tvgLanguage,
      tvgId: tvgId,
      group: group,
      name: name,
      url: url,
      languageFromCountry: languageFromCountry,
    );

void main() {
  group('alias tables — the two lookup shapes', () {
    test('codes, names and demonyms all resolve for a whole token', () {
      expect(countryForToken(' bd '), 'Bangladesh');
      expect(countryForToken('Bangladesh'), 'Bangladesh');
      expect(countryForToken('Bangladeshi'), 'Bangladesh');
      expect(countryForToken('News'), isNull);
      expect(languageForToken('bn'), 'Bangla');
      expect(languageForToken('Bangla'), 'Bangla');
    });

    test('a free-text scan never matches a bare code', () {
      // `in`, `as`, `my`, `or` are codes *and* ordinary words.
      expect(countryNameForToken('in'), isNull);
      expect(countryNameForToken('India'), 'India');
      expect(languageNameForToken('as'), isNull);
      expect(languageNameForToken('my'), isNull);
      expect(languageNameForToken('or'), isNull);
      expect(languageNameForToken('Assamese'), 'Assamese');
      // Canonical names are accepted at any length.
      expect(languageNameForToken('Lao'), 'Lao');
      expect(countryInText('Republic of Korea TV'), 'South Korea');
      expect(countryInText('Bangladeshi News'), 'Bangladesh');
      expect(languageInText('Hindi Movies'), 'Hindi');
      expect(languageInText('Bahasa Indonesia TV'), 'Indonesian');
      expect(languageInText('24/7 News in HD'), isNull);
    });

    test('a multi-value tag groups by its primary value', () {
      expect(firstTagValue('US;CA'), 'US');
      expect(firstTagValue(' English ; Spanish '), 'English');
      expect(firstTagValue(';'), isNull);
      expect(firstTagValue('  '), isNull);
      expect(firstTagValue(null), isNull);
    });

    test('a code in a label counts as a language only if no country has it',
        () {
      // No country is `EN`, `HI`, `ZH`, `KO` — those read as a language.
      expect(languageCodeForLabel('EN'), 'English');
      expect(languageCodeForLabel('hi'), 'Hindi');
      expect(languageCodeForLabel('ZH'), 'Chinese');
      expect(languageCodeForLabel('ko'), 'Korean');
      // `UK`, `CA`, `MY`, `AR`, `ES` are countries first.
      expect(languageCodeForLabel('UK'), isNull);
      expect(languageCodeForLabel('CA'), isNull);
      expect(languageCodeForLabel('MY'), isNull);
      expect(languageCodeForLabel('AR'), isNull);
      expect(languageCodeForLabel('ES'), isNull);
      expect(languageCodeForLabel('News'), isNull);
      // A code is always believed where it cannot be anything else.
      expect(languageForToken('uk'), 'Ukrainian');
      expect(languageForToken('bn'), 'Bangla');
    });

    test('only a country with one dominant language has a fallback', () {
      expect(primaryLanguageOf('Bangladesh'), 'Bangla');
      expect(primaryLanguageOf('bd'), 'Bangla');
      expect(primaryLanguageOf('United Kingdom'), 'English');
      // Multilingual — never a guess.
      expect(primaryLanguageOf('India'), isNull);
      expect(primaryLanguageOf('Canada'), isNull);
      expect(primaryLanguageOf('Switzerland'), isNull);
      expect(primaryLanguageOf('Atlantis'), isNull);
    });
  });

  group('inference order', () {
    test('the playlist\'s own tag beats every inference', () {
      final ChannelMetadata m = infer(
        tvgCountry: 'UK',
        tvgLanguage: 'en',
        group: 'Bangladeshi',
        name: 'Zee Cinema (India)',
      );
      expect(m.country, 'United Kingdom');
      expect(m.countrySource, MetadataSource.attribute);
      expect(m.language, 'English');
      expect(m.languageSource, MetadataSource.attribute);
    });

    test('an unrecognised tag value is still kept as written', () {
      final ChannelMetadata m =
          infer(tvgCountry: 'Atlantis', tvgLanguage: 'Klingon', name: 'A');
      expect(m.country, 'Atlantis');
      expect(m.language, 'Klingon');
    });

    test('the group is read before the name, the name before the URL', () {
      expect(infer(group: 'Bangladesh', name: 'X', url: 'http://h/?country=in')
          .country, 'Bangladesh');
      expect(infer(name: 'India Today', url: 'http://h/?country=bd').country,
          'India');
      expect(infer(name: 'NTV', url: 'http://h/?country=bd').country,
          'Bangladesh');
    });
  });

  group('country from the group title', () {
    test('a code head, a name head, a spaced hyphen and a pipe tail', () {
      expect(infer(group: 'US | News').country, 'United States');
      expect(infer(group: 'IN: SONY TEN 2').country, 'India');
      expect(infer(group: 'BD - News').country, 'Bangladesh');
      expect(infer(group: 'News | UK').country, 'United Kingdom');
      expect(infer(group: 'United Kingdom | News').country, 'United Kingdom');
    });

    test('a whole group that is a country, a name or a demonym', () {
      expect(infer(group: 'Albania').country, 'Albania');
      expect(infer(group: 'BD').country, 'Bangladesh');
      expect(infer(group: 'Bangladeshi').country, 'Bangladesh');
      expect(infer(group: 'Indian Channels').country, 'India');
      expect(infer(group: 'Pakistani').country, 'Pakistan');
    });

    test('an ordinary category is not a country', () {
      expect(infer(group: 'News').country, isNull);
      expect(infer(group: '24/7 Movies').country, isNull);
      expect(infer(group: 'Hindi Movies').country, isNull);
      expect(infer(group: 'FromGrp').country, isNull);
    });

    test('a hyphen inside a word is not a separator', () {
      expect(infer(group: 'Al-Jazeera').country, isNull);
      expect(infer(name: 'Al-Jazeera Live').country, isNull);
    });
  });

  group('language from the group title', () {
    test('a language name anywhere in the category', () {
      expect(infer(group: 'Hindi Movies').language, 'Hindi');
      expect(infer(group: 'Bangla News').language, 'Bangla');
      expect(infer(group: 'Tamil').language, 'Tamil');
      expect(infer(group: 'Arabic | News').language, 'Arabic');
      expect(infer(group: 'Movies (Urdu)').language, 'Urdu');
      expect(infer(group: 'VOD Movies (EN)').language, 'English');
    });

    test('a country code in a category is a country, not a language', () {
      // `(AR)` is Argentina; its one dominant language follows, so the row
      // is Spanish rather than an invented Arabic.
      final ChannelMetadata m = infer(group: 'Movies (AR)');
      expect(m.country, 'Argentina');
      expect(m.language, 'Spanish');
      expect(m.languageSource, MetadataSource.countryLanguage);
    });

    test('a two-letter head is a country, never a language', () {
      final ChannelMetadata m = infer(group: 'MY | News');
      expect(m.country, 'Malaysia');
      // `my` is Burmese's code; this is Malaysia, so language stays blank.
      expect(m.language, isNull);
    });

    test('a category with no language leaves it to the country rule', () {
      expect(infer(group: 'News').language, isNull);
      final ChannelMetadata m = infer(group: 'US | News');
      expect(m.country, 'United States');
      expect(m.language, 'English');
      expect(m.languageSource, MetadataSource.countryLanguage);
      // Opt out of the weakest rule and it stays blank.
      expect(infer(group: 'US | News', languageFromCountry: false).language,
          isNull);
    });
  });

  group('country and language from the channel label', () {
    test('a code head and a bracketed tag', () {
      expect(infer(name: 'IN: SONY TEN 2').country, 'India');
      expect(infer(name: 'Eye 95 America (US)').country, 'United States');
      expect(infer(name: 'Eawaz TV (CA)').country, 'Canada');
      expect(infer(name: 'NTV | UK').country, 'United Kingdom');
    });

    test('a bracketed country code never reads as a language code', () {
      // `uk` is Ukrainian's code and `ca` is Catalan's; in a channel label
      // they are the United Kingdom and Canada.
      final ChannelMetadata uk = infer(name: 'Sky News (UK)');
      expect(uk.country, 'United Kingdom');
      expect(uk.language, 'English');
      expect(uk.languageSource, MetadataSource.countryLanguage);
      expect(
          infer(name: 'Sky News (UK)', languageFromCountry: false).language,
          isNull);
      final ChannelMetadata ca = infer(name: 'Eawaz TV (CA)');
      expect(ca.country, 'Canada');
      expect(ca.language, isNull);
    });

    test('a language word in the name', () {
      expect(infer(name: 'Madani TV Bangla').language, 'Bangla');
      expect(infer(name: 'Life Punjabi').language, 'Punjabi');
      expect(infer(name: 'Tamil Business').language, 'Tamil');
      expect(infer(name: 'KTV Tamil Movie Classic').language, 'Tamil');
    });

    test('a whole name is never read as a country code', () {
      // `IN` and `BD` as a bare label are a name, not a country code; a
      // country *name* inside the label still counts.
      expect(infer(name: 'IN').country, isNull);
      expect(infer(name: 'BD').country, isNull);
      expect(infer(name: 'Jordan').country, 'Jordan');
      expect(infer(name: 'Jordan TV').country, 'Jordan');
    });

    test('a bare code inside a name or a bracket is not a country', () {
      expect(infer(name: 'Sony TV (in HD)').country, isNull);
      expect(infer(name: 'Channel 5 HD').country, isNull);
      expect(infer(name: '92 News').country, isNull);
      expect(infer(name: 'NTV').country, isNull);
    });

    test('a quality tag is not a language', () {
      expect(infer(name: 'Zee TV (HD)').language, isNull);
      expect(infer(name: 'Star Jalsha').language, isNull);
    });
  });

  group('the tvg-id region suffix', () {
    // iptv-org's generated playlists carry no tvg-country at all — the id
    // suffix is the only country in the file (`ATNBangla.bd@SD`).
    test('a code suffix is the country, with or without an @variant', () {
      expect(countryFromChannelId('ATNBangla.bd@SD'), 'Bangladesh');
      expect(countryFromChannelId('AamarBangla.in@SD'), 'India');
      expect(countryFromChannelId('BBCNews.uk'), 'United Kingdom');
      expect(countryFromChannelId('3sat.de@SD'), 'Germany');
      expect(countryFromChannelId('RUV.is'), 'Iceland');
      expect(countryFromChannelId('TVCG1.me'), 'Montenegro');
      expect(countryFromChannelId('BrianTV.la'), 'Laos');
    });

    test('a generic TLD suffix is never a country', () {
      // Measured: every `.tv` id in the wild was a stream site — Toronto360
      // is Canada, Las Estrellas Mexico, Taiwan+ Taiwan.
      expect(countryFromChannelId('Toronto360.tv'), isNull);
      expect(countryFromChannelId('Lasestrellas.tv'), isNull);
      expect(countryFromChannelId('TaiwanPlus.tv'), isNull);
    });

    test('an id without a code suffix says nothing', () {
      expect(countryFromChannelId('Discovery'), isNull);
      expect(countryFromChannelId('X.com'), isNull);
      expect(countryFromChannelId('a.'), isNull);
      expect(countryFromChannelId(''), isNull);
      expect(countryFromChannelId(null), isNull);
    });

    test('the tag and the group both outrank the id', () {
      expect(
          infer(tvgCountry: 'CA', tvgId: 'Toronto360.tv', name: 'Toronto 360')
              .country,
          'Canada');
      expect(infer(group: 'Bangladesh', tvgId: 'X.in', name: 'X').country,
          'Bangladesh');
      expect(
          infer(tvgId: 'ATNBangla.bd@SD', group: 'General', name: 'ATN Bangla')
              .countrySource,
          MetadataSource.channelId);
    });
  });

  group('a country taken out of the category', () {
    test('a separated head or tail leaves the genre behind', () {
      expect(infer(group: 'US | News', name: 'X').groupWithoutCountry, 'News');
      expect(infer(group: 'News | UK', name: 'X').groupWithoutCountry, 'News');
      expect(infer(group: 'BD - News', name: 'X').groupWithoutCountry, 'News');
    });

    test('a whole-label country keeps its category', () {
      // `Albania` and `Bangladeshi` *are* the category — stripping them
      // would drop the row into Unknown.
      expect(infer(group: 'Albania', name: 'X').groupWithoutCountry, isNull);
      expect(
          infer(group: 'Bangladeshi', name: 'X').groupWithoutCountry, isNull);
      expect(infer(group: 'Bangla News', name: 'X').groupWithoutCountry, isNull);
      expect(infer(name: 'Eye 95 America (US)').groupWithoutCountry, isNull);
    });
  });

  group('the stream URL\'s query string', () {
    test('a country and a language parameter are read', () {
      final ChannelMetadata m =
          infer(name: 'NTV', url: 'http://h/live/x.m3u8?country=bd&lang=hi');
      expect(m.country, 'Bangladesh');
      expect(m.countrySource, MetadataSource.url);
      expect(m.language, 'Hindi');
      expect(m.languageSource, MetadataSource.url);
    });

    test('region / geo spellings work, junk does not', () {
      expect(infer(name: 'X', url: 'http://h/x?region=PK').country, 'Pakistan');
      expect(infer(name: 'X', url: 'http://h/x?geo=us').country,
          'United States');
      expect(infer(name: 'X', url: 'http://h/x?country=zzz').country, isNull);
      // A credential-bearing query is never read as a country.
      expect(infer(name: 'X', url: 'http://u:p@h/live/1.ts').country, isNull);
    });

    test('a URL with no query contributes nothing', () {
      expect(
          infer(name: 'NTV', url: 'http://h/live/ntv/chunks.m3u8').country,
          isNull);
    });
  });

  group('the country → language fallback', () {
    test('a single-language country fills language as a last resort', () {
      final ChannelMetadata m = infer(group: 'Bangladesh');
      expect(m.country, 'Bangladesh');
      expect(m.language, 'Bangla');
      expect(m.languageSource, MetadataSource.countryLanguage);
    });

    test('it never overrides a language the playlist gave', () {
      expect(infer(tvgLanguage: 'English', group: 'Bangladesh').language,
          'English');
      expect(infer(group: 'Bangla News').language, 'Bangla');
    });

    test('it is off when the caller opts out', () {
      final ChannelMetadata m =
          infer(group: 'Bangladesh', languageFromCountry: false);
      expect(m.country, 'Bangladesh');
      expect(m.language, isNull);
    });

    test('a multilingual country leaves language blank', () {
      expect(infer(group: 'India').language, isNull);
      expect(infer(group: 'Canadian').language, isNull);
    });
  });

  group('a whole playlist — the modes the pill offers', () {
    // Shapes copied from real public lists: an attributed entry (Free-TV),
    // a demonym category, a language category, a `CC:` name, a compound-tag
    // entry (iptv-org) and a bare name with nothing to go on.
    const String playlist = '''
#EXTM3U
#EXTINF:-1 tvg-id="Kanali7.al" tvg-name="Kanali 7" tvg-country="AL" group-title="Albania",Kanali 7
https://fe.tring.al/delta/105/out/u/1200_1.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/x.png" group-title="Bangladeshi",ATN News
https://edge01.iptv.digijadoo.net/live/atn_news/chunks.m3u8
#EXTINF:-1 group-title="Hindi Movies",Zee Cinema
https://h/zee.m3u8
#EXTINF:-1 ,IN: SONY TEN 2
http://103.205.133.19/hls/ten2.m3u8
#EXTINF:-1 tvg-language="English;Spanish" tvg-country="US;CA" group-title="News",Eye 95 America
http://h/e.m3u8
#EXTINF:-1 ,NTV
https://h/ntv.m3u8
''';

    test('a group-title-only list now offers language and country', () {
      final List<QueueItem> items = mapAll(playlist);
      expect(items, hasLength(6));
      expect(
          items.map((QueueItem i) => i.country).toList(),
          <String?>[
            'Albania',
            'Bangladesh',
            null,
            'India',
            'United States',
            null,
          ]);
      expect(
          items.map((QueueItem i) => i.language).toList(),
          <String?>[
            'Albanian',
            'Bangla',
            'Hindi',
            null,
            'English',
            null,
          ]);

      final Map<ChannelGroupMode, bool> available =
          ChannelGrouping.availability(items);
      expect(available[ChannelGroupMode.flat], isTrue);
      expect(available[ChannelGroupMode.category], isTrue);
      expect(available[ChannelGroupMode.language], isTrue);
      expect(available[ChannelGroupMode.country], isTrue);
    });

    test('grouping by country sorts alphabetically with Unknown last', () {
      final List<QueueItem> items = mapAll(playlist);
      final List<int> all = List<int>.generate(items.length, (int i) => i);
      final List<ChannelGroup> groups = ChannelGrouping.buildGroups(
          items, all, ChannelGroupMode.country);
      expect(groups.map((ChannelGroup g) => g.label).toList(), <String>[
        'Albania',
        'Bangladesh',
        'India',
        'United States',
        'Unknown',
      ]);
      expect(groups.last.unknown, isTrue);
      expect(groups.last.indexes, <int>[2, 5]);
    });

    test('grouping by language does the same', () {
      final List<QueueItem> items = mapAll(playlist);
      final List<int> all = List<int>.generate(items.length, (int i) => i);
      final List<ChannelGroup> groups =
          ChannelGrouping.buildGroups(items, all, ChannelGroupMode.language);
      expect(groups.map((ChannelGroup g) => g.label).toList(), <String>[
        'Albanian',
        'Bangla',
        'English',
        'Hindi',
        'Unknown',
      ]);
      expect(groups.last.indexes, <int>[3, 5]);
    });

    test('the category grouping the owner already has is untouched', () {
      final List<QueueItem> items = mapAll(playlist);
      expect(
          items.map((QueueItem i) => i.group).toList(),
          <String?>[
            'Albania',
            'Bangladeshi',
            'Hindi Movies',
            null,
            'News',
            null,
          ]);
      expect(items[4].searchKey, 'eye 95 america news');
    });

    test('an iptv-org shaped list groups by country and language', () {
      // The real shape (countries/bd.m3u): no tvg-country, no tvg-language,
      // a category and a `Name.cc@Variant` id.
      final List<QueueItem> items = mapAll('''
#EXTM3U
#EXTINF:-1 tvg-id="AamarBangla.in@SD" tvg-logo="https://x/a.png" group-title="Entertainment",Aamar Bangla (720p)
https://h/a.m3u8
#EXTINF:-1 tvg-id="ATNBangla.bd@SD" tvg-logo="https://x/b.png" group-title="General",ATN Bangla (720p)
http://h/b.m3u8
#EXTINF:-1 tvg-id="BBCNews.uk" group-title="News",BBC News (1080p)
http://h/c.m3u8
#EXTINF:-1 tvg-id="Toronto360.tv" group-title="News",Toronto 360
http://h/d.m3u8
''');
      expect(items, hasLength(4));
      expect(items.map((QueueItem i) => i.country).toList(),
          <String?>['India', 'Bangladesh', 'United Kingdom', null]);
      expect(items.map((QueueItem i) => i.language).toList(),
          <String?>['Bangla', 'Bangla', 'English', null]);
      // The category is the provider's own word — nothing to strip here.
      expect(items.map((QueueItem i) => i.group).toList(),
          <String?>['Entertainment', 'General', 'News', 'News']);
      final Map<ChannelGroupMode, bool> available =
          ChannelGrouping.availability(items);
      expect(available[ChannelGroupMode.language], isTrue);
      expect(available[ChannelGroupMode.country], isTrue);
    });

    test('a country head leaves the category', () {
      final List<QueueItem> items = mapAll('''
#EXTINF:-1 tvg-id="X.us" group-title="US | News",NBC
http://h/a.m3u8
#EXTINF:-1 tvg-id="Y.bd" group-title="Bangladeshi",ATN News
http://h/b.m3u8
''');
      expect(items[0].group, 'News');
      expect(items[0].country, 'United States');
      expect(items[0].searchKey, 'nbc news');
      expect(items[1].group, 'Bangladeshi');
      expect(items[1].country, 'Bangladesh');
    });

    test('shared country/language strings are interned per load', () {
      final ChannelMapper m = ChannelMapper();
      final List<QueueItem> items = parseAll('''
#EXTINF:-1 group-title="Bangladeshi",A
http://h/a
#EXTINF:-1 group-title="Bangladeshi",B
http://h/b
''').map(m.map).whereType<QueueItem>().toList();
      expect(identical(items[0].country, items[1].country), isTrue);
      expect(identical(items[0].language, items[1].language), isTrue);
      // One country + one language + one group.
      expect(m.internedCount, 3);
    });
  });

  group('an empty entry stays empty', () {
    test('no tag, no group, no evidence, no query', () {
      final ChannelMetadata m = infer(name: 'NTV', url: 'http://h/ntv.m3u8');
      expect(m.country, isNull);
      expect(m.countrySource, isNull);
      expect(m.language, isNull);
      expect(m.languageSource, isNull);
      expect(identical(m, ChannelMetadata.none), isTrue);
    });
  });
}
