#!/bin/sh
set -eu

STAGE_SCRIPT="${STAGE_SCRIPT:-/tmp/stage-0083-static-network-selftest-supervisor.sh}"
SELFTEST_SCRIPT="${SELFTEST_SCRIPT:-/tmp/rootfs-selftest-chroot.sh}"
IMAGE="/System/Generations/0034-rootfs-image-static-network-selftest-supervisor/rootfs.squashfs"

if [ "$(id -u)" != "0" ]; then
  echo "run as root" >&2
  exit 1
fi

if [ ! -f "$STAGE_SCRIPT" ]; then
  echo "missing stage script: $STAGE_SCRIPT" >&2
  exit 1
fi

if [ ! -f "$SELFTEST_SCRIPT" ]; then
  echo "missing self-test script: $SELFTEST_SCRIPT" >&2
  exit 1
fi

cleanup_stale_selftests() {
  for d in /tmp/mixtar-rootfs-selftest-*; do
    [ -d "$d" ] || continue
    for m in \
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
    esac
  done
}

echo "phase=cleanup"
cleanup_stale_selftests

echo "phase=build"
timeout 120 env MIXTAR_BUILD_ONLY=1 sh "$STAGE_SCRIPT"

if [ ! -f "$IMAGE" ]; then
  echo "missing generated image: $IMAGE" >&2
  exit 1
fi

echo "phase=syntax"
unsquashfs -cat "$IMAGE" /sbin/init >/tmp/init-0083-extracted.sh
sh -n /tmp/init-0083-extracted.sh

echo "phase=selftest"
timeout 60 sh "$SELFTEST_SCRIPT" "$IMAGE" /

echo "phase=done"
echo "EFI candidate was not created"
echo "BootNext was not set"
echo "reboot was not requested"
