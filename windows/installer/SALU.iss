; ─────────────────────────────────────────────────────────────────────────────
; SALU — Windows installer (Phase 9 · Step 4, Inno Setup 6)
;
; Build:
;   1. flutter build windows --release
;   2. iscc windows\installer\SALU.iss        (from the repo root)
;   3. Result: windows\installer\output\SALU-1.0.0-setup.exe
;
; The installer registers SALU as a native handler for the common media
; formats and injects "Open with SALU" into Explorer's right-click menu.
; Double-clicked files land on salu.exe → the Phase 1 single-instance layer
; forwards the path to the already-running SALU window (or launches it).
; ─────────────────────────────────────────────────────────────────────────────

#define MyAppName "SALU"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "hamamun"
#define MyAppURL "https://github.com/hamamun/Salu"
#define MyAppExeName "salu.exe"
#define ProgId "SALU.Media"

[Setup]
; Stable GUID — never change, or upgrades will install side-by-side.
AppId={{8C1B9D3E-6A4F-4B77-9E52-5F0A2C7D1E90}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}
OutputDir=output
OutputBaseFilename={#MyAppName}-{#MyAppVersion}-setup
SetupIconFile=..\runner\resources\app_icon.ico
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
PrivilegesRequired=admin
CloseApplications=yes

[Tasks]
Name: "fileassoc"; Description: "Register {#MyAppName} for common video & audio formats"
Name: "contextmenu"; Description: "Add ""Open with {#MyAppName}"" to the Explorer right-click menu"
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional icons:"; Flags: unchecked

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\{#MyAppExeName}"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

; ── App Paths: lets Windows resolve `salu.exe "%1"` anywhere ─────────────────
[Registry]
Root: HKLM; Subkey: "SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\{#MyAppExeName}"; \
  ValueType: string; ValueData: "{app}\{#MyAppExeName}"; Flags: uninsdeletekey
Root: HKLM; Subkey: "SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\{#MyAppExeName}"; \
  ValueType: string; ValueName: "Path"; ValueData: "{app}"; Flags: uninsdeletekey

; ── ProgID: SALU is a player for generic media files ─────────────────────────
Root: HKCR; Subkey: "{#ProgId}"; ValueType: string; ValueData: "{#MyAppName} Media File"; \
  Tasks: fileassoc; Flags: uninsdeletekey
Root: HKCR; Subkey: "{#ProgId}\DefaultIcon"; ValueType: string; \
  ValueData: "{app}\{#MyAppExeName},0"; Tasks: fileassoc; Flags: uninsdeletekey
Root: HKCR; Subkey: "{#ProgId}\shell\open\command"; ValueType: string; \
  ValueData: """{app}\{#MyAppExeName}"" ""%1"""; Tasks: fileassoc; Flags: uninsdeletekey
Root: HKCR; Subkey: "{#ProgId}\InstallInfo"; ValueType: string; ValueName: "ReinstallMode"; \
  ValueData: "machine"; Tasks: fileassoc; Flags: uninsdeletekey

; ── Per-extension registrations ─────────────────────────────────────────────
; One line per extension, kept explicit so it is trivial to audit/remove.
; "OpenWithProgids" advertises SALU in the *Open with…* dialog without ever
; hijacking the user's existing default player; the context-menu verbs below
; add a direct "Open with SALU" entry.
Root: HKCR; Subkey: ".mp4\OpenWithProgids"; ValueType: string; ValueName: "{#ProgId}"; ValueData: ""; Tasks: fileassoc; Flags: uninsdeletevalue
Root: HKCR; Subkey: ".mkv\OpenWithProgids"; ValueType: string; ValueName: "{#ProgId}"; ValueData: ""; Tasks: fileassoc; Flags: uninsdeletevalue
Root: HKCR; Subkey: ".avi\OpenWithProgids"; ValueType: string; ValueName: "{#ProgId}"; ValueData: ""; Tasks: fileassoc; Flags: uninsdeletevalue
Root: HKCR; Subkey: ".mov\OpenWithProgids"; ValueType: string; ValueName: "{#ProgId}"; ValueData: ""; Tasks: fileassoc; Flags: uninsdeletevalue
Root: HKCR; Subkey: ".wmv\OpenWithProgids"; ValueType: string; ValueName: "{#ProgId}"; ValueData: ""; Tasks: fileassoc; Flags: uninsdeletevalue
Root: HKCR; Subkey: ".flv\OpenWithProgids"; ValueType: string; ValueName: "{#ProgId}"; ValueData: ""; Tasks: fileassoc; Flags: uninsdeletevalue
Root: HKCR; Subkey: ".webm\OpenWithProgids"; ValueType: string; ValueName: "{#ProgId}"; ValueData: ""; Tasks: fileassoc; Flags: uninsdeletevalue
Root: HKCR; Subkey: ".m4v\OpenWithProgids"; ValueType: string; ValueName: "{#ProgId}"; ValueData: ""; Tasks: fileassoc; Flags: uninsdeletevalue
Root: HKCR; Subkey: ".mpg\OpenWithProgids"; ValueType: string; ValueName: "{#ProgId}"; ValueData: ""; Tasks: fileassoc; Flags: uninsdeletevalue
Root: HKCR; Subkey: ".mpeg\OpenWithProgids"; ValueType: string; ValueName: "{#ProgId}"; ValueData: ""; Tasks: fileassoc; Flags: uninsdeletevalue
Root: HKCR; Subkey: ".ts\OpenWithProgids"; ValueType: string; ValueName: "{#ProgId}"; ValueData: ""; Tasks: fileassoc; Flags: uninsdeletevalue
Root: HKCR; Subkey: ".m2ts\OpenWithProgids"; ValueType: string; ValueName: "{#ProgId}"; ValueData: ""; Tasks: fileassoc; Flags: uninsdeletevalue
Root: HKCR; Subkey: ".mts\OpenWithProgids"; ValueType: string; ValueName: "{#ProgId}"; ValueData: ""; Tasks: fileassoc; Flags: uninsdeletevalue
Root: HKCR; Subkey: ".mp3\OpenWithProgids"; ValueType: string; ValueName: "{#ProgId}"; ValueData: ""; Tasks: fileassoc; Flags: uninsdeletevalue
Root: HKCR; Subkey: ".flac\OpenWithProgids"; ValueType: string; ValueName: "{#ProgId}"; ValueData: ""; Tasks: fileassoc; Flags: uninsdeletevalue
Root: HKCR; Subkey: ".m4a\OpenWithProgids"; ValueType: string; ValueName: "{#ProgId}"; ValueData: ""; Tasks: fileassoc; Flags: uninsdeletevalue
Root: HKCR; Subkey: ".aac\OpenWithProgids"; ValueType: string; ValueName: "{#ProgId}"; ValueData: ""; Tasks: fileassoc; Flags: uninsdeletevalue
Root: HKCR; Subkey: ".ogg\OpenWithProgids"; ValueType: string; ValueName: "{#ProgId}"; ValueData: ""; Tasks: fileassoc; Flags: uninsdeletevalue
Root: HKCR; Subkey: ".opus\OpenWithProgids"; ValueType: string; ValueName: "{#ProgId}"; ValueData: ""; Tasks: fileassoc; Flags: uninsdeletevalue
Root: HKCR; Subkey: ".wav\OpenWithProgids"; ValueType: string; ValueName: "{#ProgId}"; ValueData: ""; Tasks: fileassoc; Flags: uninsdeletevalue
Root: HKCR; Subkey: ".m3u\OpenWithProgids"; ValueType: string; ValueName: "{#ProgId}"; ValueData: ""; Tasks: fileassoc; Flags: uninsdeletevalue
Root: HKCR; Subkey: ".m3u8\OpenWithProgids"; ValueType: string; ValueName: "{#ProgId}"; ValueData: ""; Tasks: fileassoc; Flags: uninsdeletevalue

; ── Right-click "Open with SALU" (classic verb, always available) ───────────
Root: HKCR; Subkey: ".mp4\shell\OpenWithSALU"; ValueType: string; ValueData: "Open with SALU"; Tasks: contextmenu; Flags: uninsdeletekey
Root: HKCR; Subkey: ".mp4\shell\OpenWithSALU"; ValueType: string; ValueName: "Icon"; ValueData: """{app}\{#MyAppExeName}"",0"; Tasks: contextmenu; Flags: uninsdeletekey
Root: HKCR; Subkey: ".mp4\shell\OpenWithSALU\command"; ValueType: string; ValueData: """{app}\{#MyAppExeName}"" ""%1"""; Tasks: contextmenu; Flags: uninsdeletekey
Root: HKCR; Subkey: ".mkv\shell\OpenWithSALU"; ValueType: string; ValueData: "Open with SALU"; Tasks: contextmenu; Flags: uninsdeletekey
Root: HKCR; Subkey: ".mkv\shell\OpenWithSALU"; ValueType: string; ValueName: "Icon"; ValueData: """{app}\{#MyAppExeName}"",0"; Tasks: contextmenu; Flags: uninsdeletekey
Root: HKCR; Subkey: ".mkv\shell\OpenWithSALU\command"; ValueType: string; ValueData: """{app}\{#MyAppExeName}"" ""%1"""; Tasks: contextmenu; Flags: uninsdeletekey
Root: HKCR; Subkey: ".avi\shell\OpenWithSALU"; ValueType: string; ValueData: "Open with SALU"; Tasks: contextmenu; Flags: uninsdeletekey
Root: HKCR; Subkey: ".avi\shell\OpenWithSALU"; ValueType: string; ValueName: "Icon"; ValueData: """{app}\{#MyAppExeName}"",0"; Tasks: contextmenu; Flags: uninsdeletekey
Root: HKCR; Subkey: ".avi\shell\OpenWithSALU\command"; ValueType: string; ValueData: """{app}\{#MyAppExeName}"" ""%1"""; Tasks: contextmenu; Flags: uninsdeletekey
Root: HKCR; Subkey: ".mov\shell\OpenWithSALU"; ValueType: string; ValueData: "Open with SALU"; Tasks: contextmenu; Flags: uninsdeletekey
Root: HKCR; Subkey: ".mov\shell\OpenWithSALU"; ValueType: string; ValueName: "Icon"; ValueData: """{app}\{#MyAppExeName}"",0"; Tasks: contextmenu; Flags: uninsdeletekey
Root: HKCR; Subkey: ".mov\shell\OpenWithSALU\command"; ValueType: string; ValueData: """{app}\{#MyAppExeName}"" ""%1"""; Tasks: contextmenu; Flags: uninsdeletekey
Root: HKCR; Subkey: ".mp3\shell\OpenWithSALU"; ValueType: string; ValueData: "Open with SALU"; Tasks: contextmenu; Flags: uninsdeletekey
Root: HKCR; Subkey: ".mp3\shell\OpenWithSALU"; ValueType: string; ValueName: "Icon"; ValueData: """{app}\{#MyAppExeName}"",0"; Tasks: contextmenu; Flags: uninsdeletekey
Root: HKCR; Subkey: ".mp3\shell\OpenWithSALU\command"; ValueType: string; ValueData: """{app}\{#MyAppExeName}"" ""%1"""; Tasks: contextmenu; Flags: uninsdeletekey
Root: HKCR; Subkey: ".flac\shell\OpenWithSALU"; ValueType: string; ValueData: "Open with SALU"; Tasks: contextmenu; Flags: uninsdeletekey
Root: HKCR; Subkey: ".flac\shell\OpenWithSALU"; ValueType: string; ValueName: "Icon"; ValueData: """{app}\{#MyAppExeName}"",0"; Tasks: contextmenu; Flags: uninsdeletekey
Root: HKCR; Subkey: ".flac\shell\OpenWithSALU\command"; ValueType: string; ValueData: """{app}\{#MyAppExeName}"" ""%1"""; Tasks: contextmenu; Flags: uninsdeletekey
Root: HKCR; Subkey: ".webm\shell\OpenWithSALU"; ValueType: string; ValueData: "Open with SALU"; Tasks: contextmenu; Flags: uninsdeletekey
Root: HKCR; Subkey: ".webm\shell\OpenWithSALU"; ValueType: string; ValueName: "Icon"; ValueData: """{app}\{#MyAppExeName}"",0"; Tasks: contextmenu; Flags: uninsdeletekey
Root: HKCR; Subkey: ".webm\shell\OpenWithSALU\command"; ValueType: string; ValueData: """{app}\{#MyAppExeName}"" ""%1"""; Tasks: contextmenu; Flags: uninsdeletekey

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; WorkingDir: "{app}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Clean anything SALU dropped next to the install folder.
Type: filesandordirs; Name: "{app}\data"
