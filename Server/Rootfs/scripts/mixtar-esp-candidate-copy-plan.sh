#!/bin/sh
set -u

STAGE_ID=0030-esp-candidate-copy-plan-no-activation
CANDIDATE_IMAGE=/System/Initramfs/Candidates/0029-initramfs-handoff-boot-command-no-install/initramfs.img
CANDIDATE_ESP_REL=EFI/mixtarrvs-rt/initrd-mixtar-candidate-0029.img
CANDIDATE_ESP_PATH='\\EFI\\mixtarrvs-rt\\initrd-mixtar-candidate-0029.img'
KERNEL_ESP_PATH='\\EFI\\mixtarrvs-rt\\vmlinuz.efi'
PLANNED_LABEL='MixtarRVS RT Candidate 0029'
PLANNED_MOUNT=/System/Runtime/ESP/mixtarrvs-rt-candidate

usage() {
	cat >&2 <<EOF
usage: mixtar-esp-candidate-copy-plan <command>

commands:
  contract
  probe
  plan
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

cmdline_value() {
	key=$1
	for item in $(cat /proc/cmdline 2>/dev/null || true); do
		case "$item" in
			$key=*)
				printf '%s\n' "${item#*=}"
				return 0
				;;
		esac
	done
	return 1
}

boot_current_id() {
	if command -v efibootmgr >/dev/null 2>&1; then
		efibootmgr 2>/dev/null | awk '/^BootCurrent:/ { print $2; exit }'
	fi
}

boot_current_line() {
	id=$(boot_current_id)
	if [ -n "$id" ] && command -v efibootmgr >/dev/null 2>&1; then
		efibootmgr -v 2>/dev/null | awk -v boot="Boot$id" '$0 ~ "^" boot { print; exit }'
	fi
}

boot_order_line() {
	if command -v efibootmgr >/dev/null 2>&1; then
		efibootmgr 2>/dev/null | awk '/^BootOrder:/ { print; exit }'
	fi
}

esp_partuuid() {
	line=$(boot_current_line)
	printf '%s\n' "$line" | sed -n 's/.*GPT,\([^,]*\),.*/\1/p'
}

esp_device() {
	partuuid=$(esp_partuuid)
	if [ -n "$partuuid" ] && [ -e "/dev/disk/by-partuuid/$partuuid" ]; then
		readlink -f "/dev/disk/by-partuuid/$partuuid"
		return 0
	fi
	if [ -n "$partuuid" ]; then
		blkid 2>/dev/null | awk -F: -v p="PARTUUID=\"$partuuid\"" '$0 ~ p { print $1; exit }'
	fi
}

blkid_value() {
	device=$1
	key=$2
	blkid "$device" 2>/dev/null | tr ' ' '\n' | awk -F= -v key="$key" '$1 == key { gsub(/"/, "", $2); print $2; exit }'
}

contract() {
	cat <<EOF
esp_candidate_copy_plan_contract=non-mutating
mounts_esp=false
copies_candidate_to_esp=false
writes_boot_entry=false
changes_boot_order=false
sets_boot_next=false
overwrites_active_initrd=false
switches_system_current=false
candidate_image=$CANDIDATE_IMAGE
candidate_esp_rel=$CANDIDATE_ESP_REL
candidate_esp_path=$CANDIDATE_ESP_PATH
kernel_esp_path=$KERNEL_ESP_PATH
planned_label=$PLANNED_LABEL
planned_mount=$PLANNED_MOUNT
EOF
}

probe() {
	device=$(esp_device || true)
	echo "esp_candidate_copy_probe=generated"
	echo "boot_current=$(boot_current_id)"
	echo "boot_order=$(boot_order_line)"
	echo "boot_current_line=$(boot_current_line)"
	echo "esp_partuuid=$(esp_partuuid)"
	echo "esp_device=$device"
	if [ -n "$device" ] && [ -b "$device" ]; then
		echo "esp_device_ready=true"
		echo "esp_fstype=$(blkid_value "$device" TYPE)"
		echo "esp_uuid=$(blkid_value "$device" UUID)"
		echo "esp_partuuid_from_blkid=$(blkid_value "$device" PARTUUID)"
	else
		echo "esp_device_ready=false"
	fi
	if awk '$2 ~ /^\/boot\/efi$|^\/efi$|^\/System\/Runtime\/ESP/ { found = 1 } END { exit found ? 0 : 1 }' /proc/mounts 2>/dev/null; then
		echo "esp_currently_mounted=true"
	else
		echo "esp_currently_mounted=false"
	fi
	echo "candidate_image_ready=$(if [ -f "$CANDIDATE_IMAGE" ]; then echo true; else echo false; fi)"
	echo "candidate_size_bytes=$(size_file "$CANDIDATE_IMAGE")"
	echo "candidate_sha256=$(hash_file "$CANDIDATE_IMAGE")"
	echo "active_initrd_arg=$(cmdline_value initrd || true)"
	echo "active_root_arg=$(cmdline_value root || true)"
	echo "active_rootfstype=$(cmdline_value rootfstype || true)"
	echo "active_rootflags=$(cmdline_value rootflags || true)"
	echo "active_modules=$(cmdline_value modules || true)"
	echo "active_profile=$(cmdline_value mixtar.profile || true)"
}

plan() {
	root_arg=$(cmdline_value root || true)
	rootfstype=$(cmdline_value rootfstype || true)
	rootflags=$(cmdline_value rootflags || true)
	modules=$(cmdline_value modules || true)
	profile=$(cmdline_value mixtar.profile || true)
	device=$(esp_device || true)
	echo "esp_candidate_copy_plan=generated"
	echo "planned_mount=$PLANNED_MOUNT"
	echo "planned_esp_device=$device"
	echo "planned_copy_source=$CANDIDATE_IMAGE"
	echo "planned_copy_target_relative=$CANDIDATE_ESP_REL"
	echo "planned_copy_target_uefi=$CANDIDATE_ESP_PATH"
	echo "planned_kernel_uefi=$KERNEL_ESP_PATH"
	echo "planned_label=$PLANNED_LABEL"
	echo "planned_kernel_args=initrd=$CANDIDATE_ESP_PATH root=$root_arg rootfstype=$rootfstype rootflags=$rootflags modules=$modules rootwait ro quiet loglevel=3 threadirqs mixtar.profile=$profile mixtar.rootfs=/System/Current/rootfs.squashfs mixtar.overlay=tmpfs mixtar.fallback=previous mixtar.handoff=boot"
	echo "future_step01=mount ESP at $PLANNED_MOUNT"
	echo "future_step02=copy candidate initramfs to $CANDIDATE_ESP_REL"
	echo "future_step03=sync and verify copied hash"
	echo "future_step04=create disabled/test EFI boot entry with label $PLANNED_LABEL"
	echo "future_step05=set BootNext only for a single test boot after explicit approval"
	echo "future_step06=preserve Boot0006 and BootOrder fallback"
	echo "would_mount_esp=false"
	echo "would_copy_candidate_to_esp=false"
	echo "would_create_boot_entry=false"
	echo "would_change_boot_order=false"
	echo "would_set_boot_next=false"
	echo "would_overwrite_active_initrd=false"
	echo "would_switch_current=false"
	echo "activation_allowed=false"
	echo "copy_plan_ready=true"
	echo "boot_test_ready=false"
	echo "boot_test_blocker=copy to ESP and EFI boot entry are not executed in this stage"
	echo "next_required_stage=0031-esp-candidate-copy-no-bootentry"
}

report() {
	echo "esp_candidate_copy_report=generated"
	contract
	probe
	plan
}

command=${1:-}
case "$command" in
	contract)
		contract
		;;
	probe)
		probe
		;;
	plan)
		plan
		;;
	report)
		report
		;;
	*)
		usage
		exit 2
		;;
esac
