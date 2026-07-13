#!/bin/sh
set -u

STAGE_ID=0026-initramfs-candidate-image-no-install
ACTIVE_INITRAMFS=/System/Kernel/Current/initramfs.img
CANDIDATE_ROOT=/System/Initramfs/Candidates/$STAGE_ID
WORK_ROOT=$CANDIDATE_ROOT/root
CANDIDATE_IMAGE=$CANDIDATE_ROOT/initramfs.img
KERNEL_RELEASE=$(uname -r)
MODULE_CLOSURE=/System/Initramfs/ModuleClosure/overlay-$KERNEL_RELEASE
HANDOFF_PROTOTYPE=/System/Initramfs/Prototypes/mixtar-initramfs-handoff.sh
CLOSURE_OVERLAY_REL=lib/modules/$KERNEL_RELEASE/kernel/fs/overlayfs/overlay.ko.xz
CANDIDATE_OVERLAY_REL=usr/lib/modules/$KERNEL_RELEASE/kernel/fs/overlayfs/overlay.ko.xz
MARKER=etc/mixtar-initramfs-candidate

usage() {
	cat >&2 <<EOF
usage: mixtar-initramfs-candidate-builder <command>

commands:
  contract
  plan
  build-candidate
  inspect
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

size_file() {
	path=$1
	if [ -f "$path" ]; then
		wc -c < "$path" 2>/dev/null | awk '{ print $1 }'
	else
		echo 0
	fi
}

tool_state() {
	name=$1
	path=$(command -v "$name" 2>/dev/null || true)
	if [ -n "$path" ]; then
		echo "tool=$name path=$path state=present"
	else
		echo "tool=$name path=missing state=missing"
	fi
}

contract() {
	cat <<EOF
initramfs_candidate_builder_contract=no-install
builds_candidate_initramfs=true
installs_candidate_initramfs=false
overwrites_active_initramfs=false
writes_bootloader=false
switches_system_current=false
loads_overlay_module=false
mounts_overlay=false
executes_switch_root=false
active_initramfs=$ACTIVE_INITRAMFS
candidate_root=$CANDIDATE_ROOT
work_root=$WORK_ROOT
candidate_image=$CANDIDATE_IMAGE
module_closure=$MODULE_CLOSURE
handoff_prototype=$HANDOFF_PROTOTYPE
EOF
}

plan() {
	echo "initramfs_candidate_plan=generated"
	echo "source_format=gzip-cpio-newc"
	echo "candidate_format=gzip-cpio-newc"
	echo "would_extract_active_initramfs=true"
	echo "would_copy_overlay_module_closure=true"
	echo "would_copy_handoff_prototype=true"
	echo "would_write_candidate_marker=true"
	echo "would_pack_candidate_initramfs=true"
	echo "would_install_candidate_initramfs=false"
	echo "would_overwrite_active_initramfs=false"
	echo "would_change_bootloader=false"
	echo "would_switch_current=false"
	echo "would_load_overlay_module=false"
	echo "would_mount_overlay=false"
	echo "active_initramfs=$ACTIVE_INITRAMFS"
	echo "candidate_image=$CANDIDATE_IMAGE"
	echo "candidate_marker=$MARKER"
	tool_state zcat
	tool_state cpio
	tool_state gzip
	tool_state find
	tool_state install
	tool_state sha256sum
}

copy_tree_files() {
	source_root=$1
	target_root=$2
	rc=0
	if [ ! -d "$source_root" ]; then
		echo "copy_tree_source_missing=$source_root"
		return 1
	fi
	(cd "$source_root" && find . -type f) | while read -r rel; do
		clean_rel=${rel#./}
		source=$source_root/$clean_rel
		target=$target_root/$clean_rel
		install -d -m 0755 "$(dirname "$target")"
		install -m 0644 "$source" "$target" || rc=1
	done
	return "$rc"
}

write_marker() {
	install -d -m 0755 "$WORK_ROOT/etc"
	cat > "$WORK_ROOT/$MARKER" <<EOF
mixtar_initramfs_candidate=$STAGE_ID
active_initramfs_sha256=$(hash_file "$ACTIVE_INITRAMFS")
overlay_module_sha256=$(hash_file "$MODULE_CLOSURE/$CLOSURE_OVERLAY_REL")
handoff_prototype_sha256=$(hash_file "$HANDOFF_PROTOTYPE")
installs_candidate_initramfs=false
overwrites_active_initramfs=false
writes_bootloader=false
switches_system_current=false
EOF
}

build_candidate() {
	rc=0
	echo "initramfs_candidate_build=generated"
	if [ "$(id -u 2>/dev/null || echo 1)" != "0" ]; then
		echo "build_error=requires-root"
		return 1
	fi
	install -d -m 0755 "$CANDIDATE_ROOT" "$WORK_ROOT"
	if [ ! -f "$ACTIVE_INITRAMFS" ]; then
		echo "build_error=missing-active-initramfs"
		return 1
	fi
	if [ ! -d "$MODULE_CLOSURE" ]; then
		echo "build_error=missing-module-closure"
		return 1
	fi
	if [ ! -x "$HANDOFF_PROTOTYPE" ]; then
		echo "build_error=missing-handoff-prototype"
		return 1
	fi
	echo "extract_active_initramfs=true"
	(cd "$WORK_ROOT" && zcat "$ACTIVE_INITRAMFS" | cpio -idmu >/dev/null 2>&1) || rc=1
	echo "copy_overlay_module_closure=true"
	copy_tree_files "$MODULE_CLOSURE" "$WORK_ROOT" || rc=1
	install -d -m 0755 "$WORK_ROOT/System/Initramfs/Prototypes" "$WORK_ROOT/usr/bin"
	install -m 0755 "$HANDOFF_PROTOTYPE" "$WORK_ROOT/System/Initramfs/Prototypes/mixtar-initramfs-handoff.sh" || rc=1
	install -m 0755 "$HANDOFF_PROTOTYPE" "$WORK_ROOT/usr/bin/mixtar-initramfs-handoff" || rc=1
	write_marker || rc=1
	echo "pack_candidate_initramfs=true"
	(cd "$WORK_ROOT" && find . -print | cpio -o -H newc 2>/dev/null | gzip -9 > "$CANDIDATE_IMAGE") || rc=1
	echo "candidate_image=$CANDIDATE_IMAGE"
	echo "candidate_size_bytes=$(size_file "$CANDIDATE_IMAGE")"
	echo "candidate_sha256=$(hash_file "$CANDIDATE_IMAGE")"
	echo "active_sha256=$(hash_file "$ACTIVE_INITRAMFS")"
	echo "installs_candidate_initramfs=false"
	echo "overwrites_active_initramfs=false"
	echo "writes_bootloader=false"
	echo "switches_system_current=false"
	echo "loads_overlay_module=false"
	echo "mounts_overlay=false"
	if [ "$rc" -eq 0 ]; then
		echo "build_result=created"
	else
		echo "build_result=incomplete"
	fi
	return "$rc"
}

candidate_list() {
	zcat "$CANDIDATE_IMAGE" 2>/dev/null | cpio -t 2>/dev/null
}

list_has_path() {
	list_file=$1
	path=$2
	if grep -Fx "$path" "$list_file" >/dev/null 2>&1; then
		return 0
	fi
	if grep -Fx "./$path" "$list_file" >/dev/null 2>&1; then
		return 0
	fi
	return 1
}

inspect() {
	list_file=/tmp/mixtar-initramfs-candidate-list.$$
	rc=0
	echo "initramfs_candidate_inspect=generated"
	if [ ! -f "$CANDIDATE_IMAGE" ]; then
		echo "candidate_present=false"
		return 1
	fi
	echo "candidate_present=true"
	echo "candidate_image=$CANDIDATE_IMAGE"
	echo "candidate_size_bytes=$(size_file "$CANDIDATE_IMAGE")"
	echo "candidate_sha256=$(hash_file "$CANDIDATE_IMAGE")"
	if gzip -t "$CANDIDATE_IMAGE" 2>/dev/null; then
		echo "candidate_gzip_test=ok"
	else
		echo "candidate_gzip_test=failed"
		rc=1
	fi
	if candidate_list > "$list_file"; then
		echo "candidate_cpio_list=ok"
	else
		echo "candidate_cpio_list=failed"
		rm -f "$list_file"
		return 1
	fi
	echo "candidate_entry_count=$(wc -l < "$list_file" | awk '{ print $1 }')"
	for path in \
		init \
		"$CANDIDATE_OVERLAY_REL" \
		System/Initramfs/Prototypes/mixtar-initramfs-handoff.sh \
		usr/bin/mixtar-initramfs-handoff \
		"$MARKER"
	do
		if list_has_path "$list_file" "$path"; then
			echo "candidate_contains=$path:true"
		else
			echo "candidate_contains=$path:false"
			rc=1
		fi
	done
	rm -f "$list_file"
	return "$rc"
}

verify() {
	rc=0
	echo "initramfs_candidate_verify=generated"
	inspect || rc=1
	active_hash=$(hash_file "$ACTIVE_INITRAMFS")
	candidate_hash=$(hash_file "$CANDIDATE_IMAGE")
	echo "active_sha256=$active_hash"
	echo "candidate_sha256=$candidate_hash"
	if [ "$candidate_hash" != "missing" ] && [ "$candidate_hash" != "$active_hash" ]; then
		echo "candidate_differs_from_active=true"
	else
		echo "candidate_differs_from_active=false"
		rc=1
	fi
	if grep -w overlay /proc/filesystems >/dev/null 2>&1; then
		echo "overlay_loaded_after_verify=true"
		rc=1
	else
		echo "overlay_loaded_after_verify=false"
	fi
	if [ -d /sys/module/overlay ]; then
		echo "overlay_sys_module_after_verify=true"
		rc=1
	else
		echo "overlay_sys_module_after_verify=false"
	fi
	echo "installs_candidate_initramfs=false"
	echo "overwrites_active_initramfs=false"
	echo "writes_bootloader=false"
	echo "switches_system_current=false"
	echo "activation_allowed=false"
	return "$rc"
}

report() {
	echo "initramfs_candidate_report=generated"
	contract
	plan
	verify
	echo "candidate_ready=$(if verify >/dev/null 2>&1; then echo true; else echo false; fi)"
	echo "activation_allowed=false"
	echo "next_required_stage=0027-initramfs-candidate-diff-and-boot-entry-plan"
}

command=${1:-}
case "$command" in
	contract)
		contract
		;;
	plan)
		plan
		;;
	build-candidate)
		build_candidate
		;;
	inspect)
		inspect
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
