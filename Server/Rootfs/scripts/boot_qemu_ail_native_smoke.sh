#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"
log_dir="$repo_root/Server/Rootfs/Generated/boot"
log="$log_dir/boot-ail-native-smoke.log"
initrd="$repo_root/Server/Rootfs/Generated/mixtar-ail-native-initramfs.cpio.gz"
timeout_seconds="${RVS_BOOT_AIL_NATIVE_TIMEOUT:-12}"

mkdir -p "$log_dir"

set +e
MIXTAR_QEMU_INIT="/System/Init/MixtarRVS" \
MIXTAR_QEMU_INIT_PARAM="rdinit" \
  timeout "${timeout_seconds}s" bash "$script_dir/boot_qemu.sh" "" "$initrd" >"$log" 2>&1
rc=$?
set -e

if { [[ "$rc" -eq 0 ]] || [[ "$rc" -eq 124 ]]; } &&
   grep -q "MixtarRVS Init: AILang PID1" "$log" &&
   grep -q "MixtarRVS Init: native root only" "$log" &&
   grep -q "MixtarRVS Init: case-sensitive paths" "$log" &&
   grep -q "MixtarRVS Init: POSIX only through /System/Compatibility" "$log" &&
   grep -q "vxz@MixtarRVS" "$log"; then
  echo "boot-ail-native-smoke: ok"
  echo "boot-ail-native-smoke: log=$log"
  exit 0
fi

echo "boot-ail-native-smoke: failed rc=$rc" >&2
echo "boot-ail-native-smoke: log=$log" >&2
tail -120 "$log" >&2 || true
exit 1
