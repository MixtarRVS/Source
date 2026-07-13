#!/bin/sh
set -eu

STAGE_ID=0035-initramfs-wrapper-procfix-no-install
SOURCE_CANDIDATE=/System/Initramfs/Candidates/0029-initramfs-handoff-boot-command-no-install/initramfs.img
TARGET_DIR=/System/Initramfs/Candidates/0035-initramfs-wrapper-procfix-no-install
TARGET_IMAGE=$TARGET_DIR/initramfs.img
WRAPPER_SOURCE=/System/Initramfs/Prototypes/mixtar-init-wrapper-procfix.sh
MARKER=etc/mixtar-initramfs-wrapper-procfix

usage() {
	cat >&2 <<EOF
usage: mixtar-initramfs-wrapper-procfix-builder <command>

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
		sha256sum "$path" | awk '{ print $1 }'
	else
		echo missing
	fi
}

size_file() {
	path=$1
	if [ -f "$path" ]; then
		wc -c "$path" | awk '{ print $1 }'
	else
		echo 0
	fi
}

list_image() {
	gzip -dc "$TARGET_IMAGE" 2>/dev/null | cpio -it 2>/dev/null
}

contract() {
	cat <<EOF
stage=$STAGE_ID
purpose=rebuild_candidate_with_init_wrapper_proc_mount_fix
source_candidate=$SOURCE_CANDIDATE
target_image=$TARGET_IMAGE
wrapper_source=$WRAPPER_SOURCE
builds_candidate_initramfs=true
installs_candidate_initramfs=false
copies_candidate_to_esp=false
creates_boot_entry=false
sets_boot_next=false
reboots_system=false
EOF
}

plan() {
	cat <<EOF
stage=$STAGE_ID
status=planned
step01=extract source candidate 0029 into temporary directory
step02=replace /init with fixed Mixtar wrapper
step03=keep /init.alpine as fallback
step04=write procfix marker
step05=repack gzip cpio newc image as $TARGET_IMAGE
step06=verify wrapper and handoff payload remain present
would_install_active_initramfs=false
would_copy_to_esp=false
would_create_boot_entry=false
would_set_bootnext=false
would_reboot=false
EOF
}

build_candidate() {
	echo "stage=$STAGE_ID"
	echo "build=started"
	if [ ! -f "$SOURCE_CANDIDATE" ]; then
		echo "status=failed"
		echo "reason=missing_source_candidate"
		return 1
	fi
	if [ ! -f "$WRAPPER_SOURCE" ]; then
		echo "status=failed"
		echo "reason=missing_wrapper_source"
		return 1
	fi

	work=/tmp/mixtar-initramfs-wrapper-procfix.$$
	rm -rf "$work"
	mkdir -p "$work" "$TARGET_DIR"
	trap 'rm -rf "$work"' EXIT INT TERM

	cd "$work"
	gzip -dc "$SOURCE_CANDIDATE" | cpio -id --quiet
	cp "$WRAPPER_SOURCE" init
	chmod 0755 init
	mkdir -p etc
	cat > "$MARKER" <<EOF
stage=$STAGE_ID
source_candidate_sha256=$(hash_file "$SOURCE_CANDIDATE")
wrapper_source_sha256=$(hash_file "$WRAPPER_SOURCE")
EOF
	find . -print | cpio -o -H newc --quiet | gzip -9 > "$TARGET_IMAGE"
	cd /

	echo "status=built"
	echo "source_candidate=$SOURCE_CANDIDATE"
	echo "source_candidate_sha256=$(hash_file "$SOURCE_CANDIDATE")"
	echo "wrapper_source_sha256=$(hash_file "$WRAPPER_SOURCE")"
	echo "target_image=$TARGET_IMAGE"
	echo "target_size_bytes=$(size_file "$TARGET_IMAGE")"
	echo "target_sha256=$(hash_file "$TARGET_IMAGE")"
	echo "installs_candidate_initramfs=false"
	echo "copies_candidate_to_esp=false"
}

inspect() {
	echo "stage=$STAGE_ID"
	echo "inspect=generated"
	if [ ! -f "$TARGET_IMAGE" ]; then
		echo "candidate_present=false"
		return 1
	fi
	echo "candidate_present=true"
	echo "candidate_image=$TARGET_IMAGE"
	echo "candidate_size_bytes=$(size_file "$TARGET_IMAGE")"
	echo "candidate_sha256=$(hash_file "$TARGET_IMAGE")"
	if gzip -t "$TARGET_IMAGE" 2>/dev/null; then
		echo "candidate_gzip_test=ok"
	else
		echo "candidate_gzip_test=failed"
	fi
	list=/tmp/mixtar-initramfs-wrapper-procfix-list.$$
	if list_image > "$list"; then
		echo "candidate_cpio_list=ok"
	else
		echo "candidate_cpio_list=failed"
	fi
	echo "candidate_entry_count=$(wc -l < "$list" | awk '{ print $1 }')"
	for path in init init.alpine usr/bin/mixtar-initramfs-handoff "$MARKER"; do
		if grep -Fx "$path" "$list" >/dev/null 2>&1 || grep -Fx "./$path" "$list" >/dev/null 2>&1; then
			echo "candidate_contains=$path:true"
		else
			echo "candidate_contains=$path:false"
		fi
	done
	rm -f "$list"
}

verify() {
	rc=0
	echo "stage=$STAGE_ID"
	echo "verify=generated"
	inspect || rc=1
	tmp=/tmp/mixtar-initramfs-wrapper-procfix-verify.$$
	rm -rf "$tmp"
	mkdir -p "$tmp"
	cd "$tmp"
	if gzip -dc "$TARGET_IMAGE" 2>/dev/null | cpio -id --quiet init "$MARKER" 2>/dev/null; then
		echo "extract_for_verify=ok"
	else
		echo "extract_for_verify=failed"
		rc=1
	fi
	if grep -F "mount_early_runtime_filesystems" init >/dev/null 2>&1; then
		echo "wrapper_has_early_mount_function=true"
	else
		echo "wrapper_has_early_mount_function=false"
		rc=1
	fi
	mount_call_line=$(grep -n '^mount_early_runtime_filesystems$' init 2>/dev/null | cut -d: -f1 | sed -n '1p')
	cmd_parse_line=$(grep -n 'rootfs=$(cmdline_value mixtar.rootfs' init 2>/dev/null | cut -d: -f1 | sed -n '1p')
	if [ -n "$mount_call_line" ] &&
	   [ -n "$cmd_parse_line" ] &&
	   [ "$mount_call_line" -lt "$cmd_parse_line" ]; then
		echo "wrapper_mounts_before_cmdline_parse=true"
	else
		echo "wrapper_mounts_before_cmdline_parse=false"
		rc=1
	fi
	if grep -F 'exec "$ORIGINAL_INIT"' init >/dev/null 2>&1; then
		echo "fallback_exec_has_no_error_argument=true"
	else
		echo "fallback_exec_has_no_error_argument=false"
		rc=1
	fi
	cd /
	rm -rf "$tmp"
	echo "verify_result=$(if [ "$rc" -eq 0 ]; then echo ok; else echo failed; fi)"
	return "$rc"
}

report() {
	echo "stage=$STAGE_ID"
	echo "report=generated"
	echo "candidate_ready=$(if verify >/dev/null 2>&1; then echo true; else echo false; fi)"
	echo "target_image=$TARGET_IMAGE"
	echo "target_sha256=$(hash_file "$TARGET_IMAGE")"
	echo "next_required_stage=0036-copy-procfix-candidate-to-esp-no-active-switch"
}

case "${1:-}" in
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
