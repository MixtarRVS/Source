#!/bin/sh
set -eu

PATH=/System/SystemTools:/System/Tools/Current/bin:/sbin:/bin:/usr/sbin:/usr/bin
export PATH

INIT_STAGE1=/System/SystemTools/mixtar-init-stage1
LOGDIR=/System/Logs

if [ "$(id -u)" != "0" ]; then
    echo "mixtar-stage1-live-start-check must run as root" >&2
    exit 1
fi

if [ ! -x "$INIT_STAGE1" ]; then
    echo "missing $INIT_STAGE1" >&2
    exit 1
fi

stamp=$(date +%Y%m%d-%H%M%S 2>/dev/null || echo unknown)
mkdir -p "$LOGDIR"
log="$LOGDIR/stage1-live-start-check-$stamp.log"

run_step() {
    name=$1
    shift
    echo
    echo "[$name]"
    echo "[$name]" >> "$log"
    "$@" 2>&1 | tee -a "$log"
}

{
    echo "MixtarRVS Stage 1 live start check"
    echo "timestamp=$stamp"
    echo "kernel=$(uname -r 2>/dev/null || true)"
    echo "pid=$$"
} | tee "$log"

run_step check "$INIT_STAGE1" check
run_step status-before "$INIT_STAGE1" status
run_step start "$INIT_STAGE1" start
run_step status-after "$INIT_STAGE1" status

echo
echo "stage1 live start check complete"
echo "log=$log"
