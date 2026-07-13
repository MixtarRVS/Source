#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"
log_dir="$repo_root/Server/Rootfs/Generated/boot"
log="$log_dir/boot-ail-smoke.log"
timeout_seconds="${RVS_BOOT_AIL_SMOKE_TIMEOUT:-45}"

mkdir -p "$log_dir"

set +e
MIXTAR_QEMU_INIT="/System/Init/MixtarAil" \
MIXTAR_QEMU_INIT_PARAM="rdinit" \
MIXTAR_QEMU_APPEND_EXTRA="mixtar.target=smoke" \
  timeout "${timeout_seconds}s" bash "$script_dir/boot_qemu.sh" >"$log" 2>&1
rc=$?
set -e

has_target_smoke_marker() {
  grep -q "Mixtar: target smoke" "$log" && return 0
  grep -q "Mixtar: target smok" "$log" && grep -q "^e$" "$log"
}

has_system_ready_marker() {
  grep -q "/System ready" "$log" && return 0
  grep -q "System ready" "$log"
}

if grep -q "Mixtar: pid1" "$log" &&
   grep -q "Mixtar: implementation ailang" "$log" &&
   has_target_smoke_marker &&
   grep -q "MixtarRVS v0" "$log" &&
   has_system_ready_marker &&
   grep -q "toolkit ready" "$log" &&
   grep -q "boot-smoke: ok" "$log" &&
   grep -q "smoke: powering off after boot proof" "$log" &&
   grep -Eq "msh ready|msh deferred" "$log"; then
  echo "boot-ail-smoke: ok"
  echo "boot-ail-smoke: log=$log"
  exit 0
fi

echo "boot-ail-smoke: failed rc=$rc" >&2
echo "boot-ail-smoke: log=$log" >&2
tail -80 "$log" >&2 || true
exit 1
