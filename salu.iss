#define MyAppName "SALU"
#define MyAppVersion "0.1.0"
#define MyAppExeName "salu.exe"

[Setup]
AppId={{A92C3F15-8D22-4E0C-9A10-5B8460D2F319}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
DefaultDirName={autopf}\SALU
DefaultGroupName=SALU
UninstallDisplayIcon={app}\salu.exe
SetupIconFile=windows\runner\resources\app_icon.ico
OutputDir=.
OutputBaseFilename=SALU-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
PrivilegesRequired=admin

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\SALU"; Filename: "{app}\salu.exe"
Name: "{autodesktop}\SALU"; Filename: "{app}\salu.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\salu.exe"; Description: "Launch SALU"; Flags: nowait postinstall skipifsilent