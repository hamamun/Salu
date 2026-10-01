# SALU — Complete Build Handout (Single-File Reference)

> **Generated:** 2026-09-30 · Branch `arena/01a0f0cb-salu` (from `4de9b57`) · Windows 10/11 · Flutter 3.47.5 · Dart >=3.4.0
> **Purpose:** One file that replaces every other `*.md` in the repo. After reading this you can rebuild SALU from scratch and re-brand it by changing only the “basic things” listed in §4.
> **Cross-checked:** Every section was verified against the live code in `lib/`, `pubspec.yaml`, `windows/`, `assets/` and `third_party/webview_windows/`. Where a design doc and the code diverged, the code is marked as truth.

---

## Contents

1. [Identity & Stack](#1-identity--stack)
2. [Requirements & Toolchain](#2-requirements--toolchain)
3. [Project Layout (verified tree)](#3-project-layout-verified-tree)
4. [Customisation Points — “Change Basic Things”](#4-customisation-points--change-basic-things)
5. [Architecture at a Glance](#5-architecture-at-a-glance)
6. [Window System — Borderless, Single Instance, State](#6-window-system)
7. [Media Engine — mpv / media_kit](#7-media-engine)
8. [Player Shell & Controller (OSC)](#8-player-shell--controller-osc)
9. [Playlist, Queue & Channel Lists (M3U/IPTV)](#9-playlist-queue--channel-lists)
10. [Built-in Web Browser (WebView2)](#10-built-in-web-browser)
11. [Subtitles — OpenSubtitles + Local Tracks](#11-subtitles)
12. [Lyrics & Audio Display](#12-lyrics--audio-display)
13. [Tune / EQ / Picture Panel](#13-tune--eq--picture)
14. [Info Panel & Metadata Harvest](#14-info-panel--metadata-harvest)
15. [Right-Click Strip & Panels Contract](#15-right-click-strip--panels-contract)
16. [Mini Bar Mode](#16-mini-bar-mode)
17. [Drag & Drop, Folder Autoload, Open Media](#17-drag--drop-folder-autoload-open-media)
18. [File Associations & Right-Click Verbs (Windows)](#18-file-associations--right-click-verbs)
19. [Remote — PC Server + QR Pairing + Phone Protocol](#19-remote--pc-server)
20. [Updater — Detached Swap for DLL/EXE](#20-updater)
21. [Shortcuts, Registry, Living Map & Alt-Peek](#21-shortcuts-registry-living-map--alt-peek)
22. [Settings & Persistence](#22-settings--persistence)
23. [Theme, Overlay Transparency & Controller Placement](#23-theme-overlay-transparency--controller-placement)
24. [Design Contract (follow.md Hard Rules)](#24-design-contract)
25. [Build / Run / Analyze / Test / Release](#25-build-run-analyze-test-release)
26. [Rebuild Checklist (fork in 15 minutes)](#26-rebuild-checklist)
27. [Verification Status & Known Gaps](#27-verification-status--known-gaps)
28. [File Index — Every Old .md → Where It Lives Now](#28-file-index)

---

## 1. Identity & Stack

| Fact | Value |
|------|-------|
| **App name** | SALU |
| **Tagline** | “A borderless media player for Windows.” |
| **Platforms** | Windows 10 (1809+) / 11 only — Web mode needs WebView2 Runtime; Player mode is pure mpv |
| **Language** | Flutter (Dart), C++ shim for window |
| **Engine** | `media_kit` 1.1.11 + `media_kit_video` 1.2.5–3.0 + `media_kit_libs_video` 1.0.5 → `libmpv-2.dll` |
| **Window** | `window_manager` 0.4.3–0.6.0 + `windows_single_instance` 1.0.1 + `screen_retriever` 0.2.2 |
| **Fonts** | **Segoe UI Variable** (Windows 11 system font) → fallback `Segoe UI` — no bundled font file |
| **Colors** | `lib/theme/app_theme.dart` → `AppColors` (legacy) + `AppPalette` (theme-aware) + `OverlayAppearance` |
| **Storage** | `shared_preferences` 2.3.0 only — no DB, no hive |
| **Vendored** | `third_party/webview_windows` (upstream `jnschulze/flutter-webview-windows` 0.4.0 + 4 SALU deltas) |
| **Version** | `pubspec.yaml` `0.1.0+1` (shown in Settings → About) |
| **Entry** | `lib/main.dart` |

Owner signature: `created by HAM` (About tab footer, `AppColors.whisper`).

---

## 2. Requirements & Toolchain

- **OS:** Windows 10/11 (WebView2 Runtime ships with 10/11; SALU never bundles Edge).
- **Flutter SDK:** **3.47.5** (CI-pinned; the checked-in `pubspec.lock` was generated with it).
- **Visual Studio:** 2022 **Desktop development with C++**, Windows 11 SDK 10.0.22000.194+.
- **Other:** `file_selector` opens native Explorer pickers (C++ backend, no win32 Dart constraint); `nuget.exe` optional for vendored WebView2 build.

```powershell
# one-time
flutter pub get          # regenerates windows/flutter/generated_*

# run
flutter run -d windows

# release
flutter build windows --release
# output: build\windows\x64\runner\Release\salu.exe

# quality gates (run on a Windows machine with SDK)
flutter analyze
flutter test
dart format --set-exit-if-changed lib test
git diff --check
```

`windows/runner/resources/app_icon.ico` is the taskbar/Start/Desktop icon (multi-res `.ico`).

---

## 3. Project Layout (verified tree)

```
Salu/
├── pubspec.yaml                 # name, version, 16 deps + flutter_test/lints
├── pubspec.lock                 # pinned with Flutter 3.47.5
├── analysis_options.yaml
├── .metadata
├── salu.md                      # THIS FILE — sole handout after cleanup
├── assets/images/               # salu_logo.png etc (declared in pubspec.yaml)
├── windows/
│   ├── runner/
│   │   ├── main.cpp             # Win32 bootstrap, COM, DartProject, 1280×720
│   │   ├── flutter_window.*     # Flutter embedding
│   │   ├── win32_window.*       # borderless sizing
│   │   ├── resources/app_icon.ico
│   │   └── Runner.rc
│   └── flutter/CMakeLists.txt   # plugin glue (regenerated by pub get)
├── third_party/webview_windows/ # vendored plugin (see §10, VENDOR_NOTES.md)
│   ├── windows/webview.{h,cc}   # Delta 1/2 live here
│   ├── windows/webview_bridge.cc
│   └── lib/src/webview.dart
├── design/                      # preview-only HTML mocks, NOT app code
│   ├── d14-fetch-preview/index.html
│   ├── iptv-channel-preview/index.html
│   ├── mini-bar-preview/index.html
│   ├── icons-preview/{index,concepts2,concepts3}.html
│   ├── remote-preview/ , right-menu-preview/, fetch-preview/ …
│   └── shortcut_preview.html    # Living Map mock (Version B superseded)
├── lib/
│   ├── main.dart                # boot (see §6)
│   ├── theme/
│   │   ├── app_theme.dart       # AppColors, AppPalette, OverlayAppearance
│   │   └── themed_app.dart      # SaluThemedApp (MaterialApp + themeMode)
│   ├── core/
│   │   ├── player_service.dart        # Player + VideoController, libass:true
│   │   ├── queue_service.dart         # ONE RAM list, contentRevision token
│   │   ├── queue_item.dart            # QueueItem (url + channel metadata)
│   │   ├── media_utils.dart           # ext sets, canonicalPath, natural sort
│   │   ├── drop_handler.dart          # DnD routing (playlist_imp §5)
│   │   ├── open_media_service.dart    # Open File/Folder/URL picker helpers
│   │   ├── resume_service.dart        # disk resume (see §8.5)
│   │   ├── sub_delay_service.dart     # per-file sub-delay (±5s)
│   │   ├── channel_load_service.dart  # m3u → Item list entry
│   │   ├── channel_view_service.dart  # Group by + open group (panel+remote)
│   │   ├── channel_grouping.dart      # Category/Language/Country inference
│   │   ├── channel_favourites_service.dart
│   │   ├── channel_logo_service.dart  # logo fetch/cache (native colours)
│   │   ├── queue_grouping_cache.dart  # shared grouping cache by revision
│   │   ├── window_state_service.dart  # full/mini geometries, alwaysOnTop lock
│   │   ├── panel_service.dart         # one-popup world (playlist/track/tune/info/rightMenu)
│   │   ├── info_collector.dart + info_controller.dart  # Info harvest
│   │   ├── audio_display_service.dart + audio_tag_fields.dart + mpv_metadata.dart
│   │   ├── lyric_service.dart + lyric_parser.dart + lyric_locator.dart
│   │   ├── subtitle_service.dart      # OpenSubtitles hash/search/download (cc.md)
│   │   ├── transport_actions.dart     # atomic play/pause/stop/next… verbs
│   │   ├── tune_service.dart + tune/  # Eq/Picture/Aspect/Speed (eq_imp.md)
│   │   ├── browser_service.dart + web/*  # Web mode (web.md)
│   │   ├── url_library_service.dart   # Saved URLs (max 7)
│   │   ├── settings_service.dart      # all prefs (see §22)
│   │   ├── ui_lock.dart               # ChromeLock
│   │   ├── updater/updater_service.dart + github_nuget … # updater.md
│   │   ├── association/association_service.dart # HKCU file assoc
│   │   ├── m3u/{m3u_parser,channel_mapper,channel_list_loader…}
│   │   ├── remote/*                   # Remote PC server (see §19)
│   │   └── shortcuts/shortcut_registry.dart # single shortcut list
│   └── ui/
│       ├── screens/
│       │   ├── home_screen.dart       # root Stack (video → panels → OSD)
│       │   ├── browser_screen.dart    # Web mode surface
│       │   └── video_screen.dart      # edge-to-edge mpv Video widget
│       ├── osc/
│       │   ├── controller_panel.dart  # top chrome + kChromeBlockHeight
│       │   ├── transport_cluster.dart # Play/Pause·Stop·Prev/Next·Seek·Mute
│       │   ├── media_timeline.dart    # seek bar + HoverChip
│       │   ├── volume_bar.dart        # 140×14 horizontal bar + in-bar %
│       │   ├── open_media_control.dart# + pill + Open URL modal
│       │   ├── open_url_dialog.dart   # URL modal (glass)
│       │   ├── right_menu.dart        # right-click strip (GlassCapsule)
│       │   ├── fetch_control.dart     # Fetch (subtitle) button
│       │   ├── tune_control.dart / playlist_control.dart / fullscreen_control.dart
│       │   └── remote_panel.dart      # QR/pairing/device list
│       ├── osd/
│       │   ├── osd_controller.dart    # OsdController singleton + TTL deck
│       │   └── osd_deck.dart          # glass capsule deck (top-center slot)
│       ├── panels/
│       │   ├── playlist_panel.dart    # 322px glass, 5-mark header, drag
│       │   ├── track_panel.dart       # Fetch panel (3 parts + sync bar)
│       │   ├── tune_panel.dart        # EQ/Picture/Aspect/Speed
│       │   └── info_panel.dart        # left slide-out (info.md §0)
│       ├── mini/
│       │   ├── mini_shell.dart        # Mini bar root
│       │   ├── mini_progress.dart     # 2px top edge meter (CustomPainter)
│       │   ├── volume_wheel.dart      # 20px ring dial
│       │   └── mini_marks/metrics/feedback
│       └── widgets/
│           ├── custom_title_bar.dart  # invisible hover title + caption marks
│           ├── salu_icon_button.dart  # THE icon recipe (1.06 hover, 0.90 press)
│           ├── salu_marks.dart + transport_marks.dart + settings_marks.dart
│           ├── glass_capsule.dart     # BackdropFilter(18)+glass+hairline
│           ├── download_badge.dart, live_light.dart, eq_curve_painter…
│           ├── settings_dialog.dart   # tab strip + Appearance/General/Web…
│           ├── about_tab.dart , associations_tab.dart , shortcuts_tab.dart
│           ├── browser_*.dart         # tab strip, address bar, hub, find bar…
│           ├── subtitle_search_dialog.dart
│           └── alt_peek.dart          # Alt-hold tooltip layer
└── test/
    ├── theme_test.dart
    ├── overlay_transparency_test.dart
    ├── controller_placement_test.dart
    ├── subtitle_scramble_test.dart
    └── …
```

**Cross-check notes**

- `lib/main.dart` boots: `MediaKit.ensureInitialized()` → `WindowStateService.load()` → `WindowOptions` (different for mini) → `setPreventClose(true)` → `Settings/UrlLibrary/Remote/Resume/SubDelay/Favourites/Tune/Browser` loads → `SaluApp`.
- `pubspec.yaml` already lists **all** deps the code imports — adding a new package without editing `pubspec.yaml` will break `flutter pub get`.
- `design/` is ignored at runtime; `third_party/webview_windows/` is compiled.

---

## 4. Customisation Points — “Change Basic Things”

To fork/re-brand SALU, change **only** these files/values (everything else follows):

| What you want | File(s) & key | Notes |
|---------------|---------------|-------|
| **App name & identity** | `pubspec.yaml: name`, `lib/main.dart: WindowOptions(title:)`, `lib/theme/themed_app.dart: title`, `windows/runner/Runner.rc` strings, `windows/runner/main.cpp` window title | Also update `assets/images/salu_logo.png` + `windows/runner/resources/app_icon.ico` (multi-res). |
| **Version** | `pubspec.yaml: version: 0.1.0+1`, About tab reads it live | `+1` is Windows build number. |
| **Window defaults** | `lib/main.dart` `Size(1280,720)` + `Size(800,600)` floor, `windows/runner/main.cpp` `Win32Window::Size(1280,720)` | Mini size is `lib/ui/mini/mini_metrics.dart` → `MiniMetrics.windowSize` (bar ~488 px, 32 px tall). |
| **Colors & typography** | `lib/theme/app_theme.dart` → `AppColors` / `AppPalette` (dark & light), `AppTheme.lightFor/darkFor` | System font `Segoe UI Variable` → fallback `Segoe UI`. Change `AppColors.glass`, `surface`, `accent #4C9EEB`, `statusAlive #57C777` etc. Light theme is a full `AppPalette` override, not just `ThemeData`. |
| **File extensions handled** | `lib/core/media_utils.dart` → `videoExtensions`, `audioExtensions`, `subtitleExtensions`, `playlistExtensions` | Adding `.mkv` etc. is here; associations read this indirectly via `association_service.dart`. |
| **Settings defaults** | `lib/core/settings_service.dart` → `ValueNotifier` initial values + `_key…` strings | e.g. `maxOverlayTransparency = 40`, `remotePort = 7258`, `subtitleLanguage = 'en'`, `webSearchSuggestions = true`. |
| **Thumb / bar sizes** | `lib/ui/osc/media_timeline.dart`, `lib/ui/osc/volume_bar.dart` (140×14), `lib/ui/mini/mini_progress.dart` | Change in one place; hover breathing is scaled, not absolute. |
| **Chrome height** | `lib/ui/osc/controller_panel.dart: kChromeBlockHeight` (40 title + 108 controller = 148) | OSD anchor `kChromeBlockHeight + 8` and playlist/info `top:` depend on it. |
| **Remote port / feature flags** | `lib/core/settings_service.dart: remotePort`, `lib/core/remote/remote_protocol.dart` `hello.features`, `lib/core/remote/remote_service.dart` | Changing protocol `queue_groups_paged` etc. must mirror on the Android APK repo. |
| **Updater feeds** | `lib/core/updater/update_manifest.dart` + `github_updater_client.dart` / `nuget_client.dart` | URLs for `libmpv-2.dll`, `yt-dlp.exe`, `WebView2Loader.dll`. |
| **Web search engine** | `lib/core/web/web_suggestions.dart` (`suggestqueries.google.com`) + `browser_service.dart` | Google is hard-coded as SALU’s only engine (web.md lock). |
| **Shortcut set** | `lib/core/shortcuts/shortcut_registry.dart` (single list) | Adding a key without a registry entry = bug. No remapping UI. |
| **Marks / icons** | `lib/ui/widgets/salu_marks.dart` + `transport_marks.dart` + `settings_marks.dart` | All marks use `markStrokeFor(size)` ≈ 8.5 % of size, round caps, monochrome. |
| **About copy / links** | `lib/ui/widgets/about_tab.dart` | Source link `github.com/hamamun/Salu`, credits, signature `created by HAM`. |

> Tip: after any branding change run `flutter pub get` (regenerates Windows glue) and a `flutter build windows --release` to see the icon/title in Explorer/taskbar.

---

## 5. Architecture at a Glance

**Stack layers (bottom → top)**

1. **OS / Engine:** Windows window → `media_kit`/`libmpv` (hwdec via `hwdec-current`) + `WebView2` (Edge).
2. **Services (singletons, `instance`):** `PlayerService`, `QueueService`, `SettingsService`, `WindowStateService`, `BrowserService`, `RemoteService`, `SubtitleService`, `TuneService`, `ResumeService`, `PanelService`, `AssociationService`, `UpdaterService`, etc. All expose `ValueNotifier`s; UI listens, never polls.
3. **Shell:** `SaluThemedApp` → `HomeScreen` (or `MiniShell`) → `VideoScreen` / `BrowserScreen`.
4. **Chrome & Surfaces:** `CustomTitleBar` + `ControllerPanel` fused as one glass block → `PlaylistPanel` (right), `TrackPanel`/`TunePanel` (drops from controller), `InfoPanel` (left), `RightMenu` (cursor-anchored), `OsdDeck` (top-centre).
5. **Persistence:** `shared_preferences` JSON blobs (see §22). Close guard flushes before `exit(0)`.

**Data flow**

- **Playback:** `QueueService.items/index` ↔ `PlayerService` (mirrors mpv playlist; channel mode: engine holds 1 URL, queue holds N). `TransportActions` is the verb layer Remote calls into — never direct `PlayerService` mutations from Remote.
- **Settings:** UI writes via `SettingsService.setX()` → `SharedPreferences` + notifier → themed rebuild / service reaction.
- **Window:** `WindowStateService` is the sole truth for `isFullscreen`/`isMaximized`/`mode` (bug-2 fix) — both caption and fullscreen buttons read it.
- **Web:** `BrowserService` owns tabs (`WebTab`), history, favourites, downloads (`WebDownloadService`), pop-ups, data control, auto-clear. `WebviewController` lives per tab, `suspend()` while offstage.
- **Remote:** `RemoteService` HttpServer (default 7258) → `RemoteCommandHandler` + `RemoteProtocol` → `TransportActions` + snapshot broadcaster (see §19).

---

## 6. Window System

### 6.1 Borderless window & title bar

- `window_manager.waitUntilReadyToShow(WindowOptions(... TitleBarStyle.hidden, windowButtonVisibility:false))`
- `CustomTitleBar` (`lib/ui/widgets/custom_title_bar.dart`) draws **Min (—) · Max (□) / Restore (two squares) · Close (×)** as thin SALU marks. Hover: `iconIdle → textPrimary` + scale 1.06; press: 0.90; **no box behind**, no red close box (follow.md rule 4). Drag on the strip moves window; double-click toggles maximize.
- Chrome fades in on mouse move, out after ~3 s of stillness **while playing** (idle shows it). Implemented in `HomeScreen` hover logic; `ChromeLock` (`lib/core/ui_lock.dart`) held by any popup.
- **Fullscreen cursor:** the arrow goes down with the chrome — `MouseRegion(cursor: SystemMouseCursors.none)` on the player's root region, swapped back to `MouseCursor.defer` on wake. Pure Flutter, no native call. Same 3 s rhythm as the chrome (`_cursorHideDelay`) and the same wake sources, but a **stricter decision**: fullscreen only, and it ignores both the transport state (drops while PAUSED, where "Pin (playback off)" keeps the chrome up) and the title-bar mode (drops in "Locked", where the chrome itself never hides). Never hides while the chrome block is hovered, `ChromeLock` is held, a panel/pill/right-menu is open (`PanelService.anySurfaceOpen`, watched through `PanelService.surfaces` so a surface raised by the remote pulls the arrow back at once), a drop is hovering, the window is unfocused (`didChangeAppLifecycleState`), or mini/Web owns the window. Leaving fullscreen reveals it immediately; entering arms the countdown instead of firing it. Pointer moves reveal it (`_wakeChromeAndCursor`); **transport keys deliberately do not** — they never wake the chrome either, so keyboard-only seeking must not flash the arrow. Child regions asking for `SystemMouseCursors.click` outrank the root while hovered.

### 6.2 Single instance & file-argument routing

- `windows_single_instance` with id `salu_media_player_instance` **before** `MediaKit.ensureInitialized()`.
- `onSecondWindow`: `windowManager.show()+focus()` → `extractFolderFromArgs` / `extractMediaPathFromArgs` → if `--enqueue` + `hasMedia` → `DropHandler.appendDroppedToQueue`; else `ChannelLoadService.openSource(path)` → else `FolderAutoloadService.maybeExpand(path)`. Duplicate process pays zero mpv startup cost.
- Cold start: same verbs in `main()` post-frame.

### 6.3 Window state & geometry

- `lib/core/window_state_service.dart` — **one owner** of `isFullscreen`, `isMaximized`, `WindowMode {full, mini}`, `FullWindowGeometry` (pos+size+max+fullscreen) + `_miniPoint`.
- Keys: `window_mode`, `window_full_geometry`, `window_mini_point` (shared_preferences).
- Invariants: **One memory, live truth wins** (`syncState()` re-reads OS after every command), **no silent restore** (maximize while fullscreen exits via `setFullScreen(false)` first).
- Mini lock: `setAlwaysOnTop(true)` → `setMinimumSize(miniSize)=setMaximumSize(miniSize)` → `setBounds(point & miniSize)`. Reverse on restore. Point clamped via `screen_retriever` (multi-monitor + DPI safe, `clampMiniPoint`).
- `HomeScreen` swaps to `MiniShell` when `isMini`.

### 6.4 Close guard

- `windowManager.setPreventClose(true)` → `_CloseGuard.onWindowClose`: flush resume, sub-delay, favourites, browser, tune, windowState, updater `applyAtClose()` each with 2 s timeout → `exit(0)`. Bypass widget teardown; OS reclaims mpv. Every step guarded so `exit` is always reached.

### 6.5 Unregister hook

- `salu.exe --unregister` → `AssociationService.instance.unregisterAll(); exit(0)` (uninstaller hook).

---

## 7. Media Engine

- **Init:** `MediaKit.ensureInitialized()` once (first instance only). Player: `Player(configuration: PlayerConfiguration(libass:true))` — **must** be `true` or mpv subs are invisible (cc.md First runtime finding).
- **Video widget:** `Video(controller: VideoController(player))` in `VideoScreen`, `BoxFit.contain`, backdrop `AppColors.videoBackdrop (#121212)` letterboxes. `SubtitleViewConfiguration(visible:false)` — Flutter overlay OFF, mpv native is the sole renderer.
- **HW decode:** enabled by default; `player.getProperty('hwdec-current')` logged as `[SALU] hardware decoding: d3d11va` (expect `d3d11va` on GPU).
- **Class extentions:** Verified: `desktop_drop`, `file_selector`, `screen_retriever`, `path`, `ffi`, `crypto`, `qr_flutter`, `http`, `audio_metadata_reader`, `flutter_video_thumbnail_plus`.
- **Supported types:** see §4 table; `MediaUtils.canonicalPath` normalises slashes, long-path prefix `\\?\`, UNC, `file://` — resume/stop equality depends on it.

### PlayerService essentials (`lib/core/player_service.dart`)

- `ValueNotifier`s: `currentPath`, `position`, `duration`, `volume (0-200)`, `isMuted`, `isPlaying`, `transportState (idle/stopped/paused/playing)`, `hasMedia`, `activeHwdec`, `stopMemory`.
- Repeat: `RepeatMode {off, all, one}` (header control; never persisted).
- Undo: sealed `QueueUndo` → `RemovedItemUndo` / `ClearedQueueUndo` with 5 s toast.
- `loadExternalSubtitle(path)`, `selectAudioTrack`, `selectSubTrack`, `subOff`, `setVolumeUI`, `toggleMute`, `seekTo`, `playIndex`, `stop()`, `next()`, `previous()`, `playFromStop()`.
- Queue mirroring: while playing, hands full playlist to mpv (native auto-advance); after **Stop**, releases item, canvas → logo, `hasMedia=false`, queue retained, index kept, stopMemory armed.

### Transport & Seek

- **Stop parks queue** (Stop ≠ Start Over): releases item, zeros timeline `00:00:00/00:00:00`, hides hairline, flushes resume store; Play resumes at that position with Resume toast.
- **Enable matrix:** see `outline_transport_osd_resume.md` §2 (Stop dims seeks & stop, Prev/Next dims at edges, `+` always live).
- **SeekRamp:** shared by `Seek Back/Forward` + ←→ keys + remote. Tap = ±5 s, rapid clicks climb `5→10→15→20…` (n×5, no ceiling, clamped at bounds), gap >400 ms resets, hold = 300 ms repeats, every other transport resets both ramps; OSD shows `>> +15s  01:12:34`.

### Volume bar

- `lib/ui/osc/volume_bar.dart` — horizontal **140×14** (hover 16, hit 34), track `barTrack`, fill `barFill`, translucent. No endpoint numerals; value `62%` inside bar at fill’s right edge (left when muted/0), `max(pad, fillEnd-labelWidth-pad)`. Brightens on hover/drag. Hover chip = timeline’s `HoverChip`. Wheel ±5 %; drag horizontal; dragging out of muted unmutes.

---

## 8. Player Shell & Controller (OSC)

### 8.1 HomeScreen layering (bottom → top)

`video canvas → drop overlay → bottom hairline (hidden when STOPPED; never drawn for a channel list) → top chrome (title+controller) → playlist panel → resume-toast click-outside → OSD deck → modals`  
Z: video < playlist < chrome < Open pill < OSD < barrier/modal.

- **Bottom hairline** (`_AutoHideProgress`, 2 px, display-only, pointer-absorbing) shows the progress fill while the chrome is auto-hidden — local files only, playing or paused. A **channel list draws nothing there**: the still soft light that used to stand in for a progress fill has no position to show, and it fades on every buffering stall and back on every recovery, which on a fullscreen bottom edge read as a buffering lamp pulsing with the network. The gate is `QueueService.isChannelList`, *not* `PlayerService.isLiveMode` — the latter also wants `hasMedia`, still false between the playlist landing and the first stream connecting. The light remains inside the timeline (`§8.2` row 1), where it belongs to a controller the user asked for.

### 8.2 ControllerPanel (`lib/ui/osc/controller_panel.dart`)

- **Row 1 = timeline** (`MediaTimeline`) — always top, full width, never moves (follow.md rule 5). Hover preview via `flutter_video_thumbnail_plus` when `mouseOverPreview` is on (Settings → General).
- **Row 2 = 36 px control row:** Open `+` (left, below timeline) → `TransportCluster` (centre) → modes + right menus (right edge reserved for Fetch/PiP/fullscreen). Grouping by pitch alone: 6 px inside group, 14 between groups, 26 before sound group — no boxes ever. `kChromeBlockHeight = 40+108 = 148` is the block height; the OSD anchor is `+8 = 156`.
- **Right edge future:** tracks/PiP/fullscreen/panels — never crowds the row.

### 8.3 TransportCluster (`lib/ui/osc/transport_cluster.dart`)

Drawn entirely as SALU marks (`transport_marks.dart`): `>` / `||` / `□` / `|<<` / `>>|` / `<<` / `>>` / speaker(+arcs). Pitch 6/14/26. Seeks are press-and-hold with ramp; speaker arcs track level (1 arc <50 %, 2 ≥50 %, slash when muted/0).

### 8.4 OSD Deck (`lib/ui/osd/osd_deck.dart` + `osd_controller.dart`)

- One slot, top-centre at `kChromeBlockHeight+8 = 156`, horizontally centred.
- Motion: enter fade+slide −10→0 160 ms, exit →−6 120 ms, replace cross-fade 100 ms. Glass capsule (Blur 18 + `AppColors.glass`, radius 10, hairline). H 36 transient / 40 toast; 14 px padding; 96–360 px width.
- **Cards:** transport (`mark 18 + time/title`, 1 s), volume (speaker + read-only VolumeBar, 1 s), **Resume toast** (`[>] 12:34  [↻ Restart]`, 4 s interactive). Discrete actions flash; bars never do. Latest replaces prior; deck never wakes chrome, never focuses. Resume: playChevron 16 + `formatClockCompact`, Restart word+mark, dismiss via 4 s / click-outside (dismiss only) / Esc.
- Bottom-placement override (enhance.md Phase 3): bottom controller → deck in upper-middle clear area.

### 8.5 Resume memory (`lib/core/resume_service.dart`)

Two memories, one shelf logic:

| Memory | Lives | Filled by | Consumed by | Gate |
|--------|-------|-----------|-------------|------|
| **Stop memory** | `PlayerService.stopMemory` (session) | Stop button | Play/Space/canvas while stopped | none |
| **Disk memory** | `shared_preferences` JSON `resume_positions` `{path:[posMs,durMs,updatedMs]}` capped 1000 oldest-pruned | every tick (5 s throttle while playing, immediate on pause/stop/switch/close) | `openPath/openPaths` on later open | Settings → Resume mode + `MediaUtils.isVideo/isAudio` |

Window: keep only if `5 s ≤ pos ≤ duration−10 s` and `duration ≥ 30 s` and local file; else remove (finished file starts over). Resuming uses `Media(start: saved)` → when playlist lands, toast fires; fallback: seek once on first `duration>0`.

### 8.6 Subtitle sync (delay)

- Per-file delay stored in `SubDelayService` (same flush-on-close path), `±5 s`, 0.1 s steps, double-tap reset, `Z/X` (Shift = 1 s). Track panel shows bar centred at `0.0s`. Drives mpv `sub-delay`.

---

## 9. Playlist, Queue & Channel Lists

### 9.1 QueueService (`lib/core/queue_service.dart`)

- **One RAM list** `ValueNotifier<List<QueueItem>> items` + `ValueNotifier<int> index`. URLs are canonical via `MediaUtils.canonicalPath`. Processes playlist via mpv while playing; after Stop re-opens at index.
- **Revision token:** `sessionToken = 'q' + 8 random hex` + monotonic serial → `contentRevision = 'qXXXX-serial'`. Changes on load/clear/replace/append/remove/reorder/metadata — NOT on position/play/pause/grouping. Phone uses it for paged reads (§19). No reuse after restart.
- Operations: `append`, `remove`, `clear`, `reorder`, `playIndex`, `replaceAll`, `paths` (lazy cached URL view). Shuffle: **playback order only** — visible list stays natural order.

### 9.2 PlaylistPanel (`lib/ui/panels/playlist_panel.dart`)

- Geometry: `Positioned(top:kChromeBlockHeight, right:0, bottom:0, width:322)` (study-approved), `ClipPath(TopRight 14)` + Blur 18 + `glass` + left hairline. Slide `translateX 1→0` 220 ms. Never covers timeline readout; overlays video (no dock — docking would rescale picture mid-scene).
- **Header (only when queue non-empty):** 5 marks in 322 px (padding 8/10): Repeat (off→all→one; off=quiet 55 %, one=+ bead), Shuffle (crossing rules), **Search** (glass field radius 14: magnifier + text + count + ✕ — no placeholder), Clear (Trash), Close (×). No footer, no tabs, no labels.
- **Rows (38 px, r 9):** `≡ grip · [▶ on playing row] · name · duration(playing-only) · hover Trash`. Click = `playIndex`. Hover wash `rgba(255,255,255,.055)`. Duration only on current item; others blank (no probe of 40 files).
- **Drag** reorder by grip; shuffle never reorders visible list.
- **Search:** filters VIEW only (queue untouched); live; no-match → centred magnifier 40 px 30 % ink; count inside field `14` / `9 / 14` (numerals are data, not instruction). Focus exception: while field focused Space/←→ type; click outside releases; Esc tiers: clear text → release focus → close panel.
- **Auto-scroll:** shortest distance to nearest edge if playing row not in 6 px slack; 220–300 ms; entrance = jump (slide is motion); suppressed while pointer scrolls + 3 s after manual scroll; ignored when filter hides row.
- **Deleting playing row:** auto-picks next → prev → initial state (logo), via `playIndex` so resume applies. Clear = stop + empty + logo. Both offer 5 s Undo toast (rule 3). SALU scrollbar: thin thumb `.16` → `.30` hover, transparent track, no arrows (`scrollbars:false` + RawScrollbar).
- **Empty:** no header, `NowRowMark(46, now:-1)` 30 % ink centred; still accepts drops.
- **Panel contract:** not a popup — toggle via playlist control / `Ctrl+L` / Esc; opening one panel closes others (`PanelService`).

### 9.3 M3U / IPTV channels (playlist_imp.md §10)

- **Parser:** `lib/core/m3u/m3u_parser.dart` + `channel_mapper.dart` + `channel_list_loader.dart` (SALU's own incremental parser, no cap, no external fetch). `ChannelSource`, `ChannelMetadata`, `ChannelLoadService`.
- **Open paths:** URL typed in Open URL modal (`http…` + `.m3u/.m8u`) → `ChannelLoadService.openSource/openBatch`; local `.m3u/.m8u` dropped or opened → same; always parsed by SALU, never handed to mpv whole. Detection: `MediaUtils.isPlaylist`.
- **Grouping & inference:** `channel_grouping.dart` + `ChannelViewService` + `QueueGroupingCache`. Modes: **Flat, Category, Language, Country** (pill). Country/language survive a bare playlist: parsed from `group-title` (`US | News`), `tvg-id` ISO suffix (`ATNBangla.bd@SD` → BD), channel name (`IN: SONY TEN 2`), stream query (`?country=bd`), falling back to single-dominant-language country. Generic TLD `.tv` never counts as country. Category-only grouping when bare.
- **UI (approved study `design/iptv-channel-preview/`):** logo rows (native-colour artwork allowed — the one follow.md rule 7 exception), per-provider favourites (`ChannelFavouritesService`, `shared_preferences`), group pill sticky accordion, reveal chevrons, faint live light on inert timeline while data arrives, dead-channel skip (3-strike guard), alphabetically sorted country/language (Unknown last), Category preserves provider order.
- **Timeline in channel mode:** inert, soft live light pulse while data arrives.
- **§10.10a:** channel mode = engine holds 1 media, queue holds N; Prev/Next follow group-dim rules; Stop retains list/current channel; Play resumes same channel.

---

## 10. Built-in Web Browser

**Status: implemented** (`lib/core/browser_service.dart` + `lib/core/web/` + `lib/ui/screens/browser_screen.dart` + `lib/ui/widgets/browser_*.dart`). `webview_windows` vendored.

### 10.1 Vended plugin (why)

Upstream `jnschulze/flutter-webview-windows` 0.4.0 (`ed81bbe`) had no PreferredColorScheme and no DownloadStarting deferral. SALU vendors it for 4 deltas (all marked `SALU addition`):

| Delta | API | File | What |
|-------|-----|------|------|
| 1 Page colours | `put_PreferredColorScheme` (`ICoreWebView2Profile`) | `webview.h/.cc`, `bridge.cc`, `lib/src/webview.dart: setPreferredColorScheme(0=auto,1=light,2=dark)` | Settings → Web → Page colours drives `prefers-color-scheme` (Edge’s own control). |
| 2 Downloads ask | `put_ResultFilePath` / `put_Cancel` + `GetDeferral` + `put_DefaultDownloadFolderPath` | same | `SetDownloadPreferences(ask, folder)`; ask ON → hold deferral → `downloadStarting` → Dart shows native Save As (via `file_selector`) → reply `{path}` or `{cancel:true}`; ask OFF = upstream behaviour. |
| 3 HID fix | `keyboard_handler` | `.cc` | corrects missing `WM_KEY*` path |
| 4 Frame callback | `FrameReceived` | `.cc` | off-screen composition stability |

Everything else byte-identical to upstream.

### 10.2 Tabs

Capped ( `+` quiets at cap, 8); inactive tabs **lazy** (no engine until first activation, `suspend()` while offstage). `×` right-of-tab, `+` right-of-last-tab, middle/right-click closes. Closing last tab leaves Web mode with start page (Flutter: logo + “SALU Web Browser”). Tabs share width, capped 208 px each; narrow tabs hide badge, ellipsize title.

### 10.3 Address bar & suggestions

Below tab bar. **Typing → dropdown only** (debounced) from merged list: **Google Suggest** (`suggestqueries.google.com/complete/search`, JSON) + **history** + **favourites** — own data first. `Enter` / row-pick navigates Google results (`google.com/search?q=…` — Google is SALU’s only engine). Settings “Search suggestions” toggle mutes Google leg only. Suggest rows use magnifier mark, not `?`.

### 10.4 Toolbar (locked row)

Left → right: **Home · Back · Forward · Reload · Close Browser** (returns to Player) — **exactly four**, fixed order. Multi-tab creation: clicking a Web Bookmark while Web mode is open spawns a new tab instead of overwriting.

### 10.5 Favourites & history

- Favourites hub: `♥` left of tab row; slide-down list, search, folder groups, edit+delete. **≤ 15 Web Bookmarks**, `shared_preferences`.
- History: grouped list, delete, clear-all — all via Edge-standard shelves.
- Clear browsing data dialog: dark, badges live (counts/KB/MB) per category, SALU monochrome marks, measures only SALU’s own profile stores (cookies, Local/Session Storage, IndexedDB, Service Workers, HTTP/code/GPU/shader caches by well-known names). Cache not-locked-by-engine deleted mid-session; locked categories report “None + queued purge” and are purged at **next startup** (`BrowserService.prepareClose` → next open). SALU’s own stores (resume, saved streams) never in scope.
- Auto-clear: Settings → Web → `WebAutoClearInterval {off, 7,15,30 days}` × `WebAutoClearTiming {onOpen,onClose,both}`; “on closing” = due-date sweep + stores flush at close guard, locked part deferred.

### 10.6 Web mode lifecycle

- Toggle **Player · Web** pill top-left of `CustomTitleBar` (same place both modes, single way to jump). Web draws no media controls and **pauses playback on entry**; mode switch **never tears browser down** (keep-alive lock 2026-09-17 — Offstage + engine `Suspend`; coming back finds tabs exact, media paused).
- Page fullscreen: hides SALU chrome for web view; Esc (page listener + Flutter fallback) releases; navigating to Player releases hand-off first. Pop-ups shimmed document-start into badge + per-site rules (Allow/Block/visit; Settings default + exceptions). Permissions: one card per request (camera/mic/location/notifications/clipboard/sensors).
- Downloads: badge animates (`download_badge`), shelf shows `start → ring → land → Play / Show in folder / Open folder`; Save-As dialog pre-filled with engine’s filename, starting in download folder; Cancel writes nothing, leaves no row; 2 parallel = 1 dialog at a time; flipping ask mid-session reaches live tabs.
- Browser windows themselves are Flutter layout; **no SALU settings live in web content**. The ⋮ menu Zoom ladder / Desktop UA / Find (Esc/Enter/arrows) / History groups / ⋮ door are all SALU-drawn.

### 10.7 Settings door

Both browser doors — ⋮ menu “Settings” row and the Web-mode title-strip button — open `SettingsDialog(initialTab: SettingsTab.web)` via `BrowserService`. Player doors still open General.

---

## 11. Subtitles

**Contract: `cc.md` D1–D17 (owner 2026-09-09/10/13). v1 implemented (12 files, §7).**

### 11.1 Settings → Subtitles

`SettingsDialog` tab with three sections (follow.md labels-only: lock strings are superseded):

- **Credentials:** API key (OsDev “consumer”), username, password (persisted **scrambled** `base64(nonce‖xor)` via `SubtitleScramble` — obfuscation, not encryption; salt in source — fixes Third runtime finding). Bearer token stays in-memory (`SubtitleService.sessionToken`).
- **Language:** ISO 639 preferred (default `en`) + `language_names.dart`.
- **Auto:** `subtitleAutoDownload` (default ON).

### 11.2 AUTO engine (§3)

- Fires once **at landing** on a local video (search uses text hash + OS; download is key+Bearer). Gated: key set + local video + no local subs sibling + file hash available + not quota-walled.
- Chain: preferred → English (D5); if neither → silence (D9), session-marked (no second quota spend). Music/URL/channel skipped. Hash match only for AUTO; query match → manual Fetch only (D9).
- Guards: **once-per-session** per file (`hash → notConfigured / failedThisSession`); 401/429 → engine paused (bad key vs quota), surfaces `Subtitles — check key / check login / limit reached` (D11/D15).
- **Credential-edit retry:** `_retryCurrent()` debounced 1.5 s after password/key edit (fixes Second finding) — one attempt/burst, silent per D10 so half-typed password never spends quota, clears `_token` and `_failedThisSession`.
- **Download retry:** 5xx → up to 2 more with backoff (`Retry-After` capped 10 s; 2 s→4 s), never rate-limited (5xx never hits quota). 429/402/403 never retried (§3.5).

### 11.3 Rendering (D16)

`PlayerConfiguration(libass:true)` in `player_service.dart` — the ONE renderer is mpv native (fixes First finding where `visible:false` without this = zero renderers). `video_screen.dart: SubtitleViewConfiguration(visible:false)`. Style via mpv options (`sub-font`, `sub-font-size`, `sub-color`, `sub-border-size`, `sub-shadow-offset`, `sub-pos:100`, `sub-ass-vsfilter-blur-compat` etc., §5 corrected 2026-09-13 to keep subs in bottom black bar via `sub-use-margins=yes` — media_kit sizes surface exactly to picture so letterbox is Flutter paint).

### 11.4 Fetch panel (D14)

- **Button:** `FetchControl` right zone, left of fullscreen. Local video only → live; audio/channel/URL → greyed inert, never hidden.
- **Panel:** `TrackPanel` slide-down from controller, floats over video, Esc/click-outside closes (keeping search window). Three live-mirror parts (poll via `PlayerService` notifiers): **Part 1 audio** (`codec/desc/lang`, untagged → “Track n”), **Part 2 embedded subs** (Off pinned top), **Part 3 local subs** (autoloaded + Load). >5 rows → fixed 5-row inner scroll. Selection mirrors mpv (including auto-selected), tap → select/deselect (D17: no default forcing). No OSD for track switches (row mark is feedback).
- **Load:** `file_selector` picker, session-only, wav channel.

### 11.5 Search window (query path §6.5)

Glass centred modal, dim barrier, open→act→gone (rule 8):

- Top: **editable field** pre-filled with file’s **full name exactly as on disk** (extension included — owner 2026-09-13; previously cleaned). Four marks: **Search · Save · Save & Load · Close** (tooltips only; Save/Load dim until row picked).
- **Search** = filename/query API (never AUTO’s hash path). Results grouped: **Group A** = best 3 in preferred language only, **Group B** = all matches all languages incl. preferred (scrollable). Rows = movie title + language (one step).
- **Save** → `<basename>.<lang>.srt` beside video (D8 naming, never overwrite), window closes, OSD `Saved · <file>` (D10’s “window closing alone would read as nothing”). **Save & Load** → same download + `loadExternalSubtitle` now.
- **Already-saved** → no download: `Already saved · <file>` (Save) or apply copy (Save & Load), quota never burned twice.
- **Manual taps SPEAK** (owner 2026-09-13): no-sign-in → `Subtitles — sign in`, download fail (inc empty/HTML 200) → `Subtitles — download failed`, paused engine repeats its wall text on every tap. AUTO stays silent (D10) and missing-login is NOT session-marked (typing flow).
- **Not configured:** opens window; Search tap → one-per-session `cc not configured` card (D11).

### 11.6 Subtitle OSD cards (deck family)

`cc not configured` · `check key` · `check login` (added after Third finding; `/login` 401) · `limit reached` · `sign in` · `download failed` · `saved/already saved` — all 1 s translucent.

### Files touched (cc.md §7)

`pubspec.yaml (+http)`, `settings_service.dart:SubtitleScramble`, `settings_dialog.dart:_SubtitlesTab`, `subtitle_service.dart` (hash/search/download/save/session guards/Bearer/credential retry/`[SALU/subs]` log), `player_service.dart` (trigger+track selectors), `osd_*`, `video_screen.dart (libass)`, `controller_panel.dart (Fetch)`, `language_names.dart`, `fetch_control.dart`, `track_panel.dart`, `subtitle_search_dialog.dart`. Tests: `subtitle_scramble_test.dart`.

---

## 12. Lyrics & Audio Display

**Spec: `lrc.md`**

- **Detection:** `MediaUtils.lyricExtensions = {.lrc}` — `.lrc` only; `.lyr` out-of-scope.
- **Locator:** `lyric_locator.dart` — same folder as audio → `song.lrc` for `song.mp3` (configurable sibling scan).
- **Parser:** `lyric_parser.dart` — `[mm:ss.xx]` lines (+ enhanced L7), sorted, deduped.
- **Service:** `lyric_service.dart` + `lyric_locator` — loads on audio landing; ticks with `position`.
- **UI:** `AudioDisplayService` + `audio_tag_fields.dart` (ID3 APIC / FLAC picture / MP4 covr via `audio_metadata_reader 1.4.0`), `AlbumArtView`, `LyricsOverlay` (scrolling view next to art, highlight current line (white) vs surrounding (gray), click line → `seekTo(timestamp)` via `ScrollController` linked to mpv). Implemented in `HomeScreen`/`TrackPanel` area for music mode.
- **Stub:** `enhance.md` notes park — lyrics engine parser ready, interactive scroll linked via ScrollController.

---

## 13. Tune / EQ / Picture

**Spec: `eq_imp.md`**

### 13.1 Grid & math (`lib/core/tune/tune_model.dart` + `tune_engine.dart`)

- **10 bands:** 31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000 Hz (labels `31…16k`). Widths `62,62,88,176,354,707,1414,2828,5657,8343` Hz (octave mid, shelved ends). Gain `−12…+12 dB`, zero threshold `0.01` → Flat = no filters in chain. A live `EqFilter` builds `af` ladder.
- **Picture:** 5 fine keys `saturation,gamma,contrast,brightness,hue` (mpv options) → `TuneState` continuum.
- **Continua:** 4 parts share ONE selection language: a thin line with labeled stops (named stop or blend between neighbours) — `TunePart {eq,picture,aspect,speed}` etc.
- **State:** `TuneService` (singleton) owns live curve, learning map `AutoEQ` (`auto_eq.dart` + `tune_state.memory`), histogram (`tone_histogram.dart`), presets (`tune_presets.dart`). Persisted via `TuneService.load()/flush()` before first frame so launch into a file lands on remembered curve (eq_imp §6) — flushed on close too.

### 13.2 Panel (`lib/ui/panels/tune_panel.dart`)

- Central card, same glass as other panels, continuum UI: `TuneContinuum` + `TuneSliders` + `EqCurveOverlay`/`EqCurvePainter` (draws live EQ curve). Hover recipe inherited; bars tint via `OverlayAppearance`.
- **Behaviour:** `AutoTone` learning, per-file memory, preset pills; default Flat. Panel opens from controller (bottom/top anchor per placement — see §23), bound to available space, scrolls internally. Changes immediate, persisted live.

---

## 14. Info Panel & Metadata Harvest

**Spec: `info.md` §0 (locked 2026-09-19). Door = right-menu Info mark only.**

### 14.1 Surface (`lib/ui/panels/info_panel.dart`)

- **Position:** `Positioned(top:kChromeBlockHeight, left:0, bottom:0)` — mirrors playlist width `min(322, windowWidth−24)` / `height = windowHeight−148` → 322×452 @ 800×600. `ClipPath(TopRight 14)` + Blur 18 + `glass` + right hairline. Slide from left, 220 ms; hit-testing stops on close start; internal scroll when overflow.
- **Row grid:** padding `14,10,14,14`; header 30 (InfoMark + Close); group heading 10.5 uppercase `textSecondary`; row 22 px fixed; label 11.5 `textSecondary` in fixed **78 px** column (settings label size); value 12 `textPrimary` left-aligned at gutter with `tabularFigures` for times/sizes/rates; ellipsize no-wrap; **no truth → row not drawn** (no `—`/`N/A`).
- **Groups (six, presence-gated — empty groups not drawn):**

| Group | Rows | Source | When |
|-------|------|--------|------|
| **Identity** | Title (`title→media-title→fname`) always, Artist/Album/Year/Genre/Track/Disc | tag map via `PlayerService.currentTitle` | when file tagged |
| **Picture** | Res→fps→codec→decoder→bitrate→colour (HDR/PQ only) | `hwdec-current` in hand + new reads ⚠ | video |
| **Sound** | codec, channels, samplerate⚠, bitrate⚠, language(+name) | `MpvTrack` + `audio-params/*` | audio track selected |
| **Clock & file** | Duration, **Position (ticks)**, **Remaining (ticks)**, fileSize (`file-size→File.stat` ⚠), container (`file-format` ⚠) | in hand/derived | local only |
| **SALU** | Queue (`4 of 12`), Played from (`resumed 12:34`), EQ (`Custom`/preset), Subtitles (`+0.4s`) | QueueService/ResumeService/TuneService/subDelay | when applicable |
| **Stream** | Provider/host, Group, Language **+ source** (`Bangla · from tvg-id`), Country + source, bitrate⚠, buffered⚠ | `channel_metadata` + MetadataSource | URL/channel |

- **Stream provenance:** channel list already tracks `MetadataSource`; Info is the sole viewer that says “from the tvg-id” vs guessed.
- **Live vs frozen:** clock ticks off `position/duration` notifiers; everything else read once on open, re-read on media/audio/sub/resolution change — no polling timers.

### 14.2 Harvest (`lib/core/info_collector.dart` + `info_controller.dart` + `mpv_metadata.dart`)

- Parses tag map, falls back across `tag.*` and `metadata.*`. Refused on purpose: engine/version (About only), decoded-frame width vs display width distinction (no window-geometry read), next-item preview (SALU owns queue).
- ⚠ marks need runtime verify on a Windows build (real mpv answers).

### 14.3 Rules

- **Dropped when none:** playing→ groups as table; nothing loaded / STOPPED → panel does not open (§0.8).
- **One-popup world** wired both ways with Open pill (measured collision: `+` at y136 + pill 6+42 → y142–184 overlaps panel top 36 px; fix: open-pill sets `infoOpen=false` and `OpenMediaControl` listens for Info open).

---

## 15. Right-Click Strip & Panels Contract

**Spec: `right_item.md` (concept A locked 2026-09-19). Code: `lib/ui/osc/right_menu.dart`.**

### 15.1 Visuals

- Glass capsule (`GlassCapsule` = Blur 18 + `glass` + `surfaceOutline`), `r 12`, padding `6v 8h`. Hit 30×30, glyph 18, stroke `markStrokeFor(18)≈1.5`.
- Marks 4 (shipped): **shuffle · repeat ‖ InfoMark · Settings (four dots)**. Remote reserved seat empty. Timeline is row 1, never moves; popups float OVER video (rule 5).
- Hover chip after 600 ms names control (timeline’s `HoverChip`, width-fitted): `Shuffle / Shuffle · suspended / Repeat · off|all|one / Info / Settings` — never teaches, never shows shortcut (rules 1–2). Press: scale 0.90; arrival fade+scale 0.96→1.0 150 ms.

### 15.2 Behaviour contract

1. **Right-click closes first, opens second** — gesture reuse: browser-tab-close, fav-edit, panel barriers all eat it before the menu. So: panel/modal open → close it, no menu; menu open → close it; door open → close it; nothing open → open at cursor (nudge 12 px margins, 10 px drop; flip above bottom edge).
2. **Toggles stay, doors leave** — Shuffle/Repeat stay open (quick-settings); Info/Remote/Settings leave the strip then show surface.
3. **Mark carries state:** off = 55 % `quiet`, on = white+ faint glow, `repeat=one` = bead at arc centre; shuffle suspended by repeat-one = ink 55 % + chip `Shuffle · suspended` (existing header rule reused).
4. **Channel mode:** drops Shuffle & Repeat (live lists already avoid them); Info always live; Remote live only when server can answer; Settings always live.
5. **Esc tiers (outer→inner):** door → **Info panel** → menu → **Open pill** → playlist. Left-click on picture with menu open → close menu only (never pause). `ChromeLock` held while menu open. One popup at a time (opening menu closes panels and vice-versa). Pill ↔ Info exclusivity wired both ways (see §14.3).

### 15.3 Code

`PanelService` owns notifier (`rightMenuOpen` beside playlist/track/tune/info). `HomeScreen` layers a `Listener(onPointerDown: kSecondaryButton)` (not `showMenu`) above video, below OSD. `InfoMark` lives in `salu_marks.dart`.

---

## 16. Mini Bar Mode

**Spec: `mini.md` v5 FINAL (2026-09-26). Code: `lib/ui/mini/*`, `lib/core/window_state_service.dart`.**

### 16.1 What it is

32 px tall, **~488 px** fixed-width, always-alive strip (never fades/sleeps/collapses — alternatives hairline-collapse/ghost-fade rejected). Always-on-top entire session. No video surface, no subs/lyrics/art, no playlist/Fetch/EQ/Settings, no resize/maximize, no OS chrome, no OSD, no tooltips (32 px has no room for a hover popup — full mode keeps tooltips).

### 16.2 Strip anatomy (left → right, group pitch **5 / 11 / 20** — mini’s own, mini compresses full 6/14/26 via “shrink the space, never the glyphs”):

1. **Drag handle** (Salu glyph) — dead space + icons drag the bar; controls never drag.
2. **Transport 7** (full-mode marks at 18 px, hit 26×30 via `SaluIconButton`, dims identical): `> / ||` · `□` · `|<<` · `>>|` · `<<` · `>>` · **speaker + wheel** (wheel = 20 px ring dial: dim track ring, level arc filling clockwise from 12 o’clock + head tick; wheel ±5 % only; click/drag ignored; rolling over speaker or ring both work). 26 px hit floor, 5 px in-group gap.
3. **Title** (~141 px, ellipsis truncation — channel name in IPTV) — the swappable feedback surface (see §16.4).
4. **Restore** button (own slot, far right) — exits mini.

### 16.3 Edge meter

**Position rides TOP edge only:** 2 px strip (`#80FFFFFF` on `#35353C`), full width, click/drag jump; invisible hit ~10 px tall hanging from top.

### 16.4 Enter / exit / runtime

- **Enter:** toggle glyph left of Settings in title strip (same family), or `M`. Saves full geometry (pos+size+max+fullscreen) **before** shrinking.
- **Exit (3 ways):** Restore button, double-click dead space, `Esc`. Restores saved geometry exactly.
- **Runtime:** video plays as audio (mpv keeps running, widget not mounted); queue Prev/Next follow group dims; folder drops & single-instance routing play instantly **staying in mini**; hotkeys (space/arrows/seek) live while bar focused; Stop parks; resume/EQ/sub-offset keep working silently; **close while in mini → next launch opens mini at same point**, full geometry remembered separately.

### 16.5 Feedback — title swap only (no toast rule)

OSD does not exist here. Title fades to transient message ~1.2 s then back (same size/colour):

| Event | Swap text |
|-------|-----------|
| Volume wheel | `Volume 45%` |
| Mute | `Muted` / `Volume 45%` |
| Seek | `+15s · 01:12:34` |
| Stop | `Stopped — queue parked` |
| Prev/Next | next track/channel name |
| Edge click | `→ 01:23 · 02:19 left` |

### 16.6 Implementation notes

`WindowMode {full,mini}` persisted. Enter: `setAlwaysOnTop(true)` → `setMinimumSize(mini)=setMaximumSize(mini)` → `setSize(mini)` + move to last point (clamped via `screen_retriever`). Exit: reverse + `setBounds(fullRect)`. `HomeScreen` root swaps to `MiniShell` (rest of tree not built). Painters reused unchanged from `transport_marks.dart` via `markStrokeFor`; group pitches mini-owned. Both bar surfaces (track+fill) tint via `OverlayAppearance.overlayTint`; playhead notch/ticks/head tick stay opaque. Change log v3–v5 locks Previous `|<<`, volume wheel, and 26/5/11/20 compression.

---

## 17. Drag & Drop, Folder Autoload, Open Media

### 17.1 Drop (`lib/core/drop_handler.dart`)

Routes per `playlist_imp.md` §5 + `fix_notes.md`:

- **Subtitle drop** first: if `.srt/.ass..` + `hasMedia` → `loadExternalSubtitle` each; if only subs → “Subtitle loaded”.
- Else **media collect:** `collectPlayable` expands folders shallow ( `isMedia` filter ) + natural episode sort (folder→name, `ep2` before `ep10`). Delegates to `ChannelLoadService.openBatch` — a `.m3u/.m8u` in the batch wins **entire batch as channels** (studied block rule: one gesture = one block, M55), never mixed queue.
- `mediaPaths.length==1` → `FolderAutoloadService.maybeExpand(path)` (see below); `handleDroppedPaths` returns summary for overlay.

### 17.2 Folder autoload (`autoload_imp.md`, `lib/core/folder_autoload_service.dart`)

Gate: Settings → `folderAutoloadMode {off, all, videoOrAudio}` + exclusions + kind lock 4 (video start → queue videos only; audio→ audio only); single file only, never batch/append-while-panel-open. When allowed: `scanFolderForMedia` (same natural sort) queues siblings silently — playback continues on the original file, but Next walks the folder.

### 17.3 Open Media (`lib/core/open_media_service.dart` + OSC)

- **Level 1 pill:** `+` left of timeline rotates 45° to `×` while open (130 ms); small horizontal glass pill **below** button, floating over video (downward); 3 marks: film frame (Open File → native multi-select), stacked frames (Open Folder → scan & queue), link (Open URL → glass modal). Tooltips hover-delay only; follow.md rule 6.
- **Level 2 URL modal** (`OpenUrlDialog` — centred glass, dim barrier, open→act→gone): one input + **inside-field marks** (▶ Play, ▶+tag Play & Save — tooltips, no label row). Clipboard URL (`http`/`m3u`/`m8u`) pre-fills selected. Saved list max **7**: row `≡ · ● dot · name` + hover `✎ · 🗑` (fade on right). Click row = plays it. Dots: green last succeeded, red failed, gray never. Edit inline (name+URL); Delete instant + 5 s Undo toast inside modal; reorder by drag-handle; Play & Save dims at 7/7 (tooltip “List full”), plain Play always works. Keys: Enter=Play, Ctrl+Enter=Play&Save, Esc=close, ↑↓ walk list. Persisted JSON (`name,url,status`) via `UrlLibraryService` (`shared_preferences`).

---

## 18. File Associations & Right-Click Verbs

**Spec: `association.md` (owner 2026-09-28). Code: `lib/core/association/association_{plan,registry,service}.dart` + `salu_context.md` addendum.**

Three features under one Settings → **File Types** tab (marks-only actions, labels + values only):

| # | Feature | Result |
|---|---------|--------|
| A | **File associations** — Video/Audio/Playlist groups, one checkbox per ext + one per group | Registers/unregisters exactly the ticked set |
| B | **Default player** | One mark opens **Windows Settings → Default apps → SALU** (SALU never touches `UserChoice` hash) |
| C | **Right-click menu** | “Play with SALU” + “Add to SALU queue” on media files & folders |

**Windows rule (since 8, locked):** default choice is hashed in `UserChoice`; only the user can set it. So:
- *Associate* = SALU ProgID `SALU.<ext>` (`FriendlyTypeName`, `DefaultIcon`, `shell\open\command`) + `HKCU\Software\Classes\.<ext>\OpenWithProgids` + `HKCU\Software\Classes\Applications\salu.exe` + `HKCU\Software\SALU\Capabilities` + `HKCU\Software\RegisteredApplications`; also sets `.<ext>(default)=SALU.<ext>` **only if empty** (no hijack of existing choice). Where no choice exists SALU becomes class default without ask.
- *Default* = user confirms in Windows Settings (mark B).
- *De-associate* = removes only SALU’s entries (fallback to previous app or prompt). No admin, no hash hack, no SetUserFTA.

Right-click verbs (feature C):

```
HKCU\Software\Classes\SystemFileAssociations\*  (or per-ext)  → Play with SALU / Add to SALU queue
HKCU\Software\Classes\Directory\shell\SALU.Play  → "Play with SALU"  "%1"
HKCU\Software\Classes\Directory\shell\SALU.Enqueue → "Add to SALU queue"  --enqueue "%1"
```

Cold/second-instance: `salu.exe "%1"` and `salu.exe --enqueue "%1"` forwarded via single-instance pipe; `AssociationService.ensureRegistered()` keeps `HKCU\Software\SALU\RegisteredExe` + `Applications\salu.exe` pointing at this exe (first run / moved folder). `--unregister` removes every SALU key (uninstaller hook).

---

## 19. Remote — PC Server

**Primary: `remote.md` v1.1 (authority). Also: `pc_part.md` Parts F, E, B, etc.; APK spec `remote_apk_ui.md` (opinion, separate repo). Code: `lib/core/remote/*` + `lib/ui/osc/remote_panel.dart`.**

### 19.1 What ships (PC)

SALU runs a **LAN WebSocket server** (default port **7258**, Settings → General → Remote, ON by default). Android APK is a separate project (built later); this phase is PC side only.

### 19.2 Pairing & security (remote.md D2–D4, D9–D10)

- **Pairing is QR-first**, not mDNS. `RemotePairing` generates 6-char code; `RemotePanel` shows QR (`crypto` SHA-256 token hash + `qr_flutter`) + code + rotating hint. Beacon is later UDP, never Bonjour.
- Every connection is **authenticated** with device token (`RemotePairing`, `GuardedScript` for script isolation).
- **Commands go into `TransportActions`** (D12), not `PlayerService`. State updates throttled: full snapshot, ~4/s position, events instantly (D5).
- **QR door:** rightmost item in the right-click strip (when serverRunning); toggle ON by default (`remoteEnabled` default true).
- Firewall hint via `RemoteFirewall` / `RemoteConnectionLog` (delayed, non-modal).

### 19.3 Commands & protocol v1 (`lib/core/remote/remote_protocol.dart`)

Supported JSON actions mapped to `TransportActions`: `play_pause`, `stop`, `next`, `previous`, `seek_forward/back` (ramp), `volume_up/down` (±5, unmutes), `mute_toggle`, `open_url`, `queue_*`, plus `queue_group_set` and paged reads below. No media keys.

**Snapshot shape (what the phone shows):**

- `hello.features` announces `queue_groups_paged` etc.
- `state.queue {kind: channel|media, count, index, grouping {available:[category|language|country], mode}, revision: opaque-token}` — `revision` is content/order token, NOT top-level `rev`; not position/play.
- `state.playback {volume, mute, state, position, duration, title}`
- `state.remote {devices, pairingCode, address, status}`

### 19.4 Large-playlist paged protocol (pc_part.md Part F2 — required wire)

**Why:** legacy `queue_groups` assumed `start+count` membership is consecutive — false for scattered channels. F2 reserves a **byte-bounded fragment** contract:

- **Rows (extended):** `queue_get {from,count,revision} → {type:queue_result, from,total,revision, rows:[{index,title}…]}` (ascending, consecutive, max count, ≤8192 bytes envelope; one title too large → shorten title, keep index; stale rev → `stale_queue`; valid rev echoed).
- **Group pages (new verb):** `queue_groups_page {by:category|country|language, revision, from,count} → {type:queue_groups_result, revision, by, groups:[{key,name,count,start,indexes:[…]}…], next}`
  - `from` = fragment offset, NOT queue index. `count` = max **fragments** (remote starts 20). `next = from+len` or null.
  - Precompute groups in descriptor-head order (Category = provider order; Country/Language = alpha, Unknown last); never reorder queue. Split each group’s members into bounded non-empty **fragments** (suggest ≤100 indexes, deterministic bounds) each carrying `key,name,count,start(first member),indexes(exact members)`.
  - Flatten fragments; byte-pack whole fragments to ≤8192 inc envelope; deterministic boundaries; multiple fragments same key → identical name/count/start; every channel exactly one group incl Unknown; no dup across/within.
  - Invalid `by` → `invalid_arguments`; stale rev → `stale_queue`; a playlist change mid-prepare must fail stale, never mix revisions. Envelope carries `id`+`ok:true`.
- **Errors:** `busy` (temp), `too_fast` (rate), `too_large` (even smallest frag cannot fit — normal pages avoid via packing), `stale_queue`. No auto-retry of mutating calls.
- **Errors copy:** same set applicable to non-queue commands where request too large.

### 19.5 Progressive loading & pacing (Part F0–F6)

- **Progressive pages:** ask now-playing channel’s page first; remaining load background; search/favourites become complete as pages arrive (not yet on-demand-only — eventually full list fetched). Keep playing row in view until manual scroll/group select.
- **One paced serial read lane:** 100 ms gap after each response, leaves budget for commands/heartbeats; read-only `busy|too_fast|timeout` retried twice with backoff; grouping mutations not auto-replayed.
- **Shrink on too_large:** reduce page sizes (incl old PC’s `busy` with same string); preserve loaded pages, Retry offered; never raise 8 KiB limit.
- **Caching:** stable descriptors cached by revision+mode, shared panel↔Remote handler; cache invalidated only on content/view changes; no sort/filter in 120/250 ms widget builds; optional worker isolate if parse/group blocks UI.
- **Heartbeat:** 10 s transport keepalive unchanged (Part E claim revised), obsolete sockets guarded, web-media poller single-flight & skips inactive/offline + ignores stale page/link.
- **Telemetry:** last 10 socket-close diagnostics (Connect → Connection history): timestamp, code, mode, authed, age, pending, RTT, error type — no URLs/tokens/paths.

### 19.6 PC panel observation (F1)

`PlaylistPanel` must subscribe to `ChannelViewService.groupMode` + `openGroup` (invalidate descriptor/reveal caches, coalesce into one frame, one service-level mode-change, preserve queue order). Remote change must paint even while panel closed.

### 19.7 UI (`lib/ui/osc/remote_panel.dart`)

Slide-down from right, shows QR + code + discovered devices + allow/forget per device, enable toggle, file-access toggle, port field, connection history (10). Pairing QRs isolated via `GuardedScript`/`RemoteWebFocusBridge`. Matches `design/remote-preview/` in shapes (code is truth).

### 19.8 APK side (`remote_apk_ui.md` / `pc_part.md` / `web.md` companion)

Opinion only — separate repo. Includes: queue pages progressive, chips row mirrors PC grouping, command headroom, connection history, web-media polling, 30-minute soak acceptance (user-PC) still required.

---

## 20. Updater

**Spec: `updater.md` v1 (2026-09-26/27). Code: `lib/core/updater/*` + `lib/ui/widgets/update_dialog.dart` + Settings → Updates.**

### 20.1 Components checked

| File | Upstream | Via |
|------|----------|-----|
| `WebView2Loader.dll` | NuGet `Microsoft.Web.WebView2` | Flat Container V3 → extract `x64/WebView2Loader.dll` |
| `libmpv-2.dll` | media-kit / mpv Windows builds | Release API → 64-bit archive |
| `yt-dlp.exe` | `yt-dlp/yt-dlp` | GitHub Latest Release API |

Also reports current mpv version, decoder, platform.

### 20.2 Cadence

- Check frequency: `UpdateCheckFrequency {daily, weekly, manual}` + `lastUpdateCheckTime` in `SettingsService`; `UpdaterService.scheduleStartupCheck()` is silent, just raises “Update Available” flag; `Updaters` tab shows badge.

### 20.3 Install = detached swap (re-engineered §6.1)

Source of truth is `saluUpdaterScript` in `update_installer_windows.dart` (annotated copy §6.2 is not a second authority).

- Stages to versioned folder under `SALU/staging/<ver>/`; `.old` renames, lock probing, script left-for-sweep on kill.
- **Apply at close:** “Restart Later” → `applyAtClose()` spawned via `setPreventClose` path with `relaunch:false` — waits for PID to die, swaps files, next launch user-initiated. “Restart now” relaunches after swap.
- **Post-launch sweep:** `postLaunchSweep()` on every startup (first moment SALU certain swapped files no longer in use) cleans stale locks/scripts/`.old`/already-installed staging.
- Staging versions never cleaned eagerly; only when already installed.
- Never needs admin — per-user layout.
- Verification on Windows: schedule sweep after kill, locked DLL handled, `.old` cleaned after restart, cadence respected.

---

## 21. Shortcuts, Registry, Living Map & Alt-Peek

**Spec: `shortcut.md` (owner 2026-09-27 FINAL). Code: `lib/core/shortcuts/shortcut_registry.dart` + `lib/ui/widgets/shortcuts_tab.dart` + `lib/ui/widgets/alt_peek.dart`.**

### 21.1 Rule (§1)

One key, **one meaning per mode** (Player vs Web). `Alt` must never replace `Ctrl`. Standard keys win over product wishes — SIP: device makers → mpv / VLC / MPC-HC / Chrome/Edge are the standards. No custom remapping — ever.

### 21.2 Scopes & groups

`ShortcutScope {player, mini, web, dialog}` — mode pill `Player·Mini·Web·Dialogs` (four-option pill recipe) switches the Living Map.  
`ShortcutGroup {transport, speed, seeking, window, subtitles, surfaces, tune, mini, webTabs, webNavigation, webPanels, webFind, webZoom, urlModal, addressDropdown, findBar, playlistSearch, playlist}`.  
`ShortcutGuard {seekable, subtitleSelected, pageFullscreen, findBarOpen, groupByPillOpen}`.

### 21.3 Inventory (§2 — silent, follow.md rule 2)

**Group A Player (VLC/mpv):** `Space` Play/Pause, `←→` Seek ramp (hold climbs), `↑↓` Volume ±5 %, `M` Mute (standardised; Bare M is mute both full+mini), `S` Stop (no-op when idle/stopped), `PgUp/PgDn` Prev/Next, `Z/X` Sub ±100 ms (Shift=1 s), `Shift+S` Shuffle, `R` Repeat, `[ ] \` Speed slower/faster/reset, `. ,` Frame step, `0–9` Jump 0–90 %, `B/V` Cycle audio/sub tracks, `F/F11` Fullscreen.

**Group B General + Mini:** `Ctrl+M` Toggle Mini (M in mini = mute), `Ctrl+L` Playlist, `Ctrl+F` → Player focuses Playlist search **and** Web opens Find (cross-mode; same standard key, separate mode), `Ctrl+Shift+O` Open Folder (VLC standard), `Esc` dismiss chain (see §15.5), `Ctrl+O` File, `Ctrl+Shift+O` Folder anecdote, `Ctrl+U` URL modal.

**Group C Web (Edge standard):** `Ctrl+T/W` New/Close Tab, `Ctrl+Tab/Shift+Tab` Next/Prev, `Ctrl+1–8` Jump, `Ctrl+9` Last, `Ctrl+Shift+T` Reopen, `Ctrl+L/Alt+D/F6` Focus address, `Ctrl+R/F5` Reload, `Ctrl+F5/Shift+R` Hard reload, `Alt+←→` Back/Forward, `Alt+Home` Home, `Ctrl+H/J/D` History/Downloads/Favourite sheet, `Ctrl+Shift+O` Favourites Hub, `Ctrl+Shift+Delete/Backspace` Clear data, `F2/Ctrl+,` Web settings (opens Settings → Web), `Ctrl+F/F3/Shift+F3` Find, `Ctrl+=/-/0` Zoom, `F11` Browser fullscreen, `Esc` close popup/release page fullscreen, `Ctrl+Shift+W/Alt+W` Switch Player⇄Web.

**Group D Dialogs:** URL modal `Enter/Ctrl+Enter/↑↓/Esc`, address dropdown `↓↑/Enter/Esc`, find bar `Enter/Shift+Enter/Esc`, playlist search `Esc` (clear→unfocus), Group-by `1/2/3/4` pills (Flat/Cat/Country/Language).

No hints printed at rest; popups never show keys.

### 21.4 Registry (§4.0)

One data list (`shortcut_registry.dart`). Entry: scope + combo(`LogicalKeyboardKey` + ctrl/shift/alt/meta) + actionId + group + guard(optional) + anchor(optional). Anchored = control-visible; rideless = lives on glass shelf at video left (generated from `rideless(scope)` so no dup/miss). `ValueNotifier`s react; handlers (`HomeScreen._onKeyEvent`, `BrowserScreen`) keep working but must update registry in same commit. Runtime bug if key ships without entry.

### 21.5 Living Map — Settings → Shortcuts (§4.1)

**Revision:** drawn-keyboard (board+pill+latch+capture) rejected in preview “did not like anyone”; Living Map approved same day.

- Type: reference tab (not a setting), `SettingsTab.shortcuts`; About tab to its right (Phase 9).
- **Idea:** miniature SALU that is alive — every always-visible control as clean icon (no key text on it), unanchored keys on quiet glass shelves at video left (action mark where exists — open folder, find, info… — else keycap `[ ] \`, `F3`…), whole thing answers when pressed, naming hover in **detail strip** below (the ONLY place key text appears: left column keycap+group+action+guard; right column same key in other three modes via §3 matrix). Hovering a mark lights it and writes detail.
- **Layout:** mode pill → miniature (~280 px) → detail strip (~80) + note; dialog `min(640×540, window−insets)` header+strip+divider leaves 640×450; top 30 + mini 280 + strip 80 ≈ 430 fits, narrower windows `FittedBox` scales as one; fifth tab → strip overflow slides horizontally.
- **Liveness engine:** while tab open it swallows keyboard; every registered key fires mock feedback: transport moves mock timeline/volume, Space swaps play mark, OSD deck flashes, `Ctrl+L`/`Ctrl+G`/`Ctrl+D` open mock playlist, `F/F11` hides chrome, mode keys (`Ctrl+M`, `Ctrl+U`, `Alt+W`) flip miniature states; `Esc` follows app order (panel→fullscreen→close). Unregistered = nothing. Dialogs is a live surface too: focussed card (typing guard) answers `Enter/Esc/↑↓`; Group-by digits light the choice; playlist field keeps two-step Esc. Two slices: (A) static map (pill+mini+shelves+hover) + (B) liveness engine; B requires A.

### 21.6 Alt-Peek (§4.2 Version C — supersedes B)

*Peek, never ladder.* Hold **Alt alone → 200 ms arm**. While armed, **hovering a control shows its key as a tooltip** in `TooltipTheme` look (SALU surface/border/font, key in tabular, sized to text never cut off). Move = tooltip follows; leave = vanishes; release Alt = disarmed. Close to mpv’s “hold H for help” but target-bound. Covers all anchored keys; rideless shelves already show via Living Map. No ladder, no “all chips at once”.

---

## 22. Settings & Persistence

**Single service: `lib/core/settings_service.dart`. Store: `shared_preferences`. `ValueNotifier` per key + `setX()` persisting immediately (or on confirm where noted). Close-guard flushes late edits.**

### 22.1 Key table (truth = code)

| Key (prefs) | Type | Default | UI | Notes |
|-------------|------|---------|----|-------|
| `title_bar_mode` | `TitleBarMode {borderless, windowed}` | `borderless` | General | chrome behaviour |
| `appearance_theme_mode` | `SaluThemeMode {defaultTheme, light, system}` | `defaultTheme` | Appearance | §23 |
| `appearance_overlay_transparency` | `int 0–40` | `0` | Appearance | % tint removed, §23 |
| `appearance_controller_placement` | `ControllerPlacement {defaultTop, top, bottom, bottomEdge}` | `defaultTop` | Appearance | §23 |
| `resume_mode` | `ResumeMode {all, videosOnly, none}` (per-kind) | `all` | General → Resume | per file kind |
| `folder_autoload_mode` | `FolderAutoloadMode {off, all, videoOrAudio}` + exclusions | `all` | General | §17.2 |
| `web_search_suggestions` | `bool` | `true` | Web | Google leg toggle |
| `web_auto_clear_interval` | `WebAutoClearInterval {off,7,15,30}` | `off` | Web | days |
| `web_auto_clear_timing` | `WebAutoClearTiming {onOpen,onClose,both}` | `onOpen` | Web | |
| `web_popup_default` | `WebPopupDefault {block, allow}` + per-site map | `block` | Web | pop-up shim |
| `web_page_scheme` | `WebPageScheme {auto, light, dark}` | `auto` (`Follow Windows`) | Web → Page colours | Δ1 |
| `web_ask_download_location` | `bool` | `true` | Web → Downloads | Save As |
| `web_download_folder` | `string` | `` (= Windows Downloads) | Web | `put_DefaultDownloadFolderPath` |
| `auto_eq` | `bool` | `false` | Tune | Auto Tone |
| `mouse_over_preview` | `bool` | `false` | General | timeline thumbs |
| `remote_enabled` | `bool` | `true` | General → Remote | ON by default |
| `remote_file_access` | `bool` | `true` | Remote | file scan |
| `remote_port` | `int` | `7258` | Remote | |
| `subtitle_api_key` | `string` | `""` | Subtitles | consumer key |
| `subtitle_username` | `string` | `""` | Subtitles | |
| `subtitle_password` | `string (scrambled)` | `""` | Subtitles | `SubtitleScramble` base64(nonce‖xor) |
| `subtitle_language` | `string` | `en` | Subtitles | ISO 639 |
| `subtitle_autodownload` | `bool` | `true` | Subtitles | AUTO engine |
| `update_check_frequency` | `UpdateCheckFrequency {daily,weekly,manual}` | `weekly` | Updates | |
| `last_update_check_time` | `int epoch` | `0` | Updates | cadence |
| `window_mode` | `WindowMode {full, mini}` | `full` | WindowStateService | |
| `window_full_geometry` | `json {x,y,w,h,maximized,fullscreen}` | none | WindowStateService | |
| `window_mini_point` | `offset` | clamped | WindowStateService | |

Plus stores outside this file: `resume_positions` (ResumeService), `subtitle_offset` map (SubDelayService), `channel_favourites` (ChannelFavouritesService), `url_library` (UrlLibraryService), `web_history`, `web_favourites` (BrowserService), `remote_devices` (Remote), `tune` (Tune).

### 22.2 SettingsDialog (`lib/ui/widgets/settings_dialog.dart`)

- Tab strip (`part`-based tabs: `general, appearance, web, updates, subtitles, shortcuts, about, associations…`). **One quiet column:** small uppercase caption, 1-line rows (label left, control right, hairline between), pill pickers (owner 2026-09-28).
- Every pill set names factory default in one quiet line beneath it (`Default · Borderless`) — word beats dot/badge.
- Every group with a default wears small **reset mark** on caption while anything off-default (silent when all defaults); instant reset + house `Settings reset` Undo toast (never confirm, rule 3). Groups without defaults (OpenSubtitles signed-in material, per-site pop-ups) carry no mark.
- **Master reset** at right end of tab strip — same mark, appears while any pref off-default, one press resets **preferences only** (never OpenSubtitles account, EQ memory, paired phones, favourites/history, per-site rules).
- Shortcuts & About are reference pages: name + one gist line per feature, no reset marks, no default lines.
- Helper sentences retired 2026-09-28 — labels+values+hover-delay tooltip only (rule 1). Owner ruling supersedes older helper copy locked in cc.md§2.3/web.md/updater.md§7.

---

## 23. Theme, Overlay Transparency & Controller Placement

**Spec: `enhance.md` (owner). Implemented Phases 1+2; Phase 3 implemented. Code: `app_theme.dart` + `themed_app.dart` + `settings_dialog.dart` Appearance tab.**

### 23.1 Theme (Phase 1)

Three options **Default · Light · System** saved as `appearance_theme_mode`:

- **Default** = today’s SALU dark (not Windows pref). Preserved for existing users.
- **Light** = complete light appearance (text, controls, panels, menus, dialogs — not just canvas).
- **System** = follows Windows light/dark and responds live when OS changes.

Implementation: `AppPalette` `ThemeExtension` on `MaterialApp` (`SaluThemedApp` builder listens to `themeMode`), `lightFor/darkFor(transparency)`. Shared colors are theme-aware tokens; audit moved every fixed `AppColors` surface through `BuildContext.palette` (shortcuts illustrations retain original colours). Browser page colours stay independent via `WebDataControlService` (Δ1).

### 23.2 Overlay transparency (Phase 2)

Saved `0–40%` slider in Appearance (5% steps, live, release commits). **0 = original alphas untouched** (preserve look), higher = fraction of **existing tint removed**, NOT opacity retained — e.g. 80% opaque glass at 40% → 48% opaque. Ceiling 40% conservative pending Windows contrast tests. `OverlayAppearance.transparency` → `tint(original) { original.withAlpha(original.a*(1-%/100)) }` and `ThemeExtension` value-equality (`hashCode` by percent so mini CustomPainter repaints correctly).

**Audited SALU-owned floating surfaces** (background tint only; text/marks/focus/shadows unchanged; blur unchanged): fused player chrome gradient, standalone title chrome, mini bar, glass controller pills/deck/toasts, hover chips, playlist/track/tune/info panels, settings/subtitle dialogs, open-URL/remote/update/firewall dialogs, Flutter browser menus/shelves/popups/tooltips, plus **bar family** (all four): media seek bar, volume bar (row + OSD copy), subtitle-delay bar (track panel), mini 2px edge meter (via `overlayTint` from widget; `BuildContext.overlayTint`). Bars’ playhead notch/ticks/labels/detent stay opaque for readability; volume/sub-delay hover-tint uses **final** colour after hover blend. Intentional exclusions: opaque video/letterbox/browser canvas, lyric canvas, WebView2 page, OS dialogs, dim barriers, QR/artwork, form-fill, selected pills, shortcut illustrations (not floating tints). Test: `overlay_transparency_test.dart` (30 sources, WASM dart_style).

### 23.3 Controller placement (Phase 3)

Persisted `appearance_controller_placement` (default `Default` = fused 148 px block). Appearance pill: **Default · Top · Bottom · Bottom edge** (icons+labels, group reset/Undo, live apply):

- **Default** = title+controller fused.
- **Top** = title bar at top, controller detached **below it with a gap** (visually distinct from Default).
- **Bottom** = floats **24 px** above lower edge.
- **Bottom edge** = flush to lower edge.

Bottom enters animating **upwards** (top/Default from above). Placement is a shared layout value: playlist bounds stop above bottom controller; track/tune panels open **upward** for bottom; info bounds bounded; OSD deck moves to upper-middle clear area (not obscured). Mini mode ignores this (its own bar). Test: `controller_placement_test.dart` (migration + persistence).

### 23.4 Shortcuts note

No shortcuts or Alt-Peek assignments for appearance; Shortcuts tab/registry untouched.

---

## 24. Design Contract

**Source: `follow.md` — binding contract, read-first for any AI/dev.**

### 24.1 Hard rules (never break)

1. **No instruction text** — no hints/tips/tutorials/onboarding/“you can also…”. UI explains itself. Tooltips (hover-delay) that NAME a control are allowed; they never teach. *Owner 2026-09-28 adds:* Settings & Remote carry labels+values only; helper sentences retired.
2. **No shortcut labels in menus/popups** — shortcuts work silently, never printed at rest. (Living Map + Alt-Peek are deliberate **reference surfaces**, not at-rest chrome — see §21.)
3. **No confirmations** — destructive deletes execute instantly + **5 s Undo** toast.
4. **No stock rectangle hover** — no filled box/pill/circle behind icon; **NoSplash** globally, no Material ripple.
5. **Container rows never shift** — Timeline ALWAYS row 1; popups float OVER video (never push/resize/reflow), no box around groups.
6. **Custom SALU icon family** — thin monochrome geometric marks in `salu_marks.dart`/`transport_marks.dart` (four-dots Settings, thin +/×, film frame / stacked frames / link, triangle/tag, pencil/bin/tick/≡, transport chevrons `>` / bars / speaker(+arcs) / ↻, caption —/□/×, channel stem/rungs/brackets/speech/globe/bookmark/chevron). No text buttons (toast Undo/Restart is sole word exception).
7. **Colors/typography** — deep grays `#121212/#1E1E1E` (never pure black), Segoe UI Variable only, monochrome icons, `AppColors`. **IPTV artwork exception** (owner 2026-09-08): channel logos retain native colours before name (`playlist_imp.md` §10.4.2 FINAL).
8. **Modal vs panel** — focus tasks = centred glass modal (dim barrier, open→act→gone); live tasks (EQ/subs/playlist) = slide-out panels. Never mix.

### 24.2 Icon recipe (every icon uses `SaluIconButton`)

- Rest: `iconIdle` (soft gray). Hover: `textPrimary` (white) in ~120 ms + scale **1.06**; nothing behind. Down: scale **0.90** instantly; up springs back 120 ms ease-out. Active/toggle: white+faint glow (reserved for on). Bars exception: thicken on hover + hover chip (bars breathe, icons glow). `volume_bar` spec: horizontal 140×14, value inside fill, wheel ±5 %.

### 24.3 Motion language

Every popup/modal: fade+scale 0.96→1.0, 130–220 ms ease-out cubic, grow from anchor. Esc closes; outside closes; opening one closes others. Open `+` rotates 45° to `×` 130 ms while pill open.

### 24.4 Open Media placement (final)

Directly below timeline at left. Pill: click +→× → small horizontal glass pill **below** button, floating over video (right reserved). 3 marks with silent shortcuts (`Ctrl+O/F/U`). URL modal specs in §17.3.

---

## 25. Build / Run / Analyze / Test / Release

### Firmware of the dev loop

```powershell
git checkout arena/01a0f0cb-salu
flutter pub get
flutter analyze
flutter test               # includes theme/overlay/controller/subtitle tests
flutter run -d windows
# observe: borderless centred 1280×720 (or mini bar if last close was mini),
# hover fades chrome, drag strip moves, drop file plays, console shows
# [SALU] hardware decoding: d3d11va

# release
flutter build windows --release
# installer (not yet shipped): would handle --unregister hook
```

### Verification gates (owner’s checklists still owed on a Windows box)

- §7 Windows-build verification for subtitles (hash→lang chain, quota cards, already-saved).
- Theme Light readability over bright/dark video in all placements.
- Transparency 0/20/40 % over bright/dark moving video, light/dark chrome, fullscreen/windowed/mini, all panels.
- Controller placement short-window panel scroll, fullscreen/max/mini transitions, 24 px bottom gap, hover popups.
- Large M3U perf + `queue_groups_paged` round-trip (30-minute soak) for Remote.
- Browser mode keep-alive round trip + auto-clear timings + pop-up badge + downloads Save As.
- Association registry round-trip + right-click verbs after move folder.

---

## 26. Rebuild Checklist

Use this if you fork SALU and want “same, but my name/colours/extensions”:

1. `git clone` → checkout `arena/01a0f0cb-salu` (or `main` after merge).
2. Edit pubspec: `name`, `description`, `version`, bump deps if needed; run `flutter pub get`.
3. Replace `assets/images/salu_logo.png` + `windows/runner/resources/app_icon.ico` (export 16/24/32/48/256).
4. Edit `lib/theme/app_theme.dart` → `AppPalette.saluDefault` (dark) + light variant, `accent`, `status*`; add brand string in `lib/ui/widgets/about_tab.dart`.
5. Edit `lib/main.dart` WindowOptions size/title, `windows/runner/main.cpp` title/size, `lib/core/media_utils.dart` ext sets.
6. If you fork Remote APK, copy `remote_protocol.dart` constants to it; change `remotePort` if needed.
7. Run `flutter analyze && flutter test && dart format --set-exit-if-changed lib test`.
8. Build Windows: `flutter build windows --release`; smoke-test: single instance (double-click file), Stop parks queue, drag folder natural sort, playlist search duplicates guard, translation `1/2/3/4` not intercepting `0–9` seek, mini bar 488×32 + top meter, right-menu seat gap, Web keep-alive, subtitle Fetch panel marks live, updater staging clean.
9. For Windows distribution, build the complete release folder with `flutter build windows --release`, then compile `salu.iss` in Inno Setup. The installer is x64 / Windows 10 1809+, offers per-user or all-user install, shortcut/startup choices and video/audio/playlist Open-with registration, closes SALU for upgrades, unregisters associations on uninstall, and optionally removes SALU settings/WebView2 profile. It checks for WebView2 and offers Microsoft's download page if missing. The installer packages the MSVC runtime DLLs next to `salu.exe`; test the release folder for `msvcp140.dll`, `vcruntime140.dll`, and `vcruntime140_1.dll` on Windows. Remote's consent-based Private-profile firewall setup remains in SALU; do not add a broad installer firewall rule. Code signing still requires the publisher's own certificate.

No instruction-copy, no box-behind-icon, no confirm-dialog should be introduced — the three undo toasts are the approved destruction path.

---

## 27. Verification Status & Known Gaps

| Area | Status (code) | Still needs Windows device proof |
|------|---------------|----------------------------------|
| Phase 1+2 (window+engine+drop+single instance) | ✅ |  |
| Transport + OSD deck + Resume + SeekRamp | ✅ | mute/volume inside-bar % over video |
| Playlist panel v4 (header 5 marks, search, drag, Undo) | ✅ | scrollbar thumb on glass, empty NowMark |
| Channel lists v1 (own parser, grouping inference, favs, logo) | ✅ | load 10k-entry list, inference table, 3-strike skip, logo colours |
| Subtitles D14 panel + D16 libass + scrambled password | ✅ code, 0 `flutter analyze` issues (was 15 → 0), log branch added | bearer 401 path, 5xx retry, HTML-body refusal, Already-saved card |
| Lyrics parser + locator | ✅ parser; interactive scroll via `ScrollController` to mpv `position` | real `.lrc` click→seek |
| EQ/Tune panel + per-file learning + auto | ✅ TuneService cache, histogram, presets | curve painter on video |
| Info panel §0 + harvest (⚠ fps/bitrate reads) | ✅ spec-locked, collectors live | engine answers `container-fps`, `demux-bitrate` etc. |
| Mini bar v5 FINAL (always-alive, wheel, pitch) | ✅ | alwaysOnTop + geometry save exactness, close-in-mini → open-in-mini |
| Browser (WebView2 vendored Δ1/2, tabs, address, clear, auto-clear, keep-alive) | ✅ | runtime per-tab lazy, next-startup purge, SaveAs single-dialog, Page colours Light/Dark |
| Remote PC v1.1 (auth, QR, TransportActions, throttle) | ✅ | pairing e2e with APK, 8 KiB cap, paged group contract F2 |
| Remote F (paged groups progressive, lane, logs) | ✅ written here, cross-repo, **not accepted**; soak pending | F1–F6 soak on user PC |
| Theme / Transparency / Placement (enhance.md) | ✅ Phases 1+2+3 implemented | contrast over video, Bottom 24 px, short-window panel scroll |
| Shortcuts registry + Living Map + Alt-Peek | ✅ registry + static map approved, liveness engine in repo | keyboard swallow + mock timelines |
| Associations (HKCU only) + Right-click | ✅ plan+registry+service | registry idempotency, `UserChoice` not touched, enqueue flag |
| Updater (detached swap) | ✅ re-engineered §6.1 | locked DLL swap, `.old` clean, staging reuse |

**Known constraints**

- Flutter `dart analyze`/`test` not run in this workspace (no Windows SDK) — bulk of logic verified via WASM `dart_style` and `git diff --check`; do not mark complete without `flutter test` pass.
- `file_selector` Windows pickers survive — their Windows backend is pure C++ (no Dart win32 constraint surfacing).
- Design previews `design/*` are mocks — do not import; `salu_context.md` is narrative, not binding (follow.md + per-file §7 bindings bind).
- `playlist_imp.md` §10.15 design lock is appearance, not code-production; study-only controls behind the three marks above player are not to be ported.
- `enhance.md` change log explicitly says Phase 3 remains “not implemented” at an older snapshot — code here implements it (appearance_controller_placement), so this file is truth.

---

## 28. File Index — Every Old .md → Where It Lives Now

This table lets you delete the old docs with confidence. **Source** is the file that existed at `hamamun/Salu@4de9b57` root or `design/`.

| Old `*.md` | Lines | What it said | Merged into this file | Code cross-check |
|------------|-------|--------------|-----------------------|------------------|
| `README.md` | 122 | Project pitch, status table, build steps, testing checklist | §1–§3, §25 | `pubspec.yaml` deps match §2 |
| `salu_context.md` | 62 | Phase Execution Tracker + Total Player Outline | §1, §5, §27 | tracker mirrors `phase_*_details` |
| `phase_1_details.md` | 31 | Foundation & Window Framework | §6 | `window_manager` + `main.cpp` |
| `phase_2_details.md` | 31 | Core Media Engine | §7 | `media_kit` player |
| `phase_3_details.md` | 97 | UI & OSC (BackDropFilter auto-hide) | §8 | `controller_panel`, OSD |
| `phase_4_details.md` | 56 | Slide-Out Panels & Menus | §9, §15 | `playlist_panel`, `right_menu` |
| `phase_5_details.md` | 54 | Media Intelligence (DnD, queuing, autoload) | §17 | `drop_handler`, `folder_autoload` |
| `phase_6_details.md` | 41 | Web & Stream Manager (10 URLs, 15 bookmarks) | §10 | `browser_service` + `web/*` |
| `phase_7_details.md` | 37 | Lyrics engine + OpenSubtitles Top-3 | §11, §12 | `lyric_parser`, `subtitle_service` |
| `phase_8_details.md` | 50 | Remote WebSocket (mDNS sketch, superseded) | §19 (decisions note) | `remote.md` supersedes per its header |
| `phase_9_details.md` | 36 | Branding & About (About → Settings tab) | §4, §6.5, §16 title swap | `about_tab.dart` |
| `follow.md` | 242 | **Hard design contract 8 rules** | §24 verbatim | `salu_icon_button.dart` recipe |
| `outline_transport_osd_resume.md` | 363 | Transport matrix, Stop semantics, SeekRamp, Volume, OSD deck, Resume | §7.3–8.5, §8.4 | `transport_actions`, `seekRamp`, `resume_service` |
| `cc.md` | 727 | Subtitle decisions D1–D17 + 12-file ship list + 5 runtime findings | §11 | Fix notes: libass:true, scrambled pass |
| `fix_notes.md` | 315 | Runtime gaps & re-engineering notes | §11 finding boxes, §27 | `update_installer_windows` sweep |
| `playlist_imp.md` | 2108 | Queue + Playlist Panel spec + §10 M3U Channels (Grouping/Favourites) | §9 | `m3u/*`, `queue_service` |
| `enhance.md` | 228 | Appearance plan (Theme + Transparency + Placement) + Phase logs | §23 | `app_theme`, `overlay_transparency_test` |
| `info.md` | 479 | Info Panel §0 surface + §1–6 inventory + harvest | §14 | `info_collector`, `panel 322×452` |
| `right_item.md` | 427 | Right-click strip concept A (geometry, contract, Info seam) | §15 | `right_menu.dart 30×30/18px` |
| `remote.md` | 1712 | **Remote PC authority v1.1** (QR, auth, TransportActions, snapshots) | §19.1–19.3 | `remote_protocol`, `remote_service` |
| `pc_part.md` | 1447 | Part F large-playlist + grouping parity + soak (not accepted) | §19.4–19.7 | `queue_grouping_cache`, `channel_view_service` |
| `remote_apk_ui.md` | 744 | APK design opinion (separate project) | §19.8 | port note only |
| `remote_opinion.md` | 350 | Alternative Remote UX opinions | §19 discussion | not binding |
| `mini.md` | 279 | Mini bar mode FINAL v5 | §16 | `mini_shell` 488×32 |
| `web.md` | 229 | Built-in Browser (WebView2) locks & checklist | §10 | `third_party/webview_windows` Δ1/2 |
| `lrc.md` | 432 | Lyrics `.lrc` locator/parser/overlay + interactive scroll | §12 | `.lrc` only, `lyric_parser` |
| `eq_imp.md` | 479 | Tune/EQ (10 bands, picture continua, learning) | §13 | `tune_model` `kEqBandFreqs/Widths` |
| `association.md` | 143 | HKCU file assoc + Default Apps + Right-click verbs | §18 | `association_registry` |
| `autoload_imp.md` | 189 | Folder autoload modes & exclusions | §17.2 | `folder_autoload_service` |
| `updater.md` | 508 | Component updater + detached swap §6.1 | §20 | `update_installer_windows.dart` |
| `shortcut.md` | 532 | Shortcut inventory + Registry + Living Map + Alt-Peek Version C | §21 | `shortcut_registry` |
| `design/*/README.md` (6) | ~40 each | Preview runners (python http.server ports) | §3 note | mocks only, not app code |
| `third_party/webview_windows/*.md` (3) | 3 | Vendor provenance (keep) | §10.1 + kept on disk | upstream 0.4.0 `ed81bbe` |

**What was deleted:** the 25 root Markdown files plus `salu_context.md` — all consolidated here.  
**What was kept:** this file `salu.md` (sole handout) + the three `third_party/webview_windows/` Markdowns (vendor/legal) + the six `design/*/README.md` preview runners (mocks). If you want a truly one-file repo, those ten can also be removed — the build does not need them.

---

### Closing note

SALU is one window, one queue, one instance, one deck, one palette. Change the palette, the name, the icon and the extension sets in §4 and you have “the same player, yours.” Everything else — grouping inference, paging, hardware-decode proof, the Stop park and the 5 s Undo — travels with it.

*End of handout. Build it quiet.*
