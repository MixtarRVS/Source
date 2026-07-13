#!/bin/sh
# Prototype only. This is intended for initramfs integration, not for host use.

set -eu

PATH=/bin:/sbin:/usr/bin:/usr/sbin
export PATH

BASE_MOUNT="${MIXTAR_BASE_MOUNT:-/MixtarBase}"
IMAGE_MOUNT="${MIXTAR_IMAGE_MOUNT:-/MixtarImage}"
INIT_PATH="${MIXTAR_INIT_PATH:-/sbin/init}"
WATCHDOG_SECONDS="${MIXTAR_WATCHDOG_SECONDS:-180}"
DEFAULT_ROOTFS="/System/Current/rootfs.squashfs"

log_file=""

log_console() {
  printf '%s\n' "mixtar-initramfs-watchdog: $*" >/dev/console 2>/dev/null || true
}

log_persistent() {
  log_console "$*"
  if [ -n "$log_file" ]; then
    printf '%s\n' "mixtar-initramfs-watchdog: $*" >> "$log_file" 2>/dev/null || true
    sync 2>/dev/null || true
  fi
}

cmdline_value() {
  key="$1"
  for arg in $(cat /proc/cmdline 2>/dev/null || true); do
    case "$arg" in
      "$key="*) printf '%s\n' "${arg#*=}"; return 0 ;;
    esac
  done
  return 1
}

root_device() {
  root_arg="$(cmdline_value root || true)"
  case "$root_arg" in
    UUID=*)
      uuid="${root_arg#UUID=}"
      if [ -e "/dev/disk/by-uuid/$uuid" ]; then
        readlink -f "/dev/disk/by-uuid/$uuid"
        return 0
      fi
      ;;
    /dev/*)
      printf '%s\n' "$root_arg"
      return 0
      ;;
  esac
  return 1
}

mount_runtime() {
  mkdir -p /dev /proc /sys /run "$BASE_MOUNT" "$IMAGE_MOUNT"
  mountpoint -q /dev 2>/dev/null || mount -t devtmpfs devtmpfs /dev 2>/dev/null || true
  mountpoint -q /proc 2>/dev/null || mount -t proc proc /proc 2>/dev/null || true
  mountpoint -q /sys 2>/dev/null || mount -t sysfs sysfs /sys 2>/dev/null || true
  mountpoint -q /run 2>/dev/null || mount -t tmpfs tmpfs /run 2>/dev/null || true
}

mount_base_root() {
  dev="$(root_device)"
  rootfstype="$(cmdline_value rootfstype || printf ext4)"
  mkdir -p "$BASE_MOUNT"
  mountpoint -q "$BASE_MOUNT" 2>/dev/null && return 0
  mount -t "$rootfstype" -o rw "$dev" "$BASE_MOUNT"
}

setup_persistent_log() {
  mkdir -p "$BASE_MOUNT/System/Base/Closure"
  log_file="$BASE_MOUNT/System/Base/Closure/initramfs-watchdog-handoff.log"
  printf '%s\n' "mixtar-initramfs-watchdog: started" >> "$log_file" 2>/dev/null || true
}

selected_rootfs() {
  cmdline_value mixtar.rootfs || printf '%s\n' "$DEFAULT_ROOTFS"
}

health_marker() {
  rootfs="$1"
  name="$(basename "$(dirname "$rootfs")")"
  mkdir -p "$BASE_MOUNT/System/Runtime/boot-health"
  printf '%s\n' "$BASE_MOUNT/System/Runtime/boot-health/$name.ok"
}

start_watchdog() {
  marker="$1"
  (
    n=0
    while [ "$n" -lt "$WATCHDOG_SECONDS" ]; do
      if [ -s "$marker" ]; then
        log_persistent "health marker observed: $marker"
        exit 0
      fi
      n=$((n + 1))
      sleep 1
    done
    log_persistent "timeout waiting for health marker: $marker"
    log_persistent "rebooting to firmware default/fallback"
    sync
    reboot -f
  ) &
  log_persistent "watchdog started seconds=$WATCHDOG_SECONDS marker=$marker"
}

mount_candidate_image() {
  rootfs="$1"
  image_path="$BASE_MOUNT$rootfs"
  if [ ! -f "$image_path" ]; then
    log_persistent "candidate rootfs missing: $image_path"
    return 1
  fi
  mkdir -p "$IMAGE_MOUNT"
  mount -o loop,ro "$image_path" "$IMAGE_MOUNT"
  mkdir -p "$IMAGE_MOUNT/System/Runtime/initramfs/base"
  mount --move "$BASE_MOUNT" "$IMAGE_MOUNT/System/Runtime/initramfs/base"
}

handoff() {
  rootfs="$(selected_rootfs)"
  marker="$(health_marker "$rootfs")"
  rm -f "$marker"
  log_persistent "candidate rootfs=$rootfs"
  log_persistent "health marker=$marker"
  start_watchdog "$marker"
  mount_candidate_image "$rootfs"
  log_persistent "switch_root target=$IMAGE_MOUNT init=$INIT_PATH"
  exec switch_root "$IMAGE_MOUNT" "$INIT_PATH"
}

main() {
  mount_runtime
  mount_base_root
  setup_persistent_log
  handoff
}

main "$@"
