#!/bin/sh
set -u

STAGE=0030-esp-candidate-copy-plan-no-activation
BASE=/System/Base/Closure/$STAGE
TOOL_NAME=mixtar-esp-candidate-copy-plan.sh
TOOL_TARGET=/System/Initramfs/Prototypes/mixtar-esp-candidate-copy-plan.sh
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

value_from_file() {
	file=$1
	key=$2
	awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$file"
}

write_contract() {
	cat <<EOF
MixtarRVS ESP candidate copy plan, stage 0030

Installed non-boot planning tool:
  $TOOL_TARGET

This stage is non-activating:
  ESP is not mounted
  candidate initramfs is not copied to ESP
  EFI boot entry is not written
  BootOrder is not changed
  BootNext is not set
  active initramfs is not overwritten
  /System/Current is not switched
EOF
}

write_summary() {
	cat > "$BASE/esp-candidate-copy-plan-summary.txt" <<EOF
esp_candidate_copy_plan_status=generated
tool_target=$TOOL_TARGET
boot_current=$(value_from_file "$BASE/probe.txt" boot_current)
esp_partuuid=$(value_from_file "$BASE/probe.txt" esp_partuuid)
esp_device=$(value_from_file "$BASE/probe.txt" esp_device)
esp_device_ready=$(value_from_file "$BASE/probe.txt" esp_device_ready)
esp_fstype=$(value_from_file "$BASE/probe.txt" esp_fstype)
esp_uuid=$(value_from_file "$BASE/probe.txt" esp_uuid)
esp_currently_mounted_before=$(cat "$BASE/esp-mounted-before.txt" 2>/dev/null || true)
esp_currently_mounted_after=$(if esp_mounted; then echo true; else echo false; fi)
candidate_image_ready=$(value_from_file "$BASE/probe.txt" candidate_image_ready)
candidate_size_bytes=$(value_from_file "$BASE/probe.txt" candidate_size_bytes)
candidate_sha256=$(value_from_file "$BASE/probe.txt" candidate_sha256)
planned_copy_target_relative=$(value_from_file "$BASE/plan.txt" planned_copy_target_relative)
planned_copy_target_uefi=$(value_from_file "$BASE/plan.txt" planned_copy_target_uefi)
would_mount_esp=$(value_from_file "$BASE/plan.txt" would_mount_esp)
would_copy_candidate_to_esp=$(value_from_file "$BASE/plan.txt" would_copy_candidate_to_esp)
would_create_boot_entry=$(value_from_file "$BASE/plan.txt" would_create_boot_entry)
would_change_boot_order=$(value_from_file "$BASE/plan.txt" would_change_boot_order)
would_set_boot_next=$(value_from_file "$BASE/plan.txt" would_set_boot_next)
activation_allowed=$(value_from_file "$BASE/plan.txt" activation_allowed)
copy_plan_ready=$(value_from_file "$BASE/plan.txt" copy_plan_ready)
boot_test_ready=$(value_from_file "$BASE/plan.txt" boot_test_ready)
active_initramfs_hash_before=$(cat "$BASE/initramfs-hash-before.txt" 2>/dev/null || true)
active_initramfs_hash_after=$(hash_file "$INITRAMFS")
current_before=$(cat "$BASE/system-current-before.txt" 2>/dev/null || true)
current_after=$(readlink /System/Current 2>/dev/null || true)
mount_after=$(if is_mounted; then echo present; else echo absent; fi)
next_required_stage=0031-esp-candidate-copy-no-bootentry
EOF
}

verify_stage() {
	rc=0
	for file in contract.txt probe.txt plan.txt report.txt esp-candidate-copy-plan-summary.txt; do
		if [ ! -s "$BASE/$file" ]; then
			printf 'verify: missing report: %s\n' "$file" >&2
			rc=1
		fi
	done
	for token in \
		'mounts_esp=false' \
		'copies_candidate_to_esp=false' \
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
	for token in \
		'esp_candidate_copy_probe=generated' \
		'esp_device_ready=true' \
		'esp_fstype=vfat' \
		'candidate_image_ready=true'
	do
		if ! grep -F "$token" "$BASE/probe.txt" >/dev/null 2>&1; then
			printf 'verify: probe missing token: %s\n' "$token" >&2
			rc=1
		fi
	done
	for token in \
		'esp_candidate_copy_plan=generated' \
		'mixtar.handoff=boot' \
		'would_mount_esp=false' \
		'would_copy_candidate_to_esp=false' \
		'would_create_boot_entry=false' \
		'would_change_boot_order=false' \
		'would_set_boot_next=false' \
		'activation_allowed=false' \
		'copy_plan_ready=true' \
		'next_required_stage=0031-esp-candidate-copy-no-bootentry'
	do
		if ! grep -F "$token" "$BASE/plan.txt" >/dev/null 2>&1; then
			printf 'verify: plan missing token: %s\n' "$token" >&2
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
	before_esp=$(cat "$BASE/esp-mounted-before.txt" 2>/dev/null || true)
	after_esp=$(if esp_mounted; then echo true; else echo false; fi)
	if [ "$before_esp" != "$after_esp" ]; then
		printf 'verify: ESP mount state changed from %s to %s\n' "$before_esp" "$after_esp" >&2
		rc=1
	fi
	if is_mounted; then
		printf 'verify: mountpoint still mounted: %s\n' "$MOUNT_POINT" >&2
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
	if esp_mounted; then echo true > "$BASE/esp-mounted-before.txt"; else echo false > "$BASE/esp-mounted-before.txt"; fi
	if is_mounted; then
		printf 'stage: mountpoint already mounted before ESP copy plan: %s\n' "$MOUNT_POINT" >&2
		return 1
	fi
	if [ "$source_path" != "$BASE/$TOOL_NAME" ]; then
		install -m 0755 "$source_path" "$BASE/$TOOL_NAME"
	fi
	install -m 0755 "$source_path" "$TOOL_TARGET"
	write_contract > "$BASE/stage-contract.txt"
	"$TOOL_TARGET" contract > "$BASE/contract.txt" 2>&1
	"$TOOL_TARGET" probe > "$BASE/probe.txt" 2>&1
	"$TOOL_TARGET" plan > "$BASE/plan.txt" 2>&1
	"$TOOL_TARGET" report > "$BASE/report.txt" 2>&1
	write_summary
	if verify_stage; then
		printf 'verified\n' > "$BASE/esp-candidate-copy-plan-no-activation-status.txt"
	else
		printf 'incomplete\n' > "$BASE/esp-candidate-copy-plan-no-activation-status.txt"
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
