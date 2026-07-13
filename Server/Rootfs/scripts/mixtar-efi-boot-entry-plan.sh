#!/bin/sh
set -eu

STAGE_ID="0032-efi-boot-entry-plan-with-bootnext"
LABEL="MixtarRVS RT Candidate 0029"
DISK="/dev/nvme0n1"
PART="1"
ESP_DEVICE="/dev/nvme0n1p1"
ESP_MOUNT="/System/Runtime/ESP/mixtar-efi-plan-0032"
KERNEL_EFI="\\EFI\\mixtarrvs-rt\\vmlinuz.efi"
INITRD_EFI="\\EFI\\mixtarrvs-rt\\initrd-mixtar-candidate-0029.img"
ESP_KERNEL_PATH="EFI/mixtarrvs-rt/vmlinuz.efi"
ESP_INITRD_PATH="EFI/mixtarrvs-rt/initrd-mixtar-candidate-0029.img"
CANDIDATE_SOURCE="/System/Initramfs/Candidates/0029-initramfs-handoff-boot-command-no-install/initramfs.img"
EXPECTED_CANDIDATE_SHA256="4880325f92e6912b67c2c5003de14907f6cbde5a0bd700392386db0443496bfb"
ROOT_UUID="146d4ab3-3e58-4317-8799-da2f451b9a6c"
FALLBACK_BOOTNUM="0006"

KERNEL_ARGS="initrd=${INITRD_EFI} root=UUID=${ROOT_UUID} rootfstype=ext4 rootflags=ro modules=nvme,ext4,jbd2,mbcache rootwait ro quiet loglevel=3 threadirqs mixtar.profile=rt-7.1.2-mixtar-rt mixtar.rootfs=/System/Current/rootfs.squashfs mixtar.overlay=tmpfs mixtar.fallback=previous mixtar.handoff=boot"

is_mounted() {
  mount_point="$1"
  grep -qs " ${mount_point} " /proc/mounts
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

mount_esp_readonly() {
  mkdir -p "$ESP_MOUNT"
  if is_mounted "$ESP_MOUNT"; then
    echo "already-mounted"
    return 0
  fi
  mount -o ro "$ESP_DEVICE" "$ESP_MOUNT"
  echo "mounted-here"
}

unmount_esp_if_needed() {
  mounted_state="$1"
  if [ "$mounted_state" = "mounted-here" ]; then
    umount "$ESP_MOUNT"
  fi
}

sha256_file() {
  file_path="$1"
  if [ -f "$file_path" ]; then
    sha256sum "$file_path" | awk '{ print $1 }'
  else
    echo "missing"
  fi
}

print_contract() {
  cat <<EOF
stage=${STAGE_ID}
purpose=plan_candidate_efi_entry_and_one_shot_bootnext
writes_boot_entry=false
changes_boot_order=false
sets_boot_next=false
reboots_system=false
mounts_esp_readonly=true
expected_fallback_bootnum=${FALLBACK_BOOTNUM}
candidate_label=${LABEL}
candidate_initrd=${INITRD_EFI}
kernel_loader=${KERNEL_EFI}
EOF
}

print_plan() {
  order="$(current_boot_order)"
  [ -n "$order" ] || order="<current_bootorder>"
  cat <<EOF
stage=${STAGE_ID}
status=planned
future_create_entry_command=efibootmgr --create --disk ${DISK} --part ${PART} --label "${LABEL}" --loader "${KERNEL_EFI}" --unicode "${KERNEL_ARGS}"
future_restore_bootorder_command=efibootmgr --bootorder ${order}
future_find_candidate_bootnum_command=efibootmgr | awk '/ ${LABEL}\$/ { print substr(\$1,5,4) }'
future_one_shot_bootnext_command=efibootmgr --bootnext <candidate_bootnum>
future_test_boot_command=reboot
fallback_policy=BootOrder stays restored to ${order}; BootNext is one-shot only after explicit approval.
EOF
}

print_verify() {
  mounted_state="$(mount_esp_readonly)"
  source_sha="$(sha256_file "$CANDIDATE_SOURCE")"
  esp_sha="$(sha256_file "${ESP_MOUNT}/${ESP_INITRD_PATH}")"
  if [ -f "${ESP_MOUNT}/${ESP_KERNEL_PATH}" ]; then
    kernel_on_esp="true"
  else
    kernel_on_esp="false"
  fi
  if [ "$source_sha" = "$EXPECTED_CANDIDATE_SHA256" ]; then
    source_hash_expected="true"
  else
    source_hash_expected="false"
  fi
  if [ "$esp_sha" = "$EXPECTED_CANDIDATE_SHA256" ]; then
    esp_hash_expected="true"
  else
    esp_hash_expected="false"
  fi
  boot_order="$(current_boot_order)"
  bootnext="$(bootnext_value)"
  candidate_num="$(candidate_bootnum)"
  if efibootmgr 2>/dev/null | grep -q "^Boot${FALLBACK_BOOTNUM}.*MixtarRVS RT"; then
    fallback_present="true"
  else
    fallback_present="false"
  fi
  if [ -n "$candidate_num" ]; then
    candidate_entry_present="true"
  else
    candidate_entry_present="false"
  fi
  if [ -n "$bootnext" ]; then
    bootnext_present="true"
  else
    bootnext_present="false"
  fi
  unmount_esp_if_needed "$mounted_state"
  if is_mounted "$ESP_MOUNT"; then
    esp_mounted_after="true"
  else
    esp_mounted_after="false"
  fi

  cat <<EOF
stage=${STAGE_ID}
status=verified_plan
source_sha256=${source_sha}
esp_candidate_sha256=${esp_sha}
expected_candidate_sha256=${EXPECTED_CANDIDATE_SHA256}
source_hash_expected=${source_hash_expected}
esp_hash_expected=${esp_hash_expected}
kernel_on_esp=${kernel_on_esp}
fallback_boot_entry_present=${fallback_present}
fallback_bootnum=${FALLBACK_BOOTNUM}
boot_order=${boot_order}
bootnext_present=${bootnext_present}
bootnext=${bootnext:-none}
candidate_entry_present=${candidate_entry_present}
candidate_bootnum=${candidate_num:-none}
esp_mounted_after=${esp_mounted_after}
stage_mutates_efi=false
ready_to_create_candidate_entry=true
EOF
}

case "${1:-plan}" in
  contract)
    print_contract
    ;;
  plan)
    print_plan
    ;;
  verify)
    print_verify
    ;;
  *)
    echo "usage: $0 [contract|plan|verify]" >&2
    exit 64
    ;;
esac
