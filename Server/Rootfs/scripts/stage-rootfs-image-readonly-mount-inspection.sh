#!/bin/sh
set -u

STAGE=0017-rootfs-image-readonly-mount-inspection
BASE=/System/Base/Closure/$STAGE
SYSTEM_TOOL=/System/SystemTools/mixtar-rootfs-image
RUNNER_NAME=mixtar-rootfs-image.sh
MOUNT_POINT=/System/Runtime/Inspect/rootfs-0015

script_dir() {
	dir=$(dirname "$0")
	cd "$dir" 2>/dev/null && pwd
}

runner_source() {
	dir=$(script_dir)
	if [ -f "$dir/$RUNNER_NAME" ]; then
		printf '%s/%s\n' "$dir" "$RUNNER_NAME"
		return 0
	fi
	if [ -f "/tmp/$RUNNER_NAME" ]; then
		printf '/tmp/%s\n' "$RUNNER_NAME"
		return 0
	fi
	return 1
}

is_mounted() {
	awk -v mount_point="$MOUNT_POINT" '$2 == mount_point { found = 1 } END { exit found ? 0 : 1 }' /proc/mounts 2>/dev/null
}

write_contract() {
	cat <<EOF
MixtarRVS rootfs image read-only mount inspection, stage 0017

Command:
  mixtar-rootfs-image mount-inspect --once

Mount point:
  $MOUNT_POINT

This stage:
  mounts rootfs.squashfs read-only for inspection
  verifies mounted paths
  unmounts before finishing

This stage does not:
  mount the image as root
  switch /System/Current
  rebuild initramfs
  change bootloader state
  leave the image mounted
EOF
}

verify() {
	rc=0
	if ! grep -F 'mount_status=mounted' "$BASE/rootfs-image-mount-inspect.txt" >/dev/null 2>&1; then
		printf 'verify: mount did not record mounted status\n' >&2
		rc=1
	fi
	if ! grep -F 'mounted_self_include=absent' "$BASE/rootfs-image-mount-inspect.txt" >/dev/null 2>&1; then
		printf 'verify: self include not absent\n' >&2
		rc=1
	fi
	if ! grep -F 'unmount_status=unmounted' "$BASE/rootfs-image-mount-inspect.txt" >/dev/null 2>&1; then
		printf 'verify: unmount did not succeed\n' >&2
		rc=1
	fi
	if ! grep -F 'mount_after=absent' "$BASE/rootfs-image-mount-inspect.txt" >/dev/null 2>&1; then
		printf 'verify: mount still present after inspection\n' >&2
		rc=1
	fi
	if ! grep -F 'mount_inspect_result=ok' "$BASE/rootfs-image-mount-inspect.txt" >/dev/null 2>&1; then
		printf 'verify: mount inspect did not report ok\n' >&2
		rc=1
	fi
	if is_mounted; then
		printf 'verify: mountpoint still mounted: %s\n' "$MOUNT_POINT" >&2
		rc=1
	fi
	before=$(cat "$BASE/system-current-before.txt" 2>/dev/null || true)
	after=$(readlink /System/Current 2>/dev/null || true)
	if [ "$before" != "$after" ]; then
		printf 'verify: /System/Current changed from %s to %s\n' "$before" "$after" >&2
		rc=1
	fi
	return "$rc"
}

stage() {
	runner=$(runner_source) || {
		printf 'stage: missing %s next to this script or in /tmp\n' "$RUNNER_NAME" >&2
		return 1
	}
	install -d -m 0755 "$BASE" /System/SystemTools
	readlink /System/Current 2>/dev/null > "$BASE/system-current-before.txt" || true
	if is_mounted; then
		printf 'stage: mountpoint already mounted before inspection: %s\n' "$MOUNT_POINT" >&2
		return 1
	fi
	install -m 0755 "$runner" "$SYSTEM_TOOL"
	write_contract > "$BASE/rootfs-image-readonly-mount-inspection-contract.txt"
	"$SYSTEM_TOOL" mount-plan > "$BASE/rootfs-image-mount-plan-before.txt" 2>&1 || true
	"$SYSTEM_TOOL" mount-inspect --once > "$BASE/rootfs-image-mount-inspect.txt" 2>&1
	if verify; then
		printf 'verified\n' > "$BASE/rootfs-image-readonly-mount-inspection-status.txt"
	else
		printf 'incomplete\n' > "$BASE/rootfs-image-readonly-mount-inspection-status.txt"
		return 1
	fi
}

mode=${1:-}
if [ -z "$mode" ]; then
	mode=--verify
fi

case "$mode" in
	--verify)
		verify
		;;
	--contract)
		write_contract
		;;
	--stage)
		stage
		;;
	*)
		printf 'usage: %s [--verify|--contract|--stage]\n' "$0" >&2
		exit 2
		;;
esac
