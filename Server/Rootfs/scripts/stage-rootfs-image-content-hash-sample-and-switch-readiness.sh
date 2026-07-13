#!/bin/sh
set -u

STAGE=0019-rootfs-image-content-hash-sample-and-switch-readiness
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
MixtarRVS rootfs image content hash sample and switch-readiness, stage 0019

Commands:
  mixtar-rootfs-image hash-sample
  mixtar-rootfs-image switch-readiness

This stage is non-activating:
  image is not mounted
  image is not modified
  /System/Current is not switched
  initramfs is not rebuilt
  bootloader state is not changed
EOF
}

write_summary() {
	matches=$(grep -F 'match=true' "$BASE/hash-sample.txt" | wc -l | awk '{ print $1 }')
	mismatches=$(grep -F 'match=false' "$BASE/hash-sample.txt" | wc -l | awk '{ print $1 }')
	samples=$(grep -F 'sample=' "$BASE/hash-sample.txt" | wc -l | awk '{ print $1 }')
	cat > "$BASE/hash-and-switch-summary.txt" <<EOF
hash_sample_status=generated
hash_sample_count=$samples
hash_match_count=$matches
hash_mismatch_count=$mismatches
current_target=$(readlink /System/Current 2>/dev/null || true)
mount_after=$(if is_mounted; then echo present; else echo absent; fi)
EOF
}

verify() {
	rc=0
	if [ ! -s "$BASE/hash-sample.txt" ]; then
		printf 'verify: missing hash sample\n' >&2
		rc=1
	fi
	if [ ! -s "$BASE/switch-readiness.txt" ]; then
		printf 'verify: missing switch readiness\n' >&2
		rc=1
	fi
	samples=$(grep -F 'sample=' "$BASE/hash-sample.txt" | wc -l | awk '{ print $1 }')
	if [ "$samples" -lt 10 ]; then
		printf 'verify: too few hash samples: %s\n' "$samples" >&2
		rc=1
	fi
	for token in \
		'rootfs_image_ready=true' \
		'generation_manifest_ready=true' \
		'activation_plan_present=true' \
		'future_switch_ready=false' \
		'would_switch_current=false' \
		'would_change_bootloader=false' \
		'would_rebuild_initramfs=false'
	do
		if ! grep -F "$token" "$BASE/switch-readiness.txt" >/dev/null 2>&1; then
			printf 'verify: switch-readiness missing token: %s\n' "$token" >&2
			rc=1
		fi
	done
	if ! grep -F 'hash_sample_status=generated' "$BASE/hash-and-switch-summary.txt" >/dev/null 2>&1; then
		printf 'verify: summary missing hash status\n' >&2
		rc=1
	fi
	before=$(cat "$BASE/system-current-before.txt" 2>/dev/null || true)
	after=$(readlink /System/Current 2>/dev/null || true)
	if [ "$before" != "$after" ]; then
		printf 'verify: /System/Current changed from %s to %s\n' "$before" "$after" >&2
		rc=1
	fi
	if is_mounted; then
		printf 'verify: mountpoint still mounted: %s\n' "$MOUNT_POINT" >&2
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
		printf 'stage: mountpoint already mounted before hash sample: %s\n' "$MOUNT_POINT" >&2
		return 1
	fi
	install -m 0755 "$runner" "$SYSTEM_TOOL"
	write_contract > "$BASE/rootfs-image-content-hash-sample-and-switch-readiness-contract.txt"
	"$SYSTEM_TOOL" hash-sample > "$BASE/hash-sample.txt" 2>&1
	"$SYSTEM_TOOL" switch-readiness > "$BASE/switch-readiness.txt" 2>&1
	write_summary
	if verify; then
		printf 'verified\n' > "$BASE/rootfs-image-content-hash-sample-and-switch-readiness-status.txt"
	else
		printf 'incomplete\n' > "$BASE/rootfs-image-content-hash-sample-and-switch-readiness-status.txt"
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
