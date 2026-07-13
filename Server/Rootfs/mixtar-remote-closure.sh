#!/bin/sh
set -eu

cmd="${1:-check}"
closure_dir="/System/Config/MixtarRVS/remote"
manifest="$closure_dir/openssh-bootstrap.manifest"

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

check_exists() {
  path="$1"
  if [ -e "$path" ]; then
    line "ok: exists $path"
    return 0
  fi
  line "fail: missing $path"
  return 1
}

is_root() {
  [ "$(id -u)" -eq 0 ]
}

contract() {
  line "MixtarRVS remote closure contract"
  line "status: pinned-bootstrap"
  line "backend: openssh-bootstrap"
  line "closure_dir: $closure_dir"
  line "required:"
  line "  /usr/sbin/sshd"
  line "  /etc/ssh/sshd_config"
  line "  /etc/ssh/ssh_host_ed25519_key"
  line "  /etc/ssh/ssh_host_rsa_key"
  line "  /home/vxz/.ssh/authorized_keys"
  line "policy:"
  line "  root ssh is not required"
  line "  vxz key login is the operational remote channel"
  line "  OpenSSH remains backend until a Mixtar remote agent exists"
}

write_manifest() {
  mkdir -p "$closure_dir"
  {
    line "backend=openssh-bootstrap"
    line "sshd=/usr/sbin/sshd"
    line "config=/etc/ssh/sshd_config"
    line "hostkey_ed25519=/etc/ssh/ssh_host_ed25519_key"
    line "hostkey_rsa=/etc/ssh/ssh_host_rsa_key"
    line "authorized_keys_vxz=/home/vxz/.ssh/authorized_keys"
    line "root_ssh_required=false"
    line "steady_state_user=vxz"
  } > "$manifest"
  cat "$manifest"
}

check() {
  fail=0
  line "MixtarRVS remote closure check"
  check_path /usr/sbin/sshd || fail=1
  check_path /etc/ssh/sshd_config || fail=1
  check_exists /etc/ssh/ssh_host_ed25519_key || fail=1
  check_exists /etc/ssh/ssh_host_rsa_key || fail=1
  check_path /home/vxz/.ssh/authorized_keys || fail=1
  if [ -r "$manifest" ]; then
    line "ok: $manifest"
  else
    line "fail: missing $manifest"
    fail=1
  fi
  if is_root; then
    if /usr/sbin/sshd -t -f /etc/ssh/sshd_config >/dev/null 2>&1; then
      line "ok: sshd_config_test"
    else
      line "fail: sshd_config_test"
      fail=1
    fi
  else
    line "ok: sshd_config_test skipped for non-root"
  fi
  if [ "$fail" -eq 0 ]; then
    line "status: PASS"
  else
    line "status: FAIL"
  fi
  return "$fail"
}

status() {
  line "MixtarRVS remote closure status"
  line "backend: openssh-bootstrap"
  path_kind /usr/sbin/sshd
  path_kind /etc/ssh/sshd_config
  path_kind /etc/ssh/ssh_host_ed25519_key
  path_kind /etc/ssh/ssh_host_rsa_key
  path_kind /home/vxz/.ssh/authorized_keys
  path_kind "$manifest"
  check
}

plan() {
  line "MixtarRVS remote closure next plan"
  line "1. keep OpenSSH pinned as remote backend while base closure stabilizes"
  line "2. keep vxz key login as required operational channel"
  line "3. make live gate require remote closure check"
  line "4. later add Mixtar remote agent as optional parallel service"
  line "5. replace OpenSSH identity only after agent supports command, log, health, and reboot fallback"
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
    line "usage: mixtar-remote-closure [contract|write-manifest|check|status|plan]" >&2
    exit 2
    ;;
esac
