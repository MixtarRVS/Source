#!/bin/sh
set -u

STAGE=0015-rootfs-image-build-first-file-no-activation
BASE=/System/Base/Closure/$STAGE
SYSTEM_TOOL=/System/SystemTools/mixtar-rootfs-image
RUNNER_NAME=mixtar-rootfs-image.sh
TARGET_DIR=/System/Generations/0015-rootfs-image-first-file
TARGET_IMAGE=$TARGET_DIR/rootfs.squashfs

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
MixtarRVS rootfs image first-file build, stage 0015

Target:
  $TARGET_IMAGE

Allowed mutation:
  create $TARGET_DIR and rootfs.squashfs

No activation:
  /System/Current is not switched
  /System/Previous is not rewritten
  initramfs is not rebuilt
  bootloader state is not changed
  generated image is not mounted as root
EOF
}

verify() {
	rc=0
	if [ ! -s "$TARGET_IMAGE" ]; then
		printf 'verify: missing or empty image %s\n' "$TARGET_IMAGE" >&2
		rc=1
	fi
	if ! unsquashfs -s "$TARGET_IMAGE" > "$BASE/unsquashfs-summary-verify.txt" 2>&1; then
		printf 'verify: unsquashfs summary failed\n' >&2
		rc=1
	fi
	if [ ! -f "$TARGET_DIR/manifest.json" ]; then
		printf 'verify: missing target manifest\n' >&2
		rc=1
	fi
	if [ ! -f "$TARGET_DIR/activation.plan" ]; then
		printf 'verify: missing activation plan\n' >&2
		rc=1
	elif ! grep -F 'activation=none' "$TARGET_DIR/activation.plan" >/dev/null 2>&1; then
		printf 'verify: activation plan is not none\n' >&2
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
	install -m 0755 "$runner" "$SYSTEM_TOOL"
	write_contract > "$BASE/rootfs-image-build-first-file-contract.txt"
	"$SYSTEM_TOOL" check > "$BASE/rootfs-image-check.txt" 2>&1 || true
	"$SYSTEM_TOOL" build --dry-run > "$BASE/rootfs-image-build-dry-run-before.txt" 2>&1 || true
	"$SYSTEM_TOOL" build --first-file > "$BASE/rootfs-image-build-first-file.txt" 2>&1
	sha256sum "$TARGET_IMAGE" > "$BASE/rootfs-image.sha256" 2>&1 || true
	wc -c "$TARGET_IMAGE" > "$BASE/rootfs-image.size" 2>&1 || true
	unsquashfs -s "$TARGET_IMAGE" > "$BASE/unsquashfs-summary.txt" 2>&1 || true
	cp "$TARGET_DIR/manifest.json" "$BASE/generation-manifest.json" 2>/dev/null || true
	cp "$TARGET_DIR/activation.plan" "$BASE/activation.plan" 2>/dev/null || true
	if verify; then
		printf 'verified\n' > "$BASE/rootfs-image-build-first-file-status.txt"
	else
		printf 'incomplete\n' > "$BASE/rootfs-image-build-first-file-status.txt"
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
