#!/bin/sh
set -eu

RESTART_NETWORK=0
if [ "${1:-}" = "--restart-network" ]; then
  RESTART_NETWORK=1
elif [ "${1:-}" != "" ]; then
  echo "usage: recover-selftest-host.sh [--restart-network]" >&2
  exit 2
fi

if [ "$(id -u)" != "0" ]; then
  echo "run as root" >&2
  exit 1
fi

section() {
  printf '\n## %s\n' "$*"
}

show_cmdline() {
  section "cmdline"
  cat /proc/cmdline 2>/dev/null || true
  printf '\n'
}

show_selftest_mounts() {
  section "selftest mounts"
  mount | grep '/tmp/mixtar-rootfs-selftest-' || true
}

cleanup_selftest_mounts() {
  section "cleanup selftest mounts"
  for d in /tmp/mixtar-rootfs-selftest-*; do
    [ -d "$d" ] || continue
    echo "cleaning $d"
    for m in \
      "$d/root/run" \
      "$d/root/tmp" \
      "$d/root/etc/resolv.conf" \
      "$d/root/etc/shells" \
      "$d/root/etc/sudoers" \
      "$d/root/etc/gshadow" \
      "$d/root/etc/shadow" \
      "$d/root/etc/group" \
      "$d/root/etc/passwd" \
      "$d/root/etc/sudoers.d" \
      "$d/root/etc/ssh" \
      "$d/root/var/log" \
      "$d/root/System/Logs" \
      "$d/root/var/lib/dhcpcd" \
      "$d/root/var/lib/iwd" \
      "$d/root/Users" \
      "$d/root/System/Runtime/initramfs/base" \
      "$d/root/proc" \
      "$d/root/sys" \
      "$d/root/dev"
    do
      mountpoint -q "$m" 2>/dev/null && umount "$m"
    done
    case "$d" in
      /tmp/mixtar-rootfs-selftest-*) rm -rf "$d" ;;
      *) echo "refusing unsafe cleanup path: $d" >&2; exit 1 ;;
    esac
  done
}

show_network() {
  section "network"
  ip link show 2>/dev/null || true
  ip -4 addr 2>/dev/null || true
  ip route 2>/dev/null || true
}

show_services() {
  section "services"
  rc-status 2>/dev/null || true
  ps 2>/dev/null | grep -E 'sshd|dhcpcd|iwd|dbus' | grep -v grep || true
  netstat -ltn 2>/dev/null || true
}

restart_network() {
  section "restart network services"
  if command -v rc-service >/dev/null 2>&1; then
    rc-service dbus restart 2>/dev/null || rc-service dbus start 2>/dev/null || true
    rc-service iwd restart 2>/dev/null || rc-service iwd start 2>/dev/null || true
    rc-service dhcpcd restart 2>/dev/null || rc-service dhcpcd start 2>/dev/null || true
    rc-service sshd restart 2>/dev/null || rc-service sshd start 2>/dev/null || true
  else
    echo "rc-service not available"
  fi
}

show_cmdline
show_selftest_mounts
cleanup_selftest_mounts
show_selftest_mounts
show_network
show_services

if [ "$RESTART_NETWORK" = "1" ]; then
  restart_network
  show_network
  show_services
fi

section "done"
echo "recovery complete"
