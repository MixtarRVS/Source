#!/bin/sh
# Debian-side MixtarRVS Base Closure Stage 1 creator.
#
# This creates an inactive generation only. It does not switch /System/Current,
# does not reboot, does not chroot, and does not touch EFI.
#
# Usage:
#   sudo sh debian-mixtar-stage-base-closure.sh dry-run [/dev/nvme0n1p3]
#   sudo sh debian-mixtar-stage-base-closure.sh apply   [/dev/nvme0n1p3]

set -eu

MODE="${1:-dry-run}"
DEV="${2:-/dev/nvme0n1p3}"
GEN_ID="${MIXTAR_BASE_CLOSURE_GEN:-0040-base-closure-stage1}"
MNT="${MIXTAR_STAGE_MOUNT:-/mnt/mixtar-stage-base-closure}"
GEN_REL="System/Generations/$GEN_ID"
GEN_ROOT_REL="$GEN_REL/Root"
MOUNTED_BY_THIS_SCRIPT=0

die() {
    printf '%s\n' "ERROR: $*" >&2
    exit 1
}

info() {
    printf '%s\n' "$*"
}

[ "$(id -u)" = "0" ] || die "run as root"

case "$MODE" in
    dry-run|apply) ;;
    *) die "mode must be dry-run or apply" ;;
esac

is_mounted_at() {
    awk -v m="$MNT" '$2 == m { found = 1 } END { exit found ? 0 : 1 }' /proc/mounts
}

mount_root() {
    mkdir -p "$MNT"
    if is_mounted_at; then
        [ "$MODE" = "apply" ] && mount -o remount,rw "$MNT"
        return 0
    fi

    if [ "$MODE" = "apply" ]; then
        mount -o rw "$DEV" "$MNT"
    else
        mount -o ro "$DEV" "$MNT"
    fi
    MOUNTED_BY_THIS_SCRIPT=1
}

cleanup() {
    if [ "$MOUNTED_BY_THIS_SCRIPT" = "1" ]; then
        umount "$MNT" >/dev/null 2>&1 || true
    fi
}

write_file() {
    rel="$1"
    mode="$2"
    path="$MNT/$rel"
    mkdir -p "${path%/*}"
    cat > "$path"
    chmod "$mode" "$path"
}

mkdir_stage() {
    rel="$1"
    mkdir -p "$MNT/$rel"
}

copy_if_exists() {
    src_rel="$1"
    dst_rel="$2"
    if [ -e "$MNT/$src_rel" ]; then
        mkdir -p "$MNT/${dst_rel%/*}"
        cp -a "$MNT/$src_rel" "$MNT/$dst_rel"
        return 0
    fi
    return 1
}

mount_root
trap cleanup EXIT INT TERM

[ -d "$MNT/System/Generations" ] || die "missing System/Generations in $DEV"

current_rel=""
if [ -L "$MNT/System/Current" ]; then
    current_rel="$(readlink "$MNT/System/Current")"
fi

free_kb="$(df -Pk "$MNT" | awk 'NR == 2 { print $4 }')"

info "mode=$MODE"
info "device=$DEV"
info "mount=$MNT"
info "generation=$GEN_ID"
info "current=$current_rel"
info "free_kb=$free_kb"
info ""

if [ -e "$MNT/$GEN_REL" ]; then
    die "generation already exists: $GEN_REL"
fi

if [ "$MODE" = "dry-run" ]; then
    info "would create inactive generation:"
    info "  /$GEN_REL"
    info ""
    info "would create clean Mixtar root skeleton:"
    info "  /Applications"
    info "  /Compatibility"
    info "  /Programs"
    info "  /System"
    info "  /Temporary"
    info "  /Users"
    info "  /Volumes"
    info ""
    info "would keep active fallback unchanged:"
    info "  /System/Current -> $current_rel"
    exit 0
fi

# This stage is small, but if Mixtar root is still almost full, stop before
# creating more state. Prune old rootfs-image generations first.
if [ "$free_kb" -lt 1048576 ]; then
    die "less than 1G free; prune inactive rootfs-image generations first"
fi

mkdir_stage "$GEN_ROOT_REL/Applications"
mkdir_stage "$GEN_ROOT_REL/Compatibility/POSIX/Alpine/3.24"
mkdir_stage "$GEN_ROOT_REL/Programs"
mkdir_stage "$GEN_ROOT_REL/System/Base/Closure"
mkdir_stage "$GEN_ROOT_REL/System/Config"
mkdir_stage "$GEN_ROOT_REL/System/Devices"
mkdir_stage "$GEN_ROOT_REL/System/Hardware"
mkdir_stage "$GEN_ROOT_REL/System/Kernel"
mkdir_stage "$GEN_ROOT_REL/System/Libraries"
mkdir_stage "$GEN_ROOT_REL/System/Logs"
mkdir_stage "$GEN_ROOT_REL/System/Process"
mkdir_stage "$GEN_ROOT_REL/System/Runtime"
mkdir_stage "$GEN_ROOT_REL/System/Shells"
mkdir_stage "$GEN_ROOT_REL/System/SystemTools"
mkdir_stage "$GEN_ROOT_REL/System/Tools"
mkdir_stage "$GEN_ROOT_REL/Temporary"
mkdir_stage "$GEN_ROOT_REL/Users"
mkdir_stage "$GEN_ROOT_REL/Volumes"

write_file "$GEN_REL/manifest.json" 0644 <<EOF
{
  "generation_id": "$GEN_ID",
  "kind": "base-closure-stage1",
  "active": false,
  "switches_boot": false,
  "source_of_truth": "/System",
  "fallback_generation": "$current_rel",
  "kernel": "linux",
  "libc": "musl",
  "init_status": "bootstrap-openrc-not-final",
  "package_backend_status": "apk-kept-only-as-bootstrap-compatibility",
  "mixtar_toolkit_status": "bsd-derived-toolkit-promoted-later",
  "native_root": [
    "/Applications",
    "/Compatibility",
    "/Programs",
    "/System",
    "/Temporary",
    "/Users",
    "/Volumes"
  ],
  "compatibility_root": "/Compatibility/POSIX/Alpine/3.24",
  "must_not_delete": [
    "/bin",
    "/sbin",
    "/etc",
    "/lib",
    "/usr",
    "/dev",
    "/proc",
    "/sys",
    "/run"
  ]
}
EOF

write_file "$GEN_REL/layout.map" 0644 <<'EOF'
# MixtarRVS Base Closure Stage 1 layout contract.
#
# Clean Mixtar-visible root:
/Applications
/Compatibility
/Programs
/System
/Temporary
/Users
/Volumes

# Mixtar source-of-truth directories:
/System/Tools
/System/SystemTools
/System/Config
/System/Libraries
/System/Runtime
/System/Devices
/System/Process
/System/Hardware
/System/Kernel
/System/Shells
/System/Logs

# Bootstrap compatibility closure:
/Compatibility/POSIX/Alpine/3.24

# Existing POSIX paths are fallback/compatibility only.
# They must not be moved in-place on the active fallback system.
EOF

write_file "$GEN_REL/base-closure-gaps.txt" 0644 <<'EOF'
Missing before MixtarRVS can stop using Alpine as identity:

1. /System/Tools must contain certified MixtarRVS BSD-derived tools directly,
   not symlink back to /bin.
2. /System/SystemTools must contain the minimal boot/runtime control tools
   directly, not symlink back to /sbin.
3. /System/Config must become the primary config tree, with POSIX /etc kept as
   compatibility.
4. /System/Libraries must contain the musl loader/libs needed by the closure,
   with POSIX /lib kept as compatibility.
5. Initramfs must create writable runtime state before switch_root.
6. /dev, /proc, /sys, /run, and /tmp must be mounted as runtime filesystems,
   never written into a read-only root image.
7. Network and SSH must be declared as Base Closure services with explicit
   dependencies: dev, proc, sys, run, dbus if needed, iwd, dhcpcd, sshd.
8. OpenRC can remain as bootstrap supervisor until a Mixtar supervisor exists,
   but it must be declared as compatibility/bootstrap, not system identity.
9. Clean Root must be activated only from a proven initramfs namespace, not by
   moving active /bin, /sbin, /etc, /lib, or /usr.
EOF

write_file "$GEN_ROOT_REL/System/Base/Closure/README.txt" 0644 <<'EOF'
This inactive generation is the first Base Closure staging root.

It is not bootable yet.
It does not switch /System/Current.
It records the desired source-of-truth layout and closure gaps.

The next stage must populate /System/Tools, /System/SystemTools,
/System/Libraries, and /System/Config from verified closure inputs.
EOF

copy_if_exists "etc/mixtar-release" "$GEN_REL/evidence/mixtar-release" || true
copy_if_exists "etc/alpine-release" "$GEN_REL/evidence/alpine-release" || true
copy_if_exists "System/Logs/firstboot-report.service.log" "$GEN_REL/evidence/firstboot-report.service.log" || true

sync

info "created inactive generation: /$GEN_REL"
info "current kept unchanged: /System/Current -> $current_rel"
info ""
df -h "$MNT"
