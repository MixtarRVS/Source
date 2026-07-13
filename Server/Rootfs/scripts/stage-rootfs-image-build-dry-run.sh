#!/bin/sh
set -u

STAGE=0014-rootfs-image-build-dry-run
BASE=/System/Base/Closure/$STAGE
SYSTEM_TOOL=/System/SystemTools/mixtar-rootfs-image
RUNNER_NAME=mixtar-rootfs-image.sh
TARGET_DIR=/System/Generations/0014-rootfs-image-preview

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
MixtarRVS rootfs image build dry-run, stage 0014

Installed interface:
  /System/SystemTools/mixtar-rootfs-image

New command:
  mixtar-rootfs-image build --dry-run

Planned target:
  $TARGET_DIR/rootfs.squashfs

Dry-run guarantees:
  rootfs.squashfs is not created
  target generation directory is not created
  mksquashfs is not run
  initramfs is not rebuilt
  /System/Current is not switched
  bootloader state is not changed
EOF
}

audit() {
	printf '## stage\n'
	printf 'STAGE=%s\n' "$STAGE"
	printf 'BASE=%s\n' "$BASE"

	printf '\n## check\n'
	"$SYSTEM_TOOL" check 2>&1 || true

	printf '\n## readiness\n'
	"$SYSTEM_TOOL" readiness 2>&1 || true

	printf '\n## build_dry_run\n'
	"$SYSTEM_TOOL" build --dry-run 2>&1 || true
}

verify() {
	rc=0
	if [ ! -x "$SYSTEM_TOOL" ]; then
		printf 'verify: missing runner %s\n' "$SYSTEM_TOOL" >&2
		rc=1
	fi
	if [ -e "$TARGET_DIR" ]; then
		printf 'verify: target dir was created: %s\n' "$TARGET_DIR" >&2
		rc=1
	fi
	if ! "$SYSTEM_TOOL" check >/dev/null 2>&1; then
		printf 'verify: rootfs image check failed\n' >&2
		rc=1
	fi
	if ! "$SYSTEM_TOOL" build --dry-run >/dev/null 2>&1; then
		printf 'verify: build dry-run failed\n' >&2
		rc=1
	fi
	for token in \
		'plan=rootfs-image-build' \
		'mode=dry-run' \
		'would_create_rootfs_image=false' \
		'would_create_generation=false' \
		'would_create_target_dir=false' \
		'would_run_mksquashfs=false' \
		'would_switch_current=false' \
		'target_generation_dir=/System/Generations/0014-rootfs-image-preview' \
		'target_image=/System/Generations/0014-rootfs-image-preview/rootfs.squashfs' \
		'mksquashfs_command=mksquashfs / /System/Generations/0014-rootfs-image-preview/rootfs.squashfs' \
		'builder_ready=true' \
		'dry_run_result=plan-generated'
	do
		if ! grep -F "$token" "$BASE/rootfs-image-build-dry-run.txt" >/dev/null 2>&1; then
			printf 'verify: dry-run output missing token: %s\n' "$token" >&2
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
	write_contract > "$BASE/rootfs-image-build-dry-run-contract.txt"
	"$SYSTEM_TOOL" check > "$BASE/rootfs-image-check.txt" 2>&1 || true
	"$SYSTEM_TOOL" readiness > "$BASE/rootfs-image-readiness.txt" 2>&1 || true
	"$SYSTEM_TOOL" build --dry-run > "$BASE/rootfs-image-build-dry-run.txt" 2>&1 || true
	audit > "$BASE/rootfs-image-build-dry-run-audit.txt"
	if verify; then
		printf 'verified\n' > "$BASE/rootfs-image-build-dry-run-status.txt"
	else
		printf 'incomplete\n' > "$BASE/rootfs-image-build-dry-run-status.txt"
		return 1
	fi
}

mode=${1:-}
if [ -z "$mode" ]; then
	mode=--audit
fi

case "$mode" in
	--audit)
		audit
		;;
	--contract)
		write_contract
		;;
	--verify)
		verify
		;;
	--stage)
		stage
		;;
	*)
		printf 'usage: %s [--audit|--contract|--verify|--stage]\n' "$0" >&2
		exit 2
		;;
esac
