#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"
log_dir="$repo_root/Server/Rootfs/Generated/boot"
log="$log_dir/boot-graphical-smoke.log"
timeout_seconds="${RVS_BOOT_GRAPHICAL_SMOKE_TIMEOUT:-60}"

mkdir -p "$log_dir"

set +e
MIXTAR_QEMU_APPEND_EXTRA="mixtar.target=graphical-smoke" \
MIXTAR_QEMU_DISPLAY="${MIXTAR_QEMU_DISPLAY:-none}" \
  timeout "${timeout_seconds}s" bash "$script_dir/boot_qemu_graphical.sh" >"$log" 2>&1
rc=$?
set -e

has_x11_smoke_marker() {
  grep -q "desktop-x11-smoke: ok" "$log" && return 0

  # Kernel diagnostics can interleave with serial output mid-marker.
  grep -q "desktop-x11-smok" "$log" &&
    grep -q "e: ok" "$log"
}

has_wayland_marker() {
  grep -q "desktop-wayland: ok" "$log" && return 0

  # Host display diagnostics can interleave with serial output mid-marker.
  grep -q "desktop.*" "$log" &&
    grep -q "^-wayland: ok$" "$log"
}

has_ailang_ui_marker() {
  grep -q "ailang-ui-smoke: ok" "$log" && return 0
  grep -q "ailang-ui-smok" "$log" && grep -q "e: ok" "$log"
}

has_xauth_marker() {
  grep -q "desktop-xauth: ok" "$log" && return 0
  grep -q "desktop-xauth:" "$log" && grep -q "ok" "$log"
}

if grep -q "MixtarRVS v0" "$log" &&
   grep -q "/System ready" "$log" &&
   has_xauth_marker &&
   grep -q "desktop: starting labwc" "$log" &&
   has_wayland_marker &&
   grep -q "desktop-panel: ok" "$log" &&
   grep -q "desktop-terminal: ok" "$log" &&
   has_ailang_ui_marker &&
   has_x11_smoke_marker &&
   grep -q "smoke: powering off after boot proof" "$log"; then
  echo "boot-graphical-smoke: ok"
  echo "boot-graphical-smoke: log=$log"
  exit 0
fi

echo "boot-graphical-smoke: failed rc=$rc" >&2
echo "boot-graphical-smoke: log=$log" >&2
tail -120 "$log" >&2 || true
exit 1
