#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"
log_dir="$repo_root/Server/Rootfs/Generated/boot"
log="$log_dir/boot-graphical-session-probe.log"
timeout_seconds="${RVS_BOOT_GRAPHICAL_SESSION_TIMEOUT:-15}"

mkdir -p "$log_dir"

set +e
MIXTAR_QEMU_DISPLAY="${MIXTAR_QEMU_DISPLAY:-none}" \
  timeout "${timeout_seconds}s" bash "$script_dir/boot_qemu_graphical.sh" >"$log" 2>&1
rc=$?
set -e

if grep -q "MixtarRVS v0" "$log" &&
   grep -q "desktop-xauth: ok" "$log" &&
   grep -q "desktop-wayland: ok" "$log" &&
   grep -q "desktop-panel: ok" "$log" &&
   grep -q "desktop-terminal: ok" "$log" &&
   grep -q "desktop-session: ready" "$log"; then
  echo "boot-graphical-session-probe: ok"
  echo "boot-graphical-session-probe: log=$log"
  exit 0
fi

echo "boot-graphical-session-probe: failed rc=$rc" >&2
echo "boot-graphical-session-probe: log=$log" >&2
tail -120 "$log" >&2 || true
exit 1
