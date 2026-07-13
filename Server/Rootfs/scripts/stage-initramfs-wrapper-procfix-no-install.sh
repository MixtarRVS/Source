#!/bin/sh
set -eu

STAGE=0035-initramfs-wrapper-procfix-no-install
BASE=/System/Base/Closure/$STAGE
BUILDER_SRC=${1:-/tmp/mixtar-initramfs-wrapper-procfix-builder.sh}
WRAPPER_SRC=${2:-/tmp/mixtar-init-wrapper.sh}
MANIFEST_SRC=${3:-/tmp/base-closure-0035-initramfs-wrapper-procfix-no-install.json}
BUILDER_TARGET=/System/Initramfs/Prototypes/mixtar-initramfs-wrapper-procfix-builder.sh
WRAPPER_TARGET=/System/Initramfs/Prototypes/mixtar-init-wrapper-procfix.sh

if [ "$(id -u)" != "0" ]; then
	echo "run_as_root_required=true" >&2
	exit 1
fi

mkdir -p "$BASE" /System/Initramfs/Prototypes
cp "$BUILDER_SRC" "$BUILDER_TARGET"
chmod 0755 "$BUILDER_TARGET"
cp "$WRAPPER_SRC" "$WRAPPER_TARGET"
chmod 0755 "$WRAPPER_TARGET"
cp "$MANIFEST_SRC" "$BASE/manifest.json"

"$BUILDER_TARGET" contract > "$BASE/contract.txt"
"$BUILDER_TARGET" plan > "$BASE/plan.txt"
"$BUILDER_TARGET" build-candidate > "$BASE/build-candidate.txt" 2>&1
"$BUILDER_TARGET" inspect > "$BASE/inspect.txt" 2>&1
"$BUILDER_TARGET" verify > "$BASE/verify.txt" 2>&1
"$BUILDER_TARGET" report > "$BASE/report-builder.txt" 2>&1

target_image=$(awk -F= '/^target_image=/ { print $2; exit }' "$BASE/build-candidate.txt")
target_size_bytes=$(awk -F= '/^target_size_bytes=/ { print $2; exit }' "$BASE/build-candidate.txt")
target_sha256=$(awk -F= '/^target_sha256=/ { print $2; exit }' "$BASE/build-candidate.txt")
source_sha256=$(awk -F= '/^source_candidate_sha256=/ { print $2; exit }' "$BASE/build-candidate.txt")
wrapper_sha256=$(awk -F= '/^wrapper_source_sha256=/ { print $2; exit }' "$BASE/build-candidate.txt")
verify_result=$(awk -F= '/^verify_result=/ { print $2; exit }' "$BASE/verify.txt")
candidate_ready=$(awk -F= '/^candidate_ready=/ { print $2; exit }' "$BASE/report-builder.txt")
mounts_before_parse=$(awk -F= '/^wrapper_mounts_before_cmdline_parse=/ { print $2; exit }' "$BASE/verify.txt")
fallback_no_arg=$(awk -F= '/^fallback_exec_has_no_error_argument=/ { print $2; exit }' "$BASE/verify.txt")

if [ "$verify_result" = "ok" ] &&
   [ "$candidate_ready" = "true" ] &&
   [ "$mounts_before_parse" = "true" ] &&
   [ "$fallback_no_arg" = "true" ]; then
	status=verified
else
	status=incomplete
fi

cat > "$BASE/initramfs-wrapper-procfix-summary.txt" <<EOF
stage=$STAGE
status=$status
source_candidate_sha256=$source_sha256
wrapper_source_sha256=$wrapper_sha256
target_image=$target_image
target_size_bytes=$target_size_bytes
target_sha256=$target_sha256
verify_result=$verify_result
candidate_ready=$candidate_ready
wrapper_mounts_before_cmdline_parse=$mounts_before_parse
fallback_exec_has_no_error_argument=$fallback_no_arg
installs_candidate_initramfs=false
copies_candidate_to_esp=false
creates_boot_entry=false
sets_boot_next=false
reboots_system=false
next_required_stage=0036-copy-procfix-candidate-to-esp-no-active-switch
EOF

cat "$BASE/initramfs-wrapper-procfix-summary.txt" > "$BASE/report.txt"
printf '%s\n' "--- verify ---" >> "$BASE/report.txt"
cat "$BASE/verify.txt" >> "$BASE/report.txt"

cat "$BASE/report.txt"
