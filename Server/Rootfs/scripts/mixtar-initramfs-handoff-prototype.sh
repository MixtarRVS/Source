#!/bin/sh
set -u

PATH=/sbin:/bin:/usr/sbin:/usr/bin
export PATH

ROOTFS_IMAGE_DEFAULT=/System/Current/rootfs.squashfs
BASE_MOUNT=/MixtarBase
IMAGE_MOUNT=/MixtarImage
OVERLAY_ROOT=/MixtarOverlay
OVERLAY_UPPER=/MixtarOverlay/upper
OVERLAY_WORK=/MixtarOverlay/work
NEW_ROOT=/MixtarRoot
PRIMARY_INIT=/sbin/openrc-init
FALLBACK_INIT=/sbin/init

usage() {
	cat >&2 <<EOF
usage: mixtar-initramfs-handoff <command>

commands:
  contract
  plan
  check-live
  simulate
  boot
EOF
}

log_msg() {
	msg=$1
	if [ -e /dev/kmsg ]; then
		printf '<3>mixtar-handoff: %s\n' "$msg" > /dev/kmsg
	fi
	printf 'mixtar-handoff: %s\n' "$msg"
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

tool_state() {
	name=$1
	path=$(command -v "$name" 2>/dev/null || true)
	if [ -n "$path" ]; then
		echo "$name=$path"
	else
		echo "$name=missing"
	fi
}

file_state() {
	label=$1
	path=$2
	if [ -f "$path" ]; then
		echo "$label=true"
		wc -c "$path" 2>/dev/null | awk -v label="$label" '{ print label "_size_bytes=" $1 }'
		sha256sum "$path" 2>/dev/null | awk -v label="$label" '{ print label "_sha256=" $1 }'
		return 0
	fi
	echo "$label=false"
	return 1
}

dir_state() {
	label=$1
	path=$2
	if [ -d "$path" ]; then
		echo "$label=true"
		return 0
	fi
	echo "$label=false"
	return 1
}

filesystem_state() {
	label=$1
	name=$2
	if grep -w "$name" /proc/filesystems >/dev/null 2>&1; then
		echo "$label=true"
		return 0
	fi
	echo "$label=false"
	return 1
}

module_hint_state() {
	label=$1
	name=$2
	if find /System/Kernel/Current/modules -name "$name.ko*" 2>/dev/null | sed -n '1p' | grep . >/dev/null 2>&1; then
		echo "$label=true"
		find /System/Kernel/Current/modules -name "$name.ko*" 2>/dev/null | sed -n '1,5p' | awk -v label="$label" '{ print label "_path=" $0 }'
		return 0
	fi
	echo "$label=false"
	return 1
}

contract() {
	cat <<EOF
mixtar_initramfs_handoff_contract=prototype-no-install
prototype_no_install=true
executes_switch_root=false
mounts_rootfs_as_root=false
writes_initramfs=false
writes_bootloader=false
switches_system_current=false
deletes_fallback=false
primary_init=$PRIMARY_INIT
fallback_init=$FALLBACK_INIT
planned_rootfs_image=$ROOTFS_IMAGE_DEFAULT
planned_base_mount=$BASE_MOUNT
planned_image_mount=$IMAGE_MOUNT
	planned_overlay_upper=$OVERLAY_UPPER
	planned_overlay_work=$OVERLAY_WORK
	planned_new_root=$NEW_ROOT
	boot_command_available=true
	executes_switch_root_when_boot_command_runs=true
	boot_command_requires_mixtar_handoff_boot=true
EOF
}

plan() {
	rootfs_arg=$(cmdline_value mixtar.rootfs || echo "$ROOTFS_IMAGE_DEFAULT")
	overlay_arg=$(cmdline_value mixtar.overlay || echo tmpfs)
	fallback_arg=$(cmdline_value mixtar.fallback || echo block-root)
	root_uuid=$(cmdline_value root || true)
	cat <<EOF
initramfs_handoff_prototype_plan=generated
rootfs_arg=$rootfs_arg
overlay_arg=$overlay_arg
fallback_arg=$fallback_arg
current_root_arg=$root_uuid
step01=mount devtmpfs on /dev
step02=mount proc on /proc
step03=mount sysfs on /sys
step04=mount base block root read-only at $BASE_MOUNT
step05=resolve $rootfs_arg from base storage
step06=mount squashfs image read-only at $IMAGE_MOUNT
step07=if overlay is available, create tmpfs upper and work dirs
step08=if overlay is available, mount overlay at $NEW_ROOT
step09=if overlay is unavailable, either use read-only image root or fallback according to policy
step10=validate $PRIMARY_INIT or $FALLBACK_INIT exists under new root
step11=switch_root to validated new root
fallback01=if rootfs image is missing, fall back to block-root boot
fallback02=if squashfs mount fails, fall back to block-root boot
fallback03=if init validation fails, fall back to block-root boot
would_mount_runtime_filesystems=false
would_mount_image=false
would_mount_overlay=false
would_switch_root=false
would_write_initramfs=false
would_change_bootloader=false
would_switch_current=false
activation_allowed=false
EOF
}

mount_runtime_filesystems() {
	mkdir -p /dev /proc /sys /run
	mount -t devtmpfs devtmpfs /dev 2>/dev/null || true
	mount -t proc proc /proc 2>/dev/null || true
	mount -t sysfs sysfs /sys 2>/dev/null || true
}

load_cmdline_modules() {
	modules=$(cmdline_value modules || true)
	if [ -n "$modules" ]; then
		for module in $(printf '%s\n' "$modules" | sed 's/,/ /g'); do
			if [ -n "$module" ]; then
				if modprobe "$module" 2>/dev/null; then
					log_msg "modprobe $module ok"
				else
					log_msg "modprobe $module failed"
				fi
			fi
		done
	fi
	if modprobe squashfs 2>/dev/null; then
		log_msg "modprobe squashfs ok"
	else
		squashfs_loaded=false
		for module_path in /usr/lib/modules/*/kernel/fs/squashfs/squashfs.ko* /lib/modules/*/kernel/fs/squashfs/squashfs.ko*; do
			[ -f "$module_path" ] || continue
			if insmod "$module_path" 2>/dev/null; then
				log_msg "insmod squashfs ok: $module_path"
				squashfs_loaded=true
				break
			fi
		done
		if [ "$squashfs_loaded" != "true" ]; then
			log_msg "modprobe squashfs failed"
		fi
	fi
	if modprobe overlay 2>/dev/null; then
		log_msg "modprobe overlay ok"
	else
		log_msg "modprobe overlay failed"
	fi
	if command -v mdev >/dev/null 2>&1; then
		mdev -s 2>/dev/null || true
		log_msg "mdev scan completed"
	fi
}

resolve_root_device() {
	root_arg=$(cmdline_value root || true)
	case "$root_arg" in
		UUID=*)
			uuid=${root_arg#UUID=}
			if [ -e "/dev/disk/by-uuid/$uuid" ]; then
				readlink -f "/dev/disk/by-uuid/$uuid"
				return 0
			fi
			blkid -U "$uuid" 2>/dev/null && return 0
			for dev in /dev/nvme*n*p* /dev/sd*[0-9]* /dev/vd*[0-9]* /dev/xvd*[0-9]*; do
				[ -b "$dev" ] || continue
				if blkid "$dev" 2>/dev/null | grep -F "UUID=\"$uuid\"" >/dev/null 2>&1; then
					readlink -f "$dev"
					return 0
				fi
			done
			;;
		LABEL=*)
			label=${root_arg#LABEL=}
			blkid -L "$label" 2>/dev/null && return 0
			;;
		/dev/*)
			printf '%s\n' "$root_arg"
			return 0
			;;
	esac
	return 1
}

wait_for_root_device() {
	count=0
	while [ "$count" -lt 20 ]; do
		if root_device=$(resolve_root_device 2>/dev/null); then
			if [ -b "$root_device" ]; then
				printf '%s\n' "$root_device"
				return 0
			fi
		fi
		sleep 1
		count=$((count + 1))
	done
	return 1
}

mount_base_root() {
	root_device=$1
	rootfstype=$(cmdline_value rootfstype || echo ext4)
	rootflags=$(cmdline_value rootflags || echo ro)
	mkdir -p "$BASE_MOUNT"
	mount -t "$rootfstype" -o "$rootflags" "$root_device" "$BASE_MOUNT"
}

rootfs_image_path() {
	rootfs_arg=$(cmdline_value mixtar.rootfs || echo "$ROOTFS_IMAGE_DEFAULT")
	case "$rootfs_arg" in
		/*)
			printf '%s%s\n' "$BASE_MOUNT" "$rootfs_arg"
			;;
		*)
			printf '%s/%s\n' "$BASE_MOUNT" "$rootfs_arg"
			;;
	esac
}

mount_image_root() {
	image=$1
	mkdir -p "$IMAGE_MOUNT"
	mount -t squashfs -o ro "$image" "$IMAGE_MOUNT"
}

mount_overlay_root() {
	overlay_mode=$(cmdline_value mixtar.overlay || echo tmpfs)
	if [ "$overlay_mode" = "readonly" ]; then
		echo "$IMAGE_MOUNT"
		return 0
	fi
	if ! grep -w overlay /proc/filesystems >/dev/null 2>&1; then
		modprobe overlay 2>/dev/null || true
	fi
	mkdir -p "$OVERLAY_ROOT" "$OVERLAY_UPPER" "$OVERLAY_WORK" "$NEW_ROOT"
	mount -t tmpfs tmpfs "$OVERLAY_ROOT" 2>/dev/null || true
	mkdir -p "$OVERLAY_UPPER" "$OVERLAY_WORK" "$NEW_ROOT"
	mount -t overlay overlay -o "lowerdir=$IMAGE_MOUNT,upperdir=$OVERLAY_UPPER,workdir=$OVERLAY_WORK" "$NEW_ROOT"
	echo "$NEW_ROOT"
}

select_init() {
	target_root=$1
	if [ -x "$target_root$PRIMARY_INIT" ]; then
		echo "$PRIMARY_INIT"
		return 0
	fi
	if [ -x "$target_root$FALLBACK_INIT" ]; then
		echo "$FALLBACK_INIT"
		return 0
	fi
	return 1
}

move_runtime_mounts() {
	target_root=$1
	mkdir -p "$target_root/dev" "$target_root/proc" "$target_root/sys" "$target_root/run"
	mount -o move /dev "$target_root/dev" 2>/dev/null || true
	mount -o move /proc "$target_root/proc" 2>/dev/null || true
	mount -o move /sys "$target_root/sys" 2>/dev/null || true
}

boot() {
	log_msg "boot command started"
	mount_runtime_filesystems
	load_cmdline_modules
	if ! root_device=$(wait_for_root_device); then
		log_msg "root device not found"
		return 1
	fi
	log_msg "mounting base root $root_device"
	if ! mount_base_root "$root_device"; then
		log_msg "base root mount failed"
		return 1
	fi
	image=$(rootfs_image_path)
	if [ ! -f "$image" ]; then
		log_msg "rootfs image missing: $image"
		return 1
	fi
	log_msg "mounting rootfs image $image"
	if ! mount_image_root "$image"; then
		log_msg "rootfs image mount failed"
		return 1
	fi
	if ! target_root=$(mount_overlay_root); then
		log_msg "overlay root mount failed"
		return 1
	fi
	if [ "$target_root" = "$IMAGE_MOUNT" ]; then
		base_target="$target_root/System/Runtime/initramfs/base"
		if [ ! -d "$base_target" ]; then
			log_msg "readonly target missing base preserve dir: $base_target"
			return 1
		fi
		if ! mount -o move "$BASE_MOUNT" "$base_target"; then
			log_msg "base root preserve move failed: $base_target"
			return 1
		fi
		log_msg "moved base root into readonly target $base_target"
	fi
	if ! init_path=$(select_init "$target_root"); then
		log_msg "no valid init found in image root"
		return 1
	fi
	log_msg "switch_root target=$target_root init=$init_path"
	move_runtime_mounts "$target_root"
	if [ -x /usr/bin/busybox ]; then
		exec /usr/bin/busybox switch_root "$target_root" "$init_path"
	fi
	exec switch_root "$target_root" "$init_path"
	log_msg "switch_root returned unexpectedly"
	return 1
}

check_live() {
	rc=0
	echo "initramfs_handoff_check_live=generated"
	echo "current_target=$(readlink /System/Current 2>/dev/null || true)"
	echo "kernel_profile_current=$(readlink /System/Kernel/Current 2>/dev/null || true)"
	file_state rootfs_image_ready /System/Generations/0015-rootfs-image-first-file/rootfs.squashfs || rc=1
	file_state kernel_vmlinuz_ready /System/Kernel/Current/vmlinuz || rc=1
	file_state kernel_initramfs_ready /System/Kernel/Current/initramfs.img || rc=1
	dir_state kernel_modules_ready /System/Kernel/Current/modules || rc=1
	filesystem_state kernel_squashfs_ready squashfs || rc=1
	if filesystem_state kernel_overlay_ready overlay; then
		echo "overlay_policy=tmpfs-overlay-available"
	else
		echo "overlay_policy=overlay-unavailable-prototype-must-fallback-or-readonly"
	fi
	module_hint_state overlay_module_present overlay || true
	module_hint_state squashfs_module_present squashfs || true
	module_hint_state loop_module_present loop || true
	tool_state sh
	tool_state mount
	tool_state umount
	tool_state switch_root
	tool_state modprobe
	tool_state insmod
	tool_state blkid
	tool_state readlink
	tool_state sha256sum
	echo "current_cmdline=$(cat /proc/cmdline 2>/dev/null || true)"
	echo "check_live_result=$(if [ "$rc" -eq 0 ]; then echo ok; else echo incomplete; fi)"
	return "$rc"
}

simulate() {
	echo "initramfs_handoff_simulation=non-mutating"
	contract
	plan
	check_live || true
	echo "simulation_result=generated"
	echo "simulation_mounts_performed=false"
	echo "simulation_switch_root_performed=false"
	echo "simulation_initramfs_written=false"
	echo "simulation_bootloader_written=false"
	echo "simulation_current_switched=false"
	echo "boot_command_available=true"
}

command=${1:-}
case "$command" in
	contract)
		contract
		;;
	plan)
		plan
		;;
	check-live)
		check_live
		;;
	simulate)
		simulate
		;;
	boot)
		if boot; then
			log_msg "boot command returned unexpectedly"
		else
			log_msg "boot command failed"
		fi
		if [ -x /init ]; then
			log_msg "fallback to original init from handoff"
			exec /init
		fi
		exit 1
		;;
	*)
		usage
		exit 2
		;;
esac
