#!/bin/sh
set -u

STAGE=0018-rootfs-image-file-manifest-and-diff
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

count_file() {
	wc -l < "$1" | awk '{ print $1 }'
}

write_contract() {
	cat <<EOF
MixtarRVS rootfs image file manifest and diff, stage 0018

Commands:
  mixtar-rootfs-image file-manifest
  mixtar-rootfs-image current-manifest
  mixtar-rootfs-image diff-current

Outputs:
  image-file-manifest.txt
  current-root-manifest.txt
  image-only.txt
  current-only.txt
  manifest-diff-summary.txt

This stage is non-activating:
  image is not mounted
  image is not modified
  /System/Current is not switched
  initramfs is not rebuilt
  bootloader state is not changed
EOF
}

write_summary() {
	cat > "$BASE/manifest-diff-summary.txt" <<EOF
diff_status=generated
image_path_count=$(count_file "$BASE/image-file-manifest.txt")
current_path_count=$(count_file "$BASE/current-root-manifest.txt")
image_only_count=$(count_file "$BASE/image-only.txt")
current_only_count=$(count_file "$BASE/current-only.txt")
current_target=$(readlink /System/Current 2>/dev/null || true)
mount_after=$(if is_mounted; then echo present; else echo absent; fi)
EOF
}

verify() {
	rc=0
	for file in image-file-manifest.txt current-root-manifest.txt image-only.txt current-only.txt manifest-diff-summary.txt; do
		if [ ! -f "$BASE/$file" ]; then
			printf 'verify: missing %s\n' "$file" >&2
			rc=1
		fi
	done
	image_count=$(count_file "$BASE/image-file-manifest.txt" 2>/dev/null || echo 0)
	current_count=$(count_file "$BASE/current-root-manifest.txt" 2>/dev/null || echo 0)
	if [ "$image_count" -lt 30000 ]; then
		printf 'verify: image manifest count too low: %s\n' "$image_count" >&2
		rc=1
	fi
	if [ "$current_count" -lt 30000 ]; then
		printf 'verify: current manifest count too low: %s\n' "$current_count" >&2
		rc=1
	fi
	for token in \
		'diff_status=generated' \
		'mount_after=absent'
	do
		if ! grep -F "$token" "$BASE/manifest-diff-summary.txt" >/dev/null 2>&1; then
			printf 'verify: summary missing token: %s\n' "$token" >&2
			rc=1
		fi
	done
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
		printf 'stage: mountpoint already mounted before manifest diff: %s\n' "$MOUNT_POINT" >&2
		return 1
	fi
	install -m 0755 "$runner" "$SYSTEM_TOOL"
	write_contract > "$BASE/rootfs-image-file-manifest-and-diff-contract.txt"
	"$SYSTEM_TOOL" file-manifest > "$BASE/image-file-manifest.txt"
	"$SYSTEM_TOOL" current-manifest > "$BASE/current-root-manifest.txt"
	comm -23 "$BASE/image-file-manifest.txt" "$BASE/current-root-manifest.txt" > "$BASE/image-only.txt"
	comm -13 "$BASE/image-file-manifest.txt" "$BASE/current-root-manifest.txt" > "$BASE/current-only.txt"
	"$SYSTEM_TOOL" diff-current > "$BASE/diff-current-command.txt" 2>&1 || true
	write_summary
	if verify; then
		printf 'verified\n' > "$BASE/rootfs-image-file-manifest-and-diff-status.txt"
	else
		printf 'incomplete\n' > "$BASE/rootfs-image-file-manifest-and-diff-status.txt"
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
