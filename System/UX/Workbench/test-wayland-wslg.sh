#!/usr/bin/env bash
set -Eeuo pipefail

readonly repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly workbench="${1:-${repo_root}/out/System/UX/Workbench/linux-x64/Workbench}"
readonly trace="${2:-${repo_root}/out/System/UX/Workbench/linux-x64/workbench.strace}"
readonly diagnostic_mode="${3:-strace}"
readonly weston_log="${repo_root}/out/System/UX/Workbench/linux-x64/weston.log"
readonly socket_name="mixtar-weston-${BASHPID}"

weston_pid=""

cleanup() {
    if [[ -n "${weston_pid}" ]] && kill -0 "${weston_pid}" 2>/dev/null; then
        kill "${weston_pid}" 2>/dev/null || true
        wait "${weston_pid}" 2>/dev/null || true
    fi
}

trap cleanup EXIT INT TERM

if [[ ! -x "${workbench}" ]]; then
    printf 'Workbench binary not found: %s\n' "${workbench}" >&2
    exit 2
fi

if [[ -z "${XDG_RUNTIME_DIR:-}" ]]; then
    printf 'XDG_RUNTIME_DIR is not set.\n' >&2
    exit 2
fi

/usr/bin/weston \
    --backend=wayland-backend.so \
    --socket="${socket_name}" \
    --width=1920 \
    --height=1080 \
    --idle-time=0 \
    --log="${weston_log}" &
weston_pid=$!

for _ in {1..100}; do
    if [[ -S "${XDG_RUNTIME_DIR}/${socket_name}" ]]; then
        break
    fi

    if ! kill -0 "${weston_pid}" 2>/dev/null; then
        cat "${weston_log}" >&2
        exit 3
    fi

    sleep 0.05
done

if [[ ! -S "${XDG_RUNTIME_DIR}/${socket_name}" ]]; then
    printf 'Nested Weston socket did not become ready.\n' >&2
    cat "${weston_log}" >&2
    exit 3
fi

set +e
case "${diagnostic_mode}" in
    strace)
        WAYLAND_DISPLAY="${socket_name}" /usr/bin/strace \
            -f \
            -z \
            -e trace=%file,%network \
            -o "${trace}" \
            /usr/bin/timeout 8s "${workbench}"
        ;;
    perf)
        WAYLAND_DISPLAY="${socket_name}" /usr/bin/perf stat \
            -x, \
            -o "${trace}" \
            -e task-clock,cycles,instructions,cache-references,cache-misses,branches,branch-misses,context-switches,page-faults \
            /usr/bin/timeout 8s "${workbench}"
        ;;
    *)
        printf 'Unknown diagnostic mode: %s\n' "${diagnostic_mode}" >&2
        exit 2
        ;;
esac
workbench_status=$?
set -e

if [[ ${workbench_status} -ne 0 && ${workbench_status} -ne 124 ]]; then
    printf 'Workbench exited unexpectedly: %d\n' "${workbench_status}" >&2
    exit "${workbench_status}"
fi

printf 'Workbench Wayland test completed with status %d.\n' "${workbench_status}"
