# SALU — Built-in Web Browser (WebView2)

**Status:** ⏳ Not Started

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
| **Floating mini-player** (browse while a video plays in an always-on-top corner window) | **PARKED 2026-09-16** | Not feasible now: a WebView2 page is a native surface Flutter can't reliably draw above, and a separate always-on-top window needs a second window + shared mpv player. Flutter desktop has no stable multi-window support; the usual workaround (`desktop_multi_window`) is a separate engine with known media_kit blank-video issues. Revisit later. |
| Drag & drop between player and browser | **OUT** | Web mode is a WebView (embedded), not mpv — no local drag & drop. |

---

## 🔒 Locked decisions

| Date | Decision | Detail |
|------|----------|--------|
| 2026-09-16 | **Web/Player toggle location — LOCKED** | **Top-left of the title strip** (the fading top chrome bar), next to the SALU logo. Rendered as a small `Player · Web` mode switch. It stays in the same place in both modes, so it is the single, always-present way to jump between the video player and the web browser. |
| 2026-09-16 | **Tab bar — LOCKED** | Multi-tab bar below the title bar. New-tab **`+`** sits at the **right of the last tab** (icon based, like Chrome/Edge). Tabs have a **close (×) button in the same spot Chrome uses** (right side of each tab). Tabs are **capped** to protect RAM; inactive tabs are lazy-loaded. |
| 2026-09-16 | **Address bar — LOCKED** | Below the tab bar: a standard URL bar with Edge/Chrome-style behaviour. **(1) Typing (live suggestions):** as the user types, a dropdown slides down below the bar showing suggestions from three merged sources in one list — Google's public suggest endpoint (e.g. `suggestqueries.google.com/complete/search`, returns JSON) + the user's own **history** + **favourites**. Typing only shows the dropdown; nothing navigates. **(2) Pressing Enter:** the current tab **navigates to Google's results page for the query** (like `google.com/search?q=…`), the same as Chrome/Edge. **Google is the only (default) search engine.** Keystroke-to-Google is controlled by a Settings **"Search suggestions" toggle** (off = only history + favourites show). |
| 2026-09-16 | **Navigation buttons — LOCKED** | **Home · Back · Forward · Reload** (icons), outside and **left** of the URL bar. |
| 2026-09-16 | **Favourite star — LOCKED** | **Inside the URL bar, left corner.** **Two-state:** outline = not saved, filled = saved (chosen left, not right, so the user doesn't cross a big screen). Clicking either state **slides out the favourite panel**: outline → save flow; filled → edit flow (Rename / Change folder / Remove). |
| 2026-09-16 | **Favourites hub — LOCKED** | Icon button on the **left of the tab bar** opens a **slide-down list** of all favourites, with **edit / delete / grouping** and search. |
| 2026-09-16 | **Clear data — LOCKED** | "Clear" button at the **right edge, outside** the URL bar → dialog with **checkboxes** (Chrome/Edge style): *Browsing history · Cookies & site data · Cached images & files · Downloads*. Clearing never touches SALU's own data (resume history / saved streams). |
| 2026-09-16 | **Auto-clear — LOCKED** | Settings option, **Off by default**. Interval choices: **7 / 15 / 30 days**. Timing choice: **on player opening / on player closing / both**. ("Player" here = SALU the app; close-time clearing is the most reliable.) |
| 2026-09-16 | **Web view area — LOCKED** | The main WebView fills everything **below the URL bar**. |
| 2026-09-16 | **Empty state / last tab — LOCKED** | When the **last tab closes**, SALU stays in Web mode: the tab bar shows **only the `+`**, and the web view area shows a **start page with the SALU logo + "SALU Web Browser" text**. That start page is a plain Flutter widget (not a WebView), so it uses no WebView/RAM. |
| 2026-09-16 | **No SALU media controls — LOCKED** | Pure browser: no SALU play/pause/volume/transport. Sites (YouTube, Netflix, Prime, …) use their **own** player controls. **Fullscreen is handed to the web page** (like Edge) — the WebView takes the whole screen and HIDES SALU chin. |
| 2026-09-16 | **Downloads — LOCKED** | Standard browser behaviour: send the file to **Windows File Explorer** (user's Downloads folder) — like Edge/Chrome. |
| 2026-09-16 | **Popups & permissions — LOCKED** | Edge/Chrome-style: block popups by default + tidy prompts for site permissions (location, camera, notifications…). |

---

## 🗺️ Browser layout (top → bottom)

```
┌──────────────────────────────────────────────────────────┐
│  [ Player | Web ]  ··· title strip ···  ─ □ ✕            │
├──────────────────────────────────────────────────────────┤
│  ♥Fav  ▢ Tab  ▢ Tab  ▢ Tab  [ + ]                       │
├──────────────────────────────────────────────────────────┤
│  ⌂ ⇦ ⇨ ⟳   [ ☆  URL + suggestions…………………… ]   🧹Clear  │
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
| 8 | **Memory cleanup** | On "Close Browser", destroy the WebView controllers, clear the session cache, and flush RAM so SALU stays lightweight. |
| 9 | **Saved bookmarks** | Up to **15 Web Bookmarks** (plus 10 M3U streams) stored instantly with `shared_preferences`. |
| 10 | **WebView2 updates** | Settings → Updates can check for and update the WebView2 linker (`WebView2Loader.dll`) and `yt-dlp`. |

---

## 📌 Status notes

- **Phase 6 is "Not Started."** No browser code exists yet — only this plan.
- This file (`web.md`) now holds the **locked** detailed browser design. It
  **supersedes** the simpler 4-button description in `phase_6_details.md`
  Step 4 (Home / Back / Forward / Close Browser) — the old plan's
  "Close Browser" is replaced by the Player/Web toggle.
- `lib/ui/screens/` currently contains only `home_screen.dart` and
  `video_screen.dart`. `browser_screen.dart` does not exist yet.
- `follow.md` records that the web browser, bookmarks, and Stream Library
  panel were **postponed** to be designed separately (they are not mpv work).
- Related pieces planned across phases:
  - **Phase 4** — Settings → Updates button (manual WebView2 / yt-dlp update).
  - **Phase 5** — Auto-update function for the WebView2 `.dll` linker files.
  - **Phase 6** — The browser itself + saved streams/bookmarks sidebar.
