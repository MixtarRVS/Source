#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
usage:
  mixtar-set-login.sh <manifest> <first-user> --hash-stdin

Updates MIXTAR_FIRST_USER and MIXTAR_FIRST_PASSWORD_HASH in a Mixtar manifest.
The password hash is read from stdin and must be a SHA-512 crypt hash starting
with $6$. Plaintext passwords are never accepted.

Recommended flow:
  mixtar-password-hash.sh | mixtar-set-login.sh t480-pre-v0.mixtar.conf vxz --hash-stdin
EOF
}

die() {
  printf '%s\n' "error: $*" >&2
  exit 1
}

manifest="${1:-}"
first_user="${2:-}"
mode="${3:-}"

if [ "$manifest" = "help" ] || [ "$manifest" = "--help" ]; then
  usage
  exit 0
fi

[ -n "$manifest" ] || die "missing manifest"
[ -f "$manifest" ] || die "missing manifest: $manifest"
[ -n "$first_user" ] || die "missing first-user"
[ "$mode" = "--hash-stdin" ] || die "expected --hash-stdin"

printf '%s\n' "$first_user" | grep -Eq '^[a-z_][a-z0-9_-]*$' || die "invalid first-user: $first_user"

IFS= read -r hash || die "missing hash on stdin"

case "$hash" in
  '$6$'*) ;;
  *) die "hash must start with \$6\$" ;;
esac

[ "${#hash}" -gt 20 ] || die "hash is too short"

case "$hash" in
  *"'"*) die "hash contains unsupported characters" ;;
esac

tmp="${manifest}.tmp.$$"
awk -v user="$first_user" -v hash="$hash" '
  BEGIN {
    seen_user = 0
    seen_hash = 0
    sq = sprintf("%c", 39)
  }
  /^MIXTAR_FIRST_USER=/ {
    print "MIXTAR_FIRST_USER=\"" user "\""
    seen_user = 1
    next
  }
  /^MIXTAR_FIRST_PASSWORD_HASH=/ {
    print "MIXTAR_FIRST_PASSWORD_HASH=" sq hash sq
    seen_hash = 1
    next
  }
  { print }
  END {
    if (!seen_user) {
      print "MIXTAR_FIRST_USER=\"" user "\""
    }
    if (!seen_hash) {
      print "MIXTAR_FIRST_PASSWORD_HASH=" sq hash sq
    }
  }
' "$manifest" > "$tmp"

mv "$tmp" "$manifest"
printf '%s\n' "login manifest updated: $manifest"
printf '%s\n' "first_user=$first_user"
printf '%s\n' "state=login-ready-after-rebuild"
