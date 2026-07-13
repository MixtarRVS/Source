#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
usage:
  mixtar-boot-evidence.sh

Collects post-boot evidence for MixtarRVS pre-v0 on a live system.
This is intentionally non-destructive and prints a compact checklist.

It should be run inside the booted Mixtar system (TTY/SSH).
EOF
}

die() {
  printf '%s
' "error: $*" >&2
  exit 1
}

if [ "${1:-}" = "help" ] || [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

ok=0
fail=0

check() {
  label="$1"
  shift
  if "$@"; then
    printf '[ok] %s
' "$label"
    ok=$((ok + 1))
  else
    printf '[!!] %s
' "$label"
    fail=$((fail + 1))
  fi
}

print_sep() {
  printf '
### %s
' "$1"
}

print_sep "Core"
check "Kernel identifies as Linux" sh -c 'uname -s | grep -q Linux'
check "Kernel command line is accessible" sh -c 'cat /proc/cmdline >/dev/null'
check "OpenRC init files exist" sh -c '[ -f /sbin/init ] && [ -d /etc/init.d ]'
check "Booted /System" sh -c '[ -d /System ]'
check "Generation link exists" sh -c '[ -L /System/Current ]'

print_sep "Identity layout"
check "/System path exists" sh -c '[ -e /System/Shells ]'
check "/Applications path exists" sh -c '[ -e /Applications ]'
check "/Programs path exists" sh -c '[ -e /Programs ]'
check "/Users path exists" sh -c '[ -e /Users ]'
check "/Compatibility path exists" sh -c '[ -e /Compatibility ]'

print_sep "Runtime contract"
check "/System/Runtime/generation.env readable" sh -c '[ -r /System/Runtime/generation.env ]'
check "Mixtar generation file exists" sh -c '[ -r /System/Current/manifest.json ]'

print_sep "Shell + tools"
check "/bin/zsh exists" sh -c '[ -x /bin/zsh ]'
check "Mixtar shell path resolves" sh -c '[ -x /System/Shells/zsh ]'
check "Mixtar postboot report tool exists" sh -c '[ -x /System/Tools/mixtar-postboot-report ]'
check "Mixtar firstboot verifier exists" sh -c '[ -x /System/Tools/mixtar-firstboot-verify ]'
check "Mixtar generation report exists" sh -c '[ -x /System/Tools/mixtar-generation-report ]'
check "OpenSSH server exists" sh -c '[ -x /usr/sbin/sshd ]'

print_sep "OpenRC"
check "OpenRC default status query" rc-status >/dev/null
check "firstboot report service known" rc-status 2>/dev/null | grep -q mixtar-firstboot-report
check "sshd service known" rc-status 2>/dev/null | grep -q sshd
check "iwd service known" rc-status 2>/dev/null | grep -q iwd
check "dhcpcd service known" rc-status 2>/dev/null | grep -q dhcpcd

print_sep "Remote access"
check "vxz authorized_keys exists" sh -c '[ -r /Users/vxz/.ssh/authorized_keys ]'
check "iwd config exists" sh -c '[ -r /etc/iwd/main.conf ]'
check "dhcpcd config exists" sh -c '[ -r /etc/dhcpcd.conf ]'
check "sshd config exists" sh -c '[ -r /etc/ssh/sshd_config ]'

print_sep "Filesystem evidence"
printf '  /System/Current -> '; readlink /System/Current || printf 'unreadable
'

print_sep "Firstboot evidence files"
check "/System/Logs/firstboot-evidence.txt" sh -c '[ -f /System/Logs/firstboot-evidence.txt ]'
check "/System/Logs/firstboot-report.service.log" sh -c '[ -f /System/Logs/firstboot-report.service.log ]'

print_sep "Commands"
printf 'uname: '; uname -a
printf 'user shell: '; getent passwd root | awk -F: '{print $7}' || printf 'n/a
'

printf '
### Mixtar firstboot verifier output
'
if [ -x /System/Tools/mixtar-firstboot-verify ]; then
  /System/Tools/mixtar-firstboot-verify || true
else
  printf 'missing /System/Tools/mixtar-firstboot-verify
'
fi

printf '
### Evidence logs (if present)
'
cat /System/Logs/firstboot-evidence.txt 2>/dev/null || true
cat /System/Logs/firstboot-report.service.log 2>/dev/null || true

print_sep "Result"
if [ "$fail" -eq 0 ]; then
  printf 'BOOT_EVIDENCE_OK=%s PASS (ok=%s fail=%s)
' "true" "$ok" "$fail"
  exit 0
fi

printf 'BOOT_EVIDENCE_OK=%s PASS? (ok=%s fail=%s)
' "false" "$ok" "$fail"
exit 1
