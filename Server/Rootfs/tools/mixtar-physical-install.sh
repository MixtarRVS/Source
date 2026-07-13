#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
usage:
  mixtar-physical-install.sh plan <manifest>
  mixtar-physical-install.sh install <manifest> --erase-device --write-grub

Plans or performs the physical pre-v0 Mixtar install. Install mode is
destructive and requires an exact interactive confirmation phrase:

  FORMAT <target-device> AS <root-label>

This script still delegates the actual work to mixtar-rebuild.sh gates:

  preinstall-gate
  install-rootfs --erase-device
  grub-install --write-grub

Install mode also generates a non-destructive approval packet before asking for
the confirmation phrase.
EOF
}

die() {
  printf '%s\n' "error: $*" >&2
  exit 1
}

root_cmd() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    command -v sudo >/dev/null 2>&1 || die "sudo is required for this step"
    sudo "$@"
  fi
}

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
rebuild_tool="$script_dir/mixtar-rebuild.sh"
approval_pack_tool="$script_dir/mixtar-install-approval-pack.sh"

command_name="${1:-help}"
manifest_path="${2:-}"
erase_flag="${3:-}"
grub_flag="${4:-}"
install_started=0
install_completed=0
audit_finalized=0

case "$command_name" in
  plan|install|help) ;;
  *) usage; die "unknown command: $command_name" ;;
esac

if [ "$command_name" = "help" ]; then
  usage
  exit 0
fi

[ -n "$manifest_path" ] || die "missing manifest"
[ -f "$manifest_path" ] || die "missing manifest: $manifest_path"
[ -f "$rebuild_tool" ] || die "missing rebuild tool: $rebuild_tool"

# shellcheck disable=SC1090
. "$manifest_path"

target_device="${MIXTAR_TARGET_DEVICE:-}"
root_label="${MIXTAR_ROOT_LABEL:-MIXTARROOT}"
kernel_release="${MIXTAR_KERNEL_RELEASE:-$(uname -r)}"

[ -n "$target_device" ] || die "MIXTAR_TARGET_DEVICE is required"

confirmation_phrase="FORMAT $target_device AS $root_label"
manifest_dir=$(CDPATH= cd -- "$(dirname -- "$manifest_path")" && pwd)
rootfs_dir=$(CDPATH= cd -- "$manifest_dir/.." && pwd)
audit_dir="$rootfs_dir/install-logs"
audit_file="$audit_dir/physical-install-$(date -u '+%Y%m%dT%H%M%SZ').log"
approval_packet=""

write_audit() {
  mkdir -p "$audit_dir" 2>/dev/null || root_cmd mkdir -p "$audit_dir"
  tmp_audit=$(mktemp "${TMPDIR:-/tmp}/mixtar-physical-audit.XXXXXX")
  {
    printf '%s\n' "timestamp_utc=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf '%s\n' "status=$1"
    printf '%s\n' "manifest=$manifest_path"
    printf '%s\n' "target_device=$target_device"
    printf '%s\n' "root_label=$root_label"
    printf '%s\n' "kernel_release=$kernel_release"
    if [ -n "$approval_packet" ]; then
      printf '%s\n' "approval_packet=$approval_packet"
    fi
    printf '%s\n' ""
  } > "$tmp_audit"

  if ! cat "$tmp_audit" >> "$audit_file" 2>/dev/null; then
    root_cmd sh -c "cat '$tmp_audit' >> '$audit_file'"
    root_cmd chown "$(id -u):$(id -g)" "$audit_file" 2>/dev/null || true
  fi

  rm -f "$tmp_audit"
}

cleanup_audit() {
  if [ "$install_started" = "1" ] && [ "$install_completed" != "1" ] && [ "$audit_finalized" != "1" ]; then
    write_audit "failed-or-interrupted"
    audit_finalized=1
  fi
}

on_interrupt() {
  cleanup_audit
  exit "$1"
}

trap cleanup_audit EXIT
trap 'on_interrupt 130' INT
trap 'on_interrupt 143' TERM

print_plan() {
  printf '%s\n' "Mixtar physical install plan"
  printf '%s\n' ""
  printf '%s\n' "Manifest: $manifest_path"
  printf '%s\n' "Target:   $target_device"
  printf '%s\n' "Label:    $root_label"
  printf '%s\n' "Kernel:   $kernel_release"
  printf '%s\n' ""
  printf '%s\n' "Non-destructive gate:"
  printf '%s\n' "  sh $rebuild_tool preinstall-gate '$manifest_path'"
  printf '%s\n' ""
  printf '%s\n' "Non-destructive approval packet:"
  printf '%s\n' "  sh $approval_pack_tool '$manifest_path'"
  printf '%s\n' ""
  printf '%s\n' "Destructive steps:"
  printf '%s\n' "  sh $rebuild_tool install-rootfs '$manifest_path' --erase-device"
  printf '%s\n' "  sh $rebuild_tool grub-install '$manifest_path' --write-grub"
  printf '%s\n' ""
  printf '%s\n' "Install mode command:"
  printf '%s\n' "  sh $0 install '$manifest_path' --erase-device --write-grub"
  printf '%s\n' ""
  printf '%s\n' "Required interactive confirmation phrase:"
  printf '%s\n' "  $confirmation_phrase"
}

if [ "$command_name" = "plan" ]; then
  print_plan
  exit 0
fi

[ "$erase_flag" = "--erase-device" ] || {
  print_plan
  die "install requires --erase-device"
}

[ "$grub_flag" = "--write-grub" ] || {
  print_plan
  die "install requires --write-grub"
}

[ -f "$approval_pack_tool" ] || die "missing approval packet tool: $approval_pack_tool"

approval_packet=$(sh "$approval_pack_tool" "$manifest_path")
write_audit "approval-packet-generated"

printf '%s\n' "About to run destructive Mixtar physical install."
printf '%s\n' "Target: $target_device"
printf '%s\n' "Label:  $root_label"
printf '%s\n' "Approval packet: $approval_packet"
printf '%s\n' ""
printf '%s\n' "Type the exact phrase to continue:"
printf '%s\n' "$confirmation_phrase"
printf '%s' "> "

IFS= read -r typed_phrase || die "confirmation input failed"

if [ "$typed_phrase" != "$confirmation_phrase" ]; then
  write_audit "confirmation-rejected"
  die "confirmation phrase did not match"
fi

install_started=1
write_audit "started"

sh "$rebuild_tool" preinstall-gate "$manifest_path"
sh "$rebuild_tool" install-rootfs "$manifest_path" --erase-device
sh "$rebuild_tool" grub-install "$manifest_path" --write-grub

install_completed=1
write_audit "completed"
audit_finalized=1

printf '%s\n' "Mixtar physical install completed. Reboot and choose the MixtarRVS GRUB entry."
printf '%s\n' "audit log: $audit_file"
