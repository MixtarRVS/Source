#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root="$script_dir/../Generated/corev07-root"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --root)
            [ "$#" -ge 2 ] || { echo "keyboard-verify: missing --root value" >&2; exit 64; }
            root=$2
            shift 2
            ;;
        *)
            echo "keyboard-verify: unknown argument: $1" >&2
            exit 64
            ;;
    esac
done

fail() {
    echo "keyboard-verify: FAIL: $*" >&2
    exit 1
}

require_file() {
    [ -s "$root$1" ] || fail "missing or empty $1"
}

require_text() {
    grep -Fq -- "$2" "$root$1" || fail "$1 does not contain: $2"
}

require_file /System/Init/ConsoleSetup
[ -x "$root/System/Init/ConsoleSetup" ] || fail "ConsoleSetup is not executable"
file "$root/System/Init/ConsoleSetup" | grep -Fq 'statically linked' || \
    fail "ConsoleSetup is not statically linked"

require_file /System/Shells/zsh
require_file /System/Shells/zshenv
require_file /System/Shells/zshrc
strings "$root/System/Shells/zsh" | grep -Fxq '/System/Shells/zshenv' || \
    fail "ZSH does not embed the immutable zshenv path"

require_text /System/Shells/zshenv 'LANG="${LANG:-C.UTF-8}"'
require_text /System/Shells/zshenv 'LC_CTYPE="${LC_CTYPE:-C.UTF-8}"'
require_text /System/Shells/zshenv 'source /System/Shells/zshrc'
require_text /System/Shells/zshrc "bindkey '^?' backward-delete-char"
require_text /System/Shells/zshrc "bindkey '^H' backward-delete-char"
require_text /System/Shells/zshrc "bindkey '^[[3~' delete-char"
require_text /System/Shells/zshrc 'mixtar-ignore-function-key'
require_text /System/Shells/zshrc 'setopt PROMPT_SUBST'

[ ! -e "$root/System/Configuration/Settings/ZSH" ] || \
    fail "duplicate Settings/ZSH configuration tree exists"

ROOT="$root" python3 - <<'PY'
import os
import pathlib
import sqlite3
import sys

root = pathlib.Path(os.environ["ROOT"])

def values(path, table, expected):
    connection = sqlite3.connect(path)
    try:
        actual = dict(connection.execute(
            f'SELECT key, value FROM "{table}" WHERE key IN '
            f'({",".join("?" for _ in expected)})',
            tuple(expected),
        ))
    finally:
        connection.close()
    missing = {key: value for key, value in expected.items()
               if actual.get(key) != value}
    if missing:
        raise SystemExit(f"{path}: invalid settings: {missing}; actual={actual}")

values(
    root / "System/Configuration/MixtarRVS.config",
    "meta",
    {
        "console.setup": "/System/Init/ConsoleSetup",
        "console.keymap": "pl",
        "locale.name": "C.UTF-8",
        "persistence.device.wait.ms": "5000",
    },
)
values(
    root / "System/Configuration/ZSH/ZSH.config",
    "setting",
    {
        "startup.global": "/System/Shells/zshenv",
        "startup.interactive": "/System/Shells/zshrc",
        "locale": "C.UTF-8",
        "keyboard.layout": "pl",
    },
)
PY

set +e
"$root/System/Init/ConsoleSetup" /not-used invalid >/dev/null 2>&1
invalid_rc=$?
set -e
[ "$invalid_rc" -eq 65 ] || fail "ConsoleSetup did not reject invalid keymap"

echo "corev08-keyboard-verify: OK"
