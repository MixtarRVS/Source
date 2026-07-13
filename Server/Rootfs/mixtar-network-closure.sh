#!/bin/sh
set -eu

cmd="${1:-check}"
closure_dir="/System/Config/MixtarRVS/network"
manifest="$closure_dir/iwd-dhcpcd-bootstrap.manifest"

line() {
  printf '%s\n' "$*"
}

path_kind() {
  path="$1"
  if [ -L "$path" ]; then
    line "link $path -> $(readlink "$path")"
  elif [ -d "$path" ]; then
    line "dir $path"
  elif [ -r "$path" ]; then
    line "file $path"
  elif [ -e "$path" ]; then
    line "unreadable $path"
  else
    line "missing $path"
  fi
}

check_path() {
  path="$1"
  if [ -r "$path" ] || [ -x "$path" ]; then
    line "ok: $path"
    return 0
  fi
  line "fail: $path"
  return 1
}

check_optional() {
  path="$1"
  if [ -e "$path" ]; then
    line "ok: optional $path"
  else
    line "note: optional missing $path"
  fi
}

contract() {
  line "MixtarRVS network closure contract"
  line "status: pinned-bootstrap"
  line "backend: iwd-dhcpcd-bootstrap"
  line "closure_dir: $closure_dir"
  line "required:"
  line "  /etc/init.d/iwd"
  line "  /etc/init.d/dhcpcd"
  line "  /usr/libexec/iwd"
  line "  /sbin/dhcpcd"
  line "  /etc/iwd"
  line "  /etc/dhcpcd.conf"
  line "  /etc/resolv.conf"
  line "policy:"
  line "  iwd handles Wi-Fi device/auth bootstrap"
  line "  dhcpcd handles DHCP bootstrap"
  line "  native Mixtar network bring-up is pending"
  line "  no service restart is allowed by this closure tool"
}

write_manifest() {
  mkdir -p "$closure_dir"
  {
    line "backend=iwd-dhcpcd-bootstrap"
    line "wifi_service=iwd"
    line "dhcp_service=dhcpcd"
    line "wifi_daemon=/usr/libexec/iwd"
    line "dhcp_client=/sbin/dhcpcd"
    line "wifi_config_dir=/etc/iwd"
    line "dhcp_config=/etc/dhcpcd.conf"
    line "resolver_config=/etc/resolv.conf"
    line "native_network_pending=true"
  } > "$manifest"
  cat "$manifest"
}

check() {
  fail=0
  line "MixtarRVS network closure check"
  check_path /etc/init.d/iwd || fail=1
  check_path /etc/init.d/dhcpcd || fail=1
  check_path /usr/libexec/iwd || fail=1
  check_path /sbin/dhcpcd || fail=1
  check_path /etc/iwd || fail=1
  check_path /etc/dhcpcd.conf || fail=1
  check_path /etc/resolv.conf || fail=1
  if [ -r "$manifest" ]; then
    line "ok: $manifest"
  else
    line "fail: missing $manifest"
    fail=1
  fi
  check_optional /var/lib/iwd
  if [ "$fail" -eq 0 ]; then
    line "status: PASS"
  else
    line "status: FAIL"
  fi
  return "$fail"
}

status_interfaces() {
  if [ ! -d /sys/class/net ]; then
    line "interfaces: /sys/class/net missing"
    return
  fi
  line "interfaces:"
  for path in /sys/class/net/*; do
    [ -e "$path" ] || continue
    iface=$(basename "$path")
    state="unknown"
    if [ -r "$path/operstate" ]; then
      state=$(cat "$path/operstate")
    fi
    line "  $iface state=$state"
  done
}

status() {
  line "MixtarRVS network closure status"
  line "backend: iwd-dhcpcd-bootstrap"
  path_kind /etc/init.d/iwd
  path_kind /etc/init.d/dhcpcd
  path_kind /usr/libexec/iwd
  path_kind /sbin/dhcpcd
  path_kind /etc/iwd
  path_kind /etc/dhcpcd.conf
  path_kind /etc/resolv.conf
  path_kind "$manifest"
  status_interfaces
  check
}

plan() {
  line "MixtarRVS network closure next plan"
  line "1. keep iwd/dhcpcd pinned as network backend while base closure stabilizes"
  line "2. make live gate require network closure check"
  line "3. add read-only network health checks first"
  line "4. add explicit Mixtar network bring-up only after service ordering is proven"
  line "5. replace iwd/dhcpcd service identity only after native policy supports Wi-Fi, DHCP, DNS, and fallback"
}

case "$cmd" in
  contract)
    contract
    ;;
  write-manifest)
    write_manifest
    ;;
  check)
    check
    ;;
  status)
    status
    ;;
  plan)
    plan
    ;;
  *)
    line "usage: mixtar-network-closure [contract|write-manifest|check|status|plan]" >&2
    exit 2
    ;;
esac
