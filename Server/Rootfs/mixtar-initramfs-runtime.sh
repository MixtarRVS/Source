#!/bin/sh
set -u

if [ "$$" -eq 1 ]; then
  cmd="handoff"
else
  cmd="${1:-check}"
fi
config_dir="/System/Config/MixtarRVS"
contract_file="$config_dir/initramfs-runtime.contract"
report_file="$config_dir/initramfs-runtime-latest.report"
marker_file="$config_dir/initramfs-runtime-pid1-latest.txt"

line() {
  printf '%s\n' "$*"
}

ok() {
  line "ok: $*"
}

fail_line() {
  line "fail: $*"
}

is_pid1() {
  [ "$$" -eq 1 ]
}

is_mounted() {
  target="$1"
  [ -r /proc/mounts ] || return 1
  awk -v target="$target" '$2 == target { found=1 } END { exit found ? 0 : 1 }' /proc/mounts
}

mount_fs() {
  type="$1"
  source="$2"
  target="$3"
  opts="${4:-}"
  mount_cmd="/bin/mount"
  if [ ! -x "$mount_cmd" ]; then
    mount_cmd="mount"
  fi

  mkdir -p "$target" || return 1
  if is_mounted "$target"; then
    ok "$target already mounted"
    return 0
  fi

  if [ -n "$opts" ]; then
    "$mount_cmd" -t "$type" -o "$opts" "$source" "$target" || {
      is_mounted "$target" && return 0
      return 1
    }
  else
    "$mount_cmd" -t "$type" "$source" "$target" || {
      is_mounted "$target" && return 0
      return 1
    }
  fi
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

check_mount() {
  path="$1"
  if is_mounted "$path"; then
    ok "mounted $path"
    return 0
  fi
  fail_line "not mounted $path"
  return 1
}

check_root_rw() {
  if [ ! -r /proc/mounts ]; then
    fail_line "cannot inspect /proc/mounts for root mode"
    return 1
  fi
  opts="$(awk '$2 == "/" { print $4; exit }' /proc/mounts)"
  case ",$opts," in
    *,rw,*)
      ok "root mount is rw"
      return 0
      ;;
    *)
      fail_line "root mount is not rw: $opts"
      return 1
      ;;
  esac
}

write_pid1_marker() {
  stage="$1"
  next="$2"
  mkdir -p "$config_dir" >/dev/null 2>&1 || true
  {
    line "MixtarRVS initramfs runtime PID1 marker"
    line "stage=$stage"
    line "pid=$$"
    line "next=$next"
    line "kernel=$(uname -r 2>/dev/null || line unknown)"
  } > "$marker_file" 2>/dev/null || true
  {
    line "MixtarRVS initramfs runtime PID1 marker"
    line "stage=$stage"
    line "pid=$$"
    line "next=$next"
    line "kernel=$(uname -r 2>/dev/null || line unknown)"
  } > /dev/mixtar-initramfs-runtime.pid1 2>/dev/null || true
}

contract() {
  line "MixtarRVS initramfs runtime contract"
  line "path: /System/SystemTools/mixtar-initramfs-runtime"
  line "status: candidate-not-default"
  line "purpose:"
  line "  own the early runtime mount contract before service supervision"
  line "required_runtime_mounts:"
  line "  /"
  line "  /dev"
  line "  /proc"
  line "  /sys"
  line "  /run"
  line "required_root_mode:"
  line "  read-write unless an explicit immutable root profile is selected"
  line "handoff_target:"
  line "  /System/SystemTools/init boot"
  line "fallback_target:"
  line "  /sbin/init"
  line "allowed_backends:"
  line "  Linux kernel mount API"
  line "  compatibility mount tool until Mixtar owns mount(8)"
  line "  OpenRC only after handoff, not as initramfs identity"
  line "non_pid1_modes:"
  line "  contract"
  line "  write-contract"
  line "  check"
  line "  ensure"
  line "  handoff-dry-run"
}

write_contract() {
  mkdir -p "$config_dir"
  contract > "$contract_file"
  cat "$contract_file"
}

check() {
  fail=0
  line "MixtarRVS initramfs runtime check"
  check_dir /System || fail=1
  check_dir /System/SystemTools || fail=1
  check_dir /System/Tools || fail=1
  check_dir /System/Libraries || fail=1
  check_exec /System/SystemTools/init || fail=1
  check_exec /System/SystemTools/mixtar-initramfs-runtime || fail=1
  check_exec /System/SystemTools/mixtar-runtime-mounts || fail=1
  check_exec /System/Tools/MixtarRVS/bin/uname || fail=1
  check_exec /sbin/init || fail=1
  check_file /etc/ld-musl-x86_64.path || fail=1
  check_mount /dev || fail=1
  check_mount /proc || fail=1
  check_mount /sys || fail=1
  check_mount /run || fail=1
  check_root_rw || fail=1

  if [ -r /etc/ld-musl-x86_64.path ]; then
    first="$(sed -n '1p' /etc/ld-musl-x86_64.path)"
    if [ "$first" = "/System/Libraries" ]; then
      ok "musl loader path starts with /System/Libraries"
    else
      fail_line "musl loader path starts with $first"
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

ensure_runtime() {
  PATH="/bin:/sbin:/System/SystemTools:/System/Tools/MixtarRVS/bin:/usr/bin:/usr/sbin"
  export PATH

  if [ -x /bin/mount ]; then
    /bin/mount -o remount,rw / >/dev/null 2>&1 || true
  else
    mount -o remount,rw / >/dev/null 2>&1 || true
  fi
  mkdir -p /dev /proc /sys /run /tmp /System/Runtime >/dev/null 2>&1 || true

  mount_fs proc proc /proc "" || return 1
  mount_fs devtmpfs devtmpfs /dev mode=0755 || return 1
  mount_fs sysfs sysfs /sys "" || return 1
  mount_fs tmpfs tmpfs /run mode=0755,nosuid,nodev || return 1

  mkdir -p "$config_dir" /System/Runtime/initramfs >/dev/null 2>&1 || true
  {
    line "MixtarRVS initramfs runtime ensure"
    line "pid=$$"
    line "kernel=$(uname -r 2>/dev/null || line unknown)"
    line "root=$(findmnt -no SOURCE,FSTYPE,OPTIONS / 2>/dev/null || line unknown)"
    line "dev=$(findmnt -no SOURCE,FSTYPE,OPTIONS /dev 2>/dev/null || line unknown)"
    line "proc=$(findmnt -no SOURCE,FSTYPE,OPTIONS /proc 2>/dev/null || line unknown)"
    line "sys=$(findmnt -no SOURCE,FSTYPE,OPTIONS /sys 2>/dev/null || line unknown)"
    line "run=$(findmnt -no SOURCE,FSTYPE,OPTIONS /run 2>/dev/null || line unknown)"
  } > "$report_file" 2>/dev/null || true

  return 0
}

handoff_dry_run() {
  contract
  line ""
  line "handoff sequence:"
  line "  1. set MixtarRVS early PATH"
  line "  2. remount / read-write"
  line "  3. ensure /dev devtmpfs"
  line "  4. ensure /proc procfs"
  line "  5. ensure /sys sysfs"
  line "  6. ensure /run tmpfs"
  line "  7. write initramfs runtime marker/report when /System is writable"
  line "  8. exec /System/SystemTools/init boot"
  line "  fallback: exec /sbin/init"
}

handoff() {
  if ! is_pid1; then
    line "refusing handoff: not PID 1" >&2
    line "use: /System/SystemTools/mixtar-initramfs-runtime ensure|check" >&2
    exit 2
  fi

  write_pid1_marker "handoff-start" "/System/SystemTools/init boot"

  ensure_runtime || {
    write_pid1_marker "ensure-failed" "/sbin/init"
    line "mixtar-initramfs-runtime: ensure failed, falling back to /sbin/init" >/dev/console 2>/dev/null || true
    exec /sbin/init
  }

  write_pid1_marker "before-system-init" "/System/SystemTools/init boot"

  exec /System/SystemTools/init boot
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
  ensure)
    ensure_runtime
    check
    ;;
  handoff-dry-run)
    handoff_dry_run
    ;;
  handoff)
    handoff
    ;;
  *)
    line "usage: mixtar-initramfs-runtime [contract|write-contract|check|ensure|handoff-dry-run|handoff]" >&2
    exit 2
    ;;
esac
