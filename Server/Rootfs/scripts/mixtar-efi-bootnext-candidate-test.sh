#!/bin/sh
set -eu

STAGE_ID="0034-set-bootnext-one-shot-candidate-test"
CANDIDATE_BOOTNUM="0007"
CANDIDATE_LABEL="MixtarRVS RT Candidate 0029"
FALLBACK_BOOTNUM="0006"
FALLBACK_LABEL="MixtarRVS RT"
EXPECTED_BOOT_ORDER="0006,0003,0004,0005,0017,0018,0019,001A,001B,001C,001D,001E,001F"
EXPECTED_CMDLINE_TOKEN="mixtar.handoff=boot"

efibootmgr_text() {
  efibootmgr 2>/dev/null || true
}

boot_current() {
  efibootmgr_text | awk -F': ' '/^BootCurrent:/ { print $2; exit }'
}

boot_order() {
  efibootmgr_text | awk -F': ' '/^BootOrder:/ { print $2; exit }'
}

bootnext_value() {
  efibootmgr_text | awk -F': ' '/^BootNext:/ { print $2; exit }'
}

entry_present() {
  bootnum="$1"
  label="$2"
  if efibootmgr_text | grep -q "^Boot${bootnum}.*${label}"; then
    echo "true"
  else
    echo "false"
  fi
}

cmdline_has_candidate_token() {
  if [ -r /proc/cmdline ] && grep -q "$EXPECTED_CMDLINE_TOKEN" /proc/cmdline; then
    echo "true"
  else
    echo "false"
  fi
}

root_mount_source() {
  awk '$2 == "/" { print $1; exit }' /proc/mounts 2>/dev/null || true
}

print_contract() {
  cat <<EOF
stage=${STAGE_ID}
purpose=one_shot_candidate_boot_test
candidate_bootnum=${CANDIDATE_BOOTNUM}
candidate_label=${CANDIDATE_LABEL}
fallback_bootnum=${FALLBACK_BOOTNUM}
fallback_label=${FALLBACK_LABEL}
preflight_mutates_efi=false
arm_sets_bootnext=true
arm_reboots_system=false
manual_reboot_required_after_arm=true
postboot_mutates_efi=false
EOF
}

print_preflight() {
  current="$(boot_current)"
  order="$(boot_order)"
  bootnext="$(bootnext_value)"
  candidate_present="$(entry_present "$CANDIDATE_BOOTNUM" "$CANDIDATE_LABEL")"
  fallback_present="$(entry_present "$FALLBACK_BOOTNUM" "$FALLBACK_LABEL")"

  if [ "$candidate_present" = "true" ] &&
     [ "$fallback_present" = "true" ] &&
     [ "$order" = "$EXPECTED_BOOT_ORDER" ] &&
     [ -z "$bootnext" ]; then
    status="ready"
  else
    status="needs_attention"
  fi

  cat <<EOF
stage=${STAGE_ID}
mode=preflight
status=${status}
boot_current=${current:-unknown}
boot_order=${order:-unknown}
boot_order_expected=${EXPECTED_BOOT_ORDER}
boot_order_matches_expected=$([ "$order" = "$EXPECTED_BOOT_ORDER" ] && echo true || echo false)
bootnext_present=$([ -n "$bootnext" ] && echo true || echo false)
bootnext=${bootnext:-none}
candidate_bootnum=${CANDIDATE_BOOTNUM}
candidate_entry_present=${candidate_present}
fallback_bootnum=${FALLBACK_BOOTNUM}
fallback_entry_present=${fallback_present}
preflight_mutates_efi=false
ready_to_arm_bootnext=$([ "$status" = "ready" ] && echo true || echo false)
arm_command=$0 arm
manual_reboot_command=reboot
EOF
}

arm_bootnext() {
  if [ "$(id -u)" != "0" ]; then
    echo "stage=${STAGE_ID}"
    echo "mode=arm"
    echo "status=failed"
    echo "reason=root_required"
    exit 1
  fi

  before_next="$(bootnext_value)"
  before_order="$(boot_order)"
  candidate_present="$(entry_present "$CANDIDATE_BOOTNUM" "$CANDIDATE_LABEL")"
  fallback_present="$(entry_present "$FALLBACK_BOOTNUM" "$FALLBACK_LABEL")"

  if [ "$candidate_present" != "true" ] || [ "$fallback_present" != "true" ]; then
    echo "stage=${STAGE_ID}"
    echo "mode=arm"
    echo "status=failed"
    echo "reason=missing_candidate_or_fallback"
    echo "candidate_entry_present=${candidate_present}"
    echo "fallback_entry_present=${fallback_present}"
    exit 1
  fi

  efibootmgr --bootnext "$CANDIDATE_BOOTNUM" >/tmp/mixtar-bootnext-arm-output.txt 2>&1
  after_next="$(bootnext_value)"
  after_order="$(boot_order)"

  if [ "$after_next" = "$CANDIDATE_BOOTNUM" ] && [ "$before_order" = "$after_order" ]; then
    status="armed"
  else
    status="needs_attention"
  fi

  cat <<EOF
stage=${STAGE_ID}
mode=arm
status=${status}
bootnext_before=${before_next:-none}
bootnext_after=${after_next:-none}
boot_order_before=${before_order:-unknown}
boot_order_after=${after_order:-unknown}
boot_order_preserved=$([ "$before_order" = "$after_order" ] && echo true || echo false)
candidate_bootnum=${CANDIDATE_BOOTNUM}
sets_boot_next=true
reboots_system=false
manual_reboot_required=true
EOF
}

postboot_verify() {
  current="$(boot_current)"
  order="$(boot_order)"
  bootnext="$(bootnext_value)"
  cmdline_token="$(cmdline_has_candidate_token)"
  root_source="$(root_mount_source)"

  if [ "$current" = "$CANDIDATE_BOOTNUM" ] && [ "$cmdline_token" = "true" ]; then
    status="candidate_booted"
  elif [ "$current" = "$FALLBACK_BOOTNUM" ]; then
    status="fallback_booted"
  else
    status="unknown_boot_path"
  fi

  cat <<EOF
stage=${STAGE_ID}
mode=postboot
status=${status}
boot_current=${current:-unknown}
boot_order=${order:-unknown}
bootnext_present=$([ -n "$bootnext" ] && echo true || echo false)
bootnext=${bootnext:-none}
candidate_bootnum=${CANDIDATE_BOOTNUM}
fallback_bootnum=${FALLBACK_BOOTNUM}
cmdline_has_candidate_token=${cmdline_token}
root_mount_source=${root_source:-unknown}
postboot_mutates_efi=false
EOF
}

case "${1:-preflight}" in
  contract)
    print_contract
    ;;
  preflight)
    print_preflight
    ;;
  arm)
    arm_bootnext
    ;;
  postboot)
    postboot_verify
    ;;
  *)
    echo "usage: $0 [contract|preflight|arm|postboot]" >&2
    exit 64
    ;;
esac
