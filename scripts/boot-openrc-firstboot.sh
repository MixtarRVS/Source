#!/usr/bin/bash
set -euo pipefail

MODE=${1:-}
KERNEL=${2:-}
INITRAMFS=${3:-}
LOG=${4:-}
: "${MIXTAR_QEMU_MEMORY_MIB:?MIXTAR_QEMU_MEMORY_MIB is required}"
: "${MIXTAR_QEMU_TIMEOUT_SECONDS:?MIXTAR_QEMU_TIMEOUT_SECONDS is required}"
: "${MIXTAR_CONSOLE:?MIXTAR_CONSOLE is required}"
: "${MIXTAR_PID1:?MIXTAR_PID1 is required}"
: "${MIXTAR_TEST_COMMAND_LINE_KEY:?MIXTAR_TEST_COMMAND_LINE_KEY is required}"
: "${MIXTAR_TEST_POWEROFF_MODE:?MIXTAR_TEST_POWEROFF_MODE is required}"
: "${MIXTAR_TEST_REBOOT_MODE:?MIXTAR_TEST_REBOOT_MODE is required}"

case "$MIXTAR_QEMU_MEMORY_MIB:$MIXTAR_QEMU_TIMEOUT_SECONDS" in
  *[!0-9:]*|:*|*:)
    printf 'Invalid QEMU memory or timeout\n' >&2
    exit 2
    ;;
esac

if [ -z "$MODE" ] || [ -z "$KERNEL" ] || [ -z "$INITRAMFS" ] \
  || [ -z "$LOG" ]; then
  printf '%s\n' \
    'usage: boot-openrc-firstboot.sh <poweroff|reboot> <kernel> <initramfs> <log>' >&2
  exit 2
fi

case "$MODE" in
  "$MIXTAR_TEST_POWEROFF_MODE")
    PID1_ACTION='poweroff'
    ACTION_MARKER='MixtarRVS: requesting controlled poweroff'
    KERNEL_MARKER='reboot: Power down'
    SUCCESS_MARKER='FIRST_BOOT_OK'
    ;;
  "$MIXTAR_TEST_REBOOT_MODE")
    PID1_ACTION='reboot'
    ACTION_MARKER='MixtarRVS: requesting controlled reboot'
    KERNEL_MARKER='reboot: Restarting system'
    SUCCESS_MARKER='REBOOT_OK'
    ;;
  *)
    printf 'Unsupported first-boot mode: %s\n' "$MODE" >&2
    exit 2
    ;;
esac

mkdir -p "$(dirname -- "$LOG")"

set +e
timeout "${MIXTAR_QEMU_TIMEOUT_SECONDS}s" qemu-system-x86_64 \
  -machine q35,accel=tcg \
  -cpu max \
  -m "${MIXTAR_QEMU_MEMORY_MIB}M" \
  -nodefaults \
  -no-reboot \
  -display none \
  -serial stdio \
  -kernel "$KERNEL" \
  -initrd "$INITRAMFS" \
  -append "console=$MIXTAR_CONSOLE rdinit=$MIXTAR_PID1 loglevel=7 $MIXTAR_TEST_COMMAND_LINE_KEY=$MODE" \
  2>&1 | tee "$LOG"
status=${PIPESTATUS[0]}
set -e

if [ "$status" -ne 0 ]; then
  exit "$status"
fi

if grep -q 'MixtarRVS: platform namespace ready' "$LOG" \
  && grep -q 'MixtarRVS: zsh .* ready' "$LOG" \
  && grep -q "$ACTION_MARKER" "$LOG" \
  && grep -q "PID1: Received \"$PID1_ACTION\" from FIFO" "$LOG" \
  && grep -q "$KERNEL_MARKER" "$LOG"; then
  printf '%s\n' "$SUCCESS_MARKER"
  exit 0
fi

printf '%s\n' "${MODE^^}_INCOMPLETE"
exit 1
