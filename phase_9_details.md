# Phase 9: Branding, About Section & Final Polish
**Status:** ⏳ Not Started

## 🎯 Goal
Apply the final coat of paint. By the end of this phase, SALU will have a dedicated, beautiful "About" window mimicking  , fully compiled Windows `.ico` assets, and all final branding applied to the app.

## 🛠️ Step-by-Step Execution Plan

### Step 1: The App Icon & Branding (`windows/runner/resources/app_icon.ico`)
*   Replace the default Flutter icon with the official SALU logo.
*   Compile the logo into a multi-resolution `.ico` file so it looks incredibly sharp on the Windows Taskbar, Start Menu, and Desktop.

### Step 2: The "About" Window UI — **SHIPPED as Settings → About (2026-09-28)**

The owner moved the About page from a standalone modal to a tab in the
Settings dialog (`lib/ui/widgets/about_tab.dart`, a `part of` the settings
dialog — the `associations_tab.dart` pattern), right of the Shortcuts tab.
Layout:

*   **Identity block** — the SALU logo (44 px, compact for the 620 px window), `SALU`, `Version 0.1.0`, and one line: "A borderless media player for Windows."
*   **The player** — the gist: one borderless window, one instance, mpv underneath.
*   **What only SALU does** — Stop parks the queue · the mini bar · the EQ follows the file · your phone is the remote · subtitles and lyrics · resume memory · a quiet keyboard · the Living Map.
*   **Channels** — the m3u gist (SALU's own incremental parser, no cap, group-by, per-provider favourites, the inert timeline's still soft light).
*   **The browser** — tabs beside the video, and the safety line: Windows' own Edge engine (WebView2), no custom engine.
*   **Engine** — live values: mpv's own version (read once via `PlayerService.readEngineVersion()`), the active decoder (the `activeHwdec` notifier the Info panel reads), platform, storage.
*   **Credits** — Source (`github.com/hamamun/Salu`, opens in SALU's own browser) · Built with (mpv · media_kit · Flutter · WebView2).
*   **Signature** — `created by HAM`, pinned at the bottom in `AppColors.whisper` (white at ~20 %): there if you look for it, gone if you don't.

### Step 3: Credits & Links
*   Inside the About window, include clean text links to:
    *   The GitHub repository.
    *   Acknowledgments/Credits for the open-source libraries used (`mpv`, `yt-dlp`, OpenSubtitles).

### Step 4: Windows OS Integration & Installer (Inno Setup / MSIX)
*   **File Association:** Write the Windows Registry scripts required during app installation so that SALU registers itself as a native media player for standard formats (`.mp4`, `.mkv`, `.avi`, `.mp3`, etc.).
*   **Context Menu:** Inject the registry keys so SALU permanently appears in the Windows right-click menu ("Open with SALU").
*   *Note: This ensures that when the user installs SALU, double-clicking any media file anywhere on their PC automatically routes into the Single-Instance architecture built in Phase 1.*