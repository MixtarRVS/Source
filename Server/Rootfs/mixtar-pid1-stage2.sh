#!/bin/sh
set -eu

PATH=/System/SystemTools:/System/Tools/Current/bin:/sbin:/bin:/usr/sbin:/usr/bin
export PATH

MOUNT_RUNTIME=${MIXTAR_MOUNT_RUNTIME:-/System/SystemTools/mixtar-mount-runtime}
DEVICE_RUNTIME=${MIXTAR_DEVICE_RUNTIME:-/System/SystemTools/mixtar-device-runtime}
SERVICE_SUPERVISOR=${MIXTAR_SERVICE_SUPERVISOR:-/System/SystemTools/mixtar-service-supervisor}
OPENRC_COMPAT_GUARD=${MIXTAR_OPENRC_COMPAT_GUARD:-/System/SystemTools/mixtar-openrc-compat-guard}
OPENRC_INIT=${MIXTAR_OPENRC_FALLBACK_INIT:-/sbin/init}
REBOOT_DEBIAN=${MIXTAR_REBOOT_DEBIAN:-/System/SystemTools/mixtar-reboot-debian-once}
LOGDIR=${MIXTAR_PID1_LOGS:-/System/Logs}
LOGFILE=$LOGDIR/pid1-stage2.log

usage() {
    cat <<'USAGE'
usage: mixtar-pid1-stage2 <check|dry-run|run-once|fallback-openrc>

Stage 2 PID1 candidate. It is not active by default. PID1 mode requires the
kernel command line flag:

  mixtar.stage2.allow=1

Without that flag, PID1 mode falls back to /sbin/init.
USAGE
}

log() {
    printf '%s\n' "$*"
    if [ -w /dev/kmsg ]; then
        printf '<6>mixtar-pid1-stage2: %s\n' "$*" >/dev/kmsg 2>/dev/null || true
    fi
    if mkdir -p "$LOGDIR" 2>/dev/null && [ -w "$LOGDIR" ]; then
        printf '%s\n' "$*" >> "$LOGFILE" 2>/dev/null || true
    fi
}

mount_if_needed() {
    target=$1
    fstype=$2
    source=$3
    shift 3
    if [ -r /proc/mounts ] && grep -q " $target " /proc/mounts 2>/dev/null; then
        return 0
    fi
    mount -t "$fstype" "$@" "$source" "$target" 2>/dev/null || true
}

prepare_pid1_runtime_early() {
    mkdir -p /proc /sys /dev /run 2>/dev/null || true
    mount -t proc proc /proc 2>/dev/null || true
    mount_if_needed /sys sysfs sysfs
    mount_if_needed /dev devtmpfs devtmpfs
    mount_if_needed /run tmpfs tmpfs -o mode=0755,nosuid,nodev
    mount -o remount,rw / 2>/dev/null || true
    mkdir -p /System/Logs /System/Runtime/run 2>/dev/null || true
    if [ -x "$OPENRC_COMPAT_GUARD" ]; then
        "$OPENRC_COMPAT_GUARD" >/dev/null 2>&1 || true
    fi
    log "early runtime prepared"
}

cmdline_has() {
    key=$1
    [ -r /proc/cmdline ] || return 1
    grep -qw "$key" /proc/cmdline
}

cmdline_value() {
    key=$1
    [ -r /proc/cmdline ] || return 1
    for arg in $(cat /proc/cmdline); do
        case "$arg" in
            "$key="*)
                printf '%s\n' "${arg#*=}"
                return 0
                ;;
        esac
    done
    return 1
}

is_uint() {
    case "$1" in
        ''|*[!0-9]*)
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

is_pid1() {
    [ "$$" = "1" ]
}

require_root() {
    if [ "$(id -u)" != "0" ]; then
        echo "mixtar-pid1-stage2 requires root for this operation" >&2
        return 1
    fi
}

check_component() {
    name=$1
    path=$2
    if [ -x "$path" ]; then
        echo "$name ok: $path"
        return 0
    fi
    echo "$name missing: $path"
    return 1
}

check_all() {
    rc=0
    check_component mount-runtime "$MOUNT_RUNTIME" || rc=1
    check_component device-runtime "$DEVICE_RUNTIME" || rc=1
    check_component service-supervisor "$SERVICE_SUPERVISOR" || rc=1
    if [ -x "$SERVICE_SUPERVISOR" ]; then
        "$SERVICE_SUPERVISOR" check all || rc=1
    fi
    if [ -x "$OPENRC_INIT" ]; then
        echo "openrc fallback ok: $OPENRC_INIT"
    else
        echo "openrc fallback missing: $OPENRC_INIT"
        rc=1
    fi
    return "$rc"
}

dry_run() {
    check_all
    echo
    echo "[planned PID1 sequence]"
    echo "1. mount runtime filesystems via $MOUNT_RUNTIME"
    echo "2. prepare device/runtime surface via $DEVICE_RUNTIME"
    echo "3. start services via $SERVICE_SUPERVISOR start all"
    echo "4. optionally start /sbin/getty or /bin/sh on /dev/tty1"
    echo "5. stay alive as PID1 test loop"
    echo
    echo "[service status surface]"
    "$SERVICE_SUPERVISOR" status all || true
}

start_console() {
    if [ -c /dev/tty1 ]; then
        if command -v getty >/dev/null 2>&1; then
            log "starting getty on tty1"
            getty 38400 tty1 &
            return 0
        fi
        log "starting fallback shell on tty1"
        setsid /bin/sh -c 'exec /bin/sh </dev/tty1 >/dev/tty1 2>&1' &
    else
        log "no /dev/tty1 for console"
    fi
}

run_once() {
    require_root
    prepare_pid1_runtime_early
    log "mixtar-pid1-stage2 run-once"
    "$MOUNT_RUNTIME" >>"$LOGFILE" 2>&1 || log "mount-runtime failed"
    "$DEVICE_RUNTIME" >>"$LOGFILE" 2>&1 || log "device-runtime failed"
    "$SERVICE_SUPERVISOR" check all >>"$LOGFILE" 2>&1 || log "service check failed"
    "$SERVICE_SUPERVISOR" start all >>"$LOGFILE" 2>&1 || log "service start failed"
    "$SERVICE_SUPERVISOR" status all >>"$LOGFILE" 2>&1 || true
    log "mixtar-pid1-stage2 run-once complete"
}

fallback_openrc() {
    log "falling back to $OPENRC_INIT"
    exec "$OPENRC_INIT"
}

start_debian_return_watchdog() {
    seconds=$(cmdline_value "mixtar.stage2.return_debian" 2>/dev/null || true)
    if ! is_uint "$seconds"; then
        log "no valid mixtar.stage2.return_debian watchdog configured"
        return 0
    fi
    if [ "$seconds" -lt 30 ]; then
        log "return watchdog value too small; using 30 seconds"
        seconds=30
    fi
    if [ ! -x "$REBOOT_DEBIAN" ]; then
        log "return watchdog unavailable: missing $REBOOT_DEBIAN"
        return 0
    fi
    log "starting Debian return watchdog: ${seconds}s"
    (
        sleep "$seconds"
        "$REBOOT_DEBIAN" 0003
    ) &
}

pid1_main() {
    prepare_pid1_runtime_early

    if ! cmdline_has "mixtar.stage2.allow=1"; then
        log "PID1 mode refused: missing mixtar.stage2.allow=1"
        fallback_openrc
    fi

    log "mixtar-pid1-stage2 PID1 start"
    start_debian_return_watchdog
    run_once || log "run-once failed; continuing to emergency surface"
    start_console || true

    log "mixtar-pid1-stage2 entering PID1 keepalive loop"
    while :; do
        wait || true
        sleep 1
    done
}

main() {
    if is_pid1; then
        pid1_main
        return 0
    fi

    cmd=${1:-}
    case "$cmd" in
        check)
            check_all
            ;;
        dry-run)
            dry_run
            ;;
        run-once)
            run_once
            ;;
        fallback-openrc)
            fallback_openrc
            ;;
        *)
            usage
            return 2
            ;;
    esac
}

main "$@"
