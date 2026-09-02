# SALU - Master Context & State

## 📍 Phase Execution Tracker
*This section tracks the build progress. Each phase will have its own detailed `.md` file during execution.*

- [x] **Phase 1: Foundation & Window Framework** ✅ (Setup `pubspec.yaml`, `window_manager` for borderless edge-to-edge window, custom title bar, Segoe UI Variable font, dark theme base).
- [x] **Phase 2: Core Media Engine** ✅ (Integrate `media_kit`, initialize `mpv`, basic video rendering, hardware acceleration check).
- [x] **Phase 3: The IINA-Style UI & OSC** ✅ (Top-anchored glass controller using `BackdropFilter` [default; also Floating/Fixed Bottom], auto-hide logic, timeline with frame-thumbnail hover preview, play/pause animations, OSD indicators).
- [x] **Phase 4: Slide-Out Panels & Menus** ✅ (Right panel for Quick Settings [Playlist/Video/Audio/Subtitles], slide-out Playlist/Chapter menus).
- [x] **Phase 5: Media Intelligence** ✅ (Drag-and-drop files/folders/srt, smart queuing/folder auto-play, multi-audio/subtitle track selector).
- [x] **Phase 6: Web & Stream Manager** ✅ (`webview_windows` implementation for built-in browser, saving 10 M3U URLs and 15 Bookmarks using `shared_preferences`, sidebar library UI).
- [x] **Phase 7: Advanced Player Tools & Search Logic** ✅ (`.lrc` lyrics engine with interactive auto-scroll synced to playback, OpenSubtitles.com v1 API integration with classic 64-bit file hashing, Top-3 Best-Matches search modal, and silent sidecar auto-download).
- [x] **Phase 8: Android Remote Server** ✅ (`shelf` + `shelf_web_socket` server on `ws://0.0.0.0:8080`, JSON command interpreter wired into `PlayerService`, throttled player-state broadcaster, dependency-free mDNS `_salu-remote._tcp` auto-discovery, and a Settings → Remote kill switch that shuts the surface down completely. *Note: the Android app itself is built separately after SALU is completed*).
- [x] **Phase 9: Branding & About Section** ✅ (multi-resolution `app_icon.ico` compiled from the SALU logo, IINA-style About modal with the live `mpv` version and open-source credits/links, Inno Setup installer registering file associations + "Open with SALU", version bumped to `1.0.0`).

---

## 📖 Total Player Outline (For AI Context)
*This section contains the complete DNA of SALU. Any AI reading this will understand the entire scope, rules, and architecture of the project at a glance.*

### 1. Identity & Architecture
*   **App Name:** SALU
*   **Platform:** Windows 10/11
*   **Language:** Flutter (Dart)
*   **Core Engine:** `media_kit` (wraps Libmpv2)
*   **Window Manager:** `window_manager` (for borderless UI, removing default Windows frames)
*   **Data Storage:** `shared_preferences` (lightweight, no heavy databases)
*   **OS Integration:** Strictly **Single Instance** (only one app window allowed). App will accept incoming file path arguments so double-clicking media anywhere in Windows instantly plays it in the active SALU window.
*   **Exceptions:** NO hardware media key support. NO pure native Windows frosted glass (using Flutter's `BackdropFilter` instead).

### 2. Design & UI Rules (IINA-Inspired)
*   **Window:** 100% borderless, video stretches edge-to-edge. Invisible window controls (Close/Min/Max) appear only on mouse hover at the top.
*   **Colors:** Deep dark grays (`#121212` or `#1E1E1E`), NOT pure black. Smooth rounded corners on all UI elements.
*   **Typography:** Strictly **Segoe UI Variable**.
*   **Icons:** Thin, modern, monochromatic outline icons.
*   **On-Screen Controller (OSC):** Floating panel near bottom. Blurred background (in-app glass effect). Auto-hides on inactivity. Video thumbnails on timeline hover.
*   **Animations:** Smooth fade-in/out for play/pause icons in screen center. Temporary minimalist OSD text/icons for volume/speed changes.

### 3. Core Playback Features
*   **Engine Specs:** Hardware accelerated by default. Supports PiP, instant resume, and unlimited playback history.
*   **Drag & Drop:** Drop a video to play instantly. Drop a `.srt` to add subtitles. Drop a folder to create a playlist.
*   **Smart Queuing:** Opening "Episode 1" auto-queues the rest of the folder silently.
*   **Track Selection:** Native reading of embedded multi-audio tracks and multi-subtitle tracks.

### 4. Right Panel (Quick Settings)
*   Slides out from the right with a blurred background.
*   **Video Tab:** 90-degree rotation, horizontal/vertical flip, aspect ratio forcing, cropping.
*   **Audio Tab:** 10-Band Graphic EQ with presets, volume boost.
*   **Subtitle Tab:** Position slider (up/down screen), style overrides (font/color/size).

### 5. Unique SALU Features (Not in IINA)
*   **Web Browser:** Built-in `webview_windows` screen to navigate streaming sites directly inside SALU.
*   **Stream Library:** A saved list of up to 10 M3U URLs and 15 Web Bookmarks, stored instantly via `shared_preferences`.
*   **Lyrics View:** Scrolling, animated text view synced to audio/music.
*   **Android Remote Capability (Windows Backend):** A built-in WebSocket server (`ws://0.0.0.0`) that runs in the background. It broadcasts the PC's location via mDNS (Auto-Discovery) and listens for JSON commands.

---

## 📱 Future Project: Android Companion App (Hint for AI)
*Once the Windows application is completed, a separate Flutter project will be initiated to build the Android Remote `.apk`.*
*   **Tech Stack:** Flutter (Dart) for zero learning curve and code reusability (copying colors/fonts from Windows).
*   **Architecture:** No PWA or WebView. It will be a true standalone native `.apk`.
*   **Communication:** It will use `web_socket_channel` to maintain a permanent, zero-latency connection to the Windows app, and `multicast_dns` to automatically find the Windows PC on the Wi-Fi without IP typing.