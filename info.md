# SALU — info.md (the Info panel + the parked data inventory)

> **Purpose — two halves, in this order:**
>
> * **§0 · THE SURFACE** — exactly what the Info panel shows for any audio or
>   video file (or stream) that is playing. **DEFINED 2026-09-19 by the owner.**
> * **§1–§6 · THE INVENTORY** — the parked candidate table behind it: every
>   field Salu *can* have, now marked **shown / parked / refused** against §0.
> * **§7 · THE HARVEST** — how a candidate name becomes a shipping row.
>
> **Status:** §0 is **DECIDED** (the surface, its placement and its rows). The
> inventory is still candidates, not contracts: ⚠ marks a name that must be
> verified against the engine Salu actually ships **before** it appears in a §0
> row. A name that does not answer is dropped, never guessed at.
>
> **The door:** the Info panel is opened **only** from the right-button menu in
> Player mode — `right_item.md` §3, concept A · the second row. There is no
> other door, by owner decision.

---

# §0 · The surface

## 0.1 What it is

A **live read of what is playing** — so, by `follow.md` rule 8, it is a
**panel**, never a modal. It slides out of the **left** edge, under the control
bar, and it never moves, resizes or reflows the chrome (rule 5). The video
keeps playing behind it, untouched.

The mark that opened it is the mark on its header — the window is recognizable
by the mark that opened it (`DotGridIcon`'s existing rule, applied once more).

## 0.2 Where it appears — left, below the control bar

| Property | Value | Why |
|---|---|---|
| Anchor | `Positioned(top: kChromeBlockHeight, left: 0, bottom: 0)` | starts exactly where the chrome block ends — panel and chrome read as one window |
| Width | **322** | the Playlist panel's width, reused: **one panel width, two sides** |
| Glass | `ClipPath(_TopRightRadius(14))` + `BackdropFilter(blur 18)` + `AppColors.glass` + a **right-edge** hairline (`surfaceOutline`) | the playlist panel's recipe, mirrored |
| Arrival | slide in from the left, one 220 ms forward/reverse controller, opacity tied to the same curve | the playlist panel's motion, verbatim |
| Hit-testing | stops the instant it starts closing | a closing panel must never eat a click |
| Overflow | one scroll view when the rows exceed the height; no scrollbar, fixed row heights | a long list stays a scroll offset |
| Collision | it owns the same screen region as the Open pill → **one-popup world** (§0.8) | two glass surfaces in one corner would stack |

Nothing else lives on that side of the window: the Playlist panel is right, the
Track panel is right (`top: kChromeBlockHeight + 6, right: 16`), the Tune panel
is a centred card, the lyrics and album art are centred, and the OSD deck is
top-centre. The left column below the chrome is free.

## 0.3 The row grid — everything left-aligned

| Element | Spec |
|---|---|
| Panel padding | `EdgeInsets.fromLTRB(14, 10, 14, 14)` |
| Header | 30 px, like every panel header: the Info mark quiet on the left, `CloseMark` on the right |
| Group heading | 10.5 px, `AppColors.textSecondary`, letterSpacing 0.08em, uppercase; each group after the first is preceded by a 10 px gap and a 1 px `AppColors.divider` hairline |
| Row height | 22 px, fixed |
| Label | 11.5 px, `AppColors.textSecondary`, in a fixed **78 px** column (the settings dialog's own label size) |
| Value | 12 px, `AppColors.textPrimary`, starting at that gutter and **left-aligned** — values are never right-aligned or stretched |
| Numbers | `FontFeature.tabularFigures()` on every time, size and rate (the hover chip's precedent) |
| Too long | ellipsize; a row never wraps to two lines and never shifts its neighbours |
| No truth | **the row is not drawn** — no `—`, no `N/A`, no `0 B` (the `AlbumArtView` discipline) |

## 0.4 The rows

Six groups. A group with nothing to say is not drawn at all.

### 1 · Identity — always, when the file carries it

| Row | Reads | Source | Shows when |
|---|---|---|---|
| Title | `title` → `media-title` → file name | tag map · `PlayerService.currentTitle` | always (the last fallback always exists) |
| Artist | `artist` | tag map | tagged |
| Album | `album` | tag map | tagged |
| Year | `date` / `year`, first four digits | tag map | tagged |
| Genre | `genre` | tag map | tagged |
| Track | `track` (+ `totaltracks` → `4 of 12`) | tag map | tagged |
| Disc | `disc` (+ `totaldiscs`) | tag map | tagged |

For a video file this group usually collapses to Title alone — which is
correct, not empty.

### 2 · Picture — video only

| Row | Reads | Source | Shows when |
|---|---|---|---|
| Resolution | `videoWidth` × `videoHeight` | **in hand** | a picture exists |
| Frame rate | `container-fps` ⚠ | new read | a picture exists |
| Codec | `video-codec` (+ profile when the engine offers one) | new read | a picture exists |
| Decoder | `hwdec-current` | **in hand** (`activeHwdec`) | a picture exists |
| Bitrate | `video-bitrate` → `demux-bitrate` ⚠ | new read | the engine answers |
| Colour | `target-prim` · `target-trc` ⚠ | new read | **HDR / PQ only** — never printed for SDR |

### 3 · Sound — the audio track actually selected

| Row | Reads | Source | Shows when |
|---|---|---|---|
| Codec | selected row's `codec` / `codec-desc` | **in hand** (`MpvTrack.codec`) | an audio track is selected |
| Channels | `demux-channels` / `audio-params/channel-count` | **in hand** (`MpvTrack.channels`) | the engine answers |
| Sample rate | `audio-params/samplerate` ⚠ | new read | the engine answers |
| Bitrate | `audio-bitrate` → `demux-bitrate` ⚠ | new read | the engine answers |
| Language | selected track's `lang` → full name | **in hand** + `language_names.dart` | the track is tagged |

### 4 · Clock & file — local media only

| Row | Reads | Source | Shows when |
|---|---|---|---|
| Duration | `duration` | **in hand** | local, known |
| Position | `position` | **in hand** | local — **ticks** (§0.6) |
| Remaining | `duration − position` | derived | local — **ticks** |
| File size | `file-size` → `File.stat` ⚠ | new read / in hand | a local file with a size |
| Container | `file-format` ⚠ | new read | the engine answers |

**A live stream has no clock and no file** — this whole group drops for a URL
or an IPTV channel, and the Stream group takes its place.

### 5 · SALU — the part no media engine knows

| Row | Reads | Source | Shows when |
|---|---|---|---|
| Queue | `4 of 12` | **in hand** (`QueueService.index` + length) | the queue holds more than one item |
| Played from | `resumed 12:34` | **in hand** (`ResumeService`) | the file was resumed |
| EQ | preset name, else `Custom` | **in hand** (`TuneService`) | the curve is not flat |
| Subtitles | `+0.4 s` | **in hand** (`PlayerService.subDelay`) | a subtitle track is selected |
| Engine | `mpv 0.3x` ⚠ | new read | after §7 verifies the name |

### 6 · Stream — only for a URL / IPTV channel

| Row | Reads | Source | Shows when |
|---|---|---|---|
| Provider | the channel's host or provider name | **in hand** | a URL/channel is playing |
| Group | the channel's category (`group-title`) | **in hand** (`channel_metadata`) | tagged |
| Language | the value **and how it was inferred** (`Bangla · from the tvg-id`) | **in hand** (`MetadataSource`) | inferred or tagged |
| Country | the value and its source (`Bangladesh · from the tvg-id`) | **in hand** | inferred or tagged |
| Bitrate | `demux-bitrate` / `hls-bitrate` ⚠ | new read | the engine answers |
| Buffered | `demuxer-cache-duration` ⚠ | new read | a stream is buffering |

**Showing where a fact came from is Salu's own idea** — the channel list
already tracks it (`MetadataSource`), and the Info panel is the one place a
viewer can see that the country was read out of a tvg-id rather than guessed.

## 0.5 What drops out — presence rules

| Playing | Groups drawn |
|---|---|
| Local audio | Identity · Sound · Clock & file · SALU |
| Local video | Identity · Picture · Sound · Clock & file · SALU |
| URL / IPTV channel | Identity · Picture (if a picture arrives) · Sound · Stream · SALU |
| Nothing loaded / STOPPED | **none** — the panel does not open (§0.8) |

The rule that makes this work is the same one the album-art canvas already
follows: **a row with no truth is not drawn.** Empty groups vanish with it. A
panel of four honest rows beats a panel of thirty fields with `undefined` in
some of them.

## 0.6 Live or frozen — the clock ticks, everything else is read once

This refines the earlier "freeze it all" recommendation, because Position and
Remaining were asked for by name — frozen they would look broken within a
second.

| Part | Behaviour |
|---|---|
| Duration · Position · Remaining | **tick**, off the `position` / `duration` notifiers that are already running |
| Every other row | read **once** when the panel opens |
| Re-reads | on media change, audio-track change, resolution change, subtitle selection change — the notifiers for all four already exist |
| Never | a polling timer, a per-frame read, or a read loop |

So: no new timers, no new cost while the panel is open, and nothing on screen
that is stale.

## 0.7 What is NOT shown — refused, on purpose

| Refused | Why |
|---|---|
| Every junk class of §5 — raw scheme names (`Id3v2 PRIV:`), binary payloads, giant blobs, ripper/scraper signatures, duplicate tag versions, free text (`COMMENT` / `DESCRIPTION` / `SYNOPSIS`) | the container's plumbing, not a fact a viewer can use |
| The full tag dump | stays parked behind a future explicit action (its own design) |
| MusicBrainz / AcoustID ids · play counts and ratings · mood / BPM / key · chapters · podcast fields | true, interesting, and noise in a panel about *this* playback |
| ReplayGain | a **tune-layer input** (L35), not a display row |
| Embedded lyrics | mode B's subject, never this panel (L34) |
| Copy-a-value · reveal-in-Explorer · a cover thumbnail · the folder path | parked affordances — none of them earn a first build, and the path is already on screen in the window title |

## 0.8 Behaviour

| Situation | Behaviour |
|---|---|
| Door | right-click menu → the Info mark, Player mode only. The mark reads **lit** while the panel is open |
| Nothing loaded, or STOPPED | the mark is **dimmed and inert** (the transport's own dim-don't-hide rule) — there is no playback to describe |
| One popup world | opening Info closes the Playlist · Track · Tune panels **and the Open pill**; opening any of them closes Info |
| ⚠ The Open pill | **finding:** the pill drops into the same left region and today does **not** close panels — `open_media_control.dart` makes no `PanelService` call — while the panel layer paints *above* the chrome, so the two would overlap with the panel covering the pill. Wiring `PanelService.infoOpen` into the pill's open path is part of building this panel |
| Esc | closes the panel first (the panel tier), then the menu, then whatever else is open |
| Click-outside | closes — the playlist panel's opaque barrier recipe, so the closing click never falls through to the picture |
| Chrome | `ChromeLock` is held while open, so the chrome never auto-hides beneath it |
| Media change (Next / a new file) | the panel **re-reads and stays open** — unlike the Track panel, which closes. It describes what is playing, so it follows the picture |
| Web mode | cannot exist — the player tree is not built while the browser owns the window |
| Mini mode | cannot exist — the 32 px bar builds no popups |
| Channel (IPTV) | works, with the Stream group; the *menu* still drops shuffle/repeat there |

---

# §1–§6 · The inventory (candidates, now marked)

**How to read the marks:** `shown` = a §0 row reads it · `canvas` = the album
art canvas already renders it · `parked` = in reach, not on any surface ·
`refused` = decided against (§0.7 / §5).

## 1. Where data comes from — five places

| # | Source | What it yields | Salu reads it today? |
|---|---|---|---|
| 1 | **mpv tag map** — `metadata` (walked as `metadata/list/count`, `metadata/list/N/key`, `metadata/list/N/value`; `metadata/by-key/<key>` as fallback) | every text tag the file carries | **yes** — `audio_display_service.dart::_readTagMap` |
| 2 | **mpv per-track metadata** — `track-list/N/metadata`, `chapter-metadata`, `playlist/N/metadata` | tags attached to a track or chapter | no — parked |
| 3 | **mpv state properties** — `video-params/*`, `audio-params/*`, `duration`, `demuxer-cache-state/*`, … | the technical truth | **partly** — §0 rows 2/3/4/6 name the ones to add |
| 4 | **`audio_metadata_reader`** | embedded picture bytes | pictures only |
| 5 | **SALU's own state + filesystem** | queue, resume, EQ, favourites, lyric sidecar, `File.stat` | **yes** — §0 group 5 reads it |

Rule that keeps 1 honest (lrc.md §3.7): the read is **`metadata`, never
`filtered-metadata`** — the filtered map is cut down to mpv's `--display-tags`
whitelist.

## 2. Audio text tags

`Canvas` = rendered by mode C today (L32) · `Info` = a §0 group-1 row.
Marked per row: **Title, Artist, Album, Genre, Year, Track** are `canvas + info`;
**Disc** is `info`; everything else in this section is `parked` unless noted.

### 2.1 Identity

| Field | Typical tag names (ID3v2 · Vorbis · MP4 · ASF · APEv2 · Matroska) | Surface |
|---|---|---|
| Title | `TIT2` · `TITLE` · `©nam` · `Title` · `Title` · `TITLE` | canvas + info |
| Artist | `TPE1` · `ARTIST` · `©ART` · `Author` · `Artist` · `ARTIST` | canvas + info |
| Album | `TALB` · `ALBUM` · `©alb` · `WM/AlbumTitle` · `Album` · `ALBUM` | canvas + info |
| Genre | `TCON` · `GENRE` · `©gen`/`gnre` · `WM/Genre` · `Genre` · `GENRE` | canvas + info |
| Date / year | `TDRC`/`TDRL`/`TYER` · `DATE`/`ORIGINALDATE` · `©day` · `WM/Year` · `Year` · `DATE` | canvas + info |
| Track number / total | `TRCK` · `TRACKNUMBER`/`TOTALTRACKS` · `trkn` · `WM/TrackNumber` · `Track` · `PARTNUMBER` | canvas + info |
| Disc number / total | `TPOS` · `DISCNUMBER`/`TOTALDISCS` · `disk` · `WM/PartOfSet` · `Disc` | **info** |
| Album artist | `TPE2` · `ALBUMARTIST` · `aART` · `WM/AlbumArtist` · `AlbumArtist` | parked |
| Artist / album sort order | `TSOP`/`TSOA` · `ARTISTSORT`/`ALBUMSORT` · `soaa`/`soal` | parked |
| Subtitle / version / mix name | `TIT3` · `SUBTITLE` · `©grp`? · `SUBTITLE` | parked |
| Compilation flag | `TCMP` · `COMPILATION` · `cpil` · `WM/IsCompilation` | parked |
| Movement / work (classical) | `MVNM`/`MVI`/`WKSD`/`GRP1` · `MOVEMENT*` · `©mvn`? · `WORK` · `MOVEMENTNAME` | parked |
| Recording / session / wave labels | `TSEE`? · `R128_*`? | parked — *diagnostic* |

### 2.2 Credits — who made it

**Every row in this block is `parked`.** Not refused — a credits block is a
legitimate future addition to the Info panel (one more group), it just is not
in the owner's first definition.

Composer · Lyricist/writer · Arranger/remixer/producer · Performer/conductor ·
Engineer/mixer · Publisher/label/catalogue/barcode/ISRC · Copyright/licence ·
Language/script.

### 2.3 The release and the collection

| Field | Surface |
|---|---|
| Media type / source (`TMED` · `MEDIA` · `WM/Media`) | parked |
| Rating / popularity / plays (`POPM` · `RATING` · `©rta` · `WM/Rating`) | **refused** (noise in a playback panel) |
| Mood / BPM / key (`TMOO`/`TBPM`/`TKEY` · `MOOD`/`BPM`/`INITIALKEY`) | **refused** for now |
| ReplayGain / loudness (`RVA2`, `REPLAYGAIN_*`, `R128_TRACK_GAIN`) | **refused as display** — a tune-layer input (L35) |
| Album series / part · Disc subtitle | parked |
| MusicBrainz / AcoustID ids | **refused** as display |
| Disc ID / CDDB / cue sheet | parked |
| Chapters / table of contents | parked (the timeline is their future home) |
| Podcast / show / episode (`TGID`/`TSSY`? · `PODCAST`/`SHOW`/`EPISODEID`/`SEASONNUMBER` · `tvsh`/`tven`/`tvsn`) | parked |
| Lyrics, unsynced / synced (`USLT`/`SYLT` · `LYRICS` · `©lyr` · `Lyrics`) | **refused here** — mode B's subject (L34) |
| Cover / extra art (`APIC` · `METADATA_BLOCK_PICTURE` · `covr` · `WM/Picture`) | the art slot + **canvas**; a panel thumbnail is parked |
| Comment / description / synopsis | **refused** (free text, §5) |
| Encoding provenance (`TENC`/`TSSE` · `ENCODED_BY`/`ENCODER`/`ISFT`) | parked |
| Tool / watermark / scratch (`MP3GAIN`, `Id3v2 PRIV:*`, `TXXX:*`, `----:com.apple.iTunes:*`) | **refused** (§5) |

### 2.4 Everything else the file may hold

mpv hands over the raw tag names it did not recognize, so the parked set is
open-ended by design. Observed in the owner's real file (2026-09-15):

```
title · artist · album · genre · album_artist · comment · encoder
lyrics-<description>            ← ID3v2 TXXX / USLT with a description
Id3v2 PRIV:peak value           ← binary, mp3gain-era
Id3v2 PRIV:average level        ← binary, mp3gain-era
```

All four junk candidates stay `refused` (§5).

## 3. Audio — the technical facts (⚠ = verify against the shipped engine)

| What | Where it lives | Surface |
|---|---|---|
| Codec (decoder + description) | `audio-codec`, `audio-codec-name`, `track-list/N/codec`, `/codec-desc`, `/codec-profile` | **Sound · Codec** |
| Sample rate, format, channels | `audio-params/samplerate`, `/format`, `/channels`, `/channel-count`, `audio-samplerate`, `audio-channels` | **Sound · Sample rate / Channels** |
| Bitrate | `track-list/N/demux-bitrate`, `audio-bitrate` | **Sound · Bitrate** |
| Duration / position | `duration`, `playback-time`, `time-pos`, `percent-pos`, `remaining` | **Clock & file** (duration, position, remaining) |
| File size / path / name / format | `file-size`, `path`, `filename`, `media-title`, `file-format` | **Clock & file** · Title fallback |
| Delay / gain / volume | `audio-delay`, `volume`, `volume-max`, `mute`, `balance`, `speed` | parked (the bars already show volume) |
| ReplayGain (parsed) | `track-list/N/replaygain-*` | **refused as display** — tune-layer input |
| Track inventory | `track-list/count`, `track-list/N/{id,type,title,lang,selected,default,forced,external,external-filename,albumart,image,src-id,ff-index,decoder-desc}` | **Sound · Codec/Channels/Language** — the rest is parked |
| Chapters | `chapter-list/N/{title,time}`, `current-chapter` | parked |
| Seekability / streaming | `seekable`, `eof-reached`, `demuxer-via-network`, `demuxer-cache-duration` | **Stream · Buffered** |
| Output device | `audio-device`, `audio-device-list` | parked (settings material) |
| Filters in the graph | `af`, `current-af`⚠ | parked (SALU writes the EQ through `af`) |

## 4. Video — what the engine can say

| Group | Properties | Surface |
|---|---|---|
| Geometry | `video-params/{w,h,…,aspect,PAR,rotate,…}` | **Picture · Resolution** |
| Motion | `container-fps`, `estimated-vf-fps`⚠, drop counters, `frame-info`⚠ | **Picture · Frame rate**; counters parked |
| Codecs | `video-codec`, `video-bitrate`, `hwdec-current`, `hwdec-interop` | **Picture · Codec / Bitrate / Decoder** |
| HDR / colour | `target-prim`, `target-trt`, `target-space`, `video-out-params/*`, gamut mapping ⚠ | **Picture · Colour — HDR only** |
| Frame / cut | `frame-step`, `frame-back-step`, `frame-metadata`⚠ | parked |
| Subtitles (owned by `cc.md`) | `sub-delay`, `sub-pos`, `sub-scale`, `sub-visibility`, `sub-text`, fonts/colours, `sub-file`, … | **SALU · Subtitles** (delay only) — everything else belongs to the Fetch panel |
| Tracks | `vid`, `aid`, `sid`, `secondary-sid`, `current-tracks/*`, `edition-list` | **Sound** reads the selected audio row; the rest parks with the Track panel |
| Menus / discs | `discs`, `disc`, `bluray-title`, `bluray-angle` | parked |
| Chapters | `chapter`, `chapter-list/*`, `chapter-metadata/*` | parked |
| Cache / network (**IPTV**) | `demuxer-cache-state/*`⚠, `demuxer-cache-duration`, `stream-*`, `network-timeout`, `user-agent`, `referrer` | **Stream · Buffered**; the rest parked |
| HLS / adaptive | `track-list/N/hls-bitrate`, `/program-id` | **Stream · Bitrate** |
| DVB / IPTV stream metadata | service and provider names, `dvbin`-channel params ⚠ | **Stream · Provider** |
| Window / display | `display-names`, `current-monitor`, `window-id`, `window-scale`, … | parked |
| Engine identity | `mpv-version`, `ffmpeg-version`⚠, `build-date`⚠, `options/*` | **SALU · Engine** (mpv only, after §7) — also About's material |

## 5. Junk classes — refused, and why

| Class | Examples | Why it stays off screen |
|---|---|---|
| Raw scheme names | `Id3v2 PRIV:…`, `Id3v1`, `riff INFO/IART`, `asf/WM/…`, `mp4:----:…`, `movstat_*`, `xmp:*` | the container's plumbing showed through |
| Binary payloads | `RVA2`, PRIV gain frames, `APIC` bytes | bytes, not text |
| Giant blobs | embedded lyrics, `CUESHEET`, multi-MB `PICTURE` blocks, `padding` | one of these is exactly what used to push the album art up the screen |
| Scraper / ripper signatures | `TXXX:*` descriptions, `MusicBrainz Release Group Id`, `AMZ*`, `iTN*`, `LAME`/`ExactAudioCopy` | true, interesting, not for a viewer |
| Same field, two tag versions | ID3v2.3 `TYER` and v2.4 `TDRC`; `date` and `year` disagree | alias order picks one, the loser stays parked |
| Free text | `COMMENT`, `DESCRIPTION`, `SYNOPSIS` | length, newline, language and content are all unknowable |

## 6. SALU's own facts — no media engine knows these

| Fact | Where | Surface |
|---|---|---|
| Queue position, item kind, grouping | `queue_service.dart`, `channel_grouping.dart` | **SALU · Queue** |
| M3U group / language / country **+ how each was inferred** | `m3u/channel_metadata.dart` (`MetadataSource`) | **Stream · Group / Language / Country** |
| Channel favourites | `channel_favourites_service.dart` | parked |
| URL library entries, last-play status dot | `url_library_service.dart` | parked |
| Resume position + duration | `resume_service.dart` | **SALU · Played from** |
| EQ curve, preset, auto-EQ memory | `tune_service.dart`, `tune/auto_eq.dart` | **SALU · EQ** |
| Subtitle delay, loaded subs | `sub_delay_service.dart`, `subtitle_service.dart` | **SALU · Subtitles** |
| Lyric sidecar found, line count | `lyric_locator.dart`, `lyric_service.dart` | parked |
| Cover-art cache key + validity | `audio_display_service.dart` (L27) | parked |
| Filesystem: size, folder, autoload origin | `File.stat`, `folder_autoload_service.dart` | **Clock & file · File size**; the folder is parked |
| Window / title-bar mode, title text | `settings_service.dart`, `custom_title_bar.dart` | parked |

---

## 7. Harvesting the truth — do this before the ⚠ rows ship

Names in this file are candidates. The rows that need verification **before
they can appear in §0** are exactly these:

`container-fps` · `video-codec` · `video-bitrate` · `demux-bitrate` ·
`audio-params/samplerate` · `audio-bitrate` · `file-format` · `file-size` ·
`demux-channels` · `target-prim` / `target-trc` · `mpv-version` ·
`demuxer-cache-duration` · `hls-bitrate`

The recipe, unchanged from the original doc:

1. **Log the engine identity** — `mpv-version` at startup in a debug build, so
   a claim can be tied to a version.
2. **Enumerate properties** — `get_property` on `property-list`⚠, or
   `mpv --list-options` / `--show-profile=all`⚠ on the same libmpv build.
   Anything the probe answers is real; anything it does not, delete here.
3. **Dump the tag map for a corpus** — a dozen representative files (MP3 with
   PRIV frames, FLAC with cuesheet + lyrics, M4A with `----` atoms, WAV with
   RIFF INFO, OGG/Opus, an MKV with chapters, a TS/IPTV stream). That is the
   real junk list, and it settles §5.
4. **Per-track metadata** — read `track-list/N/metadata` for a multi-audio or
   multi-sub file; today Salu never asks.
5. A name that fails the probe is **deleted from §0's row list** — the row
   simply never ships. It is never replaced by a guess.

---

## 8. Build checklist for the Info panel

- [ ] `PanelService.infoOpen` — the one notifier, beside the other three.
- [ ] `lib/ui/panels/info_panel.dart` — glass, geometry and motion copied from
      `playlist_panel.dart`, mirrored to the left (§0.2).
- [ ] The one-read collector: one pass over the §0 rows at open, one pass on
      media/track/resolution/subtitle change, nothing on a timer.
- [ ] The clock rows bound to the existing `position` / `duration` notifiers.
- [ ] The Open pill's open path closes the panel (the §0.8 finding).
- [ ] `InfoMark` added to `salu_marks.dart` (see `right_item.md` §4), wired to
      the right-click menu's Info slot and dimmed when nothing is loaded.
- [ ] Esc / click-outside / CloseMark / `ChromeLock`, all on the existing
      panel recipe.
- [ ] `flutter analyze` clean; widget tests for the presence rules (§0.5) and
      the one-popup world (§0.8).
- [ ] Seen on a real Windows build with hardware decoding on, over a live 4K
      picture — the blur cost is the one thing a test cannot prove.

## 9. Open questions

1. **The clock** — confirm §0.6: the three clock rows tick, everything else is
   read once. (Supersedes the earlier "freeze everything" advice.)
2. **Credits (§2.2)** — a second wave for the panel, or never? Every row there
   is parked, not refused.
3. **A cover thumbnail** at the top of the panel — parked; say the word and it
   moves into the first build (`AudioDisplayService.coverBytes` is already in
   hand).
4. **About** — Salu's own identity (version, credits, engine) is still
   unbuilt (Phase 9). SALU · Engine is the one row that touches it; does About
   become its own door later, or grow out of this group?
5. **A silent keyboard shortcut** — the owner locked the menu as the only
   door. `Ctrl+I` would cost nothing and is never printed (rule 2). Noted,
   not applied.
6. **Per-file or per-playback truth** — codec/size facts as the *container*
   declares them, or as the *output graph* ends up after hardware decoding and
   filters? They disagree in interesting ways; §0 currently takes the engine's
   live answer.
