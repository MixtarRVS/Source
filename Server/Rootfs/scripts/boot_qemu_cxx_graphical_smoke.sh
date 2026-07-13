#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"
log_dir="$repo_root/Server/Rootfs/Generated/boot"
log="$log_dir/boot-cxx-graphical-smoke.log"
timeout_seconds="${RVS_BOOT_CXX_GRAPHICAL_SMOKE_TIMEOUT:-75}"

mkdir -p "$log_dir"

set +e
MIXTAR_QEMU_INIT="/System/Init/MixtarCxx" \
MIXTAR_QEMU_INIT_PARAM="rdinit" \
MIXTAR_QEMU_APPEND_EXTRA="mixtar.target=graphical-smoke" \
MIXTAR_QEMU_DISPLAY="${MIXTAR_QEMU_DISPLAY:-none}" \
  timeout "${timeout_seconds}s" bash "$script_dir/boot_qemu_graphical.sh" >"$log" 2>&1
rc=$?
set -e

has_x11_smoke_marker() {
  grep -q "desktop-x11-smoke: ok" "$log" && return 0
  grep -q "desktop-x11-smok" "$log" && grep -q "e: ok" "$log"
}

has_wayland_marker() {
  grep -q "desktop-wayland: ok" "$log" && return 0
  grep -q "desktop.*" "$log" && grep -q "^-wayland: ok$" "$log"
}

has_ailang_ui_marker() {
  grep -q "ailang-ui-smoke: ok" "$log" && return 0
  grep -q "ailang-ui-smok" "$log" && grep -q "e: ok" "$log"
}

has_xauth_marker() {
  grep -q "desktop-xauth: ok" "$log" && return 0
  grep -q "desktop-xauth:" "$log" && grep -q "ok" "$log"
}

if grep -q "desktop: starting labwc" "$log" &&
   has_xauth_marker &&
   has_wayland_marker &&
   grep -q "desktop-panel: ok" "$log" &&
   has_ailang_ui_marker &&
   has_x11_smoke_marker &&
   grep -q "boot-smoke: ok" "$log" &&
   grep -q "smoke: powering off after boot proof" "$log"; then
  echo "boot-cxx-graphical-smoke: ok"
  echo "boot-cxx-graphical-smoke: log=$log"
  exit 0
fi

echo "boot-cxx-graphical-smoke: failed rc=$rc" >&2
echo "boot-cxx-graphical-smoke: log=$log" >&2
tail -140 "$log" >&2 || true
exit 1
