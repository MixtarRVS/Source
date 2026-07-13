#!/bin/sh
set -eu

PATH=/System/SystemTools:/System/Tools/Current/bin:/sbin:/bin:/usr/sbin:/usr/bin
export PATH

PID1_STAGE2=/System/SystemTools/mixtar-pid1-stage2
LOGDIR=/System/Logs

if [ "$(id -u)" != "0" ]; then
    echo "mixtar-stage2-live-run-once-check must run as root" >&2
    exit 1
fi

if [ ! -x "$PID1_STAGE2" ]; then
    echo "missing $PID1_STAGE2" >&2
    exit 1
fi

stamp=$(date +%Y%m%d-%H%M%S 2>/dev/null || echo unknown)
mkdir -p "$LOGDIR"
log="$LOGDIR/stage2-live-run-once-check-$stamp.log"

run_step() {
    name=$1
    shift
    echo
    echo "[$name]"
    echo "[$name]" >> "$log"
    "$@" 2>&1 | tee -a "$log"
}

{
    echo "MixtarRVS Stage 2 live run-once check"
    echo "timestamp=$stamp"
    echo "kernel=$(uname -r 2>/dev/null || true)"
    echo "pid=$$"
} | tee "$log"

run_step check "$PID1_STAGE2" check
run_step dry-run "$PID1_STAGE2" dry-run
run_step run-once "$PID1_STAGE2" run-once
run_step status-after /System/SystemTools/mixtar-init-stage1 status

echo
echo "stage2 live run-once check complete"
echo "log=$log"
