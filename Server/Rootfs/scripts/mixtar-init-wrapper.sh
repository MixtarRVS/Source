#!/bin/sh
set -u

PATH=/sbin:/bin:/usr/sbin:/usr/bin
export PATH

ORIGINAL_INIT=/init.alpine
HANDOFF=/usr/bin/mixtar-initramfs-handoff

install_busybox_applets() {
	if [ -x /usr/bin/busybox ]; then
		/usr/bin/busybox --install -s /usr/bin 2>/dev/null || true
	fi
}

mount_early_runtime_filesystems() {
	mkdir -p /dev /proc /sys
	mount -t devtmpfs devtmpfs /dev 2>/dev/null || true
	mount -t proc proc /proc 2>/dev/null || true
	mount -t sysfs sysfs /sys 2>/dev/null || true
}

log_msg() {
	msg=$1
	if [ -e /dev/kmsg ]; then
		printf '<3>mixtar-init: %s\n' "$msg" > /dev/kmsg
	fi
	printf 'mixtar-init: %s\n' "$msg"
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

fallback_original() {
	reason=$1
	log_msg "fallback to original init: $reason"
	exec "$ORIGINAL_INIT"
}

install_busybox_applets
mount_early_runtime_filesystems

rootfs=$(cmdline_value mixtar.rootfs || true)
handoff_mode=$(cmdline_value mixtar.handoff || true)
log_msg "wrapper started rootfs=${rootfs:-none} handoff=${handoff_mode:-none}"

if [ -z "$rootfs" ]; then
	fallback_original "no mixtar.rootfs"
fi

if [ ! -x "$HANDOFF" ]; then
	fallback_original "handoff tool missing"
fi

if [ "$handoff_mode" != "boot" ]; then
	log_msg "mixtar.rootfs present but mixtar.handoff=boot not set"
	"$HANDOFF" simulate || true
	fallback_original "handoff not armed"
fi

log_msg "attempting Mixtar handoff boot"
exec "$HANDOFF" boot
log_msg "handoff exec failed"

fallback_original "handoff exec failed"
