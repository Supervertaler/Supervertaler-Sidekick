#!/usr/bin/env bash
# Proves tools/check-stage.sh refuses what it is there to refuse. A check that
# has only ever been seen passing a clean build has not been seen working.
#
#   bash tools/check-stage-test.sh
#
# Each case stages the committed files, plants one problem, and expects the
# check to fail. Nothing here reads or copies anything from the working
# folder: the stage comes from git, and every planted file is made up.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$ROOT/tools/check-stage.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Assembled at run time, so this file never contains a key-shaped string and
# the pre-commit hook has nothing to object to.
FAKE_KEY="sk-ant-""api03-$(printf 'x%.0s' {1..40})"

fail=0
stage() {
    rm -rf "$WORK/s"
    mkdir -p "$WORK/s"
    git -C "$ROOT" archive --format=tar HEAD | tar -x -C "$WORK/s"
    rm -rf "$WORK/s/.githooks" "$WORK/s/.gitignore" "$WORK/s/installer" "$WORK/s/tools"
}
expect() {   # expect pass|fail "name"
    local want="$1" name="$2" out status
    out="$(bash "$CHECK" "$WORK/s" 2>&1)"; status=$?
    if [[ "$want" == pass && $status -eq 0 ]] || [[ "$want" == fail && $status -ne 0 ]]; then
        echo "ok   $name"
    else
        echo "FAIL $name (exit $status)"; echo "$out" | sed 's/^/     /'; fail=$((fail + 1))
    fi
    # Whatever happened, the key itself must never be printed.
    if [[ "$out" == *"$FAKE_KEY"* ]]; then
        echo "FAIL $name: the output printed the key"; fail=$((fail + 1))
    fi
}

stage;                                                   expect pass "the committed files pass"
stage; mkdir "$WORK/s/data"; echo '{}' > "$WORK/s/data/clipboard.json"
                                                         expect fail "a data folder"
stage; echo '[Keys]' > "$WORK/s/settings.ini";           expect fail "settings.ini at the top"
stage; echo '[Keys]' > "$WORK/s/lib/settings.ini";       expect fail "settings.ini inside lib"
stage; echo 'x' > "$WORK/s/data.example/expansions.gen.ahk"
                                                         expect fail "a generated expansions script"
stage; echo 'x' > "$WORK/s/packs/scratchpad.txt";        expect fail "a scratchpad note"
stage; echo 'x' > "$WORK/s/lib/AutoCorrect.ahk";         expect fail "a personal script"
stage; echo 'x' > "$WORK/s/notes.txt";                   expect fail "an unexpected top-level file"
stage; echo 'x' > "$WORK/s/.secret";                     expect fail "an unexpected hidden file"
stage; echo "key := \"$FAKE_KEY\"" > "$WORK/s/lib/extra.ahk"
                                                         expect fail "a key-shaped string in code"
stage; echo "{\"k\": \"$FAKE_KEY\"}" > "$WORK/s/data.example/menu2.json"
                                                         expect fail "a key-shaped string in the starter data"

echo "failures=$fail"
exit $(( fail > 0 ))
