#!/bin/sh
set -u

STAGE=0025-initramfs-module-closure-overlay
BASE=/System/Base/Closure/$STAGE
TOOL_NAME=mixtar-initramfs-module-closure-overlay.sh
TOOL_TARGET=/System/Initramfs/Prototypes/mixtar-initramfs-module-closure-overlay.sh
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
MixtarRVS overlay module closure, stage 0025

Installed non-boot module closure tool:
  $TOOL_TARGET

This stage is non-activating:
  overlay module is copied but not loaded
  overlay is not mounted
  initramfs is not built or overwritten
  bootloader state is not changed
  /System/Current is not switched
EOF
}

write_summary() {
	cat > "$BASE/initramfs-module-closure-overlay-summary.txt" <<EOF
overlay_module_closure_status=generated
tool_target=$TOOL_TARGET
target_root=$(value_from_file "$BASE/contract.txt" target_root)
overlay_source=$(value_from_file "$BASE/contract.txt" overlay_source)
overlay_target=$(value_from_file "$BASE/contract.txt" overlay_target)
overlay_hash_match=$(value_from_file "$BASE/verify.txt" overlay_hash_match)
module_closure_ready=$(value_from_file "$BASE/report.txt" module_closure_ready)
kernel_rebuild_required=$(value_from_file "$BASE/report.txt" kernel_rebuild_required)
initramfs_must_include_overlay_module=$(value_from_file "$BASE/report.txt" initramfs_must_include_overlay_module)
initramfs_candidate_build_ready=$(value_from_file "$BASE/report.txt" initramfs_candidate_build_ready)
activation_allowed=$(value_from_file "$BASE/report.txt" activation_allowed)
overlay_loaded_before=$(value_from_file "$BASE/probe.txt" overlay_loaded_before)
overlay_loaded_after=$(value_from_file "$BASE/verify.txt" overlay_loaded_after_verify)
overlay_sys_module_before=$(value_from_file "$BASE/probe.txt" overlay_sys_module_before)
overlay_sys_module_after=$(value_from_file "$BASE/verify.txt" overlay_sys_module_after_verify)
initramfs_hash_before=$(cat "$BASE/initramfs-hash-before.txt" 2>/dev/null || true)
initramfs_hash_after=$(hash_file "$INITRAMFS")
current_before=$(cat "$BASE/system-current-before.txt" 2>/dev/null || true)
current_after=$(readlink /System/Current 2>/dev/null || true)
mount_after=$(if is_mounted; then echo present; else echo absent; fi)
next_required_stage=0026-initramfs-candidate-image-no-install
EOF
}

verify_stage() {
	rc=0
	if [ ! -x "$TOOL_TARGET" ]; then
		printf 'verify: tool target missing or not executable: %s\n' "$TOOL_TARGET" >&2
		rc=1
	fi
	for file in contract.txt probe.txt plan.txt stage-copy.txt verify.txt report.txt initramfs-module-closure-overlay-summary.txt; do
		if [ ! -s "$BASE/$file" ]; then
			printf 'verify: missing report: %s\n' "$file" >&2
			rc=1
		fi
	done
	for token in \
		'loads_overlay_module=false' \
		'mounts_overlay=false' \
		'builds_initramfs=false' \
		'writes_initramfs=false' \
		'writes_bootloader=false' \
		'switches_system_current=false'
	do
		if ! grep -F "$token" "$BASE/contract.txt" >/dev/null 2>&1; then
			printf 'verify: contract missing token: %s\n' "$token" >&2
			rc=1
		fi
	done
	for token in \
		'overlay_source_ready=true' \
		'modprobe_show_depends_result=ok' \
		'overlay_loaded_before=false' \
		'overlay_sys_module_before=false'
	do
		if ! grep -F "$token" "$BASE/probe.txt" >/dev/null 2>&1; then
			printf 'verify: probe missing token: %s\n' "$token" >&2
			rc=1
		fi
	done
	for token in \
		'would_load_overlay_module=false' \
		'would_mount_overlay=false' \
		'would_build_initramfs=false' \
		'would_write_initramfs=false' \
		'would_change_bootloader=false' \
		'would_switch_current=false'
	do
		if ! grep -F "$token" "$BASE/plan.txt" >/dev/null 2>&1; then
			printf 'verify: plan missing token: %s\n' "$token" >&2
			rc=1
		fi
	done
	for token in \
		'overlay_hash_match=true' \
		'overlay_loaded_after_verify=false' \
		'overlay_sys_module_after_verify=false'
	do
		if ! grep -F "$token" "$BASE/verify.txt" >/dev/null 2>&1; then
			printf 'verify: verify report missing token: %s\n' "$token" >&2
			rc=1
		fi
	done
	for token in \
		'module_closure_ready=true' \
		'kernel_rebuild_required=false' \
		'initramfs_must_include_overlay_module=true' \
		'initramfs_candidate_build_ready=true' \
		'activation_allowed=false' \
		'next_required_stage=0026-initramfs-candidate-image-no-install'
	do
		if ! grep -F "$token" "$BASE/report.txt" >/dev/null 2>&1; then
			printf 'verify: report missing token: %s\n' "$token" >&2
			rc=1
		fi
	done
	before_hash=$(cat "$BASE/initramfs-hash-before.txt" 2>/dev/null || true)
	after_hash=$(hash_file "$INITRAMFS")
	if [ "$before_hash" != "$after_hash" ]; then
		printf 'verify: initramfs hash changed from %s to %s\n' "$before_hash" "$after_hash" >&2
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
		printf 'stage: mountpoint already mounted before overlay module closure: %s\n' "$MOUNT_POINT" >&2
		return 1
	fi
	if [ "$source_path" != "$BASE/$TOOL_NAME" ]; then
		install -m 0755 "$source_path" "$BASE/$TOOL_NAME"
	fi
	install -m 0755 "$source_path" "$TOOL_TARGET"
	write_contract > "$BASE/stage-contract.txt"
	"$TOOL_TARGET" contract > "$BASE/contract.txt" 2>&1
	"$TOOL_TARGET" probe > "$BASE/probe.txt" 2>&1
	"$TOOL_TARGET" plan > "$BASE/plan.txt" 2>&1
	"$TOOL_TARGET" stage-copy > "$BASE/stage-copy.txt" 2>&1
	"$TOOL_TARGET" verify > "$BASE/verify.txt" 2>&1
	"$TOOL_TARGET" report > "$BASE/report.txt" 2>&1
	write_summary
	if verify_stage; then
		printf 'verified\n' > "$BASE/initramfs-module-closure-overlay-status.txt"
	else
		printf 'incomplete\n' > "$BASE/initramfs-module-closure-overlay-status.txt"
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
