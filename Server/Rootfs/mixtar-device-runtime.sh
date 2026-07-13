#!/bin/sh
set -eu

MODULES_FILE=${MIXTAR_STAGE2_MODULES:-/System/Config/MixtarRVS/modules.stage2}
LOGFILE=${MIXTAR_DEVICE_RUNTIME_LOG:-/System/Logs/device-runtime-stage2.log}

log() {
    printf '%s\n' "$*"
    if [ -w /dev/kmsg ]; then
        printf '<6>mixtar-device-runtime: %s\n' "$*" >/dev/kmsg 2>/dev/null || true
    fi
    mkdir -p /System/Logs 2>/dev/null || true
    printf '%s\n' "$*" >> "$LOGFILE" 2>/dev/null || true
}

mount_basic() {
    mkdir -p /proc /sys /dev /run 2>/dev/null || true
    mount -t proc proc /proc 2>/dev/null || true
    mount -t sysfs sysfs /sys 2>/dev/null || true
    mount -t devtmpfs devtmpfs /dev 2>/dev/null || true
    mount -t tmpfs -o mode=0755,nosuid,nodev tmpfs /run 2>/dev/null || true
}

load_modules() {
    if [ ! -r "$MODULES_FILE" ]; then
        log "modules file missing: $MODULES_FILE"
        return 0
    fi
    while IFS= read -r mod; do
        case "$mod" in
            ''|\#*)
                continue
                ;;
        esac
        if command -v modprobe >/dev/null 2>&1; then
            modprobe "$mod" 2>/dev/null && log "module loaded: $mod" || log "module load failed: $mod"
        else
            log "modprobe missing"
            return 0
        fi
    done < "$MODULES_FILE"
}

run_mdev() {
    if [ -w /proc/sys/kernel/hotplug ]; then
        printf '%s\n' /sbin/mdev >/proc/sys/kernel/hotplug 2>/dev/null || true
    fi
    if command -v mdev >/dev/null 2>&1; then
        mdev -s 2>/dev/null && log "mdev scan complete" || log "mdev scan failed"
    elif [ -x /bin/busybox ]; then
        /bin/busybox mdev -s 2>/dev/null && log "busybox mdev scan complete" || log "busybox mdev scan failed"
    else
        log "mdev missing"
    fi
}

bring_loopback_up() {
    if command -v ip >/dev/null 2>&1; then
        ip link set lo up 2>/dev/null && log "loopback up via ip" || log "loopback ip setup failed"
    elif command -v ifconfig >/dev/null 2>&1; then
        ifconfig lo up 2>/dev/null && log "loopback up via ifconfig" || log "loopback ifconfig setup failed"
    else
        log "no ip/ifconfig for loopback"
    fi
}

mount_basic
load_modules
run_mdev
bring_loopback_up
log "device runtime complete"
