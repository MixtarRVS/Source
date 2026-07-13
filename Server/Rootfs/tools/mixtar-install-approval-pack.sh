#!/bin/sh
set -eu

usage() {
  cat <<'USAGE'
Usage:
  mixtar-install-approval-pack.sh <manifest>

Purpose:
  Generate a non-destructive physical-install approval packet.

The packet records target device, root label, kernel release, image path,
checksums when available, the required confirmation phrase, and the exact
destructive command.

This script does not approve, format, install, or write GRUB.
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

if [ "${1:-}" = "" ] || [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

manifest="$1"
case "$manifest" in
  /*) ;;
  *)
    manifest_dir=$(dirname -- "$manifest")
    manifest_base=$(basename -- "$manifest")
    if [ -d "$manifest_dir" ]; then
      manifest="$(CDPATH= cd -- "$manifest_dir" && pwd)/$manifest_base"
    fi
    ;;
esac
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
packet_dir="$manifest_dir/approval-packets"
timestamp=$(date -u '+%Y%m%dT%H%M%SZ')
packet="$packet_dir/physical-install-$timestamp.md"
phrase="FORMAT $target_device AS $root_label"

mkdir -p "$packet_dir" 2>/dev/null || root_cmd mkdir -p "$packet_dir"
tmp_packet=$(mktemp "${TMPDIR:-/tmp}/mixtar-approval.XXXXXX")
trap 'rm -f "$tmp_packet"' EXIT INT TERM

manifest_sha=$(sha256_or_missing "$manifest")
image_sha=$(sha256_or_missing "$image_path")

cat > "$tmp_packet" <<PACKET
# MixtarRVS physical install approval packet

Generated: $timestamp
System: $system_name

This packet is non-destructive evidence for a later decision.

It does not approve installation.
It does not format the target partition.
It does not write GRUB.

## Target

\`\`\`text
target_device=$target_device
root_label=$root_label
kernel_release=$kernel_release
manifest=$manifest
image_path=$image_path
\`\`\`

## Checksums

\`\`\`text
manifest_sha256=$manifest_sha
image_sha256=$image_sha
\`\`\`

## Required confirmation phrase

\`\`\`text
$phrase
\`\`\`

## Destructive command

Run only after explicit approval:

\`\`\`sh
sh $rebuild physical-install '$manifest' --erase-device --write-grub
\`\`\`

## Expected destructive effects

\`\`\`text
$target_device is formatted
Mixtar rootfs is installed on $target_device
GRUB receives Mixtar boot entries
Debian remains the rollback boot path
\`\`\`

## Approval status

\`\`\`text
install_approval=missing
\`\`\`
PACKET

if ! cp "$tmp_packet" "$packet" 2>/dev/null; then
  root_cmd cp "$tmp_packet" "$packet"
  root_cmd chown "$(id -u):$(id -g)" "$packet" 2>/dev/null || true
fi

printf '%s\n' "$packet"
