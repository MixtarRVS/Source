#!/bin/sh
set -u

ESP_DEVICE=/dev/nvme0n1p1
ESP_UUID=F70B-FE60
ESP_PARTUUID=bbd8b85d-f0d0-4262-b930-fd1ae4360165
MOUNT_POINT=/System/Runtime/ESP/mixtarrvs-rt-candidate
CANDIDATE_IMAGE=/System/Initramfs/Candidates/0029-initramfs-handoff-boot-command-no-install/initramfs.img
TARGET_REL=EFI/mixtarrvs-rt/initrd-mixtar-candidate-0029.img
TARGET_UEFI='\\EFI\\mixtarrvs-rt\\initrd-mixtar-candidate-0029.img'

usage() {
	cat >&2 <<EOF
usage: mixtar-esp-candidate-copy <command>

commands:
  contract
  plan
  copy
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

esp_is_mounted() {
	awk -v mp="$MOUNT_POINT" '$2 == mp { found = 1 } END { exit found ? 0 : 1 }' /proc/mounts 2>/dev/null
}

any_esp_mounted() {
	awk '$2 ~ /^\/boot\/efi$|^\/efi$|^\/System\/Runtime\/ESP/ { found = 1 } END { exit found ? 0 : 1 }' /proc/mounts 2>/dev/null
}

ensure_esp_identity() {
	line=$(blkid "$ESP_DEVICE" 2>/dev/null || true)
	printf '%s\n' "$line" | grep -F "TYPE=\"vfat\"" >/dev/null 2>&1 || return 1
	printf '%s\n' "$line" | grep -F "UUID=\"$ESP_UUID\"" >/dev/null 2>&1 || return 1
	printf '%s\n' "$line" | grep -F "PARTUUID=\"$ESP_PARTUUID\"" >/dev/null 2>&1 || return 1
	return 0
}

mount_esp() {
	install -d -m 0755 "$MOUNT_POINT"
	if esp_is_mounted; then
		return 0
	fi
	mount -t vfat -o rw,noatime "$ESP_DEVICE" "$MOUNT_POINT"
}

unmount_esp() {
	if esp_is_mounted; then
		umount "$MOUNT_POINT"
	fi
}

target_path() {
	printf '%s/%s\n' "$MOUNT_POINT" "$TARGET_REL"
}

contract() {
	cat <<EOF
esp_candidate_copy_contract=copy-only
mounts_esp_temporarily=true
copies_candidate_to_esp=true
writes_boot_entry=false
changes_boot_order=false
sets_boot_next=false
overwrites_active_initrd=false
switches_system_current=false
candidate_image=$CANDIDATE_IMAGE
esp_device=$ESP_DEVICE
esp_uuid=$ESP_UUID
esp_partuuid=$ESP_PARTUUID
mount_point=$MOUNT_POINT
target_relative=$TARGET_REL
target_uefi=$TARGET_UEFI
EOF
}

plan() {
	echo "esp_candidate_copy_plan=copy-only"
	echo "candidate_image=$CANDIDATE_IMAGE"
	echo "candidate_size_bytes=$(size_file "$CANDIDATE_IMAGE")"
	echo "candidate_sha256=$(hash_file "$CANDIDATE_IMAGE")"
	echo "esp_device=$ESP_DEVICE"
	echo "mount_point=$MOUNT_POINT"
	echo "target_relative=$TARGET_REL"
	echo "target_uefi=$TARGET_UEFI"
	echo "would_mount_esp_temporarily=true"
	echo "would_copy_candidate_to_esp=true"
	echo "would_verify_copied_hash=true"
	echo "would_unmount_esp=true"
	echo "would_create_boot_entry=false"
	echo "would_change_boot_order=false"
	echo "would_set_boot_next=false"
	echo "would_overwrite_active_initrd=false"
	echo "would_switch_current=false"
}

copy_candidate() {
	rc=0
	echo "esp_candidate_copy=generated"
	if [ "$(id -u 2>/dev/null || echo 1)" != "0" ]; then
		echo "copy_error=requires-root"
		return 1
	fi
	if [ ! -f "$CANDIDATE_IMAGE" ]; then
		echo "copy_error=missing-candidate"
		return 1
	fi
	if ! ensure_esp_identity; then
		echo "copy_error=esp-identity-mismatch"
		return 1
	fi
	if any_esp_mounted; then
		echo "esp_mounted_before=true"
	else
		echo "esp_mounted_before=false"
	fi
	mount_esp || return 1
	trap 'unmount_esp' EXIT INT TERM
	target=$(target_path)
	install -d -m 0755 "$(dirname "$target")"
	source_hash=$(hash_file "$CANDIDATE_IMAGE")
	if [ -f "$target" ]; then
		target_hash=$(hash_file "$target")
		if [ "$source_hash" = "$target_hash" ]; then
			echo "copy_status=already-present-same-hash"
		else
			echo "copy_error=target-exists-with-different-hash"
			rc=1
		fi
	else
		cp "$CANDIDATE_IMAGE" "$target" || rc=1
		sync
		echo "copy_status=copied"
	fi
	if [ "$rc" -eq 0 ]; then
		echo "target_path=$target"
		echo "source_sha256=$source_hash"
		echo "target_sha256=$(hash_file "$target")"
		echo "target_size_bytes=$(size_file "$target")"
	fi
	unmount_esp
	trap - EXIT INT TERM
	echo "esp_mounted_after=$(if esp_is_mounted; then echo true; else echo false; fi)"
	echo "writes_boot_entry=false"
	echo "changes_boot_order=false"
	echo "sets_boot_next=false"
	echo "activation_allowed=false"
	return "$rc"
}

verify_copy() {
	rc=0
	echo "esp_candidate_copy_verify=generated"
	if ! ensure_esp_identity; then
		echo "verify_error=esp-identity-mismatch"
		return 1
	fi
	mount_esp || return 1
	trap 'unmount_esp' EXIT INT TERM
	target=$(target_path)
	source_hash=$(hash_file "$CANDIDATE_IMAGE")
	target_hash=$(hash_file "$target")
	echo "target_path=$target"
	echo "source_sha256=$source_hash"
	echo "target_sha256=$target_hash"
	echo "source_size_bytes=$(size_file "$CANDIDATE_IMAGE")"
	echo "target_size_bytes=$(size_file "$target")"
	if [ "$source_hash" = "$target_hash" ] && [ "$source_hash" != "missing" ]; then
		echo "copy_hash_match=true"
	else
		echo "copy_hash_match=false"
		rc=1
	fi
	unmount_esp
	trap - EXIT INT TERM
	echo "esp_mounted_after_verify=$(if esp_is_mounted; then echo true; else echo false; fi)"
	echo "writes_boot_entry=false"
	echo "changes_boot_order=false"
	echo "sets_boot_next=false"
	echo "activation_allowed=false"
	return "$rc"
}

report() {
	echo "esp_candidate_copy_report=generated"
	contract
	plan
	verify_copy
	echo "esp_copy_ready=$(if verify_copy >/dev/null 2>&1; then echo true; else echo false; fi)"
	echo "boot_entry_ready=false"
	echo "next_required_stage=0032-efi-boot-entry-plan-with-bootnext"
}

command=${1:-}
case "$command" in
	contract)
		contract
		;;
	plan)
		plan
		;;
	copy)
		copy_candidate
		;;
	verify)
		verify_copy
		;;
	report)
		report
		;;
	*)
		usage
		exit 2
		;;
esac
