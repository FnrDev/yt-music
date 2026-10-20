; Inno Setup script for the YT Music installer.
;
; Wraps the self-contained single-file YTMusic.exe from `dotnet publish`.
; Per-user install (no admin prompt) into %LOCALAPPDATA%\Programs\YT Music.
;
; Build (from the repo root, after publishing to .\publish):
;   iscc /DAppVersion=0.1.0 /DSourceDir=..\..\publish /DOutputDir=..\..\dist windows\installer\YTMusic.iss

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\publish"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\dist"
#endif

#define AppName "YT Music"
#define AppExe "YTMusic.exe"

[Setup]
AppId={{6B0C4E5A-3F7D-4C2B-9A61-8E2D5F1C7B40}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=FnrDev
AppPublisherURL=https://github.com/FnrDev/yt-music
AppSupportURL=https://github.com/FnrDev/yt-music/issues
AppUpdatesURL=https://github.com/FnrDev/yt-music/releases
AppComments=Unofficial desktop app for YouTube Music. Not affiliated with Google or YouTube.
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.19041
; The app keeps running in the tray; make sure it's closed before replacing it.
AppMutex=Local\YTMusic.SingleInstance
CloseApplications=yes
SetupIconFile=..\YTMusic\Assets\AppIcon.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
OutputDir={#OutputDir}
OutputBaseFilename=YTMusic-Setup-{#AppVersion}-x64
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceDir}\{#AppExe}"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

; Settings (%APPDATA%\YTMusic) and the WebView2 profile (%LOCALAPPDATA%\YTMusic)
; are left in place on uninstall so a reinstall stays signed in.
