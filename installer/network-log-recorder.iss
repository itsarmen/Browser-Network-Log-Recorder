; /*
;  * Project : Firefox Network Log Recorder
;  * Author  : AMiran Kimadze (itsarmen)
;  * GitHub  : https://github.com/itsarmen
;  * Email   : amoswaper@gmail.com
;  * Web     : https://xrow.asia
;  */
;
; Inno Setup script — per-user installer (no admin rights needed).
; Build the app first, then compile this script:
;   python run_windows.py --installer
; or manually:
;   flutter build windows --release
;   ISCC installer\network-log-recorder.iss

#define MyAppName "Network Log Recorder"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "AMiran Kimadze (itsarmen)"
#define MyAppURL "https://xrow.asia"
#define MyAppSupportURL "https://github.com/itsarmen"
#define MyAppExeName "network_log_viewer.exe"
#define MyBuildDir "..\\flutter-desktop-app\\build\\windows\\x64\\runner\\Release"

[Setup]
AppId={{E4307326-58DF-4C00-83AA-2FBE7DEAC2BD}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppSupportURL}
AppUpdatesURL={#MyAppSupportURL}
DefaultDirName={localappdata}\{#MyAppName}
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=output
OutputBaseFilename=NetworkLogRecorder-Setup-{#MyAppVersion}
SetupIconFile=..\\branding\\icons\\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
#ifndef LicenseTxt
#define LicenseTxt "..\\LICENSE"
#endif
#ifndef AgreementTxt
#define AgreementTxt "..\\AGREEMENT.md"
#endif
InfoBeforeFile={#LicenseTxt}
LicenseFile={#AgreementTxt}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
DisableProgramGroupPage=yes
CloseApplications=yes

; Code signing (optional): `python run_windows.py --installer --sign` passes
; /DSignEnabled=1 and /Sdevsign="<signtool command>" on the ISCC command line,
; so no secrets are stored in this script.
#ifdef SignEnabled
SignedUninstaller=yes
SignTool=devsign
#endif

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; \
  GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
Source: "{#MyBuildDir}\\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#MyBuildDir}\\*.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#MyBuildDir}\\data\\*"; DestDir: "{app}\\data"; \
  Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\\{#MyAppName}"; Filename: "{app}\\{#MyAppExeName}"
Name: "{autodesktop}\\{#MyAppName}"; Filename: "{app}\\{#MyAppExeName}"; \
  Tasks: desktopicon

[Run]
Filename: "{app}\\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; \
  Flags: nowait postinstall skipifsilent
