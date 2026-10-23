#!/usr/bin/env bash
# Checks a staged copy of Sidekick before it is packaged, and fails if anything
# in it should not leave this computer. Used by build-installer.sh; tested by
# check-stage-test.sh.
#
#   bash tools/check-stage.sh <folder>
#
# Three checks, each of which alone would stop a known mistake:
#   1. Only the top-level files and folders on ALLOWED. An allow-list, not a
#      deny-list: something new stops the build until someone decides it
#      belongs, rather than shipping because nobody thought to forbid it.
#   2. No file that holds personal data, by name, anywhere in the tree.
#   3. Nothing shaped like an API key, by the pre-commit hook's own pattern -
#      read from the hook, so the two cannot disagree about what a key is.
set -euo pipefail

STAGE="${1:?usage: check-stage.sh <folder>}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -d "$STAGE" ]] || { echo "ERROR: no such folder: $STAGE" >&2; exit 1; }

ALLOWED=" Sidekick.ahk lib packs data.example Sidekick.ico Sidekick-on-dark.ico settings.example.ini CHANGELOG.md README.md LICENSE "
shopt -s dotglob nullglob
for path in "$STAGE"/*; do
    name="$(basename "$path")"
    [[ "$ALLOWED" == *" $name "* ]] || {
        echo "ERROR: '$name' is not on the list of what may ship." >&2
        echo "       If it should, add it to ALLOWED in tools/check-stage.sh." >&2
        exit 1; }
done
shopt -u dotglob nullglob

PRIVATE="$(find "$STAGE" \( -type d -iname data \) \
    -o \( -type f \( \( -iname '*.ini' ! -iname 'settings.example.ini' \) \
                     -o -iname 'expansions.gen.ahk' -o -iname 'clipboard.json' \
                     -o -iname 'scratchpad.txt' -o -iname 'api-keys.json' \
                     -o -iname 'api_keys.*' -o -iname '*.env' \
                     -o -iname 'capture.paused' -o -iname 'AutoCorrect.ahk' \
                     -o -iname 'AHK.ahk' \) \) )"
[[ -z "$PRIVATE" ]] || {
    echo "ERROR: refusing to package files that hold personal data:" >&2
    echo "$PRIVATE" | sed "s|^$STAGE/|       |" >&2
    exit 1; }

PATTERN="$(sed -n "s/^PATTERN='\(.*\)'\$/\1/p" "$ROOT/.githooks/pre-commit")"
[[ -n "$PATTERN" ]] || { echo "ERROR: could not read the key pattern from .githooks/pre-commit" >&2; exit 1; }
# File names only, never the matching lines: the output of a build that caught
# a key must not print the key.
KEYS="$(grep -rl -- "$PATTERN" "$STAGE" || true)"
[[ -z "$KEYS" ]] || {
    echo "ERROR: refusing to package files containing something shaped like an API key:" >&2
    echo "$KEYS" | sed "s|^$STAGE/|       |" >&2
    exit 1; }

echo "checked: $(find "$STAGE" -type f | wc -l) files, nothing private, no keys"
