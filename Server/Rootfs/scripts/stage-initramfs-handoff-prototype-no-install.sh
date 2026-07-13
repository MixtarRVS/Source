#!/bin/sh
set -u

STAGE=0022-initramfs-handoff-prototype-no-install
BASE=/System/Base/Closure/$STAGE
PROTOTYPE_NAME=mixtar-initramfs-handoff-prototype.sh
PROTOTYPE_TARGET=/System/Initramfs/Prototypes/mixtar-initramfs-handoff.sh
INITRAMFS=/System/Kernel/Current/initramfs.img
MOUNT_POINT=/System/Runtime/Inspect/rootfs-0015

script_dir() {
	dir=$(dirname "$0")
	cd "$dir" 2>/dev/null && pwd
}

prototype_source() {
	dir=$(script_dir)
	if [ -f "$dir/$PROTOTYPE_NAME" ]; then
		printf '%s/%s\n' "$dir" "$PROTOTYPE_NAME"
		return 0
	fi
	if [ -f "/tmp/$PROTOTYPE_NAME" ]; then
		printf '/tmp/%s\n' "$PROTOTYPE_NAME"
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
MixtarRVS initramfs handoff prototype, stage 0022

Installed prototype path:
  $PROTOTYPE_TARGET

This stage is non-activating:
  prototype is not packed into active initramfs
  active initramfs is not rebuilt or overwritten
  bootloader state is not changed
  /System/Current is not switched
  rootfs image is not mounted as /
  switch_root is not executed
EOF
}

write_summary() {
	cat > "$BASE/initramfs-handoff-prototype-summary.txt" <<EOF
initramfs_handoff_prototype_status=generated
prototype_target=$PROTOTYPE_TARGET
prototype_no_install=$(value_from_file "$BASE/contract.txt" prototype_no_install)
executes_switch_root=$(value_from_file "$BASE/contract.txt" executes_switch_root)
rootfs_image_ready=$(value_from_file "$BASE/check-live.txt" rootfs_image_ready)
kernel_squashfs_ready=$(value_from_file "$BASE/check-live.txt" kernel_squashfs_ready)
kernel_overlay_ready=$(value_from_file "$BASE/check-live.txt" kernel_overlay_ready)
overlay_policy=$(value_from_file "$BASE/check-live.txt" overlay_policy)
switch_root_tool=$(value_from_file "$BASE/check-live.txt" switch_root)
check_live_result=$(value_from_file "$BASE/check-live.txt" check_live_result)
simulation_result=$(value_from_file "$BASE/simulate.txt" simulation_result)
simulation_switch_root_performed=$(value_from_file "$BASE/simulate.txt" simulation_switch_root_performed)
initramfs_hash_before=$(cat "$BASE/initramfs-hash-before.txt" 2>/dev/null || true)
initramfs_hash_after=$(hash_file "$INITRAMFS")
current_before=$(cat "$BASE/system-current-before.txt" 2>/dev/null || true)
current_after=$(readlink /System/Current 2>/dev/null || true)
mount_after=$(if is_mounted; then echo present; else echo absent; fi)
next_required_stage=0023-initramfs-builder-input-closure
EOF
}

verify() {
	rc=0
	if [ ! -x "$PROTOTYPE_TARGET" ]; then
		printf 'verify: prototype target missing or not executable: %s\n' "$PROTOTYPE_TARGET" >&2
		rc=1
	fi
	for file in contract.txt plan.txt check-live.txt simulate.txt initramfs-handoff-prototype-summary.txt; do
		if [ ! -s "$BASE/$file" ]; then
			printf 'verify: missing report: %s\n' "$file" >&2
			rc=1
		fi
	done
	for token in \
		'prototype_no_install=true' \
		'executes_switch_root=false' \
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
		'initramfs_handoff_prototype_plan=generated' \
		'would_mount_runtime_filesystems=false' \
		'would_switch_root=false' \
		'would_write_initramfs=false' \
		'would_change_bootloader=false' \
		'would_switch_current=false' \
		'activation_allowed=false'
	do
		if ! grep -F "$token" "$BASE/plan.txt" >/dev/null 2>&1; then
			printf 'verify: plan missing token: %s\n' "$token" >&2
			rc=1
		fi
	done
	for token in \
		'rootfs_image_ready=true' \
		'kernel_squashfs_ready=true' \
		'kernel_overlay_ready=' \
		'check_live_result='
	do
		if ! grep -F "$token" "$BASE/check-live.txt" >/dev/null 2>&1; then
			printf 'verify: check-live missing token: %s\n' "$token" >&2
			rc=1
		fi
	done
	for token in \
		'initramfs_handoff_simulation=non-mutating' \
		'simulation_result=generated' \
		'simulation_switch_root_performed=false' \
		'simulation_initramfs_written=false' \
		'simulation_bootloader_written=false' \
		'simulation_current_switched=false'
	do
		if ! grep -F "$token" "$BASE/simulate.txt" >/dev/null 2>&1; then
			printf 'verify: simulate missing token: %s\n' "$token" >&2
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
	source_path=$(prototype_source) || {
		printf 'stage: missing %s next to this script or in /tmp\n' "$PROTOTYPE_NAME" >&2
		return 1
	}
	install -d -m 0755 "$BASE" /System/Initramfs/Prototypes
	readlink /System/Current 2>/dev/null > "$BASE/system-current-before.txt" || true
	hash_file "$INITRAMFS" > "$BASE/initramfs-hash-before.txt"
	if is_mounted; then
		printf 'stage: mountpoint already mounted before prototype diagnostics: %s\n' "$MOUNT_POINT" >&2
		return 1
	fi
	if [ "$source_path" != "$BASE/$PROTOTYPE_NAME" ]; then
		install -m 0755 "$source_path" "$BASE/$PROTOTYPE_NAME"
	fi
	install -m 0755 "$source_path" "$PROTOTYPE_TARGET"
	write_contract > "$BASE/stage-contract.txt"
	"$PROTOTYPE_TARGET" contract > "$BASE/contract.txt" 2>&1
	"$PROTOTYPE_TARGET" plan > "$BASE/plan.txt" 2>&1
	"$PROTOTYPE_TARGET" check-live > "$BASE/check-live.txt" 2>&1 || true
	"$PROTOTYPE_TARGET" simulate > "$BASE/simulate.txt" 2>&1
	write_summary
	if verify; then
		printf 'verified\n' > "$BASE/initramfs-handoff-prototype-no-install-status.txt"
	else
		printf 'incomplete\n' > "$BASE/initramfs-handoff-prototype-no-install-status.txt"
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
