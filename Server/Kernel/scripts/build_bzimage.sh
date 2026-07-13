#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"

kernel_src="${1:-$repo_root/Server/Kernel/Generated/src/linux-7.0.9}"
build_dir="${2:-$repo_root/Server/Kernel/Generated/build/linux-7.0.9-mixtar-qemu}"
jobs="${JOBS:-$(nproc)}"

if [[ ! -f "$build_dir/.config" ]]; then
  echo "kernel-build: config missing: $build_dir/.config" >&2
  echo "kernel-build: run Server/Kernel/scripts/prepare_config.sh first" >&2
  exit 1
fi

make -C "$kernel_src" O="$build_dir" -j"$jobs" bzImage

mkdir -p "$repo_root/Server/Kernel/Generated/boot"
cp "$build_dir/arch/x86/boot/bzImage" "$repo_root/Server/Kernel/Generated/boot/bzImage-7.0.9-mixtar-qemu"

echo "kernel-build: wrote Server/Kernel/Generated/boot/bzImage-7.0.9-mixtar-qemu"
