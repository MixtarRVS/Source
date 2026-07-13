#!/bin/sh
set -eu

STAGE_ID=0041-initramfs-binsh-fix-no-install
SOURCE_CANDIDATE=/System/Initramfs/Candidates/0038-init-wrapper-pathlog-no-install/initramfs.img
TARGET_DIR=/System/Initramfs/Candidates/0041-initramfs-binsh-fix-no-install
TARGET_IMAGE=$TARGET_DIR/initramfs.img
MARKER=etc/mixtar-initramfs-binsh-fix

hash_file() { [ -f "$1" ] && sha256sum "$1" | awk '{print $1}' || echo missing; }
size_file() { [ -f "$1" ] && wc -c "$1" | awk '{print $1}' || echo 0; }

contract() {
	cat <<EOF
stage=$STAGE_ID
purpose=add_bin_sh_compatibility_for_init_shebang
source_candidate=$SOURCE_CANDIDATE
target_image=$TARGET_IMAGE
builds_candidate_initramfs=true
installs_candidate_initramfs=false
copies_candidate_to_esp=false
creates_boot_entry=false
sets_boot_next=false
reboots_system=false
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
	work=/tmp/mixtar-initramfs-binsh-fix.$$
	rm -rf "$work"
	mkdir -p "$work" "$TARGET_DIR"
	trap 'rm -rf "$work"' EXIT INT TERM
	cd "$work"
	gzip -dc "$SOURCE_CANDIDATE" | cpio -id --quiet
	if [ ! -e bin ]; then
		ln -s usr/bin bin
	elif [ -d bin ] && [ ! -e bin/sh ]; then
		ln -s ../usr/bin/sh bin/sh
	fi
	mkdir -p etc
	cat > "$MARKER" <<EOF
stage=$STAGE_ID
source_candidate_sha256=$(hash_file "$SOURCE_CANDIDATE")
bin_fix=bin-to-usr-bin-or-bin-sh-symlink
EOF
	find . -print | cpio -o -H newc --quiet | gzip -9 > "$TARGET_IMAGE"
	cd /
	echo "status=built"
	echo "source_candidate_sha256=$(hash_file "$SOURCE_CANDIDATE")"
	echo "target_image=$TARGET_IMAGE"
	echo "target_size_bytes=$(size_file "$TARGET_IMAGE")"
	echo "target_sha256=$(hash_file "$TARGET_IMAGE")"
	echo "installs_candidate_initramfs=false"
	echo "copies_candidate_to_esp=false"
}

verify() {
	rc=0
	echo "stage=$STAGE_ID"
	echo "verify=generated"
	tmp=/tmp/mixtar-initramfs-binsh-fix-verify.$$
	rm -rf "$tmp"
	mkdir -p "$tmp"
	cd "$tmp"
	if gzip -dc "$TARGET_IMAGE" 2>/dev/null | cpio -id --quiet init bin usr/bin/sh "$MARKER" 2>/dev/null; then
		echo "extract_for_verify=ok"
	else
		echo "extract_for_verify=failed"
		rc=1
	fi
	if [ -e bin/sh ] || { [ -L bin ] && [ -e bin/sh ]; }; then
		echo "bin_sh_resolves=true"
	else
		echo "bin_sh_resolves=false"
		rc=1
	fi
	if [ -x usr/bin/sh ]; then
		echo "usr_bin_sh_executable=true"
	else
		echo "usr_bin_sh_executable=false"
		rc=1
	fi
	if head -1 init | grep -Fx '#!/bin/sh' >/dev/null 2>&1; then
		echo "init_shebang_bin_sh=true"
	else
		echo "init_shebang_bin_sh=false"
		rc=1
	fi
	if grep -F '<3>mixtar-init:' init >/dev/null 2>&1; then
		echo "wrapper_priority_logs_present=true"
	else
		echo "wrapper_priority_logs_present=false"
		rc=1
	fi
	cd /
	rm -rf "$tmp"
	echo "verify_result=$(if [ "$rc" -eq 0 ]; then echo ok; else echo failed; fi)"
	return "$rc"
}

report() {
	echo "stage=$STAGE_ID"
	echo "candidate_ready=$(if verify >/dev/null 2>&1; then echo true; else echo false; fi)"
	echo "target_image=$TARGET_IMAGE"
	echo "target_sha256=$(hash_file "$TARGET_IMAGE")"
	echo "next_required_stage=0042-copy-binsh-fix-candidate-to-esp-no-active-switch"
}

case "${1:-}" in
	contract) contract ;;
	build-candidate) build_candidate ;;
	verify) verify ;;
	report) report ;;
	*) echo "usage: $0 [contract|build-candidate|verify|report]" >&2; exit 2 ;;
esac
