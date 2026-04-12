#define MyAppName "Flight Tracker"
#define MyAppPublisher "Flight Tracker"
#define MyAppExeName "Desktop\\FlightTracker.exe"
#define MyBrowserExeName "DashboardHost\\FlightTrackerDashboard.exe"

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

#ifndef SourceDir
  #error SourceDir must be provided to the Inno Setup compiler.
#endif

#ifndef OutputDir
  #error OutputDir must be provided to the Inno Setup compiler.
#endif

#ifndef OutputBaseFilename
  #define OutputBaseFilename "FlightTracker-Setup"
#endif

[Setup]
AppId={{8B8A8B93-17A3-499D-AF6A-835655FB4827}
AppName={#MyAppName}
AppVersion={#AppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\Flight Tracker
DefaultGroupName=Flight Tracker
DisableProgramGroupPage=yes
OutputDir={#OutputDir}
OutputBaseFilename={#OutputBaseFilename}
Compression=lzma
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
UninstallDisplayIcon={app}\{#MyAppExeName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Flight Tracker"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Flight Tracker Browser Host"; Filename: "{app}\{#MyBrowserExeName}"
Name: "{autodesktop}\Flight Tracker"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch Flight Tracker"; Flags: nowait postinstall skipifsilent
