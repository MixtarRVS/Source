#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
usage:
  mixtar-plan-grub-entry.sh plan <root-label> [kernel-release]
  mixtar-plan-grub-entry.sh install <root-label> [kernel-release] --write-grub

Prints or installs a GRUB custom menuentry for a Mixtar test root. The default
workflow is plan-only. Install mode appends a marked block to /etc/grub.d/40_custom
and runs update-grub.
EOF
}

die() {
  printf '%s\n' "error: $*" >&2
  exit 1
}

command_name="${1:-help}"
root_label="${2:-}"
kernel_release="${3:-$(uname -r)}"
confirm_flag="${4:-}"

if [ "$command_name" = "install" ] && [ "$kernel_release" = "--write-grub" ]; then
  kernel_release="$(uname -r)"
  confirm_flag="--write-grub"
fi

case "$command_name" in
  plan|install|help) ;;
  *) usage; die "unknown command: $command_name" ;;
esac

if [ "$command_name" = "help" ]; then
  usage
  exit 0
fi

[ -n "$root_label" ] || die "missing root-label"

kernel="/boot/vmlinuz-$kernel_release"
initrd="/boot/initrd.img-$kernel_release"

[ -f "$kernel" ] || die "missing kernel: $kernel"
[ -f "$initrd" ] || die "missing initrd: $initrd"

root_cmd() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    command -v sudo >/dev/null 2>&1 || die "sudo is required for this step"
    sudo "$@"
  fi
}

find_tool() {
  if command -v "$1" >/dev/null 2>&1; then
    command -v "$1"
    return 0
  fi

  if [ -x "/usr/sbin/$1" ]; then
    printf '%s\n' "/usr/sbin/$1"
    return 0
  fi

  if [ -x "/sbin/$1" ]; then
    printf '%s\n' "/sbin/$1"
    return 0
  fi

  return 1
}

generate_block() {
  cat <<EOF
# BEGIN MIXTARRVS PRE-V0
menuentry 'MixtarRVS pre-v0 Alpine/OpenRC/zsh' {
    search --no-floppy --label --set=root $root_label
    linux $kernel root=LABEL=$root_label ro rootwait
    initrd $initrd
}

menuentry 'MixtarRVS pre-v0 rescue shell' {
    search --no-floppy --label --set=root $root_label
    linux $kernel root=LABEL=$root_label rw rootwait init=/bin/sh
    initrd $initrd
}
# END MIXTARRVS PRE-V0
EOF
}

if [ "$command_name" = "plan" ]; then
  cat <<EOF
# MixtarRVS temporary GRUB plan
#
# This is a plan only. Install mode writes a marked block to /etc/grub.d/40_custom
# and runs update-grub. Keep the Debian entries as rollback.

EOF
  generate_block
  exit 0
fi

if [ "$confirm_flag" != "--write-grub" ]; then
  generate_block
  die "install requires explicit --write-grub"
fi

custom_file="/etc/grub.d/40_custom"
tmp_file=$(mktemp "${TMPDIR:-/tmp}/mixtar-grub.XXXXXX")
block_file=$(mktemp "${TMPDIR:-/tmp}/mixtar-grub-block.XXXXXX")
trap 'rm -f "$tmp_file" "$block_file"' EXIT INT TERM

generate_block > "$block_file"

if [ -f "$custom_file" ]; then
  awk '
    $0 == "# BEGIN MIXTARRVS PRE-V0" { skip = 1; next }
    $0 == "# END MIXTARRVS PRE-V0" { skip = 0; next }
    skip != 1 { print }
  ' "$custom_file" > "$tmp_file"
else
  : > "$tmp_file"
fi

{
  cat "$tmp_file"
  printf '\n'
  cat "$block_file"
} > "$tmp_file.next"
mv "$tmp_file.next" "$tmp_file"

root_cmd cp "$custom_file" "$custom_file.mixtar-backup" 2>/dev/null || true
root_cmd cp "$tmp_file" "$custom_file"
root_cmd chmod 755 "$custom_file"

update_grub=$(find_tool update-grub || true)
grub_mkconfig=$(find_tool grub-mkconfig || true)

if [ -n "$update_grub" ]; then
  root_cmd "$update_grub"
elif [ -n "$grub_mkconfig" ]; then
  root_cmd "$grub_mkconfig" -o /boot/grub/grub.cfg
else
  die "missing update-grub or grub-mkconfig"
fi

printf '%s\n' "installed Mixtar GRUB block for LABEL=$root_label using $kernel_release"
