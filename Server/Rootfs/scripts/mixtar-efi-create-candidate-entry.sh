#!/bin/sh
set -eu

STAGE_ID="0033-create-candidate-efi-entry-preserve-bootorder"
LABEL="MixtarRVS RT Candidate 0029"
DISK="/dev/nvme0n1"
PART="1"
KERNEL_EFI="\\EFI\\mixtarrvs-rt\\vmlinuz.efi"
INITRD_EFI="\\EFI\\mixtarrvs-rt\\initrd-mixtar-candidate-0029.img"
ROOT_UUID="146d4ab3-3e58-4317-8799-da2f451b9a6c"
FALLBACK_BOOTNUM="0006"

KERNEL_ARGS="initrd=${INITRD_EFI} root=UUID=${ROOT_UUID} rootfstype=ext4 rootflags=ro modules=nvme,ext4,jbd2,mbcache rootwait ro quiet loglevel=3 threadirqs mixtar.profile=rt-7.1.2-mixtar-rt mixtar.rootfs=/System/Current/rootfs.squashfs mixtar.overlay=tmpfs mixtar.fallback=previous mixtar.handoff=boot"

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
    echo "true"
  else
    echo "false"
  fi
}

print_contract() {
  cat <<EOF
stage=${STAGE_ID}
purpose=create_candidate_efi_entry_without_bootnext
creates_boot_entry=true
restores_boot_order=true
sets_boot_next=false
reboots_system=false
fallback_bootnum=${FALLBACK_BOOTNUM}
candidate_label=${LABEL}
kernel_loader=${KERNEL_EFI}
candidate_initrd=${INITRD_EFI}
EOF
}

create_or_reuse() {
  if [ "$(id -u)" != "0" ]; then
    echo "status=failed"
    echo "reason=root_required"
    return 0
  fi

  before_order="$(current_boot_order)"
  before_bootnext="$(bootnext_value)"
  before_candidate="$(candidate_bootnum)"
  create_exit="skipped"
  restore_exit="skipped"
  action="reused"

  if [ -z "$before_order" ]; then
    echo "stage=${STAGE_ID}"
    echo "status=failed"
    echo "reason=missing_bootorder"
    return 0
  fi

  if [ -z "$before_candidate" ]; then
    action="created"
    set +e
    efibootmgr --create --disk "$DISK" --part "$PART" --label "$LABEL" --loader "$KERNEL_EFI" --unicode "$KERNEL_ARGS"
    create_exit="$?"
    set -e
  fi

  set +e
  efibootmgr --bootorder "$before_order"
  restore_exit="$?"
  set -e

  after_order="$(current_boot_order)"
  after_bootnext="$(bootnext_value)"
  after_candidate="$(candidate_bootnum)"
  fallback="$(fallback_present)"

  if [ -n "$after_candidate" ]; then
    candidate_present="true"
  else
    candidate_present="false"
  fi
  if [ "$before_order" = "$after_order" ]; then
    boot_order_preserved="true"
  else
    boot_order_preserved="false"
  fi
  if [ "${before_bootnext:-none}" = "${after_bootnext:-none}" ]; then
    bootnext_preserved="true"
  else
    bootnext_preserved="false"
  fi

  if [ "$candidate_present" = "true" ] &&
     [ "$boot_order_preserved" = "true" ] &&
     [ "$bootnext_preserved" = "true" ] &&
     [ "$fallback" = "true" ] &&
     [ "$restore_exit" = "0" ]; then
    status="verified"
  else
    status="needs_attention"
  fi

  cat <<EOF
stage=${STAGE_ID}
status=${status}
action=${action}
create_exit=${create_exit}
restore_exit=${restore_exit}
boot_order_before=${before_order}
boot_order_after=${after_order:-none}
boot_order_preserved=${boot_order_preserved}
bootnext_before=${before_bootnext:-none}
bootnext_after=${after_bootnext:-none}
bootnext_preserved=${bootnext_preserved}
candidate_bootnum_before=${before_candidate:-none}
candidate_bootnum_after=${after_candidate:-none}
candidate_entry_present=${candidate_present}
fallback_boot_entry_present=${fallback}
sets_boot_next=false
reboots_system=false
next_required_stage=0034-set-bootnext-one-shot-candidate-test
EOF
}

case "${1:-create}" in
  contract)
    print_contract
    ;;
  create)
    create_or_reuse
    ;;
  *)
    echo "usage: $0 [contract|create]" >&2
    exit 64
    ;;
esac
