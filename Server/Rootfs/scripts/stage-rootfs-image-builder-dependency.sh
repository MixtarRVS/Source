#!/bin/sh
set -u

STAGE=0013-rootfs-image-builder-dependency-stage
BASE=/System/Base/Closure/$STAGE
IMAGE_DIR=/System/Config/ImageBuilder
PROFILE_NAME=rootfs-image.requirements
PACKAGE=squashfs-tools

script_dir() {
	dir=$(dirname "$0")
	cd "$dir" 2>/dev/null && pwd
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

package_count() {
	apk info 2>/dev/null | awk 'END { print NR + 0 }'
}

world_count() {
	awk 'NF > 0 { count++ } END { print count + 0 }' /etc/apk/world 2>/dev/null
}

write_contract() {
	cat <<EOF
MixtarRVS rootfs image builder dependency stage, 0013

Dependency:
  package backend: apk
  package: $PACKAGE
  expected tools: mksquashfs, unsquashfs

Allowed mutations:
  apk may install $PACKAGE
  /etc/apk/world may gain $PACKAGE
  /System/Config/ImageBuilder/rootfs-image.requirements may record builder_status=staged-apk-backend

Non-goals:
  rootfs.squashfs is not created
  no generation directory is created
  /System/Current is not switched
  initramfs is not rebuilt
  bootloader state is not changed
  no package removal or apk upgrade is performed
EOF
}

audit_state() {
	label=$1
	printf '## %s\n' "$label"
	printf 'package_count='
	package_count
	printf 'world_count='
	world_count
	printf 'world_has_squashfs_tools='
	if grep -qx "$PACKAGE" /etc/apk/world 2>/dev/null; then
		printf 'true\n'
	else
		printf 'false\n'
	fi
	printf 'mksquashfs='
	path=$(command -v mksquashfs 2>/dev/null || true)
	printf '%s\n' "$path"
	printf 'unsquashfs='
	path=$(command -v unsquashfs 2>/dev/null || true)
	printf '%s\n' "$path"
	printf 'current_target='
	readlink /System/Current 2>/dev/null || true
}

install_dependency() {
	if command -v mksquashfs >/dev/null 2>&1 && command -v unsquashfs >/dev/null 2>&1; then
		printf 'dependency already present\n'
		return 0
	fi
	apk add "$PACKAGE"
}

verify() {
	rc=0
	if ! command -v mksquashfs >/dev/null 2>&1; then
		printf 'verify: missing mksquashfs\n' >&2
		rc=1
	fi
	if ! command -v unsquashfs >/dev/null 2>&1; then
		printf 'verify: missing unsquashfs\n' >&2
		rc=1
	fi
	if ! apk info -e "$PACKAGE" >/dev/null 2>&1; then
		printf 'verify: package not installed: %s\n' "$PACKAGE" >&2
		rc=1
	fi
	if ! /System/SystemTools/mixtar-rootfs-image check >/dev/null 2>&1; then
		printf 'verify: rootfs image check failed\n' >&2
		rc=1
	fi
	if ! /System/SystemTools/mixtar-rootfs-image readiness > "$BASE/rootfs-image-readiness-after.txt" 2>&1; then
		printf 'verify: rootfs readiness still reports incomplete\n' >&2
		rc=1
	fi
	if ! grep -F 'builder_ready=true' "$BASE/rootfs-image-readiness-after.txt" >/dev/null 2>&1; then
		printf 'verify: builder_ready=true not recorded\n' >&2
		rc=1
	fi
	if ! /System/SystemTools/mixtar-generation build --dry-run > "$BASE/generation-build-dry-run-after.txt" 2>&1; then
		printf 'verify: generation dry-run failed\n' >&2
		rc=1
	fi
	for token in 'would_create_generation=false' 'would_activate_generation=false' 'dry_run_result=plan-generated'; do
		if ! grep -F "$token" "$BASE/generation-build-dry-run-after.txt" >/dev/null 2>&1; then
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
	profile=$(profile_source) || {
		printf 'stage: missing %s next to this script or in /tmp/mixtar-image-profiles\n' "$PROFILE_NAME" >&2
		return 1
	}
	install -d -m 0755 "$BASE" "$IMAGE_DIR"
	readlink /System/Current 2>/dev/null > "$BASE/system-current-before.txt" || true
	write_contract > "$BASE/rootfs-image-builder-dependency-contract.txt"
	audit_state before > "$BASE/dependency-before.txt"
	install_dependency > "$BASE/apk-install-squashfs-tools.txt" 2>&1
	install -m 0644 "$profile" "$IMAGE_DIR/$PROFILE_NAME"
	audit_state after > "$BASE/dependency-after.txt"
	/System/SystemTools/mixtar-rootfs-image backend > "$BASE/rootfs-image-backend-after.txt" 2>&1 || true
	/System/SystemTools/mixtar-rootfs-image readiness > "$BASE/rootfs-image-readiness-after.txt" 2>&1 || true
	if verify; then
		printf 'verified\n' > "$BASE/rootfs-image-builder-dependency-status.txt"
	else
		printf 'incomplete\n' > "$BASE/rootfs-image-builder-dependency-status.txt"
		return 1
	fi
}

mode=${1:-}
if [ -z "$mode" ]; then
	mode=--audit
fi

case "$mode" in
	--audit)
		audit_state current
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
