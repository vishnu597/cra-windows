; Cra's Windows installer (Inno Setup 6): Windows/scripts/installer.ps1 builds it from
; Windows/build/Cra. A per-user install, as Chrome's and Arc's are: no administrator, into
; %LOCALAPPDATA%\Programs\Cra, with a Start menu entry and an uninstaller in Settings ▸ Apps.
; The Windows App Runtime Cra's WinUI needs is installed with it when missing. The data folder
; (%LOCALAPPDATA%\Cra: spaces, settings, Chromium's profiles) stays on uninstall, as browsers'
; data does; the registry entries Cra wrote for itself go.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\build\Cra"
#endif
#ifndef OutputDir
  #define OutputDir "..\build\installer"
#endif

[Setup]
; Fixed for every version: Windows finds the installed Cra by it to update or remove it.
AppId={{6F7C2B1E-4A8D-4C7E-9B3F-2D5E8A1C0F42}
AppName=Cra
AppVersion={#AppVersion}
AppVerName=Cra {#AppVersion}
AppPublisher=Cra
AppPublisherURL=https://crabrowser.app
AppSupportURL=https://crabrowser.app
DefaultDirName={localappdata}\Programs\Cra
DefaultGroupName=Cra
DisableProgramGroupPage=yes
DisableDirPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
OutputDir={#OutputDir}
OutputBaseFilename=Cra-{#AppVersion}-Setup
SetupIconFile=..\Resources\Cra.ico
UninstallDisplayIcon={app}\Cra.exe
UninstallDisplayName=Cra
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; A running Cra holds its files: Windows' Restart Manager closes it first, and it opens again after.
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Excludes: "*.pdb,*.lib,*.exp,*.ilk"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#SourceDir}\..\windowsappruntimeinstall-x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall skipifsourcedoesntexist

[Icons]
Name: "{autoprograms}\Cra"; Filename: "{app}\Cra.exe"
Name: "{autodesktop}\Cra"; Filename: "{app}\Cra.exe"; Tasks: desktopicon

[Run]
Filename: "{tmp}\windowsappruntimeinstall-x64.exe"; Parameters: "--quiet"; StatusMsg: "Installing the Windows App Runtime…"; Flags: runhidden waituntilterminated skipifdoesntexist; Check: NeedsAppRuntime
Filename: "{app}\Cra.exe"; Description: "{cm:LaunchProgram,Cra}"; Flags: nowait postinstall skipifsilent

[Code]
// The Windows App Runtime 1.7 (WinUI 3) is a framework package: installed once per user,
// shared by apps. Asked of PowerShell, which lists the packages this user has.
function NeedsAppRuntime: Boolean;
var
  Code: Integer;
begin
  Result := True;
  if Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
          '-NoProfile -NonInteractive -Command "if (Get-AppxPackage -Name ''Microsoft.WindowsAppRuntime.1.7'' | Where-Object Architecture -eq ''X64'') { exit 0 } else { exit 1 }"',
          '', SW_HIDE, ewWaitUntilTerminated, Code) then
    Result := Code <> 0;
end;

// What Cra registers for itself while it runs (DefaultBrowser.swift, LaunchAtLogin) goes with it,
// so Default apps and Startup apps don't list a Cra that's gone. Written after installing, so
// Inno Setup's own log doesn't have them: removed here.
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep <> usPostUninstall then Exit;
  RegDeleteKeyIncludingSubkeys(HKCU, 'Software\Classes\CraHTML');
  RegDeleteKeyIncludingSubkeys(HKCU, 'Software\Classes\cra');
  RegDeleteKeyIncludingSubkeys(HKCU, 'Software\Clients\StartMenuInternet\Cra');
  RegDeleteValue(HKCU, 'Software\RegisteredApplications', 'Cra');
  RegDeleteValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Run', 'Cra');
  RegDeleteValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run', 'Cra');
end;
