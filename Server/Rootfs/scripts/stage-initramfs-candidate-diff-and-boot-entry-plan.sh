#!/bin/sh
set -u

STAGE=0027-initramfs-candidate-diff-and-boot-entry-plan
BASE=/System/Base/Closure/$STAGE
TOOL_NAME=mixtar-initramfs-candidate-boot-plan.sh
TOOL_TARGET=/System/Initramfs/Prototypes/mixtar-initramfs-candidate-boot-plan.sh
INITRAMFS=/System/Kernel/Current/initramfs.img
MOUNT_POINT=/System/Runtime/Inspect/rootfs-0015

script_dir() {
	dir=$(dirname "$0")
	cd "$dir" 2>/dev/null && pwd
}

tool_source() {
	dir=$(script_dir)
	if [ -f "$dir/$TOOL_NAME" ]; then
		printf '%s/%s\n' "$dir" "$TOOL_NAME"
		return 0
	fi
	if [ -f "/tmp/$TOOL_NAME" ]; then
		printf '/tmp/%s\n' "$TOOL_NAME"
		return 0
	fi
	return 1
}

is_mounted() {
	awk -v mount_point="$MOUNT_POINT" '$2 == mount_point { found = 1 } END { exit found ? 0 : 1 }' /proc/mounts 2>/dev/null
}

hash_file() {
	path=$1
	if [ -f "$path" ]; then
		sha256sum "$path" 2>/dev/null | awk '{ print $1 }'
	else
		echo missing
	fi
}

value_from_file() {
	file=$1
	key=$2
	awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$file"
}

write_contract() {
	cat <<EOF
MixtarRVS initramfs candidate diff and boot entry plan, stage 0027

Installed non-boot planning tool:
  $TOOL_TARGET

This stage is non-activating:
  candidate initramfs is not copied to ESP
  boot entry is not written
  BootOrder is not changed
  BootNext is not set
  active initramfs is not overwritten
  /System/Current is not switched
EOF
}

write_summary() {
	cat > "$BASE/initramfs-candidate-boot-plan-summary.txt" <<EOF
initramfs_candidate_boot_plan_status=generated
tool_target=$TOOL_TARGET
active_sha256=$(value_from_file "$BASE/diff.txt" active_sha256)
candidate_sha256=$(value_from_file "$BASE/diff.txt" candidate_sha256)
candidate_only_count=$(value_from_file "$BASE/diff.txt" candidate_only_count)
active_only_count=$(value_from_file "$BASE/diff.txt" active_only_count)
boot_current=$(value_from_file "$BASE/boot-probe.txt" boot_current)
current_initrd_arg=$(value_from_file "$BASE/boot-probe.txt" current_initrd_arg)
esp_mounted=$(value_from_file "$BASE/boot-probe.txt" esp_mounted)
planned_candidate_initrd_esp_path=$(value_from_file "$BASE/boot-plan.txt" planned_candidate_initrd_esp_path)
would_copy_candidate_to_esp=$(value_from_file "$BASE/boot-plan.txt" would_copy_candidate_to_esp)
would_create_boot_entry=$(value_from_file "$BASE/boot-plan.txt" would_create_boot_entry)
would_change_boot_order=$(value_from_file "$BASE/boot-plan.txt" would_change_boot_order)
would_set_boot_next=$(value_from_file "$BASE/boot-plan.txt" would_set_boot_next)
activation_allowed=$(value_from_file "$BASE/boot-plan.txt" activation_allowed)
boot_entry_ready=$(value_from_file "$BASE/boot-plan.txt" boot_entry_ready)
active_initramfs_hash_before=$(cat "$BASE/initramfs-hash-before.txt" 2>/dev/null || true)
active_initramfs_hash_after=$(hash_file "$INITRAMFS")
current_before=$(cat "$BASE/system-current-before.txt" 2>/dev/null || true)
current_after=$(readlink /System/Current 2>/dev/null || true)
mount_after=$(if is_mounted; then echo present; else echo absent; fi)
next_required_stage=0028-initramfs-candidate-init-handoff-wiring-no-install
EOF
}

verify_stage() {
	rc=0
	if [ ! -x "$TOOL_TARGET" ]; then
		printf 'verify: tool target missing or not executable: %s\n' "$TOOL_TARGET" >&2
		rc=1
	fi
	for file in contract.txt diff.txt boot-probe.txt boot-plan.txt report.txt initramfs-candidate-boot-plan-summary.txt; do
		if [ ! -s "$BASE/$file" ]; then
			printf 'verify: missing report: %s\n' "$file" >&2
			rc=1
		fi
	done
	for token in \
		'copies_candidate_to_esp=false' \
		'writes_boot_entry=false' \
		'changes_boot_order=false' \
		'sets_boot_next=false' \
		'overwrites_active_initramfs=false' \
		'switches_system_current=false'
	do
		if ! grep -F "$token" "$BASE/contract.txt" >/dev/null 2>&1; then
			printf 'verify: contract missing token: %s\n' "$token" >&2
			rc=1
		fi
	done
	for token in \
		'initramfs_candidate_diff=generated' \
		'candidate_addition=System/Initramfs/Prototypes/mixtar-initramfs-handoff.sh:true' \
		'candidate_addition=usr/bin/mixtar-initramfs-handoff:true' \
		'candidate_addition=etc/mixtar-initramfs-candidate:true'
	do
		if ! grep -F "$token" "$BASE/diff.txt" >/dev/null 2>&1; then
			printf 'verify: diff missing token: %s\n' "$token" >&2
			rc=1
		fi
	done
	if grep -F 'candidate_addition=usr/lib/modules/7.1.2-mixtar-rt/kernel/fs/overlayfs/overlay.ko.xz:' "$BASE/diff.txt" >/dev/null 2>&1; then
		:
	else
		printf 'verify: diff missing overlay module presence marker\n' >&2
		rc=1
	fi
	for token in \
		'boot_probe=generated' \
		'candidate_image_ready=true'
	do
		if ! grep -F "$token" "$BASE/boot-probe.txt" >/dev/null 2>&1; then
			printf 'verify: boot probe missing token: %s\n' "$token" >&2
			rc=1
		fi
	done
	for token in \
		'boot_entry_plan=generated' \
		'would_copy_candidate_to_esp=false' \
		'would_create_boot_entry=false' \
		'would_change_boot_order=false' \
		'would_set_boot_next=false' \
		'activation_allowed=false' \
		'boot_entry_ready=false' \
		'next_required_stage=0028-initramfs-candidate-init-handoff-wiring-no-install'
	do
		if ! grep -F "$token" "$BASE/boot-plan.txt" >/dev/null 2>&1; then
			printf 'verify: boot plan missing token: %s\n' "$token" >&2
			rc=1
		fi
	done
	before_hash=$(cat "$BASE/initramfs-hash-before.txt" 2>/dev/null || true)
	after_hash=$(hash_file "$INITRAMFS")
	if [ "$before_hash" != "$after_hash" ]; then
		printf 'verify: active initramfs hash changed from %s to %s\n' "$before_hash" "$after_hash" >&2
		rc=1
	fi
	before_current=$(cat "$BASE/system-current-before.txt" 2>/dev/null || true)
	after_current=$(readlink /System/Current 2>/dev/null || true)
	if [ "$before_current" != "$after_current" ]; then
		printf 'verify: /System/Current changed from %s to %s\n' "$before_current" "$after_current" >&2
		rc=1
	fi
	if is_mounted; then
		printf 'verify: mountpoint still mounted: %s\n' "$MOUNT_POINT" >&2
		rc=1
	fi
	return "$rc"
}

stage() {
	source_path=$(tool_source) || {
		printf 'stage: missing %s next to this script or in /tmp\n' "$TOOL_NAME" >&2
		return 1
	}
	install -d -m 0755 "$BASE" /System/Initramfs/Prototypes
	readlink /System/Current 2>/dev/null > "$BASE/system-current-before.txt" || true
	hash_file "$INITRAMFS" > "$BASE/initramfs-hash-before.txt"
	if is_mounted; then
		printf 'stage: mountpoint already mounted before boot entry plan: %s\n' "$MOUNT_POINT" >&2
		return 1
	fi
	if [ "$source_path" != "$BASE/$TOOL_NAME" ]; then
		install -m 0755 "$source_path" "$BASE/$TOOL_NAME"
	fi
	install -m 0755 "$source_path" "$TOOL_TARGET"
	write_contract > "$BASE/stage-contract.txt"
	"$TOOL_TARGET" contract > "$BASE/contract.txt" 2>&1
	"$TOOL_TARGET" diff > "$BASE/diff.txt" 2>&1
	"$TOOL_TARGET" boot-probe > "$BASE/boot-probe.txt" 2>&1
	"$TOOL_TARGET" boot-plan > "$BASE/boot-plan.txt" 2>&1
	"$TOOL_TARGET" report > "$BASE/report.txt" 2>&1
	write_summary
	if verify_stage; then
		printf 'verified\n' > "$BASE/initramfs-candidate-diff-and-boot-entry-plan-status.txt"
	else
		printf 'incomplete\n' > "$BASE/initramfs-candidate-diff-and-boot-entry-plan-status.txt"
		return 1
	fi
}

mode=${1:-}
if [ -z "$mode" ]; then
	mode=--verify
fi

case "$mode" in
	--verify)
		verify_stage
		;;
	--contract)
		write_contract
		;;
	--stage)
		stage
		;;
	*)
		printf 'usage: %s [--verify|--contract|--stage]\n' "$0" >&2
		exit 2
		;;
esac
