#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"

kernel="${1:-$repo_root/Server/Kernel/Generated/boot/bzImage-7.0.9-mixtar-qemu}"
initrd="${2:-$repo_root/Server/Rootfs/Generated/mixtar-initramfs.cpio.gz}"
extra_append="${MIXTAR_QEMU_APPEND_EXTRA:-}"
init_path="${MIXTAR_QEMU_INIT:-/System/Init/MixtarRVS}"
init_param="${MIXTAR_QEMU_INIT_PARAM:-rdinit}"

if [[ ! -f "$kernel" ]]; then
  echo "boot-qemu: kernel image missing: $kernel" >&2
  echo "boot-qemu: build a bzImage first, then rerun this script" >&2
  exit 1
fi

if [[ ! -f "$initrd" ]]; then
  echo "boot-qemu: initramfs missing: $initrd" >&2
  echo "boot-qemu: run Server/Rootfs/scripts/build_initramfs.sh first" >&2
  exit 1
fi

accel="tcg"
cpu="max"
if [[ -e /dev/kvm ]]; then
  accel="kvm"
  cpu="host"
fi

exec qemu-system-x86_64 \
  -machine "q35,accel=$accel" \
  -cpu "$cpu" \
  -m 512M \
  -smp 2 \
  -kernel "$kernel" \
  -initrd "$initrd" \
  -append "console=ttyS0 earlyprintk=serial panic=-1 devtmpfs.mount=0 $init_param=$init_path $extra_append" \
  -nographic \
  -no-reboot
