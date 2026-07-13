#!/usr/bin/env bash
set -Eeuo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    printf '%s\n' 'usage: corev09-qemu-gate.sh IMAGE.ext4 [QEMU_IMAGE.ext4]' >&2
    exit 64
fi
[ "${EUID:-$(id -u)}" -eq 0 ] || {
    printf '%s\n' 'corev09-qemu-gate: root privileges are required' >&2
    exit 77
}

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/../../.." && pwd)
image=$(realpath "$1")
qemu_arg=${2:-"${image%.ext4}-QemuSerial.ext4"}
qemu_image=$(realpath -m "$qemu_arg")
log="${qemu_image%.ext4}.qemu.log"
mount_dir=$(mktemp -d /tmp/mixtar-corev09-qemu.XXXXXX)
efi=$(mktemp /tmp/mixtar-corev09-qemu-efi.XXXXXX)
mounted=0
boot_wait=${MIXTAR_QEMU_BOOT_WAIT:-40}
timeout_seconds=${MIXTAR_QEMU_TIMEOUT:-80}

fail() {
    printf 'corev09-qemu-gate: %s\n' "$*" >&2
    exit 1
}

cleanup() {
    rc=$?
    if [ "$mounted" -eq 1 ] && mountpoint -q "$mount_dir"; then
        umount "$mount_dir" || rc=1
    fi
    rm -f -- "$efi"
    rmdir "$mount_dir" 2>/dev/null || true
    exit "$rc"
}
trap cleanup EXIT

case "$qemu_image" in
    "$repo_root"/out/server/*|/tmp/*) ;;
    *) fail "QEMU image is outside approved candidate locations: $qemu_image" ;;
esac
case "$boot_wait:$timeout_seconds" in
    *[!0-9:]*) fail 'QEMU timing values must be integers' ;;
esac
[ -f "$image" ] || fail "candidate image is missing: $image"
[ ! -e "$qemu_image" ] || fail "QEMU candidate already exists: $qemu_image"
for tool in qemu-system-x86_64 timeout mount umount e2fsck sha256sum python3; do
    command -v "$tool" >/dev/null 2>&1 || fail "missing QEMU-gate tool: $tool"
done

main_hash_before=$(sha256sum "$image" | awk '{print $1}')
cp --sparse=always -- "$image" "$qemu_image"

mount -o loop,rw "$qemu_image" "$mount_dir"
mounted=1
python3 - "$mount_dir/System/Configuration/MixtarRVS.config" <<'PY'
import sqlite3
import sys

database = sqlite3.connect(sys.argv[1])
with database:
    changed = database.execute(
        "UPDATE meta SET value='/System/Devices/ttyS0' WHERE key='console.path'"
    ).rowcount
if changed != 1:
    raise SystemExit(f"console.path update count={changed}")
print("QEMU_SERIAL_CONSOLE_POLICY=PASS")
PY
expected_ca=$(python3 - "$mount_dir/System/Configuration/Updates.config" <<'PY'
import sqlite3
import sys

database = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
value = database.execute(
    "SELECT replace(fingerprint, 'SHA256:', '') FROM trust_anchor "
    "WHERE id='curl-ca-bundle' AND enabled=1"
).fetchone()
if value is None:
    raise SystemExit("curl-ca-bundle trust is missing")
print(value[0])
PY
)
cp -- "$mount_dir/System/EFI/MixtarRVS/0.9.efi" "$efi"
bash "$script_dir/corev09-verify.sh" "$mount_dir" 0.9 >/dev/null
sync
umount "$mount_dir"
mounted=0

if ! e2fsck -fn "$qemu_image" >"$qemu_image.e2fsck.log" 2>&1; then
    cat "$qemu_image.e2fsck.log" >&2
    fail 'QEMU candidate filesystem failed e2fsck'
fi

console_input() {
    sleep "$boot_wait"
    printf '%s\n' '/System/Userland/id'
    printf '%s\n' 'print -r -- "MIXTAR_ZDOTDIR=$ZDOTDIR"'
    printf '%s\n' 'print -r -- "MIXTAR_GLOBAL=$MIXTAR_GLOBAL_ZSHRC_LOADED"'
    printf '%s\n' 'print -r -- "MIXTAR_PROMPT=$PROMPT"'
    printf '%s\n' 'print -P -- "MIXTAR_COLOR=$PROMPT"'
    printf '%s\n' '/System/Userland/mixtar-sha256 /System/Configuration/TLS/cacert.pem'
    printf '%s\n' '/System/Userland/gpgv --version'
    printf '%s\n' '/System/Userland/updates status /System/Configuration/Updates.config'
    printf '%s\n' 'echo MIXTARRVS_09_QEMU_RUNTIME=PASS'
    sleep 1
    printf '%s\n' '/System/Userland/poweroff'
}

set +e
console_input | timeout --foreground "${timeout_seconds}s" \
    qemu-system-x86_64 \
      -machine q35,accel=tcg -cpu max -smp 2 -m 1024 \
      -snapshot -net none -display none -serial stdio -monitor none -no-reboot \
      -kernel "$efi" \
      -append 'console=ttyS0 rdinit=/System/Init/MixtarBoot mixtar.root=/System/Devices/nvme0n1 mixtar.rootfstype=ext4 rw rootwait panic=-1' \
      -drive "file=$qemu_image,format=raw,if=none,id=mixtarroot" \
      -device 'nvme,drive=mixtarroot,serial=mixtarroot' \
      >"$log" 2>&1
qemu_rc=$?
set -e

cat "$log"
printf 'QEMU_RC=%s\n' "$qemu_rc"
[ "$qemu_rc" -eq 0 ] || fail "QEMU did not power off cleanly rc=$qemu_rc"
grep -F 'MixtarBoot: executing /System/Init/MixtarRVS' "$log" >/dev/null || fail 'MixtarBoot handoff marker missing'
grep -F 'MixtarRVS Init: headless core ready' "$log" >/dev/null || fail 'PID1 ready marker missing'
grep -F 'uid=1000 gid=1000' "$log" >/dev/null || fail 'user session identity marker missing'
grep -F 'MIXTAR_ZDOTDIR=/System/Shells/zsh.apx/Resources/Configuration' "$log" >/dev/null || fail 'global ZSH path marker missing'
grep -F 'MIXTAR_GLOBAL=1' "$log" >/dev/null || fail 'global ZSH configuration marker missing'
grep -F 'MIXTAR_PROMPT=' "$log" | grep -F '%F{' >/dev/null || fail 'color prompt policy marker missing'
grep -F "$expected_ca" "$log" >/dev/null || fail 'native CA bundle digest marker missing'
grep -F 'gpgv (GnuPG) 2.5.21' "$log" >/dev/null || fail 'native gpgv marker missing'
grep -F 'MIXTARRVS_09_QEMU_RUNTIME=PASS' "$log" >/dev/null || fail 'runtime marker missing'

python3 - "$log" <<'PY'
from pathlib import Path
import sys

data = Path(sys.argv[1]).read_bytes()
if b"\x1b[32m" not in data or b"\x1b[34m" not in data:
    raise SystemExit("colored ZSH prompt sequences are missing")
print("QEMU_ZSH_COLOR_GATE=PASS")
PY

for forbidden in \
    'Kernel panic' \
    'Attempted to kill init' \
    'not syncing' \
    'no such file or directory: /dev/null' \
    "can't open /dev/null" \
    "can't create temp file for here document" \
    'networking: sshd exited rc=' \
    '.cache: Permission denied'
do
    grep -F "$forbidden" "$log" >/dev/null && fail "forbidden runtime message: $forbidden"
done

main_hash_after=$(sha256sum "$image" | awk '{print $1}')
[ "$main_hash_before" = "$main_hash_after" ] || fail 'main candidate changed during QEMU gate'
printf 'MAIN_CANDIDATE_UNCHANGED=%s\n' "$main_hash_after"
echo QEMU_RUNTIME_WARNINGS=ABSENT
echo MIXTARRVS_COREV09_QEMU_GATE=PASS
