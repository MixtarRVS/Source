#!/bin/sh
set -eu

ROOTFS_SRC=/System/Generations/0022-rootfs-image-pid1-log-autoreboot-rw/rootfs.squashfs
ROOTFS_GEN=/System/Generations/0023-rootfs-image-openrc-watchdog
ROOTFS_OUT=$ROOTFS_GEN/rootfs.squashfs

REPORT=/System/Base/Closure/0070-openrc-image-root-watchdog.report
ROOT_WORK=/tmp/mixtar-rootfs-0023.$$
VERIFY=/tmp/mixtar-0070-verify.$$

ESP_DEV=/dev/nvme0n1p1
ESP_MOUNT=/tmp/mixtar-esp-0070

LABEL="MixtarRVS RT Candidate 0070 openrc image-root watchdog"
LOADER="\\EFI\\mixtarrvs-rt\\vmlinuz.efi"
INITRD="\\EFI\\mixtarrvs-rt\\initrd-mixtar-candidate-0069.img"
ROOTFS_ARG=/System/Generations/0023-rootfs-image-openrc-watchdog/rootfs.squashfs

mounted_by_script=false

cleanup() {
	if [ "$mounted_by_script" = true ]; then
		sudo -n umount "$ESP_MOUNT" >/dev/null 2>&1 || true
	fi
	sudo -n rmdir "$ESP_MOUNT" >/dev/null 2>&1 || true
	sudo -n umount "$VERIFY/rootfs" >/dev/null 2>&1 || true
	sudo -n rm -rf "$ROOT_WORK" "$VERIFY"
}

trap cleanup EXIT

need_file() {
	if [ ! -f "$1" ]; then
		echo "missing file: $1" >&2
		exit 1
	fi
}

need_absent() {
	if [ -e "$1" ]; then
		echo "target already exists: $1" >&2
		exit 1
	fi
}

need_file "$ROOTFS_SRC"
need_absent "$ROOTFS_GEN"

sudo -n mkdir -p /System/Base/Closure "$ROOTFS_GEN"
sudo -n mkdir -p "$ROOT_WORK/root" "$VERIFY/rootfs"

rootfs_src_sha=$(sha256sum "$ROOTFS_SRC" | awk '{ print $1 }')

sudo -n unsquashfs -d "$ROOT_WORK/root" "$ROOTFS_SRC" >/tmp/mixtar-0070-unsquashfs.log 2>&1 || {
	cat /tmp/mixtar-0070-unsquashfs.log
	exit 1
}

sudo -n mkdir -p "$ROOT_WORK/root/dev" "$ROOT_WORK/root/proc" "$ROOT_WORK/root/sys" "$ROOT_WORK/root/run" "$ROOT_WORK/root/tmp"
sudo -n mkdir -p "$ROOT_WORK/root/System/Runtime/initramfs/base"
sudo -n mkdir -p "$ROOT_WORK/root/System/Runtime/diagnostics"

sudo -n rm -f "$ROOT_WORK/root/sbin/init"
sudo -n tee "$ROOT_WORK/root/sbin/init" >/dev/null <<'EOS'
#!/bin/sh

BASE_LOG_DIR=/System/Runtime/initramfs/base/System/Base/Closure
LOG=$BASE_LOG_DIR/0070-after-switch-root.log

append_log() {
	mkdir -p "$BASE_LOG_DIR" 2>/dev/null || true
	printf '%s\n' "$1" >>"$LOG" 2>/dev/null || true
}

mount_if_missing() {
	target=$1
	type=$2
	source=$3
	options=${4:-}
	if ! awk -v target="$target" '$2 == target { found=1 } END { exit found ? 0 : 1 }' /proc/mounts 2>/dev/null; then
		if [ -n "$options" ]; then
			mount -t "$type" -o "$options" "$source" "$target" >>"$LOG" 2>&1 || true
		else
			mount -t "$type" "$source" "$target" >>"$LOG" 2>&1 || true
		fi
	fi
}

ensure_node() {
	path=$1
	mode=$2
	major=$3
	minor=$4
	if [ ! -e "$path" ]; then
		mknod -m "$mode" "$path" c "$major" "$minor" >>"$LOG" 2>&1 || true
	fi
}

write_snapshot() {
	{
		echo "stage=0070-after-switch-root"
		echo "pid=$$"
		echo "cmdline=$(cat /proc/cmdline 2>/dev/null || true)"
		echo "root_mount=$(awk '$2 == "/" { print; exit }' /proc/mounts 2>/dev/null || true)"
		echo "base_mount=$(awk '$2 == "/System/Runtime/initramfs/base" { print; exit }' /proc/mounts 2>/dev/null || true)"
		echo "dev_mount=$(awk '$2 == "/dev" { print; exit }' /proc/mounts 2>/dev/null || true)"
		echo "run_mount=$(awk '$2 == "/run" { print; exit }' /proc/mounts 2>/dev/null || true)"
		echo "tmp_mount=$(awk '$2 == "/tmp" { print; exit }' /proc/mounts 2>/dev/null || true)"
		echo "dev_nodes_begin"
		ls -l /dev/console /dev/tty /dev/tty0 /dev/tty1 /dev/null /dev/zero 2>&1 || true
		echo "dev_nodes_end"
		echo "init_files_begin"
		ls -l /sbin/init /bin/busybox /sbin/openrc 2>&1 || true
		echo "init_files_end"
		echo "inittab_begin"
		sed -n '1,120p' /etc/inittab 2>/dev/null || true
		echo "inittab_end"
		echo "rootfs_marker_begin"
		cat /System/Runtime/rootfs-image-mode 2>/dev/null || true
		echo "rootfs_marker_end"
		echo "mounts_begin"
		cat /proc/mounts 2>/dev/null || true
		echo "mounts_end"
	} >>"$LOG" 2>&1 || true
}

start_watchdog() {
	(
		sleep 180
		mkdir -p "$BASE_LOG_DIR" 2>/dev/null || true
		{
			echo "stage=0070-watchdog-reboot"
			echo "reason=timeout"
			echo "cmdline=$(cat /proc/cmdline 2>/dev/null || true)"
			echo "mounts_begin"
			cat /proc/mounts 2>/dev/null || true
			echo "mounts_end"
		} >>"$BASE_LOG_DIR/0070-watchdog-reboot.log" 2>&1 || true
		sync
		if [ -w /proc/sysrq-trigger ]; then
			echo b > /proc/sysrq-trigger
		fi
		/bin/busybox reboot -f 2>/dev/null || true
		reboot -f 2>/dev/null || true
	) &
}

mkdir -p "$BASE_LOG_DIR" 2>/dev/null || true
append_log "0070 openrc image-root pid1 wrapper started"

mount_if_missing /proc proc proc
mount_if_missing /sys sysfs sysfs
if ! awk '$2 == "/dev" && $3 == "devtmpfs" { found=1 } END { exit found ? 0 : 1 }' /proc/mounts 2>/dev/null; then
	mount -t devtmpfs devtmpfs /dev >>"$LOG" 2>&1 || mount -t tmpfs tmpfs /dev >>"$LOG" 2>&1 || true
fi
mkdir -p /dev/pts /dev/shm /run /tmp 2>/dev/null || true
mount_if_missing /dev/pts devpts devpts
mount_if_missing /run tmpfs tmpfs mode=755
mount_if_missing /tmp tmpfs tmpfs mode=1777

ensure_node /dev/console 600 5 1
ensure_node /dev/tty 666 5 0
ensure_node /dev/tty0 620 4 0
ensure_node /dev/tty1 620 4 1
ensure_node /dev/null 666 1 3
ensure_node /dev/zero 666 1 5
ensure_node /dev/random 666 1 8
ensure_node /dev/urandom 666 1 9

if command -v mdev >/dev/null 2>&1; then
	mdev -s >>"$LOG" 2>&1 || true
fi

write_snapshot
append_log "0070 starting watchdog and execing busybox init"
sync
start_watchdog
exec /bin/busybox init

append_log "0070 busybox init exec failed"
while :; do
	sleep 60
done
EOS

sudo -n chmod 755 "$ROOT_WORK/root/sbin/init"

sudo -n tee "$ROOT_WORK/root/System/Runtime/rootfs-image-mode" >/dev/null <<'EOS'
rootfs_mode=image-readonly-openrc-watchdog
source_generation=0022-rootfs-image-pid1-log-autoreboot-rw
base_preserve_mountpoint=/System/Runtime/initramfs/base
init_wrapper=/sbin/init
init_exec=/bin/busybox init
watchdog_reboot_seconds=180
runtime_mounts=devtmpfs,proc,sysfs,devpts,run-tmpfs,tmp-tmpfs
EOS

sudo -n mksquashfs "$ROOT_WORK/root" "$ROOTFS_OUT" -noappend -no-progress >/tmp/mixtar-0070-mksquashfs.log 2>&1 || {
	cat /tmp/mixtar-0070-mksquashfs.log
	exit 1
}

rootfs_out_sha=$(sha256sum "$ROOTFS_OUT" | awk '{ print $1 }')
rootfs_out_size=$(wc -c <"$ROOTFS_OUT" | tr -d ' ')

sudo -n mount -o loop,ro -t squashfs "$ROOTFS_OUT" "$VERIFY/rootfs"
verify_rootfs_marker=$(sudo -n cat "$VERIFY/rootfs/System/Runtime/rootfs-image-mode" 2>/dev/null || true)
verify_rootfs_init=$(sudo -n grep -n -E '0070-after-switch-root|busybox init|watchdog|/run tmpfs|tty0' "$VERIFY/rootfs/sbin/init" 2>/dev/null || true)
verify_mountpoints=$(sudo -n ls -ld "$VERIFY/rootfs/dev" "$VERIFY/rootfs/proc" "$VERIFY/rootfs/sys" "$VERIFY/rootfs/run" "$VERIFY/rootfs/tmp" 2>/dev/null || true)
sudo -n umount "$VERIFY/rootfs"

printf '%s\n' "$verify_rootfs_marker" | grep -q 'rootfs_mode=image-readonly-openrc-watchdog' || {
	echo "rootfs 0023 openrc watchdog marker missing" >&2
	exit 1
}
printf '%s\n' "$verify_rootfs_init" | grep -q 'busybox init' || {
	echo "rootfs 0023 busybox init verification failed" >&2
	exit 1
}

sudo -n mkdir -p "$ESP_MOUNT"
if ! awk -v d="$ESP_DEV" '$1 == d { found=1 } END { exit found ? 0 : 1 }' /proc/mounts; then
	sudo -n mount -t vfat "$ESP_DEV" "$ESP_MOUNT"
	mounted_by_script=true
else
	ESP_MOUNT=$(awk -v d="$ESP_DEV" '$1 == d { print $2; exit }' /proc/mounts)
fi

need_file "$ESP_MOUNT/EFI/mixtarrvs-rt/initrd-mixtar-candidate-0069.img"
need_file "$ESP_MOUNT/EFI/mixtarrvs-rt/vmlinuz.efi"

root_uuid=$(blkid -s UUID -o value /dev/nvme0n1p3 2>/dev/null || true)
if [ -z "$root_uuid" ]; then
	echo "root UUID not found" >&2
	exit 1
fi

before_order=$(sudo -n efibootmgr | awk -F': ' '/^BootOrder:/ { print $2; exit }')
before_next=$(sudo -n efibootmgr | awk -F': ' '/^BootNext:/ { print $2; exit }')

cmdline="initrd=$INITRD rdinit=/mixtar-init root=UUID=$root_uuid rootfstype=ext4 rootflags=ro modules=nvme,ext4,jbd2,mbcache rootwait ro quiet loglevel=3 threadirqs mixtar.profile=rt-7.1.2-mixtar-rt mixtar.rootfs=$ROOTFS_ARG mixtar.overlay=readonly mixtar.fallback=previous mixtar.handoff=boot"

sudo -n efibootmgr -c -d /dev/nvme0n1 -p 1 -L "$LABEL" -l "$LOADER" -u "$cmdline" >/tmp/mixtar-0070-efibootmgr-create.log 2>&1 || {
	cat /tmp/mixtar-0070-efibootmgr-create.log
	exit 1
}

created=$(sudo -n efibootmgr | awk -v label="$LABEL" 'index($0,label) { gsub(/^Boot/, "", $1); gsub(/\*/, "", $1); print $1 }' | tail -1)
if [ -z "$created" ]; then
	echo "created boot entry not found" >&2
	exit 1
fi

sudo -n efibootmgr -o "$before_order" >/tmp/mixtar-0070-efibootmgr-order.log 2>&1 || {
	cat /tmp/mixtar-0070-efibootmgr-order.log
	exit 1
}

after_order=$(sudo -n efibootmgr | awk -F': ' '/^BootOrder:/ { print $2; exit }')
after_next=$(sudo -n efibootmgr | awk -F': ' '/^BootNext:/ { print $2; exit }')

{
	echo "stage=0070-openrc-image-root-watchdog"
	echo "status=verified"
	echo "rootfs_source=$ROOTFS_SRC"
	echo "rootfs_source_sha256=$rootfs_src_sha"
	echo "rootfs_target=$ROOTFS_OUT"
	echo "rootfs_target_sha256=$rootfs_out_sha"
	echo "rootfs_target_size_bytes=$rootfs_out_size"
	echo "initrd_reused=$INITRD"
	echo "rootfs_arg=$ROOTFS_ARG"
	echo "overlay_mode=readonly"
	echo "primary_init=/sbin/init"
	echo "init_exec=/bin/busybox init"
	echo "watchdog_reboot_seconds=180"
	echo "label=$LABEL"
	echo "candidate_bootnum=$created"
	echo "boot_order_before=$before_order"
	echo "boot_order_after=$after_order"
	echo "boot_order_preserved=$([ "$before_order" = "$after_order" ] && echo true || echo false)"
	echo "bootnext_before=${before_next:-none}"
	echo "bootnext_after=${after_next:-none}"
	echo "sets_boot_next=false"
	echo "reboots_system=false"
	echo "verify_rootfs_marker_begin"
	printf '%s\n' "$verify_rootfs_marker"
	echo "verify_rootfs_marker_end"
	echo "verify_rootfs_init_begin"
	printf '%s\n' "$verify_rootfs_init"
	echo "verify_rootfs_init_end"
	echo "verify_mountpoints_begin"
	printf '%s\n' "$verify_mountpoints"
	echo "verify_mountpoints_end"
	echo "next_required_stage=0071-set-bootnext-one-shot-openrc-watchdog-test"
} | sudo -n tee "$REPORT" >/dev/null

cat "$REPORT"
printf 'EFIBOOT_FILTERED=\n'
sudo -n efibootmgr | awk -v boot="Boot$created" '/^BootCurrent:|^BootNext:|^BootOrder:/ { print } index($0, boot) == 1 { print } /^Boot0006\*/ { print }'
