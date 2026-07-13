#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"

kernel="${1:-$repo_root/Server/Kernel/Generated/boot/bzImage-7.0.9-mixtar-qemu}"
initrd="${2:-$repo_root/Server/Rootfs/Generated/mixtar-graphical-initramfs.cpio.gz}"
extra_append="${MIXTAR_QEMU_APPEND_EXTRA:-}"
display="${MIXTAR_QEMU_DISPLAY:-gtk,gl=off}"
init_path="${MIXTAR_QEMU_INIT:-/init}"
init_param="${MIXTAR_QEMU_INIT_PARAM:-init}"
video_device="${MIXTAR_QEMU_VIDEO_DEVICE:-virtio-vga}"
spice_enabled="${MIXTAR_QEMU_SPICE:-0}"
spice_addr="${MIXTAR_QEMU_SPICE_ADDR:-127.0.0.1}"
spice_port="${MIXTAR_QEMU_SPICE_PORT:-5930}"
base_append="console=ttyS0 earlyprintk=serial panic=-1 $init_param=$init_path"

if [[ "$extra_append" != *"mixtar.target="* ]]; then
  base_append="$base_append mixtar.target=graphical"
fi

if [[ -n "$extra_append" ]]; then
  base_append="$base_append $extra_append"
fi

if [[ ! -f "$kernel" ]]; then
  echo "boot-qemu-graphical: kernel image missing: $kernel" >&2
  exit 1
fi

if [[ ! -f "$initrd" ]]; then
  echo "boot-qemu-graphical: graphical initramfs missing: $initrd" >&2
  echo "boot-qemu-graphical: run Server/Rootfs/scripts/build_graphical_initramfs.sh first" >&2
  exit 1
fi

accel="tcg"
cpu="max"
if [[ -e /dev/kvm ]]; then
  accel="kvm"
  cpu="host"
fi

qemu_args=(
  -machine "q35,accel=$accel" \
  -cpu "$cpu" \
  -m 1024M \
  -smp 2 \
  -kernel "$kernel" \
  -initrd "$initrd" \
  -append "$base_append" \
  -device "$video_device" \
  -device virtio-keyboard-pci \
  -device virtio-mouse-pci \
  -device qemu-xhci \
  -device usb-tablet \
  -device usb-kbd \
  -serial mon:stdio \
  -no-reboot
)

if [[ "$spice_enabled" == "1" || "$spice_enabled" == "ON" || "$spice_enabled" == "on" ]]; then
  qemu_args+=(
    -spice "addr=$spice_addr,port=$spice_port,disable-ticketing=on"
    -display "$display"
  )
  echo "boot-qemu-graphical: SPICE listening on $spice_addr:$spice_port" >&2
else
  qemu_args+=(-display "$display")
fi

exec qemu-system-x86_64 "${qemu_args[@]}"
