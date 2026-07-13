#!/bin/sh
set -eu

STAGE=0041-initramfs-binsh-fix-no-install
BASE=/System/Base/Closure/$STAGE
BUILDER_SRC=${1:-/tmp/mixtar-initramfs-binsh-fix-builder.sh}
MANIFEST_SRC=${2:-/tmp/base-closure-0041-initramfs-binsh-fix-no-install.json}
BUILDER_TARGET=/System/Initramfs/Prototypes/mixtar-initramfs-binsh-fix-builder.sh

if [ "$(id -u)" != "0" ]; then
	echo "run_as_root_required=true" >&2
	exit 1
fi

mkdir -p "$BASE" /System/Initramfs/Prototypes
cp "$BUILDER_SRC" "$BUILDER_TARGET"
chmod 0755 "$BUILDER_TARGET"
cp "$MANIFEST_SRC" "$BASE/manifest.json"

"$BUILDER_TARGET" contract > "$BASE/contract.txt"
"$BUILDER_TARGET" build-candidate > "$BASE/build-candidate.txt" 2>&1
"$BUILDER_TARGET" verify > "$BASE/verify.txt" 2>&1
"$BUILDER_TARGET" report > "$BASE/report-builder.txt" 2>&1

target_image=$(awk -F= '/^target_image=/ { print $2; exit }' "$BASE/build-candidate.txt")
target_size_bytes=$(awk -F= '/^target_size_bytes=/ { print $2; exit }' "$BASE/build-candidate.txt")
target_sha256=$(awk -F= '/^target_sha256=/ { print $2; exit }' "$BASE/build-candidate.txt")
source_sha256=$(awk -F= '/^source_candidate_sha256=/ { print $2; exit }' "$BASE/build-candidate.txt")
verify_result=$(awk -F= '/^verify_result=/ { print $2; exit }' "$BASE/verify.txt")
candidate_ready=$(awk -F= '/^candidate_ready=/ { print $2; exit }' "$BASE/report-builder.txt")
bin_sh_resolves=$(awk -F= '/^bin_sh_resolves=/ { print $2; exit }' "$BASE/verify.txt")
usr_bin_sh_executable=$(awk -F= '/^usr_bin_sh_executable=/ { print $2; exit }' "$BASE/verify.txt")
wrapper_logs=$(awk -F= '/^wrapper_priority_logs_present=/ { print $2; exit }' "$BASE/verify.txt")

if [ "$verify_result" = ok ] &&
   [ "$candidate_ready" = true ] &&
   [ "$bin_sh_resolves" = true ] &&
   [ "$usr_bin_sh_executable" = true ] &&
   [ "$wrapper_logs" = true ]; then
	status=verified
else
	status=incomplete
fi

cat > "$BASE/initramfs-binsh-fix-summary.txt" <<EOF
stage=$STAGE
status=$status
source_candidate_sha256=$source_sha256
target_image=$target_image
target_size_bytes=$target_size_bytes
target_sha256=$target_sha256
verify_result=$verify_result
candidate_ready=$candidate_ready
bin_sh_resolves=$bin_sh_resolves
usr_bin_sh_executable=$usr_bin_sh_executable
wrapper_priority_logs_present=$wrapper_logs
installs_candidate_initramfs=false
copies_candidate_to_esp=false
creates_boot_entry=false
sets_boot_next=false
reboots_system=false
next_required_stage=0042-copy-binsh-fix-candidate-to-esp-no-active-switch
EOF

cat "$BASE/initramfs-binsh-fix-summary.txt" > "$BASE/report.txt"
printf '%s\n' "--- verify ---" >> "$BASE/report.txt"
cat "$BASE/verify.txt" >> "$BASE/report.txt"
cat "$BASE/report.txt"
