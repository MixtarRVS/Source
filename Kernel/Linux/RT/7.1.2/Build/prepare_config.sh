#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"

kernel_src="${1:-$repo_root/System/Kernel/Generated/src/linux-7.0.9}"
build_dir="${2:-$repo_root/System/Kernel/Generated/build/linux-7.0.9-mixtar-qemu}"
fragment="$repo_root/System/Kernel/configs/mixtar-server-qemu.fragment"

if [[ ! -f "$kernel_src/Makefile" ]]; then
  echo "kernel-config: kernel source missing: $kernel_src" >&2
  echo "kernel-config: run System/Kernel/scripts/kernel_fetch.sh all first" >&2
  exit 1
fi

if [[ ! -f "$fragment" ]]; then
  echo "kernel-config: fragment missing: $fragment" >&2
  exit 1
fi

mkdir -p "$build_dir"

make -C "$kernel_src" O="$build_dir" x86_64_defconfig
"$kernel_src/scripts/kconfig/merge_config.sh" -m -O "$build_dir" "$build_dir/.config" "$fragment"
make -C "$kernel_src" O="$build_dir" olddefconfig

echo "kernel-config: wrote $build_dir/.config"
