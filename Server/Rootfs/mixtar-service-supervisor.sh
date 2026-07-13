#!/bin/sh
set -eu

MANIFEST=${MIXTAR_SERVICE_MANIFEST:-/System/Config/MixtarRVS/services.stage1}
RUNTIME=${MIXTAR_SERVICE_RUNTIME:-/System/Runtime/services}
LOGDIR=${MIXTAR_SERVICE_LOGS:-/System/Logs/services}

PATH=/System/SystemTools:/System/Tools/Current/bin:/sbin:/bin:/usr/sbin:/usr/bin
export PATH

usage() {
    cat <<'USAGE'
usage: mixtar-service-supervisor <check|list|status|start|stop|restart> [service|all]

Stage 1 service supervisor. It is manual-only and is not enabled as PID1 or an
OpenRC replacement yet.
USAGE
}

ensure_dirs() {
    mkdir -p "$RUNTIME" "$LOGDIR"
}

field() {
    n=$1
    line=$2
    printf '%s\n' "$line" | awk -F '|' -v n="$n" '{ print $n }'
}

manifest_lines() {
    if [ ! -f "$MANIFEST" ]; then
        echo "missing manifest: $MANIFEST" >&2
        return 1
    fi
    grep -v '^[	 ]*#' "$MANIFEST" | grep -v '^[	 ]*$'
}

service_line() {
    name=$1
    manifest_lines | while IFS= read -r line; do
        svc=$(field 1 "$line")
        if [ "$svc" = "$name" ]; then
            printf '%s\n' "$line"
            return 0
        fi
    done
}

pidfile_for() {
    name=$1
    line=$2
    pidfile=$(field 4 "$line")
    if [ -n "$pidfile" ]; then
        printf '%s\n' "$pidfile"
    else
        printf '%s/%s.pid\n' "$RUNTIME" "$name"
    fi
}

is_running_pidfile() {
    pidfile=$1
    [ -f "$pidfile" ] || return 1
    pid=$(cat "$pidfile" 2>/dev/null || true)
    [ -n "$pid" ] || return 1
    kill -0 "$pid" 2>/dev/null
}

status_one() {
    name=$1
    line=$(service_line "$name" || true)
    if [ -z "$line" ]; then
        echo "$name unknown"
        return 2
    fi
    pidfile=$(pidfile_for "$name" "$line")
    if is_running_pidfile "$pidfile"; then
        echo "$name running pid=$(cat "$pidfile")"
        return 0
    fi
    match=$(field 5 "$line")
    if [ -n "$match" ] && pidof "$match" >/dev/null 2>&1; then
        echo "$name running match=$match"
        return 0
    fi
    echo "$name stopped"
    return 3
}

check_one() {
    name=$1
    line=$(service_line "$name" || true)
    if [ -z "$line" ]; then
        echo "$name unknown"
        return 2
    fi
    cmd=$(field 2 "$line")
    if [ -x "$cmd" ]; then
        echo "$name command ok: $cmd"
        return 0
    fi
    echo "$name command missing: $cmd"
    return 1
}

start_one() {
    name=$1
    line=$(service_line "$name" || true)
    if [ -z "$line" ]; then
        echo "$name unknown" >&2
        return 2
    fi
    if status_one "$name" >/dev/null 2>&1; then
        echo "$name already running"
        return 0
    fi
    cmd=$(field 2 "$line")
    args=$(field 3 "$line")
    pidfile=$(pidfile_for "$name" "$line")
    workdir=$(dirname "$pidfile")
    mkdir -p "$workdir"
    if [ ! -x "$cmd" ]; then
        echo "$name command missing: $cmd" >&2
        return 1
    fi
    log="$LOGDIR/$name.log"
    echo "starting $name"
    # shellcheck disable=SC2086
    nohup "$cmd" $args >>"$log" 2>&1 &
    echo "$!" > "$pidfile"
}

stop_one() {
    name=$1
    line=$(service_line "$name" || true)
    if [ -z "$line" ]; then
        echo "$name unknown" >&2
        return 2
    fi
    pidfile=$(pidfile_for "$name" "$line")
    if is_running_pidfile "$pidfile"; then
        pid=$(cat "$pidfile")
        echo "stopping $name pid=$pid"
        kill "$pid" 2>/dev/null || true
        sleep 1
        kill -0 "$pid" 2>/dev/null && kill -TERM "$pid" 2>/dev/null || true
        rm -f "$pidfile"
        return 0
    fi
    echo "$name not running"
}

list_services() {
    manifest_lines | while IFS= read -r line; do
        field 1 "$line"
    done
}

for_each_service() {
    action=$1
    target=${2:-all}
    rc=0
    if [ "$target" = "all" ]; then
        tmp="${TMPDIR:-/tmp}/mixtar-service-list.$$"
        list_services > "$tmp"
        while IFS= read -r svc; do
            "$action" "$svc" || rc=$?
        done < "$tmp"
        rm -f "$tmp"
        return "$rc"
    fi
    "$action" "$target" || rc=$?
    return "$rc"
}

main() {
    cmd=${1:-}
    target=${2:-all}
    case "$cmd" in
        check)
            ensure_dirs
            for_each_service check_one "$target"
            ;;
        list)
            list_services
            ;;
        status)
            ensure_dirs
            for_each_service status_one "$target"
            ;;
        start)
            ensure_dirs
            for_each_service start_one "$target"
            ;;
        stop)
            ensure_dirs
            for_each_service stop_one "$target"
            ;;
        restart)
            ensure_dirs
            for_each_service stop_one "$target"
            for_each_service start_one "$target"
            ;;
        *)
            usage
            return 2
            ;;
    esac
}

main "$@"
