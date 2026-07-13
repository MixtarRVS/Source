#!/bin/sh
set -eu

STAGE_ID="0032-efi-boot-entry-plan-with-bootnext"
BASE="/System/Base/Closure/${STAGE_ID}"
HELPER_SRC="${1:-/tmp/mixtar-efi-boot-entry-plan.sh}"
MANIFEST_SRC="${2:-/tmp/base-closure-0032-efi-boot-entry-plan-with-bootnext.json}"
HELPER_DST="${BASE}/mixtar-efi-boot-entry-plan.sh"
MANIFEST_DST="${BASE}/manifest.json"

if [ "$(id -u)" != "0" ]; then
  echo "run_as_root_required=true" >&2
  exit 1
fi

mkdir -p "$BASE"
cp "$HELPER_SRC" "$HELPER_DST"
chmod 0755 "$HELPER_DST"
cp "$MANIFEST_SRC" "$MANIFEST_DST"

efibootmgr > "${BASE}/efibootmgr-before.txt" 2>&1 || true
sh "$HELPER_DST" contract > "${BASE}/contract.txt"
sh "$HELPER_DST" plan > "${BASE}/plan.txt"
sh "$HELPER_DST" verify > "${BASE}/verify-plan.txt"
efibootmgr > "${BASE}/efibootmgr-after.txt" 2>&1 || true

if cmp -s "${BASE}/efibootmgr-before.txt" "${BASE}/efibootmgr-after.txt"; then
  boot_state_changed="false"
else
  boot_state_changed="true"
fi

boot_current="$(awk -F': ' '/^BootCurrent:/ { print $2; exit }' "${BASE}/efibootmgr-after.txt" || true)"
boot_order="$(awk -F': ' '/^BootOrder:/ { print $2; exit }' "${BASE}/efibootmgr-after.txt" || true)"
bootnext="$(awk -F': ' '/^BootNext:/ { print $2; exit }' "${BASE}/efibootmgr-after.txt" || true)"
candidate_present="$(awk -F= '/^candidate_entry_present=/ { print $2; exit }' "${BASE}/verify-plan.txt" || true)"
source_hash_expected="$(awk -F= '/^source_hash_expected=/ { print $2; exit }' "${BASE}/verify-plan.txt" || true)"
esp_hash_expected="$(awk -F= '/^esp_hash_expected=/ { print $2; exit }' "${BASE}/verify-plan.txt" || true)"
kernel_on_esp="$(awk -F= '/^kernel_on_esp=/ { print $2; exit }' "${BASE}/verify-plan.txt" || true)"
fallback_present="$(awk -F= '/^fallback_boot_entry_present=/ { print $2; exit }' "${BASE}/verify-plan.txt" || true)"
esp_mounted_after="$(awk -F= '/^esp_mounted_after=/ { print $2; exit }' "${BASE}/verify-plan.txt" || true)"

if [ -n "$bootnext" ]; then
  bootnext_present="true"
else
  bootnext_present="false"
fi

if [ "$boot_state_changed" = "false" ] &&
   [ "$source_hash_expected" = "true" ] &&
   [ "$esp_hash_expected" = "true" ] &&
   [ "$kernel_on_esp" = "true" ] &&
   [ "$fallback_present" = "true" ] &&
   [ "$esp_mounted_after" = "false" ]; then
  status="verified"
else
  status="needs_attention"
fi

cat > "${BASE}/efi-boot-entry-plan-summary.txt" <<EOF
stage=${STAGE_ID}
status=${status}
boot_current=${boot_current:-unknown}
boot_order=${boot_order:-unknown}
bootnext_present=${bootnext_present}
bootnext=${bootnext:-none}
candidate_entry_present=${candidate_present:-unknown}
source_hash_expected=${source_hash_expected:-unknown}
esp_hash_expected=${esp_hash_expected:-unknown}
kernel_on_esp=${kernel_on_esp:-unknown}
fallback_boot_entry_present=${fallback_present:-unknown}
esp_mounted_after=${esp_mounted_after:-unknown}
boot_state_changed=${boot_state_changed}
writes_boot_entry=false
changes_boot_order=false
sets_boot_next=false
reboots_system=false
next_required_stage=0033-create-candidate-efi-entry-preserve-bootorder
EOF

cat "${BASE}/efi-boot-entry-plan-summary.txt" > "${BASE}/report.txt"
printf '%s\n' "--- planned commands ---" >> "${BASE}/report.txt"
cat "${BASE}/plan.txt" >> "${BASE}/report.txt"

cat "${BASE}/report.txt"
