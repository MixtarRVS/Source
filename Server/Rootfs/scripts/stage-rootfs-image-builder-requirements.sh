#!/bin/sh
set -u

STAGE=0012-rootfs-image-builder-requirements
BASE=/System/Base/Closure/$STAGE
SYSTEM_TOOL=/System/SystemTools/mixtar-rootfs-image
IMAGE_DIR=/System/Config/ImageBuilder
RUNNER_NAME=mixtar-rootfs-image.sh
PROFILE_NAME=rootfs-image.requirements

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

profile_source() {
	dir=$(script_dir)
	if [ -f "$dir/$PROFILE_NAME" ]; then
		printf '%s/%s\n' "$dir" "$PROFILE_NAME"
		return 0
	fi
	if [ -f "/tmp/mixtar-image-profiles/$PROFILE_NAME" ]; then
		printf '/tmp/mixtar-image-profiles/%s\n' "$PROFILE_NAME"
		return 0
	fi
	return 1
}

write_contract() {
	cat <<EOF
MixtarRVS rootfs image builder requirements, stage 0012

Installed interface:
  /System/SystemTools/mixtar-rootfs-image

Installed profile:
  /System/Config/ImageBuilder/rootfs-image.requirements

Commands:
  mixtar-rootfs-image contract
  mixtar-rootfs-image check
  mixtar-rootfs-image requirements
  mixtar-rootfs-image inputs
  mixtar-rootfs-image exclusions
  mixtar-rootfs-image plan
  mixtar-rootfs-image backend
  mixtar-rootfs-image readiness

This stage is non-activating:
  rootfs.squashfs is not created
  no generation directory is created
  filesystems are not mounted
  mksquashfs is not run
  initramfs is not rebuilt
  bootloader state is not changed
  /System/Current is not switched
EOF
}

audit() {
	printf '## stage\n'
	printf 'STAGE=%s\n' "$STAGE"
	printf 'BASE=%s\n' "$BASE"

	printf '\n## runner\n'
	if [ -x "$SYSTEM_TOOL" ]; then
		ls -l "$SYSTEM_TOOL"
	else
		printf 'missing %s\n' "$SYSTEM_TOOL"
	fi

	printf '\n## check\n'
	"$SYSTEM_TOOL" check 2>&1 || true

	printf '\n## plan\n'
	"$SYSTEM_TOOL" plan 2>&1 || true

	printf '\n## backend\n'
	"$SYSTEM_TOOL" backend 2>&1 || true

	printf '\n## readiness\n'
	"$SYSTEM_TOOL" readiness 2>&1 || true
}

verify() {
	rc=0
	if [ ! -x "$SYSTEM_TOOL" ]; then
		printf 'verify: missing runner %s\n' "$SYSTEM_TOOL" >&2
		rc=1
	fi
	if [ ! -f "$IMAGE_DIR/$PROFILE_NAME" ]; then
		printf 'verify: missing profile %s/%s\n' "$IMAGE_DIR" "$PROFILE_NAME" >&2
		rc=1
	fi
	if ! "$SYSTEM_TOOL" check >/dev/null 2>&1; then
		printf 'verify: rootfs image requirements check failed\n' >&2
		rc=1
	fi
	for token in \
		'plan=rootfs-image-build-requirements' \
		'mode=requirements-only' \
		'would_create_rootfs_image=false' \
		'would_create_generation=false' \
		'would_run_mksquashfs=false' \
		'would_switch_current=false' \
		'format=squashfs' \
		'required_builder=mksquashfs' \
		'activation_policy=stage-only-first' \
		'rollback_policy=preserve-current-and-previous-until-boot-tested'
	do
		if ! grep -F "$token" "$BASE/rootfs-image-plan.txt" >/dev/null 2>&1; then
			printf 'verify: plan output missing token: %s\n' "$token" >&2
			rc=1
		fi
	done
	if ! grep -F 'mksquashfs=missing' "$BASE/rootfs-image-backend.txt" >/dev/null 2>&1; then
		printf 'verify: backend did not record missing mksquashfs\n' >&2
		rc=1
	fi
	if ! grep -F 'builder_ready=false' "$BASE/rootfs-image-readiness.txt" >/dev/null 2>&1; then
		printf 'verify: readiness did not record builder_ready=false\n' >&2
		rc=1
	fi
	return "$rc"
}

stage() {
	runner=$(runner_source) || {
		printf 'stage: missing %s next to this script or in /tmp\n' "$RUNNER_NAME" >&2
		return 1
	}
	profile=$(profile_source) || {
		printf 'stage: missing %s next to this script or in /tmp/mixtar-image-profiles\n' "$PROFILE_NAME" >&2
		return 1
	}
	install -d -m 0755 "$BASE" /System/SystemTools "$IMAGE_DIR"
	install -m 0755 "$runner" "$SYSTEM_TOOL"
	install -m 0644 "$profile" "$IMAGE_DIR/$PROFILE_NAME"
	write_contract > "$BASE/rootfs-image-requirements-contract.txt"
	"$SYSTEM_TOOL" check > "$BASE/rootfs-image-check.txt" 2>&1 || true
	"$SYSTEM_TOOL" requirements > "$BASE/rootfs-image-requirements.txt" 2>&1 || true
	"$SYSTEM_TOOL" inputs > "$BASE/rootfs-image-inputs.txt" 2>&1 || true
	"$SYSTEM_TOOL" exclusions > "$BASE/rootfs-image-exclusions.txt" 2>&1 || true
	"$SYSTEM_TOOL" plan > "$BASE/rootfs-image-plan.txt" 2>&1 || true
	"$SYSTEM_TOOL" backend > "$BASE/rootfs-image-backend.txt" 2>&1 || true
	"$SYSTEM_TOOL" readiness > "$BASE/rootfs-image-readiness.txt" 2>&1 || true
	audit > "$BASE/rootfs-image-audit.txt"
	if verify; then
		printf 'verified\n' > "$BASE/rootfs-image-requirements-status.txt"
	else
		printf 'incomplete\n' > "$BASE/rootfs-image-requirements-status.txt"
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
