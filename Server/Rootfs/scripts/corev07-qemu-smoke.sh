#!/usr/bin/env bash
set -euo pipefail

VERSION="0.8"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"

efi_artifact="$repo_root/Server/Rootfs/Generated/corev07-root/System/EFI/MixtarRVS/$VERSION.efi"
log_file="$repo_root/Server/Rootfs/Generated/corev07-qemu-smoke.log"
timeout_seconds="${TIMEOUT_SECONDS:-45}"

fail() {
  echo "corev07-qemu-smoke: error: $*" >&2
  exit 1
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || fail "missing tool: $1"
}

prepare_artifact() {
  [[ -s "$efi_artifact" ]] || fail "missing CoreV07 EFI artifact: $efi_artifact"
}

run_qemu() {
  rm -f "$log_file"
  set +e
  timeout --foreground "$timeout_seconds" \
    qemu-system-x86_64 \
      -machine q35,accel=tcg \
      -cpu max \
      -smp 2 \
      -m 1024 \
      -net none \
      -display none \
      -serial stdio \
      -no-reboot \
      -kernel "$efi_artifact" \
    2>&1 | tee "$log_file"
  rc=${PIPESTATUS[0]}
  set -e

  if grep -F "MixtarRVS Init: headless core ready" "$log_file" >/dev/null 2>&1; then
    if grep -F "unable to open an initial console" "$log_file" >/dev/null 2>&1; then
      fail "MixtarRVS Init booted, but kernel initial console bootstrap is incomplete; log: $log_file"
    fi
    if grep -F "networking: service is not available" "$log_file" >/dev/null 2>&1; then
      fail "MixtarRVS Init booted, but networking service is falsely advertised; log: $log_file"
    fi
    if grep -F "session: ZSH returned" "$log_file" >/dev/null 2>&1; then
      fail "MixtarRVS Init booted, but ZSH session returned immediately; log: $log_file"
    fi
    if grep -F "can't find terminal definition" "$log_file" >/dev/null 2>&1; then
      fail "MixtarRVS Init booted, but ZSH terminfo is incomplete; log: $log_file"
    fi
    echo "corev07-qemu-smoke: headless core ready marker found"
    exit 0
  fi

  if [[ "$rc" -eq 124 ]]; then
    fail "QEMU timed out without MixtarRVS Init marker; log: $log_file"
  fi

  fail "QEMU exited rc=$rc without MixtarRVS Init marker; log: $log_file"
}

case "${1:-run}" in
  run)
    require_tool qemu-system-x86_64
    require_tool timeout
    prepare_artifact
    run_qemu
    ;;
  log)
    cat "$log_file"
    ;;
  *)
    echo "usage: corev07-qemu-smoke.sh [run|log]" >&2
    exit 2
    ;;
esac
