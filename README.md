# SALU

A modern, borderless, IINA-inspired media player for **Windows 10/11**, built with Flutter and powered by the `mpv` engine (`media_kit`).

![SALU](assets/images/salu_logo.png)

## Status

| Phase | Description | Status |
|-------|-------------|--------|
| 1 | Foundation & Window Framework | ✅ Completed |
| 2 | Core Media Engine | ✅ Completed |
| 3 | IINA-Style UI & OSC | ✅ Completed |
| 4 | Slide-Out Panels & Menus | ✅ Completed |
| 5 | Media Intelligence | ✅ Completed |
| 6 | Web & Stream Manager | ✅ Completed |
| 7 | Advanced Player Tools & Search Logic | ✅ Completed |
| 8 | Android Remote Server | ✅ Completed |
| 9 | Branding & About Section | ✅ Completed |

## What works right now (Phase 1–9)

- **Borderless window** — the native Windows title bar is gone; SALU draws its own invisible chrome that fades in when the mouse moves and fades out after 3 seconds of stillness.
- **Custom caption buttons** — Minimize / Maximize / Close rendered with native Segoe Fluent glyphs, with the classic red close-hover. Drag anywhere on the top strip to move the window; double-click it to maximize/restore.
- **Dark theme foundation** — rich dark gray (`#1E1E1E`), Segoe UI Variable typography (system font, falls back to Segoe UI on Windows 10), rounded corners everywhere.
- **mpv engine** — `media_kit` + `libmpv` with **hardware decoding enabled by default** (the active decoder is verified via mpv's `hwdec-current` and logged on playback start).
- **Edge-to-edge video** — aspect-ratio-correct scaling behind the invisible title bar.
- **Drag & drop** — drop a video/audio file to play it instantly, drop multiple files to queue them, drop a **folder** to queue its media, drop an `.srt`/`.ass` onto a playing video to load subtitles.
- **Single instance** — only one SALU window can ever exist. Double-clicking a media file while SALU is open routes the file into the running window instantly.
- **Basic transport** — click the video or press <kbd>Space</kbd> to play/pause, with the full OSC now in place (Phase 3).

### Phase 3 · IINA-style UI & OSC

- **Glass OSC** — a floating, blurred (`BackdropFilter`) controller with the timeline, transport (previous / −10s / play-pause / +10s / next), volume + mute, audio/subtitle track pop-ups, PiP, fullscreen, Media Inspector and Quick Settings buttons.
- **Three OSC layouts** — Top-Anchored (default), Floating Bottom, and Fixed Bottom, switchable from Settings → User Interface.
- **Unified auto-hide** — the title bar and OSC fade out together after 3 s of stillness and reappear on mouse movement; they stay put while you hover the OSC, drag the timeline, or keep a panel open.
- **Timeline scrub bar** — click anywhere to seek instantly, drag to scrub, hover for a floating box with a live **video-frame thumbnail** and timestamp (captured by a headless second mpv instance, so playback is never disturbed), with the buffered region drawn.
- **Center play/pause flash** — clicking the video (or pressing <kbd>Space</kbd>) shows a large icon that expands and fades out.
- **OSD indicators** — volume / mute / seek flashes appear top-right and fade after ~1 s without waking the OSC.
- **Media Inspector (HUD)** — toggled via the `i` button or <kbd>I</kbd>: live video/audio codec, resolution, fps, dropped frames, bitrate and hardware-decoder status.
- **Music Mode** — audio-only files switch to an album-art + metadata layout, with the PiP and fullscreen buttons disabled as IINA does.

### Phase 4 · Slide-Out Panels & Menus

- **Right Quick Settings panel** — slides in from the right with Playlist, Video, Audio and Subtitles tabs.
- **Playlist tab** — current queue with the playing item highlighted, add/remove controls, chapter markers (read straight from mpv), and loop (off/single/playlist) + shuffle toggles.
- **Video tab** — 90° rotation steps, horizontal/vertical flip, and aspect-ratio forcing (Auto / 16:9 / 4:3 / 21:9 / 1:1).
- **Audio tab** — volume boost up to 200 %, audio delay/sync, and a 10-band graphic EQ with dynamic presets (music vs video).
- **Subtitles tab** — search & load modal (local load works now; OpenSubtitles results land in Phase 7), vertical position slider, and delay/sync slider.
- **Settings screen** — General, User Interface, Playback, Subtitles, Updates and Key Bindings categories (UI drafted; heavy logic wires up in Phases 5–8).

### Phase 5 · Media Intelligence

- **Intelligent drag & drop** — a media file dropped on the video replaces the queue and plays; dropped on the open **Playlist panel** it is appended without interrupting playback; an `.srt`/`.ass` is attached and enabled instantly; a folder is scanned, queued and started.
- **Smart queuing & folder auto-play** — opening `Episode_1.mp4` silently queues the rest of the folder using **natural sorting** (`Episode_2 … Episode_10`, never `1, 10, 2`), matching only files of the same kind (video vs audio).
- **Sidecar subtitles** — `movie.srt` sitting next to `movie.mp4` loads automatically.
- **Seamless resume** — playback positions are persisted with `shared_preferences`; reopening a file resumes silently (no pop-up) with a *"Resumed from 12:04"* OSD flash. Toggleable in Settings → Playback, along with a "Clear playback history" action.
- **Hardware decoding control** — Settings → Playback exposes `Auto (GPU)` / `Disabled (CPU)`, applied live to the running mpv instance.
- **Exact vs. keyframe seeking** — arrow keys seek by keyframe, <kbd>Shift</kbd> + arrows seek exactly (millisecond `hr-seek`); a Settings toggle flips the default.
- **Persisted preferences** — every setting now survives a restart.
- **Component updater** — Settings → Updates downloads the newest `yt-dlp.exe` from GitHub releases and refreshes the `WebView2Loader.dll` linker into `%APPDATA%/SALU/bin`.

### Phase 6 · Web & Stream Manager

- **Left Library sidebar** — slides in from the left (so it never clashes with the right Quick Settings panel) with two sections: **Saved Streams** and **Web Bookmarks**, each with `+` add and trash delete, and an empty-state message.
- **Persistent library** — up to **10** M3U/network streams and **15** bookmarks stored in `shared_preferences`, with duplicate and limit validation.
- **IPTV / M3U playback** — clicking a saved stream fetches and parses the extended M3U (`#EXTINF` with `group-title`, `tvg-country`, `tvg-language`), loads every channel into the queue, and shows the channel names in the Playlist tab.
- **Massive playlist UI** — playlists past 25 entries unlock a **Clear Playlist** button and a **Group By** dropdown (Category / Country / Language / Flat) with chip filters.
- **Live stream OSC** — when the duration is unknown the timeline is replaced by a **LIVE** badge, the ±10 s buttons disappear, and Previous/Next become Channel Down / Channel Up.
- **Built-in browser** — `webview_windows` (Windows WebView2) with a multi-tab top bar and exactly four navigation actions: **Home, Back, Forward, Close Browser**. Opening another bookmark while the browser is up spawns a new tab. SALU's OSC is hidden in browser mode, and "Close Browser" destroys every controller, clears cache/cookies and frees the RAM.

### Phase 7 · Advanced Player Tools & Search Logic

- **Lyrics engine** — a full `.lrc` parser (multi-stamp lines, `[ti:]/[ar:]/[al:]` metadata, `[offset:±ms]` shift) with **smart matching**: play `song.mp3` and `song.lrc` in the same folder is found and loaded silently.
- **Scrolling Lyrics view** — injected next to the album art in Music Mode: a glass panel that auto-scrolls with the `mpv` position stream, glows the sung line bright white while neighbours dim, pauses auto-follow while you browse, and **seeks to any line you click**. A visibility-off button hides it for the track.
- **OpenSubtitles API integration** — the classic OpenSubtitles **file hash** (size + 64-bit checksum of the first/last 64 KB) plus a filename query are sent to `api.opensubtitles.com/api/v1` with the key from Settings → Subtitles.
- **Top-3 Match search modal** — results split into "Top matches · exact file hash" and "All results", each with a language flag chip, download stats and rating. Clicking a row downloads the `.srt` **directly next to the video under its own base name** (`movie.mp4` → `movie.srt`), loads it into `mpv` instantly and flashes *"Subtitle Downloaded: [Language]"* — and since it's now a sidecar, the Phase 5 loader means it never downloads twice.
- **Smart auto-download** — the Settings toggle pings OpenSubtitles in the background on every video load; a perfect hash match in your default language is fetched and applied silently.
- **Language plumbing** — default-language dropdown (Settings and modal share it), per-language flags, and a "Test connection" key validator.

### Phase 8 · Android Remote Server

- **Local WebSocket server** — `shelf` + `shelf_web_socket` listening on `ws://0.0.0.0:8080` (auto-climbs to a free port), plus a tiny `GET /health` probe for companion apps. New clients get a `hello` + full state snapshot the moment they connect.
- **Command receiver** — JSON actions `play_pause`, `volume_up/down`, `set_volume` (0–200 % incl. boost), `mute_toggle`, `seek_forward/backward`, `seek_to`, `next_track`, `previous_track`, `set_rate` and `get_state`, dispatched straight into `PlayerService`.
- **State broadcaster** — every engine change (`playing`, title, volume, mute, duration…) pushes `{"type":"state", position_ms, duration_ms, …}` to all clients instantly; position ticks are throttled to 4 Hz so scrubs never flood the LAN.
- **mDNS auto-discovery** — a hand-built RFC 6762 broadcaster announces `_salu-remote._tcp.local` (PTR + SRV + TXT + A records) with zero native dependencies, so the future Android app finds the PC without typing an IP.
- **Privacy kill switch** — Settings → Remote *"Enable Remote Control Server"*. OFF means the sockets are closed and there is **zero background network activity**; the status card shows the live port, endpoints and connected-client count.

### Phase 9 · Branding, About & Installer

- **App icon** — `windows/runner/resources/app_icon.ico` compiled from the SALU logo into a multi-resolution icon (16/24/32/48 BMP + 64/128/256 PNG entries) — razor-sharp on taskbar, Start menu, Alt-Tab and window corners.
- **About window** — IINA-style floating modal (Settings → About): the SALU mark, `Version 1.0.0`, the **live `mpv` engine version read from the running player**, and one-tap links to the GitHub repo and every library SALU stands on (mpv, media_kit, yt-dlp, OpenSubtitles, Flutter), with an IINA nod in the credits.
- **Installer** — `windows/installer/SALU.iss` (Inno Setup 6) registers the `SALU.Media` ProgID for 22 common extensions, adds **"Open with SALU"** to the right-click menu and writes `App Paths`, so double-clicking any media file anywhere routes straight into the single-instance window. Uninstalling removes every key.

## Requirements

- Windows 10/11
- [Flutter SDK](https://docs.flutter.dev/get-started/install/windows) **3.27 or newer** (stable channel)
- Visual Studio 2022 with the **Desktop development with C++** workload

## Build & Run

```powershell
flutter pub get
flutter run -d windows
```

Release build:

```powershell
flutter build windows --release
# Output: build\windows\x64\runner\Release\salu.exe
```

> `flutter pub get` regenerates the `windows/flutter/generated_*` plugin glue automatically — no manual steps needed.

Installer (Inno Setup 6 required, see `windows/installer/README.md`):

```powershell
.\windows\installer\build_installer.ps1
# → windows\installer\output\SALU-1.0.0-setup.exe
```

## Testing checklist (Phase 1 + 2)

1. Launch → borderless dark window, centered, min size 800×600.
2. Move the mouse → top chrome fades in; keep still 3 s during playback → fades out.
3. Drag your own `.mp4`/`.mkv` from Explorer onto the window → instant playback.
4. Drag the window edges while playing → video resizes fluidly, no distortion.
5. Check the debug console for `[SALU] hardware decoding: d3d11va` (GPU active).
6. Try launching a second instance / double-clicking another media file → it plays in the existing window instead of opening a new one.

## Testing checklist (Phase 3 + 4)

1. Hover the bottom of the window → the glass OSC fades in; move away and stay still → it fades out with the title bar.
2. Click the timeline anywhere → instant seek; drag → scrub; hover → a floating frame-thumbnail + timestamp preview appears (for video) or a timestamp box (for audio).
3. Click the video / press <kbd>Space</kbd> → center play/pause flash; press <kbd>←</kbd>/<kbd>→</kbd> → "+5 s"/"−5 s" OSD; <kbd>↑</kbd>/<kbd>↓</kbd> → volume OSD; <kbd>M</kbd> mute; <kbd>F</kbd> fullscreen; <kbd>I</kbd> HUD.
4. Play an `.mkv` with multiple audio/subtitle tracks → the track pop-ups list them; "Disable / Off" removes subtitles.
5. Open the right panel (tune icon) → Playlist, Video, Audio, Subtitles tabs work; rotate 90°, flip, force 16:9, raise volume boost, drag the EQ.
6. Play an MP3/FLAC → Music Mode shows album art + metadata.
7. Settings (gear in the panel) → change the OSC layout and watch it re-position live.

## Testing checklist (Phase 5 + 6)

1. Drop `Episode_3.mp4` from a season folder → it plays and the Playlist tab shows the whole folder in natural order.
2. Close and reopen the same file → it resumes silently with a *"Resumed from …"* OSD; turn the toggle off in Settings → Playback and confirm it starts from zero.
3. Open the right panel on the Playlist tab and drop files onto it → they append instead of interrupting playback.
4. Hold <kbd>Shift</kbd> while pressing <kbd>←</kbd>/<kbd>→</kbd> → the OSD reads "· exact".
5. Settings → Playback → switch hardware decoding to *Disabled (CPU)* and check the HUD's decoder line.
6. Settings → Updates → "Check for yt-dlp updates" downloads/updates `%APPDATA%/SALU/bin/yt-dlp.exe`.
7. Open the Library (video-library icon on the OSC) → add an M3U URL → click it → channels populate the Playlist tab; a big list shows the Group By filter, and the OSC shows the LIVE badge.
8. Add a bookmark → click it → the built-in browser opens; add a second bookmark → it opens as a new tab; "Close Browser" returns to the player.

## Testing checklist (Phase 7 + 8 + 9)

1. Play an `.mp3` that has a `song.lrc` next to it → Music Mode shifts and the lyrics panel slides in beside the album art, auto-scrolling with playback; the current line is bright white.
2. Click a later lyric line → audio jumps exactly to its timestamp; scroll the wheel while playing → auto-follow pauses ~6 s, then glides back onto the sung line.
3. Settings → Subtitles → paste an OpenSubtitles.com API key → *Test connection* → OSD confirms. Open a `.mp4`, press the Subtitles-tab **Search & Load Subtitles** → the modal auto-searches; "TOP MATCHES · exact file hash" appears when the file is known to the DB.
4. Click a result → `<video>.srt` appears next to the video, plays instantly on the subtitle track, OSD reads *"Subtitle Downloaded: [Language]"*; reopen the video later → subtitle auto-loads via the sidecar with no download.
5. Enable *Auto-download subtitles on video load* → play a well-known movie file → after a few seconds the subtitle appears with an OSD flash, no clicks.
6. Settings → Remote → toggle **Enable Remote Control Server** → status card shows `ws://<your-LAN-IP>:8080`. From another machine on the Wi-Fi: `curl http://<ip>:8080/health` answers; an mDNS browser (`dns-sd -B _salu-remote._tcp` / Android `multicast_dns`) finds the `_salu-remote._tcp.local` service.
7. Point any WebSocket client at the port and send `{"action":"play_pause"}`, `{"action":"volume_up"}`, `{"action":"seek_forward"}` → SALU reacts live, and `{"type":"state", …}` broadcasts stream back with position/volume updates.
8. Toggle the switch off → port closes (`curl` fails) — zero LAN surface while disabled.
9. Rebuild → the taskbar, window corner and Alt-Tab show the new SALU icon; Settings → **About** → the modal shows `Version 1.0.0` plus the live `mpv` engine line, and every link opens your default browser.
10. `.\windows\installer\build_installer.ps1` → install `SALU-1.0.0-setup.exe`, tick *Open with SALU* → right-click any `.mp4` in Explorer → "Open with SALU" plays it; with SALU already running, double-clicking another file routes into the existing window.

## Project layout

```
lib/
├── main.dart                     # Engine boot, single instance, window setup
├── theme/app_theme.dart          # Colors, Segoe UI Variable, dark theme
├── core/
│   ├── player_service.dart       # mpv Player + VideoController + UI state
│   ├── app_prefs.dart            # Persisted user preferences (shared_preferences)
│   ├── app_info.dart             # Version, links, live mpv build (Phase 9)
│   ├── history_manager.dart      # Playback history + seamless resume
│   ├── smart_queue_service.dart  # Folder scan, sibling queue, sidecar lookup
│   ├── natural_sort.dart         # Human-order sorting (Episode_2 < Episode_10)
│   ├── hwdec_manager.dart        # Hardware-decoding modes → mpv `hwdec`
│   ├── updater_service.dart      # yt-dlp / WebView2 loader updates
│   ├── stream_manager.dart       # Saved M3U streams (10) + bookmarks (15)
│   ├── network_player.dart       # M3U parsing, IPTV queue, grouping
│   ├── audio_presets.dart        # 10-band EQ preset curves
│   ├── thumbnail_service.dart    # Headless mpv → timeline hover frame captures
│   ├── drag_drop_handler.dart    # IINA-style drop rules (zone aware)
│   ├── drop_handler.dart         # Legacy Phase 2 shim → drag_drop_handler
│   ├── lyrics_parser.dart        # .lrc parsing + Music Mode lyrics state (Phase 7)
│   ├── subtitles_api.dart        # OpenSubtitles v1 client + 64-bit file hash
│   ├── language_utils.dart       # Language names + flag chips
│   ├── media_utils.dart          # Media/subtitle/playlist detection + formatting
│   └── remote/                   # Android remote backend (Phase 8)
│       ├── remote_server.dart    # Facade: lifecycle + Settings kill switch
│       ├── websocket_server.dart # shelf + shelf_web_socket server (0.0.0.0:8080)
│       ├── command_handler.dart  # JSON {"action": …} → PlayerService
│       ├── state_broadcaster.dart# Throttled {"type":"state", …} broadcasts
│       └── mdns_broadcaster.dart # Hand-rolled _salu-remote._tcp announcer
└── ui/
    ├── managers/
    │   └── ui_visibility_manager.dart   # Chrome auto-hide state
    ├── screens/
    │   ├── home_screen.dart      # Main canvas + overlay composition + hotkeys
    │   ├── video_screen.dart     # Edge-to-edge mpv video canvas
    │   ├── music_mode.dart       # Album art + metadata + lyrics (Phase 7)
    │   ├── browser_screen.dart   # Built-in WebView2 browser (tabs + nav)
    │   └── settings_screen.dart  # Global settings overlay (incl. Remote tab)
    ├── osc/
    │   ├── osc_panel.dart        # Glass OSC bar (3 layouts)
    │   ├── control_buttons.dart  # Transport, volume, track menus, view modes
    │   ├── timeline_slider.dart  # Scrub bar + floating frame-thumbnail preview
    │   └── osc_bar_anchor.dart   # Shared key for OSC bar geometry
    ├── panels/
    │   ├── right_panel_container.dart   # Slide-out Quick Settings
    │   ├── library_panel.dart           # Left sidebar: streams + bookmarks
    │   └── tabs/                        # playlist / video / audio / subtitle
    ├── modals/
    │   ├── subtitle_search_modal.dart   # OpenSubtitles Top-3 + results flow
    │   └── about_modal.dart             # IINA-style About window (Phase 9)
    └── widgets/
        ├── custom_title_bar.dart # Invisible hover title bar + caption buttons
        ├── center_play_pause.dart# Center-screen play/pause flash
        ├── lyrics_view.dart      # Auto-scrolling synced lyrics panel
        ├── osd_indicator.dart    # Top-right OSD flashes
        └── media_hud.dart        # Media Inspector stats

windows/installer/
├── SALU.iss                      # Inno Setup: file associations + context menu
├── build_installer.ps1           # Release build → setup.exe one-shot
└── README.md                     # What the installer registers and why
```
