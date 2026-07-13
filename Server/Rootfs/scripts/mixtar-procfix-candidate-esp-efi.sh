#!/bin/sh
set -eu

STAGE_ID=0036-copy-procfix-candidate-to-esp-no-active-switch
LABEL="MixtarRVS RT Candidate 0035"
DISK=/dev/nvme0n1
PART=1
ESP_DEVICE=/dev/nvme0n1p1
ESP_MOUNT=/System/Runtime/ESP/mixtarrvs-rt-candidate-0035
SOURCE_IMAGE=/System/Initramfs/Candidates/0035-initramfs-wrapper-procfix-no-install/initramfs.img
EXPECTED_SHA256=2060cdc9e2d61928687a82ddb4dc8d4cc7e84be833e746953dabe392e182a835
TARGET_REL=EFI/mixtarrvs-rt/initrd-mixtar-candidate-0035.img
KERNEL_EFI="\\EFI\\mixtarrvs-rt\\vmlinuz.efi"
INITRD_EFI="\\EFI\\mixtarrvs-rt\\initrd-mixtar-candidate-0035.img"
ROOT_UUID=146d4ab3-3e58-4317-8799-da2f451b9a6c
FALLBACK_BOOTNUM=0006

KERNEL_ARGS="initrd=${INITRD_EFI} root=UUID=${ROOT_UUID} rootfstype=ext4 rootflags=ro modules=nvme,ext4,jbd2,mbcache rootwait ro quiet loglevel=3 threadirqs mixtar.profile=rt-7.1.2-mixtar-rt mixtar.rootfs=/System/Current/rootfs.squashfs mixtar.overlay=tmpfs mixtar.fallback=previous mixtar.handoff=boot"

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

is_mounted() {
	mount_point=$1
	grep -qs " ${mount_point} " /proc/mounts
}

mount_esp_rw() {
	mkdir -p "$ESP_MOUNT"
	if is_mounted "$ESP_MOUNT"; then
		echo already-mounted
		return 0
	fi
	mount "$ESP_DEVICE" "$ESP_MOUNT"
	echo mounted-here
}

unmount_esp_if_needed() {
	state=$1
	if [ "$state" = "mounted-here" ]; then
		umount "$ESP_MOUNT"
	fi
}

current_boot_order() {
	efibootmgr 2>/dev/null | awk -F': ' '/^BootOrder:/ { print $2; exit }'
}

bootnext_value() {
	efibootmgr 2>/dev/null | awk -F': ' '/^BootNext:/ { print $2; exit }'
}

candidate_bootnum() {
	efibootmgr 2>/dev/null | awk -v label="$LABEL" '
		$0 ~ " " label {
			boot=$1
			sub(/^Boot/, "", boot)
			sub(/\*$/, "", boot)
			print boot
			exit
		}
	'
}

fallback_present() {
	if efibootmgr 2>/dev/null | grep -q "^Boot${FALLBACK_BOOTNUM}.*MixtarRVS RT"; then
		echo true
	else
		echo false
	fi
}

contract() {
	cat <<EOF
stage=$STAGE_ID
purpose=copy_procfix_candidate_to_esp_and_create_inactive_efi_entry
source_image=$SOURCE_IMAGE
target_rel=$TARGET_REL
label=$LABEL
copies_candidate_to_esp=true
creates_boot_entry=true
restores_boot_order=true
sets_boot_next=false
reboots_system=false
EOF
}

plan() {
	order=$(current_boot_order)
	cat <<EOF
stage=$STAGE_ID
status=planned
source_image=$SOURCE_IMAGE
source_sha256=$(hash_file "$SOURCE_IMAGE")
expected_sha256=$EXPECTED_SHA256
target_rel=$TARGET_REL
future_create_entry_command=efibootmgr --create --disk $DISK --part $PART --label "$LABEL" --loader "$KERNEL_EFI" --unicode "$KERNEL_ARGS"
future_restore_bootorder_command=efibootmgr --bootorder ${order:-unknown}
sets_boot_next=false
reboots_system=false
EOF
}

copy_and_create_entry() {
	if [ "$(id -u)" != "0" ]; then
		echo "stage=$STAGE_ID"
		echo "status=failed"
		echo "reason=root_required"
		return 1
	fi

	before_order=$(current_boot_order)
	before_bootnext=$(bootnext_value)
	before_candidate=$(candidate_bootnum)
	source_sha=$(hash_file "$SOURCE_IMAGE")

	if [ "$source_sha" != "$EXPECTED_SHA256" ]; then
		echo "stage=$STAGE_ID"
		echo "status=failed"
		echo "reason=source_hash_mismatch"
		echo "source_sha256=$source_sha"
		echo "expected_sha256=$EXPECTED_SHA256"
		return 1
	fi

	mount_state=$(mount_esp_rw)
	mkdir -p "$ESP_MOUNT/$(dirname "$TARGET_REL")"
	cp "$SOURCE_IMAGE" "$ESP_MOUNT/$TARGET_REL"
	sync
	target_sha=$(hash_file "$ESP_MOUNT/$TARGET_REL")
	target_size=$(size_file "$ESP_MOUNT/$TARGET_REL")
	unmount_esp_if_needed "$mount_state"

	if [ -z "$before_candidate" ]; then
		action=created
		set +e
		efibootmgr --create --disk "$DISK" --part "$PART" --label "$LABEL" --loader "$KERNEL_EFI" --unicode "$KERNEL_ARGS"
		create_exit=$?
		set -e
	else
		action=reused
		create_exit=skipped
	fi

	set +e
	efibootmgr --bootorder "$before_order"
	restore_exit=$?
	set -e

	after_order=$(current_boot_order)
	after_bootnext=$(bootnext_value)
	after_candidate=$(candidate_bootnum)
	fallback=$(fallback_present)

	if is_mounted "$ESP_MOUNT"; then
		esp_mounted_after=true
	else
		esp_mounted_after=false
	fi
	if [ "$source_sha" = "$target_sha" ]; then
		copy_hash_match=true
	else
		copy_hash_match=false
	fi
	if [ "$before_order" = "$after_order" ]; then
		boot_order_preserved=true
	else
		boot_order_preserved=false
	fi
	if [ "${before_bootnext:-none}" = "${after_bootnext:-none}" ]; then
		bootnext_preserved=true
	else
		bootnext_preserved=false
	fi
	if [ -n "$after_candidate" ]; then
		candidate_present=true
	else
		candidate_present=false
	fi

	if [ "$copy_hash_match" = "true" ] &&
	   [ "$candidate_present" = "true" ] &&
	   [ "$boot_order_preserved" = "true" ] &&
	   [ "$bootnext_preserved" = "true" ] &&
	   [ "$fallback" = "true" ] &&
	   [ "$restore_exit" = "0" ] &&
	   [ "$esp_mounted_after" = "false" ]; then
		status=verified
	else
		status=needs_attention
	fi

	cat <<EOF
stage=$STAGE_ID
status=$status
copy_action=copied
entry_action=$action
source_sha256=$source_sha
target_sha256=$target_sha
copy_hash_match=$copy_hash_match
target_size_bytes=$target_size
create_exit=$create_exit
restore_exit=$restore_exit
boot_order_before=$before_order
boot_order_after=${after_order:-none}
boot_order_preserved=$boot_order_preserved
bootnext_before=${before_bootnext:-none}
bootnext_after=${after_bootnext:-none}
bootnext_preserved=$bootnext_preserved
candidate_bootnum_before=${before_candidate:-none}
candidate_bootnum_after=${after_candidate:-none}
candidate_entry_present=$candidate_present
fallback_boot_entry_present=$fallback
esp_mounted_after=$esp_mounted_after
sets_boot_next=false
reboots_system=false
next_required_stage=0037-set-bootnext-one-shot-procfix-candidate-test
EOF
}

case "${1:-}" in
	contract)
		contract
		;;
	plan)
		plan
		;;
	apply)
		copy_and_create_entry
		;;
	*)
		echo "usage: $0 [contract|plan|apply]" >&2
		exit 2
		;;
esac
