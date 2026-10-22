; Inno Setup script for DragWheel. Built by CI:  iscc /DAppVersion=1.0.0 /DSourceDir=..\publish DragWheel.iss
; Installs for the current user only — no administrator rights, nothing outside the user's profile.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\publish"
#endif

[Setup]
AppId={{6E1C1B4F-3E7A-4B57-9C61-4C0B5E2D7A11}
AppName=DragWheel
AppVersion={#AppVersion}
AppVerName=DragWheel {#AppVersion}
AppPublisher=DragWheel contributors
AppPublisherURL=https://github.com/nico43245/DragWheel
AppSupportURL=https://github.com/nico43245/DragWheel/issues
DefaultDirName={localappdata}\Programs\DragWheel
DefaultGroupName=DragWheel
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.19041
OutputDir=..\..\dist
OutputBaseFilename=DragWheel-{#AppVersion}-Windows-Setup
SetupIconFile=..\src\DragWheel\Assets\DragWheel.ico
UninstallDisplayIcon={app}\DragWheel.exe
LicenseFile=..\..\LICENSE
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes

[Tasks]
Name: "autostart"; Description: "Start DragWheel when I sign in to Windows"; GroupDescription: "Options:"
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Options:"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\DragWheel"; Filename: "{app}\DragWheel.exe"
Name: "{userdesktop}\DragWheel"; Filename: "{app}\DragWheel.exe"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "DragWheel"; \
    ValueData: """{app}\DragWheel.exe"" --background"; Flags: uninsdeletevalue; Tasks: autostart

[Run]
Filename: "{app}\DragWheel.exe"; Description: "Start DragWheel now"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{cmd}"; Parameters: "/C taskkill /IM DragWheel.exe /F"; Flags: runhidden; RunOnceId: "StopDragWheel"

[UninstallDelete]
; Settings live in %APPDATA%\DragWheel — remove them so an uninstall leaves nothing behind.
Type: filesandordirs; Name: "{userappdata}\DragWheel"

[Code]
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  // Also clear "Start with Windows" if it was turned on later from Preferences.
  if CurUninstallStep = usPostUninstall then
    RegDeleteValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Run', 'DragWheel');
end;
