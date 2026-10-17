; Supervertaler Sidekick - installer
;
; Built by tools/build-installer.sh, never by hand: the script decides what goes
; in, and this file only says where it lands.
;
; Sidekick is an AutoHotkey script, and this installs it for someone who has
; never heard of AutoHotkey. It carries its own copy of AutoHotkey, unmodified,
; in a folder of its own beside the script, and the shortcuts run the script
; with it. Nothing is compiled, so text expansion - which includes a script
; Sidekick writes from your entries - works exactly as it does from the
; repository, and an installed Sidekick is the same program a developer runs.
;
; It installs for the current user only, so it needs no administrator rights.
; That is also what Sidekick needs: it writes its settings and data beside
; itself, and a folder under Program Files would refuse it.
;
; WHERE it installs is asked, not decided, because that folder is also where
; the user's own content lives - the menu, clipboard history, notes and
; settings - and they need to be able to find it. The first build put it in
; %LocalAppData%\Programs, which Windows offers for exactly this and which
; hardly anyone knows exists. The suggestion is a sidekick folder inside the
; Supervertaler data folder, beside the memoq and trados folders the plugins
; keep there.

#define AppName      "Supervertaler Sidekick"
#define AppPublisher "Michael Beijer"
#define AppUrl       "https://supervertaler.com"
#define DocsUrl      "https://docs.supervertaler.com/sidekick/"

#ifndef Stage
  #error Stage is not defined - build with tools/build-installer.sh
#endif
#ifndef AppVersion
  #error AppVersion is not defined - build with tools/build-installer.sh
#endif
#ifndef AhkVersion
  #error AhkVersion is not defined - build with tools/build-installer.sh
#endif

[Setup]
AppId={{4CA1D500-A5B4-4C9D-84C8-11C34354336C}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppUrl}
AppSupportURL={#DocsUrl}
VersionInfoVersion={#AppVersion}

PrivilegesRequired=lowest
; The folder page is shown on a first install and skipped on an update, which
; goes where the first one went.
DefaultDirName={code:SuggestedFolder}
DisableDirPage=auto
DisableProgramGroupPage=yes

; The runtime it carries is the 64-bit AutoHotkey.
ArchitecturesAllowed=x64compatible

UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\Sidekick.ico
SetupIconFile=..\Sidekick.ico
OutputBaseFilename=Supervertaler-Sidekick-Setup-{#AppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Messages]
SelectDirLabel3=Sidekick keeps your own things in this folder too: your menu, clipboard history, notes and settings. Choose somewhere you will find it again. The suggestion is your Supervertaler data folder, where the other Supervertaler products keep theirs.

[Tasks]
Name: "startup"; Description: "Start Sidekick when I sign in to Windows"

[InstallDelete]
; The program's own code, replaced whole on every update so a file dropped
; from Sidekick cannot linger and be loaded. Nothing of the user's lives here:
; their content is in data\ and their settings in settings.ini, and neither is
; ever in the installer, so an update cannot touch them.
Type: filesandordirs; Name: "{app}\lib"

[Files]
; Everything the build staged, and only that. The build takes it from what git
; has committed and refuses anything not on its list of what may ship.
Source: "{#Stage}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Supervertaler Sidekick"; Filename: "{app}\AutoHotkey\AutoHotkey64.exe"; Parameters: """{app}\Sidekick.ahk"""; WorkingDir: "{app}"; IconFilename: "{app}\Sidekick.ico"; Comment: "The system-wide toolbox for translators"
Name: "{autostartup}\Supervertaler Sidekick"; Filename: "{app}\AutoHotkey\AutoHotkey64.exe"; Parameters: """{app}\Sidekick.ahk"""; WorkingDir: "{app}"; IconFilename: "{app}\Sidekick.ico"; Tasks: startup

[Run]
Filename: "{app}\AutoHotkey\AutoHotkey64.exe"; Parameters: """{app}\Sidekick.ahk"""; WorkingDir: "{app}"; Description: "Start Supervertaler Sidekick now"; Flags: postinstall nowait skipifsilent

[Code]
#include "folders.iss"

{ Somewhere Windows will not let an ordinary program write would install, then
  fail the first time Sidekick saved anything. Refused on the folder page
  instead, while there is still a choice to make. }
function NextButtonClick(CurPageID: Integer): Boolean;
var
  Dir: String;
begin
  Result := True;
  if CurPageID <> wpSelectDir then Exit;
  Dir := WizardDirValue();
  if IsUnder(Dir, ExpandConstant('{commonpf32}')) or IsUnder(Dir, ExpandConstant('{commonpf64}')) or
     IsUnder(Dir, ExpandConstant('{win}')) then
  begin
    MsgBox('Sidekick cannot go in ' + Dir + '.' + #13#10#13#10 +
           'It saves your settings and content in its own folder, and Windows does not let ' +
           'programs write in that one. Choose a folder of your own, such as the one suggested.',
           mbError, MB_OK);
    Result := False;
  end;
end;

{ The last page says where everything went, because that folder is now where
  the user's content lives - the thing the first build's location hid. }
procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = wpFinished then
    WizardForm.FinishedLabel.Caption :=
      'Supervertaler Sidekick is installed in' + #13#10 + ExpandConstant('{app}') + #13#10#13#10 +
      'Your own menu, clipboard history, notes and settings are kept there too.' + #13#10#13#10 +
      'It runs in the system tray, by the clock - click the ^ there if you cannot see its icon. ' +
      'Press ` (backtick) in any program to open its window, or select some text and press ' +
      'Ctrl+Alt+T to translate it.' + #13#10#13#10 +
      'The help is at docs.supervertaler.com/sidekick.';
end;

const
  WM_COMMAND = $0111;
  { AutoHotkey's own Exit command, the one its tray menu sends. Asking the
    script to exit this way runs its exit handler, which saves a note still
    being typed in the Scratchpad; ending the process would not. }
  AHK_EXIT = 65405;

{ AutoHotkey titles a script's hidden main window with the script's full path
  and its own version, so this finds this install's Sidekick and no other
  AutoHotkey script that happens to be running. }
function SidekickWindow(): HWND;
begin
  Result := FindWindowByWindowName(ExpandConstant('{app}') + '\Sidekick.ahk - AutoHotkey v{#AhkVersion}');
end;

{ True once no Sidekick from this folder is running. }
function CloseSidekick(): Boolean;
var
  Wnd: HWND;
  Waited: Integer;
begin
  Wnd := SidekickWindow();
  if Wnd <> 0 then
  begin
    PostMessage(Wnd, WM_COMMAND, AHK_EXIT, 0);
    Waited := 0;
    while (SidekickWindow() <> 0) and (Waited < 5000) do
    begin
      Sleep(100);
      Waited := Waited + 100;
    end;
  end;
  Result := SidekickWindow() = 0;
end;

{ An update replaces the AutoHotkey that is running Sidekick, which Windows
  will not allow while it runs. A Sidekick started by an older installer with
  another AutoHotkey version has another title and is not found here; Inno's
  own check for programs using the files catches that one. }
function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  if not CloseSidekick() then
    Result := 'Sidekick is still running. Right-click its icon in the system tray, choose Exit, and run this again.';
end;

function InitializeUninstall(): Boolean;
begin
  Result := CloseSidekick();
  if not Result then
    MsgBox('Sidekick is still running.' + #13#10#13#10 +
           'Right-click its icon in the system tray, choose Exit, and run this again.',
           mbError, MB_OK);
end;

{ Uninstalling removes the program and leaves what is yours: the data folder
  (your menu, clipboard history, notes and expansions) and settings.ini. Said
  at the end, so nobody believes it went when it did not. }
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if (CurUninstallStep = usPostUninstall) and
     (DirExists(ExpandConstant('{app}\data')) or FileExists(ExpandConstant('{app}\settings.ini'))) then
    MsgBox('Sidekick is uninstalled.' + #13#10#13#10 +
           'Your own content is still in ' + ExpandConstant('{app}') +
           ' - the data folder and settings.ini - in case you reinstall. ' +
           'Delete that folder if you do not want it.', mbInformation, MB_OK);
end;
