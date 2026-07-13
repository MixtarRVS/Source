#!/bin/sh
set -eu

STAGE_ID=0039-copy-pathlog-candidate-to-esp-no-active-switch
LABEL="MixtarRVS RT Candidate 0038"
DISK=/dev/nvme0n1
PART=1
ESP_DEVICE=/dev/nvme0n1p1
ESP_MOUNT=/System/Runtime/ESP/mixtarrvs-rt-candidate-0038
SOURCE_IMAGE=/System/Initramfs/Candidates/0038-init-wrapper-pathlog-no-install/initramfs.img
EXPECTED_SHA256=aa595911f2721f876428943b10b703287f864757a485c6d2a7847ef79b218d52
TARGET_REL=EFI/mixtarrvs-rt/initrd-mixtar-candidate-0038.img
KERNEL_EFI="\\EFI\\mixtarrvs-rt\\vmlinuz.efi"
INITRD_EFI="\\EFI\\mixtarrvs-rt\\initrd-mixtar-candidate-0038.img"
ROOT_UUID=146d4ab3-3e58-4317-8799-da2f451b9a6c
FALLBACK_BOOTNUM=0006
KERNEL_ARGS="initrd=${INITRD_EFI} root=UUID=${ROOT_UUID} rootfstype=ext4 rootflags=ro modules=nvme,ext4,jbd2,mbcache rootwait ro quiet loglevel=3 threadirqs mixtar.profile=rt-7.1.2-mixtar-rt mixtar.rootfs=/System/Current/rootfs.squashfs mixtar.overlay=tmpfs mixtar.fallback=previous mixtar.handoff=boot"

hash_file() { [ -f "$1" ] && sha256sum "$1" | awk '{print $1}' || echo missing; }
size_file() { [ -f "$1" ] && wc -c "$1" | awk '{print $1}' || echo 0; }
is_mounted() { grep -qs " $1 " /proc/mounts; }
boot_order() { efibootmgr 2>/dev/null | awk -F': ' '/^BootOrder:/ {print $2; exit}'; }
bootnext_value() { efibootmgr 2>/dev/null | awk -F': ' '/^BootNext:/ {print $2; exit}'; }
candidate_bootnum() {
	efibootmgr 2>/dev/null | awk -v label="$LABEL" '$0 ~ " " label { boot=$1; sub(/^Boot/,"",boot); sub(/\*$/,"",boot); print boot; exit }'
}
fallback_present() {
	efibootmgr 2>/dev/null | grep -q "^Boot${FALLBACK_BOOTNUM}.*MixtarRVS RT" && echo true || echo false
}

contract() {
	cat <<EOF
stage=$STAGE_ID
purpose=copy_pathlog_candidate_to_esp_and_create_inactive_efi_entry
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

apply_stage() {
	before_order=$(boot_order)
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
	mkdir -p "$ESP_MOUNT"
	if is_mounted "$ESP_MOUNT"; then mount_state=already-mounted; else mount "$ESP_DEVICE" "$ESP_MOUNT"; mount_state=mounted-here; fi
	mkdir -p "$ESP_MOUNT/$(dirname "$TARGET_REL")"
	cp "$SOURCE_IMAGE" "$ESP_MOUNT/$TARGET_REL"
	sync
	target_sha=$(hash_file "$ESP_MOUNT/$TARGET_REL")
	target_size=$(size_file "$ESP_MOUNT/$TARGET_REL")
	if [ "$mount_state" = mounted-here ]; then umount "$ESP_MOUNT"; fi
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
	after_order=$(boot_order)
	after_bootnext=$(bootnext_value)
	after_candidate=$(candidate_bootnum)
	fallback=$(fallback_present)
	[ "$source_sha" = "$target_sha" ] && copy_hash_match=true || copy_hash_match=false
	[ "$before_order" = "$after_order" ] && boot_order_preserved=true || boot_order_preserved=false
	[ "${before_bootnext:-none}" = "${after_bootnext:-none}" ] && bootnext_preserved=true || bootnext_preserved=false
	[ -n "$after_candidate" ] && candidate_present=true || candidate_present=false
	is_mounted "$ESP_MOUNT" && esp_mounted_after=true || esp_mounted_after=false
	if [ "$copy_hash_match" = true ] && [ "$candidate_present" = true ] && [ "$boot_order_preserved" = true ] && [ "$bootnext_preserved" = true ] && [ "$fallback" = true ] && [ "$restore_exit" = 0 ] && [ "$esp_mounted_after" = false ]; then
		status=verified
	else
		status=needs_attention
	fi
	cat <<EOF
stage=$STAGE_ID
status=$status
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
next_required_stage=0040-set-bootnext-one-shot-pathlog-candidate-test
EOF
}

case "${1:-}" in
	contract) contract ;;
	apply) apply_stage ;;
	*) echo "usage: $0 [contract|apply]" >&2; exit 2 ;;
esac
