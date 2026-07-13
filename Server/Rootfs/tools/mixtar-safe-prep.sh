#!/bin/sh
set -eu

usage() {
  cat <<'USAGE'
Usage:
  mixtar-safe-prep.sh <manifest> [--with-preinstall-gate]

Purpose:
  Run the non-destructive preparation path for a MixtarRVS pre-v0 image.

This script may rebuild the rootfs artifact and overwrite the configured image
file when install-image uses --erase-image. It must not format the target block
device and must not write GRUB.

Default sequence:
  build
  image-plan
  install-image --erase-image
  image-verify
  readiness-report
  operator-runbook
  physical-plan
  grub-rollback-plan

Optional:
  --with-preinstall-gate also runs preinstall-gate.

Not included:
  physical-install
  install-rootfs --erase-device
  grub-install --write-grub
USAGE
}

die() {
  printf '%s\n' "error: $*" >&2
  exit 1
}

run_step() {
  name="$1"
  shift
  printf '\n==> %s\n' "$name"
  "$@"
}

if [ "${1:-}" = "" ] || [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

manifest="$1"
shift

with_preinstall_gate=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --with-preinstall-gate)
      with_preinstall_gate=1
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
  shift
done

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
rebuild="$script_dir/mixtar-rebuild.sh"
approval_pack="$script_dir/mixtar-install-approval-pack.sh"

[ -f "$rebuild" ] || die "missing rebuild script: $rebuild"
[ -f "$approval_pack" ] || die "missing approval packet script: $approval_pack"
[ -f "$manifest" ] || die "missing manifest: $manifest"

printf '%s\n' "MixtarRVS safe preparation"
printf '%s\n' "manifest=$manifest"
printf '%s\n' "physical_install=not-run"
printf '%s\n' "grub_write=not-run"
printf '%s\n' "target_format=not-run"
printf '%s\n' ""
printf '%s\n' "This script is non-destructive toward the target partition."
printf '%s\n' "It may refresh the configured image file only."

run_step "build rootfs artifact" sh "$rebuild" build "$manifest"
run_step "show image plan" sh "$rebuild" image-plan "$manifest"
run_step "refresh ext4 image file" sh "$rebuild" install-image "$manifest" --erase-image
run_step "verify ext4 image file" sh "$rebuild" image-verify "$manifest"
run_step "readiness report" sh "$rebuild" readiness-report "$manifest"
run_step "operator runbook" sh "$rebuild" operator-runbook "$manifest"
run_step "physical install plan only" sh "$rebuild" physical-plan "$manifest"
run_step "GRUB rollback plan only" sh "$rebuild" grub-rollback-plan "$manifest"
run_step "generate install approval packet" sh "$rebuild" approval-pack "$manifest"

if [ "$with_preinstall_gate" -eq 1 ]; then
  run_step "preinstall gate" sh "$rebuild" preinstall-gate "$manifest"
else
  printf '\n%s\n' "preinstall-gate=skipped"
  printf '%s\n' "Run again with --with-preinstall-gate when ready to inspect live target state."
fi

printf '\n%s\n' "safe-prep=complete"
printf '%s\n' "install_approval=missing"
printf '%s\n' "No physical install was run."
