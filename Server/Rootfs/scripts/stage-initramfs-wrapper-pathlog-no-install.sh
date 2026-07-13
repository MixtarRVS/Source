#!/bin/sh
set -eu

STAGE=0038-init-wrapper-pathlog-no-install
BASE=/System/Base/Closure/$STAGE
BUILDER_SRC=${1:-/tmp/mixtar-initramfs-wrapper-pathlog-builder.sh}
WRAPPER_SRC=${2:-/tmp/mixtar-init-wrapper.sh}
HANDOFF_SRC=${3:-/tmp/mixtar-initramfs-handoff-prototype.sh}
MANIFEST_SRC=${4:-/tmp/base-closure-0038-init-wrapper-pathlog-no-install.json}
BUILDER_TARGET=/System/Initramfs/Prototypes/mixtar-initramfs-wrapper-pathlog-builder.sh
WRAPPER_TARGET=/System/Initramfs/Prototypes/mixtar-init-wrapper-pathlog.sh
HANDOFF_TARGET=/System/Initramfs/Prototypes/mixtar-initramfs-handoff-pathlog.sh

if [ "$(id -u)" != "0" ]; then
	echo "run_as_root_required=true" >&2
	exit 1
fi

mkdir -p "$BASE" /System/Initramfs/Prototypes
cp "$BUILDER_SRC" "$BUILDER_TARGET"
chmod 0755 "$BUILDER_TARGET"
cp "$WRAPPER_SRC" "$WRAPPER_TARGET"
chmod 0755 "$WRAPPER_TARGET"
cp "$HANDOFF_SRC" "$HANDOFF_TARGET"
chmod 0755 "$HANDOFF_TARGET"
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
handoff_sha256=$(awk -F= '/^handoff_source_sha256=/ { print $2; exit }' "$BASE/build-candidate.txt")
verify_result=$(awk -F= '/^verify_result=/ { print $2; exit }' "$BASE/verify.txt")
candidate_ready=$(awk -F= '/^candidate_ready=/ { print $2; exit }' "$BASE/report-builder.txt")
wrapper_path=$(awk -F= '/^wrapper_has_explicit_path=/ { print $2; exit }' "$BASE/verify.txt")
handoff_path=$(awk -F= '/^handoff_has_explicit_path=/ { print $2; exit }' "$BASE/verify.txt")
wrapper_logs=$(awk -F= '/^wrapper_has_kernel_priority_logs=/ { print $2; exit }' "$BASE/verify.txt")
handoff_logs=$(awk -F= '/^handoff_has_kernel_priority_logs=/ { print $2; exit }' "$BASE/verify.txt")

if [ "$verify_result" = "ok" ] &&
   [ "$candidate_ready" = "true" ] &&
   [ "$wrapper_path" = "true" ] &&
   [ "$handoff_path" = "true" ] &&
   [ "$wrapper_logs" = "true" ] &&
   [ "$handoff_logs" = "true" ]; then
	status=verified
else
	status=incomplete
fi

cat > "$BASE/initramfs-wrapper-pathlog-summary.txt" <<EOF
stage=$STAGE
status=$status
source_candidate_sha256=$source_sha256
wrapper_source_sha256=$wrapper_sha256
handoff_source_sha256=$handoff_sha256
target_image=$target_image
target_size_bytes=$target_size_bytes
target_sha256=$target_sha256
verify_result=$verify_result
candidate_ready=$candidate_ready
wrapper_has_explicit_path=$wrapper_path
handoff_has_explicit_path=$handoff_path
wrapper_has_kernel_priority_logs=$wrapper_logs
handoff_has_kernel_priority_logs=$handoff_logs
installs_candidate_initramfs=false
copies_candidate_to_esp=false
creates_boot_entry=false
sets_boot_next=false
reboots_system=false
next_required_stage=0039-copy-pathlog-candidate-to-esp-no-active-switch
EOF

cat "$BASE/initramfs-wrapper-pathlog-summary.txt" > "$BASE/report.txt"
printf '%s\n' "--- verify ---" >> "$BASE/report.txt"
cat "$BASE/verify.txt" >> "$BASE/report.txt"

cat "$BASE/report.txt"
