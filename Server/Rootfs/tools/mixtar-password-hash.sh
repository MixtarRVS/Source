#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
usage:
  mixtar-password-hash.sh
  mixtar-password-hash.sh --stdin

Generates a SHA-512 crypt password hash for MIXTAR_FIRST_PASSWORD_HASH.
Do not store plaintext passwords in scripts, manifests, or shell history.
EOF
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "help" ]; then
  usage
  exit 0
fi

command -v openssl >/dev/null 2>&1 || {
  printf '%s\n' "error: missing required tool: openssl" >&2
  exit 1
}

if [ "${1:-}" = "--stdin" ]; then
  openssl passwd -6 -stdin
  exit 0
fi

old_stty=$(stty -g 2>/dev/null || true)
cleanup() {
  if [ -n "$old_stty" ]; then
    stty "$old_stty" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

printf '%s' "Password: " >&2
stty -echo 2>/dev/null || true
IFS= read -r password
printf '\n%s' "Confirm: " >&2
IFS= read -r confirm
printf '\n' >&2
cleanup
trap - EXIT INT TERM

if [ "$password" != "$confirm" ]; then
  printf '%s\n' "error: passwords do not match" >&2
  exit 1
fi

printf '%s\n' "$password" | openssl passwd -6 -stdin
