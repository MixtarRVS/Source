#!/usr/bin/env bash
set -Eeuo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    printf '%s\n' 'usage: corev09-build-image.sh STAGED_ROOT [OUTPUT.ext4]' >&2
    exit 64
fi
[ "${EUID:-$(id -u)}" -eq 0 ] || {
    printf '%s\n' 'corev09-build-image: root privileges are required' >&2
    exit 77
}

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/../../.." && pwd)
root=$(realpath "$1")
output_arg=${2:-"$repo_root/out/server/MixtarRVS-0.9-Candidate.ext4"}
mkdir -p "$(dirname -- "$output_arg")"
output=$(realpath -m "$output_arg")
next="$output.next.$$"
verify_log="$output.verify.log"
fsck_log="$output.e2fsck.log"
manifest="$output.provenance"
image_size=${MIXTAR_IMAGE_SIZE:-2G}
mount_dir=$(mktemp -d /tmp/mixtar-corev09-image.XXXXXX)
mounted=0

fail() {
    printf 'corev09-build-image: %s\n' "$*" >&2
    exit 1
}

cleanup() {
    rc=$?
    if [ "$mounted" -eq 1 ] && mountpoint -q "$mount_dir"; then
        umount "$mount_dir" || rc=1
    fi
    rmdir "$mount_dir" 2>/dev/null || true
    rm -f -- "$next"
    exit "$rc"
}
trap cleanup EXIT

case "$root" in
    /|/System|/Temporary) fail "unsafe staged root: $root" ;;
esac
case "$output" in
    "$repo_root"/out/server/*|/tmp/*) ;;
    *) fail "output is outside approved candidate locations: $output" ;;
esac
case "$image_size" in
    *[!0-9MG]*) fail "invalid MIXTAR_IMAGE_SIZE: $image_size" ;;
esac
[ -d "$root/System" ] || fail "staged root has no /System"
[ -x "$root/System/Init/MixtarRVS" ] || fail "staged root has no MixtarRVS PID1"
[ ! -e "$output" ] || fail "candidate already exists: $output"
[ ! -b "$output" ] || fail "refusing block-device output"

for tool in truncate mke2fs tune2fs e2fsck mount umount sha256sum; do
    command -v "$tool" >/dev/null 2>&1 || fail "missing build-host tool: $tool"
done

bash "$script_dir/corev09-verify.sh" "$root" 0.9

truncate -s "$image_size" "$next"
mke2fs -q -F -t ext4 -L MIXTARBUILD -m 0 \
    -E lazy_itable_init=0,lazy_journal_init=0 \
    -d "$root" "$next"
tune2fs -c 0 -i 0 "$next" >/dev/null

if ! e2fsck -fn "$next" >"$fsck_log" 2>&1; then
    cat "$fsck_log" >&2
    fail "candidate filesystem failed pre-mount e2fsck"
fi

mount -o loop,ro "$next" "$mount_dir"
mounted=1
bash "$script_dir/corev09-verify.sh" "$mount_dir" 0.9 | tee "$verify_log"
umount "$mount_dir"
mounted=0

if ! e2fsck -fn "$next" >>"$fsck_log" 2>&1; then
    cat "$fsck_log" >&2
    fail "candidate filesystem failed final e2fsck"
fi

mv -- "$next" "$output"
image_hash=$(sha256sum "$output" | awk '{print $1}')
updates_hash=$(sha256sum "$root/System/Configuration/Updates.config" | awk '{print $1}')
efi_hash=$(sha256sum "$root/System/EFI/MixtarRVS/0.9.efi" | awk '{print $1}')
cat >"$manifest" <<EOF
format=MixtarRVS-CoreV09-Image-v1
version=0.9
filesystem=ext4
label=MIXTARBUILD
image_sha256=$image_hash
updates_config_sha256=$updates_hash
efi_sha256=$efi_hash
source_root=$root
EOF
printf '%s  %s\n' "$image_hash" "$(basename -- "$output")" >"$output.sha256"
printf 'CORE_V09_IMAGE=%s\n' "$output"
printf 'CORE_V09_IMAGE_SHA256=%s\n' "$image_hash"
echo MIXTARRVS_COREV09_IMAGE_GATE=PASS
