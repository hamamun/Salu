# SALU — cc.md (Subtitle decisions & implementation contract)

> **Purpose:** The single decision log for everything subtitle-related in SALU.
> Every subtitle decision the owner locks in chat lands here first, then in code.
> `follow.md` (hard rules) and `outline_transport_osd_resume.md` (transport/OSD)
> still bind everything below — this file only adds subtitle rules.
>
> **Status:** DECISIONS LOCKED D1–D13, D15–D17 (owner, 2026-09-09) ·
> D14 (Fetch button) still proposed, design not locked · NOT YET IMPLEMENTED.

---

## 1. Locked decisions

| # | Decision | Status | Date |
|---|---|---|---|
| D1 | Settings gains a second tab **"Subtitles"** beside **General** | ✅ LOCKED | 2026-09-09 |
| D2 | The Subtitles tab carries an **OpenSubtitles.com API key field** | ✅ LOCKED | 2026-09-09 |
| D3 | The Subtitles tab carries an **Auto-download toggle, default ON** | ✅ LOCKED | 2026-09-09 |
| D4 | When a video has no usable subtitle, SALU auto-downloads the **best-match English** subtitle and stores it **alongside the media** | ✅ LOCKED | 2026-09-09 |
| D5 | The Subtitles tab carries a **Preferred language selector, default English** (D4's "English" becomes "the preferred language") | ✅ LOCKED | 2026-09-09 |
| D6 | v1 scope: **local video files only** — never audio, never channel/live mode, never remote streams | ✅ LOCKED | 2026-09-09 |
| D7 | "No usable subtitle" = **no embedded subtitle track AND no basename-matching sibling subtitle file** (`movie.srt` or `movie.<lang>.srt` in any supported extension — the exact set mpv autoloads, §3.4) | ✅ LOCKED | 2026-09-09 |
| D8 | Save rule: **named after the MOVIE, never the provider's filename — `<basename>.<lang>.<ext>` next to the video** (e.g. `movie.en.srt`); temp-dir fallback when the folder is not writable | ✅ LOCKED | 2026-09-09 |
| D9 | **AUTO = moviehash hits only** (preferred → English); filename/query search is **manual-Fetch-only**, where a human picks from the Top-3 (tightened 2026-09-09: kills wrong-sub fetches for music videos / odd files) | ✅ LOCKED | 2026-09-09 |
| D10 | Engine is **silent background work**: never blocks playback, never modal; OSD speaks only for `cc not configured` / bad-key / quota-wall (each once per session) and manual-fetch results | ✅ LOCKED | 2026-09-09 |
| D11 | **Missing API key → OSD `cc not configured`** (owner's literal): toggle ON + bare video + no key = one transient deck card per session, then skip. Toggle OFF stays fully silent. | ✅ LOCKED | 2026-09-09 |
| D12 | Toggling auto-download **OFF stops future fetches only** — already-downloaded `.srt` files are never touched or deleted | ✅ LOCKED | 2026-09-09 |
| D13 | Auth: API key field now; **username + password fields** join it (Bearer token kept in memory only, never persisted) — because `/download` requires both key AND token (see §4) | ✅ LOCKED | 2026-09-09 |
| D14 | OSC slot left of fullscreen is reserved for the **Fetch button** (cycle tracks when subs exist · find-and-apply when they don't — owns the query search + Top-3 pick that auto never touches) — decided in concept, design not yet locked | 💡 PROPOSED | — |
| D15 | Subtitle position: **mpv decides, zero SALU code** — no `sub-pos`, no margins, no asserts, no forcing of any kind (owner: "no code no force on mpv") | ✅ LOCKED | 2026-09-09 |
| D16 | **Single renderer = mpv native** — media_kit's Flutter subtitle overlay goes `visible: false` (owner-delegated pick: only mpv shows ALL kinds — text, styled, bitmap) | ✅ LOCKED | 2026-09-09 |
| D17 | v1 **does not touch mpv track selection** — no `slang`, no manipulation of any default (owner-delegated pick: easiest to adapt, fewest surprises). Preferred language governs downloads only. | ✅ LOCKED | 2026-09-09 |

---

## 2. Settings → Subtitles tab (D1 · D2 · D3 · D5)

Follows the existing `SettingsDialog` anatomy exactly (same dialog, same tab
strip, same `_OptionTile` / section-header language — General tab is the template):

```
Settings
├── General   (existing — untouched)
└── Subtitles (new)
    ├── Section 1 · "OpenSubtitles" — API key field (+ login, D13)
    ├── Section 2 · "Language" — preferred-language selector (D5)
    └── Section 3 · "Auto-download" — ON/OFF toggle, default ON (D3)
```

### 2.1 Section 1 · OpenSubtitles account

- **API key field** (D2): single-line, obscured with show/hide eye, paste-friendly.
  - Persisted in `shared_preferences` (`subtitle_api_key`) the moment it changes.
  - Empty = signed-out state; the engine no-ops (D11), the field's helper reads
    `Needed for subtitle search & download.` — naming, not teaching (follow.md rule 1
    allows settings helper lines; the General tab already uses them).
  - Trailing clear (×) when non-empty. No "Test" button in v1 — the first real
    search is the test; a 401 surfaces once as an OSD card (see §4.3), not a dialog.
- **Username + password** (D13): two plain fields under the key, same styling.
  - Password is **never persisted** — login happens per app session, the Bearer
    token lives in memory only. Restart = re-login (one silent POST, no UI).
  - Why both: OpenSubtitles `/download` rejects key-only calls (401). Key-only
    gives search without download — a broken v1. (API facts in §4.)

### 2.2 Section 2 · Language (D5)

- A single selector (dropdown row in `_OptionTile` styling): label + current value
  + chevron; tapping opens the language list.
- **Default: English (`en`).** Persisted (`subtitle_language`, ISO 639-1 code).
- v1 list (curated, not the full 70 — covers the audience + the API's deep catalog):
  `English · Bangla · Hindi · Urdu · Arabic · Spanish · French · German ·
  Portuguese · Turkish · Indonesian`. "More later" — the list is one const array.
- Fallback chain (locked with D5): **preferred → English (when preferred ≠ English)
  → nothing.** Never auto-applies a third language the viewer didn't ask for.

### 2.3 Section 3 · Auto-download (D3 · D4)

- One switch row (same tile styling, switch at the right edge where the radio dot
  sits on General tiles): **Auto-download subtitles — ON by default.**
  - Helper: `Fetches the best match when a video has no subtitles.`
  - Persisted (`subtitle_autodownload`, default `true`).
  - OFF (D12): stops future fetches; downloaded files stay where they are.

---

## 3. Auto-download engine (D4 · D6–D12)

### 3.1 Trigger & guards

On every **local video load** (`_openQueueAt` landing on a `MediaUtils.isVideo`
path with no `://`), in the background, fetch **iff ALL hold**:

1. Toggle is ON (if OFF → fully silent stop, D12) **and** an API key is stored — if the key is missing while everything else would fetch, show the `cc not configured` OSD card (once per session) and stop (D11).
2. **Local video only** (D6): skip audio (lyrics own that — Phase 7), skip
   channel lists (live has no hash, no file, no writable folder), skip remote URLs.
3. **No usable subtitle already** (D7):
   - mpv reports zero subtitle tracks for the item, **and**
   - no `MediaUtils.isSubtitle` sibling shares the video's basename —
     `movie.srt` or `movie.<lang>.srt` next to `movie.mkv`, any supported
     extension (exactly the set mpv's `sub-auto=exact` would load, §3.4).
4. This file hasn't already failed/come up empty **this session** (in-memory
   `Set<String>` of canonical paths — a 12-episode binge never fires 12 doomed
   retries, and a quota wall (429/402) pauses the engine until next launch).
5. **Target check on arrival:** the download applies only if the fetched file's
   video is still the loaded one (`currentPath` match) — a fast zapper never gets
   episode 1's subs dropped onto episode 4. The file is still saved (it belongs to
   that video), just not applied.

Only the **actually opened item** is ever fetched — no queue prefetch (quota §3.5).

### 3.2 Search (D9) — auto takes hash hits only

1. Compute the **OpenSubtitles moviehash** of the local file (64-bit hash —
   first + last 64 KB; needs `dart:io` reads only, no new native deps).
2. `GET /subtitles?moviehash=<hash>&languages=<pref>` → if hits, take **[0]**
   (the API orders exact-hash hits by trust/downloads already).
3. Else repeat step 2 with `languages=en` (D5 fallback, skipped when pref is `en`).
4. Else: record "empty" for the session (guard 4) and stop silently.

There is deliberately NO filename/query step in the auto path (locked 2026-09-09):
a hash hit is exact-file and sync-correct by construction, while a query "best
hit" can be a wrong sub for music videos, home movies, trailers and misnamed
files. Query search belongs to the **manual Fetch button** (D14), where the
viewer picks from a Top-3 — a human judges relevance, automation never guesses.

**Why music videos are harmless (owner Q, 2026-09-09):** nobody uploads subs for
them, so the hash search comes back empty → silent stop, session-marked, zero
quota (search is unlimited; only downloads are budgeted). SALU needs no
music-vs-movie detection — the library answers "nothing exists" for free. What
v1 will NOT do: duration floors (murder shorts), filename keywords (fragile,
English-only), audio-ML detection (absurd cost). Reserved future: a per-folder
"never fetch here" learned from one user gesture — SALU learns instead of guessing.

### 3.3 Download, save, apply (D4 · D8)

1. `POST /download { file_id }` with `Api-Key` + `Authorization: Bearer` (D13)
   → follow the returned `link` (single-use, expires — download immediately).
2. Decompress if gzipped (the API serves `.gz` unless asked otherwise).
3. Save **next to the video** as `<basename>.<lang>.<ext>` (D8):
   `D:/Shows/ep1.mkv` + English → `D:/Shows/ep1.en.srt`. The lang tag keeps a
   later Bangla fetch from overwriting it and keeps the viewer's own `ep1.srt`
   sacred — SALU never overwrites an existing sibling (if the exact target name
   exists, the download is discarded; the sibling already satisfies D7 anyway).
   - Unwritable folder (read-only share, permissions) → `Directory.systemTemp/salu_subs/`
     with the same name; still applied to this session, just not permanent.
4. Apply via the existing `PlayerService.loadExternalSubtitle(path)` — no new
   engine path, mpv picks it up as the active track.
5. Success is **silent** (D10): the subs simply appear. The OSD deck stays quiet —
   auto-work that succeeded needs no announcement (resume memory precedent: silent
   `Media(start:)` + toast only where the viewer must choose).

### 3.4 Autoload — mpv does it, SALU's naming is designed for it (D7 · D8)

mpv autoloads external subtitles by default (`sub-auto=exact`: *"load the media
filename with subtitle file extension and possibly language suffixes"*)
[3](https://mpv.io/manual/master/) — so `Episode01.mkv` automatically picks up
`Episode01.srt`, `Episode01.en.srt`, `Episode01.es.srt`, … with zero SALU code
[1](https://salivity.github.io/mpv/article/can-mpv-auto-load-subtitles-with-the-same-name).
SALU deliberately keeps this default and names every download to match it.

**Why movie-title naming, never the provider's filename** (owner Q, 2026-09-09):

| | Movie-title naming (`movie.en.srt`) | Provider naming (`The.Matrix.1999.1080p-GROUP.srt`) |
|---|---|---|
| Next open | mpv autoloads it — subs just appear | mpv ignores it — video opens bare, SALU re-downloads (quota burn) |
| D7 sibling check | matches → fetch skipped | misses → fetch loop, duplicate subs pile up |
| Series folder | each episode pairs with its own subs | release names collide / can't be paired |
| Explorer | one movie ↔ its subs, obvious at a glance | clutter with unmatchable names |

**Edge cases (what counts, what doesn't):**

| Situation | mpv | SALU v1 | Viewer path |
|---|---|---|---|
| `movie.en.srt` next to `movie.mkv` | ✅ autoloads + selects | D7 sees it → no fetch | nothing to do — it just works |
| Random-named `.srt` in the same folder | ❌ ignored (exact needs the basename) | D7 misses it → fetches own copy | rename to match, **or drag-drop the `.srt` onto the window** (existing drop-to-load-subs) |
| `.srt` elsewhere on the drive (different folder) | ❌ no association possible | same — not detectable | drag-drop it onto the window |
| Series folder (`ep5.mkv` + only `ep1.srt`) | ❌ correctly ignored for ep5 | D7 per-video check → ep5 still fetches | correct behavior — folder-wide matching would be a bug (ep5 would starve on ep1's subs) |

Deliberately NOT widening mpv to `fuzzy`/`all`: in a series folder that loads the
wrong episode's subs onto the video — worse than loading none. Exact + our naming
is the correct pair. A v2 "adopt this loose subtitle (rename to match)" offer may
follow; v1 never renames the viewer's files silently.

### 3.5 Failures & quota (D10)

| Failure | Behavior |
|---|---|
| Missing key (toggle ON + bare video) | OSD card once per session: `cc not configured` (owner's literal; transient 1 s, deck rules). Engine skips. |
| 401 (bad key / bad login) | OSD card once per session: `Subtitles — check key` (mark + words;Deck rules apply). Engine pauses until settings change. |
| 429 / 402 (quota / rate) | OSD card once: `Subtitle limit reached`. Engine pauses until next launch. No retry loop. |
| No hits | Silent. Session-marked (guard 4). |
| Network down / timeout (10 s cap) | Silent. Session-marked. Playback never waits. |
| Hash of a growing file (recording) | N/A v1 — local finished files only; no special case. |

Quota context: free OpenSubtitles accounts get a small daily download budget
(~10/day, level-dependent); search is unlimited. The guards in §3.1 exist so one
series evening can't burn a week of quota.

---

## 4. API facts (verified 2026-09-09)

- Base: `https://api.opensubtitles.com/api/v1` [3](https://forum.opensubtitles.org/viewtopic.php?t=19154)
- **Search is unlimited; downloads are quota-based** per account level [1](https://mcpmarket.com/server/opensubtitles)
- Most endpoints need `Api-Key: <key>`; `/download` (and `/infos/user`, `/logout`)
  need **both** `Api-Key` **and** `Authorization: Bearer <token>` from `POST /login`
  (body: username + password) [3](https://forum.opensubtitles.org/viewtopic.php?t=19154)
- Search supports `query`, `languages`, `moviehash` (+ season/episode for series);
  hash gives exact-file matches [4](https://forum.opensubtitles.org/viewtopic.php?t=17146&start=105)
- The API key identifies the *app/developer*; the download quota belongs to the
  *user account* — apps like Bazarr ship their own key and ask only for the user's
  login [5](https://www.reddit.com/r/bazarr/comments/12d29qt/question_how_do_i_use_the_opensubtitlescom_api/)
  → SALU v1 inverts this (user pastes their own key, D2) to avoid shipping a shared
  secret; revisit if SALU ever gets its own developer key.

New dependency: `http: ^1.2.0` (search/download/login) — pure Dart, no native glue.

---

## 5. Rendering & position (D15–D17)

**Owner Q (2026-09-09):** subs appear in the bottom black bar — is that mpv's
automatic default? And can mpv be forced to keep them there?

**Finding: yes, it is the default — keep it.** mpv's `sub-use-margins` defaults
to `yes`: *"enables placing toptitles and subtitles in black borders when they
are available, if the subtitles are in a plain text format (or ASS if
--sub-ass-override is set high enough)"*
[1](https://www.reddit.com/r/mpv/comments/1mvbda1/subs_dont_get_out_of_the_video_frame_in_fullscreen/).
So every SRT/VTT rides into the letterbox automatically, with zero SALU code.
Two built-in limits (D15 accepts both — they are correct behavior, not bugs):

| Subtitle kind | Where it lands | Why |
|---|---|---|
| Plain text (SRT/VTT — everything SALU downloads) | ✅ bottom black bar when bars exist, else video bottom | `sub-use-margins=yes` (default) |
| Styled (ASS/SSA authored files) | follows the file's own margins/positions | fansub placement is deliberate (signs, toptitles) — forcing it into the bars would break rendering; `sub-ass-override` stays at mpv's default `scale` [3](https://mpv.io/manual/master/) |
| Bitmap (PGS/VOB/DVB) | baked into the video frame | image subs cannot be repositioned, full stop |

D15 (locked — owner: "no code no force on mpv"): mpv decides, zero SALU code —
not even an init-time assert. If bars exist the subs sit in them; a 16:9 video
in fullscreen has no
bars and bottom-of-video is the right fallback. Phase 4's planned position
slider stays a future panel control — the default never needs it.

**Two renderers are currently ON — D16 (locked) picks mpv native.** SALU's canvas today runs
mpv native rendering (subs drawn into the frames) AND media_kit's Flutter
`SubtitleView` overlay (`visible` defaults to `true`, bottom-anchored with
24 px padding — the same black bar). The overlay is plaintext-only: ASS styling
is stripped and bitmap subs render **nothing** (images have no `sub-text`) —
a Blu-ray rip would play with silently missing subs. D16 (locked, owner-delegated): **mpv native is the
one renderer; the overlay goes `visible: false`.** SALU typography is not lost —
plain-text styling moves to mpv (`sub-font="Segoe UI Variable"`,
`sub-font-size`, `sub-color`, `sub-border-size`, `sub-shadow-offset`) in the
styling pass; the current `subtitleViewConfiguration` style block retires with
the overlay. Verify on a Windows build: SRT video → one rendering, in the bar
(no doubling); PGS `.mkv` → subs visible (the D16 proof).

**D17 (locked, owner-delegated): v1 does not touch mpv track selection — no
`slang`, no manipulation of any mpv default.** Whatever mpv would auto-pick
(default/forced flags, audio-match, OS language) stands untouched: least code,
fewest surprises, easiest to adapt later. The preferred language governs what
SALU *downloads* (§3.2) — that is SALU's own choice, not an mpv override. If
viewers ever report the embedded pick mismatching their language, `slang` is the
reserved answer — not before.

---

## 6. Files to touch (when implementation starts)

| # | File | Change |
|---|---|---|
| 1 | `pubspec.yaml` | add `http` |
| 2 | `lib/core/settings_service.dart` | `subtitleApiKey` (String), `subtitleLanguage` (String `en` default), `subtitleAutoDownload` (bool, default `true`) + setters + load() |
| 3 | `lib/ui/widgets/settings_dialog.dart` | `_SettingsTab.subtitle`, `Subtitles` tab button, `_SubtitlesTab` (3 sections per §2) |
| 4 | `lib/core/subtitle_service.dart` (new) | hash + search + download + save + session guards (§3); owns the Bearer token in memory |
| 5 | `lib/core/player_service.dart` | hook §3.1 trigger after playlist-lands-on-video; reuse `loadExternalSubtitle` for apply |
| 6 | `lib/ui/osd/osd_controller.dart` + `osd_deck.dart` | new cards (`cc not configured`, `check key`, `limit reached` — §3.5) — only if new card types are needed |
| 7 | `lib/ui/screens/video_screen.dart` | `SubtitleViewConfiguration(visible: false)` — mpv native becomes the one renderer (D16); the style block retires with the overlay |

Verification (on a Windows build): key empty + ON → plays, zero network · key set,
video with embedded subs → zero network · video with `movie.srt` sibling → zero
network · bare `movie.mkv` → `movie.en.srt` appears beside it, subs render, no OSD
· close + reopen `movie.mkv` → subs autoload with zero network (mpv exact match)
· zap mid-download → file saved, nothing applied to the new video · quota 429 →
one OSD card, engine quiet till relaunch · toggle OFF → zero network, files kept ·
preferred `bn` with no Bangla hit → English fetched; neither → silence ·
random-named `.srt` beside video → SALU fetches its own copy (documented v1) ·
`ep5.mkv` with only `ep1.srt` in folder → ep5 still fetches (no folder-wide false hit) ·
SRT video → ONE rendering in the black bar (no doubling after D16) · PGS `.mkv`
→ subs visible (the D16 proof) · 16:9 fullscreen → subs at video bottom ·
embedded tracks → mpv default selection untouched (D17) · ASS
fansub → authored positions intact (signs not dragged into the bars) ·
bare video + ON + no key → one `cc not configured` card per session (D11) ·
music video / home video (hash miss) → silence, zero quota, session-marked (D9) ·
rare file with query-only match → NO auto-download, manual Fetch only (D9).