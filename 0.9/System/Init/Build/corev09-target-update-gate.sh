#!/usr/bin/env bash
set -Eeuo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    printf '%s\n' 'usage: corev09-target-update-gate.sh ROOT [LOG]' >&2
    exit 64
fi

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/../../.." && pwd)
root=$(realpath "$1")
log=${2:-"$repo_root/out/server/corev09-target-update-gate.log"}
db_rel=/Temporary/Updates-test.config
db="$root$db_rel"
work="$root/Temporary/Updates/Work"
canonical="$root/System/Configuration/Updates.config"
devices="$root/System/Devices"
zsh_installed=${MIXTAR_TEST_ZSH_INSTALLED:-5.9.1}
ncurses_installed=${MIXTAR_TEST_NCURSES_INSTALLED:-6.5}

fail() {
    printf 'corev09-target-update-gate: %s\n' "$*" >&2
    exit 1
}

case "$root" in
    /|/System|/Temporary) fail "unsafe root: $root" ;;
esac
for required in \
    "$canonical" \
    "$root/System/Userland/updates" \
    "$root/System/Userland/updates-ncurses" \
    "$root/System/Userland/mixtar-sha256" \
    "$root/System/Configuration/TLS/cacert.pem"
do
    [ -e "$required" ] || fail "missing target input: $required"
done
[ -d "$devices" ] || fail "native device mountpoint is missing"
[ ! -e "$root/dev" ] || fail "foreign /dev leaked into native root"
[ ! -e "$root/etc" ] || fail "foreign /etc leaked into native root"
[ ! -e "$root/usr" ] || fail "foreign /usr leaked into native root"
[ ! -e "$db" ] || fail "test database already exists: $db"
[ ! -e "$work" ] || fail "test work directory already exists: $work"
mountpoint -q "$devices" && fail "device mountpoint is already active"

mkdir -p "$(dirname -- "$log")"
exec > >(tee "$log") 2>&1

canonical_before=$(sha256sum "$canonical" | awk '{print $1}')
mounted=0
cleanup() {
    rc=$?
    if [ "$mounted" -eq 1 ] && mountpoint -q "$devices"; then
        umount "$devices" || rc=1
    fi
    rm -f -- "$db"
    case "$work" in
        "$root"/Temporary/Updates/Work) rm -rf -- "$work" ;;
        *) rc=1 ;;
    esac
    canonical_after=$(sha256sum "$canonical" 2>/dev/null | awk '{print $1}')
    if [ "$canonical_before" != "$canonical_after" ]; then
        printf '%s\n' 'CANONICAL_UPDATES_CONFIG_UNCHANGED=FAIL' >&2
        rc=1
    fi
    exit "$rc"
}
trap cleanup EXIT

cp -- "$canonical" "$db"
python3 - "$db" "$zsh_installed" "$ncurses_installed" <<'PY'
import sqlite3
import sys

database = sqlite3.connect(sys.argv[1])
with database:
    changed_zsh = database.execute(
        "UPDATE component SET installed_version=? WHERE id='zsh'",
        (sys.argv[2],),
    ).rowcount
    changed_ncurses = database.execute(
        "UPDATE component SET installed_version=? WHERE id='ncurses'",
        (sys.argv[3],),
    ).rowcount
    database.execute(
        "DELETE FROM observation WHERE component_id IN ('zsh', 'ncurses')"
    )
if changed_zsh != 1 or changed_ncurses != 1:
    raise SystemExit(
        f"component seed mismatch: zsh={changed_zsh} ncurses={changed_ncurses}"
    )
print("TEST_DATABASE_PREPARED=PASS")
PY

mount --bind /dev "$devices"
mounted=1

run_target() {
    label=$1
    seconds=$2
    shift 2
    printf '\n=== %s (timeout=%ss) ===\n' "$label" "$seconds"
    timeout --signal=TERM --kill-after=5s "${seconds}s" \
        /usr/sbin/chroot "$root" "$@"
}

run_target zsh-check 90 /System/Userland/updates check-zsh "$db_rel"
run_target zsh-fetch 120 /System/Userland/updates fetch-zsh "$db_rel"
run_target zsh-verify 60 /System/Userland/updates verify-zsh "$db_rel"
run_target ncurses-check 90 /System/Userland/updates-ncurses check-ncurses "$db_rel"
run_target ncurses-fetch 120 /System/Userland/updates-ncurses fetch-ncurses "$db_rel"
run_target ncurses-verify 60 /System/Userland/updates-ncurses verify-ncurses "$db_rel"

python3 - "$db" "$root" <<'PY'
from pathlib import Path
import sqlite3
import sys

database = sqlite3.connect(sys.argv[1])
root = Path(sys.argv[2])
rows = database.execute(
    """
    SELECT component_id, available_version, status, source_path,
           signature_path, detail
      FROM observation
     WHERE component_id IN ('zsh', 'ncurses')
     ORDER BY component_id
    """
).fetchall()
if len(rows) != 2:
    raise SystemExit(f"expected 2 observations, got {len(rows)}")

for component, version, status, source_path, signature_path, detail in rows:
    print(
        f"OBSERVATION component={component} version={version} "
        f"status={status} source={source_path} signature={signature_path}"
    )
    if status != "verified-source":
        raise SystemExit(
            f"{component}: expected verified-source, got {status}: {detail}"
        )
    for kind, configured_path in (
        ("source", source_path),
        ("signature", signature_path),
    ):
        if not configured_path.startswith("/Temporary/Updates/Work/"):
            raise SystemExit(f"{component}: unsafe {kind} path: {configured_path}")
        artifact = root / configured_path.lstrip("/")
        if not artifact.is_file() or artifact.stat().st_size == 0:
            raise SystemExit(f"{component}: missing {kind} artifact: {artifact}")

print("TARGET_SIGNED_SOURCE_STATE=PASS")
PY

canonical_after=$(sha256sum "$canonical" | awk '{print $1}')
[ "$canonical_before" = "$canonical_after" ]
printf 'CANONICAL_UPDATES_CONFIG_UNCHANGED=%s\n' "$canonical_after"
echo MIXTARRVS_TARGET_SOURCE_VERIFY_GATE=PASS
