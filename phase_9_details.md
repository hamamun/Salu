# Phase 9: Branding, About Section & Final Polish
**Status:** ⏳ Not Started

## 🎯 Goal
Apply the final coat of paint. By the end of this phase, SALU will have a dedicated, beautiful "About" window mimicking  , fully compiled Windows `.ico` assets, and all final branding applied to the app.

## 🛠️ Step-by-Step Execution Plan

### Step 1: The App Icon & Branding (`windows/runner/resources/app_icon.ico`)
*   Replace the default Flutter icon with the official SALU logo.
*   Compile the logo into a multi-resolution `.ico` file so it looks incredibly sharp on the Windows Taskbar, Start Menu, and Desktop.

### Step 2: The "About" Window UI (`lib/ui/modals/about_modal.dart`)
*   Create a clean, dedicated pop-up modal (accessed via an "Info" or "About" menu button in the Global Settings).
*   **Layout:**
    *   Center the official SALU logo prominently at the top.
    *   Display the current app version (e.g., `Version 1.0.0`).
    *   Display the underlying `mpv` engine version pulled directly from `media_kit`.

### Step 3: Credits & Links
*   Inside the About window, include clean text links to:
    *   The GitHub repository.
    *   Acknowledgments/Credits for the open-source libraries used (`mpv`, `yt-dlp`, OpenSubtitles).

### Step 4: Windows OS Integration & Installer (Inno Setup / MSIX)
*   **File Association:** Write the Windows Registry scripts required during app installation so that SALU registers itself as a native media player for standard formats (`.mp4`, `.mkv`, `.avi`, `.mp3`, etc.).
*   **Context Menu:** Inject the registry keys so SALU permanently appears in the Windows right-click menu ("Open with SALU").
*   *Note: This ensures that when the user installs SALU, double-clicking any media file anywhere on their PC automatically routes into the Single-Instance architecture built in Phase 1.*