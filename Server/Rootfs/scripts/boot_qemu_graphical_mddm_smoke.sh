#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"
log_dir="$repo_root/Server/Rootfs/Generated/boot"
log="$log_dir/boot-graphical-mddm-smoke.log"
timeout_seconds="${RVS_BOOT_GRAPHICAL_MDDM_SMOKE_TIMEOUT:-120}"

mkdir -p "$log_dir"

MIXTAR_DESKTOP_PROFILE=rich bash "$script_dir/build_graphical_initramfs.sh" >/dev/null

set +e
MIXTAR_QEMU_APPEND_EXTRA="mixtar.target=graphical-smoke mixtar.dbus=1 mixtar.mddm=1" \
MIXTAR_QEMU_DISPLAY="${MIXTAR_QEMU_DISPLAY:-none}" \
  timeout "${timeout_seconds}s" bash "$script_dir/boot_qemu_graphical.sh" >"$log" 2>&1
rc=$?
set -e

if grep -q "MixtarRVS v0" "$log" &&
   grep -q "desktop-wayland: ok" "$log" &&
   grep -q "desktop-dbus: ok" "$log" &&
   grep -q "desktop-terminal: ok" "$log" &&
   grep -q "desktop-x11-smoke: ok" "$log" &&
   grep -q "mddm-greeter: ok" "$log" &&
   grep -q "mddm-auth-backend: test" "$log" &&
   grep -q "mddm-auth: ok" "$log" &&
   grep -q "mddm-session: started" "$log" &&
   grep -q "mddm-session: stopped" "$log" &&
   grep -q "mddm-smoke: ok" "$log" &&
   grep -q "boot-smoke: ok" "$log"; then
  echo "boot-graphical-mddm-smoke: ok"
  echo "boot-graphical-mddm-smoke: log=$log"
  exit 0
fi

echo "boot-graphical-mddm-smoke: failed rc=$rc" >&2
echo "boot-graphical-mddm-smoke: log=$log" >&2
tail -180 "$log" >&2 || true
exit 1
