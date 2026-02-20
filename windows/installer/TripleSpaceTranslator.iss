#define MyAppName "Triple Space Translator"
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#define MyAppPublisher "Leo"
#define MyAppExeName "TripleSpaceTranslator.Win.exe"

[Setup]
AppId={{A9D3B2F7-704A-4C6C-8C0C-A0BF44D011B1}
AppName={#MyAppName}
AppVersion={#AppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
PrivilegesRequired=admin
OutputDir={#SourcePath}\..\dist\installer
OutputBaseFilename=TripleSpaceTranslator-Setup-{#AppVersion}
Compression=lzma
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x86compatible or x64compatible or arm64
ArchitecturesInstallIn64BitMode=x64compatible or arm64

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional icons:"; Flags: unchecked

[Files]
Source: "..\dist\win-x86\{#MyAppExeName}"; DestDir: "{app}"; DestName: "{#MyAppExeName}"; Flags: ignoreversion; Check: not Is64BitInstallMode
Source: "..\dist\win-x86\{#MyAppExeName}"; DestDir: "{app}"; DestName: "{#MyAppExeName}"; Flags: ignoreversion; Check: Is64BitInstallMode
Source: "..\local-libretranslate\*"; DestDir: "{app}\local-libretranslate"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Enable Local LibreTranslate (One Click)"; Filename: "{app}\local-libretranslate\one-click-local-libretranslate.bat"
Name: "{group}\Stop Local LibreTranslate"; Filename: "{app}\local-libretranslate\stop-local-libretranslate.bat"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent
