<div align="center">
  <img src="assets/images/salu_logo.png" alt="SALU Logo" width="84" />
  <h1>SALU</h1>
  <p><strong>A borderless, modern multimedia player for Windows 10 &amp; 11 — powered by mpv.</strong></p>

  <p>
    <a href="https://hamamun.github.io/Salu/"><strong>Project Website &amp; Interactive Preview</strong></a>
    &nbsp;·&nbsp;
    <a href="salu.md">Architecture Handout</a>
    &nbsp;·&nbsp;
    <a href="https://github.com/hamamun/Salu/releases">Releases</a>
  </p>

  <p>
    <img src="https://img.shields.io/badge/platform-Windows%2010%20%2F%2011%20x64-1E1E1E?style=flat-square&logo=windows&logoColor=4C9EEB" alt="Windows 10/11 x64" />
    <img src="https://img.shields.io/badge/framework-Flutter%203.47.5-1E1E1E?style=flat-square&logo=flutter&logoColor=4C9EEB" alt="Flutter" />
    <img src="https://img.shields.io/badge/engine-libmpv%20%2B%20WebView2-1E1E1E?style=flat-square" alt="libmpv + WebView2" />
    <img src="https://img.shields.io/badge/version-0.1.0-1E1E1E?style=flat-square" alt="Version 0.1.0" />
  </p>
</div>

---

## Overview

SALU brings local video, audio, subtitles, IPTV playlists, a built-in browser, and a phone remote together in one quiet, borderless Windows window. Chrome fades away when you watch, shortcuts work silently without clutter, and every file remembers where you left off.

**Project Showcase:** [hamamun.github.io/Salu](https://hamamun.github.io/Salu/)

## Highlights

- **Borderless One-Window UI** — Auto-hiding fused glass chrome, fullscreen cursor hiding, Default Dark / Light / System themes, 0–40% overlay transparency, and flexible controller placement.
- **mpv Playback & Resume Memory** — Hardware-decoded playback (`media_kit` / `libmpv-2.dll`), strict single-instance handling, natural folder sorting, and **Stop-parks-queue** (Play resumes at the exact stopped second).
- **32 px Mini Bar Mode** — Collapses the player into a `488 × 32 px` always-on-top floating bar with a top-edge seek meter and volume dial.
- **10-Band Tune & Auto EQ** — 13 audio presets + 4 video presets, picture looks, aspect ratio stops, speed control (`0.5×–3×`), and per-file Auto Tone memory.
- **50,000+ M3U / IPTV Channels** — Incremental off-thread parser with automatic `Flat` / `Category` / `Country` / `Language` grouping, per-provider favourites, and 3-strike dead-channel skip.
- **Subtitles & Synced Lyrics** — OpenSubtitles hash & text search with auto-download, native `libass` rendering, per-file subtitle sync (`±5s`), and `.lrc` click-to-seek lyrics with cover art.
- **Built-in Edge WebView2 Browser** — Lazy tabs, bookmarks, downloads shelf, pop-up control, and live keep-alive when switching between `Player` and `Web` modes.
- **QR Phone Remote (LAN)** — Local WebSocket server (`port 7258`) with instant QR pairing and byte-paged playlist browsing — no cloud or account required.
- **Living Map & Alt-Peek** — Interactive miniature player in **Settings → Shortcuts**, plus hold `Alt` to peek key bindings on hover.

## Quick Start (Build from Source)

### Requirements
- **OS:** Windows 10 (1809+) or Windows 11 (x64)
- **SDK:** Flutter **3.47.5** (Dart `>=3.4.0`)
- **Toolchain:** Visual Studio 2022 (**Desktop development with C++**) + Windows 11 SDK
- **Packaging (optional):** [Inno Setup 6](https://jrsoftware.org/isdl.php) (`ISCC.exe`) for building the Windows installer

### Run & Build

```powershell
git clone https://github.com/hamamun/Salu.git
cd Salu

flutter pub get
flutter run -d windows
```

Build a release bundle or standalone Windows installer (`dist\SALU-Setup-0.1.0.exe`):

```powershell
# Release binary (build\windows\x64\runner\Release\salu.exe)
flutter build windows --release

# One-command clean rebuild, tests, and Inno Setup installer
powershell -ExecutionPolicy Bypass -File tools\build_installer.ps1
```

Run checks:

```powershell
flutter analyze
flutter test
dart format --set-exit-if-changed lib test
```

## Repository Layout

| Path | Purpose |
|------|---------|
| `lib/` | Application core services, mpv/remote/web/tune engines, and UI shell |
| `third_party/webview_windows/` | Vendored WebView2 plugin with PreferredColorScheme & Save-As deferrals |
| `windows/` | Win32 Flutter runner, app icon, and CMake setup |
| `tools/` | `build_installer.ps1` / `build-installer.cmd` one-command release packager |
| `salu.iss` | Inno Setup 6 installer script (HKCU Open-With & clean uninstall) |
| `docs/` | GitHub Pages showcase site ([hamamun.github.io/Salu](https://hamamun.github.io/Salu/)) |
| `salu.md` | Complete single-file architecture & engineering reference |

---

<p align="center">
  <sub>created by HAM · Built with Flutter, libmpv, media_kit &amp; WebView2</sub>
</p>
