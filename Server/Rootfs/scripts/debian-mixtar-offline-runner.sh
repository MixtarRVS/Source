#!/bin/sh
set -eu

ROOT_PART="${ROOT_PART:-/dev/nvme0n1p3}"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
COLLECT="${COLLECT:-$SCRIPT_DIR/collect-mixtar-offline-logs-from-debian.sh}"
REPAIR="${REPAIR:-$SCRIPT_DIR/repair-mixtar-ssh-from-debian.sh}"
MODE="${1:-collect}"

usage() {
  cat >&2 <<'USAGE'
usage: debian-mixtar-offline-runner.sh [collect|repair-ssh|collect-and-repair]

Environment:
  ROOT_PART=/dev/nvme0n1p3
  COLLECT=/path/to/collect-mixtar-offline-logs-from-debian.sh
  REPAIR=/path/to/repair-mixtar-ssh-from-debian.sh

Safety:
  collect             mounts Mixtar read-only and writes a Debian /tmp report
  repair-ssh          repairs Mixtar SSH config/permissions through chroot
  collect-and-repair  collects first, then repairs SSH

This runner does not reboot, does not set BootNext, and does not edit EFI.
USAGE
}

need_root() {
  if [ "$(id -u)" != "0" ]; then
    echo "run as root" >&2
    exit 1
  fi
}

need_file() {
  if [ ! -f "$1" ]; then
    echo "missing required script: $1" >&2
    exit 1
  fi
}

run_collect() {
  need_file "$COLLECT"
  echo "phase=collect root=$ROOT_PART"
  sh "$COLLECT" "$ROOT_PART"
}

run_repair() {
  need_file "$REPAIR"
  echo "phase=repair-ssh root=$ROOT_PART"
  sh "$REPAIR" "$ROOT_PART"
}

need_root

case "$MODE" in
  collect)
    run_collect
    ;;
  repair-ssh)
    run_repair
    ;;
  collect-and-repair)
    run_collect
    run_repair
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage
    exit 2
    ;;
esac

echo "phase=done"
echo "no reboot requested"
echo "no EFI changes requested"
