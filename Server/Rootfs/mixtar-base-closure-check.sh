#!/bin/sh
set -eu

config_dir="/System/Config/MixtarRVS"
report="$config_dir/base-closure-check-latest.txt"
fail=0

line() {
  printf '%s\n' "$*"
}

ok() {
  line "ok: $*"
}

bad() {
  line "fail: $*"
  fail=1
}

pending() {
  line "pending: $*"
}

check_exec() {
  path="$1"
  if [ -x "$path" ]; then
    ok "executable $path"
  else
    bad "missing executable $path"
  fi
}

check_file() {
  path="$1"
  if [ -r "$path" ]; then
    ok "readable $path"
  else
    bad "missing readable $path"
  fi
}

check_dir() {
  path="$1"
  if [ -d "$path" ] && [ ! -L "$path" ]; then
    ok "directory $path"
  elif [ -L "$path" ]; then
    bad "$path is still a symlink -> $(readlink "$path")"
  else
    bad "missing directory $path"
  fi
}

check_command_path() {
  cmd="$1"
  resolved=$(PATH="/System/Tools/MixtarRVS/bin:/System/SystemTools:/bin:/sbin:/usr/bin:/usr/sbin" command -v "$cmd" 2>/dev/null || true)
  case "$resolved" in
    /System/Tools/MixtarRVS/bin/*)
      ok "$cmd resolves to $resolved"
      ;;
    "")
      bad "$cmd does not resolve"
      ;;
    *)
      bad "$cmd resolves outside Mixtar tools: $resolved"
      ;;
  esac
}

check_tool_result() {
  label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    ok "$label"
  else
    bad "$label"
  fi
}

run_check() {
  line "MixtarRVS base-closure stage check"
  line "kernel: $(uname -r)"
  line "machine: $(uname -m)"
  line ""

  line "== Userland =="
  check_exec /System/SystemTools/mixtar-userland-verify
  check_file "$config_dir/userland-source-tools.txt"
  check_file "$config_dir/userland-source-only.manifest"
  if [ -x /System/SystemTools/mixtar-userland-verify ]; then
    if /System/SystemTools/mixtar-userland-verify >/dev/null 2>&1; then
      ok "mixtar-userland-verify"
    else
      bad "mixtar-userland-verify"
    fi
  fi
  for cmd in uname ls cat cp mv rm grep sed awk ps find sort wc chmod ln mkdir rmdir; do
    check_command_path "$cmd"
  done
  line ""

  line "== Runtime libraries =="
  check_exec /System/SystemTools/mixtar-library-closure
  check_exec /System/SystemTools/mixtar-library-activate
  check_dir /System/Libraries
  check_file "$config_dir/runtime-library-required-paths.txt"
  check_file "$config_dir/runtime-library-closure.manifest"
  check_file /etc/ld-musl-x86_64.path
  if [ -r /etc/ld-musl-x86_64.path ]; then
    first=$(sed -n '1p' /etc/ld-musl-x86_64.path)
    if [ "$first" = "/System/Libraries" ]; then
      ok "musl loader path starts with /System/Libraries"
    else
      bad "musl loader path does not start with /System/Libraries"
    fi
  fi
  check_tool_result "mixtar ls runs without LD_LIBRARY_PATH" /System/Tools/MixtarRVS/bin/ls /System
  line ""

  line "== Runtime mounts =="
  check_exec /System/SystemTools/mixtar-runtime-mounts
  if [ -x /System/SystemTools/mixtar-runtime-mounts ]; then
    if /System/SystemTools/mixtar-runtime-mounts status >/dev/null 2>&1; then
      ok "mixtar-runtime-mounts status"
    else
      bad "mixtar-runtime-mounts status"
    fi
  fi
  line ""

  line "== Init candidate =="
  check_exec /System/SystemTools/init
  if [ -x /System/SystemTools/init ]; then
    check_tool_result "mixtar init contract" /System/SystemTools/init contract
    check_tool_result "mixtar init check" /System/SystemTools/init check
  fi
  line ""

  line "== Initramfs handoff candidate =="
  check_exec /System/SystemTools/mixtar-initramfs-handoff
  if [ -x /System/SystemTools/mixtar-initramfs-handoff ]; then
    check_tool_result "mixtar initramfs handoff contract" /System/SystemTools/mixtar-initramfs-handoff contract
    check_tool_result "mixtar initramfs handoff check" /System/SystemTools/mixtar-initramfs-handoff check
  fi
  line ""

  line "== Services =="
  check_exec /System/SystemTools/mixtar-service
  if [ -x /System/SystemTools/mixtar-service ]; then
    backend=$(/System/SystemTools/mixtar-service backend 2>/dev/null || true)
    if [ "$backend" = "openrc-bootstrap" ]; then
      ok "mixtar-service backend openrc-bootstrap"
    else
      bad "unexpected mixtar-service backend: ${backend:-missing}"
    fi
    check_tool_result "mixtar-service list" /System/SystemTools/mixtar-service list
  fi
  line ""

  line "== Supervisor candidate =="
  check_exec /System/SystemTools/mixtar-supervisor
  if [ -x /System/SystemTools/mixtar-supervisor ]; then
    check_tool_result "mixtar supervisor contract" /System/SystemTools/mixtar-supervisor contract
    check_tool_result "mixtar supervisor check" /System/SystemTools/mixtar-supervisor check
    check_tool_result "mixtar supervisor list" /System/SystemTools/mixtar-supervisor list
  fi
  line ""

  line "== Network and remote =="
  check_exec /System/SystemTools/mixtar-network
  check_exec /System/SystemTools/mixtar-remote
  if [ -x /System/SystemTools/mixtar-network ]; then
    backend=$(/System/SystemTools/mixtar-network backend 2>/dev/null || true)
    if [ "$backend" = "iwd-dhcpcd-bootstrap" ]; then
      ok "mixtar-network backend iwd-dhcpcd-bootstrap"
    else
      bad "unexpected mixtar-network backend: ${backend:-missing}"
    fi
    check_tool_result "mixtar-network status" /System/SystemTools/mixtar-network status
  fi
  if [ -x /System/SystemTools/mixtar-remote ]; then
    backend=$(/System/SystemTools/mixtar-remote backend 2>/dev/null || true)
    if [ "$backend" = "openssh-bootstrap" ]; then
      ok "mixtar-remote backend openssh-bootstrap"
    else
      bad "unexpected mixtar-remote backend: ${backend:-missing}"
    fi
    check_tool_result "mixtar-remote status" /System/SystemTools/mixtar-remote status
  fi
  line ""

  line "== Network closure =="
  check_exec /System/SystemTools/mixtar-network-closure
  if [ -x /System/SystemTools/mixtar-network-closure ]; then
    check_tool_result "mixtar network closure contract" /System/SystemTools/mixtar-network-closure contract
    check_tool_result "mixtar network closure check" /System/SystemTools/mixtar-network-closure check
    check_tool_result "mixtar network closure status" /System/SystemTools/mixtar-network-closure status
  fi
  line ""

  line "== Remote closure =="
  check_exec /System/SystemTools/mixtar-remote-closure
  if [ -x /System/SystemTools/mixtar-remote-closure ]; then
    check_tool_result "mixtar remote closure contract" /System/SystemTools/mixtar-remote-closure contract
    check_tool_result "mixtar remote closure check" /System/SystemTools/mixtar-remote-closure check
    check_tool_result "mixtar remote closure status" /System/SystemTools/mixtar-remote-closure status
  fi
  line ""

  line "== Pending native closure =="
  pending "/System/SystemTools/init boot activation as PID1 or pinned supervisor"
  pending "initramfs handoff activation using /System as source of truth"
  pending "mixtar-supervisor activation from init and eventual replacement of OpenRC backend"
  pending "native network bring-up replacing pinned iwd/dhcpcd backend"
  pending "native remote agent replacing pinned OpenSSH backend"
  line ""

  if [ "$fail" -eq 0 ]; then
    line "stage_gate: PASS"
  else
    line "stage_gate: FAIL"
  fi
  line "base_closure: NOT CLOSED"
  return "$fail"
}

output="$report"
if ! mkdir -p "$config_dir" 2>/dev/null; then
  output=""
elif [ ! -w "$config_dir" ]; then
  output=""
fi

if [ -n "$output" ]; then
  set +e
  run_check > "$output"
  rc=$?
  set -e
  cat "$output"
else
  line "note: $config_dir is not writable; writing report to stdout only"
  set +e
  run_check
  rc=$?
  set -e
fi
exit "$rc"
