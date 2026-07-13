#!/bin/sh
set -u

STAGE_ID=0028-initramfs-candidate-init-handoff-wiring-no-install
SOURCE_CANDIDATE=/System/Initramfs/Candidates/0026-initramfs-candidate-image-no-install/initramfs.img
ACTIVE_INITRAMFS=/System/Kernel/Current/initramfs.img
TARGET_ROOT=/System/Initramfs/Candidates/$STAGE_ID
WORK_ROOT=$TARGET_ROOT/root
TARGET_IMAGE=$TARGET_ROOT/initramfs.img
WRAPPER_SOURCE=/System/Initramfs/Prototypes/mixtar-init-wrapper.sh
MARKER=etc/mixtar-initramfs-wired-candidate

usage() {
	cat >&2 <<EOF
usage: mixtar-initramfs-init-wiring-builder <command>

commands:
  contract
  plan
  build-wired-candidate
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

contract() {
	cat <<EOF
initramfs_init_wiring_contract=no-install
builds_wired_candidate=true
installs_wired_candidate=false
overwrites_active_initramfs=false
writes_bootloader=false
switches_system_current=false
loads_overlay_module=false
mounts_overlay=false
executes_switch_root=false
source_candidate=$SOURCE_CANDIDATE
target_image=$TARGET_IMAGE
original_init_path=/init.alpine
wrapper_init_path=/init
wrapper_source=$WRAPPER_SOURCE
handoff_path=/usr/bin/mixtar-initramfs-handoff
fallback_policy=exec-init-alpine-unless-mixtar-handoff-boot-is-armed
EOF
}

plan() {
	echo "initramfs_init_wiring_plan=generated"
	echo "would_extract_source_candidate=true"
	echo "would_preserve_original_init_as=/init.alpine"
	echo "would_install_wrapper_as=/init"
	echo "would_write_marker=true"
	echo "would_pack_wired_candidate=true"
	echo "would_install_wired_candidate=false"
	echo "would_overwrite_active_initramfs=false"
	echo "would_change_bootloader=false"
	echo "would_switch_current=false"
	echo "source_candidate=$SOURCE_CANDIDATE"
	echo "target_image=$TARGET_IMAGE"
}

write_marker() {
	install -d -m 0755 "$WORK_ROOT/etc"
	cat > "$WORK_ROOT/$MARKER" <<EOF
mixtar_initramfs_wired_candidate=$STAGE_ID
source_candidate_sha256=$(hash_file "$SOURCE_CANDIDATE")
active_initramfs_sha256=$(hash_file "$ACTIVE_INITRAMFS")
wrapper_sha256=$(hash_file "$WRAPPER_SOURCE")
installs_wired_candidate=false
overwrites_active_initramfs=false
writes_bootloader=false
switches_system_current=false
EOF
}

build_wired_candidate() {
	rc=0
	echo "initramfs_init_wiring_build=generated"
	if [ "$(id -u 2>/dev/null || echo 1)" != "0" ]; then
		echo "build_error=requires-root"
		return 1
	fi
	if [ ! -f "$SOURCE_CANDIDATE" ]; then
		echo "build_error=missing-source-candidate"
		return 1
	fi
	if [ ! -x "$WRAPPER_SOURCE" ]; then
		echo "build_error=missing-wrapper-source"
		return 1
	fi
	install -d -m 0755 "$TARGET_ROOT" "$WORK_ROOT"
	(cd "$WORK_ROOT" && zcat "$SOURCE_CANDIDATE" | cpio -idmu >/dev/null 2>&1) || rc=1
	if [ -f "$WORK_ROOT/init" ]; then
		cp "$WORK_ROOT/init" "$WORK_ROOT/init.alpine" || rc=1
	else
		echo "build_error=missing-init-in-source-candidate"
		rc=1
	fi
	install -m 0755 "$WRAPPER_SOURCE" "$WORK_ROOT/init" || rc=1
	write_marker || rc=1
	(cd "$WORK_ROOT" && find . -print | cpio -o -H newc 2>/dev/null | gzip -9 > "$TARGET_IMAGE") || rc=1
	echo "target_image=$TARGET_IMAGE"
	echo "target_size_bytes=$(size_file "$TARGET_IMAGE")"
	echo "target_sha256=$(hash_file "$TARGET_IMAGE")"
	echo "source_candidate_sha256=$(hash_file "$SOURCE_CANDIDATE")"
	echo "active_sha256=$(hash_file "$ACTIVE_INITRAMFS")"
	echo "installs_wired_candidate=false"
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

image_list() {
	image=$1
	zcat "$image" 2>/dev/null | cpio -t 2>/dev/null | sed 's#^\./##'
}

list_has_path() {
	list_file=$1
	path=$2
	grep -Fx "$path" "$list_file" >/dev/null 2>&1
}

inspect() {
	list_file=/tmp/mixtar-wired-initramfs-list.$$
	rc=0
	echo "initramfs_init_wiring_inspect=generated"
	if [ ! -f "$TARGET_IMAGE" ]; then
		echo "target_present=false"
		return 1
	fi
	echo "target_present=true"
	echo "target_image=$TARGET_IMAGE"
	echo "target_size_bytes=$(size_file "$TARGET_IMAGE")"
	echo "target_sha256=$(hash_file "$TARGET_IMAGE")"
	if gzip -t "$TARGET_IMAGE" 2>/dev/null; then
		echo "target_gzip_test=ok"
	else
		echo "target_gzip_test=failed"
		rc=1
	fi
	if image_list "$TARGET_IMAGE" > "$list_file"; then
		echo "target_cpio_list=ok"
	else
		echo "target_cpio_list=failed"
		rm -f "$list_file"
		return 1
	fi
	echo "target_entry_count=$(wc -l < "$list_file" | awk '{ print $1 }')"
	for path in \
		init \
		init.alpine \
		usr/bin/mixtar-initramfs-handoff \
		System/Initramfs/Prototypes/mixtar-initramfs-handoff.sh \
		"$MARKER"
	do
		if list_has_path "$list_file" "$path"; then
			echo "target_contains=$path:true"
		else
			echo "target_contains=$path:false"
			rc=1
		fi
	done
	rm -f "$list_file"
	return "$rc"
}

extract_file_hash() {
	image=$1
	path=$2
	zcat "$image" 2>/dev/null | cpio -i --to-stdout "$path" 2>/dev/null | sha256sum | awk '{ print $1 }'
}

verify() {
	rc=0
	echo "initramfs_init_wiring_verify=generated"
	inspect || rc=1
	wrapper_hash=$(hash_file "$WRAPPER_SOURCE")
	target_init_hash=$(extract_file_hash "$TARGET_IMAGE" init)
	target_original_hash=$(extract_file_hash "$TARGET_IMAGE" init.alpine)
	source_init_hash=$(extract_file_hash "$SOURCE_CANDIDATE" init)
	echo "wrapper_sha256=$wrapper_hash"
	echo "target_init_sha256=$target_init_hash"
	echo "target_original_init_sha256=$target_original_hash"
	echo "source_candidate_init_sha256=$source_init_hash"
	if [ "$target_init_hash" = "$wrapper_hash" ] && [ "$wrapper_hash" != "missing" ]; then
		echo "wrapper_installed_as_init=true"
	else
		echo "wrapper_installed_as_init=false"
		rc=1
	fi
	if [ "$target_original_hash" = "$source_init_hash" ] && [ -n "$source_init_hash" ]; then
		echo "original_init_preserved=true"
	else
		echo "original_init_preserved=false"
		rc=1
	fi
	echo "wired_candidate_differs_from_source=$(if [ "$(hash_file "$TARGET_IMAGE")" != "$(hash_file "$SOURCE_CANDIDATE")" ]; then echo true; else echo false; fi)"
	echo "active_initramfs_unchanged_reference=$(hash_file "$ACTIVE_INITRAMFS")"
	echo "installs_wired_candidate=false"
	echo "overwrites_active_initramfs=false"
	echo "writes_bootloader=false"
	echo "switches_system_current=false"
	echo "activation_allowed=false"
	return "$rc"
}

report() {
	echo "initramfs_init_wiring_report=generated"
	contract
	plan
	verify
	echo "wired_candidate_ready=$(if verify >/dev/null 2>&1; then echo true; else echo false; fi)"
	echo "boot_test_ready=false"
	echo "boot_test_blocker=handoff script still has no real boot command"
	echo "activation_allowed=false"
	echo "next_required_stage=0029-initramfs-handoff-boot-command-no-install"
}

command=${1:-}
case "$command" in
	contract)
		contract
		;;
	plan)
		plan
		;;
	build-wired-candidate)
		build_wired_candidate
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
