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
| 5 | Media Intelligence | ⏳ Not started |
| 6 | Web & Stream Manager | ⏳ Not started |
| 7 | Advanced Player Tools & Search Logic | ⏳ Not started |
| 8 | Android Remote Server | ⏳ Not started |
| 9 | Branding & About Section | ⏳ Not started |

## What works right now (Phase 1–4)

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

## Project layout

```
lib/
├── main.dart                     # Engine boot, single instance, window setup
├── theme/app_theme.dart          # Colors, Segoe UI Variable, dark theme
├── core/
│   ├── player_service.dart       # mpv Player + VideoController + UI state
│   ├── app_prefs.dart            # In-memory user preferences (OSC layout…)
│   ├── audio_presets.dart        # 10-band EQ preset curves
│   ├── thumbnail_service.dart    # Headless mpv → timeline hover frame captures
│   ├── drop_handler.dart         # Drag & drop routing rules
│   └── media_utils.dart          # Media/subtitle/playlist detection + formatting
└── ui/
    ├── managers/
    │   └── ui_visibility_manager.dart   # Chrome auto-hide state
    ├── screens/
    │   ├── home_screen.dart      # Main canvas + overlay composition + hotkeys
    │   ├── video_screen.dart     # Edge-to-edge mpv video canvas
    │   ├── music_mode.dart       # Album art + metadata (audio-only files)
    │   └── settings_screen.dart  # Global settings overlay
    ├── osc/
    │   ├── osc_panel.dart        # Glass OSC bar (3 layouts)
    │   ├── control_buttons.dart  # Transport, volume, track menus, view modes
    │   ├── timeline_slider.dart  # Scrub bar + floating frame-thumbnail preview
    │   └── osc_bar_anchor.dart   # Shared key for OSC bar geometry
    ├── panels/
    │   ├── right_panel_container.dart   # Slide-out Quick Settings
    │   └── tabs/                        # playlist / video / audio / subtitle
    ├── modals/
    │   └── subtitle_search_modal.dart   # Local load + OpenSubtitles placeholder
    └── widgets/
        ├── custom_title_bar.dart # Invisible hover title bar + caption buttons
        ├── center_play_pause.dart# Center-screen play/pause flash
        ├── osd_indicator.dart    # Top-right OSD flashes
        └── media_hud.dart        # Media Inspector stats
```
