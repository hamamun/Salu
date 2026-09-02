# SALU Windows Installer (Phase 9 · Step 4)

`SALU.iss` is an **Inno Setup 6** script that packages the release build and
wires SALU into the Windows shell:

| What | How |
|------|-----|
| Native media handler | ProgID `SALU.Media` registered under `HKCR`, advertised via `OpenWithProgids` for `.mp4 .mkv .avi .mov .wmv .flv .webm .m4v .mpg .mpeg .ts .m2ts .mts` (video) and `.mp3 .flac .m4a .aac .ogg .opus .wav` (audio) plus `.m3u .m3u8` playlists. |
| Right-click menu | Optional “Open with SALU” verb on the most common extensions (task checkbox at install time). |
| Single-instance routing | `HKLM\…\App Paths\salu.exe` + `salu.exe "%1"` command line — double-clicking a media file anywhere launches SALU, and if it is already running the Phase 1 `windows_single_instance` channel forwards the path to the live window. |
| Clean removal | All keys carry `uninsdeletekey` / `uninsdeletevalue` flags, so uninstall leaves the registry spotless. |

## Build

```powershell
.\windows\installer\build_installer.ps1
# → windows\installer\output\SALU-1.0.0-setup.exe
```

…or manually:

```powershell
flutter build windows --release
iscc windows\installer\SALU.iss
```

> Install [Inno Setup 6](https://jrsoftware.org/isdl.php) once to get `iscc`.
> The setup icon comes from `windows/runner/resources/app_icon.ico`, the same
> multi-resolution ico the app embeds as `IDI_APP_ICON` (taskbar / Start menu
> / desktop share one crisp SALU mark at 16–256 px).
