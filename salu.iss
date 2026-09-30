#define MyAppName "SALU"
#define MyAppVersion "0.1.0"
#define MyAppExeName "salu.exe"

[Setup]
AppId={{A92C3F15-8D22-4E0C-9A10-5B8460D2F319}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=SALU
AppPublisherURL=https://github.com/hamamun/Salu
DefaultDirName={autopf}\SALU
DefaultGroupName=SALU
UninstallDisplayName=SALU
UninstallDisplayIcon={app}\salu.exe
SetupIconFile=windows\runner\resources\app_icon.ico
OutputDir=.
OutputBaseFilename=SALU-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
MinVersion=10.0.17763
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=dialog
CloseApplications=yes
CloseApplicationsFilter=salu.exe
RestartApplications=no
UsePreviousAppDir=yes

[Tasks]
Name: "desktopicon"; Description: "Create a Desktop shortcut"; GroupDescription: "Shortcuts:"; Flags: unchecked
Name: "startup"; Description: "Start SALU when I sign in to Windows"; GroupDescription: "Windows options:"; Flags: unchecked
Name: "assoc_video"; Description: "Add SALU to Open with for supported video files"; GroupDescription: "File associations (does not force Windows defaults):"; Flags: unchecked
Name: "assoc_audio"; Description: "Add SALU to Open with for supported audio files"; GroupDescription: "File associations (does not force Windows defaults):"; Flags: unchecked
Name: "assoc_playlists"; Description: "Add SALU to Open with for supported playlist files"; GroupDescription: "File associations (does not force Windows defaults):"; Flags: unchecked

[Files]
; Package the complete Flutter release bundle, not just salu.exe.
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\SALU"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{autodesktop}\SALU"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Registry]
; Per-user startup preference; removed by the uninstaller.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "SALU"; ValueData: """{app}\{#MyAppExeName}"""; Tasks: startup; Flags: uninsdeletevalue

[Run]
; Apply the selected groups in the installing user's HKCU registry, not in the elevated admin account.
Filename: "{app}\{#MyAppExeName}"; Parameters: "{code:AssociationParameters}"; WorkingDir: "{app}"; Flags: runhidden waituntilterminated runasoriginaluser; Check: HasAssociationTasks
; Optional finish-page checkbox; on by default. Silent installations do not auto-launch the UI.
Filename: "{app}\{#MyAppExeName}"; Description: "Launch SALU"; WorkingDir: "{app}"; Flags: nowait postinstall skipifsilent
; If the optional browser runtime is missing, offer to open Microsoft's download page.
Filename: "https://developer.microsoft.com/en-us/microsoft-edge/webview2/"; Description: "Get the WebView2 Runtime (needed for SALU's built-in browser)"; Flags: shellexec postinstall skipifsilent; Check: not IsWebView2RuntimeInstalled

[UninstallRun]
; Remove only SALU's per-user association registrations before the files are removed.
Filename: "{app}\{#MyAppExeName}"; Parameters: "--unregister"; WorkingDir: "{app}"; Flags: runhidden waituntilterminated; RunOnceId: "SALUUnregisterAssociations"

[Code]
var
  PurgeSaluUserData: Boolean;

function HasAssociationTasks: Boolean;
begin
  Result := WizardIsTaskSelected('assoc_video') or
    WizardIsTaskSelected('assoc_audio') or
    WizardIsTaskSelected('assoc_playlists');
end;

function AssociationParameters(Param: String): String;
begin
  Result := '';
  if WizardIsTaskSelected('assoc_video') then
    Result := Result + '--associate-video ';
  if WizardIsTaskSelected('assoc_audio') then
    Result := Result + '--associate-audio ';
  if WizardIsTaskSelected('assoc_playlists') then
    Result := Result + '--associate-playlists ';
end;

function RuntimeVersionPresent(const RootKey: Integer; const SubKey: String): Boolean;
var
  Version: String;
begin
  Result := RegQueryStringValue(RootKey, SubKey, 'pv', Version) and
    (Version <> '') and (Version <> '0.0.0.0');
end;

function IsWebView2RuntimeInstalled: Boolean;
const
  WebView2Client = '{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}';
begin
  Result := RuntimeVersionPresent(HKLM,
    'SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\' + WebView2Client) or
    RuntimeVersionPresent(HKLM,
    'SOFTWARE\Microsoft\EdgeUpdate\Clients\' + WebView2Client) or
    RuntimeVersionPresent(HKCU,
    'Software\Microsoft\EdgeUpdate\Clients\' + WebView2Client);
end;

function HasPurgeDataSwitch: Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to ParamCount do
    if CompareText(ParamStr(I), '/PURGEDATA') = 0 then
      Result := True;
end;

function InitializeUninstall: Boolean;
begin
  PurgeSaluUserData := HasPurgeDataSwitch;
  if (not UninstallSilent) and (not PurgeSaluUserData) then
    PurgeSaluUserData := MsgBox(
      'Also remove SALU settings and its built-in browser profile? Your media files and downloaded files will not be removed.',
      mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES;
  Result := True;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if (CurUninstallStep = usPostUninstall) and PurgeSaluUserData then
  begin
    { shared_preferences Windows storage: %APPDATA%\SALU\SALU }
    DelTree(ExpandConstant('{userappdata}\SALU\SALU'), True, True, True);
    { SALU's dedicated WebView2 browser profile; no other LocalAppData data is touched. }
    DelTree(ExpandConstant('{localappdata}\SALU\WebView2'), True, True, True);
  end;
end;

// Code signing needs a certificate owned by the publisher. After configuring a
// Sign Tool in Inno Setup's Tools > Configure Sign Tools, set the SignTool
// directive in [Setup], for example: SignTool=SALU-CodeSign. Test it before release.