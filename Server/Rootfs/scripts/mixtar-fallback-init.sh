#!/bin/sh
set -u

PATH=/System/Tools/Current/bin:/System/Tools/MixtarRVS/bin:/System/SystemTools:/sbin:/bin:/usr/sbin:/usr/bin
export PATH

NATIVE_INIT=/System/SystemTools/init
FALLBACK_INIT=/sbin/init

native_init_ready() {
	if [ ! -x "$NATIVE_INIT" ]; then
		return 1
	fi
	target=$(readlink "$NATIVE_INIT" 2>/dev/null || true)
	if [ "$target" = "/bin/busybox" ]; then
		return 1
	fi
	return 0
}

is_mounted() {
	target=$1
	awk -v target="$target" '$2 == target { found = 1 } END { exit found ? 0 : 1 }' /proc/mounts 2>/dev/null
}

ensure_dir() {
	path=$1
	mode=$2
	if [ ! -e "$path" ]; then
		mkdir -p "$path"
		chmod "$mode" "$path" 2>/dev/null || true
	fi
}

mount_if_needed() {
	fstype=$1
	source=$2
	target=$3
	options=$4
	ensure_dir "$target" 0755
	if is_mounted "$target"; then
		return 0
	fi
	mount -t "$fstype" -o "$options" "$source" "$target"
}

bind_if_needed() {
	source=$1
	target=$2
	mode=$3
	ensure_dir "$target" "$mode"
	if is_mounted "$target"; then
		return 0
	fi
	mount --bind "$source" "$target"
}

prepare_runtime() {
	ensure_dir /System 0755
	ensure_dir /System/Devices 0755
	ensure_dir /System/Process 0755
	ensure_dir /System/Hardware 0755
	ensure_dir /System/Runtime 0755
	ensure_dir /System/Runtime/run 0755
	ensure_dir /Temporary 1777

	mount_if_needed devtmpfs devtmpfs /dev mode=0755,nosuid
	mount_if_needed proc proc /proc nosuid,nodev,noexec
	mount_if_needed sysfs sysfs /sys nosuid,nodev,noexec
	mount_if_needed tmpfs tmpfs /run mode=0755,nosuid,nodev
	mount_if_needed tmpfs tmpfs /tmp mode=1777,nosuid,nodev

	bind_if_needed /dev /System/Devices 0755
	bind_if_needed /proc /System/Process 0755
	bind_if_needed /sys /System/Hardware 0755
	bind_if_needed /run /System/Runtime/run 0755
	bind_if_needed /tmp /Temporary 1777
}

check_runtime() {
	rc=0
	for path in /System /System/Tools/Current/bin/sh /System/Libraries/MixtarRVS/Runtime/0003/lib /dev /proc /sys /run /tmp "$FALLBACK_INIT"; do
		if [ ! -e "$path" ]; then
			printf 'missing %s\n' "$path" >&2
			rc=1
		fi
	done
	if native_init_ready; then
		printf 'native-init=%s\n' "$NATIVE_INIT"
	elif [ -e "$NATIVE_INIT" ]; then
		printf 'native-init=compat-fallback:%s\n' "$NATIVE_INIT"
	else
		printf 'native-init=not-yet-present\n'
	fi
	if [ -x "$FALLBACK_INIT" ]; then
		printf 'fallback-init=%s\n' "$FALLBACK_INIT"
	else
		printf 'fallback-init=missing\n' >&2
		rc=1
	fi
	return "$rc"
}

exec_init() {
	if native_init_ready; then
		exec "$NATIVE_INIT"
	fi
	exec "$FALLBACK_INIT"
}

contract() {
	cat <<EOF
MixtarRVS fallback init shim contract:
  default mode: check only
  --prepare: mount kernel/runtime views and Mixtar native bind views
  --exec: prepare runtime, then exec /System/SystemTools/init when present, otherwise /sbin/init

Native views:
  /System/Devices -> /dev
  /System/Process -> /proc
  /System/Hardware -> /sys
  /System/Runtime/run -> /run
  /Temporary -> /tmp

Fallbacks kept:
  /sbin/init
  OpenRC services
  compatibility POSIX paths
EOF
}

mode=${1:-}
if [ -z "$mode" ]; then
	mode=--check
fi

case "$mode" in
	--check)
		check_runtime
		;;
	--contract)
		contract
		;;
	--prepare)
		prepare_runtime
		;;
	--exec)
		prepare_runtime
		exec_init
		;;
	*)
		printf 'usage: %s [--check|--contract|--prepare|--exec]\n' "$0" >&2
		exit 2
		;;
esac
