#!/bin/sh
set -eu

STAGE_ID="0034-set-bootnext-one-shot-candidate-test"
BASE="/System/Base/Closure/${STAGE_ID}"
HELPER_SRC="${1:-/tmp/mixtar-efi-bootnext-candidate-test.sh}"
MANIFEST_SRC="${2:-/tmp/base-closure-0034-set-bootnext-one-shot-candidate-test.json}"
HELPER_DST="${BASE}/mixtar-efi-bootnext-candidate-test.sh"
MANIFEST_DST="${BASE}/manifest.json"

if [ "$(id -u)" != "0" ]; then
  echo "run_as_root_required=true" >&2
  exit 1
fi

mkdir -p "$BASE"
cp "$HELPER_SRC" "$HELPER_DST"
chmod 0755 "$HELPER_DST"
cp "$MANIFEST_SRC" "$MANIFEST_DST"

efibootmgr > "${BASE}/efibootmgr-before-preflight.txt" 2>&1 || true
sh "$HELPER_DST" contract > "${BASE}/contract.txt"
sh "$HELPER_DST" preflight > "${BASE}/preflight.txt"
efibootmgr > "${BASE}/efibootmgr-after-preflight.txt" 2>&1 || true

if cmp -s "${BASE}/efibootmgr-before-preflight.txt" "${BASE}/efibootmgr-after-preflight.txt"; then
  boot_state_changed="false"
else
  boot_state_changed="true"
fi

preflight_status="$(awk -F= '/^status=/ { print $2; exit }' "${BASE}/preflight.txt" || true)"
ready_to_arm="$(awk -F= '/^ready_to_arm_bootnext=/ { print $2; exit }' "${BASE}/preflight.txt" || true)"
boot_current="$(awk -F= '/^boot_current=/ { print $2; exit }' "${BASE}/preflight.txt" || true)"
boot_order="$(awk -F= '/^boot_order=/ { print $2; exit }' "${BASE}/preflight.txt" || true)"
bootnext_present="$(awk -F= '/^bootnext_present=/ { print $2; exit }' "${BASE}/preflight.txt" || true)"
candidate_present="$(awk -F= '/^candidate_entry_present=/ { print $2; exit }' "${BASE}/preflight.txt" || true)"
fallback_present="$(awk -F= '/^fallback_entry_present=/ { print $2; exit }' "${BASE}/preflight.txt" || true)"

if [ "$preflight_status" = "ready" ] &&
   [ "$ready_to_arm" = "true" ] &&
   [ "$boot_state_changed" = "false" ]; then
  status="verified_preflight"
else
  status="needs_attention"
fi

cat > "${BASE}/bootnext-candidate-test-preflight-summary.txt" <<EOF
stage=${STAGE_ID}
status=${status}
preflight_status=${preflight_status:-unknown}
ready_to_arm_bootnext=${ready_to_arm:-unknown}
boot_current=${boot_current:-unknown}
boot_order=${boot_order:-unknown}
bootnext_present=${bootnext_present:-unknown}
candidate_entry_present=${candidate_present:-unknown}
fallback_entry_present=${fallback_present:-unknown}
boot_state_changed=${boot_state_changed}
sets_boot_next=false
reboots_system=false
arm_command=sudo sh ${HELPER_DST} arm
manual_reboot_command=sudo reboot
postboot_verify_command=sudo sh ${HELPER_DST} postboot
EOF

cat "${BASE}/bootnext-candidate-test-preflight-summary.txt" > "${BASE}/report.txt"
printf '%s\n' "--- preflight output ---" >> "${BASE}/report.txt"
cat "${BASE}/preflight.txt" >> "${BASE}/report.txt"

cat "${BASE}/report.txt"
