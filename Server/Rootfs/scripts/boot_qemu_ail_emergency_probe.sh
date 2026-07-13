#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"
log_dir="$repo_root/Server/Rootfs/Generated/boot"
log="$log_dir/boot-ail-emergency-probe.log"
timeout_seconds="${RVS_BOOT_AIL_EMERGENCY_TIMEOUT:-12}"

mkdir -p "$log_dir"

set +e
MIXTAR_QEMU_INIT="/System/Init/MixtarAil" \
MIXTAR_QEMU_INIT_PARAM="rdinit" \
MIXTAR_QEMU_APPEND_EXTRA="mixtar.target=emergency" \
  timeout "${timeout_seconds}s" bash "$script_dir/boot_qemu.sh" >"$log" 2>&1
rc=$?
set -e

if { [[ "$rc" -eq 0 ]] || [[ "$rc" -eq 124 ]]; } &&
   grep -q "Mixtar: implementation ailang" "$log" &&
   grep -q "Mixtar: target emergency" "$log" &&
   grep -q "toolkit-echo: ok" "$log" &&
   grep -q "Mixtar: entering emergency shell" "$log" &&
   grep -q "console: starting /System/Shells/msh" "$log"; then
  echo "boot-ail-emergency-probe: ok"
  echo "boot-ail-emergency-probe: log=$log"
  exit 0
fi

echo "boot-ail-emergency-probe: failed rc=$rc" >&2
echo "boot-ail-emergency-probe: log=$log" >&2
tail -100 "$log" >&2 || true
exit 1
