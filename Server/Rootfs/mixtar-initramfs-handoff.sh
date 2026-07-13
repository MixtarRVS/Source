#!/bin/sh
set -eu

cmd="${1:-check}"
config_dir="/System/Config/MixtarRVS"
contract_file="$config_dir/initramfs-handoff.contract"

line() {
  printf '%s\n' "$*"
}

ok() {
  line "ok: $*"
}

fail_line() {
  line "fail: $*"
}

check_exec() {
  path="$1"
  if [ -x "$path" ]; then
    ok "executable $path"
    return 0
  fi
  fail_line "missing executable $path"
  return 1
}

check_dir() {
  path="$1"
  if [ -d "$path" ]; then
    ok "directory $path"
    return 0
  fi
  fail_line "missing directory $path"
  return 1
}

check_file() {
  path="$1"
  if [ -r "$path" ]; then
    ok "readable $path"
    return 0
  fi
  fail_line "missing readable $path"
  return 1
}

contract() {
  line "MixtarRVS initramfs handoff contract"
  line "status: candidate-not-active"
  line "source_of_truth: /System"
  line "runtime_target: /System/SystemTools/mixtar-initramfs-runtime handoff"
  line "handoff_target: /System/SystemTools/init boot"
  line "fallback_target: /sbin/init"
  line "required_before_switch_root:"
  line "  1. mount real root filesystem read-write or prepared overlay"
  line "  2. mount /dev /proc /sys /run"
  line "  3. expose /System, /System/Tools, /System/SystemTools, /System/Libraries"
  line "  4. preserve /etc/ld-musl-x86_64.path with /System/Libraries first"
  line "  5. exec /System/SystemTools/mixtar-initramfs-runtime handoff"
  line "  6. runtime handoff then execs /System/SystemTools/init boot"
  line "fallback_policy:"
  line "  if Mixtar init handoff fails before exec, fall back to /sbin/init"
  line "not_active_until:"
  line "  bootloader/initramfs explicitly selects this handoff"
}

write_contract() {
  mkdir -p "$config_dir"
  contract > "$contract_file"
  cat "$contract_file"
}

check() {
  fail=0
  line "MixtarRVS initramfs handoff check"
  check_dir /System || fail=1
  check_dir /System/Tools || fail=1
  check_dir /System/SystemTools || fail=1
  check_dir /System/Libraries || fail=1
  check_exec /System/SystemTools/init || fail=1
  check_exec /System/SystemTools/mixtar-initramfs-runtime || fail=1
  check_exec /System/SystemTools/mixtar-runtime-mounts || fail=1
  check_exec /System/Tools/MixtarRVS/bin/uname || fail=1
  check_exec /sbin/init || fail=1
  check_file /etc/ld-musl-x86_64.path || fail=1
  if [ -r /etc/ld-musl-x86_64.path ]; then
    first=$(sed -n '1p' /etc/ld-musl-x86_64.path)
    if [ "$first" = "/System/Libraries" ]; then
      ok "loader path starts with /System/Libraries"
    else
      fail_line "loader path starts with $first"
      fail=1
    fi
  fi
  if /System/SystemTools/init check >/dev/null 2>&1; then
    ok "init shim check"
  else
    fail_line "init shim check"
    fail=1
  fi
  if [ "$fail" -eq 0 ]; then
    line "status: PASS"
  else
    line "status: FAIL"
  fi
  return "$fail"
}

plan() {
  line "MixtarRVS initramfs handoff activation plan"
  line "1. keep Debian fallback Boot0003 untouched"
  line "2. keep normal Mixtar OpenRC boot entry untouched until chroot checks pass"
  line "3. create a separate experimental one-shot boot entry or kernel cmdline"
  line "4. make initramfs call /System/SystemTools/mixtar-initramfs-handoff check"
  line "5. make initramfs exec /System/SystemTools/mixtar-initramfs-runtime handoff only after check passes"
  line "6. runtime handoff execs /System/SystemTools/init boot"
  line "7. on failure, write /System/Config/MixtarRVS/initramfs-handoff-failed.log and exec /sbin/init"
  line "8. test only with one-shot bootnext, never permanent BootOrder"
}

case "$cmd" in
  contract)
    contract
    ;;
  write-contract)
    write_contract
    ;;
  check)
    check
    ;;
  plan)
    plan
    ;;
  *)
    line "usage: mixtar-initramfs-handoff [contract|write-contract|check|plan]" >&2
    exit 2
    ;;
esac
