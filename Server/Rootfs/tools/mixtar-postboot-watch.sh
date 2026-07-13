#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
Usage:
  mixtar-postboot-watch.sh [--host=IP] [--user=USER] [--timeout=SECONDS]

Waits for SSH after the first Mixtar pre-v0 boot and verifies that the live
system is the Alpine/OpenRC/zsh Mixtar rootfs, not the previous host system.

This script is non-destructive. It only polls SSH and runs read-only checks.
EOF
}

die() {
  printf '%s\n' "error: $*" >&2
  exit 1
}

host="192.168.99.110"
user="vxz"
timeout_seconds=420

while [ "$#" -gt 0 ]; do
  case "$1" in
    --host=*) host="${1#*=}" ;;
    --user=*) user="${1#*=}" ;;
    --timeout=*) timeout_seconds="${1#*=}" ;;
    -h|--help|help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
  shift
done

case "$timeout_seconds" in
  ''|*[!0-9]*) die "timeout must be a positive integer" ;;
esac

ssh_base="ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new"
deadline=$(( $(date +%s) + timeout_seconds ))

printf '%s\n' "Waiting for SSH: $user@$host"

while :; do
  if $ssh_base "$user@$host" "true" >/dev/null 2>&1; then
    break
  fi

  now=$(date +%s)
  if [ "$now" -ge "$deadline" ]; then
    die "SSH did not return before timeout"
  fi

  sleep 5
done

printf '%s\n' "SSH is reachable. Collecting Mixtar post-boot evidence..."

$ssh_base "$user@$host" 'sh -s' <<'REMOTE_CHECKS'
set -eu

fail=0

ok() {
  printf 'ok: %s\n' "$1"
}

bad() {
  printf 'FAIL: %s\n' "$1"
  fail=1
}

need_path() {
  if [ -e "$1" ] || [ -L "$1" ]; then ok "$1"; else bad "$1"; fi
}

need_cmd() {
  if command -v "$1" >/dev/null 2>&1; then ok "command $1"; else bad "command $1"; fi
}

printf '%s\n' "## identity"
uname -a || true

if [ -r /etc/mixtar-release ]; then
  ok "/etc/mixtar-release"
  cat /etc/mixtar-release
else
  bad "/etc/mixtar-release"
fi

if [ -r /etc/alpine-release ]; then
  ok "/etc/alpine-release"
  cat /etc/alpine-release
else
  bad "/etc/alpine-release"
fi

printf '%s\n' "## layout"
need_path /System
need_path /System/Current
need_path /System/Runtime/generation.env
need_path /Applications
need_path /Programs
need_path /Users
need_path /Compatibility

printf '%s\n' "## services"
need_cmd rc-status
rc-status 2>/dev/null || true

printf '%s\n' "## remote access"
need_cmd sshd
need_path /Users/vxz/.ssh/authorized_keys
need_path /etc/iwd/main.conf
need_path /etc/init.d/sshd
need_path /etc/runlevels/default/sshd
need_path /etc/init.d/iwd
need_path /etc/runlevels/default/iwd
need_path /etc/init.d/dhcpcd
need_path /etc/runlevels/default/dhcpcd

printf '%s\n' "## Mixtar tools"
if [ -x /System/Tools/mixtar-firstboot-verify ]; then
  /System/Tools/mixtar-firstboot-verify || fail=1
else
  bad "/System/Tools/mixtar-firstboot-verify"
fi

if [ -x /System/Tools/mixtar-generation-report ]; then
  /System/Tools/mixtar-generation-report || true
else
  bad "/System/Tools/mixtar-generation-report"
fi

if [ -x /System/Tools/mixtar-postboot-report ]; then
  /System/Tools/mixtar-postboot-report || true
else
  bad "/System/Tools/mixtar-postboot-report"
fi

printf '%s\n' "## firstboot logs"
cat /System/Logs/firstboot-evidence.txt 2>/dev/null || true
cat /System/Logs/firstboot-report.service.log 2>/dev/null || true

if [ "$fail" -eq 0 ]; then
  printf '%s\n' "POSTBOOT_WATCH=ok"
  exit 0
fi

printf '%s\n' "POSTBOOT_WATCH=failed"
exit 1
REMOTE_CHECKS
