# SALU

A modern, borderless,  -inspired media player for **Windows 10/11**, built with Flutter and powered by the `mpv` engine (`media_kit`).

![SALU](assets/images/salu_logo.png)

## Status

| Phase | Description | Status |
|-------|-------------|--------|
| 1 | Foundation & Window Framework | ✅ Completed |
| 2 | Core Media Engine | ✅ Completed |
| 3 |  -Style UI & OSC | 🔄 In progress — controller + transport + OSD deck done (see `outline_transport_osd_resume.md`) |
| 4 | Slide-Out Panels & Menus | ⏳ Not started |
| 5 | Media Intelligence | 🔄 In progress — resume memory done |
| 6 | Web & Stream Manager | ⏳ Not started |
| 7 | Advanced Player Tools & Search Logic | ⏳ Not started |
| 8 | Android Remote Server | ⏳ Not started |
| 9 | Branding & About Section | ⏳ Not started |

## What works right now (Phase 1 + 2 + transport pass)

- **Borderless window** — the native Windows title bar is gone; SALU draws its own invisible chrome that fades in when the mouse moves and fades out after 3 seconds of stillness.
- **Custom caption buttons** — Minimize / Maximize / Close rendered with native Segoe Fluent glyphs, with the classic red close-hover. Drag anywhere on the top strip to move the window; double-click it to maximize/restore.
- **Dark theme foundation** — rich dark gray (`#1E1E1E`), Segoe UI Variable typography (system font, falls back to Segoe UI on Windows 10), rounded corners everywhere.
- **mpv engine** — `media_kit` + `libmpv` with **hardware decoding enabled by default** (the active decoder is verified via mpv's `hwdec-current` and logged on playback start).
- **Edge-to-edge video** — aspect-ratio-correct scaling behind the invisible title bar.
- **Drag & drop** — drop a video/audio file to play it instantly, drop multiple files to queue them, drop a **folder** to queue its media, drop an `.srt`/`.ass` onto a playing video to load subtitles.
- **Single instance** — only one SALU window can ever exist. Double-clicking a media file while SALU is open routes the file into the running window instantly.
- **Transport cluster** — the full control row, drawn as SALU's own thin
  marks: Play/Pause · Stop · Previous/Next · Seek backward/forward (hold to
  climb `5 s → 10 s → 15 s…`) · Mute + volume bar (value inside the bar,
  wheel ±5 %). Grouping reads from pitch alone — no boxes, ever.
- **Stop parks the queue** (Stop ≠ Start Over) — the engine releases the
  item, the canvas returns to the logo window, the queue stays loaded and
  Play resumes at the exact position.
- **OSD deck** — one top-center slot: transport flashes (`>> +15s
  01:12:34`), volume/mute cards, and the interactive Resume toast
  (`[>] 12:34 [↻ Restart]`). Transport keys drive the deck without waking
  the chrome.
- **Resume memory** — files pick up where you stopped (per-kind modes in
  Settings → General → Resume), resumed silently with no visible jump;
  closing after a Stop still remembers.
- **Silent keyboard set** — Space, ←→ (ramp seek), ↑↓, M, S, PageUp/PageDown;
  none of it is ever printed in the UI.

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

## Project layout

```
lib/
├── main.dart                     # Engine boot, single instance, window setup
├── theme/app_theme.dart          # Colors, Segoe UI Variable, dark theme
├── core/
│   ├── player_service.dart       # mpv Player + VideoController manager
│   ├── drop_handler.dart         # Drag & drop routing rules
│   └── media_utils.dart          # Media/subtitle/playlist type detection
└── ui/
    ├── screens/
    │   ├── home_screen.dart      # Main canvas, hover logic, drop target
    │   └── video_screen.dart     # Edge-to-edge mpv video canvas
    └── widgets/
        └── custom_title_bar.dart # Invisible hover title bar + caption buttons
```
