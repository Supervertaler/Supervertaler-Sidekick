#!/usr/bin/env bash
# Runs the installer's folder logic (installer/folders.iss) against sample
# config files and checks what it suggests and what it refuses.
#
#   bash tools/installer-folders-test.sh
#
# It builds a throwaway setup program whose only code is that file plus a
# start-up routine that writes the answers to a text file and stops - no
# window, nothing installed - then reads them back. The last case reads this
# computer's own config.json, read-only.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ISCC="/c/Users/$USERNAME/AppData/Local/Programs/Inno Setup 6/ISCC.exe"
[[ -x "$ISCC" ]] || { echo "ERROR: Inno Setup not found at $ISCC" >&2; exit 1; }

W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
WW="$(cygpath -w "$W")"
J="${WW//\\/\\\\}"                         # the same path, escaped as JSON writes it

mkdir -p "$W/data root"
printf '{\n  "user_data_path": "%s\\\\data root",\n  "other": 1\n}\n' "$J" > "$W/good.json"
printf '{"user_data_path" :  "%s\\\\data root\\\\"}' "$J"                 > "$W/trailing.json"
printf '{"user_data_path": "%s\\\\not there"}' "$J"                       > "$W/missing.json"
printf '{"theme": "dark"}'                                                > "$W/nokey.json"
printf '{"user_data_path": ""}'                                           > "$W/empty.json"
printf 'this is not json "user_data_path'                                 > "$W/broken.json"

cat > "$W/t.iss" <<EOF
[Setup]
AppName=folders-test
AppVersion=1
DefaultDirName={tmp}\\folders-test
PrivilegesRequired=lowest
CreateAppDir=no
Uninstallable=no
OutputDir=$WW\\out
OutputBaseFilename=folders-test

[Code]
#include "$(cygpath -w "$ROOT/installer/folders.iss")"

function B(V: Boolean): String;
begin
  if V then Result := 'yes' else Result := 'no';
end;

function InitializeSetup(): Boolean;
var
  S: String;
begin
  S := DataFolderFrom('$WW\\good.json') + #13#10 +
       DataFolderFrom('$WW\\trailing.json') + #13#10 +
       DataFolderFrom('$WW\\missing.json') + #13#10 +
       DataFolderFrom('$WW\\nokey.json') + #13#10 +
       DataFolderFrom('$WW\\empty.json') + #13#10 +
       DataFolderFrom('$WW\\broken.json') + #13#10 +
       DataFolderFrom('$WW\\absent.json') + #13#10 +
       B(IsUnder('C:\\Program Files\\Sidekick', 'C:\\Program Files')) + #13#10 +
       B(IsUnder('c:\\program files', 'C:\\Program Files')) + #13#10 +
       B(IsUnder('C:\\Program Files (x86)\\Sidekick', 'C:\\Program Files')) + #13#10 +
       B(IsUnder('D:\\Supervertaler\\sidekick', 'C:\\Program Files')) + #13#10 +
       SuggestedFolder('');
  SaveStringToFile('$WW\\result.txt', S, False);
  Result := False;
end;
EOF

"$ISCC" "$(cygpath -w "$W/t.iss")" > "$W/iscc.log" 2>&1 || {
    echo "ERROR: the test setup did not compile:" >&2; tail -20 "$W/iscc.log" >&2; exit 1; }
MSYS2_ARG_CONV_EXCL='*' timeout 60 "$W/out/folders-test.exe" /VERYSILENT /SUPPRESSMSGBOXES
[[ -f "$W/result.txt" ]] || { echo "ERROR: the test setup wrote no answers" >&2; exit 1; }
mapfile -t got < <(tr -d '\r' < "$W/result.txt")

FALLBACK="$USERPROFILE\\Supervertaler"
REAL_ROOT="$(sed -n 's/.*"user_data_path"[^"]*"\([^"]*\)".*/\1/p' "$APPDATA/Supervertaler/config.json" 2>/dev/null | sed 's/\\\\/\\/g')"
[[ -n "$REAL_ROOT" && -d "$(cygpath -u "$REAL_ROOT")" ]] || REAL_ROOT="$FALLBACK"

fail=0
check() {   # check index expected name
    if [[ "${got[$1]-}" == "$2" ]]; then echo "ok   $3"
    else echo "FAIL $3"; echo "     want: $2"; echo "     got:  ${got[$1]-<nothing>}"; fail=$((fail + 1)); fi
}
check 0  "$WW\\data root" "reads the data folder from config.json"
check 1  "$WW\\data root" "copes with spaces around the colon and a trailing backslash"
check 2  "$FALLBACK"      "a data folder that does not exist falls back"
check 3  "$FALLBACK"      "a config without the setting falls back"
check 4  "$FALLBACK"      "an empty setting falls back"
check 5  "$FALLBACK"      "a broken config falls back"
check 6  "$FALLBACK"      "no config at all falls back"
check 7  "yes"            "a folder inside Program Files is refused"
check 8  "yes"            "whatever its capitals"
check 9  "no"             "Program Files (x86) is not mistaken for Program Files"
check 10 "no"             "the data folder is not refused"
check 11 "$REAL_ROOT\\sidekick" "on this computer it suggests $REAL_ROOT\\sidekick"

echo "failures=$fail"
exit $(( fail > 0 ))
