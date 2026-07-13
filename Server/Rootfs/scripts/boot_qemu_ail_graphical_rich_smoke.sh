#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"
log_dir="$repo_root/Server/Rootfs/Generated/boot"
log="$log_dir/boot-ail-graphical-rich-smoke.log"
timeout_seconds="${RVS_BOOT_AIL_GRAPHICAL_RICH_SMOKE_TIMEOUT:-85}"

mkdir -p "$log_dir"

MIXTAR_DESKTOP_PROFILE=rich bash "$script_dir/build_graphical_initramfs.sh" >/dev/null

set +e
MIXTAR_QEMU_INIT="/System/Init/MixtarAil" \
MIXTAR_QEMU_INIT_PARAM="rdinit" \
MIXTAR_QEMU_APPEND_EXTRA="mixtar.target=graphical-smoke mixtar.dbus=1" \
MIXTAR_QEMU_DISPLAY="${MIXTAR_QEMU_DISPLAY:-none}" \
  timeout "${timeout_seconds}s" bash "$script_dir/boot_qemu_graphical.sh" >"$log" 2>&1
rc=$?
set -e

if grep -q "Mixtar: implementation ailang" "$log" &&
   grep -q "desktop-xauth: ok" "$log" &&
   grep -q "desktop-wayland: ok" "$log" &&
   grep -q "desktop-dbus: ok" "$log" &&
   grep -q "desktop-panel: ok" "$log" &&
   grep -q "desktop-terminal: ok" "$log" &&
   grep -q "desktop-x11-smoke: ok" "$log" &&
   grep -q "boot-smoke: ok" "$log"; then
  echo "boot-ail-graphical-rich-smoke: ok"
  echo "boot-ail-graphical-rich-smoke: log=$log"
  exit 0
fi

echo "boot-ail-graphical-rich-smoke: failed rc=$rc" >&2
echo "boot-ail-graphical-rich-smoke: log=$log" >&2
tail -160 "$log" >&2 || true
exit 1
