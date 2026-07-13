#!/bin/sh
set -u

KERNEL_PROFILE=/System/Kernel/Current
KERNEL_CONFIG=/System/Kernel/Current/config
MODULE_ROOT=/lib/modules/$(uname -r)
OVERLAY_MODULE_REL=kernel/fs/overlayfs/overlay.ko.xz
OVERLAY_MODULE=$MODULE_ROOT/$OVERLAY_MODULE_REL

usage() {
	cat >&2 <<EOF
usage: mixtar-overlay-support-decision <command>

commands:
  contract
  probe
  decision
EOF
}

config_value() {
	key=$1
	if [ -f "$KERNEL_CONFIG" ]; then
		awk -F= -v key="$key" '$1 == key { print $2; exit }' "$KERNEL_CONFIG"
	fi
}

contract() {
	cat <<EOF
overlay_support_decision_contract=non-mutating
builds_kernel=false
writes_kernel=false
builds_initramfs=false
writes_initramfs=false
writes_bootloader=false
switches_system_current=false
loads_overlay_module=false
mounts_overlay=false
kernel_profile=$KERNEL_PROFILE
kernel_config=$KERNEL_CONFIG
module_root=$MODULE_ROOT
EOF
}

probe() {
	echo "overlay_probe=generated"
	echo "uname=$(uname -r)"
	echo "kernel_profile_current=$(readlink "$KERNEL_PROFILE" 2>/dev/null || true)"
	if [ -f "$KERNEL_CONFIG" ]; then
		echo "kernel_config_ready=true"
	else
		echo "kernel_config_ready=false"
	fi
	value=$(config_value CONFIG_OVERLAY_FS)
	if [ -n "$value" ]; then
		echo "config_overlay_fs=$value"
	else
		echo "config_overlay_fs=missing"
	fi
	if grep -w overlay /proc/filesystems >/dev/null 2>&1; then
		echo "overlay_filesystem_loaded=true"
	else
		echo "overlay_filesystem_loaded=false"
	fi
	if [ -d /sys/module/overlay ]; then
		echo "overlay_sys_module_loaded=true"
	else
		echo "overlay_sys_module_loaded=false"
	fi
	if [ -f "$OVERLAY_MODULE" ]; then
		echo "overlay_module_file_ready=true"
		echo "overlay_module_path=$OVERLAY_MODULE"
		wc -c "$OVERLAY_MODULE" | awk '{ print "overlay_module_size_bytes=" $1 }'
		sha256sum "$OVERLAY_MODULE" | awk '{ print "overlay_module_sha256=" $1 }'
	else
		echo "overlay_module_file_ready=false"
	fi
	echo "modprobe_dryrun_begin"
	if modprobe -n -v overlay 2>&1; then
		echo "modprobe_dryrun_result=ok"
	else
		echo "modprobe_dryrun_result=failed"
	fi
	echo "modprobe_dryrun_end"
}

decision() {
	config=$(config_value CONFIG_OVERLAY_FS)
	echo "overlay_decision=generated"
	probe
	if [ "$config" = "m" ] && [ -f "$OVERLAY_MODULE" ]; then
		echo "overlay_support_state=available-as-module"
		echo "kernel_rebuild_required=false"
		echo "initramfs_must_include_overlay_module=true"
		echo "initramfs_module_source=$OVERLAY_MODULE"
		echo "primary_boot_policy=squashfs-readonly-plus-writable-overlay"
		echo "readonly_image_boot_policy=emergency-or-diagnostic-only"
		echo "activation_allowed=false"
		echo "activation_blocker=initramfs module closure and candidate image not built"
		echo "next_required_stage=0025-initramfs-module-closure-overlay"
		return 0
	fi
	if [ "$config" = "y" ]; then
		echo "overlay_support_state=built-in"
		echo "kernel_rebuild_required=false"
		echo "initramfs_must_include_overlay_module=false"
		echo "primary_boot_policy=squashfs-readonly-plus-writable-overlay"
		echo "readonly_image_boot_policy=emergency-or-diagnostic-only"
		echo "activation_allowed=false"
		echo "activation_blocker=initramfs candidate image not built"
		echo "next_required_stage=0025-initramfs-candidate-no-install"
		return 0
	fi
	echo "overlay_support_state=missing"
	echo "kernel_rebuild_required=true"
	echo "initramfs_must_include_overlay_module=false"
	echo "primary_boot_policy=blocked-until-overlay-support"
	echo "readonly_image_boot_policy=diagnostic-only-not-primary"
	echo "activation_allowed=false"
	echo "activation_blocker=overlay support missing from kernel profile"
	echo "next_required_stage=0025-kernel-overlay-profile-rebuild-plan"
	return 1
}

command=${1:-}
case "$command" in
	contract)
		contract
		;;
	probe)
		probe
		;;
	decision)
		decision
		;;
	*)
		usage
		exit 2
		;;
esac
