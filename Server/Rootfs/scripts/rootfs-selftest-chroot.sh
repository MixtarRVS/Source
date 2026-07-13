#!/bin/sh
set -eu

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "usage: rootfs-selftest-chroot.sh <rootfs.squashfs> [base-root]" >&2
  exit 2
fi

IMAGE="$1"
BASE="${2:-/}"
WORK="/tmp/mixtar-rootfs-selftest-$$"
ROOT="$WORK/root"

if [ "${MIXTAR_SELFTEST_IN_NS:-0}" != "1" ] && command -v unshare >/dev/null 2>&1; then
  exec env MIXTAR_SELFTEST_IN_NS=1 unshare -m -- /bin/sh "$0" "$@"
fi

require() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required tool: $1" >&2
    exit 1
  fi
}

cleanup() {
  set +e
  for m in \
    "$ROOT/run" \
    "$ROOT/tmp" \
    "$ROOT/etc/resolv.conf" \
    "$ROOT/etc/shells" \
    "$ROOT/etc/sudoers" \
    "$ROOT/etc/gshadow" \
    "$ROOT/etc/shadow" \
    "$ROOT/etc/group" \
    "$ROOT/etc/passwd" \
    "$ROOT/etc/sudoers.d" \
    "$ROOT/etc/ssh" \
    "$ROOT/var/log" \
    "$ROOT/System/Logs" \
    "$ROOT/var/lib/dhcpcd" \
    "$ROOT/var/lib/iwd" \
    "$ROOT/Users" \
    "$ROOT/System/Runtime/initramfs/base" \
    "$ROOT/proc" \
    "$ROOT/sys" \
    "$ROOT/dev"
  do
    mountpoint -q "$m" 2>/dev/null && umount "$m"
  done
  case "$WORK" in
    /tmp/mixtar-rootfs-selftest-*) rm -rf "$WORK" ;;
  esac
}

safe_path() {
  case "$1" in
    /*) ;;
    *) echo "path must be absolute: $1" >&2; exit 1 ;;
  esac
}

require unsquashfs
require chroot
require mount
require umount

mount --make-rprivate / 2>/dev/null || true

if [ "$(id -u)" != "0" ]; then
  echo "run as root" >&2
  exit 1
fi

safe_path "$IMAGE"
safe_path "$BASE"

if [ ! -f "$IMAGE" ]; then
  echo "missing rootfs image: $IMAGE" >&2
  exit 1
fi

if [ ! -d "$BASE" ]; then
  echo "missing base root: $BASE" >&2
  exit 1
fi

trap cleanup EXIT INT TERM

mkdir -p "$ROOT"
unsquashfs -d "$ROOT" "$IMAGE" >/dev/null

mkdir -p \
  "$ROOT/dev" \
  "$ROOT/proc" \
  "$ROOT/sys" \
  "$ROOT/run" \
  "$ROOT/tmp" \
  "$ROOT/System/Runtime/initramfs/base" \
  "$ROOT/Users" \
  "$ROOT/var/lib/iwd" \
  "$ROOT/var/lib/dhcpcd" \
  "$ROOT/System/Logs" \
  "$ROOT/var/log" \
  "$ROOT/etc/ssh" \
  "$ROOT/etc/sudoers.d"

touch \
  "$ROOT/etc/passwd" \
  "$ROOT/etc/group" \
  "$ROOT/etc/shadow" \
  "$ROOT/etc/gshadow" \
  "$ROOT/etc/sudoers" \
  "$ROOT/etc/shells" \
  "$ROOT/etc/resolv.conf"

mount -o bind /dev "$ROOT/dev"
mount -t proc proc "$ROOT/proc"
mount -t sysfs sysfs "$ROOT/sys"
mount -t tmpfs tmpfs "$ROOT/run"
mount -t tmpfs tmpfs "$ROOT/tmp"
mount -o bind "$BASE" "$ROOT/System/Runtime/initramfs/base"
mkdir -p "$ROOT/run/sshd" "$ROOT/run/dbus" "$ROOT/var/run/dbus"

bind_dir() {
  src="$1"
  dst="$2"
  [ -d "$src" ] || return 0
  mount -o bind "$src" "$dst"
}

bind_file() {
  src="$1"
  dst="$2"
  [ -f "$src" ] || return 0
  mount -o bind "$src" "$dst"
}

bind_dir "$BASE/Users" "$ROOT/Users"
bind_dir "$BASE/var/lib/iwd" "$ROOT/var/lib/iwd"
bind_dir "$BASE/var/lib/dhcpcd" "$ROOT/var/lib/dhcpcd"
bind_dir "$BASE/System/Logs" "$ROOT/System/Logs"
bind_dir "$BASE/var/log" "$ROOT/var/log"
bind_dir "$BASE/etc/ssh" "$ROOT/etc/ssh"
bind_dir "$BASE/etc/sudoers.d" "$ROOT/etc/sudoers.d"
bind_file "$BASE/etc/passwd" "$ROOT/etc/passwd"
bind_file "$BASE/etc/group" "$ROOT/etc/group"
bind_file "$BASE/etc/shadow" "$ROOT/etc/shadow"
bind_file "$BASE/etc/gshadow" "$ROOT/etc/gshadow"
bind_file "$BASE/etc/sudoers" "$ROOT/etc/sudoers"
bind_file "$BASE/etc/shells" "$ROOT/etc/shells"
bind_file "$BASE/etc/resolv.conf" "$ROOT/etc/resolv.conf"

echo "rootfs=$IMAGE"
echo "base=$BASE"
env MIXTAR_SELFTEST_PREPARED=1 chroot "$ROOT" /sbin/init --self-test
