#!/bin/sh
set -eu

cmd="${1:-status}"

line() {
  printf '%s\n' "$*"
}

is_mounted() {
  path="$1"
  [ -r /proc/mounts ] && grep -q " $path " /proc/mounts
}

mount_type() {
  path="$1"
  if [ -r /proc/mounts ]; then
    awk -v p="$path" '$2 == p { print $3; found=1; exit } END { if (!found) exit 1 }' /proc/mounts 2>/dev/null || true
  fi
}

status_one() {
  path="$1"
  expected="$2"
  if is_mounted "$path"; then
    type=$(mount_type "$path")
    line "mounted $path type=${type:-unknown} expected=$expected"
  elif [ -d "$path" ]; then
    line "directory $path expected=$expected"
  elif [ -e "$path" ]; then
    line "wrong-node $path expected=$expected"
  else
    line "missing $path expected=$expected"
  fi
}

ensure_dir() {
  path="$1"
  if [ -e "$path" ] && [ ! -d "$path" ]; then
    line "refusing: $path exists and is not a directory" >&2
    exit 2
  fi
  mkdir -p "$path"
}

ensure_mount() {
  path="$1"
  fstype="$2"
  source="$3"
  options="$4"

  ensure_dir "$path"
  if is_mounted "$path"; then
    return
  fi

  if [ -n "$options" ]; then
    mount -t "$fstype" -o "$options" "$source" "$path"
  else
    mount -t "$fstype" "$source" "$path"
  fi
}

status_all() {
  line "MixtarRVS runtime mount status"
  status_one /dev devtmpfs
  status_one /proc proc
  status_one /sys sysfs
  status_one /run tmpfs
}

ensure_all() {
  ensure_mount /proc proc proc ""
  ensure_mount /sys sysfs sysfs ""
  ensure_mount /run tmpfs tmpfs "mode=0755,nosuid,nodev"
  ensure_mount /dev devtmpfs devtmpfs "mode=0755,nosuid"
  mkdir -p /run/openrc
  status_all
}

case "$cmd" in
  status)
    status_all
    ;;
  ensure)
    ensure_all
    ;;
  *)
    line "usage: mixtar-runtime-mounts [status|ensure]" >&2
    exit 2
    ;;
esac
