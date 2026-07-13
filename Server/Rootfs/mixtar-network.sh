#!/bin/sh
set -eu

cmd="${1:-status}"

line() {
  printf '%s\n' "$*"
}

service_enabled() {
  name="$1"
  if [ -L "/etc/runlevels/default/$name" ]; then
    line "$name: enabled -> $(readlink "/etc/runlevels/default/$name")"
  elif [ -e "/etc/init.d/$name" ]; then
    line "$name: present"
  else
    line "$name: missing"
  fi
}

interface_status() {
  iface="$1"
  state="unknown"
  mac="unknown"
  if [ -r "/sys/class/net/$iface/operstate" ]; then
    state=$(cat "/sys/class/net/$iface/operstate")
  fi
  if [ -r "/sys/class/net/$iface/address" ]; then
    mac=$(cat "/sys/class/net/$iface/address")
  fi
  line "$iface state=$state mac=$mac"
}

status_interfaces() {
  if [ ! -d /sys/class/net ]; then
    line "interfaces: /sys/class/net missing"
    return
  fi
  line "interfaces:"
  for path in /sys/class/net/*; do
    [ -e "$path" ] || continue
    interface_status "$(basename "$path")" | sed 's/^/  /'
  done
}

status_routes() {
  if [ -r /proc/net/route ]; then
    line "routes:"
    sed 's/^/  /' /proc/net/route
  else
    line "routes: /proc/net/route missing"
  fi
}

status_config() {
  line "config:"
  for path in /etc/iwd /etc/dhcpcd.conf /etc/resolv.conf; do
    if [ -d "$path" ]; then
      line "  dir  $path"
    elif [ -r "$path" ]; then
      line "  file $path"
    elif [ -e "$path" ]; then
      line "  unreadable $path"
    else
      line "  missing $path"
    fi
  done
}

status_services() {
  line "services:"
  service_enabled iwd | sed 's/^/  /'
  service_enabled dhcpcd | sed 's/^/  /'
}

status_all() {
  line "MixtarRVS network status"
  line "backend: iwd-dhcpcd-bootstrap"
  status_services
  status_config
  status_interfaces
  status_routes
}

case "$cmd" in
  status)
    status_all
    ;;
  backend)
    line "iwd-dhcpcd-bootstrap"
    ;;
  *)
    line "usage: mixtar-network [status|backend]" >&2
    exit 2
    ;;
esac
