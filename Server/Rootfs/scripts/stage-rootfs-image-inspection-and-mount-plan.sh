#!/bin/sh
set -u

STAGE=0016-rootfs-image-inspection-and-mount-plan
BASE=/System/Base/Closure/$STAGE
SYSTEM_TOOL=/System/SystemTools/mixtar-rootfs-image
RUNNER_NAME=mixtar-rootfs-image.sh
IMAGE=/System/Generations/0015-rootfs-image-first-file/rootfs.squashfs

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

write_contract() {
	cat <<EOF
MixtarRVS rootfs image inspection and mount plan, stage 0016

Image:
  $IMAGE

Commands:
  mixtar-rootfs-image inspect
  mixtar-rootfs-image contents-check
  mixtar-rootfs-image mount-plan

This stage is non-activating:
  image is not mounted
  image is not mounted as root
  /System/Current is not switched
  initramfs is not rebuilt
  bootloader state is not changed
EOF
}

verify() {
	rc=0
	if [ ! -s "$IMAGE" ]; then
		printf 'verify: missing image %s\n' "$IMAGE" >&2
		rc=1
	fi
	if ! "$SYSTEM_TOOL" inspect >/dev/null 2>&1; then
		printf 'verify: inspect failed\n' >&2
		rc=1
	fi
	if ! "$SYSTEM_TOOL" contents-check > "$BASE/rootfs-image-contents-check.txt" 2>&1; then
		printf 'verify: contents-check failed\n' >&2
		rc=1
	fi
	if ! "$SYSTEM_TOOL" mount-plan > "$BASE/rootfs-image-mount-plan.txt" 2>&1; then
		printf 'verify: mount-plan failed\n' >&2
		rc=1
	fi
	for token in \
		'contents_check=ok' \
		'self_include=absent'
	do
		if ! grep -F "$token" "$BASE/rootfs-image-contents-check.txt" >/dev/null 2>&1; then
			printf 'verify: contents check missing token: %s\n' "$token" >&2
			rc=1
		fi
	done
	for token in \
		'mount_plan=inspect-only' \
		'would_mount=false' \
		'activation=none'
	do
		if ! grep -F "$token" "$BASE/rootfs-image-mount-plan.txt" >/dev/null 2>&1; then
			printf 'verify: mount plan missing token: %s\n' "$token" >&2
			rc=1
		fi
	done
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
	install -m 0755 "$runner" "$SYSTEM_TOOL"
	write_contract > "$BASE/rootfs-image-inspection-contract.txt"
	"$SYSTEM_TOOL" inspect > "$BASE/rootfs-image-inspect.txt" 2>&1 || true
	"$SYSTEM_TOOL" contents-check > "$BASE/rootfs-image-contents-check.txt" 2>&1 || true
	"$SYSTEM_TOOL" mount-plan > "$BASE/rootfs-image-mount-plan.txt" 2>&1 || true
	if verify; then
		printf 'verified\n' > "$BASE/rootfs-image-inspection-status.txt"
	else
		printf 'incomplete\n' > "$BASE/rootfs-image-inspection-status.txt"
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
