#!/bin/sh
set -u

STAGE=0026-initramfs-candidate-image-no-install
BASE=/System/Base/Closure/$STAGE
TOOL_NAME=mixtar-initramfs-candidate-builder.sh
TOOL_TARGET=/System/Initramfs/Prototypes/mixtar-initramfs-candidate-builder.sh
INITRAMFS=/System/Kernel/Current/initramfs.img
MOUNT_POINT=/System/Runtime/Inspect/rootfs-0015

script_dir() {
	dir=$(dirname "$0")
	cd "$dir" 2>/dev/null && pwd
}

tool_source() {
	dir=$(script_dir)
	if [ -f "$dir/$TOOL_NAME" ]; then
		printf '%s/%s\n' "$dir" "$TOOL_NAME"
		return 0
	fi
	if [ -f "/tmp/$TOOL_NAME" ]; then
		printf '/tmp/%s\n' "$TOOL_NAME"
		return 0
	fi
	return 1
}

is_mounted() {
	awk -v mount_point="$MOUNT_POINT" '$2 == mount_point { found = 1 } END { exit found ? 0 : 1 }' /proc/mounts 2>/dev/null
}

hash_file() {
	path=$1
	if [ -f "$path" ]; then
		sha256sum "$path" 2>/dev/null | awk '{ print $1 }'
	else
		echo missing
	fi
}

value_from_file() {
	file=$1
	key=$2
	awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$file"
}

write_contract() {
	cat <<EOF
MixtarRVS initramfs candidate image, stage 0026

Installed non-boot candidate builder:
  $TOOL_TARGET

This stage is non-activating:
  candidate initramfs is built outside active kernel profile
  active initramfs is not overwritten
  bootloader state is not changed
  /System/Current is not switched
  overlay module is not loaded
  overlay is not mounted
EOF
}

write_summary() {
	cat > "$BASE/initramfs-candidate-image-summary.txt" <<EOF
initramfs_candidate_status=generated
tool_target=$TOOL_TARGET
candidate_image=$(value_from_file "$BASE/build-candidate.txt" candidate_image)
candidate_size_bytes=$(value_from_file "$BASE/build-candidate.txt" candidate_size_bytes)
candidate_sha256=$(value_from_file "$BASE/build-candidate.txt" candidate_sha256)
active_sha256_before=$(cat "$BASE/initramfs-hash-before.txt" 2>/dev/null || true)
active_sha256_after=$(hash_file "$INITRAMFS")
candidate_gzip_test=$(value_from_file "$BASE/inspect.txt" candidate_gzip_test)
candidate_cpio_list=$(value_from_file "$BASE/inspect.txt" candidate_cpio_list)
candidate_entry_count=$(value_from_file "$BASE/inspect.txt" candidate_entry_count)
candidate_differs_from_active=$(value_from_file "$BASE/verify.txt" candidate_differs_from_active)
candidate_ready=$(value_from_file "$BASE/report.txt" candidate_ready)
activation_allowed=$(value_from_file "$BASE/report.txt" activation_allowed)
overlay_loaded_after=$(value_from_file "$BASE/verify.txt" overlay_loaded_after_verify)
overlay_sys_module_after=$(value_from_file "$BASE/verify.txt" overlay_sys_module_after_verify)
current_before=$(cat "$BASE/system-current-before.txt" 2>/dev/null || true)
current_after=$(readlink /System/Current 2>/dev/null || true)
mount_after=$(if is_mounted; then echo present; else echo absent; fi)
next_required_stage=0027-initramfs-candidate-diff-and-boot-entry-plan
EOF
}

verify_stage() {
	rc=0
	if [ ! -x "$TOOL_TARGET" ]; then
		printf 'verify: tool target missing or not executable: %s\n' "$TOOL_TARGET" >&2
		rc=1
	fi
	for file in contract.txt plan.txt build-candidate.txt inspect.txt verify.txt report.txt initramfs-candidate-image-summary.txt; do
		if [ ! -s "$BASE/$file" ]; then
			printf 'verify: missing report: %s\n' "$file" >&2
			rc=1
		fi
	done
	for token in \
		'installs_candidate_initramfs=false' \
		'overwrites_active_initramfs=false' \
		'writes_bootloader=false' \
		'switches_system_current=false' \
		'loads_overlay_module=false' \
		'mounts_overlay=false'
	do
		if ! grep -F "$token" "$BASE/contract.txt" >/dev/null 2>&1; then
			printf 'verify: contract missing token: %s\n' "$token" >&2
			rc=1
		fi
	done
	for token in \
		'build_result=created' \
		'installs_candidate_initramfs=false' \
		'overwrites_active_initramfs=false' \
		'writes_bootloader=false' \
		'switches_system_current=false'
	do
		if ! grep -F "$token" "$BASE/build-candidate.txt" >/dev/null 2>&1; then
			printf 'verify: build missing token: %s\n' "$token" >&2
			rc=1
		fi
	done
	for token in \
		'candidate_present=true' \
		'candidate_gzip_test=ok' \
		'candidate_cpio_list=ok' \
		'candidate_contains=init:true' \
		'candidate_contains=System/Initramfs/Prototypes/mixtar-initramfs-handoff.sh:true' \
		'candidate_contains=usr/bin/mixtar-initramfs-handoff:true' \
		'candidate_contains=etc/mixtar-initramfs-candidate:true'
	do
		if ! grep -F "$token" "$BASE/inspect.txt" >/dev/null 2>&1; then
			printf 'verify: inspect missing token: %s\n' "$token" >&2
			rc=1
		fi
	done
	if ! grep -F 'kernel/fs/overlayfs/overlay.ko.xz:true' "$BASE/inspect.txt" >/dev/null 2>&1; then
		printf 'verify: inspect missing overlay module\n' >&2
		rc=1
	fi
	for token in \
		'candidate_differs_from_active=true' \
		'overlay_loaded_after_verify=false' \
		'overlay_sys_module_after_verify=false' \
		'activation_allowed=false'
	do
		if ! grep -F "$token" "$BASE/verify.txt" >/dev/null 2>&1; then
			printf 'verify: verify report missing token: %s\n' "$token" >&2
			rc=1
		fi
	done
	for token in \
		'candidate_ready=true' \
		'activation_allowed=false' \
		'next_required_stage=0027-initramfs-candidate-diff-and-boot-entry-plan'
	do
		if ! grep -F "$token" "$BASE/report.txt" >/dev/null 2>&1; then
			printf 'verify: report missing token: %s\n' "$token" >&2
			rc=1
		fi
	done
	before_hash=$(cat "$BASE/initramfs-hash-before.txt" 2>/dev/null || true)
	after_hash=$(hash_file "$INITRAMFS")
	if [ "$before_hash" != "$after_hash" ]; then
		printf 'verify: active initramfs hash changed from %s to %s\n' "$before_hash" "$after_hash" >&2
		rc=1
	fi
	before_current=$(cat "$BASE/system-current-before.txt" 2>/dev/null || true)
	after_current=$(readlink /System/Current 2>/dev/null || true)
	if [ "$before_current" != "$after_current" ]; then
		printf 'verify: /System/Current changed from %s to %s\n' "$before_current" "$after_current" >&2
		rc=1
	fi
	if is_mounted; then
		printf 'verify: mountpoint still mounted: %s\n' "$MOUNT_POINT" >&2
		rc=1
	fi
	return "$rc"
}

stage() {
	source_path=$(tool_source) || {
		printf 'stage: missing %s next to this script or in /tmp\n' "$TOOL_NAME" >&2
		return 1
	}
	install -d -m 0755 "$BASE" /System/Initramfs/Prototypes
	readlink /System/Current 2>/dev/null > "$BASE/system-current-before.txt" || true
	hash_file "$INITRAMFS" > "$BASE/initramfs-hash-before.txt"
	if is_mounted; then
		printf 'stage: mountpoint already mounted before initramfs candidate build: %s\n' "$MOUNT_POINT" >&2
		return 1
	fi
	if [ "$source_path" != "$BASE/$TOOL_NAME" ]; then
		install -m 0755 "$source_path" "$BASE/$TOOL_NAME"
	fi
	install -m 0755 "$source_path" "$TOOL_TARGET"
	write_contract > "$BASE/stage-contract.txt"
	"$TOOL_TARGET" contract > "$BASE/contract.txt" 2>&1
	"$TOOL_TARGET" plan > "$BASE/plan.txt" 2>&1
	"$TOOL_TARGET" build-candidate > "$BASE/build-candidate.txt" 2>&1
	"$TOOL_TARGET" inspect > "$BASE/inspect.txt" 2>&1
	"$TOOL_TARGET" verify > "$BASE/verify.txt" 2>&1
	"$TOOL_TARGET" report > "$BASE/report.txt" 2>&1
	write_summary
	if verify_stage; then
		printf 'verified\n' > "$BASE/initramfs-candidate-image-no-install-status.txt"
	else
		printf 'incomplete\n' > "$BASE/initramfs-candidate-image-no-install-status.txt"
		return 1
	fi
}

mode=${1:-}
if [ -z "$mode" ]; then
	mode=--verify
fi

case "$mode" in
	--verify)
		verify_stage
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
