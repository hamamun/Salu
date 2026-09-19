# SALU — Built-in Web Browser (WebView2)

**Status:** ✅ Implemented — built against every lock in this file;
the on-device checklist below still runs on a Windows build (first code
touch requires `flutter pub get` — it pulls `webview_windows` and
regenerates the Windows plugin glue; the app is Windows-only from here on
for Web mode, and every other platform keeps Player mode).

Where the code lives: `lib/core/web/` (address rules, suggestions, tabs,
favourites, history, data control, auto-clear policy),
`lib/core/browser_service.dart` (the Player · Web mode itself),
`lib/ui/screens/browser_screen.dart` + `lib/ui/widgets/browser_*.dart`
(the strip, bar, hub, sheet, dialog).

Implementation notes, lock by lock:
- **Tabs** — capped (`+` goes quiet past the cap), inactive tabs lazy: no
  engine until first activation, `suspend()` while offstage;
  × on the tab's right, `+` right of the last tab, middle/right-click also
  closes. Last tab closed → Web mode stays, strip keeps its `+`, the
  content is the plain-Flutter start page (logo + “SALU Web Browser”).
- **Address bar** — typing only ever fills the dropdown (debounced),
  Enter/row-pick navigates; Google suggest + history + favourites merged,
  own data first; the Settings “Search suggestions” toggle mutes the
  Google leg only; Google is the only search engine SALU ever navigates to.
- **Favourite star** — the URL bar's left-corner two-state mark: outline
  opens the save flow, filled opens the same sheet as an edit (Rename ·
  Change folder · Remove), removals answer with the standard 5 s Undo.
  Hub = ♥ left of the tab row, slide-down list with search, folder groups,
  edit + delete. Store ≤ 15 Web Bookmarks, `shared_preferences`, instant.
- **Clear** — accessible via the standard browser (⋮) menu ("Clear browsing
  data…"); the dialog is styled in SALU's clean dark palette with a dedicated
  header, Segoe typography, and live data footprint badges
  (item counts / KB / MB) for each category like Edge and Chrome; every mark
  is SALU-drawn and monochrome (the follow.md recipe — nothing is ever boxed
  behind an icon);
  history/cookies/cache/own-store deletes apply instantly, and everything a
  live WebView2 profile locks is purged at the next startup (the only moment
  a folder delete is guaranteed). Footprint badges measure only SALU's own
  profile stores — cookie jars · Local/Session Storage · IndexedDB · Service
  Workers · HTTP/code/GPU/shader caches — discovered by their well-known
  names wherever the runtime parked them (never whole-folder guesswork, so
  runtime internals never count as browsing data); cache files the running
  engine does not lock are deleted immediately mid-session, and once a purge
  is queued the locked categories report "None" + a queued-purge note instead
  of the stale pre-clean size. SALU's own data (resume, saved streams)
  lives in different stores and is never in scope. Auto-clear = Settings → Web
  (off default · 7/15/30 days · open/close/both; “on closing” = the due-date
  sweep + stores flush at the close guard, the locked-folder part running at
  next open).
- **Mode + window** — Player · Web switch top-left of the strip in both
  modes; Web draws no SALU media controls and pauses playback on entry;
  a mode switch never tears the browser down (2026-09-17, Mode keep-alive
  lock below — the page comes back exactly where it was, media paused);
  page fullscreen hides SALU's whole chrome for the web view and Esc
  (page-side listener + Flutter fallback) releases it, and a page still
  holding the screen releases the hand-off on the way to Player mode;
  pop-ups captured by the document-start shim into the badge + per-site
  rules (2026-09-17 cut — the lock below), permission prompts are one
  tidy card (camera/mic/location/notifications/clipboard/sensors),
  downloads go to the WebView2 default (Windows Downloads) and are
  tracked: engine reports → one shared log → the address bar's + the
  title bar's badge → the download shelf, where a landed media file
  plays inside SALU (2026-09-19 lock below).
- **Memory** — a mode switch keeps the browser alive (2026-09-17, Mode
  keep-alive lock below): leaving for Player mode Offstages the surface
  and parks every running page (media paused first, then the engine's
  Suspend — the same contract the off-stage tabs already use); coming
  back finds every tab on its exact page, media paused like the player.
  The `WebviewController` teardown (session cache cleared before dispose)
  runs only when the app CLOSES (key function 8, the close guard).
- `BrowserService.openInBrowser()` is the ready door for the Phase 6
  Library panel (key function 3/6) when that lands.
- Settings → Updates WebView2/yt-dlp detection stays Phase 4/5 scope —
  intentionally not part of this cut.
- PARKED: the floating mini-player in Web mode. OUT: drag & drop between
  player and browser.

**On-device checklist** (needs a Windows run): toggle in both modes ·
**mode keep-alive round trip** (Web → Player → Web: every page exactly
where it was, none reloaded · page media comes back PAUSED, not
auto-playing · a fullscreen page releases the hand-off · the player's
own pause state is untouched the whole way) ·
tab cap + laziness · suggestion merge (and the Settings toggle) ·
star ↔ sheet ↔ hub round-trip incl. Undo · clear dialog incl. next-startup
purge · auto-clear all three timings · fullscreen hand-off + Esc ·
pop-up capture (stub defeats gates · badge + held-back list · per-site
Allow/Block/visit · Settings default + exceptions) · ⋮ menu (zoom ladder
· desktop UA + restore · find incl. Esc/Enter/arrows · history groups +
delete + clear-all · downloads badge + shelf (start → ring → land → Play / Show in folder / Open folder · ⋮ door · title-bar badge in BOTH modes) · clear dialog · Edge door ·
Settings) · Ctrl+T/W/R/L/F + zoom keys · permission cards · resume memory
untouched by any of it.

**Source of truth:** `phase_6_details.md` (Phase 6: Web & Stream Manager), `salu_context.md`, `phase_4_details.md`, `phase_5_details.md`.

---

## 🎯 Goal

Give SALU a built-in web browser so users can browse streaming websites
directly inside the app — no external browser needed.

## 🔑 Key idea

SALU uses a Flutter package called **`webview_windows`**, which runs on
**Microsoft's built-in WebView2 engine**. WebView2 is the web view that's
already built into Windows 10/11 (backed by Edge/Chromium). SALU doesn't
ship its own browser engine — it *wraps* the one Windows already has.

---

## 🔓 Parked ideas (decided NOT in v1)

| Idea | Verdict | Why (plain) |
|------|---------|-------------|
| **Floating mini-player** (browse while a video plays in an always-on-top corner window) | **PARKED 2026-09-16** | Not feasible now: it needs a separate always-on-top window + shared mpv player (the pages themselves are texture-composited, so drawing over them is fine — it is the second window that is the problem). Flutter desktop has no stable multi-window support; the usual workaround (`desktop_multi_window`) is a separate engine with known media_kit blank-video issues. Revisit later. |
| Drag & drop between player and browser | **OUT** | Web mode is a WebView (embedded), not mpv — no local drag & drop. |

---

## 🔒 Locked decisions

| Date | Decision | Detail |
|------|----------|--------|
| 2026-09-16 | **Web/Player toggle location — LOCKED** | **Top-left of the title strip** (the fading top chrome bar), next to the SALU logo. Rendered as a small `Player · Web` mode switch. It stays in the same place in both modes, so it is the single, always-present way to jump between the video player and the web browser. |
| 2026-09-16 | **Tab bar — LOCKED** | Multi-tab bar below the title bar. New-tab **`+`** sits at the **right of the last tab** (icon based, like Chrome/Edge). Tabs have a **close (×) button in the same spot Chrome uses** (right side of each tab). Tabs are **capped** to protect RAM; inactive tabs are lazy-loaded. |
| 2026-09-16 | **Address bar — LOCKED** | Below the tab bar: a standard URL bar with Edge/Chrome-style behaviour. **(1) Typing (live suggestions):** as the user types, a dropdown slides down below the bar showing suggestions from three merged sources in one list — Google's public suggest endpoint (e.g. `suggestqueries.google.com/complete/search`, returns JSON) + the user's own **history** + **favourites**. Typing only shows the dropdown; nothing navigates. **(2) Pressing Enter:** the current tab **navigates to Google's results page for the query** (like `google.com/search?q=…`), the same as Chrome/Edge. **Google is the only (default) search engine.** Keystroke-to-Google is controlled by a Settings **"Search suggestions" toggle** (off = only history + favourites show). |
| 2026-09-16 | **Navigation buttons — LOCKED** | **Home · Back · Forward · Reload** (icons), outside and **left** of the URL bar. Home navigates the current website to its root page (for example, a YouTube video returns to YouTube home); a fresh tab remains on SALU Web's own start page. |
| 2026-09-16 | **Favourite star — LOCKED** | **Inside the URL bar, left corner.** **Two-state:** outline = not saved, filled = saved (chosen left, not right, so the user doesn't cross a big screen). Clicking either state **slides out the favourite panel**: outline → save flow; filled → edit flow (Rename / Change folder / Remove). |
| 2026-09-16 | **Favourites hub — LOCKED** | Icon button on the **left of the tab bar** opens a **slide-down list** of all favourites, with **edit / delete / grouping** and search. |
| 2026-09-16 | **Clear data — LOCKED** | Accessed via the **⋮ browser menu** ("Clear browsing data…") → dialog with **checkboxes and size metrics** (Chrome/Edge style): *Browsing history · Cookies & site data · Cached images & files · Downloads history*. Clearing never touches SALU's own data (resume history / saved streams). |
| 2026-09-16 | **Auto-clear — LOCKED** | Settings option, **Off by default**. Interval choices: **7 / 15 / 30 days**. Timing choice: **on player opening / on player closing / both**. ("Player" here = SALU the app; close-time clearing is the most reliable.) |
| 2026-09-16 | **Web view area — LOCKED** | The main WebView fills everything **below the URL bar**. |
| 2026-09-16 | **Empty state / last tab — LOCKED** | When the **last tab closes**, SALU stays in Web mode: the tab bar shows **only the `+`**, and the web view area shows a **start page with the SALU logo + "SALU Web Browser" text**. That start page is a plain Flutter widget (not a WebView), so it uses no WebView/RAM. |
| 2026-09-16 | **No SALU media controls — LOCKED** | Pure browser: no SALU play/pause/volume/transport. Sites (YouTube, Netflix, Prime, …) use their **own** player controls. **Fullscreen is handed to the web page** (like Edge) — the WebView takes the whole screen and HIDES SALU chin. |
| 2026-09-16 | **Downloads — LOCKED** | Standard browser behaviour: send the file to **Windows File Explorer** (user's Downloads folder) — like Edge/Chrome. |
| 2026-09-16 | **Popups & permissions — LOCKED** | Edge/Chrome-style: block popups by default + tidy prompts for site permissions (location, camera, notifications…). |
| 2026-09-17 | **Pop-up system: capture + badge + per-site — LOCKED** | Engine policy stays `deny` (nothing ever escapes to an OS window); a document-start shim reports every `window.open` / `target=_blank` to Dart over `webMessage` and returns a stub handle, so ad-gates pass with nothing rendered. Held-back pop-ups count into an address-bar badge (⧉) with per-URL Open; allowed sites open in a new foreground SALU tab (at the tab cap they park in the list instead — never a hijack). Per-site Allow/Block lives in the padlock panel (+ "just for this visit", session-only); the global default + exceptions list live in Settings → Web. |
| 2026-09-17 | **Standard browser menu (⋮) — LOCKED** | One ⋮ at the row's right edge (beside 🧹, which stays): New tab · Zoom −/%/+ (Chrome's ladder, per tab, % resets) · Desktop mode switch (per tab, Edge-on-Windows UA + reload) · Find in page… (own highlighter — the plugin exposes no Find API) · History (Today/Yesterday/Earlier, search, per-row ×, clear-all) · Downloads (a door to the download shelf — see the 2026-09-19 Downloads lock; the earlier note here that "no progress events reach this plugin" was WRONG, the engine reports every download and SALU now listens) · Clear browsing data… (the same dialog as 🧹) · Open in Edge (the `microsoft-edge:` escape door) · Settings. Keyboard: Ctrl+T/W/R/L/F and Ctrl +/−/0 while Flutter holds focus (a native-focused page eats keys first — no accelerator hook exists). |
| 2026-09-17 | **Page colours — LOCKED** | Pages render **light by default**, the way Edge shows them. Cause of the old mismatch: WebView2 answers `prefers-color-scheme` from the **Windows app mode** (its `PreferredColorScheme` profile control defaults to Auto = follow the OS; Edge answers from its own Appearance setting), so on a dark-mode PC a site with a dark theme (pixabay.com) went dark inside SALU while staying white in Edge. Fix: the engine's own supported control — `ICoreWebView2Profile::put_PreferredColorScheme` — reached through the vendored plugin's one addition (`third_party/webview_windows`, VENDOR_NOTES.md); the earlier `--blink-settings` command-line switch was undocumented, silently lost to the host's preference sync, and restart-bound — removed. Settings → Web → **Page colours**: Light (default) · Dark · Follow Windows; applies **immediately** — every live page re-themes in place (`WebDataControlService.applyPageScheme`), new tabs inherit at birth. SALU's own chrome stays dark regardless. |
| 2026-09-17 | **Mode keep-alive — LOCKED** | The Player/Web switch **hides the browser, it does not close it**. The web surface is born on the first Web entry and stays in the tree for the life of the process (the home screen Offstages it instead of unmounting it), so Web → Player → Web lands on the **exact same pages** — same tabs, URLs, scroll and state, nothing reloaded. Leaving Web, every running page's **own media pauses first** (no site may play unattended behind the player — the same courtesy SALU's player gets when Web opens), then its renderer **suspends** (the engine's Suspend/Resume — the same contract the off-stage tabs already use), and a page that owns the screen releases the fullscreen hand-off on the way out. Returning to Web, the active tab resumes and every page sits **paused**, like the player; resume is manual, on the site's own controls. RAM stays honest the whole time: hidden renderers are suspended, not idle-playing. Mini-bar swaps still tear the tree (mini.md §8 — a 32-px bar hosts no browser), and the app's **close** still runs key function 8 exactly as written. |
| 2026-09-19 | **Downloads: badge + shelf + Play — LOCKED** | The engine was always reporting its downloads (`add_DownloadStarting` → `add_BytesReceivedChanged` → `add_StateChanged` in the vendored plugin's `webview.cc`, reaching Dart as `WebviewController.onDownloadEvent` with url, **result path**, bytes and total); SALU simply never subscribed, which is why a download landed with no trace. Now: `WebTab._wire` listens and feeds **one shared log** (`lib/core/web/web_download_service.dart`, keyed on the engine's result path — the event carries no download id). A **badge** stands in **two** places — the address bar's right corner (Chrome's own slot, left of the ⋮) *and* the title bar's caption row, because the browser stays alive behind the mode switch, so a file can land while Player mode owns the window. It shows only while it has news: a hairline ring for what is travelling (determinate when the server gave a size, the tab strip's spinner when it did not), a count above one, and it **stays after the last byte** until the shelf is opened. Its tap opens the **download shelf** — a slide-down panel in the same family as the site panel and the held-back list, NOT a tab (Chrome and Edge open a flyout here too; the ⋮ menu's "Downloads" is a second door to it). Rows: file name · what has landed of what, from which host · the progress hairline; landed rows carry ▶ **Play** (media only), **Show in folder** (`explorer /select,` — Explorer lands ON the file) and ×; the footer is **Open Downloads folder**. **Play's rule (owner):** a queue already there → the file joins its end and Web mode keeps the screen; nothing queued → the file becomes the queue, Player mode takes the window and playback starts (a channel list is the one populated queue a local file never joins, so it takes the fresh-load branch). A one-flight guard makes a double tap land the file once. Landed rows persist (`web_downloads`, 200 cap, newest first); a traveller never does — the engine cannot resume it. "Downloads history" in the Clear dialog now empties this log **and** the files stay on the PC, which is what its own line always said. **Known gaps:** the plugin exposes no cancel/pause and drops `DOWNLOAD_STATE_INTERRUPTED` silently (`webview.cc`), so a traveller carries no × and a failed download can only be dismissed by hand — both need a vendor delta, parked. |

---

## 🗺️ Browser layout (top → bottom)

```
┌──────────────────────────────────────────────────────────┐
│  [ Player | Web ]  ··· title strip ···  ─ □ ✕            │
├──────────────────────────────────────────────────────────┤
│  ♥Fav  ▢ Tab  ▢ Tab  ▢ Tab  [ + ]                       │
├──────────────────────────────────────────────────────────┤
│  ⌂ ⇦ ⇨ ⟳   [ 🔒 ☆ URL + suggestions………… ⧉ ]      ↓ ⋮  │
├──────────────────────────────────────────────────────────┤
│                                                          │
│                    WebView (the page)                    │
│                                                          │
└──────────────────────────────────────────────────────────┘
```


## 🛠️ Key functions

| # | Function | Detail |
|---|----------|--------|
| 1 | **Built-in browser screen** | A new screen `lib/ui/screens/browser_screen.dart` replaces the main SALU canvas when a bookmark is opened — or when the Web/Player toggle is flipped to Web. |
| 2 | **WebView2 wrapper** | Renders pages through `webview_windows`, which bridges to the built-in Windows WebView2 engine. |
| 3 | **Open a bookmark** | Clicking a saved Web Bookmark switches SALU to the browser screen and loads that URL. |
| 4 | **Multi-tab bar** | A tab bar at the top, like a standard browser. Each bookmark can open in its own tab. |
| 5 | **Navigation buttons** | **Home · Back · Forward · Reload** (icons, left of the URL bar). "Close Browser" is replaced by the Player toggle in the title strip. See layout below. |
| 6 | **New tab on new bookmark** | Clicking a different bookmark while the browser is open spawns a **new tab** instead of overwriting the current page. |
| 7 | **No SALU media controls** | The SALU OSC (Play/Pause, Volume) is hidden in browser mode — streaming sites use their own player controls. |
| 8 | **Memory cleanup** | When the app **closes** (the close guard), destroy the WebView controllers, clear the session cache, and flush RAM so SALU stays lightweight. A Player/Web mode switch does NOT destroy anything (see **Mode keep-alive — LOCKED** in the locked decisions) — it parks the running pages instead, and the surface only dies with the app. |
| 9 | **Saved bookmarks** | Up to **15 Web Bookmarks** (plus 10 M3U streams) stored instantly with `shared_preferences`. |
| 10 | **WebView2 updates** | Settings → Updates can check for and update the WebView2 linker (`WebView2Loader.dll`) and `yt-dlp`. |

---

## 📌 Status notes

- **Phase 6 browser is ✅ Implemented (PR #81 → main).** All locks in this
  file are built: Player·Web toggle top-left in BOTH modes (fixed 2026-09-17),
  capped lazy tabs, omnibox with merged Google+history+favourites, two-state
  star + hub, Clear dialog (4 boxes), auto-clear schedule, start page,
  fullscreen hand-off + Esc, popup block + permission cards, memory cleanup.
- This file (`web.md`) holds the **locked** detailed browser design. It
  **supersedes** the simpler 4-button description in `phase_6_details.md`
  Step 4 (Home / Back / Forward / Close Browser) — the old plan's
  "Close Browser" is replaced by the Player/Web toggle.
- `lib/ui/screens/` now contains `browser_screen.dart`; `lib/ui/widgets/`
  holds `browser_tab_strip.dart`, `browser_address_bar.dart`,
  `browser_favourite_sheet.dart`, `browser_favourites_hub.dart`,
  `browser_site_panel.dart` (padlock panel + held-back list),
  `browser_menu.dart` (the ⋮ shelf), `browser_history_panel.dart`,
  `browser_find_bar.dart`, `browser_clear_dialog.dart`,
  `browser_views.dart`, `web_marks.dart`, `web_mode_toggle.dart`,
  `download_badge.dart` (the badge, one widget for both of its homes) and
  `browser_downloads_panel.dart` (the shelf);
  `lib/core/web/` holds `web_popup_service.dart` (per-site rules + visit
  memories; the global default is `SettingsService.webPopupDefault`),
  `web_download_service.dart` (the download log + badge counts +
  Explorer's two answers) and `web_find.dart` (the highlighter script +
  answer parsing).
- `follow.md` records that the web browser, bookmarks, and Stream Library
  panel were **postponed** to be designed separately (they are not mpv work).
  Browser part is done; Stream Library / M3U sidebar remains Phase 6 pending.
- Related pieces:
  - **Phase 4** — Settings → Updates button (manual WebView2 / yt-dlp update).
  - **Phase 5** — Auto-update function for the WebView2 `.dll` linker files.
  - **Phase 6** — Browser done; saved streams/bookmarks Library panel still
    pending (uses `BrowserService.openInBrowser()` as its entry point).
