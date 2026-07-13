#!/bin/sh
set -u

STAGE=0028-initramfs-candidate-init-handoff-wiring-no-install
BASE=/System/Base/Closure/$STAGE
BUILDER_NAME=mixtar-initramfs-init-wiring-builder.sh
WRAPPER_NAME=mixtar-init-wrapper.sh
BUILDER_TARGET=/System/Initramfs/Prototypes/mixtar-initramfs-init-wiring-builder.sh
WRAPPER_TARGET=/System/Initramfs/Prototypes/mixtar-init-wrapper.sh
INITRAMFS=/System/Kernel/Current/initramfs.img
MOUNT_POINT=/System/Runtime/Inspect/rootfs-0015

script_dir() {
	dir=$(dirname "$0")
	cd "$dir" 2>/dev/null && pwd
}

source_file() {
	name=$1
	dir=$(script_dir)
	if [ -f "$dir/$name" ]; then
		printf '%s/%s\n' "$dir" "$name"
		return 0
	fi
	if [ -f "/tmp/$name" ]; then
		printf '/tmp/%s\n' "$name"
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
MixtarRVS initramfs init handoff wiring, stage 0028

Installed non-boot tools:
  $BUILDER_TARGET
  $WRAPPER_TARGET

This stage is non-activating:
  wired candidate initramfs is built outside active kernel profile
  active initramfs is not overwritten
  bootloader state is not changed
  /System/Current is not switched
EOF
}

write_summary() {
	cat > "$BASE/initramfs-init-handoff-wiring-summary.txt" <<EOF
initramfs_init_handoff_wiring_status=generated
builder_target=$BUILDER_TARGET
wrapper_target=$WRAPPER_TARGET
target_image=$(value_from_file "$BASE/build-wired-candidate.txt" target_image)
target_size_bytes=$(value_from_file "$BASE/build-wired-candidate.txt" target_size_bytes)
target_sha256=$(value_from_file "$BASE/build-wired-candidate.txt" target_sha256)
source_candidate_sha256=$(value_from_file "$BASE/build-wired-candidate.txt" source_candidate_sha256)
target_gzip_test=$(value_from_file "$BASE/inspect.txt" target_gzip_test)
target_cpio_list=$(value_from_file "$BASE/inspect.txt" target_cpio_list)
wrapper_installed_as_init=$(value_from_file "$BASE/verify.txt" wrapper_installed_as_init)
original_init_preserved=$(value_from_file "$BASE/verify.txt" original_init_preserved)
wired_candidate_ready=$(value_from_file "$BASE/report.txt" wired_candidate_ready)
boot_test_ready=$(value_from_file "$BASE/report.txt" boot_test_ready)
activation_allowed=$(value_from_file "$BASE/report.txt" activation_allowed)
active_initramfs_hash_before=$(cat "$BASE/initramfs-hash-before.txt" 2>/dev/null || true)
active_initramfs_hash_after=$(hash_file "$INITRAMFS")
current_before=$(cat "$BASE/system-current-before.txt" 2>/dev/null || true)
current_after=$(readlink /System/Current 2>/dev/null || true)
mount_after=$(if is_mounted; then echo present; else echo absent; fi)
next_required_stage=0029-initramfs-handoff-boot-command-no-install
EOF
}

verify_stage() {
	rc=0
	for file in contract.txt plan.txt build-wired-candidate.txt inspect.txt verify.txt report.txt initramfs-init-handoff-wiring-summary.txt; do
		if [ ! -s "$BASE/$file" ]; then
			printf 'verify: missing report: %s\n' "$file" >&2
			rc=1
		fi
	done
	for token in \
		'installs_wired_candidate=false' \
		'overwrites_active_initramfs=false' \
		'writes_bootloader=false' \
		'switches_system_current=false'
	do
		if ! grep -F "$token" "$BASE/contract.txt" >/dev/null 2>&1; then
			printf 'verify: contract missing token: %s\n' "$token" >&2
			rc=1
		fi
	done
	for token in \
		'build_result=created' \
		'installs_wired_candidate=false' \
		'overwrites_active_initramfs=false' \
		'writes_bootloader=false' \
		'switches_system_current=false'
	do
		if ! grep -F "$token" "$BASE/build-wired-candidate.txt" >/dev/null 2>&1; then
			printf 'verify: build missing token: %s\n' "$token" >&2
			rc=1
		fi
	done
	for token in \
		'target_present=true' \
		'target_gzip_test=ok' \
		'target_cpio_list=ok' \
		'target_contains=init:true' \
		'target_contains=init.alpine:true' \
		'target_contains=usr/bin/mixtar-initramfs-handoff:true' \
		'target_contains=etc/mixtar-initramfs-wired-candidate:true'
	do
		if ! grep -F "$token" "$BASE/inspect.txt" >/dev/null 2>&1; then
			printf 'verify: inspect missing token: %s\n' "$token" >&2
			rc=1
		fi
	done
	for token in \
		'wrapper_installed_as_init=true' \
		'original_init_preserved=true' \
		'wired_candidate_differs_from_source=true' \
		'activation_allowed=false'
	do
		if ! grep -F "$token" "$BASE/verify.txt" >/dev/null 2>&1; then
			printf 'verify: verify report missing token: %s\n' "$token" >&2
			rc=1
		fi
	done
	for token in \
		'wired_candidate_ready=true' \
		'boot_test_ready=false' \
		'activation_allowed=false' \
		'next_required_stage=0029-initramfs-handoff-boot-command-no-install'
	do
		if ! grep -F "$token" "$BASE/report.txt" >/dev/null 2>&1; then
			printf 'verify: report missing token: %s\n' "$token" >&2
			rc=1
		fi
	done
	before_hash=$(cat "$BASE/initramfs-hash-before.txt" 2>/dev/null || true)
	after_hash=$(hash_file "$INITRAMFS")
	if [ "$before_hash" != "$after_hash" ]; then
		printf 'verify: active initramfs hash changed from %s to %s\n' "$before_hash" "$after_hash" >&2
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
	builder=$(source_file "$BUILDER_NAME") || return 1
	wrapper=$(source_file "$WRAPPER_NAME") || return 1
	install -d -m 0755 "$BASE" /System/Initramfs/Prototypes
	readlink /System/Current 2>/dev/null > "$BASE/system-current-before.txt" || true
	hash_file "$INITRAMFS" > "$BASE/initramfs-hash-before.txt"
	if is_mounted; then
		printf 'stage: mountpoint already mounted before init handoff wiring: %s\n' "$MOUNT_POINT" >&2
		return 1
	fi
	if [ "$builder" != "$BASE/$BUILDER_NAME" ]; then
		install -m 0755 "$builder" "$BASE/$BUILDER_NAME"
	fi
	if [ "$wrapper" != "$BASE/$WRAPPER_NAME" ]; then
		install -m 0755 "$wrapper" "$BASE/$WRAPPER_NAME"
	fi
	install -m 0755 "$builder" "$BUILDER_TARGET"
	install -m 0755 "$wrapper" "$WRAPPER_TARGET"
	write_contract > "$BASE/stage-contract.txt"
	"$BUILDER_TARGET" contract > "$BASE/contract.txt" 2>&1
	"$BUILDER_TARGET" plan > "$BASE/plan.txt" 2>&1
	"$BUILDER_TARGET" build-wired-candidate > "$BASE/build-wired-candidate.txt" 2>&1
	"$BUILDER_TARGET" inspect > "$BASE/inspect.txt" 2>&1
	"$BUILDER_TARGET" verify > "$BASE/verify.txt" 2>&1
	"$BUILDER_TARGET" report > "$BASE/report.txt" 2>&1
	write_summary
	if verify_stage; then
		printf 'verified\n' > "$BASE/initramfs-candidate-init-handoff-wiring-no-install-status.txt"
	else
		printf 'incomplete\n' > "$BASE/initramfs-candidate-init-handoff-wiring-no-install-status.txt"
		return 1
	fi
}

mode=${1:-}
if [ -z "$mode" ]; then
	mode=--verify
fi

case "$mode" in
	--verify)
		verify_stage
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
