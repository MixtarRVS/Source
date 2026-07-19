#!/usr/bin/env bash
set -euo pipefail

mode="${1:-strace}"
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
graphics="$repo/Output/P4/GraphicsRoot"
mwm="$repo/out/Product/MWMStack/Root"
logs="$repo/out/Product/MWMTest"
runtime="/tmp/mixtar-mwm-test-${UID}-$$"
gallium_driver="${MIXTAR_GALLIUM_DRIVER:-softpipe}"
graphics_mode="${MIXTAR_GRAPHICS_MODE:-auto}"

loader="$mwm/System/Libraries/Loader/ld-linux-x86-64.so.2"
mwm_binary="$mwm/System/Core/Graphics/MWM"
workbench_dir="$graphics/System/UX/Workbench"
workbench="$workbench_dir/Workbench"
libraries="$mwm/System/Libraries/Graphics:$graphics/System/Libraries/Graphics:$mwm/System/Libraries:$graphics/System/Libraries:$workbench_dir"

for required in "$loader" "$mwm_binary" "$workbench"; do
  [[ -f "$required" ]] || { printf 'Missing runtime file: %s\n' "$required" >&2; exit 1; }
done
command -v weston >/dev/null || { printf 'weston is required\n' >&2; exit 1; }

mkdir -p "$logs" "$runtime"
rm -f "$logs"/MWM.strace* "$logs"/Workbench.strace*
chmod 0700 "$runtime"

cleanup() {
  [[ -n "${mwm_pid:-}" ]] && kill "$mwm_pid" 2>/dev/null || true
  [[ -n "${weston_pid:-}" ]] && kill "$weston_pid" 2>/dev/null || true
  wait "${mwm_pid:-0}" 2>/dev/null || true
  wait "${weston_pid:-0}" 2>/dev/null || true
  case "$runtime" in /tmp/mixtar-mwm-test-*) rm -rf -- "$runtime" ;; esac
}
trap cleanup EXIT INT TERM

XDG_RUNTIME_DIR="$runtime" weston \
  --backend=headless-backend.so \
  --socket=mwm-parent \
  --idle-time=0 \
  --width=2048 \
  --height=1120 \
  >"$logs/Weston.log" 2>&1 &
weston_pid=$!

for _ in $(seq 1 100); do
  [[ -S "$runtime/mwm-parent" ]] && break
  kill -0 "$weston_pid" 2>/dev/null || { cat "$logs/Weston.log" >&2; exit 1; }
  sleep 0.05
done
[[ -S "$runtime/mwm-parent" ]] || { printf 'Parent Wayland socket was not created\n' >&2; exit 1; }

mwm_command=(
  env
  XDG_RUNTIME_DIR="$runtime"
  WAYLAND_DISPLAY=mwm-parent
  WLR_BACKENDS=wayland
  WLR_RENDERER=pixman
  WLR_ALLOCATOR=shm
  WLR_RENDERER_ALLOW_SOFTWARE=1
  XKB_CONFIG_ROOT="$mwm/System/Configuration/Keyboard/xkeyboard-config-2"
  XKB_DEFAULT_LAYOUT=us
  LD_LIBRARY_PATH="$libraries"
  LIBGL_ALWAYS_SOFTWARE=1
  GALLIUM_DRIVER="$gallium_driver"
  LIBGL_DRIVERS_PATH="$graphics/System/Libraries/Graphics/dri"
  "$loader" --library-path "$libraries" "$mwm_binary"
)

"${mwm_command[@]}" >"$logs/MWM.log" 2>&1 &
mwm_pid=$!

socket=''
for _ in $(seq 1 200); do
  for candidate in "$runtime"/wayland-*; do
    [[ -S "$candidate" ]] || continue
    socket="${candidate##*/}"
    break
  done
  [[ -n "$socket" ]] && break
  kill -0 "$mwm_pid" 2>/dev/null || { cat "$logs/MWM.log" >&2; exit 1; }
  sleep 0.05
done
[[ -n "$socket" ]] || { cat "$logs/MWM.log" >&2; printf 'MWM socket was not created\n' >&2; exit 1; }

client_command=(
  env
  XDG_RUNTIME_DIR="$runtime"
  WAYLAND_DISPLAY="$socket"
  MIXTAR_GRAPHICS_MODE="$graphics_mode"
  LD_LIBRARY_PATH="$libraries"
  FONTCONFIG_FILE=/etc/fonts/fonts.conf
  FONTCONFIG_PATH=/etc/fonts
  LIBGL_ALWAYS_SOFTWARE=1
  GALLIUM_DRIVER="$gallium_driver"
  LIBGL_DRIVERS_PATH="$graphics/System/Libraries/Graphics/dri"
  "$loader" --library-path "$libraries" "$workbench"
)

set +e
case "$mode" in
  strace)
    strace -f -qq -o "$logs/Workbench.strace" timeout --signal=TERM --kill-after=2s 8s "${client_command[@]}"
    status=$?
    ;;
  perf)
    perf stat -x, -o "$logs/Workbench.perf.txt" -- timeout --signal=TERM --kill-after=2s 8s "${client_command[@]}"
    status=$?
    ;;
  perf-record)
    perf record -q -g -o "$logs/Workbench.perf.data" -- timeout --signal=TERM --kill-after=2s 8s "${client_command[@]}"
    status=$?
    ;;
  plain)
    timeout --signal=TERM --kill-after=2s 8s "${client_command[@]}"
    status=$?
    ;;
  *) printf 'Usage: %s {strace|perf|perf-record|plain}\n' "$0" >&2; exit 2 ;;
esac
set -e

[[ "$status" -eq 124 ]] || { cat "$logs/MWM.log" >&2; exit "$status"; }
kill -0 "$mwm_pid"
printf 'MWM nested gate passed: socket=%s mode=%s status=%s\n' "$socket" "$mode" "$status"
