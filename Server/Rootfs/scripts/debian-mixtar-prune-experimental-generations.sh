#!/bin/sh
# Debian-side MixtarRVS experimental generation pruner.
#
# Safe defaults:
# - dry-run unless first argument is "apply"
# - no reboot
# - no efibootmgr / BootNext
# - no chroot
# - preserves /System/Current target
# - removes only rootfs-image experimental generations
#
# Usage:
#   sudo sh debian-mixtar-prune-experimental-generations.sh dry-run [/dev/nvme0n1p3]
#   sudo sh debian-mixtar-prune-experimental-generations.sh apply   [/dev/nvme0n1p3]

set -eu

MODE="${1:-dry-run}"
DEV="${2:-/dev/nvme0n1p3}"
MNT="${MIXTAR_PRUNE_MOUNT:-/mnt/mixtar-prune-generations}"
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

safe_rel_target() {
    link="$1"
    if [ -L "$MNT/$link" ]; then
        readlink "$MNT/$link"
    else
        printf '%s\n' ""
    fi
}

is_delete_candidate() {
    name="$1"
    case "$name" in
        *rootfs-image*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

mount_root
trap cleanup EXIT INT TERM

[ -d "$MNT/System/Generations" ] || die "missing System/Generations in $DEV"

label="$(lsblk -no LABEL "$DEV" 2>/dev/null | sed -n '1p' || true)"
uuid="$(lsblk -no UUID "$DEV" 2>/dev/null | sed -n '1p' || true)"
current_rel="$(safe_rel_target "System/Current")"
previous_rel="$(safe_rel_target "System/Previous")"

info "mode=$MODE"
info "device=$DEV"
info "label=$label"
info "uuid=$uuid"
info "mount=$MNT"
info "current=$current_rel"
info "previous=$previous_rel"
info ""
info "space-before:"
df -h "$MNT"
info ""
info "candidates:"

found=0
for path in "$MNT"/System/Generations/*; do
    [ -d "$path" ] || continue
    name="${path##*/}"

    is_delete_candidate "$name" || continue
    if [ "$current_rel" = "Generations/$name" ] || [ "$previous_rel" = "Generations/$name" ]; then
        info "KEEP current/previous: $name"
        continue
    fi

    found=1
    du -sh "$path" 2>/dev/null || true

    if [ "$MODE" = "apply" ]; then
        case "$path" in
            "$MNT"/System/Generations/*rootfs-image*)
                rm -rf -- "$path"
                info "removed: $name"
                ;;
            *)
                die "refusing unexpected path: $path"
                ;;
        esac
    fi
done

[ "$found" = "1" ] || info "none"

if [ "$MODE" = "apply" ]; then
    sync
fi

info ""
info "space-after:"
df -h "$MNT"
