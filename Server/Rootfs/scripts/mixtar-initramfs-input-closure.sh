#!/bin/sh
set -u

ROOTFS_IMAGE=/System/Generations/0015-rootfs-image-first-file/rootfs.squashfs
HANDOFF_PROTOTYPE=/System/Initramfs/Prototypes/mixtar-initramfs-handoff.sh
KERNEL_PROFILE=/System/Kernel/Current
MODULE_ROOT=/System/Kernel/Current/modules

REQUIRED_TOOLS="sh mount umount switch_root modprobe insmod blkid readlink mkdir cat grep awk sed sha256sum find"
REQUIRED_MODULES="squashfs overlay loop ext4 nvme jbd2 mbcache"
REQUIRED_MOUNTS="devtmpfs proc sysfs squashfs overlay"

usage() {
	cat >&2 <<EOF
usage: mixtar-initramfs-input-closure <command>

commands:
  contract
  tools
  libraries
  modules
  mounts
  report
EOF
}

contract() {
	cat <<EOF
initramfs_input_closure_contract=prototype-no-build
builds_initramfs=false
writes_initramfs=false
writes_bootloader=false
switches_system_current=false
mounts_rootfs_as_root=false
executes_switch_root=false
rootfs_image=$ROOTFS_IMAGE
handoff_prototype=$HANDOFF_PROTOTYPE
kernel_profile=$KERNEL_PROFILE
module_root=$MODULE_ROOT
required_tools=$REQUIRED_TOOLS
required_modules=$REQUIRED_MODULES
required_mounts=$REQUIRED_MOUNTS
EOF
}

resolve_tool() {
	name=$1
	path=$(command -v "$name" 2>/dev/null || true)
	if [ -n "$path" ]; then
		echo "tool=$name path=$path state=present"
		return 0
	fi
	echo "tool=$name path=missing state=missing"
	return 1
}

tools() {
	missing=0
	echo "tools_report=generated"
	for tool in $REQUIRED_TOOLS; do
		resolve_tool "$tool" || missing=$((missing + 1))
	done
	echo "required_tools_missing=$missing"
}

tool_paths() {
	for tool in $REQUIRED_TOOLS; do
		path=$(command -v "$tool" 2>/dev/null || true)
		if [ -n "$path" ]; then
			echo "$path"
		fi
	done | sort -u
}

library_paths_for() {
	path=$1
	if [ ! -e "$path" ]; then
		return 0
	fi
	ldd "$path" 2>/dev/null | awk '
		{
			for (i = 1; i <= NF; i++) {
				if ($i ~ /^\//) {
					gsub(/\(.*/, "", $i)
					print $i
				}
			}
		}
	'
}

libraries() {
	tmp=/tmp/mixtar-initramfs-libs.$$
	missing=0
	: > "$tmp"
	echo "libraries_report=generated"
	for path in $(tool_paths); do
		library_paths_for "$path" >> "$tmp"
	done
	sort -u "$tmp" | while read -r lib; do
		if [ -z "$lib" ]; then
			continue
		fi
		if [ -e "$lib" ]; then
			echo "library=$lib state=present"
		else
			echo "library=$lib state=missing"
		fi
	done
	for lib in $(sort -u "$tmp"); do
		if [ ! -e "$lib" ]; then
			missing=$((missing + 1))
		fi
	done
	rm -f "$tmp"
	echo "required_libraries_missing=$missing"
}

filesystem_available() {
	name=$1
	grep -w "$name" /proc/filesystems >/dev/null 2>&1
}

module_paths() {
	name=$1
	find "$MODULE_ROOT" -name "$name.ko*" 2>/dev/null | sort
}

module_state() {
	name=$1
	if filesystem_available "$name"; then
		echo "module=$name state=available_or_builtin"
		return 0
	fi
	if [ -d "/sys/module/$name" ]; then
		echo "module=$name state=sys-module-present"
		return 0
	fi
	paths=$(module_paths "$name" | sed -n '1,5p')
	if [ -n "$paths" ]; then
		echo "module=$name state=module-file-present"
		module_paths "$name" | sed -n '1,5p' | while read -r path; do
			echo "module_path=$name:$path"
		done
		return 0
	fi
	echo "module=$name state=missing"
	return 1
}

modules() {
	missing=0
	echo "modules_report=generated"
	for module in $REQUIRED_MODULES; do
		module_state "$module" || missing=$((missing + 1))
	done
	echo "required_modules_missing=$missing"
}

mounts() {
	echo "mounts_report=generated"
	for fs in $REQUIRED_MOUNTS; do
		if filesystem_available "$fs"; then
			echo "mount_fs=$fs state=available"
		else
			echo "mount_fs=$fs state=missing"
		fi
	done
}

count_missing_from() {
	key=$1
	file=$2
	awk -F= -v key="$key" '$1 == key { print $2; exit }' "$file"
}

report() {
	base=/tmp/mixtar-initramfs-closure.$$
	mkdir -p "$base"
	contract > "$base/contract"
	tools > "$base/tools"
	libraries > "$base/libraries"
	modules > "$base/modules"
	mounts > "$base/mounts"
	tool_missing=$(count_missing_from required_tools_missing "$base/tools")
	lib_missing=$(count_missing_from required_libraries_missing "$base/libraries")
	module_missing=$(count_missing_from required_modules_missing "$base/modules")
	overlay_state=$(awk '$1 == "module=overlay" { sub(/^state=/, "", $2); print $2; exit }' "$base/modules")
	echo "initramfs_input_closure_report=generated"
	cat "$base/contract"
	cat "$base/tools"
	cat "$base/libraries"
	cat "$base/modules"
	cat "$base/mounts"
	echo "required_tools_missing=$tool_missing"
	echo "required_libraries_missing=$lib_missing"
	echo "required_modules_missing=$module_missing"
	echo "overlay_state=${overlay_state:-unknown}"
	if [ -f "$ROOTFS_IMAGE" ]; then
		echo "rootfs_image_ready=true"
		wc -c "$ROOTFS_IMAGE" | awk '{ print "rootfs_size_bytes=" $1 }'
		sha256sum "$ROOTFS_IMAGE" | awk '{ print "rootfs_sha256=" $1 }'
	else
		echo "rootfs_image_ready=false"
	fi
	if [ -x "$HANDOFF_PROTOTYPE" ]; then
		echo "handoff_prototype_ready=true"
	else
		echo "handoff_prototype_ready=false"
	fi
	echo "initramfs_build_inputs_ready=false"
	echo "activation_allowed=false"
	echo "ready_blocker=overlay support is missing or not exposed in current kernel profile"
	echo "ready_blocker=initramfs builder has not produced a candidate image"
	echo "next_required_stage=0024-overlay-support-decision"
	rm -rf "$base"
}

command=${1:-}
case "$command" in
	contract)
		contract
		;;
	tools)
		tools
		;;
	libraries)
		libraries
		;;
	modules)
		modules
		;;
	mounts)
		mounts
		;;
	report)
		report
		;;
	*)
		usage
		exit 2
		;;
esac
