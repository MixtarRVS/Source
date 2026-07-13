#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
Usage:
  mixtar-t480-firstboot.sh safe [--host=IP] [--user=USER] [--manifest=PATH]
  mixtar-t480-firstboot.sh install --phrase="FORMAT <target> AS <label>" [--host=IP] [--user=USER] [--manifest=PATH] [--allow-rescue-login]
  mixtar-t480-firstboot.sh full [--phrase=...] [--host=IP] [--user=USER] [--manifest=PATH] [--allow-rescue-login]
  mixtar-t480-firstboot.sh plan [--host=IP] [--user=USER] [--manifest=PATH]
  mixtar-t480-firstboot.sh login-plan [--manifest=PATH]
  mixtar-t480-firstboot.sh setup-login [--manifest=PATH] [--first-user=USER]
  mixtar-t480-firstboot.sh set-login --hash-stdin [--manifest=PATH] [--first-user=USER]
  mixtar-t480-firstboot.sh password-hash
  mixtar-t480-firstboot.sh help

Orchestrator for ThinkPad T480 Mixtar pre-v0 boot flow.
safe/full run the non-destructive preinstall gate before any physical install.
Physical install stays behind explicit phrase confirmation.
EOF
}

die() {
  printf '%s\n' "error: $*"
  exit 1
}

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
first_boot="$repo_root/Server/Installer/imported/Mixtar-OS-Setup/artifacts/mixtar-installer/scripts/first-boot-mixtar-t480.sh"
rebuild_script="$repo_root/Server/Rootfs/tools/mixtar-rebuild.sh"
password_hash_script="$repo_root/Server/Rootfs/tools/mixtar-password-hash.sh"

[ -f "$first_boot" ] || die "missing installer script: $first_boot"
[ -f "$rebuild_script" ] || die "missing rebuild script: $rebuild_script"
[ -f "$password_hash_script" ] || die "missing password hash script: $password_hash_script"

mode="${1:-safe}"
shift || true

host="192.168.99.110"
user="vxz"
manifest="$repo_root/Server/Rootfs/manifests/t480-pre-v0.mixtar.conf"
phrase="${MIXTAR_PHRASE:-}"
allow_rescue_login=0
first_user_override=""
hash_stdin=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --host=*) host="${1#*=}" ;;
    --user=*) user="${1#*=}" ;;
    --first-user=*) first_user_override="${1#*=}" ;;
    --manifest=*) manifest="${1#*=}" ;;
    --phrase=*) phrase="${1#*=}" ;;
    --allow-rescue-login) allow_rescue_login=1 ;;
    --hash-stdin) hash_stdin=1 ;;
    *) die "unknown argument: $1" ;;
  esac
  shift
done

[ -f "$manifest" ] || die "missing manifest: $manifest"

bootstrap_cmd() {
  mode_flag="$1"
  shift
  sh "$first_boot" "$mode_flag" --host="$host" --user="$user" --manifest="$manifest" "$@"
}

manifest_value() {
  key="$1"
  awk -v key="$key" -F= '
    $1 == key {
      value = $2
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      gsub(/^['\''"]|['\''"]$/, "", value)
      print value
      exit
    }
  ' "$manifest"
}

target_first_user() {
  if [ -n "$first_user_override" ]; then
    printf '%s\n' "$first_user_override"
    return 0
  fi

  configured_user=$(manifest_value MIXTAR_FIRST_USER)
  if [ -n "$configured_user" ]; then
    printf '%s\n' "$configured_user"
    return 0
  fi

  printf '%s\n' "vxz"
}

require_login_or_rescue_acceptance() {
  first_user=$(manifest_value MIXTAR_FIRST_USER)
  first_hash=$(manifest_value MIXTAR_FIRST_PASSWORD_HASH)

  if [ -n "$first_user" ] && [ -n "$first_hash" ]; then
    return 0
  fi

  if [ "$allow_rescue_login" -eq 1 ]; then
    printf '%s\n' "login_state=rescue-accepted"
    return 0
  fi

  sh "$rebuild_script" login-plan "$manifest" || true
  die "normal login is not ready; set MIXTAR_FIRST_PASSWORD_HASH or pass --allow-rescue-login"
}

ask_phrase() {
  if [ -z "$phrase" ]; then
    printf '%s\n' "To proceed with physical install, type exact phrase:"
    printf '%s\n' "FORMAT /dev/nvme0n1p3 AS MIXTARROOT"
    return 1
  fi
}

case "$mode" in
  safe)
    bootstrap_cmd --safe-only --with-preinstall-gate
    ;;
  install)
    require_login_or_rescue_acceptance
    if [ -z "$phrase" ]; then
      ask_phrase
      die "missing --phrase"
    fi
    bootstrap_cmd --install-only --phrase="$phrase"
    ;;
  full)
    require_login_or_rescue_acceptance
    bootstrap_cmd --safe-only --with-preinstall-gate
    printf '\n'
    printf '%s\n' "Safe preflight done."
    if [ -z "$phrase" ]; then
      die "full mode requires --phrase"
    fi
    bootstrap_cmd --install-only --phrase="$phrase"
    ;;
  plan)
    sh "$rebuild_script" readiness-report "$manifest"
    printf '\n'
    sh "$rebuild_script" physical-plan "$manifest"
    ;;
  login-plan)
    sh "$rebuild_script" login-plan "$manifest"
    ;;
  setup-login)
    login_user=$(target_first_user)
    sh "$password_hash_script" | sh "$rebuild_script" set-login "$manifest" "$login_user" --hash-stdin
    ;;
  set-login)
    [ "$hash_stdin" -eq 1 ] || die "set-login requires --hash-stdin"
    login_user=$(target_first_user)
    sh "$rebuild_script" set-login "$manifest" "$login_user" --hash-stdin
    ;;
  password-hash)
    sh "$password_hash_script"
    ;;
  help|--help|-h)
    usage
    exit 0
    ;;
  *)
    usage
    die "unknown mode: $mode"
    ;;
esac

printf '\n%s\n' "Done."
