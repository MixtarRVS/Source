#!/bin/sh
set -eu

STAGE=0036-copy-procfix-candidate-to-esp-no-active-switch
BASE=/System/Base/Closure/$STAGE
TOOL_SRC=${1:-/tmp/mixtar-procfix-candidate-esp-efi.sh}
MANIFEST_SRC=${2:-/tmp/base-closure-0036-copy-procfix-candidate-to-esp-no-active-switch.json}
TOOL_TARGET=/System/Initramfs/Prototypes/mixtar-procfix-candidate-esp-efi.sh

if [ "$(id -u)" != "0" ]; then
	echo "run_as_root_required=true" >&2
	exit 1
fi

mkdir -p "$BASE" /System/Initramfs/Prototypes
cp "$TOOL_SRC" "$TOOL_TARGET"
chmod 0755 "$TOOL_TARGET"
cp "$MANIFEST_SRC" "$BASE/manifest.json"

efibootmgr > "$BASE/efibootmgr-before.txt" 2>&1 || true
"$TOOL_TARGET" contract > "$BASE/contract.txt"
"$TOOL_TARGET" plan > "$BASE/plan.txt"
"$TOOL_TARGET" apply > "$BASE/apply.txt" 2>&1
efibootmgr > "$BASE/efibootmgr-after.txt" 2>&1 || true

status=$(awk -F= '/^status=/ { print $2; exit }' "$BASE/apply.txt")
entry_action=$(awk -F= '/^entry_action=/ { print $2; exit }' "$BASE/apply.txt")
source_sha256=$(awk -F= '/^source_sha256=/ { print $2; exit }' "$BASE/apply.txt")
target_sha256=$(awk -F= '/^target_sha256=/ { print $2; exit }' "$BASE/apply.txt")
copy_hash_match=$(awk -F= '/^copy_hash_match=/ { print $2; exit }' "$BASE/apply.txt")
candidate_bootnum=$(awk -F= '/^candidate_bootnum_after=/ { print $2; exit }' "$BASE/apply.txt")
boot_order_preserved=$(awk -F= '/^boot_order_preserved=/ { print $2; exit }' "$BASE/apply.txt")
bootnext_preserved=$(awk -F= '/^bootnext_preserved=/ { print $2; exit }' "$BASE/apply.txt")
fallback_present=$(awk -F= '/^fallback_boot_entry_present=/ { print $2; exit }' "$BASE/apply.txt")
esp_mounted_after=$(awk -F= '/^esp_mounted_after=/ { print $2; exit }' "$BASE/apply.txt")
boot_current=$(awk -F': ' '/^BootCurrent:/ { print $2; exit }' "$BASE/efibootmgr-after.txt")
boot_order=$(awk -F': ' '/^BootOrder:/ { print $2; exit }' "$BASE/efibootmgr-after.txt")
bootnext=$(awk -F': ' '/^BootNext:/ { print $2; exit }' "$BASE/efibootmgr-after.txt" || true)

if [ -n "$bootnext" ]; then
	bootnext_present=true
else
	bootnext_present=false
fi

if [ "$status" = "verified" ]; then
	stage_status=verified
else
	stage_status=needs_attention
fi

cat > "$BASE/procfix-candidate-esp-efi-summary.txt" <<EOF
stage=$STAGE
status=$stage_status
entry_action=$entry_action
boot_current=$boot_current
boot_order=$boot_order
bootnext_present=$bootnext_present
bootnext=${bootnext:-none}
source_sha256=$source_sha256
target_sha256=$target_sha256
copy_hash_match=$copy_hash_match
candidate_bootnum=$candidate_bootnum
boot_order_preserved=$boot_order_preserved
bootnext_preserved=$bootnext_preserved
fallback_boot_entry_present=$fallback_present
esp_mounted_after=$esp_mounted_after
copies_candidate_to_esp=true
creates_boot_entry=true
sets_boot_next=false
reboots_system=false
next_required_stage=0037-set-bootnext-one-shot-procfix-candidate-test
EOF

cat "$BASE/procfix-candidate-esp-efi-summary.txt" > "$BASE/report.txt"
printf '%s\n' "--- apply ---" >> "$BASE/report.txt"
cat "$BASE/apply.txt" >> "$BASE/report.txt"

cat "$BASE/report.txt"
