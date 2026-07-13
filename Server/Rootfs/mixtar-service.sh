#!/bin/sh
set -eu

cmd="${1:-list}"
service="${2:-}"
runlevel_dir="/etc/runlevels/default"

line() {
  printf '%s\n' "$*"
}

backend() {
  if command -v rc-service >/dev/null 2>&1; then
    line "rc-service"
    return
  fi
  if [ -x /sbin/rc-service ]; then
    line "/sbin/rc-service"
    return
  fi
  line ""
}

require_service() {
  if [ -z "$service" ]; then
    line "missing service name" >&2
    exit 2
  fi
  if [ ! -e "/etc/init.d/$service" ]; then
    line "unknown service: $service" >&2
    exit 2
  fi
}

list_services() {
  line "MixtarRVS services"
  line "backend: openrc-bootstrap"
  if [ ! -d "$runlevel_dir" ]; then
    line "default_runlevel: missing"
    return
  fi
  line "default_runlevel:"
  for entry in "$runlevel_dir"/*; do
    [ -e "$entry" ] || continue
    name=$(basename "$entry")
    if [ -L "$entry" ]; then
      target=$(readlink "$entry")
      line "  $name -> $target"
    else
      line "  $name"
    fi
  done
}

status_all() {
  line "MixtarRVS service status"
  line "backend: openrc-bootstrap"
  if command -v rc-status >/dev/null 2>&1; then
    rc-status 2>/dev/null || true
  elif [ -x /bin/rc-status ]; then
    /bin/rc-status 2>/dev/null || true
  elif [ -x /sbin/rc-status ]; then
    /sbin/rc-status 2>/dev/null || true
  else
    line "rc-status: missing"
  fi
}

status_one() {
  require_service
  rc=$(backend)
  if [ -n "$rc" ]; then
    "$rc" "$service" status || true
    return
  fi
  "/etc/init.d/$service" status || true
}

run_action() {
  action="$1"
  require_service
  rc=$(backend)
  if [ -z "$rc" ]; then
    line "rc-service backend missing" >&2
    exit 2
  fi
  "$rc" "$service" "$action"
}

case "$cmd" in
  list)
    list_services
    ;;
  status)
    if [ -n "$service" ]; then
      status_one
    else
      status_all
    fi
    ;;
  start|stop|restart)
    run_action "$cmd"
    ;;
  backend)
    line "openrc-bootstrap"
    ;;
  *)
    line "usage: mixtar-service [list|status [name]|start name|stop name|restart name|backend]" >&2
    exit 2
    ;;
esac
