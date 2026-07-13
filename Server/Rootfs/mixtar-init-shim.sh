#!/bin/sh
set -eu

cmd="${1:-boot}"
log_dir="/System/Runtime/init"
log_file="$log_dir/init-shim.log"
marker_file="/System/Config/MixtarRVS/init-shim-pid1-latest.txt"

line() {
  printf '%s\n' "$*"
}

is_pid1() {
  [ "$$" -eq 1 ]
}

check_exec() {
  path="$1"
  if [ -x "$path" ]; then
    line "ok: executable $path"
    return 0
  fi
  line "fail: missing executable $path"
  return 1
}

check_file() {
  path="$1"
  if [ -r "$path" ]; then
    line "ok: readable $path"
    return 0
  fi
  line "fail: missing readable $path"
  return 1
}

contract() {
  line "MixtarRVS init shim contract"
  line "path: /System/SystemTools/init"
  line "status: candidate-not-active"
  line "pid1_behavior:"
  line "  1. refuse boot mode unless running as PID 1"
  line "  2. set MixtarRVS PATH"
  line "  3. ensure /dev /proc /sys /run through mixtar-runtime-mounts"
  line "  4. preserve /System/Libraries as first musl loader path"
  line "  5. exec /sbin/init as OpenRC bootstrap backend"
  line "non_pid1_modes:"
  line "  contract"
  line "  check"
  line "  boot-dry-run"
}

check() {
  fail=0
  line "MixtarRVS init shim check"
  check_exec /System/SystemTools/mixtar-runtime-mounts || fail=1
  check_exec /System/SystemTools/mixtar-service || fail=1
  check_exec /System/SystemTools/mixtar-network || fail=1
  check_exec /System/SystemTools/mixtar-remote || fail=1
  check_exec /System/Tools/MixtarRVS/bin/uname || fail=1
  check_exec /sbin/init || fail=1
  check_file /etc/ld-musl-x86_64.path || fail=1
  if [ -d /System/Libraries ]; then
    line "ok: directory /System/Libraries"
  else
    line "fail: missing directory /System/Libraries"
    fail=1
  fi
  if [ -r /etc/ld-musl-x86_64.path ]; then
    first=$(sed -n '1p' /etc/ld-musl-x86_64.path)
    if [ "$first" = "/System/Libraries" ]; then
      line "ok: musl loader path starts with /System/Libraries"
    else
      line "fail: musl loader path starts with $first"
      fail=1
    fi
  fi
  if [ "$fail" -eq 0 ]; then
    line "status: PASS"
  else
    line "status: FAIL"
  fi
  return "$fail"
}

boot_dry_run() {
  contract
  line ""
  check
}

boot() {
  if ! is_pid1; then
    line "refusing boot mode: not PID 1" >&2
    line "use: /System/SystemTools/init check" >&2
    exit 2
  fi

  PATH="/System/Tools/MixtarRVS/bin:/System/SystemTools:/bin:/sbin:/usr/bin:/usr/sbin"
  export PATH

  mount -o remount,rw / >/dev/null 2>&1 || true
  mkdir -p /System/Config/MixtarRVS >/dev/null 2>&1 || true
  {
    line "MixtarRVS init shim PID1 marker"
    line "stage=early"
    line "pid=$$"
    line "next=/sbin/init"
    line "kernel=$(uname -r 2>/dev/null || line unknown)"
  } > "$marker_file" 2>/dev/null || true
  {
    line "MixtarRVS init shim PID1 marker"
    line "stage=early"
    line "pid=$$"
    line "next=/sbin/init"
    line "kernel=$(uname -r 2>/dev/null || line unknown)"
  } > /dev/mixtar-init-shim.pid1 2>/dev/null || true

  mkdir -p "$log_dir" || true
  {
    line "MixtarRVS init shim starting"
    line "pid: $$"
    line "kernel: $(uname -r 2>/dev/null || line unknown)"
    line "runtime mounts: ensure"
  } >> "$log_file" 2>/dev/null || true

  /System/SystemTools/mixtar-runtime-mounts ensure >> "$log_file" 2>&1 || {
    line "mixtar-init: runtime mount ensure failed" >/dev/console 2>/dev/null || true
    exec /sbin/init
  }

  {
    line "MixtarRVS init shim PID1 marker"
    line "stage=after-runtime-mounts"
    line "pid=$$"
    if grep -q 'mixtar.supervisor=pre-openrc' /proc/cmdline 2>/dev/null; then
      line "next=/System/SystemTools/mixtar-supervisor pid1-openrc"
    else
      line "next=/sbin/init"
    fi
    line "kernel=$(uname -r 2>/dev/null || line unknown)"
  } > "$marker_file" 2>/dev/null || true
  {
    line "MixtarRVS init shim PID1 marker"
    line "stage=after-runtime-mounts"
    line "pid=$$"
    if grep -q 'mixtar.supervisor=pre-openrc' /proc/cmdline 2>/dev/null; then
      line "next=/System/SystemTools/mixtar-supervisor pid1-openrc"
    else
      line "next=/sbin/init"
    fi
    line "kernel=$(uname -r 2>/dev/null || line unknown)"
  } > /dev/mixtar-init-shim.pid1 2>/dev/null || true

  if grep -q 'mixtar.supervisor=pre-openrc' /proc/cmdline 2>/dev/null; then
    exec /System/SystemTools/mixtar-supervisor pid1-openrc
  fi

  exec /sbin/init
}

case "$cmd" in
  contract)
    contract
    ;;
  check)
    check
    ;;
  boot-dry-run)
    boot_dry_run
    ;;
  boot)
    boot
    ;;
  *)
    line "usage: init [contract|check|boot-dry-run|boot]" >&2
    exit 2
    ;;
esac
