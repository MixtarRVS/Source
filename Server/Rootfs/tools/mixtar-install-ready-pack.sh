#!/bin/sh
set -eu

usage() {
  cat <<'USAGE'
Usage:
  mixtar-install-ready-pack.sh <manifest>

Purpose:
  Generate a non-destructive install-ready packet after preinstall-gate passes.

This script does not approve installation.
This script does not format the target partition.
This script does not write GRUB.
USAGE
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

sha256_or_missing() {
  path="$1"
  if [ -f "$path" ]; then
    sha256sum "$path" | awk '{ print $1 }'
  else
    printf '%s' "missing"
  fi
}

canonical_path() {
  input_path="$1"
  case "$input_path" in
    /*)
      printf '%s\n' "$input_path"
      ;;
    *)
      input_dir=$(dirname -- "$input_path")
      input_base=$(basename -- "$input_path")
      [ -d "$input_dir" ] || die "missing directory: $input_dir"
      printf '%s/%s\n' "$(CDPATH= cd -- "$input_dir" && pwd)" "$input_base"
      ;;
  esac
}

if [ "${1:-}" = "" ] || [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

manifest=$(canonical_path "$1")
[ -f "$manifest" ] || die "missing manifest: $manifest"

# shellcheck disable=SC1090
. "$manifest"

target_device="${MIXTAR_TARGET_DEVICE:-}"
root_label="${MIXTAR_ROOT_LABEL:-MIXTARROOT}"
kernel_release="${MIXTAR_KERNEL_RELEASE:-unknown}"
image_path="${MIXTAR_IMAGE_PATH:-}"
system_name="${MIXTAR_SYSTEM_NAME:-mixtar-pre-v0}"

[ -n "$target_device" ] || die "MIXTAR_TARGET_DEVICE is empty"
[ -n "$image_path" ] || die "MIXTAR_IMAGE_PATH is empty"

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
rebuild="$script_dir/mixtar-rebuild.sh"
manifest_dir=$(CDPATH= cd -- "$(dirname -- "$manifest")" && pwd)
rootfs_dir=$(CDPATH= cd -- "$manifest_dir/.." && pwd)
packet_dir="$rootfs_dir/install-logs"
approval_dir="$manifest_dir/approval-packets"
timestamp=$(date -u '+%Y%m%dT%H%M%SZ')
packet="$packet_dir/mixtar-install-ready-$timestamp.md"
phrase="FORMAT $target_device AS $root_label"

approval_packet="missing"
if [ -d "$approval_dir" ]; then
  latest_approval=$(ls -t "$approval_dir"/physical-install-*.md 2>/dev/null | head -n 1 || true)
  if [ -n "$latest_approval" ]; then
    approval_packet="$latest_approval"
  fi
fi

mkdir -p "$packet_dir" 2>/dev/null || root_cmd mkdir -p "$packet_dir"
tmp_packet=$(mktemp "${TMPDIR:-/tmp}/mixtar-install-ready.XXXXXX")
trap 'rm -f "$tmp_packet"' EXIT INT TERM

manifest_sha=$(sha256_or_missing "$manifest")
image_sha=$(sha256_or_missing "$image_path")

{
  printf '%s\n' '# MixtarRVS install-ready packet'
  printf '\n%s\n' "Generated: $timestamp"
  printf '%s\n' "System: $system_name"
  printf '\n%s\n' 'This packet records non-destructive readiness evidence only.'
  printf '%s\n' 'It does not approve installation.'
  printf '%s\n' 'It does not format the target partition.'
  printf '%s\n' 'It does not write GRUB.'
  printf '\n%s\n' '## Current evidence'
  printf '\n%s\n' '```text'
  printf '%s\n' 'preinstall_gate=passed'
  printf '%s\n' "target_device=$target_device"
  printf '%s\n' "root_label=$root_label"
  printf '%s\n' "kernel_release=$kernel_release"
  printf '%s\n' "manifest=$manifest"
  printf '%s\n' "manifest_sha256=$manifest_sha"
  printf '%s\n' "image_path=$image_path"
  printf '%s\n' "image_sha256=$image_sha"
  printf '%s\n' "approval_packet=$approval_packet"
  printf '%s\n' '```'
  printf '\n%s\n' '## Required exact confirmation phrase'
  printf '\n%s\n' '```text'
  printf '%s\n' "$phrase"
  printf '%s\n' '```'
  printf '\n%s\n' '## Destructive command after approval only'
  printf '\n%s\n' '```sh'
  printf '%s\n' "sh $rebuild physical-install '$manifest' --erase-device --write-grub"
  printf '%s\n' '```'
} > "$tmp_packet"

if ! cp "$tmp_packet" "$packet" 2>/dev/null; then
  root_cmd cp "$tmp_packet" "$packet"
  root_cmd chown "$(id -u):$(id -g)" "$packet" 2>/dev/null || true
fi

printf '%s\n' "$packet"
