; Windows installer for DB Client (Inno Setup 6).
;
; Build the app first, then compile this script from the app folder:
;   flutter build windows --release
;   iscc /DAppVersion=0.1.0 windows\installer\db-client.iss
; The installer is written to build\installer\.
;
; Installs for the current user by default (no admin prompt); the first
; page offers installing for all users instead.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
; 64-bit system DLLs. A 32-bit compiler sees them only through Sysnative;
; System32 would give it the 32-bit copies.
#if FileExists(GetEnv("WINDIR") + "\Sysnative\msvcp140.dll")
  #define SysDir GetEnv("WINDIR") + "\Sysnative"
#else
  #define SysDir GetEnv("WINDIR") + "\System32"
#endif
#ifndef BuildDir
  #define BuildDir "..\..\build\windows\x64\runner\Release"
#endif

[Setup]
; Never change AppId: upgrades and the uninstaller find the app by it.
AppId={{E4AAC3FC-16B9-4123-BF93-D359B12BE949}
AppName=DB Client
AppVersion={#AppVersion}
AppVerName=DB Client {#AppVersion}
AppPublisher=DB Client
AppPublisherURL=https://dbclient.is-my.app
AppSupportURL=https://github.com/afnanhakimfathurrahman/dbclient/issues
AppUpdatesURL=https://github.com/afnanhakimfathurrahman/dbclient/releases
DefaultDirName={autopf}\DB Client
DefaultGroupName=DB Client
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir=..\..\build\installer
OutputBaseFilename=db-client-windows-x64-setup
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\db_client.exe
UninstallDisplayName=DB Client
WizardStyle=modern
Compression=lzma2/max
SolidCompression=yes
; Close a running copy before replacing its files.
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; The Visual C++ runtime from the build PC, next to the app, so it starts
; on PCs without it.
Source: "{#SysDir}\msvcp140.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SysDir}\vcruntime140.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SysDir}\vcruntime140_1.dll"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\DB Client"; Filename: "{app}\db_client.exe"
Name: "{autodesktop}\DB Client"; Filename: "{app}\db_client.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\db_client.exe"; Description: "{cm:LaunchProgram,DB Client}"; Flags: nowait postinstall skipifsilent
