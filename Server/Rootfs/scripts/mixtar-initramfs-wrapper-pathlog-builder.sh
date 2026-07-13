#!/bin/sh
set -eu

STAGE_ID=0038-init-wrapper-pathlog-no-install
SOURCE_CANDIDATE=/System/Initramfs/Candidates/0035-initramfs-wrapper-procfix-no-install/initramfs.img
TARGET_DIR=/System/Initramfs/Candidates/0038-init-wrapper-pathlog-no-install
TARGET_IMAGE=$TARGET_DIR/initramfs.img
WRAPPER_SOURCE=/System/Initramfs/Prototypes/mixtar-init-wrapper-pathlog.sh
HANDOFF_SOURCE=/System/Initramfs/Prototypes/mixtar-initramfs-handoff-pathlog.sh
HANDOFF_TARGET=usr/bin/mixtar-initramfs-handoff
HANDOFF_PROTO_TARGET=System/Initramfs/Prototypes/mixtar-initramfs-handoff.sh
MARKER=etc/mixtar-initramfs-wrapper-pathlog

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

contract() {
	cat <<EOF
stage=$STAGE_ID
purpose=rebuild_candidate_with_explicit_initramfs_path_and_kernel_priority_logs
source_candidate=$SOURCE_CANDIDATE
target_image=$TARGET_IMAGE
wrapper_source=$WRAPPER_SOURCE
handoff_source=$HANDOFF_SOURCE
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
step01=extract 0035 source candidate
step02=replace /init with PATH-aware wrapper
step03=replace handoff tool with PATH-aware high-priority logger version
step04=write marker
step05=repack gzip cpio newc image
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
	for path in "$SOURCE_CANDIDATE" "$WRAPPER_SOURCE" "$HANDOFF_SOURCE"; do
		if [ ! -f "$path" ]; then
			echo "status=failed"
			echo "reason=missing_input:$path"
			return 1
		fi
	done
	work=/tmp/mixtar-initramfs-wrapper-pathlog.$$
	rm -rf "$work"
	mkdir -p "$work" "$TARGET_DIR"
	trap 'rm -rf "$work"' EXIT INT TERM
	cd "$work"
	gzip -dc "$SOURCE_CANDIDATE" | cpio -id --quiet
	cp "$WRAPPER_SOURCE" init
	chmod 0755 init
	mkdir -p "$(dirname "$HANDOFF_TARGET")" "$(dirname "$HANDOFF_PROTO_TARGET")" etc
	cp "$HANDOFF_SOURCE" "$HANDOFF_TARGET"
	cp "$HANDOFF_SOURCE" "$HANDOFF_PROTO_TARGET"
	chmod 0755 "$HANDOFF_TARGET" "$HANDOFF_PROTO_TARGET"
	cat > "$MARKER" <<EOF
stage=$STAGE_ID
source_candidate_sha256=$(hash_file "$SOURCE_CANDIDATE")
wrapper_source_sha256=$(hash_file "$WRAPPER_SOURCE")
handoff_source_sha256=$(hash_file "$HANDOFF_SOURCE")
EOF
	find . -print | cpio -o -H newc --quiet | gzip -9 > "$TARGET_IMAGE"
	cd /
	echo "status=built"
	echo "source_candidate_sha256=$(hash_file "$SOURCE_CANDIDATE")"
	echo "wrapper_source_sha256=$(hash_file "$WRAPPER_SOURCE")"
	echo "handoff_source_sha256=$(hash_file "$HANDOFF_SOURCE")"
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
	list=/tmp/mixtar-initramfs-wrapper-pathlog-list.$$
	gzip -dc "$TARGET_IMAGE" 2>/dev/null | cpio -it 2>/dev/null > "$list"
	echo "candidate_entry_count=$(wc -l < "$list" | awk '{ print $1 }')"
	for path in init init.alpine "$HANDOFF_TARGET" "$HANDOFF_PROTO_TARGET" "$MARKER"; do
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
	tmp=/tmp/mixtar-initramfs-wrapper-pathlog-verify.$$
	rm -rf "$tmp"
	mkdir -p "$tmp"
	cd "$tmp"
	if gzip -dc "$TARGET_IMAGE" 2>/dev/null | cpio -id --quiet init "$HANDOFF_TARGET" "$MARKER" 2>/dev/null; then
		echo "extract_for_verify=ok"
	else
		echo "extract_for_verify=failed"
		rc=1
	fi
	if grep -F 'PATH=/sbin:/bin:/usr/sbin:/usr/bin' init >/dev/null 2>&1; then
		echo "wrapper_has_explicit_path=true"
	else
		echo "wrapper_has_explicit_path=false"
		rc=1
	fi
	if grep -F '<3>mixtar-init:' init >/dev/null 2>&1; then
		echo "wrapper_has_kernel_priority_logs=true"
	else
		echo "wrapper_has_kernel_priority_logs=false"
		rc=1
	fi
	if grep -F 'PATH=/sbin:/bin:/usr/sbin:/usr/bin' "$HANDOFF_TARGET" >/dev/null 2>&1; then
		echo "handoff_has_explicit_path=true"
	else
		echo "handoff_has_explicit_path=false"
		rc=1
	fi
	if grep -F '<3>mixtar-handoff:' "$HANDOFF_TARGET" >/dev/null 2>&1; then
		echo "handoff_has_kernel_priority_logs=true"
	else
		echo "handoff_has_kernel_priority_logs=false"
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
	echo "next_required_stage=0039-copy-pathlog-candidate-to-esp-no-active-switch"
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
		echo "usage: $0 [contract|plan|build-candidate|inspect|verify|report]" >&2
		exit 2
		;;
esac
