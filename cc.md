# SALU — cc.md (Subtitle decisions & implementation contract)

> **Purpose:** The single decision log for everything subtitle-related in SALU.
> Every subtitle decision the owner locks in chat lands here first, then in code.
> `follow.md` (hard rules) and `outline_transport_osd_resume.md` (transport/OSD)
> still bind everything below — this file only adds subtitle rules.
>
> **Status:** DECISIONS LOCKED D1–D17 (D1–D12, D15–D17 owner 2026-09-09 ·
> D14 design locked owner 2026-09-10 · **D13 AMENDED owner 2026-09-13** —
> the password is now persisted scrambled, see the third runtime finding
> below) · **v1 IMPLEMENTED** (all 12 files of
> §7 in place). Recheck 2026-09-10: D1–D17 + §2/§3/§6 verified complete;
> six review fixes applied (missing media_kit import — was a compile
> error · /login now sends its required Api-Key header · D7 counts bitmap
> sub tracks too · D7 track report now waits for a settled quiet window
> on zaps · §6.5 already-saved check covers the temp fallback · §2.3
> helper copy restored to the locked words). The owner's first
> `flutter analyze` (15 issues) is now fixed to zero: the two
> observeProperty closures (media_kit wants `Future<void> Function(String)`
> callbacks) · `const GZipCodec()` (not a const constructor) · the Search
> window's Save assignment (nullable + unused) · import order ·
> deprecated Matrix4 translate/scale → ByDouble · two never-passed
> params (`_PartRows` key, `_PlainField` helper) · one needless
> nullable. The §7 Windows-build verification pass is still owed — no
> runtime test has been done yet.
>
> **First runtime finding (2026-09-13) — "subtitle is not showing", ROOT
> CAUSE + FIX:** media_kit ships with **mpv's own subtitle rendering OFF**
> unless the player is created with `libass: true` — its default is
> `false`, documented as *"By default, subtitles rendering is Flutter
> Widget based"*. D16 switched the Flutter overlay off (`visible: false`,
> §7 file 7) but nothing ever switched mpv's renderer on, so the canvas
> was left with **zero subtitle renderers**: no embedded, autoloaded,
> dropped or downloaded subtitle could ever be drawn. Fixed with the one
> missing flag in `player_service.dart` (`PlayerConfiguration(libass:
> true)`). D16 now holds as designed: mpv native is the one renderer, the
> Flutter overlay stays off (both on = doubled subtitles), and the
> typography pass belongs to mpv (`sub-font`, `sub-font-size`,
> `sub-color`, `sub-border-size`, `sub-shadow-offset` — §5). The §7
> Windows-build verification pass is still owed.
>
> **Second runtime finding (2026-09-13) — "search works, Save does
> nothing" + the name box:** (a) Save/Save & Load failed in TOTAL
> silence whenever there was no stored login — `/download` needs a
> Bearer token only `/login` can mint (§4), and D13 keeps the password
> in memory, so every app restart silently broke Save until Settings was
> refilled. The manual taps now speak (`Subtitles — sign in` /
> `Subtitles — download failed`) while AUTO keeps D10's silence.
> (b) The Search window's name box was pre-filled with a "cleaned"
> title and lost the real release name — it now shows the file's own
> full name, untouched (§6.5, owner 2026-09-13).
>
> **Third runtime finding (2026-09-13) — "the password is gone every new
> session, and download still doesn't work with all three filled", ROOT
> CAUSE + FIX (D13 AMENDED, owner-approved 2026-09-13).** The owner's two
> symptoms are one cause with a second bug hiding behind it:
>
> 1. **The password was never stored — on purpose.** D13 kept it in RAM
>    (`SubtitleService.sessionPassword`), while the key and the username
>    were persisted (§2.1). Restart = signed out. That is not a defect, it
>    is the locked rule working as written — but its consequence is that
>    `/download` (key **and** Bearer, §4) is dead from the first frame of
>    every session, while search (key only) keeps working. Hence "search
>    fine, download broken".
> 2. **Typing the password afterwards changed nothing for the video on
>    screen.** §3.1's AUTO trigger fires exactly once, at the landing —
>    which is always *before* the viewer can reach Settings. The refusal
>    (`notSignedIn`) is silent and unmarked by design (D10), and the
>    credential listener only cleared `_authPaused`; **nothing ever
>    re-asked the question**. So the loaded video never fetched, and with
>    the deck quiet the owner saw exactly what they reported: *nothing at
>    all*. Recovery required closing and reopening the file.
> 3. **Every failure looked like every other.** `subtitle_service.dart`
>    had zero logging, so all twelve refusal branches were
>    indistinguishable; and a 401 from `/login` (username/password
>    refused) showed **`Subtitles — check key`**, naming the one field
>    that was fine.
>
> **Fix.** (a) **D13 amended**: the password IS persisted, scrambled —
> `SettingsService.subtitlePassword` + `setSubtitlePassword`, stored as
> `base64(nonce ‖ xor-keystream)` (`SubtitleScramble`, `shared_preferences`
> only, no new dependency per follow.md §7). **Obfuscation, not
> encryption** — the salt is in the source tree, and that limit is stated
> in code and here so nobody mistakes it for protection. The Bearer TOKEN
> is still memory-only, so a restart is still one silent `/login`.
> (b) `_retryCurrent()` — a credential edit now re-answers the video that
> is already loaded, debounced 1.5 s (one attempt per typing burst, and
> two logins never inside `/login`'s 1/s rate limit), silent per D10 so a
> half-typed password can't spend the session's card, giving the file its
> `_failedThisSession` try back, and dropping the now-stale `_token`.
> (c) The deck gained **`Subtitles — check login`** for the `/login` 401;
> `check key` stays for the API-key half (§3.5). (d) `[SALU/subs]` console
> logging on every branch — refusal reason, HTTP status **and the server's
> own body** — so a silent UI is never a silent log again. (e) `/download`
> no longer writes junk under the D8 name: an empty body or an HTML page
> behind a 200 is refused, because a broken `movie.en.srt` would then be
> treated as the bought subtitle FOREVER by the already-saved check.
> New: `test/subtitle_scramble_test.dart`. The §7 Windows-build
> verification pass is still owed.

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
| D13 | Auth: API key field now; **username + password fields** join it (Bearer token kept in memory only, never persisted) — because `/download` requires both key AND token (see §4). **AMENDED owner 2026-09-13:** the password IS persisted, scrambled (`SubtitleScramble` — obfuscation, not encryption); the Bearer token stays memory-only. Reason: a RAM-only password left `/download` dead after every restart, and §3.1's one-shot AUTO trigger always fired before it could be retyped — see the third runtime finding above | ✅ AMENDED | 2026-09-13 |
| D14 | OSC slot left of fullscreen carries the **Fetch button**: one tap opens the slide-down **track panel** — audio tracks · embedded subs (Off pinned on top) · local subs, live-mirroring mpv — plus **Load** (file explorer) and **Search** (query window: Top-3 in the preferred language + all-language matches, rows are subtitle files, human picks → Save / Save & Load). Owns the query search + Top-3 pick that auto never touches. The original cycle-tracks concept is retired (design: §6) | ✅ LOCKED | 2026-09-10 |
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
    search is the test; a 401 surfaces once as an OSD card (see §3.5), not a
    dialog.
- **Username + password** (D13, amended 2026-09-13): two plain fields under the
  key, same styling.
  - Password IS persisted (`subtitle_password`), **scrambled** — `base64(nonce ‖
    xor-keystream)` via `SubtitleScramble`, stored the moment the field changes
    like every other SALU setting. **Obfuscation, NOT encryption:** the salt is a
    constant in the source tree, so it keeps the password out of plain sight in
    `%APPDATA%` and nothing more — stated in the code so nobody later reads it as
    protection. Clearing the field removes the stored value (signs SALU out).
    The field's helper names both facts: `Remembered between sessions — stored
    scrambled.`
  - The **Bearer token still lives in memory only** and is dropped whenever any
    credential changes. Restart = one silent `/login`, no UI.
  - The original "never persisted" rule is what broke downloads: `/download` was
    dead from the first frame of every session while search (key-only) worked,
    and §3.1's one-shot AUTO trigger always fired before the password could be
    retyped. `_retryCurrent()` covers the mid-session case — a credential edit
    re-answers the video that is already loaded (debounced 1.5 s, silent per D10).
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
viewer picks from a Top-3 — a human judges relevance, automation never
guesses. The button's full design is §6.

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
| 401 from `/subtitles` or `/download` (bad **API key** / dead token) | OSD card once per session: `Subtitles — check key` (mark + words; deck rules apply). Engine pauses until settings change. |
| 401 from `/login` (bad **username/password**) | OSD card once per session: `Subtitles — check login` (added owner 2026-09-13 — the deck used to say `check key` for this too, naming the one field that was fine). Engine pauses until settings change. |
| 429 / 402 / 403 on `/download` (quota / rate) | OSD card once: `Subtitle limit reached`. Engine pauses until next launch. No retry loop. |
| No login (username or password empty) | AUTO: silent and **not** session-marked — signing in mid-session retries it (§3.1b). Manual Save: `Subtitles — sign in`, every tap. |
| 200 with junk behind it (empty body / HTML page on the download link) | Refused, nothing written (owner 2026-09-13). A broken D8 file would be treated as the bought subtitle forever by the already-saved check. |
| No hits | Silent. Session-marked (guard 4). |
| Network down / timeout (10 s cap) | Silent. Session-marked. Playback never waits. |
| Hash of a growing file (recording) | N/A v1 — local finished files only; no special case. |

**§3.1b — a credential edit re-answers the loaded video (owner 2026-09-13).**
§3.1's trigger fires once, at the landing. If the credentials were missing or
wrong at that moment, the fetch was refused and nothing would ever ask again for
that video — so editing any credential field now retries it (`_retryCurrent`):
debounced 1.5 s of quiet (one attempt per typing burst; two logins never inside
`/login`'s 1/s rate limit), gated by the same guards as a landing (D12's toggle,
the quota wall, D7, the in-flight lock), given the file's `_failedThisSession`
try back, and **silent** — it answers a keystroke, not a viewer request, so it
never spends a once-per-session card (the flag is checked before the shown-flag
is set: deferred, not consumed). The next deliberate act still speaks.

**The console is never silent (owner 2026-09-13).** D10 governs the DECK, not
the log: every branch above also prints one `[SALU/subs]` line — the refusal
reason, the HTTP status, and the server's own body (trimmed to 240 chars). The
password itself is never logged; the username is (it already sits in prefs
unscrambled, and naming it catches the opensubtitles.**org**-vs-.**com** account
mix-up in one glance).

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

## 6. The Fetch button · track panel + search window (D14 · locked 2026-09-10)

The OSC slot left of fullscreen (reserved by D14's concept) now has a real
design. The original "cycle tracks when subs exist" idea is **retired**:
cycling is blind — a panel shows the viewer what they are switching to.
This section is the locked contract for the button, its slide-down panel,
and the search window; everything above (auto engine, rendering, D15–D17)
stands untouched.

> **Design reference:** an interactive HTML mock of this exact design lives
> at `design/d14-fetch-preview/` (open `index.html` — review artifact only,
> not app code; the README maps every behavior to its subsection here).

### 6.1 The button

- Lives in the control row's right zone, immediately left of fullscreen
  (`controller_panel.dart`).
- **Local video files only** (D6 scope): for audio (lyrics own audio,
  Phase 7), channel lists and remote URLs the mark is **greyed out and
  inert — it never vanishes** (owner revision, 2026-09-10: greyed beats
  hidden — the button keeps its slot in the row, the viewer always knows
  where it lives; a vanished control teaches nothing).
- One tap opens the track panel; the button never toggles anything directly.
- Custom monochrome SALU mark (rule 6), drawn in the family's stroke language
  — a caption-family mark, visually distinct from the channel line's speech
  bubble (= Language).

### 6.2 The panel — slides down, floats, mirrors

- Slides down from the control row, anchored at the button: fade + slight
  scale (0.96 → 1.0), ~130–220 ms ease-out cubic, growing from its anchor
  (rule 3).
- Floats OVER the video — never pushes, resizes or reflows the container
  (rule 5).
- Esc closes. Click-outside closes. Opening it closes any other open popup
  (rule 3).
- **Stays open across taps** (owner, 2026-09-10): the viewer flips tracks
  and compares; only Esc, click-outside, or a media change closes it.
- **Live mirror** (owner, 2026-09-10): the panel listens to mpv's track
  state and re-marks the active rows on every change — from its own taps,
  from mpv's defaults, from anything. Rows never go stale. mpv is the single
  source of truth; the panel is only a view of it. This answers "items must
  refresh with the open track" — the refresh is continuous, not one-shot.
- If the queue moves to another item while the panel is open, the panel
  closes itself — a stale list for a new file is worse than one extra tap.

### 6.3 The three parts

Each part is a fixed-height list — **5 visible rows** — with its own inner
scroll when longer ("autoscroll", owner 2026-09-10): the panel keeps a
stable size even for a file with 8 audio tracks and 10 subs. One row per
track, proper language names, the active row marked, tap = switch.

1. **Audio** — every embedded audio track. mpv reports language *codes*
   (`en`, `jpn`, `hin`); SALU translates to real names (English, Japanese,
   Hindi) via one code→name table. Untagged tracks fall back to their mpv
   title, else `Track 1 / 2 / 3`. Default mark = the track mpv is playing
   right now (mirror, never a forced default).
2. **Embedded subtitles** — every embedded subtitle track, with an **Off
   row pinned at the top** (owner, 2026-09-10: the viewer must always be
   able to hide subtitles over the video). The mark mirrors mpv's live sub
   state — if mpv auto-picked a track (D17 allows exactly this), that row
   is marked; if nothing is active, Off is marked. Off governs ALL
   subtitles (embedded + local): tapping it = no sub track.
3. **Local subtitles** — external subs loaded with the media (mpv's
   `external` tracks): exact-name siblings mpv autoloaded (§3.4 — including
   the auto-engine's downloads, D8's naming) plus anything added via the
   Load icon or drag-drop. Selectable like any embedded track. A
   random-named `.srt` mpv did not autoload is correctly absent
   (documented v1, §3.4 edge table) — the Load icon covers that case.

Parts 2 and 3 are ONE selection domain (mpv's single sub-track id) shown as
two groups: marking a row in either part moves the mark across both. Off
sits atop the first subtitle part that has rows — part 2 when embedded
tracks exist, else part 3. A part with zero tracks collapses entirely, no
empty-state text (rule 1); the panel with all parts empty is still the
Load + Search marks — that is the find-and-apply case.

### 6.4 Load (file explorer)

- Opens the system file picker filtered to subtitle extensions.
- Loads through the existing `PlayerService.loadExternalSubtitle` — no new
  engine path, playback never stops, part 3 refreshes instantly (live
  mirror, §6.2).
- Session-only, accepted for v1: mpv will not re-find the file on the next
  open unless it is named to match (§3.4). A future "adopt this file"
  (copy + rename beside the movie) is reserved; v1 never renames the
  viewer's files.

### 6.5 Search (the query window)

A centered glass modal with dimmed barrier — a focus task, open → act →
gone (rule 8), deliberately distinct from the live slide-out panel.

- **Top: the movie name — an editable field**, pre-filled with the
  video's **FULL file name exactly as it sits on disk — extension
  included, nothing cleaned** (owner revision **2026-09-13**, replaces the
  2026-09-10 "extension stripped, obvious release junk cleaned" wording).
  Reason: the cleaner threw away the release name — the thing
  OpenSubtitles indexes best — together with the junk, and a file whose
  title began with a tag on the list lost its title entirely. Editable
  because D9's whole philosophy is *a human judges*: the box hands over
  the true name and the human edits it, never SALU guessing.
- **Below the field: four marks — Search · Save · Save & Load · Close**
  (custom marks + hover-delay tooltips, rule 6; Save / Save & Load dim
  until a row is picked).
- **Search** runs the filename/query search — the one AUTO never touches
  (§3.2). One query; results group locally:
  - **Group A · best 3 matches in the Settings preferred language**
    (owner, 2026-09-10) — may be fewer than 3, may be empty.
  - **Group B · all matches, all languages — including the preferred
    language** (owner, 2026-09-10), each row showing movie title +
    language. Scrollable.
  - The AUTO fallback chain (preferred → English, D5) is AUTO-only. Manual
    search never substitutes a language the viewer did not ask for —
    Group B already shows everything; the human picks.
- **Rows are subtitle files** (owner, 2026-09-10): movie title + language
  per row — one step, pick a row, no movie-then-subs drill-down.
- **Save** = download + write next to the video as `<basename>.<lang>.<ext>`
  (D8 naming, never overwrite an existing file) → window closes, one
  transient OSD card `Saved · <filename>` (D10's manual-fetch-results
  clause — the window closing alone would read as "nothing happened";
  subs silently appear on the next open via mpv's exact autoload).
- **Save & Load** = the same download + apply now via
  `loadExternalSubtitle` → window closes, subs on screen.
- **Already-saved target** (the D8 filename already exists from an earlier
  save): no download is spent — Save shows `Already saved · <filename>`
  (same card, honest words), Save & Load applies the existing local copy.
  Quota is never burned twice for one file.
- **Close** = dismiss, nothing happens.
- **A Save that cannot run SPEAKS** (owner, **2026-09-13**): a tap is a
  deliberate human act, so it is never answered with silence, and it
  answers on **every** tap — the once-per-session flags stay the AUTO
  engine's business (§3.5), they never mute a human who asked twice.
  Two new cards join the deck's subtitle family, both 1 s transient:
  - `Subtitles — sign in` — no stored username/password, so `/download`
    has no Bearer token (§4: search is key-only, download is key +
    login). **Rare since D13's amendment (owner 2026-09-13)** — the
    password is persisted scrambled, so this is now a first run or a
    field the viewer cleared, not every restart.
  - `Subtitles — download failed` — the download or the write died
    (including a 200 carrying junk: an empty body or an HTML page is
    refused rather than written under the D8 name).
  - An engine already paused by a wall names the wall again on a manual
    tap (`Subtitles — check key` / `Subtitles — check login` /
    `Subtitle limit reached`), because the viewer is asking again now.
    `check login` (added owner 2026-09-13) is the `/login` 401 — the
    username/password half; `check key` stays the API-key half (§3.5).
  - AUTO stays silent for all of the above (D10 holds): a missing login
    is not the FILE's fault, so it is not session-marked — signing in
    mid-session retries it at once (§3.1b).
- **Not configured**: the window still opens; tapping Search shows the
  one-per-session `cc not configured` OSD card (D11) — no new dialog.
  (A manual **Save** with no key shows the same card directly, every
  tap.) Bad key (401) and quota walls surface through their own cards
  (§3.5 deck rules).

### 6.6 What D14 does NOT touch

- **D17 stands:** the panel never forces a default on load — it acts only
  on explicit taps; mpv's autoloaded pick stands until the viewer taps.
- **D15 / D16 stand:** rendering and position stay mpv-native, zero SALU
  code.
- **No OSD for track switches:** the panel's own row marking is the
  feedback; the deck stays quiet (D10 — the panel IS the visible UI).
- **The auto engine is untouched:** §3 keeps working exactly as locked;
  this button adds a manual path, it changes no automatic one.

---

## 7. Files to touch (when implementation starts)

| # | File | Change |
|---|---|---|
| 1 | `pubspec.yaml` | add `http` |
| 2 | `lib/core/settings_service.dart` | `subtitleApiKey` (String), `subtitleUsername` (String), `subtitlePassword` (String, stored scrambled), `subtitleLanguage` (String `en` default), `subtitleAutoDownload` (bool, default `true`) + setters + load(); `SubtitleScramble` (D13 amended 2026-09-13) |
| 3 | `lib/ui/widgets/settings_dialog.dart` | `_SettingsTab.subtitle`, `Subtitles` tab button, `_SubtitlesTab` (3 sections per §2) |
| 4 | `lib/core/subtitle_service.dart` (new) | hash + search + download + save + session guards (§3); owns the Bearer token in memory; gains the manual query-search + save-without-apply path (§6.5), the credential-edit retry (§3.1b) and `[SALU/subs]` console logging on every branch (§3.5) |
| 5 | `lib/core/player_service.dart` | hook §3.1 trigger after playlist-lands-on-video; reuse `loadExternalSubtitle` for apply; expose the track lists + live selection notifier and the selectors (audio track, sub track by id, sub off) — the panel's single source of truth (§6.2) |
| 6 | `lib/ui/osd/osd_controller.dart` + `osd_deck.dart` | new cards (`cc not configured`, `check key`, `check login`, `limit reached` — §3.5; `sign in`, `download failed`, `saved` — §6.5) — only if new card types are needed |
| 7 | `lib/ui/screens/video_screen.dart` | `SubtitleViewConfiguration(visible: false)` — mpv native becomes the one renderer (D16); the style block retires with the overlay |
| 8 | `lib/ui/osc/controller_panel.dart` | Fetch button in the right zone, immediately left of fullscreen (§6.1) |
| 9 | `lib/core/language_names.dart` (new) | ISO 639 code → display name table (`en` → English …), shared by the panel rows and the search-window rows |
| 10 | `lib/ui/osc/fetch_control.dart` (new) | the Fetch button — mark, tap → panel, greyed-out-inert rule when not a local video (§6.1) |
| 11 | `lib/ui/panels/track_panel.dart` (new) | the slide-down panel — three live-mirror parts, Off row, per-part 5-row scroll, Load + Search marks (§6.2–6.4) |
| 12 | `lib/ui/widgets/subtitle_search_dialog.dart` (new) | the query window — editable name field, four marks, Group A/B results, Save / Save & Load (§6.5) |

**Verification added by the third runtime finding (owner 2026-09-13):**
restart with all three fields filled → the password comes back (scrambled in
prefs, never as text) and the FIRST bare video of the new session downloads with
zero Settings visits · clear the password, open a bare video, then type it →
subs arrive within ~2 s **without reopening the video** (§3.1b) · wrong password
→ `Subtitles — check login`, not `check key` · typing a password slowly → at most
ONE login attempt, and no card while typing (the retry is silent) · every refusal
prints one `[SALU/subs]` line naming the branch, the HTTP status and the server's
body · a download link returning an empty body or an HTML page → nothing written,
`Subtitles — download failed` · `test/subtitle_scramble_test.dart` passes.

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
rare file with query-only match → NO auto-download, manual Fetch only (D9) ·
**D14 panel:** local video → button live; audio / channel / URL → button
greyed out and inert, never vanished · open panel → parts mirror mpv's live picks (audio + sub), including
an mpv-auto-selected sub shown marked (D17) · Off at the top of the subtitle
list → tap → subs gone from the video · file with >5 tracks per part → part
scrolls internally, panel size stable · Load a `.srt` → part 3 gains the row,
playback never stops · panel open + Next track → panel closes itself ·
track switch from the panel → NO OSD card (the row mark is the feedback) ·
**D14 search window:** name field editable + pre-cleaned · Search → Group A =
best 3 in the preferred language only, Group B = all languages incl.
preferred · pick a row → Save / Save & Load light up · Save →
`<basename>.<lang>.srt` beside the video, window gone, subs autoload next
open with zero network · Save & Load → subs on screen now · Save & Load the
same target twice → ONE download, second applies the local copy · no key →
Search tap → one `cc not configured` card, no dialog.