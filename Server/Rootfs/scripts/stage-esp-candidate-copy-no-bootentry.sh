#!/bin/sh
set -u

STAGE=0031-esp-candidate-copy-no-bootentry
BASE=/System/Base/Closure/$STAGE
TOOL_NAME=mixtar-esp-candidate-copy.sh
TOOL_TARGET=/System/Initramfs/Prototypes/mixtar-esp-candidate-copy.sh
INITRAMFS=/System/Kernel/Current/initramfs.img
MOUNT_POINT=/System/Runtime/Inspect/rootfs-0015

script_dir() {
	dir=$(dirname "$0")
	cd "$dir" 2>/dev/null && pwd
}

tool_source() {
	dir=$(script_dir)
	if [ -f "$dir/$TOOL_NAME" ]; then
		printf '%s/%s\n' "$dir" "$TOOL_NAME"
		return 0
	fi
	if [ -f "/tmp/$TOOL_NAME" ]; then
		printf '/tmp/%s\n' "$TOOL_NAME"
		return 0
	fi
	return 1
}

is_mounted() {
	awk -v mount_point="$MOUNT_POINT" '$2 == mount_point { found = 1 } END { exit found ? 0 : 1 }' /proc/mounts 2>/dev/null
}

esp_mounted() {
	awk '$2 ~ /^\/boot\/efi$|^\/efi$|^\/System\/Runtime\/ESP/ { found = 1 } END { exit found ? 0 : 1 }' /proc/mounts 2>/dev/null
}

hash_file() {
	path=$1
	if [ -f "$path" ]; then
		sha256sum "$path" 2>/dev/null | awk '{ print $1 }'
	else
		echo missing
	fi
}

boot_state() {
	if command -v efibootmgr >/dev/null 2>&1; then
		efibootmgr 2>/dev/null | awk '/^BootCurrent:/ || /^BootOrder:/ { print }'
	fi
}

value_from_file() {
	file=$1
	key=$2
	awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$file"
}

write_contract() {
	cat <<EOF
MixtarRVS ESP candidate copy, stage 0031

Installed copy tool:
  $TOOL_TARGET

This stage is copy-only:
  ESP is mounted temporarily
  candidate is copied under a unique filename
  copied hash is verified
  ESP is unmounted
  EFI boot entry is not written
  BootOrder is not changed
  BootNext is not set
EOF
}

write_summary() {
	cat > "$BASE/esp-candidate-copy-summary.txt" <<EOF
esp_candidate_copy_status=generated
tool_target=$TOOL_TARGET
copy_status=$(value_from_file "$BASE/copy.txt" copy_status)
target_path=$(value_from_file "$BASE/verify-copy.txt" target_path)
source_sha256=$(value_from_file "$BASE/verify-copy.txt" source_sha256)
target_sha256=$(value_from_file "$BASE/verify-copy.txt" target_sha256)
copy_hash_match=$(value_from_file "$BASE/verify-copy.txt" copy_hash_match)
source_size_bytes=$(value_from_file "$BASE/verify-copy.txt" source_size_bytes)
target_size_bytes=$(value_from_file "$BASE/verify-copy.txt" target_size_bytes)
esp_mounted_before=$(cat "$BASE/esp-mounted-before.txt" 2>/dev/null || true)
esp_mounted_after=$(if esp_mounted; then echo true; else echo false; fi)
boot_state_before=$(cat "$BASE/boot-state-before.txt" 2>/dev/null | tr '\n' ';' || true)
boot_state_after=$(boot_state | tr '\n' ';')
active_initramfs_hash_before=$(cat "$BASE/initramfs-hash-before.txt" 2>/dev/null || true)
active_initramfs_hash_after=$(hash_file "$INITRAMFS")
current_before=$(cat "$BASE/system-current-before.txt" 2>/dev/null || true)
current_after=$(readlink /System/Current 2>/dev/null || true)
mount_after=$(if is_mounted; then echo present; else echo absent; fi)
writes_boot_entry=false
changes_boot_order=false
sets_boot_next=false
activation_allowed=false
next_required_stage=0032-efi-boot-entry-plan-with-bootnext
EOF
}

verify_stage() {
	rc=0
	for file in contract.txt plan.txt copy.txt verify-copy.txt report.txt esp-candidate-copy-summary.txt; do
		if [ ! -s "$BASE/$file" ]; then
			printf 'verify: missing report: %s\n' "$file" >&2
			rc=1
		fi
	done
	for token in \
		'copies_candidate_to_esp=true' \
		'writes_boot_entry=false' \
		'changes_boot_order=false' \
		'sets_boot_next=false' \
		'overwrites_active_initrd=false' \
		'switches_system_current=false'
	do
		if ! grep -F "$token" "$BASE/contract.txt" >/dev/null 2>&1; then
			printf 'verify: contract missing token: %s\n' "$token" >&2
			rc=1
		fi
	done
	if grep -F 'copy_status=copied' "$BASE/copy.txt" >/dev/null 2>&1 || grep -F 'copy_status=already-present-same-hash' "$BASE/copy.txt" >/dev/null 2>&1; then
		:
	else
		printf 'verify: copy did not report copied or already-present-same-hash\n' >&2
		rc=1
	fi
	for token in \
		'copy_hash_match=true' \
		'esp_mounted_after_verify=false' \
		'writes_boot_entry=false' \
		'changes_boot_order=false' \
		'sets_boot_next=false' \
		'activation_allowed=false'
	do
		if ! grep -F "$token" "$BASE/verify-copy.txt" >/dev/null 2>&1; then
			printf 'verify: verify-copy missing token: %s\n' "$token" >&2
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
	if ! cmp -s "$BASE/boot-state-before.txt" "$BASE/boot-state-after.txt"; then
		printf 'verify: boot state changed\n' >&2
		rc=1
	fi
	if esp_mounted; then
		printf 'verify: ESP still mounted after stage\n' >&2
		rc=1
	fi
	if is_mounted; then
		printf 'verify: inspection mountpoint still mounted: %s\n' "$MOUNT_POINT" >&2
		rc=1
	fi
	return "$rc"
}

stage() {
	source_path=$(tool_source) || {
		printf 'stage: missing %s next to this script or in /tmp\n' "$TOOL_NAME" >&2
		return 1
	}
	install -d -m 0755 "$BASE" /System/Initramfs/Prototypes
	readlink /System/Current 2>/dev/null > "$BASE/system-current-before.txt" || true
	hash_file "$INITRAMFS" > "$BASE/initramfs-hash-before.txt"
	boot_state > "$BASE/boot-state-before.txt"
	if esp_mounted; then echo true > "$BASE/esp-mounted-before.txt"; else echo false > "$BASE/esp-mounted-before.txt"; fi
	if is_mounted; then
		printf 'stage: inspection mountpoint already mounted before ESP copy: %s\n' "$MOUNT_POINT" >&2
		return 1
	fi
	if [ "$source_path" != "$BASE/$TOOL_NAME" ]; then
		install -m 0755 "$source_path" "$BASE/$TOOL_NAME"
	fi
	install -m 0755 "$source_path" "$TOOL_TARGET"
	write_contract > "$BASE/stage-contract.txt"
	"$TOOL_TARGET" contract > "$BASE/contract.txt" 2>&1
	"$TOOL_TARGET" plan > "$BASE/plan.txt" 2>&1
	"$TOOL_TARGET" copy > "$BASE/copy.txt" 2>&1
	"$TOOL_TARGET" verify > "$BASE/verify-copy.txt" 2>&1
	"$TOOL_TARGET" report > "$BASE/report.txt" 2>&1
	boot_state > "$BASE/boot-state-after.txt"
	write_summary
	if verify_stage; then
		printf 'verified\n' > "$BASE/esp-candidate-copy-no-bootentry-status.txt"
	else
		printf 'incomplete\n' > "$BASE/esp-candidate-copy-no-bootentry-status.txt"
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
