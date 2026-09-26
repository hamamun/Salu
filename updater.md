# SALU — Component & Engine Updater (`updater.md`)

**Status:** 📋 Architecture & Implementation Plan  
**Target Platform:** Windows 10/11  
**Key Goal:** Allow SALU to automatically check, download, and update its core external runtime binaries (`WebView2Loader.dll` from NuGet, `libmpv-2.dll`, and `yt-dlp.exe`) safely without requiring a manual reinstall of the entire application.

---

## 1. Components in Scope

| Component | Target File | Upstream Source | Update Mechanism |
| :--- | :--- | :--- | :--- |
| **WebView2 Connector** | `WebView2Loader.dll` | **NuGet** (`Microsoft.Web.WebView2`) | NuGet Flat Container V3 API (download `.nupkg` ZIP, extract `x64/WebView2Loader.dll`) |
| **Media Playback Engine** | `libmpv-2.dll` | Official mpv Windows builds / `media-kit` releases | Release API, download 64-bit archive, extract DLL |
| **Stream Parser & Extractor** | `yt-dlp.exe` | GitHub (`yt-dlp/yt-dlp`) | GitHub Latest Release API, download standalone binary |

---

## 2. Why a Special Swap Mechanism Is Required on Windows

On Windows, when an application is running:
* **Operating System File Lock:** Any loaded `.dll` (`WebView2Loader.dll`, `libmpv-2.dll`, etc.) and the main `.exe` cannot be overwritten or deleted while in use.
* **Solution:** SALU cannot replace its own files mid-execution. It must:
  1. Download and verify the updates in a temporary staging folder (`staging/`).
  2. Launch a tiny, detached updater script (`salu_updater.bat` or standalone helper).
  3. Close SALU cleanly (releasing all file locks).
  4. The updater script copies the new files into the app root.
  5. The updater script relaunches `salu.exe`.

---

## 3. Step-by-Step Architecture Pipeline

```text
[SALU Running]
       │
       ▼
[1. CHECK PHASE]
  ├── Query NuGet API for newest Microsoft.Web.WebView2 version
  ├── Query mpv / media-kit feed for newest libmpv-2.dll build
  └── Query GitHub API for newest yt-dlp release tag
       │
       ▼
[2. COMPARE VERSIONS]
  ├── Read local versions stored in `app_data/versions.json`
  └── If remote version > local version: flag as "Update Available"
       │
       ▼
[3. DOWNLOAD & STAGE]
  ├── Download to temporary directory: `%TEMP%\salu_update\`
  ├── NuGet: download `.nupkg` (ZIP), extract `build/native/x64/WebView2Loader.dll`
  ├── mpv: download archive, extract `libmpv-2.dll`
  ├── yt-dlp: download `yt-dlp.exe`
  └── Verify integrity / checksums / file sizes
       │
       ▼
[4. USER PROMPT / NOTIFICATION]
  └── In-app card: "Updates ready to install (WebView2Loader / mpv / yt-dlp). Restart SALU?"
       │
       ▼
[5. RESTART & SWAP PROCESS]
  ├── Create `salu_updater.bat` in `%TEMP%\salu_update\`
  ├── Spawn script detached: `cmd.exe /c salu_updater.bat`
  └── SALU exits: `exit(0)`
       │
       ▼
[6. DETACHED UPDATER SCRIPT]
  ├── Loop-wait for `salu.exe` process to terminate
  ├── Backup existing DLLs to `backup/`
  ├── Copy new files from `%TEMP%\salu_update\` to SALU installation root
  ├── If copy succeeds: clean up staging directory
  ├── If copy fails: restore from `backup/`
  └── Launch `salu.exe`
```

---

## 4. NuGet API Deep-Dive (How SALU talks to NuGet)

NuGet is a RESTful open API. Every NuGet package is a standard ZIP file with the `.nupkg` extension.

### Step 1: Query Latest Version
* **Endpoint:**  
  `GET https://api.nuget.org/v3-flatcontainer/microsoft.web.webview2/index.json`
* **Response:**
  ```json
  {
    "versions": [
      "1.0.864.35",
      "1.0.1210.39",
      "1.0.2903.40",
      "1.0.3065.39"
    ]
  }
  ```
* **Logic:** SALU filters out pre-release tags (e.g. `-prerelease`) and selects the highest stable version string.

### Step 2: Download Package
* **Package URL:**  
  `https://api.nuget.org/v3-flatcontainer/microsoft.web.webview2/{version}/microsoft.web.webview2.{version}.nupkg`
* **Extraction:**  
  Using Dart's built-in archive handling, SALU opens the `.nupkg` and extracts:
  * `build/native/x64/WebView2Loader.dll` → copied to `%TEMP%\salu_update\WebView2Loader.dll`

---

## 5. File System & Staging Layout

### Staging Directory: `%TEMP%\salu_update\`
```text
%TEMP%\salu_update\
├── WebView2Loader.dll       (New loader extracted from NuGet)
├── libmpv-2.dll             (New mpv engine)
├── yt-dlp.exe               (New streaming parser)
├── manifest.json            (Target files, paths, and new versions)
└── salu_updater.bat         (Swap script)
```

### Application Directory:
```text
C:\Program Files\Salu\ (or user folder)
├── salu.exe
├── flutter_windows.dll
├── WebView2Loader.dll       <-- Overwritten during restart
├── webview_windows_plugin.dll
├── libmpv-2.dll             <-- Overwritten during restart
├── yt-dlp.exe               <-- Overwritten during restart
└── versions.json            <-- Keeps track of current component versions
```

---

## 6. The Detached Windows Swap Script (`salu_updater.bat`)

When the user confirms "Restart & Update", SALU writes and triggers this script:

```bat
@echo off
setlocal enabledelayedexpansion

set SALU_PID=%1
set TARGET_DIR=%~2
set STAGING_DIR=%~3
set SALU_EXE=%TARGET_DIR%\salu.exe

:: 1. Wait for SALU to exit and release file locks
:WAIT_LOOP
tasklist /fi "PID eq %SALU_PID%" | findstr /i "%SALU_PID%" >nul
if not errorlevel 1 (
    timeout /t 1 /nobreak >nul
    goto WAIT_LOOP
)

:: Extra 1s safety margin for DLL handles to release completely
timeout /t 1 /nobreak >nul

:: 2. Create backup
if not exist "%TARGET_DIR%\backup" mkdir "%TARGET_DIR%\backup"
if exist "%STAGING_DIR%\WebView2Loader.dll" copy /y "%TARGET_DIR%\WebView2Loader.dll" "%TARGET_DIR%\backup\" >nul
if exist "%STAGING_DIR%\libmpv-2.dll" copy /y "%TARGET_DIR%\libmpv-2.dll" "%TARGET_DIR%\backup\" >nul
if exist "%STAGING_DIR%\yt-dlp.exe" copy /y "%TARGET_DIR%\yt-dlp.exe" "%TARGET_DIR%\backup\" >nul

:: 3. Copy new files
copy /y "%STAGING_DIR%\*.*" "%TARGET_DIR%\" >nul
if errorlevel 1 (
    :: Rollback on failure
    copy /y "%TARGET_DIR%\backup\*.*" "%TARGET_DIR%\" >nul
    msg * "SALU Update failed. Previous files restored."
    start "" "%SALU_EXE%"
    exit /b 1
)

:: 4. Update versions file
copy /y "%STAGING_DIR%\manifest.json" "%TARGET_DIR%\versions.json" >nul

:: 5. Clean up staging folder
rmdir /s /q "%STAGING_DIR%"
rmdir /s /q "%TARGET_DIR%\backup"

:: 6. Relaunch SALU
start "" "%SALU_EXE%"
exit /b 0
```

---

## 7. Code Structure Plan in Dart

New files in `lib/core/updater/`:

```
lib/core/updater/
├── updater_service.dart         # Main coordinator (Check / Download / Trigger Restart)
├── nuget_client.dart            # Handles NuGet API requests & .nupkg unzipping
├── github_updater_client.dart   # Handles yt-dlp / mpv GitHub release queries
├── update_manifest.dart         # Model for version comparison & pending updates
└── update_installer_windows.dart# Generates bat script, executes Process.start detached, exits app
```

### UI Integration:
1. **Settings → Updates Tab (`lib/ui/widgets/settings_dialog.dart`):**
   * **Automatic Update Check Frequency:**
     Selection tiles (`_OptionTile`):
     * **Off:** Only checks when clicking "Check now".
     * **Daily:** Checks once every 24 hours.
     * **Weekly (Default):** Checks once every 7 days.
     * **Monthly:** Checks once every 30 days.
   * **Action Button:**
     * Clean button below: `[ Check now ]`

2. **Persistence & Scheduled Checks:**
   * `SettingsService.updateCheckFrequency`: `UpdateCheckFrequency.off | daily | weekly | monthly`
   * `SettingsService.lastUpdateCheckTime`: Stored as milliseconds epoch in `shared_preferences`.
   * On app startup, if interval has elapsed (and not `off`), runs silent check in background.

---

## 8. SALU-Style Compact Update Modal Dialog

When the user clicks `[ Check now ]` in Settings → Updates, a SALU-styled compact dialog appears centered over a dimmed glass backdrop.

### Layout Flow:

```text
┌────────────────────────────────────────────────────────┐
│  SALU Updater                                        ✕ │
├────────────────────────────────────────────────────────┤
│                                                        │
│  [State 1: Checking]                                   │
│  Checking for updates...                               │
│  Connecting to NuGet and GitHub release feeds...       │
│                                                        │
├────────────────────────────────────────────────────────┤
│                                                        │
│  [State 2A: Update Found]                              │
│  New updates are available:                            │
│                                                        │
│  Component        Installed       Latest on Web        │
│  ───────────────────────────────────────────────       │
│  WebView2Loader   1.0.1210.39  →  1.0.3065.39          │
│  MPV Engine       0.38.0          0.38.0 (Current)     │
│  yt-dlp           2024.08.06   →  2024.09.20           │
│                                                        │
│  [ Cancel ]                             [ Update ]     │
│                                                        │
├────────────────────────────────────────────────────────┤
│                                                        │
│  [State 2B: No Update Found (All Up to Date)]          │
│  ✓ All components are up to date!                      │
│                                                        │
│  Component        Installed       Latest on Web        │
│  ───────────────────────────────────────────────       │
│  WebView2Loader   1.0.1210.39     1.0.1210.39          │
│  MPV Engine       0.38.0          0.38.0               │
│  yt-dlp           2024.08.06      2024.08.06           │
│                                                        │
│  Last checked: Just now                                │
│                                                        │
│                                            [ Close ]   │
│                                                        │
├────────────────────────────────────────────────────────┤
│                                                        │
│  [State 2C: Downloading with Live Progress Bar]        │
│  Downloading components...                             │
│                                                        │
│  Fetching: WebView2Loader.dll (1.2 MB / 2.8 MB)        │
│  [████████████████████░░░░░░░░░░░░░░] 45%              │
│                                                        │
│  Overall: 1 of 2 downloaded                            │
│                                            [ Cancel ]  │
│                                                        │
├────────────────────────────────────────────────────────┤
│                                                        │
│  [State 2D: Download Finished & Prompt Restart]        │
│  ✓ Downloads Complete!                                 │
│                                                        │
│  All updates are staged and ready to be applied.       │
│  SALU will restart, install the new files, and reopen. │
│                                                        │
│  [ Restart Later ]                  [ Restart Now ]    │
└────────────────────────────────────────────────────────┘
```

### Action Logic:
* **If User selects `[ Update ]`:**
  1. Dialog transitions immediately to **State 2C: Downloading with Live Progress Bar**.
  2. Uses Dart HTTP stream listening (`response.stream.listen`) tracking `downloadedBytes / totalBytes` to render a smooth linear progress bar and speed/MB status.
  3. Archives (`.nupkg` / `.zip`) are extracted to `%TEMP%\salu_update\`.
  4. Once all components are verified, dialog transitions to **State 2D: Prompt Restart**.
* **If User selects `[ Restart Now ]`:**
  * Spawns `salu_updater.bat` detached with SALU's PID.
  * SALU exits cleanly (`exit(0)`), files are swapped, and SALU relaunches within 1–2 seconds.
* **If User selects `[ Restart Later ]`:**
  * Staged files remain in `%TEMP%\salu_update\`.
  * SALU will apply them on next normal app close/relaunch, or prompt again later.
* **If User selects `[ Cancel ]` or `[ ✕ ]`:**
  * If cancelled before download starts: modal closes immediately.
  * If cancelled mid-download: active stream is aborted, staging folder is purged, and modal closes cleanly.
* **If User selects `[ Close ]` (when up to date):**
  * Dialog dismisses cleanly. Settings screen updates "Last checked" timestamp.

### State 2: Checking in Progress
* The button is disabled and displays a subtle activity indicator: `"Checking for updates..."`.

### State 3: Update Available
* Header: **"Update Available"**.
* Specific components with newer versions are highlighted with an upgrade tag (e.g. `v1.0.1210.39 → v1.0.3065.39`).
* Action button transforms into `[Download & Install]` or `[Restart to Apply]` once downloaded in the background.

### State 4: Network Error / Offline
* Muted, non-blocking warning: *"Unable to connect to update servers. Check your internet connection."*
* Existing files remain untouched and fully functional.

---

## 9. Safety & Rollback Guards

1. **Architecture Guard:** Always check that the downloaded DLL is 64-bit (`x64`) so 32-bit (`x86`) files are never placed into a 64-bit SALU installation.
2. **Atomic Rollback:** If any file fails to copy during `salu_updater.bat`, the `backup/` directory restores the old files immediately and launches SALU safely.
3. **No Interruption of Playback:** Updates download quietly in the background without affecting playing media or web browsing tabs.
4. **Offline Resilience:** If internet drops or NuGet API fails, SALU logs a gentle warning and continues normal operations without crashing.
