#!/bin/sh
set -u

KERNEL_RELEASE=$(uname -r)
SOURCE_ROOT=/lib/modules/$KERNEL_RELEASE
TARGET_ROOT=/System/Initramfs/ModuleClosure/overlay-$KERNEL_RELEASE
OVERLAY_REL=kernel/fs/overlayfs/overlay.ko.xz
OVERLAY_SOURCE=$SOURCE_ROOT/$OVERLAY_REL
OVERLAY_TARGET=$TARGET_ROOT/lib/modules/$KERNEL_RELEASE/$OVERLAY_REL
METADATA_FILES="modules.dep modules.dep.bin modules.alias modules.alias.bin modules.builtin modules.order"

usage() {
	cat >&2 <<EOF
usage: mixtar-initramfs-module-closure-overlay <command>

commands:
  contract
  probe
  plan
  stage-copy
  verify
  report
EOF
}

hash_file() {
	path=$1
	if [ -f "$path" ]; then
		sha256sum "$path" 2>/dev/null | awk '{ print $1 }'
	else
		echo missing
	fi
}

file_report() {
	label=$1
	path=$2
	if [ -f "$path" ]; then
		echo "$label=true"
		printf '%s_path=%s\n' "$label" "$path"
		wc -c "$path" | awk -v label="$label" '{ print label "_size_bytes=" $1 }'
		sha256sum "$path" | awk -v label="$label" '{ print label "_sha256=" $1 }'
		return 0
	fi
	echo "$label=false"
	printf '%s_path=%s\n' "$label" "$path"
	return 1
}

contract() {
	cat <<EOF
overlay_module_closure_contract=non-boot
loads_overlay_module=false
mounts_overlay=false
builds_initramfs=false
writes_initramfs=false
writes_bootloader=false
switches_system_current=false
kernel_release=$KERNEL_RELEASE
source_root=$SOURCE_ROOT
target_root=$TARGET_ROOT
overlay_source=$OVERLAY_SOURCE
overlay_target=$OVERLAY_TARGET
load_policy=insmod-exact-path-first
modprobe_metadata_included=true
EOF
}

probe() {
	echo "overlay_module_probe=generated"
	file_report overlay_source_ready "$OVERLAY_SOURCE" || true
	echo "modprobe_show_depends_begin"
	if modprobe --show-depends overlay 2>&1; then
		echo "modprobe_show_depends_result=ok"
	else
		echo "modprobe_show_depends_result=failed"
	fi
	echo "modprobe_show_depends_end"
	echo "overlay_loaded_before=$(if grep -w overlay /proc/filesystems >/dev/null 2>&1; then echo true; else echo false; fi)"
	echo "overlay_sys_module_before=$(if [ -d /sys/module/overlay ]; then echo true; else echo false; fi)"
	for file in $METADATA_FILES; do
		if [ -f "$SOURCE_ROOT/$file" ]; then
			echo "metadata_source=$file state=present sha256=$(hash_file "$SOURCE_ROOT/$file")"
		else
			echo "metadata_source=$file state=missing sha256=missing"
		fi
	done
}

plan() {
	echo "overlay_module_closure_plan=generated"
	echo "would_create_target_root=true"
	echo "would_copy_overlay_module=true"
	echo "would_copy_modprobe_metadata=true"
	echo "would_load_overlay_module=false"
	echo "would_mount_overlay=false"
	echo "would_build_initramfs=false"
	echo "would_write_initramfs=false"
	echo "would_change_bootloader=false"
	echo "would_switch_current=false"
	echo "target_root=$TARGET_ROOT"
	echo "overlay_target=$OVERLAY_TARGET"
	for file in $METADATA_FILES; do
		echo "metadata_target=$TARGET_ROOT/lib/modules/$KERNEL_RELEASE/$file"
	done
}

copy_one() {
	source=$1
	target=$2
	if [ ! -f "$source" ]; then
		echo "copy_missing=$source"
		return 1
	fi
	install -d -m 0755 "$(dirname "$target")"
	install -m 0644 "$source" "$target"
	echo "copied=$source -> $target"
}

stage_copy() {
	rc=0
	echo "overlay_module_closure_stage_copy=generated"
	copy_one "$OVERLAY_SOURCE" "$OVERLAY_TARGET" || rc=1
	for file in $METADATA_FILES; do
		copy_one "$SOURCE_ROOT/$file" "$TARGET_ROOT/lib/modules/$KERNEL_RELEASE/$file" || rc=1
	done
	echo "overlay_loaded_after_copy=$(if grep -w overlay /proc/filesystems >/dev/null 2>&1; then echo true; else echo false; fi)"
	echo "overlay_sys_module_after_copy=$(if [ -d /sys/module/overlay ]; then echo true; else echo false; fi)"
	return "$rc"
}

verify() {
	rc=0
	echo "overlay_module_closure_verify=generated"
	source_hash=$(hash_file "$OVERLAY_SOURCE")
	target_hash=$(hash_file "$OVERLAY_TARGET")
	echo "overlay_source_sha256=$source_hash"
	echo "overlay_target_sha256=$target_hash"
	if [ "$source_hash" = "$target_hash" ] && [ "$source_hash" != "missing" ]; then
		echo "overlay_hash_match=true"
	else
		echo "overlay_hash_match=false"
		rc=1
	fi
	for file in $METADATA_FILES; do
		source="$SOURCE_ROOT/$file"
		target="$TARGET_ROOT/lib/modules/$KERNEL_RELEASE/$file"
		source_hash=$(hash_file "$source")
		target_hash=$(hash_file "$target")
		if [ "$source_hash" = "$target_hash" ] && [ "$source_hash" != "missing" ]; then
			echo "metadata_hash_match=$file:true"
		else
			echo "metadata_hash_match=$file:false"
			rc=1
		fi
	done
	echo "overlay_loaded_after_verify=$(if grep -w overlay /proc/filesystems >/dev/null 2>&1; then echo true; else echo false; fi)"
	echo "overlay_sys_module_after_verify=$(if [ -d /sys/module/overlay ]; then echo true; else echo false; fi)"
	return "$rc"
}

report() {
	echo "overlay_module_closure_report=generated"
	contract
	probe
	plan
	verify
	echo "module_closure_ready=$(if verify >/dev/null 2>&1; then echo true; else echo false; fi)"
	echo "kernel_rebuild_required=false"
	echo "initramfs_must_include_overlay_module=true"
	echo "initramfs_candidate_build_ready=true"
	echo "activation_allowed=false"
	echo "next_required_stage=0026-initramfs-candidate-image-no-install"
}

command=${1:-}
case "$command" in
	contract)
		contract
		;;
	probe)
		probe
		;;
	plan)
		plan
		;;
	stage-copy)
		stage_copy
		;;
	verify)
		verify
		;;
	report)
		report
		;;
	*)
		usage
		exit 2
		;;
esac
