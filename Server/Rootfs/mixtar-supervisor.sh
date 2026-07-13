#!/bin/sh
set -eu

cmd="${1:-list}"
arg="${2:-}"
manifest_dir="/System/Config/MixtarRVS/services"
config_dir="/System/Config/MixtarRVS"
pid1_marker="$config_dir/supervisor-pid1-latest.txt"
pid1_check_report="$config_dir/supervisor-pid1-check.txt"
pid1_direct_start_dbus_report="$config_dir/supervisor-pid1-direct-start-dbus.txt"

line() {
  printf '%s\n' "$*"
}

field() {
  file="$1"
  key="$2"
  sed -n "s/^$key=//p" "$file" 2>/dev/null | tail -n 1
}

write_manifest() {
  name="$1"
  service="$2"
  enabled="$3"
  critical="$4"
  after="$5"
  path="$manifest_dir/$name.service"

  if [ -e "$path" ]; then
    line "exists: $path"
    return
  fi

  cat > "$path" <<EOF
name=$name
backend=openrc-bootstrap
service=$service
enabled=$enabled
critical=$critical
after=$after
EOF
  line "created: $path"
}

is_pid1() {
  [ "$$" -eq 1 ]
}

write_pid1_marker() {
  stage="$1"
  next="$2"
  mkdir -p "$config_dir" >/dev/null 2>&1 || true
  {
    line "MixtarRVS supervisor PID1 marker"
    line "stage=$stage"
    line "pid=$$"
    line "next=$next"
    line "kernel=$(uname -r 2>/dev/null || line unknown)"
  } > "$pid1_marker" 2>/dev/null || true
  {
    line "MixtarRVS supervisor PID1 marker"
    line "stage=$stage"
    line "pid=$$"
    line "next=$next"
    line "kernel=$(uname -r 2>/dev/null || line unknown)"
  } > /dev/mixtar-supervisor.pid1 2>/dev/null || true
}

contract() {
  line "MixtarRVS supervisor contract"
  line "status: candidate-not-active"
  line "manifest_dir: $manifest_dir"
  line "manifest_format: key=value"
  line "backend_current: openrc-bootstrap"
  line "allowed_now:"
  line "  contract"
  line "  check"
  line "  list"
  line "  plan"
  line "  write-defaults"
  line "  direct-status"
  line "  direct-start-plan dbus"
  line "  direct-start dbus"
  line "  direct-start-plan iwd"
  line "  direct-start iwd"
  line "  direct-start-plan dhcpcd"
  line "  direct-start dhcpcd"
  line "  pid1-openrc candidate, only when selected by one-shot boot"
  line "not_allowed_yet:"
  line "  replacing OpenRC PID1"
  line "  broad service restart policy"
}

write_defaults() {
  mkdir -p "$manifest_dir"
  write_manifest dbus dbus true false localmount
  write_manifest iwd iwd true true dbus
  write_manifest dhcpcd dhcpcd true true iwd
  write_manifest sshd sshd true true network
  write_manifest mixtar-firstboot-report mixtar-firstboot-report true false localmount
  write_manifest mixtar-boot-profiler mixtar-boot-profiler true false localmount
  write_manifest mixtar-ssh-watchdog mixtar-ssh-watchdog true true sshd
  write_manifest mixtar-return-debian-once mixtar-return-debian-once true true sshd
}

check_one() {
  file="$1"
  fail=0
  name=$(field "$file" name)
  backend=$(field "$file" backend)
  service=$(field "$file" service)
  enabled=$(field "$file" enabled)
  critical=$(field "$file" critical)

  if [ -z "$name" ]; then line "fail: $file missing name"; fail=1; fi
  if [ "$backend" != "openrc-bootstrap" ]; then line "fail: $file backend=$backend"; fail=1; fi
  if [ -z "$service" ]; then line "fail: $file missing service"; fail=1; fi
  if [ "$enabled" != "true" ] && [ "$enabled" != "false" ]; then line "fail: $file enabled=$enabled"; fail=1; fi
  if [ "$critical" != "true" ] && [ "$critical" != "false" ]; then line "fail: $file critical=$critical"; fail=1; fi
  if [ -n "$service" ] && [ ! -e "/etc/init.d/$service" ]; then line "fail: $file service missing /etc/init.d/$service"; fail=1; fi

  if [ "$fail" -eq 0 ]; then
    line "ok: $(basename "$file") service=$service enabled=$enabled critical=$critical"
  fi
  return "$fail"
}

check() {
  fail=0
  line "MixtarRVS supervisor check"
  if [ ! -d "$manifest_dir" ]; then
    line "fail: missing manifest directory $manifest_dir"
    line "hint: run /System/SystemTools/mixtar-supervisor write-defaults"
    return 1
  fi
  found=0
  for file in "$manifest_dir"/*.service; do
    [ -e "$file" ] || continue
    found=1
    check_one "$file" || fail=1
  done
  if [ "$found" -eq 0 ]; then
    line "fail: no service manifests in $manifest_dir"
    fail=1
  fi
  if [ "$fail" -eq 0 ]; then
    line "status: PASS"
  else
    line "status: FAIL"
  fi
  return "$fail"
}

list_services() {
  line "MixtarRVS supervisor services"
  line "backend: openrc-bootstrap"
  if [ ! -d "$manifest_dir" ]; then
    line "manifest_dir: missing $manifest_dir"
    return
  fi
  for file in "$manifest_dir"/*.service; do
    [ -e "$file" ] || continue
    name=$(field "$file" name)
    service=$(field "$file" service)
    enabled=$(field "$file" enabled)
    critical=$(field "$file" critical)
    line "$name service=$service enabled=$enabled critical=$critical"
  done
}

proc_comm_exists() {
  expected="$1"
  for proc_dir in /proc/[0-9]*; do
    [ -r "$proc_dir/comm" ] || continue
    read -r comm < "$proc_dir/comm" || continue
    if [ "$comm" = "$expected" ]; then
      return 0
    fi
  done
  return 1
}

proc_cmdline_contains() {
  expected="$1"
  for proc_dir in /proc/[0-9]*; do
    [ -r "$proc_dir/cmdline" ] || continue
    tr '\000' ' ' < "$proc_dir/cmdline" 2>/dev/null | grep -q "$expected" && return 0
  done
  return 1
}

direct_status_one() {
  name="$1"
  fail=0
  case "$name" in
    dbus)
      if proc_comm_exists dbus-daemon && [ -S /run/dbus/system_bus_socket ]; then
        line "ok: dbus process=dbus-daemon socket=/run/dbus/system_bus_socket"
      else
        line "fail: dbus direct status"
        fail=1
      fi
      ;;
    iwd)
      if proc_comm_exists iwd; then
        line "ok: iwd process=iwd"
      else
        line "fail: iwd direct status"
        fail=1
      fi
      ;;
    dhcpcd)
      if proc_comm_exists dhcpcd; then
        line "ok: dhcpcd process=dhcpcd"
      else
        line "fail: dhcpcd direct status"
        fail=1
      fi
      ;;
    sshd)
      if proc_comm_exists sshd || proc_cmdline_contains "sshd"; then
        line "ok: sshd process=sshd"
      else
        line "fail: sshd direct status"
        fail=1
      fi
      ;;
    *)
      line "skip: $name direct status not defined"
      ;;
  esac
  return "$fail"
}

direct_status() {
  fail=0
  line "MixtarRVS direct service status"
  line "backend: mixtar-procfs"
  if [ ! -d /proc ]; then
    line "fail: /proc missing"
    line "status: FAIL"
    return 1
  fi
  for name in dbus iwd dhcpcd sshd; do
    direct_status_one "$name" || fail=1
  done
  if [ "$fail" -eq 0 ]; then
    line "status: PASS"
  else
    line "status: FAIL"
  fi
  return "$fail"
}

direct_start_plan() {
  name="$1"
  case "$name" in
    dbus)
      line "MixtarRVS direct start plan: dbus"
      line "backend: mixtar-direct"
      line "1. if dbus-daemon and /run/dbus/system_bus_socket already exist, do nothing"
      line "2. ensure /run/dbus exists"
      line "3. start /usr/bin/dbus-daemon --system --fork"
      line "4. verify direct-status dbus"
      line "5. OpenRC remains fallback and still owns default boot ordering"
      ;;
    iwd)
      line "MixtarRVS direct start plan: iwd"
      line "backend: mixtar-direct"
      line "1. require dbus direct status to be OK"
      line "2. if iwd already exists, do nothing"
      line "3. start /usr/libexec/iwd in background"
      line "4. write /run/iwd.pid"
      line "5. verify direct-status iwd"
      line "6. OpenRC remains fallback and still owns default boot ordering"
      ;;
    dhcpcd)
      line "MixtarRVS direct start plan: dhcpcd"
      line "backend: mixtar-direct"
      line "1. require iwd direct status to be OK for this Wi-Fi boot profile"
      line "2. if dhcpcd already exists, do nothing"
      line "3. ensure /run/dhcpcd exists"
      line "4. start /sbin/dhcpcd -q"
      line "5. verify direct-status dhcpcd"
      line "6. OpenRC remains fallback and still owns default boot ordering"
      ;;
    *)
      line "unsupported direct-start-plan service: $name" >&2
      return 2
      ;;
  esac
}

direct_start_dbus() {
  if proc_comm_exists dbus-daemon && [ -S /run/dbus/system_bus_socket ]; then
    line "ok: dbus already running"
    return 0
  fi

  if [ ! -x /usr/bin/dbus-daemon ]; then
    line "fail: missing /usr/bin/dbus-daemon"
    return 1
  fi

  mkdir -p /run/dbus || {
    line "fail: cannot create /run/dbus"
    return 1
  }

  /usr/bin/dbus-daemon --system --fork || {
    line "fail: dbus-daemon --system --fork"
    return 1
  }

  sleep 1
  direct_status_one dbus
}

direct_start_iwd() {
  if proc_comm_exists iwd; then
    line "ok: iwd already running"
    return 0
  fi

  if ! proc_comm_exists dbus-daemon || [ ! -S /run/dbus/system_bus_socket ]; then
    line "fail: dbus is required before iwd"
    return 1
  fi

  if [ ! -x /usr/libexec/iwd ]; then
    line "fail: missing /usr/libexec/iwd"
    return 1
  fi

  /usr/libexec/iwd >/dev/null 2>&1 &
  pid="$!"
  mkdir -p /run || true
  printf '%s\n' "$pid" > /run/iwd.pid 2>/dev/null || true

  sleep 1
  direct_status_one iwd
}

direct_start_dhcpcd() {
  if proc_comm_exists dhcpcd; then
    line "ok: dhcpcd already running"
    return 0
  fi

  if ! proc_comm_exists iwd; then
    line "fail: iwd is required before dhcpcd in this profile"
    return 1
  fi

  if [ ! -x /sbin/dhcpcd ]; then
    line "fail: missing /sbin/dhcpcd"
    return 1
  fi

  mkdir -p /run/dhcpcd || {
    line "fail: cannot create /run/dhcpcd"
    return 1
  }

  /sbin/dhcpcd -q || {
    line "fail: /sbin/dhcpcd -q"
    return 1
  }

  sleep 2
  direct_status_one dhcpcd
}

direct_start() {
  name="$1"
  line "MixtarRVS direct start"
  line "backend: mixtar-direct"
  case "$name" in
    dbus)
      direct_start_dbus
      ;;
    iwd)
      direct_start_iwd
      ;;
    dhcpcd)
      direct_start_dhcpcd
      ;;
    *)
      line "unsupported direct-start service: $name" >&2
      return 2
      ;;
  esac
}

plan() {
  line "MixtarRVS supervisor activation plan"
  line "1. keep OpenRC as backend while manifests stabilize"
  line "2. require supervisor check to pass before any boot integration"
  line "3. make /System/SystemTools/init exec supervisor only after runtime mounts are ready"
  line "4. supervisor runs as PID1, writes marker, validates manifests, then execs /sbin/init"
  line "5. use direct-status to prove Mixtar-owned service health checks without rc-status"
  line "6. add direct-start for simple services first: dbus, iwd, then dhcpcd"
  line "7. start with OpenRC fallback; no broad service restart policy yet"
  line "8. replace OpenRC backend only after service ordering and failure policy are proven"
}

pid1_openrc() {
  if ! is_pid1; then
    line "refusing pid1-openrc: not PID 1" >&2
    exit 2
  fi

  PATH="/bin:/sbin:/System/SystemTools:/System/Tools/MixtarRVS/bin:/usr/bin:/usr/sbin"
  export PATH

  write_pid1_marker "start" "/sbin/init"
  if check > "$pid1_check_report" 2>&1; then
    write_pid1_marker "before-openrc" "/sbin/init"
  else
    write_pid1_marker "check-failed-openrc-fallback" "/sbin/init"
  fi

  if grep -q 'mixtar.direct_start=dbus' /proc/cmdline 2>/dev/null; then
    {
      line "MixtarRVS supervisor PID1 direct-start dbus"
      line "mode=before-openrc"
      line "kernel=$(uname -r 2>/dev/null || line unknown)"
      direct_start_plan dbus
      direct_start dbus
      line "direct_status_after:"
      direct_status
    } > "$pid1_direct_start_dbus_report" 2>&1 || true
  fi

  if grep -q 'mixtar.direct_start=dbus,iwd' /proc/cmdline 2>/dev/null || grep -q 'mixtar.direct_start=iwd' /proc/cmdline 2>/dev/null; then
    {
      line "MixtarRVS supervisor PID1 direct-start iwd"
      line "mode=before-openrc"
      line "kernel=$(uname -r 2>/dev/null || line unknown)"
      direct_start_plan iwd
      direct_start iwd
      line "direct_status_after:"
      direct_status
    } > "$config_dir/supervisor-pid1-direct-start-iwd.txt" 2>&1 || true
  fi

  if grep -q 'mixtar.direct_start=dbus,iwd,dhcpcd' /proc/cmdline 2>/dev/null || grep -q 'mixtar.direct_start=dhcpcd' /proc/cmdline 2>/dev/null; then
    {
      line "MixtarRVS supervisor PID1 direct-start dhcpcd"
      line "mode=before-openrc"
      line "kernel=$(uname -r 2>/dev/null || line unknown)"
      direct_start_plan dhcpcd
      direct_start dhcpcd
      line "direct_status_after:"
      direct_status
    } > "$config_dir/supervisor-pid1-direct-start-dhcpcd.txt" 2>&1 || true
  fi

  exec /sbin/init
}

case "$cmd" in
  contract)
    contract
    ;;
  write-defaults)
    write_defaults
    ;;
  check)
    check
    ;;
  list)
    list_services
    ;;
  plan)
    plan
    ;;
  direct-status)
    direct_status
    ;;
  direct-start-plan)
    if [ -z "$arg" ]; then
      line "usage: mixtar-supervisor direct-start-plan dbus" >&2
      exit 2
    fi
    direct_start_plan "$arg"
    ;;
  direct-start)
    if [ -z "$arg" ]; then
      line "usage: mixtar-supervisor direct-start dbus" >&2
      exit 2
    fi
    direct_start "$arg"
    ;;
  pid1-openrc)
    pid1_openrc
    ;;
  *)
    line "usage: mixtar-supervisor [contract|write-defaults|check|list|plan|direct-status|direct-start-plan dbus|direct-start dbus|direct-start-plan iwd|direct-start iwd|direct-start-plan dhcpcd|direct-start dhcpcd|pid1-openrc]" >&2
    exit 2
    ;;
esac
