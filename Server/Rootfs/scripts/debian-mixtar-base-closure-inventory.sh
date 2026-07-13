#!/bin/sh
# Debian-side MixtarRVS Base Closure inventory.
#
# Read-only by design:
# - no reboot
# - no efibootmgr / BootNext
# - no chroot
# - no bind mounts
# - mounts the Mixtar root read-only
#
# Usage:
#   sudo sh debian-mixtar-base-closure-inventory.sh [/dev/nvme0n1p3]

set -eu

DEV="${1:-/dev/nvme0n1p3}"
MNT="${MIXTAR_INVENTORY_MOUNT:-/mnt/mixtar-base-closure-inventory}"
TS="$(date +%Y%m%d-%H%M%S 2>/dev/null || printf now)"
REPORT="/tmp/mixtar-base-closure-inventory-$TS.txt"
MOUNTED_BY_THIS_SCRIPT=0

die() {
    printf '%s\n' "ERROR: $*" >&2
    exit 1
}

out() {
    printf '%s\n' "$*" | tee -a "$REPORT" >/dev/null
}

section() {
    out ""
    out "## $*"
}

need_root() {
    [ "$(id -u)" = "0" ] || die "run as root"
}

is_mounted_at() {
    awk -v m="$MNT" '$2 == m { found = 1 } END { exit found ? 0 : 1 }' /proc/mounts
}

mount_ro() {
    mkdir -p "$MNT"
    if is_mounted_at; then
        return 0
    fi
    mount -o ro "$DEV" "$MNT"
    MOUNTED_BY_THIS_SCRIPT=1
}

cleanup() {
    if [ "$MOUNTED_BY_THIS_SCRIPT" = "1" ]; then
        umount "$MNT" >/dev/null 2>&1 || true
    fi
}

rel_status() {
    rel="$1"
    path="$MNT/$rel"
    if [ -L "$path" ]; then
        printf 'link:%s' "$(readlink "$path")"
    elif [ -d "$path" ]; then
        printf 'dir'
    elif [ -f "$path" ]; then
        printf 'file'
    elif [ -c "$path" ]; then
        printf 'char'
    elif [ -b "$path" ]; then
        printf 'block'
    elif [ -e "$path" ]; then
        printf 'other'
    else
        printf 'missing'
    fi
}

print_status() {
    rel="$1"
    out "$(printf '%-48s %s' "/$rel" "$(rel_status "$rel")")"
}

print_exists_list() {
    title="$1"
    shift
    section "$title"
    for rel in "$@"; do
        print_status "$rel"
    done
}

print_cmd_info() {
    rel="$1"
    path="$MNT/$rel"
    out ""
    out "### /$rel"
    if [ ! -e "$path" ] && [ ! -L "$path" ]; then
        out "missing"
        return
    fi
    ls -lah "$path" >> "$REPORT" 2>&1 || true
    if command -v file >/dev/null 2>&1 && [ -f "$path" ]; then
        file "$path" >> "$REPORT" 2>&1 || true
    fi
    if command -v readelf >/dev/null 2>&1 && [ -f "$path" ]; then
        readelf -l "$path" 2>/dev/null | grep -E 'Requesting program interpreter|INTERP' >> "$REPORT" 2>&1 || true
        readelf -d "$path" 2>/dev/null | grep 'NEEDED' >> "$REPORT" 2>&1 || true
    fi
}

count_execs() {
    rel="$1"
    path="$MNT/$rel"
    if [ -d "$path" ]; then
        find "$path" -maxdepth 1 -type f -perm /111 2>/dev/null | wc -l | awk '{ print $1 }'
    else
        printf '0'
    fi
}

count_links() {
    rel="$1"
    path="$MNT/$rel"
    if [ -d "$path" ]; then
        find "$path" -maxdepth 1 -type l 2>/dev/null | wc -l | awk '{ print $1 }'
    else
        printf '0'
    fi
}

need_root
trap cleanup EXIT INT TERM
mount_ro
: > "$REPORT"

out "MixtarRVS Base Closure inventory"
out "timestamp=$TS"
out "device=$DEV"
out "mount=$MNT"
out "mode=read-only"

section "Host and filesystem"
uname -a >> "$REPORT" 2>&1 || true
df -h "$MNT" >> "$REPORT" 2>&1 || true
lsblk -f "$DEV" >> "$REPORT" 2>&1 || true
mount | grep " $MNT " >> "$REPORT" 2>&1 || true

section "Generation pointers"
print_status "System/Current"
print_status "System/Previous"
if [ -L "$MNT/System/Current" ]; then
    out "System/Current target=$(readlink "$MNT/System/Current")"
fi
if [ -L "$MNT/System/Previous" ]; then
    out "System/Previous target=$(readlink "$MNT/System/Previous")"
fi

print_exists_list "Native Mixtar root contract" \
    "Applications" \
    "Compatibility" \
    "Programs" \
    "System" \
    "Temporary" \
    "Users" \
    "Volumes"

print_exists_list "Current /System ownership state" \
    "System/Tools" \
    "System/SystemTools" \
    "System/Config" \
    "System/Libraries" \
    "System/Runtime" \
    "System/Devices" \
    "System/Process" \
    "System/Hardware" \
    "System/Kernel" \
    "System/Shells" \
    "System/Logs"

print_exists_list "Visible POSIX compatibility paths" \
    "bin" \
    "sbin" \
    "etc" \
    "lib" \
    "usr" \
    "dev" \
    "proc" \
    "sys" \
    "run" \
    "tmp" \
    "var"

print_exists_list "Runtime mountpoint correctness offline view" \
    "dev/null" \
    "dev/tty" \
    "dev/tty0" \
    "dev/pts" \
    "proc/mounts" \
    "sys/kernel" \
    "run/openrc" \
    "tmp"

section "Bootstrap identity counters"
out "bin executable files=$(count_execs bin)"
out "bin symlinks=$(count_links bin)"
out "sbin executable files=$(count_execs sbin)"
out "sbin symlinks=$(count_links sbin)"
out "System/Tools executable files=$(count_execs System/Tools)"
out "System/SystemTools executable files=$(count_execs System/SystemTools)"
out "bin/MixtarRVS executable files=$(count_execs bin/MixtarRVS)"

section "Essential boot/runtime commands"
for rel in \
    "sbin/init" \
    "bin/sh" \
    "bin/busybox" \
    "lib/ld-musl-x86_64.so.1" \
    "sbin/openrc" \
    "sbin/rc" \
    "sbin/rc-service" \
    "bin/rc-status" \
    "sbin/mdev" \
    "sbin/modprobe" \
    "bin/mount" \
    "bin/umount" \
    "sbin/dhcpcd" \
    "usr/libexec/iwd" \
    "usr/sbin/sshd" \
    "usr/bin/dbus-daemon" \
    "System/SystemTools/mixtar-reboot-debian-once"; do
    print_cmd_info "$rel"
done

print_exists_list "Essential configuration" \
    "etc/inittab" \
    "etc/fstab" \
    "etc/hostname" \
    "etc/hosts" \
    "etc/resolv.conf" \
    "etc/network/interfaces" \
    "etc/dhcpcd.conf" \
    "etc/iwd/main.conf" \
    "etc/ssh/sshd_config" \
    "etc/runlevels/default/dbus" \
    "etc/runlevels/default/iwd" \
    "etc/runlevels/default/dhcpcd" \
    "etc/runlevels/default/sshd"

section "Kernel and modules"
find "$MNT/System/Kernel" -maxdepth 4 -type f -o -type l 2>/dev/null | sed "s#^$MNT/#/#" >> "$REPORT" 2>&1 || true
find "$MNT/lib/modules" -maxdepth 2 -type d 2>/dev/null | sed "s#^$MNT/#/#" >> "$REPORT" 2>&1 || true

section "Mixtar release evidence"
for rel in "etc/mixtar-release" "etc/alpine-release" "System/Runtime/generation.env"; do
    out ""
    out "### /$rel"
    if [ -f "$MNT/$rel" ]; then
        sed -n '1,120p' "$MNT/$rel" >> "$REPORT" 2>&1 || true
    else
        out "missing"
    fi
done

section "Base Closure gaps inferred by inventory"
if [ "$(rel_status System/Tools)" != "dir" ]; then
    out "gap: /System/Tools is not an independent directory"
fi
if [ "$(rel_status System/SystemTools)" != "dir" ]; then
    out "gap: /System/SystemTools is not an independent directory"
fi
if [ "$(rel_status System/Config)" != "dir" ]; then
    out "gap: /System/Config is not an independent directory"
fi
if [ "$(rel_status System/Libraries)" != "dir" ]; then
    out "gap: /System/Libraries is not an independent directory"
fi
if [ "$(rel_status dev/null)" != "char" ]; then
    out "gap: /dev/null is not a character device in the offline root; runtime must mount devtmpfs before services"
fi
if [ "$(rel_status proc/mounts)" = "missing" ]; then
    out "gap: /proc is not mounted in offline root; initramfs/init must mount procfs before OpenRC/services"
fi
if [ "$(rel_status sys/kernel)" = "missing" ]; then
    out "gap: /sys is not mounted in offline root; initramfs/init must mount sysfs before device/network services"
fi
if [ "$(rel_status run/openrc)" = "missing" ]; then
    out "gap: /run runtime state is not present offline; init must create tmpfs /run before OpenRC"
fi

out ""
out "report=$REPORT"
printf '%s\n' "$REPORT"
