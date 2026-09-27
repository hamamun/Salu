# SALU — Component & Engine Updater (`updater.md`)

**Status:** ✅ Implemented (2026-09-26) · 🩺 swap re-engineered (2026-09-27,
§6.1) — `lib/core/updater/` + Settings → Updates tab + the updater modal
(`lib/ui/widgets/update_dialog.dart`).
Architecture below stands as the design record. The hand-off in §6 is NOT the
sketch it started as: `saluUpdaterScript` in `update_installer_windows.dart` is
the source of truth for the script (the copy in §6.2 is the annotated shape, not
a second authority), and §6.1 records why.  
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
  2. Launch a tiny, detached updater script (`salu_swap.bat`, §6).
  3. Close SALU cleanly (`exit(0)`), releasing the file locks.
  4. The updater script renames each old file aside, copies the new one in,
     and puts the old one back if anything failed — it *never* waits for a
     process id (§6.1).
  5. The updater script relaunches the executable SALU told it about, after a
     pause long enough for the single-instance mutex to close (§6.5).

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
  ├── Guards: writable install root? no swap already in flight? (§6.4)
  │     └── refused  -> say why in the modal, keep SALU running, keep staging
  ├── Write `%TEMP%\salu_swap.bat` (outside the staging folder it cleans)
  ├── Spawn detached: `cmd.exe /c salu_swap.bat`, job in the environment
  └── SALU exits: `exit(0)`  (dev build: no relaunch asked for — §10)
       │
       ▼
[6. DETACHED UPDATER SCRIPT]              (§6.1: no pid poll, no new windows)
  ├── Re-run itself under `start /min` so no console tool flashes a window
  ├── For each component: rename the current file aside, copy the staged one
  │     ├── busy? pause 1 s and try the whole set again (up to 10 times)
  │     └── out of attempts? rename every swapped file back, keep staging
  ├── All swapped: promote manifest.json -> versions.json, log "swap OK"
  └── Clean staging, pause for the single-instance mutex, launch the exe (§6.5)
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
└── manifest.json            (Target files, paths, and new versions)

%TEMP%\                        ← the swap's own files, ONE LEVEL UP
├── salu_swap.bat            (Swap script — never inside staging, see §6.3)
├── salu_swap.log            (Both outcomes; survives either way)
└── salu_swap.lock           ("A swap is in flight" marker, §6.4)
```

The swap script deliberately lives **beside** `%TEMP%\salu_update\` and not
inside it, because step 5 deletes that folder: a batch file that removes the
folder it is running from can stop reading itself halfway through, and the
lines after it (the relaunch among them) silently never run.

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

## 6. The Detached Windows Swap Script (`salu_swap.bat`)

**The authority for this script is `saluUpdaterScript` in
`lib/core/updater/update_installer_windows.dart`** — one const string, CRLF,
ASCII only (cmd reads a `.bat` in the console's OEM codepage, so a non-ASCII
byte echoes as mojibake). What follows is the shape and the reasons, not a
second copy to keep in sync.

### 6.1 The two rules, learned on 2026-09-27

The first version of the hand-off worked — and filled the screen with flashing
black cmd windows, one of them stuck on a title like `findstr /i "21304"`,
until the user pressed Ctrl+C into it. Two rules came out of that, and the
tests in `test/update_installer_windows_test.dart` enforce both:

1. **The swap must create no console windows.** SALU starts the script with
   `ProcessStartMode.detached`, which on Windows means *no console at all* —
   and every console tool a console-less process launches then gets a
   brand-new window of its own. A loop that ran `tasklist | findstr` per pass
   was therefore a loop that opened a window per pass. The fix is step 0: the
   script re-runs itself under `start "" /min cmd.exe /c "%~f0"`, so the whole
   run owns ONE minimized console that every tool below inherits. (A tool
   with a console also behaves properly: `timeout`, the other half of the old
   bug, refuses to sleep without one and errors out instantly — turning a
   1-second wait into a loop running as fast as the CPU can, printing a new
   window every pass and showing its "Press CTRL+C to quit" prompt.)
   window every pass and showing its "Press CTRL+C to quit" prompt.)

   Belt and braces: `copy`, `ren`, `del`, `rd`, `echo`, `set`, `if`, `goto`,
   `call` and `title` are cmd **internal** commands — they start no process,
   so they cannot open a window. The only external tool the script uses is
   `ping` (the pause), so even if `start /min` were ever unavailable the
   common path — swap on the first attempt, no relaunch asked for — spawns
   **nothing at all**.
2. **The swap must never wait on a process id.** `tasklist /fi "PID eq X" |
   findstr X` is not a reliable liveness test: the digits can match another
   process's row, and Windows recycles pids — while the poll itself is spawning
   processes by the thousand. So the script waits on the *file* instead, which
   is the only fact it needs: it renames the current file aside, and a rename
   is exactly what Windows still permits while SALU is on its way out (a loaded
   DLL is opened with share-delete; its owner keeps its own mapping). A busy
   file simply makes the attempt fail, and the attempt repeats one second later
   — `ping -n 2 -w 1000 127.0.0.1` being the pause that needs no keyboard.
   Ten attempts, ten seconds, then everything goes back as it was.

Two more notes from the same reading: `errorlevel` is ONE slot every command
writes and 0 is what any successful command stores last, so `if errorlevel 1`
inside a `( ) block` — or after a `call` — reads the PREVIOUS command's value.
The old script's backup step used exactly that and believed it had copied
everything when it had backed up nothing. Each swap outcome therefore keeps its
own slot-named variable (`DONE1..3`, `OLD1..3`), read back with delayed
expansion. And `msg *` (the failure popup) does not exist on Windows Home, so
the announcement was the part that broke: the outcome goes to `salu_swap.log`.

### 6.2 Shape of the script

```bat
@echo off
rem 0. Give the run one hidden console, then read the job from the
rem    environment SALU set (no quoted path on a command line to re-split):
rem      SALU_SWAP_TARGET / STAGING / EXE / RELAUNCH / LOCK
if not "%SALU_SWAP_HIDDEN%"=="1" (
    set SALU_SWAP_HIDDEN=1
    start "" /min cmd.exe /c "%~f0"
    exit /b 0
)

:TRY                                  rem 1. swap by rename-aside, retryable
call :SWAP 1 WebView2Loader.dll         rem    -> ren file file.old, copy new in
call :SWAP 2 libmpv-2.dll               rem    (a slot already DONE is skipped,
call :SWAP 3 yt-dlp.exe                 rem     so a retry never re-wraps the
if "%BAD%"=="0" goto :OK                rem     new file as if it were the old)
if %ATTEMPT% LSS 10 ( ping -n 2 -w 1000 127.0.0.1 >nul & goto :TRY )

set RC=1 & set KEEP_STAGING=1           rem 2. out of attempts: restore every
if "!DONE1!"=="1" call :RESTORE …       rem    swapped file from its .old, and
goto :FINISH                            rem    KEEP staging for the next try

:OK                                     rem 3. only now: manifest.json ->
if exist "%STAGING%\manifest.json" copy /y "%STAGING%\manifest.json" "%TARGET%\versions.json" >nul

:FINISH                                 rem 4. clean up, then reopen SALU
call :CLEAN                             rem    (staging is outside this file)
if not "%RELAUNCH%"=="0" ( ping -n 4 -w 1000 127.0.0.1 >nul & start "" "%EXE%" )
exit /b %RC%
```

### 6.3 What the swap must not do

* **`copy staging\*.*`** — the original sketch: it drops the script itself and
  `manifest.json` into the installation root, and its rollback restores a wider
  set than the one it backed up. Only the three component files are copied, by
  name, and only when a staged copy of that name exists.
* **Deleting the folder it runs from.** `rd /s /q "%STAGING%"` is safe precisely
  because the script, its log and its lock sit one level up (§5).
* **`backup\` in the install root.** The `.old` rename IS the backup, so a swap
  into a read-only folder fails at once instead of leaving a half-written
  backup directory behind; nothing else in that folder is touched.
* **`msg *`** for a failure (§6.1), and any `timeout` for a pause (§6.1).

### 6.4 One swap at a time

`SALU_SWAP_LOCK` is stamped by SALU before the spawn and released by the
script's last step, so a second swap can never fight the first over the same
staging folder — and a swap that was *killed* rather than finished cannot block
SALU forever: [swapLockLifetime] (5 minutes) ages the lock out. `refusal()` in
`update_installer_windows.dart` is what checks all of this **before** anything
is written: no script, no spawn, no `exit(0)` — SALU keeps running with its
files and its staged payloads intact.

### 6.5 Why the relaunch is late

SALU's own exit is what frees the files, but its single-instance mutex
(`main.dart`) closes a moment after that. A new instance started inside that
gap is treated as a second window: it forwards its arguments to a process that
is already gone and quits, which reads as "SALU never came back". One pause
before `start` covers it.

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
  * The guards run first (§6.4). Refused — a read-only install folder, or a
    swap already running — means the modal says why in plain words, keeps
    SALU open, and keeps every staged byte.
  * Spawns `salu_swap.bat` detached with the job in its environment block
    (install root, staging folder, SALU's own exe path, relaunch flag).
  * SALU exits cleanly (`exit(0)`); the script swaps and reopens it (§6.5).
* **If User selects `[ Restart Later ]`:**
  * Staged files remain in `%TEMP%\salu_update\`.
  * SALU applies them on the next normal close — the same script, spawned
    from the close hook with `SALU_SWAP_RELAUNCH=0`, so closing stays closing.
  * The close hook stays silent: a refusal there is a log line, never a dialog
    and never a blocked shutdown.
* **State 2D in a dev build (`flutter run`, F5):** the primary button reads
  `[ Apply & Close ]` and the copy says what will really happen — §10.
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
* A failed feed check shows: *"Unable to connect to update servers. Check your internet connection."*
* A failed payload download says the download could not be completed, without exposing an internal exception or claiming the earlier version check failed.
* Existing files remain untouched and fully functional.

### Preparation or Installer Error
* An unreadable NuGet package, failed verification, local disk error or failed MPV extraction is a **preparation** failure, not a network failure. The dialog explains that the update could not be prepared and the installed files have not changed.
* A failed installer handoff reports that the updater could not start. It does not blame the internet or show a raw exception name.

---

## 9. Safety & Rollback Guards

1. **Architecture Guard:** Always check that the downloaded DLL is 64-bit (`x64`) so 32-bit (`x86`) files are never placed into a 64-bit SALU installation.
2. **Atomic Rollback:** the `.old` rename IS the backup. If a file cannot be replaced, every file this run already swapped is renamed back, staging is kept for the next try, `versions.json` is never promoted, and SALU is launched anyway (§6.2).
3. **No Interruption of Playback:** Updates download quietly in the background without affecting playing media or web browsing tabs.
4. **Offline Resilience:** If internet drops or NuGet API fails, SALU logs a gentle warning and continues normal operations without crashing.

---

## 10. Dev Build vs Installed Build

The swap writes into the folder that holds the running `salu.exe` — which is a
different place, with different consequences, in each case.

| | Dev build (`flutter run` / F5) | Installed / release build |
| :--- | :--- | :--- |
| Install root | `build\windows\x64\runner\Debug\` | wherever SALU was unpacked |
| Relaunch after the swap | **off** | on |
| Primary button | `Apply & Close` | `Restart Now` |
| Who starts SALU next | the debugger (F5) | the script, after the §6.5 pause |
| Does the swap survive a rebuild? | **no** — CMake re-copies the pinned `libmpv-2.dll` and downloads the pinned `WebView2Loader.dll` into the output folder | yes |
| `versions.json` | lives in the build output (so a `flutter clean` resets it, honestly) | lives beside `salu.exe` |

**Why relaunch is off in a dev build.** Reopening the Debug `salu.exe` from the
swap script puts a SALU on screen that the debugger no longer owns: no console,
no hot reload, no breakpoints, and `flutter run` reports its app as exited. It
is worse than doing nothing, because it looks like it worked. So
`UpdaterService.isDevBuild` (a seam; default `kDebugMode`) turns `relaunch` off
and the modal tells the truth instead: SALU will close, the files will be
swapped, and the user starts it again from VS Code.

**What a dev build is still good for.** Everything up to the hand-off — feed
checks, download, the x64 and checksum guards, staging, the swap *script*, and
the swap itself. `Apply & Close` really does rewrite the DLLs in `Debug\`, and
SALU then runs on them: the honest way to try a new `libmpv-2.dll` before
anything is packaged. `flutter test` runs in a debug build, so the seams
(`devBuildProbe`, `installer`, `writability`, `lockReader`) are what keep the
suite testing both shapes without ever spawning a real `cmd.exe`.

**To see the real restart flow, run a release build:**

1. `flutter build windows --release`
2. Copy the whole `build\windows\x64\runner\Release\` folder to a folder you
   own — e.g. `%LOCALAPPDATA%\Programs\Salu` — and run `salu.exe` from there.
3. Update, `Restart Now`: SALU closes, swaps, and reopens itself.
4. If anything looks wrong, `%TEMP%\salu_swap.log` says what the script did
   after SALU was gone (`swap OK on attempt N`, `still held by …`,
   `could not write …`, `restored …`).

**Never install into `C:\Program Files`.** Windows protects it: a swap there
needs elevation, and the updater deliberately does not silently
`runas`-elevate — SALU would relaunch as a different user, and the promise
"`SALU reopens itself`" would turn into a UAC prompt at the worst moment.
Instead `refusal()` probes writability up front (create-and-delete a probe file
in the install root) and says so: keep SALU in a folder you own, or run SALU as
administrator once to apply the update. A per-user folder needs none of that and
is also the layout that lets SALU update itself forever.

**Startup sweep.** Every launch runs `postLaunchSweep()` (`main.dart`), the
moment SALU can be certain the files it swapped are no longer in use. It drops a
stale script or lock left by a swap that was *killed* instead of finished,
removes a `.old` whose new file is already in place, and — the part that keeps
the Settings tab honest — purges a staging folder whose versions are already
installed, so a swap that died before its cleanup cannot haunt the user with a
permanent "Update ready". A `.old` is only deleted when the live file exists
beside it, and the sweep never touches a leftover that is still young enough to
belong to a running swap (§6.4).

---

## 11. What the Tests Refuse to Accept

`test/update_installer_windows_test.dart` asserts the SHAPE of the script
because the previous version of that file asserted its WORDING — it demanded
that `tasklist /fi "PID eq …"` and `timeout /t 1 /nobreak` be present, and so
helped ship the exact loop that flooded the desktop. The suite now pins:

* **absence** of the process poll (`tasklist`, `findstr`, `SALU_PID`) and of
  `timeout`, checked against the script's **code lines only** — the comments
  explain the old design by naming it, and an assertion that can be satisfied
  by prose is no rule;
* the hidden-console relaunch happening **before** any tool runs;
* CRLF throughout, pure ASCII throughout, and every `( )` block balanced (one
  stray `)` in an `echo` line ends a block early and silently drops the rest
  of the script — including the relaunch);
* the script's file name never appearing among the things it deletes;
* `versions.json` being written only where the failure path has already jumped
  past it;
* the three component names matching `UpdateComponent`, so a component cannot be
  downloaded, verified, and then never installed;
* and the guards: a read-only install root refusing the handoff **before** the
  script is written, a fresh lock blocking a second swap, a stale lock not, and
  a refused spawn leaving no lock behind.
