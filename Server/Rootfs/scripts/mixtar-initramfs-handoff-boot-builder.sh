#!/bin/sh
set -u

STAGE_ID=0029-initramfs-handoff-boot-command-no-install
SOURCE_CANDIDATE=/System/Initramfs/Candidates/0028-initramfs-candidate-init-handoff-wiring-no-install/initramfs.img
ACTIVE_INITRAMFS=/System/Kernel/Current/initramfs.img
TARGET_ROOT=/System/Initramfs/Candidates/$STAGE_ID
WORK_ROOT=$TARGET_ROOT/root
TARGET_IMAGE=$TARGET_ROOT/initramfs.img
HANDOFF_SOURCE=/System/Initramfs/Prototypes/mixtar-initramfs-handoff.sh
MARKER=etc/mixtar-initramfs-handoff-boot-candidate

usage() {
	cat >&2 <<EOF
usage: mixtar-initramfs-handoff-boot-builder <command>

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

contract() {
	cat <<EOF
initramfs_handoff_boot_builder_contract=no-install
builds_handoff_boot_candidate=true
installs_handoff_boot_candidate=false
overwrites_active_initramfs=false
writes_bootloader=false
switches_system_current=false
loads_overlay_module=false
mounts_overlay=false
executes_switch_root_during_build=false
source_candidate=$SOURCE_CANDIDATE
target_image=$TARGET_IMAGE
handoff_source=$HANDOFF_SOURCE
handoff_targets=usr/bin/mixtar-initramfs-handoff System/Initramfs/Prototypes/mixtar-initramfs-handoff.sh
EOF
}

plan() {
	echo "initramfs_handoff_boot_plan=generated"
	echo "would_extract_source_candidate=true"
	echo "would_replace_usr_bin_handoff=true"
	echo "would_replace_prototype_handoff=true"
	echo "would_write_marker=true"
	echo "would_pack_handoff_boot_candidate=true"
	echo "would_install_handoff_boot_candidate=false"
	echo "would_overwrite_active_initramfs=false"
	echo "would_change_bootloader=false"
	echo "would_switch_current=false"
	echo "source_candidate=$SOURCE_CANDIDATE"
	echo "target_image=$TARGET_IMAGE"
}

write_marker() {
	install -d -m 0755 "$WORK_ROOT/etc"
	cat > "$WORK_ROOT/$MARKER" <<EOF
mixtar_initramfs_handoff_boot_candidate=$STAGE_ID
source_candidate_sha256=$(hash_file "$SOURCE_CANDIDATE")
active_initramfs_sha256=$(hash_file "$ACTIVE_INITRAMFS")
handoff_source_sha256=$(hash_file "$HANDOFF_SOURCE")
installs_handoff_boot_candidate=false
overwrites_active_initramfs=false
writes_bootloader=false
switches_system_current=false
EOF
}

build_candidate() {
	rc=0
	echo "initramfs_handoff_boot_build=generated"
	if [ "$(id -u 2>/dev/null || echo 1)" != "0" ]; then
		echo "build_error=requires-root"
		return 1
	fi
	if [ ! -f "$SOURCE_CANDIDATE" ]; then
		echo "build_error=missing-source-candidate"
		return 1
	fi
	if [ ! -x "$HANDOFF_SOURCE" ]; then
		echo "build_error=missing-handoff-source"
		return 1
	fi
	install -d -m 0755 "$TARGET_ROOT" "$WORK_ROOT"
	(cd "$WORK_ROOT" && zcat "$SOURCE_CANDIDATE" | cpio -idmu >/dev/null 2>&1) || rc=1
	install -d -m 0755 "$WORK_ROOT/usr/bin" "$WORK_ROOT/System/Initramfs/Prototypes"
	install -m 0755 "$HANDOFF_SOURCE" "$WORK_ROOT/usr/bin/mixtar-initramfs-handoff" || rc=1
	install -m 0755 "$HANDOFF_SOURCE" "$WORK_ROOT/System/Initramfs/Prototypes/mixtar-initramfs-handoff.sh" || rc=1
	write_marker || rc=1
	(cd "$WORK_ROOT" && find . -print | cpio -o -H newc 2>/dev/null | gzip -9 > "$TARGET_IMAGE") || rc=1
	echo "target_image=$TARGET_IMAGE"
	echo "target_size_bytes=$(size_file "$TARGET_IMAGE")"
	echo "target_sha256=$(hash_file "$TARGET_IMAGE")"
	echo "source_candidate_sha256=$(hash_file "$SOURCE_CANDIDATE")"
	echo "active_sha256=$(hash_file "$ACTIVE_INITRAMFS")"
	echo "handoff_source_sha256=$(hash_file "$HANDOFF_SOURCE")"
	echo "installs_handoff_boot_candidate=false"
	echo "overwrites_active_initramfs=false"
	echo "writes_bootloader=false"
	echo "switches_system_current=false"
	echo "loads_overlay_module=false"
	echo "mounts_overlay=false"
	echo "executes_switch_root_during_build=false"
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

extract_file() {
	image=$1
	path=$2
	target=$3
	zcat "$image" 2>/dev/null | cpio -i --to-stdout "$path" 2>/dev/null > "$target"
}

extract_file_hash() {
	image=$1
	path=$2
	zcat "$image" 2>/dev/null | cpio -i --to-stdout "$path" 2>/dev/null | sha256sum | awk '{ print $1 }'
}

inspect() {
	list_file=/tmp/mixtar-handoff-boot-list.$$
	rc=0
	echo "initramfs_handoff_boot_inspect=generated"
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

verify() {
	rc=0
	tmp_handoff=/tmp/mixtar-handoff-boot.$$
	tmp_contract=/tmp/mixtar-handoff-boot-contract.$$
	echo "initramfs_handoff_boot_verify=generated"
	inspect || rc=1
	extract_file "$TARGET_IMAGE" usr/bin/mixtar-initramfs-handoff "$tmp_handoff" || rc=1
	chmod 0755 "$tmp_handoff" 2>/dev/null || true
	if sh "$tmp_handoff" contract > "$tmp_contract" 2>&1; then
		echo "target_handoff_contract_runs=true"
	else
		echo "target_handoff_contract_runs=false"
		rc=1
	fi
	cat "$tmp_contract"
	source_hash=$(hash_file "$HANDOFF_SOURCE")
	target_bin_hash=$(extract_file_hash "$TARGET_IMAGE" usr/bin/mixtar-initramfs-handoff)
	target_proto_hash=$(extract_file_hash "$TARGET_IMAGE" System/Initramfs/Prototypes/mixtar-initramfs-handoff.sh)
	echo "handoff_source_sha256=$source_hash"
	echo "target_usr_bin_handoff_sha256=$target_bin_hash"
	echo "target_prototype_handoff_sha256=$target_proto_hash"
	if [ "$source_hash" = "$target_bin_hash" ] && [ "$source_hash" = "$target_proto_hash" ]; then
		echo "handoff_hash_match=true"
	else
		echo "handoff_hash_match=false"
		rc=1
	fi
	if grep -F 'boot_command_available=true' "$tmp_contract" >/dev/null 2>&1; then
		echo "boot_command_available=true"
	else
		echo "boot_command_available=false"
		rc=1
	fi
	if grep -F 'executes_switch_root_when_boot_command_runs=true' "$tmp_contract" >/dev/null 2>&1; then
		echo "boot_executes_switch_root_when_run=true"
	else
		echo "boot_executes_switch_root_when_run=false"
		rc=1
	fi
	echo "target_differs_from_source=$(if [ "$(hash_file "$TARGET_IMAGE")" != "$(hash_file "$SOURCE_CANDIDATE")" ]; then echo true; else echo false; fi)"
	echo "active_initramfs_unchanged_reference=$(hash_file "$ACTIVE_INITRAMFS")"
	echo "installs_handoff_boot_candidate=false"
	echo "overwrites_active_initramfs=false"
	echo "writes_bootloader=false"
	echo "switches_system_current=false"
	echo "activation_allowed=false"
	rm -f "$tmp_handoff" "$tmp_contract"
	return "$rc"
}

report() {
	echo "initramfs_handoff_boot_report=generated"
	contract
	plan
	verify
	echo "handoff_boot_candidate_ready=$(if verify >/dev/null 2>&1; then echo true; else echo false; fi)"
	echo "boot_entry_ready=false"
	echo "boot_entry_blocker=candidate not copied to ESP and no fallback BootNext plan executed"
	echo "activation_allowed=false"
	echo "next_required_stage=0030-esp-candidate-copy-plan-no-activation"
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
