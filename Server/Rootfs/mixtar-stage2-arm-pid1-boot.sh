#!/bin/sh
set -eu

LABEL=${MIXTAR_STAGE2_LABEL:-MixtarRVS Stage2 PID1 Test}
DISK=${MIXTAR_STAGE2_DISK:-/dev/nvme0n1}
ESP_PART=${MIXTAR_STAGE2_ESP_PART:-1}
LOADER=${MIXTAR_STAGE2_LOADER:-\\EFI\\mixtarrvs-rt\\vmlinuz.efi}
ROOT_UUID=${MIXTAR_STAGE2_ROOT_UUID:-146d4ab3-3e58-4317-8799-da2f451b9a6c}
RETURN_SECONDS=${MIXTAR_STAGE2_RETURN_SECONDS:-180}

BASE_CMDLINE="initrd=\\EFI\\mixtarrvs-rt\\initrd.img root=UUID=$ROOT_UUID rootfstype=ext4 rootflags=ro modules=nvme,ext4,jbd2,mbcache rootwait ro quiet loglevel=3 threadirqs mixtar.profile=rt-7.1.2-mixtar-rt"
STAGE2_CMDLINE="$BASE_CMDLINE init=/System/SystemTools/mixtar-pid1-stage2 mixtar.stage2.allow=1 mixtar.stage2.return_debian=$RETURN_SECONDS"

usage() {
    cat <<'USAGE'
usage: mixtar-stage2-arm-pid1-boot <plan|create|arm|boot-once>

plan      print the intended EFI action only
create    create the Stage 2 EFI entry if it does not exist
arm       create if needed and set BootNext to the Stage 2 entry
boot-once create, set BootNext, and reboot

Run from Debian fallback. This script refuses to run from Mixtar.
USAGE
}

require_debian_fallback() {
    kernel=$(uname -r 2>/dev/null || true)
    case "$kernel" in
        7.0.0-rc3-mixtarrvs)
            return 0
            ;;
        *)
            echo "refusing: expected Debian fallback kernel, got $kernel" >&2
            return 1
            ;;
    esac
}

require_root() {
    if [ "$(id -u)" != "0" ]; then
        echo "this action requires root" >&2
        return 1
    fi
}

find_entry() {
    efibootmgr 2>/dev/null | awk -v label="$LABEL" '
        index($0, label) {
            id = substr($1, 5, 4)
            gsub(/[^0-9A-Fa-f]/, "", id)
            print id
            exit
        }
    '
}

print_plan() {
    echo "Stage 2 PID1 test EFI plan"
    echo "label=$LABEL"
    echo "disk=$DISK"
    echo "esp_part=$ESP_PART"
    printf 'loader=%s\n' "$LOADER"
    echo "root_uuid=$ROOT_UUID"
    echo "return_seconds=$RETURN_SECONDS"
    echo
    echo "cmdline:"
    printf '%s\n' "$STAGE2_CMDLINE"
    echo
    existing=$(find_entry || true)
    if [ -n "$existing" ]; then
        echo "existing_entry=Boot$existing"
    else
        echo "existing_entry=none"
    fi
}

create_entry() {
    require_root
    existing=$(find_entry || true)
    if [ -n "$existing" ]; then
        echo "Stage 2 entry already exists: Boot$existing"
        return 0
    fi
    previous_order=$(efibootmgr 2>/dev/null | awk -F': ' '/^BootOrder:/ { print $2; exit }')
    efibootmgr -c -d "$DISK" -p "$ESP_PART" -L "$LABEL" -l "$LOADER" -u "$STAGE2_CMDLINE"
    if [ -n "$previous_order" ]; then
        efibootmgr -o "$previous_order"
    fi
    created=$(find_entry || true)
    if [ -z "$created" ]; then
        echo "failed to create Stage 2 EFI entry" >&2
        return 1
    fi
    echo "created Boot$created"
}

arm_entry() {
    require_root
    create_entry
    entry=$(find_entry || true)
    if [ -z "$entry" ]; then
        echo "missing Stage 2 EFI entry after create" >&2
        return 1
    fi
    efibootmgr -n "$entry"
    echo "BootNext set to Boot$entry"
}

main() {
    action=${1:-plan}
    require_debian_fallback
    case "$action" in
        plan)
            print_plan
            ;;
        create)
            create_entry
            ;;
        arm)
            arm_entry
            ;;
        boot-once)
            arm_entry
            reboot
            ;;
        *)
            usage
            return 2
            ;;
    esac
}

main "$@"
