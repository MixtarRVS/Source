#!/bin/sh
set -u

STAGE=0024-overlay-support-decision
BASE=/System/Base/Closure/$STAGE
TOOL_NAME=mixtar-overlay-support-decision.sh
TOOL_TARGET=/System/Initramfs/Prototypes/mixtar-overlay-support-decision.sh
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
MixtarRVS overlay support decision, stage 0024

Installed non-boot decision tool:
  $TOOL_TARGET

This stage is non-activating:
  overlay module is not loaded
  overlay is not mounted
  kernel is not rebuilt
  initramfs is not built or overwritten
  bootloader state is not changed
  /System/Current is not switched
EOF
}

write_summary() {
	cat > "$BASE/overlay-support-decision-summary.txt" <<EOF
overlay_support_decision_status=generated
tool_target=$TOOL_TARGET
config_overlay_fs=$(value_from_file "$BASE/probe.txt" config_overlay_fs)
overlay_module_file_ready=$(value_from_file "$BASE/probe.txt" overlay_module_file_ready)
overlay_module_path=$(value_from_file "$BASE/probe.txt" overlay_module_path)
overlay_support_state=$(value_from_file "$BASE/decision.txt" overlay_support_state)
kernel_rebuild_required=$(value_from_file "$BASE/decision.txt" kernel_rebuild_required)
initramfs_must_include_overlay_module=$(value_from_file "$BASE/decision.txt" initramfs_must_include_overlay_module)
primary_boot_policy=$(value_from_file "$BASE/decision.txt" primary_boot_policy)
readonly_image_boot_policy=$(value_from_file "$BASE/decision.txt" readonly_image_boot_policy)
activation_allowed=$(value_from_file "$BASE/decision.txt" activation_allowed)
next_required_stage=$(value_from_file "$BASE/decision.txt" next_required_stage)
initramfs_hash_before=$(cat "$BASE/initramfs-hash-before.txt" 2>/dev/null || true)
initramfs_hash_after=$(hash_file "$INITRAMFS")
current_before=$(cat "$BASE/system-current-before.txt" 2>/dev/null || true)
current_after=$(readlink /System/Current 2>/dev/null || true)
mount_after=$(if is_mounted; then echo present; else echo absent; fi)
EOF
}

verify() {
	rc=0
	if [ ! -x "$TOOL_TARGET" ]; then
		printf 'verify: tool target missing or not executable: %s\n' "$TOOL_TARGET" >&2
		rc=1
	fi
	for file in contract.txt probe.txt decision.txt overlay-support-decision-summary.txt; do
		if [ ! -s "$BASE/$file" ]; then
			printf 'verify: missing report: %s\n' "$file" >&2
			rc=1
		fi
	done
	for token in \
		'builds_kernel=false' \
		'writes_kernel=false' \
		'builds_initramfs=false' \
		'writes_initramfs=false' \
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
		'config_overlay_fs=m' \
		'overlay_module_file_ready=true' \
		'modprobe_dryrun_result=ok'
	do
		if ! grep -F "$token" "$BASE/probe.txt" >/dev/null 2>&1; then
			printf 'verify: probe missing token: %s\n' "$token" >&2
			rc=1
		fi
	done
	for token in \
		'overlay_support_state=available-as-module' \
		'kernel_rebuild_required=false' \
		'initramfs_must_include_overlay_module=true' \
		'primary_boot_policy=squashfs-readonly-plus-writable-overlay' \
		'readonly_image_boot_policy=emergency-or-diagnostic-only' \
		'activation_allowed=false' \
		'next_required_stage=0025-initramfs-module-closure-overlay'
	do
		if ! grep -F "$token" "$BASE/decision.txt" >/dev/null 2>&1; then
			printf 'verify: decision missing token: %s\n' "$token" >&2
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
		printf 'stage: mountpoint already mounted before overlay decision: %s\n' "$MOUNT_POINT" >&2
		return 1
	fi
	if [ "$source_path" != "$BASE/$TOOL_NAME" ]; then
		install -m 0755 "$source_path" "$BASE/$TOOL_NAME"
	fi
	install -m 0755 "$source_path" "$TOOL_TARGET"
	write_contract > "$BASE/stage-contract.txt"
	"$TOOL_TARGET" contract > "$BASE/contract.txt" 2>&1
	"$TOOL_TARGET" probe > "$BASE/probe.txt" 2>&1
	"$TOOL_TARGET" decision > "$BASE/decision.txt" 2>&1
	write_summary
	if verify; then
		printf 'verified\n' > "$BASE/overlay-support-decision-status.txt"
	else
		printf 'incomplete\n' > "$BASE/overlay-support-decision-status.txt"
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
