#!/bin/sh
set -u

STAGE_ID=0027-initramfs-candidate-diff-and-boot-entry-plan
ACTIVE_INITRAMFS=/System/Kernel/Current/initramfs.img
CANDIDATE_IMAGE=/System/Initramfs/Candidates/0026-initramfs-candidate-image-no-install/initramfs.img
CANDIDATE_ESP_PATH='\\EFI\\mixtarrvs-rt\\initrd-mixtar-candidate-0026.img'
ACTIVE_ESP_INITRD='\\EFI\\mixtarrvs-rt\\initrd.img'
KERNEL_ESP_PATH='\\EFI\\mixtarrvs-rt\\vmlinuz.efi'
PLANNED_LABEL='MixtarRVS RT Candidate 0026'

usage() {
	cat >&2 <<EOF
usage: mixtar-initramfs-candidate-boot-plan <command>

commands:
  contract
  diff
  boot-probe
  boot-plan
  report
EOF
}

hash_file() {
	path=$1
	if [ -f "$path" ]; then
		sha256sum "$path" 2>/dev/null | awk '{ print $1 }'
	else
		echo missing
	fi
}

size_file() {
	path=$1
	if [ -f "$path" ]; then
		wc -c < "$path" 2>/dev/null | awk '{ print $1 }'
	else
		echo 0
	fi
}

cmdline_value() {
	key=$1
	for item in $(cat /proc/cmdline 2>/dev/null || true); do
		case "$item" in
			$key=*)
				printf '%s\n' "${item#*=}"
				return 0
				;;
		esac
	done
	return 1
}

image_list() {
	image=$1
	zcat "$image" 2>/dev/null | cpio -t 2>/dev/null | sed 's#^\./##' | sort -u
}

boot_current_id() {
	if command -v efibootmgr >/dev/null 2>&1; then
		efibootmgr 2>/dev/null | awk '/^BootCurrent:/ { print $2; exit }'
	fi
}

boot_current_line() {
	id=$(boot_current_id)
	if [ -n "$id" ] && command -v efibootmgr >/dev/null 2>&1; then
		efibootmgr -v 2>/dev/null | awk -v boot="Boot$id" '$0 ~ "^" boot { print; exit }'
	fi
}

contract() {
	cat <<EOF
initramfs_candidate_boot_plan_contract=non-mutating
copies_candidate_to_esp=false
writes_boot_entry=false
changes_boot_order=false
sets_boot_next=false
overwrites_active_initramfs=false
switches_system_current=false
loads_overlay_module=false
mounts_overlay=false
active_initramfs=$ACTIVE_INITRAMFS
candidate_image=$CANDIDATE_IMAGE
active_esp_initrd=$ACTIVE_ESP_INITRD
candidate_esp_path=$CANDIDATE_ESP_PATH
kernel_esp_path=$KERNEL_ESP_PATH
planned_label=$PLANNED_LABEL
EOF
}

diff_images() {
	active_list=/tmp/mixtar-active-initramfs-list.$$
	candidate_list=/tmp/mixtar-candidate-initramfs-list.$$
	candidate_only=/tmp/mixtar-candidate-only.$$
	active_only=/tmp/mixtar-active-only.$$
	echo "initramfs_candidate_diff=generated"
	echo "active_initramfs=$ACTIVE_INITRAMFS"
	echo "candidate_image=$CANDIDATE_IMAGE"
	echo "active_sha256=$(hash_file "$ACTIVE_INITRAMFS")"
	echo "candidate_sha256=$(hash_file "$CANDIDATE_IMAGE")"
	image_list "$ACTIVE_INITRAMFS" > "$active_list"
	image_list "$CANDIDATE_IMAGE" > "$candidate_list"
	comm -13 "$active_list" "$candidate_list" > "$candidate_only"
	comm -23 "$active_list" "$candidate_list" > "$active_only"
	echo "active_entry_count=$(wc -l < "$active_list" | awk '{ print $1 }')"
	echo "candidate_entry_count=$(wc -l < "$candidate_list" | awk '{ print $1 }')"
	echo "candidate_only_count=$(wc -l < "$candidate_only" | awk '{ print $1 }')"
	echo "active_only_count=$(wc -l < "$active_only" | awk '{ print $1 }')"
	echo "candidate_only_begin"
	sed -n '1,80p' "$candidate_only"
	echo "candidate_only_end"
	for path in \
		usr/lib/modules/7.1.2-mixtar-rt/kernel/fs/overlayfs/overlay.ko.xz \
		System/Initramfs/Prototypes/mixtar-initramfs-handoff.sh \
		usr/bin/mixtar-initramfs-handoff \
		etc/mixtar-initramfs-candidate
	do
		if grep -Fx "$path" "$candidate_only" >/dev/null 2>&1; then
			echo "candidate_addition=$path:true"
		else
			if grep -Fx "$path" "$candidate_list" >/dev/null 2>&1; then
				echo "candidate_addition=$path:already-present"
			else
				echo "candidate_addition=$path:false"
			fi
		fi
	done
	rm -f "$active_list" "$candidate_list" "$candidate_only" "$active_only"
}

boot_probe() {
	echo "boot_probe=generated"
	echo "boot_current=$(boot_current_id)"
	echo "boot_current_line=$(boot_current_line)"
	echo "current_cmdline=$(cat /proc/cmdline 2>/dev/null || true)"
	echo "current_initrd_arg=$(cmdline_value initrd || true)"
	echo "current_root_arg=$(cmdline_value root || true)"
	echo "current_rootfstype=$(cmdline_value rootfstype || true)"
	echo "current_rootflags=$(cmdline_value rootflags || true)"
	echo "current_modules=$(cmdline_value modules || true)"
	echo "current_mixtar_profile=$(cmdline_value mixtar.profile || true)"
	if awk '$2 ~ /^\/boot\/efi$|^\/efi$/ { found = 1 } END { exit found ? 0 : 1 }' /proc/mounts 2>/dev/null; then
		echo "esp_mounted=true"
	else
		echo "esp_mounted=false"
	fi
	echo "candidate_image_ready=$(if [ -f "$CANDIDATE_IMAGE" ]; then echo true; else echo false; fi)"
	echo "candidate_size_bytes=$(size_file "$CANDIDATE_IMAGE")"
	echo "candidate_sha256=$(hash_file "$CANDIDATE_IMAGE")"
}

boot_plan() {
	root_arg=$(cmdline_value root || true)
	rootfstype=$(cmdline_value rootfstype || true)
	rootflags=$(cmdline_value rootflags || true)
	modules=$(cmdline_value modules || true)
	profile=$(cmdline_value mixtar.profile || true)
	echo "boot_entry_plan=generated"
	echo "planned_label=$PLANNED_LABEL"
	echo "planned_kernel_esp_path=$KERNEL_ESP_PATH"
	echo "planned_candidate_initrd_esp_path=$CANDIDATE_ESP_PATH"
	echo "planned_copy_source=$CANDIDATE_IMAGE"
	echo "planned_copy_target_esp=$CANDIDATE_ESP_PATH"
	echo "planned_kernel_args=initrd=$CANDIDATE_ESP_PATH root=$root_arg rootfstype=$rootfstype rootflags=$rootflags modules=$modules rootwait ro quiet loglevel=3 threadirqs mixtar.profile=$profile mixtar.rootfs=/System/Current/rootfs.squashfs mixtar.overlay=tmpfs mixtar.fallback=previous"
	echo "would_copy_candidate_to_esp=false"
	echo "would_create_boot_entry=false"
	echo "would_change_boot_order=false"
	echo "would_set_boot_next=false"
	echo "would_overwrite_active_initramfs=false"
	echo "would_switch_current=false"
	echo "activation_allowed=false"
	echo "boot_entry_ready=false"
	echo "boot_entry_blocker=candidate initramfs contains Mixtar handoff prototype but active /init is not wired to delegate to it"
	echo "boot_entry_blocker=ESP mount/copy step is not implemented in this stage"
	echo "fallback_policy=preserve Boot0006 MixtarRVS RT and current /System/Current"
	echo "next_required_stage=0028-initramfs-candidate-init-handoff-wiring-no-install"
}

report() {
	echo "initramfs_candidate_boot_report=generated"
	contract
	diff_images
	boot_probe
	boot_plan
}

command=${1:-}
case "$command" in
	contract)
		contract
		;;
	diff)
		diff_images
		;;
	boot-probe)
		boot_probe
		;;
	boot-plan)
		boot_plan
		;;
	report)
		report
		;;
	*)
		usage
		exit 2
		;;
esac
