#!/bin/sh
set -eu

STAGE_ID="0033-create-candidate-efi-entry-preserve-bootorder"
BASE="/System/Base/Closure/${STAGE_ID}"
HELPER_SRC="${1:-/tmp/mixtar-efi-create-candidate-entry.sh}"
MANIFEST_SRC="${2:-/tmp/base-closure-0033-create-candidate-efi-entry-preserve-bootorder.json}"
HELPER_DST="${BASE}/mixtar-efi-create-candidate-entry.sh"
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
sh "$HELPER_DST" create > "${BASE}/create.txt" 2>&1
efibootmgr > "${BASE}/efibootmgr-after.txt" 2>&1 || true

status="$(awk -F= '/^status=/ { print $2; exit }' "${BASE}/create.txt" || true)"
action="$(awk -F= '/^action=/ { print $2; exit }' "${BASE}/create.txt" || true)"
create_exit="$(awk -F= '/^create_exit=/ { print $2; exit }' "${BASE}/create.txt" || true)"
restore_exit="$(awk -F= '/^restore_exit=/ { print $2; exit }' "${BASE}/create.txt" || true)"
boot_order_preserved="$(awk -F= '/^boot_order_preserved=/ { print $2; exit }' "${BASE}/create.txt" || true)"
bootnext_preserved="$(awk -F= '/^bootnext_preserved=/ { print $2; exit }' "${BASE}/create.txt" || true)"
candidate_bootnum="$(awk -F= '/^candidate_bootnum_after=/ { print $2; exit }' "${BASE}/create.txt" || true)"
candidate_present="$(awk -F= '/^candidate_entry_present=/ { print $2; exit }' "${BASE}/create.txt" || true)"
fallback_present="$(awk -F= '/^fallback_boot_entry_present=/ { print $2; exit }' "${BASE}/create.txt" || true)"
boot_current="$(awk -F': ' '/^BootCurrent:/ { print $2; exit }' "${BASE}/efibootmgr-after.txt" || true)"
boot_order="$(awk -F': ' '/^BootOrder:/ { print $2; exit }' "${BASE}/efibootmgr-after.txt" || true)"
bootnext="$(awk -F': ' '/^BootNext:/ { print $2; exit }' "${BASE}/efibootmgr-after.txt" || true)"

if [ -n "$bootnext" ]; then
  bootnext_present="true"
else
  bootnext_present="false"
fi

if [ "$status" = "verified" ] &&
   [ "$boot_order_preserved" = "true" ] &&
   [ "$bootnext_preserved" = "true" ] &&
   [ "$candidate_present" = "true" ] &&
   [ "$fallback_present" = "true" ]; then
  stage_status="verified"
else
  stage_status="needs_attention"
fi

cat > "${BASE}/create-candidate-efi-entry-summary.txt" <<EOF
stage=${STAGE_ID}
status=${stage_status}
action=${action:-unknown}
create_exit=${create_exit:-unknown}
restore_exit=${restore_exit:-unknown}
boot_current=${boot_current:-unknown}
boot_order=${boot_order:-unknown}
bootnext_present=${bootnext_present}
bootnext=${bootnext:-none}
candidate_bootnum=${candidate_bootnum:-unknown}
candidate_entry_present=${candidate_present:-unknown}
fallback_boot_entry_present=${fallback_present:-unknown}
boot_order_preserved=${boot_order_preserved:-unknown}
bootnext_preserved=${bootnext_preserved:-unknown}
creates_boot_entry=true
sets_boot_next=false
reboots_system=false
next_required_stage=0034-set-bootnext-one-shot-candidate-test
EOF

cat "${BASE}/create-candidate-efi-entry-summary.txt" > "${BASE}/report.txt"
printf '%s\n' "--- create output ---" >> "${BASE}/report.txt"
cat "${BASE}/create.txt" >> "${BASE}/report.txt"

cat "${BASE}/report.txt"
