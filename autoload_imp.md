# Folder auto-load — implementation brief

> **Status:** **IMPLEMENTED (Phase B, shipped 2026-09-07).** Settings →
> General → *Folder auto-load* (`Off · All videos in folder · Same
> series only`, default **All**, persisted). The trigger lives in
> `folder_autoload_service.dart::maybeExpand`, called from the three
> single-file entry points (Open File single pick · single-file drop ·
> open-with, both cold-start and second-instance); the in-place queue
> surgery lives in `player_service.dart::insertAroundCurrent`; the
> verdict card is `OsdAutoloadCard`. Prerequisite was `playlist_imp.md`
> **Phase A** (shipped); never interleave changes with playlist §10
> (m3u / IPTV) work.
>
> **The exception is recorded at the source:** playlist_imp.md §1 lock
> 5's "a fresh load starts at row 0" has exactly one sanctioned
> exception — an auto-load trigger starts at the picked file's natural
> folder row (lock 7 below). It is noted in playlist_imp.md's header
> box as well.
>
> **New session? Read this box, then §1.** Owner rulings recorded here —
> do not re-open them:
> - **Level 3 (content similarity) is DROPPED by the owner, permanently.**
>   Matching is folder membership and name shape only. Files are never
>   opened, fingerprinted or decoded to decide "similar".
> - **Playback never waits for the scan.** The picked file opens exactly
>   as Phase A does today; the queue fills in *behind* the playing row.
>   The current media object is never reloaded to grow the queue.
> - **One Settings picker, three modes, default ON.** Owner: "on by
>   default, but if the user turns it off it must be remembered across
>   sessions."
>
> **Read `follow.md` first — every hard rule applies.** Where this brief
> fills a gap the owner did not decide, the entry is marked *(default)*
> and may be vetoed; nothing else is open.

---

## 0. Baseline (what the code already gives you)

| Area | Fact | File |
|---|---|---|
| Folder scanner | `DropHandler.scanFolderForMedia(dir)` — **non-recursive** (`listSync`), video+audio (`MediaUtils.isMedia`), already sorted natural. Needs one new parameter: kind filter (§2). | `core/drop_handler.dart` |
| Natural order | `MediaUtils.naturalPathCompare` / `naturalCompare` — the "mpv serial": folder first, then name, `ep2` before `ep10`. | `core/media_utils.dart` |
| Kind split | `MediaUtils.isVideo` / `isAudio` / `isMedia` + the extension sets. | `core/media_utils.dart` |
| Single-file entry points | **Three:** ① Open File… resolving to one path (`openFiles` → `openPath`) · ② drop resolving to one media file (`drop_handler.dart` → `openPath`, line ~49) · ③ Explorer open-with / command-line arg (`main.dart::openPath` → `home_screen` initial). | `open_media_service.dart`, `drop_handler.dart`, `main.dart` |
| Queue surgery | media_kit `Player`: `add(Media)`, `move(from, to)`, `jump(int)` — insert around the current item without reopening it. | playlist_imp.md §0 |
| Queue truth | `QueueService.instance` — filling the engine playlist is what fills the panel; no separate view-list to sync. | `core/queue_service.dart` |
| Settings pattern | `SettingsService` — enum + `ValueNotifier` + `shared_preferences` key, loaded before first frame. UI = General-tab radio group (`_OptionTile` rows: `TitleBarModePicker`, `ResumeModePicker`). | `core/settings_service.dart`, `ui/widgets/settings_dialog.dart` |
| OSD deck | One transient top-center card slot, ≤ 1 s, never wakes chrome (follow.md §6). | `ui/osd/osd_deck.dart` |

---

## 1. Locked decisions (owner's picks, 2026-09-07)

| # | Decision | Locked value |
|---|---|---|
| 1 | **Feature exists as a Settings picker** | Settings → General gets a **Folder auto-load** radio group with three options: **Off · All videos in folder · Same series only.** Built with the existing `_OptionTile` pattern — no switches, no new UI family. |
| 2 | **Default = ON, and it sticks** | Factory default is **All videos in folder**. The choice persists via `shared_preferences` and is remembered across sessions (owner's explicit requirement). |
| 3 | **Trigger = exactly one local media file** | Fires at all three single-file entry points (§0). **Never** fires for: multi-select batches, Open Folder… (already the whole folder), URLs, or `.m3u` / `.m3u8` playlists. |
| 4 | **Same kind only** | The scan keeps the picked file's kind: video → queue videos, audio → queue audio. A video binge never swallows the MP3s sitting next to it, and an MP3 still picks up its album. |
| 5 | **One folder deep** | The picked file's own folder only. No recursion, ever. |
| 6 | **Order = natural serial** | The folder's own natural order (`naturalPathCompare`) — what mpv's autoload produces: `ep2` sits before `ep10`. |
| 7 | **Start position = the picked file** | This is the **single sanctioned exception** to playlist_imp.md §1 lock 5 ("a fresh load starts at row 0"). For an auto-load trigger, row 0 is *not* the start — the file the user pointed at is. Its row in the shown list is its natural position in the folder order, and playback begins there. Record this exception in playlist_imp.md when this phase ships, so nobody "fixes" it later. |
| 8 | **Both modes ship in one phase** | Owner chose "together": the three-option picker ships complete (§3), not staged. |
| 9 | **Same series = name shape only** | Deterministic filename matching (§3.2). When nothing matches, **nothing extra is queued** — no fallback to whole-folder (that would be the surprise the mode exists to prevent). |

---

## 2. The trigger surface

Flow at each of the three single-file entry points:

1. Load the picked file **immediately**, exactly as Phase A does today
   (`openPath`). Zero added delay, zero behavior change at this step.
2. Read `FolderAutoloadMode`. **Off → stop.** Excluded source (URL,
   playlist file, batch > 1) → stop.
3. Scan the picked file's folder — non-recursive, **kind-filtered**
   (`scanFolderForMedia` gains a kind parameter; Off/Open-Folder callers
   keep the current video+audio behavior).
4. Keep matches per the active mode (§3). If the result is just the
   picked file itself → stop; playback is already right.
5. Sort natural. Insert the siblings into the engine playlist **around
   the current item** (`add` + `move`), so the shown order equals the
   folder order and the picked file sits at its natural index, still
   playing. Set `QueueService` truth to match. **The current media is
   never reopened** — no flicker, no position jump, resume memory
   untouched.

### 2.1 Edge cases

| Case | Behavior |
|---|---|
| Only media file in its folder | Scan returns itself → nothing queued; indistinguishable from Off. |
| A queue already exists | Replaced by the new folder's queue — same replace semantics a single drop has today. Phase A's Stop-parks-the-queue rule is untouched (auto-load only runs at a *load* gesture). |
| Toggle changed mid-session | Applies from the next load gesture; never retrofits the live queue. |
| Huge folder (thousands) | A filename listing is milliseconds regardless; no cap, no progress UI *(default)*. |
| Subtitle siblings (`.srt`) | Ignored by the scan — `isMedia` already excludes them. Existing drop-time subtitle attach is unaffected. |

---

## 3. The two modes

### 3.1 All videos in folder

Default mode. The scan result (same kind, natural order) **is** the
queue. This covers "the whole season is in one folder" — the everyday
binge case — with zero guessing.

### 3.2 Same series only

Matches by **name shape**, computed like this:

1. Take the file **name without extension**.
2. Case-fold; treat `space`, `.`, `_`, `-` as one separator kind.
3. Replace **every run of digits** with a single `#` token, regardless of
   length or value.
4. Two files are the same series iff their shapes are **identical**.

| Picked file | Matches | Does not match |
|---|---|---|
| `Show.S01E03.mkv` → `show s#e#` | `Show S01E01`, `show_s02e07` | `Show.1080p.x264` (`show # x#`), `ShowTrailer` |
| `Movie.CD1.avi` → `movie cd#` | `Movie CD2` | `Movie (2003)` |
| `DSC_0012.jpg`-style camera dump | all of `DSC_0001…9999` | — (accepted: in this mode a camera dump *is* one named series; the user picked the mode) |

Deterministic, unit-testable with pure strings, and explains itself in
one sentence. No aliases, no fuzzy scoring, no "did you mean".

---

## 4. Feedback (one whisper) — *(default, one-line veto)*

When auto-load grows the queue, flash **one** transient OSD deck card:
`12 videos queued from "Season 1"` (count + kind word + folder name,
≤ 1 s, follow.md §6 language — a status card, not instruction text). It
exists so a 200-file folder never *silently* becomes the playlist. Veto
it and the feature goes fully silent.

---

## 5. Settings integration

- `SettingsService` gains `FolderAutoloadMode { off, allVideos,
  sameSeries }` with `ValueNotifier`, key `folder_autoload_mode`, default
  `allVideos`, loaded in `load()` like the two existing enums.
- `SettingsDialog` → General tab: a third radio group beside Title bar
  and Resume, same `_OptionTile` anatomy (name row + tiny descriptor +
  radio dot). Copy: **Folder auto-load** — *Off* / *All videos in
  folder* / *Same series only*. No shortcut labels, no teaching text
  (follow.md §1 rules 1–2).

---

## 6. Out of scope (locked out)

- **Content similarity (Level 3)** — dropped by owner; never resurface.
- Recursion into subfolders.
- Mixed-kind queues.
- Regex / user-defined patterns for "same series".
- Any indexing, library, or background watching of folders.

---

## 7. Verification checklist (when built)

1. Toggle **Off** → all three entry points behave byte-identically to
   Phase A.
2. Default install (no key stored) → auto-load **On**, *All videos* mode.
3. Flip to Off, kill the app, relaunch → still Off (owner's persistence
   rule).
4. One file from a 12-video folder → 12-row queue, picked file at its
   natural row, playing **uninterrupted** from load to panel fill (watch
   the position tick — it must never reset).
5. `ep2` … `ep10` order is natural, not lexicographic.
6. Same-series mode: §3.2's table, each row.
7. Same-series with no siblings → single file, no queue change.
8. Multi-select of 3, Open Folder, a URL, an `.m3u` → never trigger.
9. Video pick next to MP3s → MP3s absent; audio pick next to videos →
   videos absent.
10. Resume toast for the picked file still works as in Phase A.

---

## 8. Defaults registry (veto list)

| Entry | Veto changes it to |
|---|---|
| §2.1 huge folders: no cap | add a cap + overflow behavior |
| §4 one OSD whisper card | fully silent growth |
| §5 label copy *Folder auto-load* | owner's wording |
