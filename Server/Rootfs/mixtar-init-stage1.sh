#!/bin/sh
set -eu

PATH=/System/SystemTools:/System/Tools/Current/bin:/sbin:/bin:/usr/sbin:/usr/bin
export PATH

MOUNT_RUNTIME=${MIXTAR_MOUNT_RUNTIME:-/System/SystemTools/mixtar-mount-runtime}
SERVICE_SUPERVISOR=${MIXTAR_SERVICE_SUPERVISOR:-/System/SystemTools/mixtar-service-supervisor}
LOGDIR=${MIXTAR_INIT_LOGS:-/System/Logs}
LOGFILE=$LOGDIR/init-stage1.log

usage() {
    cat <<'USAGE'
usage: mixtar-init-stage1 <check|dry-run|status|start|stop|restart>

Manual Stage 1 init orchestrator. It is not installed as PID1 and must not be
made the default boot path until Mixtar owns the full runtime/service closure.
USAGE
}

log() {
    printf '%s\n' "$*"
    if mkdir -p "$LOGDIR" 2>/dev/null && [ -w "$LOGDIR" ]; then
        printf '%s\n' "$*" >> "$LOGFILE" 2>/dev/null || true
    fi
}

require_root() {
    if [ "$(id -u)" != "0" ]; then
        echo "mixtar-init-stage1 requires root for this operation" >&2
        return 1
    fi
}

refuse_pid1() {
    if [ "$$" = "1" ] && [ "${MIXTAR_INIT_STAGE1_ALLOW_PID1:-0}" != "1" ]; then
        echo "refusing PID1 mode: set MIXTAR_INIT_STAGE1_ALLOW_PID1=1 only for an explicit test boot" >&2
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
    check_component service-supervisor "$SERVICE_SUPERVISOR" || rc=1
    if [ -x "$SERVICE_SUPERVISOR" ]; then
        "$SERVICE_SUPERVISOR" check all || rc=1
    fi
    return "$rc"
}

dry_run() {
    check_all
    echo
    echo "[mount-runtime dry-run]"
    "$MOUNT_RUNTIME" --dry-run
    echo
    echo "[service list]"
    "$SERVICE_SUPERVISOR" list
}

status_all() {
    "$MOUNT_RUNTIME" --check || true
    "$SERVICE_SUPERVISOR" status all || true
}

start_all() {
    refuse_pid1
    require_root
    log "mixtar-init-stage1 start"
    "$MOUNT_RUNTIME"
    "$SERVICE_SUPERVISOR" check all
    "$SERVICE_SUPERVISOR" start all
    "$SERVICE_SUPERVISOR" status all || true
    log "mixtar-init-stage1 start complete"
}

stop_all() {
    refuse_pid1
    require_root
    log "mixtar-init-stage1 stop"
    "$SERVICE_SUPERVISOR" stop all
    log "mixtar-init-stage1 stop complete"
}

main() {
    cmd=${1:-}
    case "$cmd" in
        check)
            check_all
            ;;
        dry-run)
            dry_run
            ;;
        status)
            status_all
            ;;
        start)
            start_all
            ;;
        stop)
            stop_all
            ;;
        restart)
            stop_all
            start_all
            ;;
        *)
            usage
            return 2
            ;;
    esac
}

main "$@"
