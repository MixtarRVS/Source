#!/usr/bin/env bash
set -euo pipefail

VERSION="0.8"
KERNEL_VERSION="7.1.2"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"
kernel_workspace="${MIXTARRVS_COREV07_KERNEL_WORKSPACE:-${HOME}/.cache/mixtarrvs-corev07/kernel}"
kernel_src="$kernel_workspace/src/linux-$KERNEL_VERSION"
build_dir="$kernel_workspace/build/linux-$KERNEL_VERSION-mixtar-rt"
output_dir="$repo_root/Server/Rootfs/Generated/corev07-efi-build"
config="$build_dir/.config"
backup="$build_dir/.config.mixtar-lifecycle-test-backup"
image="$build_dir/arch/x86/boot/bzImage"
jobs="${JOBS:-$(nproc)}"
base_cmdline="quiet loglevel=3 console=ttyS0,115200 rdinit=/System/Init/MixtarRVS init=/System/Init/MixtarRVS devtmpfs.mount=0 panic=-1"

fail() {
    printf '%s\n' "corev08-lifecycle-test-efi: error: $*" >&2
    exit 1
}

restore_build() {
    if [[ ! -f "$backup" ]]; then
        return
    fi
    set +e
    cp "$backup" "$config"
    make -C "$kernel_src" O="$build_dir" olddefconfig >/dev/null
    make -C "$kernel_src" O="$build_dir" -j"$jobs" bzImage >/dev/null
    rm -f "$backup"
}

[[ -f "$kernel_src/Makefile" ]] || fail "missing kernel source: $kernel_src"
[[ -f "$config" ]] || fail "missing kernel config: $config"
[[ ! -e "$backup" ]] || fail "stale backup exists: $backup"
mkdir -p "$output_dir"
cp "$config" "$backup"
trap restore_build EXIT HUP INT TERM

for action in reboot poweroff; do
    cmdline="$base_cmdline mixtar.test.lifecycle=$action"
    "$kernel_src/scripts/config" --file "$config" --set-str CMDLINE "$cmdline"
    make -C "$kernel_src" O="$build_dir" olddefconfig >/dev/null
    make -C "$kernel_src" O="$build_dir" -j"$jobs" bzImage >/dev/null
    [[ -s "$image" ]] || fail "missing rebuilt image: $image"
    output="$output_dir/MixtarRVS-$VERSION-$action-test.efi"
    cp "$image" "$output"
    [[ "$(dd if="$output" bs=2 count=1 2>/dev/null)" == "MZ" ]] ||
        fail "test artifact is not EFI/PE: $output"
    strings "$output" | grep -F "mixtar.test.lifecycle=$action" >/dev/null ||
        fail "test artifact lacks lifecycle flag: $action"
    printf '%s\n' "corev08-lifecycle-test-efi: wrote $output"
done

