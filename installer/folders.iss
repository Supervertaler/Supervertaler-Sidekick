{ Where Sidekick is suggested to go, and where it may not go. Pascal only, no
  section header: it is #included inside the [Code] section of
  Supervertaler-Sidekick.iss, and of the test tools/installer-folders-test.sh
  builds, which runs it against sample config files - it is the one part of
  the installer that reads something it did not write. }

{ The Supervertaler data folder, found the way the plugins and Sidekick find
  it: user_data_path in %APPDATA%\Supervertaler\config.json. Read with plain
  string matching, since the installer has no JSON reader; anything it cannot
  read, or a folder that is not there, falls back to the default the products
  use, C:\Users\<you>\Supervertaler. }
function DataFolderFrom(ConfigFile: String): String;
var
  Raw: AnsiString;
  S: String;
  P: Integer;
begin
  Result := '';
  if LoadStringFromFile(ConfigFile, Raw) then
  begin
    S := String(Raw);
    P := Pos('"user_data_path"', S);
    if P > 0 then
    begin
      S := Copy(S, P + Length('"user_data_path"'), MaxInt);
      P := Pos('"', S);
      if P > 0 then
      begin
        S := Copy(S, P + 1, MaxInt);
        P := Pos('"', S);
        if P > 0 then
        begin
          S := Copy(S, 1, P - 1);
          StringChangeEx(S, '\\', '\', True);
          S := RemoveBackslashUnlessRoot(Trim(S));
          if (S <> '') and DirExists(S) then Result := S;
        end;
      end;
    end;
  end;
  if Result = '' then
    Result := ExpandConstant('{%USERPROFILE}') + '\Supervertaler';
end;

function SuggestedFolder(Param: String): String;
begin
  Result := DataFolderFrom(ExpandConstant('{userappdata}\Supervertaler\config.json')) + '\sidekick';
end;

function IsUnder(Path, Root: String): Boolean;
begin
  Result := Pos(AddBackslash(Lowercase(Root)), AddBackslash(Lowercase(Path))) = 1;
end;
