#!/usr/bin/env bash
# Builds the Sidekick installer: dist/Supervertaler-Sidekick-Setup-<version>.exe
#
# What goes in is what git has COMMITTED - the same files anyone can see on
# GitHub - and nothing from the working folder. The folder Sidekick runs from
# is full of things that must never leave this computer: data\ (the menu,
# clipboard history, notes, expansions), settings.ini with its API keys, and
# personal scripts. .gitignore keeps them out of git, so taking the files from
# git keeps them out of the installer. Then the staged files are checked again
# anyway, because this is the step after which a mistake is published.
#
# A change you have not committed is not in the installer. That is the point:
# what users get is what GitHub shows.
#
# Publishes nothing.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ISCC="/c/Users/$USERNAME/AppData/Local/Programs/Inno Setup 6/ISCC.exe"

[[ -x "$ISCC" ]] || { echo "ERROR: Inno Setup not found at $ISCC" >&2
                      echo "       winget install --id JRSoftware.InnoSetup" >&2; exit 1; }

# --- the AutoHotkey that ships ---------------------------------------------
# An unmodified copy of the one installed here, pinned by SHA-256 so that a
# different file can never reach a user unnoticed: when AutoHotkey is updated
# on this machine the build stops until the pin is updated with it, which is
# also the moment to check Sidekick still runs on the new one.
AHK_EXE="/c/Program Files/AutoHotkey/v2/AutoHotkey64.exe"
AHK_LICENSE="/c/Program Files/AutoHotkey/license.txt"
AHK_VERSION="2.0.26"
AHK_SHA256="a2a54b8abc476d7671d4de0771bb54bf5f2373d79ff6871d0ba6a62c3b88ae00"

[[ -f "$AHK_EXE" && -f "$AHK_LICENSE" ]] || {
    echo "ERROR: AutoHotkey v2 is not installed where expected: $AHK_EXE" >&2; exit 1; }
actual="$(sha256sum < "$AHK_EXE" | cut -d' ' -f1)"
[[ "$actual" == "$AHK_SHA256" ]] || {
    echo "ERROR: $AHK_EXE is not the pinned AutoHotkey $AHK_VERSION." >&2
    echo "       Its SHA-256 is $actual." >&2
    echo "       If AutoHotkey was updated on purpose, check Sidekick on it and" >&2
    echo "       update AHK_VERSION and AHK_SHA256 in this script." >&2
    exit 1; }

# --- the version -------------------------------------------------------------
# Sidekick's changelog is dated rather than numbered, so the installer is too:
# the date of the commit it was built from, then which commit of that day, so
# two releases on one day still differ. 2026.10.17.2 is the second of the 17th.
DAY="$(git -C "$ROOT" log -1 --format=%cd --date=format:%Y.%m.%d HEAD)"
NTH="$(git -C "$ROOT" log --format=%cd --date=format:%Y.%m.%d HEAD | grep -c "^$DAY\$")"
VERSION="$(echo "$DAY" | awk -F. '{ printf "%d.%d.%d", $1, $2, $3 }').$NTH"
echo "version: $VERSION ($(git -C "$ROOT" log -1 --format='%h %s' HEAD))"

UNCOMMITTED="$(git -C "$ROOT" status --porcelain --untracked-files=no)"
if [[ -n "$UNCOMMITTED" ]]; then
    echo "NOTE: these changes are not committed, so they are NOT in the installer:"
    echo "$UNCOMMITTED" | sed 's/^/      /'
fi

# --- stage what git has committed --------------------------------------------
# Outside the Google Drive folder, where Drive cannot lock a file mid-build, and
# removed however the build ends, so a failed run leaves no copy of anything.
STAGE="/c/Temp/sidekick-stage"
OUT="/c/Temp/sidekick-installer"
trap 'rm -rf "$STAGE" "$OUT"' EXIT
rm -rf "$STAGE" "$OUT"
mkdir -p "$STAGE" "$OUT"

git -C "$ROOT" archive --format=tar HEAD | tar -x -C "$STAGE"

# Repository plumbing, of no use to someone running the program.
rm -rf "$STAGE/.githooks" "$STAGE/.gitignore" "$STAGE/installer" "$STAGE/tools"

# --- refuse anything that is not meant to ship -------------------------------
bash "$ROOT/tools/check-stage.sh" "$STAGE"

# --- the runtime, added after the checks: it is a binary, pinned above -------
mkdir -p "$STAGE/AutoHotkey"
cp "$AHK_EXE" "$AHK_LICENSE" "$STAGE/AutoHotkey/"
cat > "$STAGE/AutoHotkey/SOURCE.txt" <<EOF
AutoHotkey64.exe in this folder is AutoHotkey $AHK_VERSION, unmodified, as
released by the AutoHotkey project at https://www.autohotkey.com/

It is free software under the GNU General Public License, version 2, which is
in license.txt beside it. Its source code is at
https://github.com/AutoHotkey/AutoHotkey/tree/v$AHK_VERSION

Supervertaler Sidekick runs on it: the program itself is Sidekick.ahk and the
lib folder, one level up.
EOF

# --- compile -----------------------------------------------------------------
SETUP_NAME="Supervertaler-Sidekick-Setup-$VERSION.exe"
MSYS2_ARG_CONV_EXCL="/D;/O" "$ISCC" \
    "/DAppVersion=$VERSION" \
    "/DAhkVersion=$AHK_VERSION" \
    "/DStage=$(cygpath -w "$STAGE")" \
    "/O$(cygpath -w "$OUT")" \
    "$(cygpath -w "$ROOT/installer/Supervertaler-Sidekick.iss")" \
    > "$OUT/iscc.log" 2>&1 || ISCC_STATUS=$?
ISCC_STATUS=${ISCC_STATUS:-0}
grep -E "^Successful|rror" "$OUT/iscc.log" || true
[[ $ISCC_STATUS -eq 0 && -f "$OUT/$SETUP_NAME" ]] || {
    echo "ERROR: Inno Setup failed (exit $ISCC_STATUS)" >&2; exit 1; }

# What the compiler actually packed, in its own words, kept beside the
# installer: the list to read before publishing one, and proof afterwards of
# what a given release contained. It has to match the stage file for file.
MANIFEST="${SETUP_NAME%.exe}.files.txt"
STAGE_W="$(cygpath -w "$STAGE")\\"
sed -n 's/^ *Compressing: *//p' "$OUT/iscc.log" | tr -d '\r' \
    | while IFS= read -r f; do echo "${f#"$STAGE_W"}"; done | sort > "$OUT/$MANIFEST"
PACKED=$(wc -l < "$OUT/$MANIFEST")
STAGED=$(find "$STAGE" -type f | wc -l)
[[ $PACKED -eq $STAGED ]] || {
    echo "ERROR: Inno packed $PACKED files but $STAGED were staged." >&2; exit 1; }

mkdir -p "$ROOT/dist"
rm -f "$ROOT/dist/$SETUP_NAME" "$ROOT/dist/$MANIFEST"
cp "$OUT/$SETUP_NAME" "$OUT/$MANIFEST" "$ROOT/dist/"

echo
echo "OK  $(cygpath -w "$ROOT/dist/$SETUP_NAME")"
echo "    $PACKED files, listed in $MANIFEST"
echo "    $(( $(stat -c%s "$ROOT/dist/$SETUP_NAME") / 1024 )) KB, SHA-256 $(sha256sum < "$ROOT/dist/$SETUP_NAME" | cut -d' ' -f1)"
echo
echo "NOT SIGNED. Windows SmartScreen will say the publisher is unknown the"
echo "first time someone runs it, as it does for the memoQ installer."
