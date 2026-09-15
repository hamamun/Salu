# SALU — info.md (the parked data inventory)

> **Purpose:** the list of everything SALU *can* have about what is playing —
> the text tags an audio file carries, the technical facts the engine knows
> about audio and video, and SALU's own state. Mode C shows four rows of it
> (`lrc.md` L29–L35); **the rest is parked here, not thrown away.**
>
> **Status:** REFERENCE ONLY. No decision in this file is locked, no field
> listed here is decided, and nothing here is implemented. When a surface for
> this data is designed, the decision lands in `lrc.md` / `cc.md` / a phase
> doc first, exactly as everywhere else in the project.
>
> **Accuracy note:** the property and tag names below are the ones mpv
> documents and the ones SALU has seen in real files. Items marked ⚠ need a
> check against the engine SALU actually ships (see §7 — the harvest recipe);
> a name that does not answer is dropped, never guessed at.

---

## 1. The five places data comes from

| # | Source | What it yields | SALU reads it today? |
|---|---|---|---|
| 1 | **mpv tag map** — `metadata` (walked as `metadata/list/count`, `metadata/list/N/key`, `metadata/list/N/value`; `metadata/by-key/<key>` as fallback) | every text tag the *file* carries, unfiltered | **yes** — `audio_display_service.dart::_readTagMap`, whole map kept in `AudioTrackInfo.rawTags` |
| 2 | **mpv per-track metadata** — `track-list/N/metadata`, `chapter-metadata`, `playlist/N/metadata` | tags attached to a *track* or a *chapter*, not the file | no |
| 3 | **mpv state properties** — `video-params/*`, `audio-params/*`, `duration`, `demuxer-cache-state/*`, … | the technical truth: codecs, sizes, rates, delay, cache, network | partly (duration, position, track list, `audio-delay`, `sub-delay`, EQ filters) |
| 4 | **`audio_metadata_reader`** (the tag reader dependency) | embedded picture *bytes* — and, unused today, its own parse of the same text tags | pictures only (L3/L21) |
| 5 | **SALU's own state + filesystem** — queue, playlist grouping, URL library, resume, EQ memory, lyric sidecar, `File.stat` | everything about *how the file sits in SALU*, which no media engine knows | yes, in the respective services |

Rule that keeps 1 honest (lrc.md §3.7): the read is **`metadata`, never
`filtered-metadata`** — the filtered map is cut down to mpv's `--display-tags`
whitelist. If mpv's idea of "displayable" is ever wanted, read
`filtered-metadata` as a *comparison*, never as the source.

---

## 2. Audio — the text-tag reserve

One row per **canonical field**. `Canvas` = rendered by mode C today
(L32); `Parked` = in `rawTags`, nothing shows it yet.

### 2.1 Identity — what a listener recognizes

| Field | Typical tag names (ID3v2 · Vorbis · MP4 · ASF · APEv2 · Matroska) | Today |
|---|---|---|
| Title | `TIT2` · `TITLE` · `©nam` · `Title` · `Title` · `TITLE` | **canvas** |
| Artist | `TPE1` · `ARTIST` · `©ART` · `Author` · `Artist` · `ARTIST` | **canvas** |
| Album | `TALB` · `ALBUM` · `©alb` · `WM/AlbumTitle` · `Album` · `ALBUM` | **canvas** |
| Genre | `TCON` · `GENRE` · `©gen`/`gnre` · `WM/Genre` · `Genre` · `GENRE` | **canvas** (context line) |
| Date / year | `TDRC`/`TDRL`/`TYER` · `DATE`/`ORIGINALDATE` · `©day` · `WM/Year` · `Year` · `DATE` | **canvas** (context line) |
| Track number / total | `TRCK` · `TRACKNUMBER`/`TOTALTRACKS` · `trkn` · `WM/TrackNumber` · `Track` · `PARTNUMBER` | **canvas** (context line) |
| Disc number / total | `TPOS` · `DISCNUMBER`/`TOTALDISCS` · `disk` · `WM/PartOfSet` · `Disc` | parked |
| Album artist | `TPE2` · `ALBUMARTIST` · `aART` · `WM/AlbumArtist` · `AlbumArtist` | parked |
| Artist / album sort order | `TSOP`/`TSOA` · `ARTISTSORT`/`ALBUMSORT` · `soaa`/`soal` | parked |
| Subtitle / version / mix name | `TIT3` · `SUBTITLE` · `©grp`? · `SUBTITLE` | parked |
| Compilation flag | `TCMP` · `COMPILATION` · `cpil` · `WM/IsCompilation` | parked |
| Movement / work (classical) | `MVNM`/`MVI`/`WKSD`/`GRP1` · `MOVEMENT*` · `©mvn`? · `WORK` · `MOVEMENTNAME` | parked |
| Recording / session / wave labels | `TSEE`? · `R128_*`? | parked — *diagnostic* |

### 2.2 Credits — who made it

| Field | Typical tag names | Today |
|---|---|---|
| Composer | `TCOM` · `COMPOSER` · `©wrt` · `WM/Composer` | parked |
| Lyricist / writer | `TEXT` · `LYRICIST` · `©lyr`? (no — see 2.4) | parked |
| Arranger, remixer, producer | `TPE4`/`TPE3`? · `ARRANGER`/`REMIXER`/`PRODUCER` · `aART`-adjacent | parked |
| Performer / band / ensemble / conductor | `TPE2`-family · `PERFORMER`/`ENSEMBLE`/`CONDUCTOR` | parked |
| Engineer / mixer / technician | `TPE?`/`IXXX` · `ENGINEER`/`MIXER` | parked |
| Publisher, label, catalogue, barcode, ISRC | `TPUB` · `PUBLISHER`/`LABEL`/`CATALOGNUMBER`/`BARCODE`/`ISRC` · `cprt`-adjacent | parked |
| Copyright, license, terms | `TCOP` · `COPYRIGHT` · `©cpt`/`cprt` · `License` | parked |
| Language / script | `TLAN` · `LANGUAGE` · `und`-matrix in Matroska | parked |

### 2.3 The release and the collection

| Field | Typical tag names | Today |
|---|---|---|
| Album series / part | `ALBUMARTISTSORT`? · `SERIES`? · `DISCSUBTITLE` | parked |
| Media type / source | `TMED` · `MEDIA` · `WM/Media` | parked |
| Rating / popularity / plays / skip | `POPM` · `RATING`/`POPULARITY` · `©rta` · `WM/Rating` | parked |
| Mood / BPM / key / energy | `TMOO`/`TBPM`/`TKEY` · `MOOD`/`BPM`/`INITIALKEY` · `bgsl`? | parked |
| ReplayGain / loudness | `RVA2`/`RVA2` (binary), `PRIV:peak value` (binary), `REPLAYGAIN_TRACK_GAIN/_PEAK`, `R128_TRACK_GAIN` | parked — **engine input candidate**, L35 |
| MusicBrainz / AcoustID ids | `TXXX:MUSICBRAINZ_*` · `MUSICBRAINZ_TRACKID`/`_RELEASEID`/`_RELEASEGROUPID`/`_WORKID` · `Acoustid Id`/`Fingerprint` | parked |
| Disc ID / CDDB / cue sheet | `TXXX:CDDB1` · `DISCID`/`CUESHEET` | parked |
| Chapters / table of contents | Matroska `CHAPTER*`, MP4 `chpl`, `CUESHEET` | parked |
| Podcast / show / episode | `TGID`/`TSSY`? · `PODCAST`/`SHOW`/`EPISODEID`/`SEASONNUMBER` · `tvsh`/`tven`/`tvsn` | parked |
| Lyrics (unsynced / synced) | `USLT`/`SYLT` · `LYRICS` · `©lyr` · `Lyrics` | parked — **mode B's subject, never mode C** (L34) |
| Cover / extra art | `APIC`/`PIC` · `METADATA_BLOCK_PICTURE` · `covr` · `WM/Picture` · `ATTACHED_PICTURE` | **art slot today** (bytes via the tag reader, L3/L21) |
| Comment / description / synopsis | `COMM` · `COMMENT`/`DESCRIPTION`/`SYNOPSIS` · `©cmt`/`desc` | parked — free text, unpredictable |
| Encoding provenance | `TENC`/`TSSE` · `ENCODED_BY`/`ENCODER`/`ENCODINGSETTINGS`/`ENCODINGTIME` · `©too` · `ISFT` | parked |
| Tool / watermark / scratch | `MP3GAIN` · `Id3v2 PRIV:*` · `TXXX:<anything>` · `----:com.apple.iTunes:*` | parked (junk class §4) |

### 2.4 Everything else the file may hold

mpv hands over the raw tag names it did not recognize, so the parked set is
open-ended by design. Observed in the owner's real file (2026-09-15):

```
title · artist · album · genre · album_artist · comment · encoder
lyrics-<description>            ← ID3v2 TXXX / USLT with a description
Id3v2 PRIV:peak value           ← binary, mp3gain-era
Id3v2 PRIV:average level        ← binary, mp3gain-era
```

---

## 3. Audio — the technical facts (not tags; `⚠` = verify against the shipped engine)

| What | Where it lives | Notes |
|---|---|---|
| Codec (decoder + description) | `audio-codec`, `audio-codec-name`, `track-list/N/codec`, `/codec-desc`, `/codec-profile` | profile answers only once decoded |
| Sample rate, format, channels | `audio-params/samplerate`, `/format`, `/channels`, `/channel-count`, `audio-samplerate`, `audio-channels` | the *output* graph; `demux-samplerate` etc. is what the container says |
| Bitrate | `track-list/N/demux-bitrate`, `audio-bitrate` | container-declared, often absent for VBR |
| Duration / position | `duration`, `playback-time`, `time-pos`, `percent-pos`, `remaining`, `metadata-only`? | SALU already uses these for the timeline |
| Human-readable duration/size | `file-size`, `path`, `filename`, `filename-and-path`, `media-title`, `file-format` | `media-title` = title tag → DVD id → filename |
| Delay / gain / volume | `audio-delay`, `volume`, `volume-max`, `mute`, `balance`, `left-balance`/`right-balance`, `speed` | SALU: volume bar, tune layer |
| ReplayGain (parsed!) | `track-list/N/replaygain-track-gain`/`-peak`, `/replaygain-album-gain`/`-peak` | **mpv already decodes the binary frames into numbers** — the cleanest path for L35's idea |
| Track inventory | `track-list/count`, `track-list/N/{id,type,title,lang,selected,default,forced,external,external-filename,albumart,image,src-id,ff-index,decoder-desc}` | `albumart` marks a "video" track that is really attached art — relevant to the art slot |
| Chapters | `chapter-list/N/{title,time}`, `current-chapter`, `chapter-metadata` | audio books / classical |
| seekability / streaming | `seekable`, `eof-reached`, `demuxer-via-network`, `demuxer-cache-duration` | |
| Output device | `audio-device`, `audio-device-list` | settings dialog material |
| Filters in the graph | `af`, `current-af`⚠ | SALU writes the EQ through `af` |

---

## 4. Video — what the engine can say

SALU renders video through the same libmpv, so all of §3's non-audio rows
apply, plus:

| Group | Properties |
|---|---|
| Geometry | `video-params/{w,h,hw,dw,dh,pix-fmt,bit-depth,avg-bitrate,max-bitrate,aspect,PAR,rotate,palette,alpha,hw-chroma}` |
| Motion | `container-fps`, `estimated-vf-fps`⚠, `frame-drop-count`, `decoder-frame-drop-count`, `mistimed-frame-count`, `vo-drop-frame-count`, `frame-info` (picture timing)⚠ |
| Codecs | `video-codec`, `video-bitrate`, `hwdec-current`, `hwdec-interop`, `current-hwdec`⚠ |
| High dynamic range / colour | `target-prim`, `target-trt`, `target-space`, `video-out-params/*`, `gamma-override`, `icc-profiles`, `icc-profiles-auto`, `gamut-mapping-mode`⚠ |
| Frame / cut | `frame-step`, `frame-back-step`, `frame-metadata`⚠, `drop-frame-count` |
| Subtitles (owned by `cc.md`) | `sub-delay`, `sub-pos`, `sub-scale`, `sub-visibility`, `sub-text`, `secondary-sub-text`, `sub-font`, `sub-font-size`, `sub-color`/`sub-border-color`/`sub-back-color`/`sub-border-size`/`sub-blur`, `sub-ass-override`, `sub-ass-styles`, `sub-ass-force-style`, `sub-use-margins`, `sub-align-x`/`sub-align-y`, `sub-bidi-paragraph-direction`, `sub-justify`, `sub-codec`, `sub-file`/`sub-files`, `sub-delay-sdj`? ⚠ |
| Tracks | `vid`, `aid`, `sid`, `secondary-sid`, `current-tracks/{video,audio,sub}/*`, `edition-list`, `current-edition` |
| Menus / discs | `discs`, `disc`, `current-disc`⚠, `bluray-title`, `bluray-angle`, `dvd/?`⚠ |
| Chapters | `chapter`, `chapter-list/*`, `chapter-metadata/*` |
| Cache / network (IPTV!) | `demuxer-cache-state/{fw-bytes,reader-pts,writer-pts,boffset,cache-buffering-state,seekable-ranges/N/{start,end}}`⚠, `demuxer-cache-duration`, `demuxer-cache-time`, `demuxer-readahead-secs`, `demuxer-lavf-o`⚠, `stream-byte-pos`, `stream-cur-pts`, `stream-end`, `stream-length`⚠, `network-timeout`, `http-proxy`, `user-agent`, `referrer` |
| HLS / adaptive | `track-list/N/hls-bitrate`, `/program-id`, `/main-selection` |
| DVB / IPTV stream metadata | service and provider names, `dvbin`-channel params⚠, `--dvbin-*` options |
| Window / display | `display-names`, `current-monitor`, `window-id`, `window-scale`, `window-maximized`, `window-active`, `window-focused`, `display-fps`⚠ |
| Engine identity | `mpv-version`, `ffmpeg-version`⚠, `build-date`⚠, `options/*`, `property-list`⚠ |

---

## 5. Junk classes — why a field can be parked forever

Not every tag is data a viewer should read. These stay in `rawTags` and are
documented here so a later surface can decide per class, not per file:

| Class | Examples | Why it stays off screen |
|---|---|---|
| Raw scheme names | `Id3v2 PRIV:…`, `Id3v1`, `riff INFO/IART`, `asf/WM/…`, `mp4:----:…`, `movstat_*`, `xmp:*` | the container's plumbing showed through; not a field name a human wrote |
| Binary payloads | `RVA2`, PRIV gain frames, `APIC` bytes | bytes, not text — control-character rejection (L32) drops them from the canvas |
| Giant blobs | embedded lyrics, `CUESHEET`, multi-MB `PICTURE` blocks, `padding` | one of these is exactly what used to push the album art up the screen |
| Scraper / ripper signatures | `TXXX:*` descriptions, `MusicBrainz Release Group Id`, `AMZ*`, `iTN*`, `LAME`/`ExactAudioCopy` strings | true, interesting, not for a full-window canvas |
| Same field, two tag versions | ID3v2.3 `TYER` and v2.4 `TDRC` both present; `date` and `year` disagree | alias order picks one (canonical first), the loser stays parked |
| Free text | `COMMENT`, `DESCRIPTION`, `SYNOPSIS` | length, newline, language, and content are all unknowable |

---

## 6. SALU's own facts — no media engine knows these

| Fact | Where |
|---|---|
| Queue position, item kind (audio/video/channel), grouping | `queue_service.dart`, `channel_grouping.dart` |
| M3U group/category, language + country + **how each was inferred** | `m3u/channel_metadata.dart` (`MetadataSource` — attribute, group, tvg-id suffix, label, URL query) |
| Channel favourites | `channel_favourites_service.dart` |
| URL library entries, last-play status dot (alive/dead/unknown), add & play times | `url_library_service.dart`, `AppColors.status*` |
| Resume position + duration of the last play per file | `resume_service.dart` |
| EQ curve, preset, auto-EQ decision + memory per file/album | `tune_service.dart`, `tune/auto_eq.dart`, `tune/eq_memory.dart` |
| Subtitle delay, loaded external subs, autoloaded sidecars | `sub_delay_service.dart`, `subtitle_service.dart` |
| Lyric sidecar found (exact `song.lrc` vs `song.<lang>.lrc`), line count, offset applied | `lyric_locator.dart`, `lyric_service.dart` |
| Cover-art cache key + validity (size/mtime) | `audio_display_service.dart` (L27) |
| Filesystem: size, modified time, folder, autoload origin | `File.stat`, `folder_autoload_service.dart` |
| Window/title-bar mode, title text | `settings_service.dart`, `custom_title_bar.dart` |

---

## 7. Harvesting the truth (do this before anything here is designed)

Names in this file are candidates, not a contract. The definitive inventory
comes from the engine SALU actually ships:

1. **Log the engine identity** — read `mpv-version`⚠ (and `options/*` for
   `--display-tags`) at startup in a debug build, so a claim can be tied to
   a version.
2. **Enumerate properties** — `get_property` on `property-list`⚠, or
   `mpv --list-options` / `--show-profile=all`⚠ on the same libmpv build.
   Anything the probe answers is real; anything it does not, delete here.
3. **Dump the tag map for a corpus** — for a dozen representative files
   (MP3 with PRIV frames, FLAC with cuesheet + lyrics, M4A with `----`
   atoms, WAV with RIFF INFO, OGG/Opus, an MKV with chapters, a TS/IPTV
   stream) print `metadata/list/count` and every `key`. That is the real
   junk list, and it decides §5.
4. **Per-track metadata** — read `track-list/N/metadata` for a multi-audio
   or multi-sub file; today SALU never asks the engine for it.
5. Keep this file as the candidate table; mark each row *shown / parked /
   refused* when the surface is designed.

---

## 8. Candidate surfaces (deliberately undecided)

* An info overlay: two-column, label left / value right, grouped
  (Identity · Credits · Release · Technical · Tracks · SALU).
* Where it opens: the OS deck, a slide-out panel like the track panel
  (`follow.md` rule 8 says a *live* read is a panel, a focus task is a
  modal — this is a live read), or a long-press/hover on the art.
* The full tag dump, scrollable, hidden behind an explicit action — a scroll
  view is acceptable *there*, precisely because the mode C canvas reserved
  block forbids one (L30).
* Copy-a-value, and any "reveal in Explorer" style affordance.
* ReplayGain from `track-list` (or from `rawTags`) as tune-layer input.
* Embedded lyrics as a mode B source when no `.lrc` exists (L34 parked).
* Chapter markers on the timeline; `mov-*` / `file-size` / codec facts in the
  playlist rows.

## 9. Open questions

1. Does an extended surface ever get its own keyboard shortcut, or only the
   existing hover marks? (`follow.md` rule 2: shortcuts stay silent.)
2. Technical facts: per-file truth (container) or per-playback truth (output
   graph after filters/hwdec)? They disagree in interesting ways.
3. Which junk classes, if any, become *shown* for power users — and does the
   answer change the whitelist at all, or only the extended view?
4. Do `rawTags` need a bounded size (a 5 MB embedded lyrics blob is currently
   held in memory for the life of the track)?
5. Should the ID3v1 genre index table (0–191) ship, so a bare numeric genre
   reads as a name instead of being dropped?
6. Multi-value genres/artists: first value (today) or joined?
7. What mode C shows for a *channel* (stream metadata that changes
   mid-programme — `network`/`icy`-style tags) if that ever matters; today
   channel mode has no canvas at all (lrc.md L1).
