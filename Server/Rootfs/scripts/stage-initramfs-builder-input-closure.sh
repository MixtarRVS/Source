#!/bin/sh
set -u

STAGE=0023-initramfs-builder-input-closure
BASE=/System/Base/Closure/$STAGE
CLOSURE_NAME=mixtar-initramfs-input-closure.sh
CLOSURE_TARGET=/System/Initramfs/Prototypes/mixtar-initramfs-input-closure.sh
INITRAMFS=/System/Kernel/Current/initramfs.img
MOUNT_POINT=/System/Runtime/Inspect/rootfs-0015

script_dir() {
	dir=$(dirname "$0")
	cd "$dir" 2>/dev/null && pwd
}

closure_source() {
	dir=$(script_dir)
	if [ -f "$dir/$CLOSURE_NAME" ]; then
		printf '%s/%s\n' "$dir" "$CLOSURE_NAME"
		return 0
	fi
	if [ -f "/tmp/$CLOSURE_NAME" ]; then
		printf '/tmp/%s\n' "$CLOSURE_NAME"
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
MixtarRVS initramfs builder input closure, stage 0023

Installed non-boot closure tool:
  $CLOSURE_TARGET

This stage is non-activating:
  initramfs is not built
  active initramfs is not overwritten
  bootloader state is not changed
  /System/Current is not switched
  rootfs image is not mounted as /
  switch_root is not executed
EOF
}

write_summary() {
	cat > "$BASE/initramfs-input-closure-summary.txt" <<EOF
initramfs_input_closure_status=generated
closure_target=$CLOSURE_TARGET
builds_initramfs=$(value_from_file "$BASE/contract.txt" builds_initramfs)
writes_initramfs=$(value_from_file "$BASE/contract.txt" writes_initramfs)
required_tools_missing=$(value_from_file "$BASE/tools.txt" required_tools_missing)
required_libraries_missing=$(value_from_file "$BASE/libraries.txt" required_libraries_missing)
required_modules_missing=$(value_from_file "$BASE/modules.txt" required_modules_missing)
overlay_state=$(value_from_file "$BASE/report.txt" overlay_state)
rootfs_image_ready=$(value_from_file "$BASE/report.txt" rootfs_image_ready)
handoff_prototype_ready=$(value_from_file "$BASE/report.txt" handoff_prototype_ready)
initramfs_build_inputs_ready=$(value_from_file "$BASE/report.txt" initramfs_build_inputs_ready)
activation_allowed=$(value_from_file "$BASE/report.txt" activation_allowed)
initramfs_hash_before=$(cat "$BASE/initramfs-hash-before.txt" 2>/dev/null || true)
initramfs_hash_after=$(hash_file "$INITRAMFS")
current_before=$(cat "$BASE/system-current-before.txt" 2>/dev/null || true)
current_after=$(readlink /System/Current 2>/dev/null || true)
mount_after=$(if is_mounted; then echo present; else echo absent; fi)
next_required_stage=0024-overlay-support-decision
EOF
}

verify() {
	rc=0
	if [ ! -x "$CLOSURE_TARGET" ]; then
		printf 'verify: closure target missing or not executable: %s\n' "$CLOSURE_TARGET" >&2
		rc=1
	fi
	for file in contract.txt tools.txt libraries.txt modules.txt mounts.txt report.txt initramfs-input-closure-summary.txt; do
		if [ ! -s "$BASE/$file" ]; then
			printf 'verify: missing report: %s\n' "$file" >&2
			rc=1
		fi
	done
	for token in \
		'builds_initramfs=false' \
		'writes_initramfs=false' \
		'writes_bootloader=false' \
		'switches_system_current=false' \
		'executes_switch_root=false'
	do
		if ! grep -F "$token" "$BASE/contract.txt" >/dev/null 2>&1; then
			printf 'verify: contract missing token: %s\n' "$token" >&2
			rc=1
		fi
	done
	for token in \
		'tools_report=generated' \
		'required_tools_missing=0'
	do
		if ! grep -F "$token" "$BASE/tools.txt" >/dev/null 2>&1; then
			printf 'verify: tools missing token: %s\n' "$token" >&2
			rc=1
		fi
	done
	for token in \
		'libraries_report=generated' \
		'required_libraries_missing=0'
	do
		if ! grep -F "$token" "$BASE/libraries.txt" >/dev/null 2>&1; then
			printf 'verify: libraries missing token: %s\n' "$token" >&2
			rc=1
		fi
	done
	for token in \
		'modules_report=generated' \
		'module=squashfs state=available_or_builtin' \
		'module=overlay state=missing'
	do
		if ! grep -F "$token" "$BASE/modules.txt" >/dev/null 2>&1; then
			printf 'verify: modules missing token: %s\n' "$token" >&2
			rc=1
		fi
	done
	for token in \
		'initramfs_input_closure_report=generated' \
		'rootfs_image_ready=true' \
		'handoff_prototype_ready=true' \
		'initramfs_build_inputs_ready=false' \
		'activation_allowed=false' \
		'next_required_stage=0024-overlay-support-decision'
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
	source_path=$(closure_source) || {
		printf 'stage: missing %s next to this script or in /tmp\n' "$CLOSURE_NAME" >&2
		return 1
	}
	install -d -m 0755 "$BASE" /System/Initramfs/Prototypes
	readlink /System/Current 2>/dev/null > "$BASE/system-current-before.txt" || true
	hash_file "$INITRAMFS" > "$BASE/initramfs-hash-before.txt"
	if is_mounted; then
		printf 'stage: mountpoint already mounted before input closure diagnostics: %s\n' "$MOUNT_POINT" >&2
		return 1
	fi
	if [ "$source_path" != "$BASE/$CLOSURE_NAME" ]; then
		install -m 0755 "$source_path" "$BASE/$CLOSURE_NAME"
	fi
	install -m 0755 "$source_path" "$CLOSURE_TARGET"
	write_contract > "$BASE/stage-contract.txt"
	"$CLOSURE_TARGET" contract > "$BASE/contract.txt" 2>&1
	"$CLOSURE_TARGET" tools > "$BASE/tools.txt" 2>&1
	"$CLOSURE_TARGET" libraries > "$BASE/libraries.txt" 2>&1
	"$CLOSURE_TARGET" modules > "$BASE/modules.txt" 2>&1
	"$CLOSURE_TARGET" mounts > "$BASE/mounts.txt" 2>&1
	"$CLOSURE_TARGET" report > "$BASE/report.txt" 2>&1
	write_summary
	if verify; then
		printf 'verified\n' > "$BASE/initramfs-builder-input-closure-status.txt"
	else
		printf 'incomplete\n' > "$BASE/initramfs-builder-input-closure-status.txt"
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
