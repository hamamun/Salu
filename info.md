# SALU — info.md (the Info panel + the parked data inventory)

> **Purpose — two halves, in this order:**
>
> * **§0 · THE SURFACE** — exactly what the Info panel shows for any audio or
>   video file (or stream) that is playing. **DEFINED 2026-09-19 by the owner.**
> * **§1–§6 · THE INVENTORY** — the parked candidate table behind it: every
>   field Salu *can* have, now marked **shown / parked / refused** against §0.
> * **§7 · THE HARVEST** — how a candidate name becomes a shipping row.
>
> **Status: FULLY DECIDED (2026-09-19). No question is open in this file.**
> §0 is the locked surface — its placement, its rows, its presence rules and
> its live-clock rule. Every §9 question was answered by the owner on
> 2026-09-19 and is recorded there as a decision.
>
> The **inventory** (§1–§6) is still candidates, not contracts: ⚠ marks a name
> that must be verified against the engine Salu actually ships **before** it
> appears in a §0 row. A name that does not answer is dropped, never guessed
> at — that is the only work left in this file, and it is a task (§7), not a
> question.
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
| Width | **`min(322, windowWidth − 24)`** — 322 at every real size (the window floor is 800), clamping only as a guard if that floor ever drops | the Playlist panel's width, reused: **one panel width, two sides** |
| Height | `windowHeight − kChromeBlockHeight` — at the 800 × 600 floor that is **452 px**, so every group fits without scrolling; the scroll view is the safety net, not the plan | the chrome block is 40 + 108 = 148 |
| Glass | `ClipPath(_TopRightRadius(14))` + `BackdropFilter(blur 18)` + `AppColors.glass` + a **right-edge** hairline (`surfaceOutline`) | the playlist panel's recipe, mirrored |
| Arrival | slide in from the left, one 220 ms forward/reverse controller, opacity tied to the same curve | the playlist panel's motion, verbatim |
| Hit-testing | stops the instant it starts closing | a closing panel must never eat a click |
| Overflow | one scroll view when the rows exceed the height; no scrollbar, fixed row heights | a long list stays a scroll offset |
| Collision | the Open pill reaches **36 px below** the chrome block (its own geometry: `+` button ends at y 136, pill drops 6 px, capsule is 42 tall → y 142–184, against a chrome bottom of 148). So it lands in this panel's top strip → **one-popup world, wired both ways** (§0.8) | measured, not guessed — the two would stack in the left column |

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

*(No engine/version row: that is About's, and only About's — §0.7.)*

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
| **A cover thumbnail** | **REFUSED by owner decision, 2026-09-19** — the panel is facts, not art (the art already has its own canvas in audio mode) |
| App identity — app version, app credits, the mpv/ffmpeg build numbers | **not this panel** — **About owns it** (Phase 9: `lib/ui/modals/about_modal.dart`, entered from Settings). Info describes *what is playing*, About describes *Salu*. The two never merge (owner, 2026-09-19) |
| Copy-a-value · reveal-in-Explorer · the folder path | parked affordances — none of them earn a first build, and the path is already on screen in the window title |

## 0.8 Behaviour

| Situation | Behaviour |
|---|---|
| Door | right-click menu → the Info mark, Player mode only. The mark reads **lit** while the panel is open |
| Nothing loaded, or STOPPED | the mark is **dimmed and inert** (the transport's own dim-don't-hide rule) — there is no playback to describe |
| One popup world | opening Info closes the Playlist · Track · Tune panels **and the Open pill**; opening any of them closes Info |
| The Open pill | **decided — the pill joins the one-popup world, both directions.** Measured collision: the pill spans y 142–184, the chrome block ends at 148, so **36 px of the pill sits in this panel's top strip**, and the panel paints above the chrome — the panel would cover the pill. The fix is the app's own rule (rule 3), not a new layout: opening the pill sets `PanelService.infoOpen = false`, and `OpenMediaControl` listens so that opening **Info** closes a pill that is up. The alternative — starting the panel 42 px lower to dodge the pill — is **rejected**: it would break the panel's flush alignment with the chrome's bottom edge, and the Playlist panel beside it, for a popup that is up a fraction of the time |
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
| Cover / extra art (`APIC` · `METADATA_BLOCK_PICTURE` · `covr` · `WM/Picture`) | the art slot + **canvas**; a panel thumbnail is **refused** (owner, 2026-09-19) |
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
| Engine identity | `mpv-version`, `ffmpeg-version`⚠, `build-date`⚠, `options/*` | **refused here** — About owns app + engine identity (Phase 9, §0.7) |

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

## 7. How the ⚠ names get settled — **decided: no separate probe pass**

*Owner delegated this decision, 2026-09-19.* Nothing is probed by hand and no
harness is built. The names settle themselves, in this order:

1. **Every new read is defensive.** Try the primary name; if it does not
   answer, try the alternate (`audio-bitrate` → `demux-bitrate`); if neither
   answers, the row is simply **not drawn** — the §0.3 rule that already
   governs the whole panel. Nothing is guessed, nothing prints `N/A`.
2. **The recipe already exists in the codebase** —
   `audio_display_service.dart`'s `_probeKeys` plus its by-key / uppercase
   fallback chain is exactly this pattern. §0's reads follow it; a second
   convention is never invented.
3. **One debug-build log line per Info open** names what answered and what did
   not — so a single run on a real Windows build settles the whole list at
   once, with no separate task and no extra tooling.
4. **After that first build, any row that never answered is deleted from §0.**
   A row that cannot ship leaves no trace in the spec.

The names below are kept only as the checklist that log line is read against —
not as a to-do:

`container-fps` · `video-codec` · `video-bitrate` · `demux-bitrate` ·
`audio-params/samplerate` · `audio-bitrate` · `file-format` · `file-size` ·
`demux-channels` · `target-prim` / `target-trc` ·
`demuxer-cache-duration` · `hls-bitrate`

*(No `mpv-version` probe is needed: engine identity belongs to About, not to
this panel — §0.7.)*

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

## 9. Decisions — every question closed (2026-09-19)

**Nothing in this file is waiting on the owner.** Recorded here so a later
reader sees the reasoning, not just the verdict.

| # | Question | Decision | Why |
|---|---|---|---|
| 1 | Do the clock rows tick? | **Yes** — duration, position and remaining tick off the existing `position` / `duration` notifiers. Everything else is read once at open and re-read on media / track / resolution / subtitle changes (§0.6) | frozen, they look broken within a second; ticking costs no timer |
| 2 | A credits block (composer, label, ISRC, copyright …)? | **Not in the first build** — every §2.2 row stays *parked*, none refused. It is one more group whenever the owner wants it | the panel is already six groups on a 322 px surface |
| 3 | A cover thumbnail at the top? | **NO** (owner) | the panel is facts, not art — the art already owns the audio canvas |
| 4 | Merge About into Info? | **NO** (owner) — **About stays its own Phase 9 window**, entered from Settings, and **nothing in this file touches it**. Info = what is playing; About = Salu itself | two different subjects; they never share a door |
| 5 | A silent `Ctrl+I` shortcut? | **Not applied** — the right-click menu is the only door (owner). Noted, never added | the owner locked one door on purpose |
| 6 | Per-file truth (container) or per-playback truth (output graph)? | **The engine's live answer** — what mpv reports right now, after hardware decoding and filters | it is the truth about what is actually playing, which is the panel's whole subject |
| 7 | How are the ⚠ property names verified? | **No separate probe pass** — defensive reads with alternates, a row that does not answer is not drawn, one debug log line per open names what answered, and rows that never answer are deleted after the first real build (§7) | it turns the first Windows run into the probe instead of inventing a task |
| 8 | The Open pill in the same corner? | **The pill joins the one-popup world, both directions** (§0.8). The panel keeps its flush alignment with the chrome — no reserved gap | measured: 36 px of overlap; the app's rule 3 already answers it |
| 9 | Panel sizing when the window changes? | **`min(322, windowWidth − 24)` wide, `windowHeight − 148` tall** (§0.2) — 322 × 452 at the window floor | the floor makes it a guard, not a redesign; the panel never needs a "too small" state |

Anything a later session wants to revisit is a **new question**, not a re-open
of these — the file is closed at this revision.

