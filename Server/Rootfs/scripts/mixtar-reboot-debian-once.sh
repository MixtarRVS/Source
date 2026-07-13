#!/bin/sh
# Reboot this Mixtar boot once into Debian.
# Runs on Mixtar. Does not mount disks and does not modify Mixtar rootfs.
#
# Usage:
#   sudo sh mixtar-reboot-debian-once.sh
#   sudo sh mixtar-reboot-debian-once.sh 0003
#   sudo sh mixtar-reboot-debian-once.sh Debian

set -eu

TARGET="${1:-Debian}"

die() {
    printf '%s\n' "ERROR: $*" >&2
    exit 1
}

[ "$(id -u)" = "0" ] || die "run as root"
[ -d /sys/firmware/efi ] || die "system is not booted through UEFI"
command -v efibootmgr >/dev/null 2>&1 || die "efibootmgr is required"

TMP="/tmp/mixtar-efibootmgr.$$"
trap 'rm -f "$TMP"' EXIT INT TERM

efibootmgr > "$TMP" 2>&1 || {
    cat "$TMP" >&2
    die "efibootmgr failed"
}

case "$TARGET" in
    [0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f])
        BOOTNUM="$TARGET"
        ;;
    *)
        BOOTNUM="$(
            awk -v target="$TARGET" '
                BEGIN { target = tolower(target) }
                /^Boot[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]/ {
                    line = tolower($0)
                    if (index(line, target) > 0) {
                        n = substr($1, 5, 4)
                        gsub(/\*/, "", n)
                        print n
                        exit
                    }
                }
            ' "$TMP"
        )"
        ;;
esac

[ -n "$BOOTNUM" ] || {
    cat "$TMP" >&2
    die "could not find UEFI boot entry matching: $TARGET"
}

awk -v boot="Boot$BOOTNUM" '
    substr($1, 1, 8) == boot {
        print "Selected next boot: " $0
        found = 1
    }
    END { exit found ? 0 : 1 }
' "$TMP" || {
    cat "$TMP" >&2
    die "boot entry Boot$BOOTNUM does not exist"
}

efibootmgr -n "$BOOTNUM"
printf '%s\n' "BootNext set to Boot$BOOTNUM. Rebooting now."
sync
reboot
