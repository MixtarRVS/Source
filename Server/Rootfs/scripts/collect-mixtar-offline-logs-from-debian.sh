#!/bin/sh
set -eu

ROOT_PART="${1:-/dev/nvme0n1p3}"
MNT="${MNT:-/mnt/mixtar-offline}"
OUT="${OUT:-/tmp/mixtar-offline-report-$(date -u +%Y%m%dT%H%M%SZ).txt}"

if [ "$(id -u)" != "0" ]; then
  echo "run as root" >&2
  exit 1
fi

case "$ROOT_PART" in
  /dev/*) ;;
  *) echo "refusing non-device root path: $ROOT_PART" >&2; exit 1 ;;
esac

mkdir -p "$MNT"
if ! mountpoint -q "$MNT" 2>/dev/null; then
  mount -o ro "$ROOT_PART" "$MNT"
fi

if [ ! -d "$MNT/System" ]; then
  echo "mounted path does not look like MixtarRVS root: $MNT" >&2
  exit 1
fi

section() {
  printf '\n## %s\n' "$*" >> "$OUT"
}

run() {
  printf '\n$ %s\n' "$*" >> "$OUT"
  "$@" >> "$OUT" 2>&1 || true
}

copy_text() {
  label="$1"
  path="$2"
  section "$label: $path"
  if [ -e "$path" ]; then
    ls -ld "$path" >> "$OUT" 2>&1 || true
    if [ -f "$path" ]; then
      sed -n '1,220p' "$path" >> "$OUT" 2>&1 || true
    fi
  else
    echo "missing" >> "$OUT"
  fi
}

: > "$OUT"

section "Mixtar offline report"
echo "root_part=$ROOT_PART" >> "$OUT"
echo "mount=$MNT" >> "$OUT"
date -u '+utc=%Y-%m-%dT%H:%M:%SZ' >> "$OUT" 2>/dev/null || true

section "Debian host"
run uname -a
run cat /proc/cmdline
run findmnt /
run lsblk -o NAME,FSTYPE,UUID,MOUNTPOINTS,SIZE

section "Mixtar mount"
run findmnt "$MNT"
run df -h "$MNT"
run ls -la "$MNT"
run ls -la "$MNT/etc/ssh"
run ls -la "$MNT/run" "$MNT/run/sshd"
run ls -la "$MNT/Users/vxz" "$MNT/Users/vxz/.ssh"

section "Mixtar identity files"
copy_text os-release "$MNT/etc/os-release"
copy_text alpine-release "$MNT/etc/alpine-release"
copy_text mixtar-release "$MNT/etc/mixtar-release"
copy_text mixtar-stage "$MNT/etc/mixtar-stage"

section "SSH config and permissions"
copy_text sshd_config "$MNT/etc/ssh/sshd_config"
for p in "$MNT"/etc/ssh/ssh_host_*; do
  [ -e "$p" ] && run ls -l "$p"
done
copy_text authorized_keys "$MNT/Users/vxz/.ssh/authorized_keys"

section "OpenRC and service logs"
for p in \
  "$MNT"/var/log/messages \
  "$MNT"/var/log/rc.log \
  "$MNT"/var/log/boot.log \
  "$MNT"/var/log/daemon.log \
  "$MNT"/var/log/auth.log
do
  [ -e "$p" ] && copy_text "log" "$p"
done

section "Mixtar closure logs recent list"
run ls -lt "$MNT/System/Base/Closure"

section "Mixtar closure logs tails"
if [ -d "$MNT/System/Base/Closure" ]; then
  find "$MNT/System/Base/Closure" -maxdepth 1 -type f 2>/dev/null | sort | while read -r f; do
    section "tail $(basename "$f")"
    ls -l "$f" >> "$OUT" 2>&1 || true
    if command -v strings >/dev/null 2>&1; then
      strings "$f" 2>/dev/null | tail -n 120 >> "$OUT" 2>&1 || true
    else
      tail -n 120 "$f" >> "$OUT" 2>&1 || true
    fi
  done
fi

section "Generations"
run du -sh "$MNT/System/Generations"/*
find "$MNT/System/Generations" -maxdepth 2 -name manifest.txt -type f 2>/dev/null | sort | while read -r m; do
  section "manifest $m"
  sed -n '1,120p' "$m" >> "$OUT" 2>&1 || true
done

section "fstab and init configs"
copy_text fstab "$MNT/etc/fstab"
run ls -la "$MNT/etc/init.d"
for p in "$MNT"/etc/init.d/sshd "$MNT"/etc/init.d/dhcpcd "$MNT"/etc/init.d/iwd "$MNT"/etc/init.d/dbus; do
  [ -e "$p" ] && copy_text "init.d" "$p"
done
run find "$MNT/etc/runlevels" -maxdepth 3 -type l -o -type f

section "done"
echo "report=$OUT" >> "$OUT"
echo "report written to $OUT"
