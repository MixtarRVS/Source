#!/bin/sh
set -eu

cmd="${1:-status}"

line() {
  printf '%s\n' "$*"
}

path_status() {
  path="$1"
  if [ -L "$path" ]; then
    line "link $path -> $(readlink "$path")"
  elif [ -d "$path" ]; then
    line "dir  $path"
  elif [ -r "$path" ]; then
    line "file $path"
  elif [ -e "$path" ]; then
    line "unreadable $path"
  else
    line "missing $path"
  fi
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

sshd_config_test() {
  if command -v sshd >/dev/null 2>&1; then
    if sshd -t -f /etc/ssh/sshd_config >/dev/null 2>&1; then
      line "sshd_config_test: ok"
    else
      line "sshd_config_test: fail"
    fi
  elif [ -x /usr/sbin/sshd ]; then
    if /usr/sbin/sshd -t -f /etc/ssh/sshd_config >/dev/null 2>&1; then
      line "sshd_config_test: ok"
    else
      line "sshd_config_test: fail"
    fi
  else
    line "sshd_config_test: sshd missing"
  fi
}

status_all() {
  line "MixtarRVS remote access status"
  line "backend: openssh-bootstrap"
  service_enabled sshd
  path_status /etc/ssh/sshd_config
  path_status /etc/ssh/ssh_host_ed25519_key
  path_status /etc/ssh/ssh_host_rsa_key
  path_status /home/vxz/.ssh/authorized_keys
  path_status /Users/Administrator/.ssh/authorized_keys
  sshd_config_test
}

case "$cmd" in
  status)
    status_all
    ;;
  backend)
    line "openssh-bootstrap"
    ;;
  *)
    line "usage: mixtar-remote [status|backend]" >&2
    exit 2
    ;;
esac
