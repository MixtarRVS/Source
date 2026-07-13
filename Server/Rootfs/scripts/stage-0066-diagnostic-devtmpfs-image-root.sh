#!/bin/sh
set -eu

ROOTFS_SRC=/System/Generations/0019-rootfs-image-diagnostic-init/rootfs.squashfs
ROOTFS_GEN=/System/Generations/0020-rootfs-image-diagnostic-devtmpfs
ROOTFS_OUT=$ROOTFS_GEN/rootfs.squashfs

INITRD_SRC=/System/Initramfs/Candidates/0065-diagnostic-image-root-candidate-no-install/initramfs.img
REPORT=/System/Base/Closure/0066-diagnostic-devtmpfs-image-root.report

ROOT_WORK=/tmp/mixtar-rootfs-0020.$$
VERIFY=/tmp/mixtar-0066-verify.$$

ESP_DEV=/dev/nvme0n1p1
ESP_MOUNT=/tmp/mixtar-esp-0066

LABEL="MixtarRVS RT Candidate 0066 diagnostic devtmpfs"
LOADER="\\EFI\\mixtarrvs-rt\\vmlinuz.efi"
INITRD="\\EFI\\mixtarrvs-rt\\initrd-mixtar-candidate-0065.img"
ROOTFS_ARG=/System/Generations/0020-rootfs-image-diagnostic-devtmpfs/rootfs.squashfs

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
need_file "$INITRD_SRC"
need_absent "$ROOTFS_GEN"

sudo -n mkdir -p /System/Base/Closure "$ROOTFS_GEN"
sudo -n mkdir -p "$ROOT_WORK/root" "$VERIFY/rootfs"

rootfs_src_sha=$(sha256sum "$ROOTFS_SRC" | awk '{ print $1 }')
initrd_src_sha=$(sha256sum "$INITRD_SRC" | awk '{ print $1 }')

sudo -n unsquashfs -d "$ROOT_WORK/root" "$ROOTFS_SRC" >/tmp/mixtar-0066-unsquashfs.log 2>&1 || {
	cat /tmp/mixtar-0066-unsquashfs.log
	exit 1
}

sudo -n mkdir -p "$ROOT_WORK/root/System/Runtime/initramfs/base"
sudo -n mkdir -p "$ROOT_WORK/root/System/Runtime/diagnostics"

if [ -e "$ROOT_WORK/root/sbin/init" ]; then
	sudo -n rm -f "$ROOT_WORK/root/sbin/init"
fi

sudo -n tee "$ROOT_WORK/root/sbin/init" >/dev/null <<'EOS'
#!/bin/sh

BASE_LOG_DIR=/System/Runtime/initramfs/base/System/Base/Closure
LOG=$BASE_LOG_DIR/0066-after-switch-root.log

log_line() {
	mkdir -p "$BASE_LOG_DIR" 2>/dev/null || true
	printf '%s\n' "$1" >>"$LOG" 2>/dev/null || true
}

mount_if_missing() {
	target=$1
	type=$2
	source=$3
	if ! awk -v target="$target" '$2 == target { found=1 } END { exit found ? 0 : 1 }' /proc/mounts 2>/dev/null; then
		mount -t "$type" "$source" "$target" >>"$LOG" 2>&1 || true
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
		echo "stage=0066-after-switch-root"
		echo "pid=$$"
		echo "cmdline=$(cat /proc/cmdline 2>/dev/null || true)"
		echo "root_mount=$(awk '$2 == "/" { print; exit }' /proc/mounts 2>/dev/null || true)"
		echo "dev_mount=$(awk '$2 == "/dev" { print; exit }' /proc/mounts 2>/dev/null || true)"
		echo "dev_nodes_begin"
		ls -l /dev/console /dev/tty /dev/tty0 /dev/tty1 /dev/null /dev/zero 2>&1 || true
		echo "dev_nodes_end"
		echo "rootfs_marker_begin"
		cat /System/Runtime/rootfs-image-mode 2>/dev/null || true
		echo "rootfs_marker_end"
		echo "mounts_begin"
		cat /proc/mounts 2>/dev/null || true
		echo "mounts_end"
	} >>"$LOG" 2>&1 || true
}

mkdir -p "$BASE_LOG_DIR" 2>/dev/null || true
log_line "0066 init wrapper started"

mount_if_missing /proc proc proc
mount_if_missing /sys sysfs sysfs

if ! awk '$2 == "/dev" && $3 == "devtmpfs" { found=1 } END { exit found ? 0 : 1 }' /proc/mounts 2>/dev/null; then
	mount -t devtmpfs devtmpfs /dev >>"$LOG" 2>&1 || mount -t tmpfs tmpfs /dev >>"$LOG" 2>&1 || true
fi

mkdir -p /dev/pts /dev/shm 2>/dev/null || true
mount_if_missing /dev/pts devpts devpts

ensure_node /dev/console 600 5 1
ensure_node /dev/tty 666 5 0
ensure_node /dev/tty0 620 4 0
ensure_node /dev/tty1 620 4 1
ensure_node /dev/tty2 620 4 2
ensure_node /dev/tty3 620 4 3
ensure_node /dev/tty4 620 4 4
ensure_node /dev/tty5 620 4 5
ensure_node /dev/tty6 620 4 6
ensure_node /dev/null 666 1 3
ensure_node /dev/zero 666 1 5
ensure_node /dev/random 666 1 8
ensure_node /dev/urandom 666 1 9

if command -v mdev >/dev/null 2>&1; then
	mdev -s >>"$LOG" 2>&1 || true
fi

write_snapshot
exec /bin/busybox init
EOS

sudo -n chmod 755 "$ROOT_WORK/root/sbin/init"

sudo -n tee "$ROOT_WORK/root/etc/init.d/mixtar-image-root-report" >/dev/null <<'EOS'
#!/sbin/openrc-run

description="Write Mixtar image-root diagnostics to preserved base root"

depend()
{
	after root devfs
	before dhcpcd iwd sshd
}

start()
{
	local log=/System/Runtime/initramfs/base/System/Base/Closure/0066-openrc-report.log
	ebegin "Writing Mixtar image-root devtmpfs diagnostics"
	mkdir -p /System/Runtime/initramfs/base/System/Base/Closure 2>/dev/null || true
	{
		echo "stage=0066-openrc-report"
		echo "service_pid=$$"
		echo "root_mount=$(awk '$2 == "/" { print; exit }' /proc/mounts 2>/dev/null || true)"
		echo "dev_mount=$(awk '$2 == "/dev" { print; exit }' /proc/mounts 2>/dev/null || true)"
		echo "dev_nodes_begin"
		ls -l /dev/console /dev/tty /dev/tty0 /dev/tty1 /dev/null /dev/zero 2>&1 || true
		echo "dev_nodes_end"
		echo "ip_addr_begin"
		ip addr 2>/dev/null || true
		echo "ip_addr_end"
		echo "rc_status_begin"
		rc-status 2>/dev/null || true
		echo "rc_status_end"
		echo "mounts_begin"
		cat /proc/mounts 2>/dev/null || true
		echo "mounts_end"
	} >>"$log" 2>&1 || true
	eend 0
}
EOS

sudo -n chmod 755 "$ROOT_WORK/root/etc/init.d/mixtar-image-root-report"
sudo -n mkdir -p "$ROOT_WORK/root/etc/runlevels/default"
sudo -n ln -sf /etc/init.d/mixtar-image-root-report "$ROOT_WORK/root/etc/runlevels/default/mixtar-image-root-report"

sudo -n tee "$ROOT_WORK/root/System/Runtime/rootfs-image-mode" >/dev/null <<'EOS'
rootfs_mode=image-readonly-diagnostic-devtmpfs
source_generation=0019-rootfs-image-diagnostic-init
fstab_block_root_disabled=true
openrc_root_service=noop
base_preserve_mountpoint=/System/Runtime/initramfs/base
diagnostic_init=/sbin/init
diagnostic_init_devtmpfs=true
diagnostic_openrc_service=mixtar-image-root-report
EOS

sudo -n mksquashfs "$ROOT_WORK/root" "$ROOTFS_OUT" -noappend -no-progress >/tmp/mixtar-0066-mksquashfs.log 2>&1 || {
	cat /tmp/mixtar-0066-mksquashfs.log
	exit 1
}

rootfs_out_sha=$(sha256sum "$ROOTFS_OUT" | awk '{ print $1 }')
rootfs_out_size=$(wc -c <"$ROOTFS_OUT" | tr -d ' ')

sudo -n mount -o loop,ro -t squashfs "$ROOTFS_OUT" "$VERIFY/rootfs"
verify_rootfs_marker=$(sudo -n cat "$VERIFY/rootfs/System/Runtime/rootfs-image-mode" 2>/dev/null || true)
verify_rootfs_init=$(sudo -n grep -n -E 'devtmpfs|tty0|mdev|busybox init|0066-after-switch-root' "$VERIFY/rootfs/sbin/init" 2>/dev/null || true)
verify_rootfs_service=$(sudo -n ls -l "$VERIFY/rootfs/etc/runlevels/default/mixtar-image-root-report" 2>/dev/null || true)
sudo -n umount "$VERIFY/rootfs"

sudo -n mkdir -p "$ESP_MOUNT"
if ! awk -v d="$ESP_DEV" '$1 == d { found=1 } END { exit found ? 0 : 1 }' /proc/mounts; then
	sudo -n mount -t vfat "$ESP_DEV" "$ESP_MOUNT"
	mounted_by_script=true
else
	ESP_MOUNT=$(awk -v d="$ESP_DEV" '$1 == d { print $2; exit }' /proc/mounts)
fi

need_file "$ESP_MOUNT/EFI/mixtarrvs-rt/initrd-mixtar-candidate-0065.img"
need_file "$ESP_MOUNT/EFI/mixtarrvs-rt/vmlinuz.efi"

root_uuid=$(blkid -s UUID -o value /dev/nvme0n1p3 2>/dev/null || true)
if [ -z "$root_uuid" ]; then
	echo "root UUID not found" >&2
	exit 1
fi

before_order=$(sudo -n efibootmgr | awk -F': ' '/^BootOrder:/ { print $2; exit }')
before_next=$(sudo -n efibootmgr | awk -F': ' '/^BootNext:/ { print $2; exit }')

cmdline="initrd=$INITRD rdinit=/mixtar-init root=UUID=$root_uuid rootfstype=ext4 rootflags=ro modules=nvme,ext4,jbd2,mbcache rootwait ro quiet loglevel=3 threadirqs mixtar.profile=rt-7.1.2-mixtar-rt mixtar.rootfs=$ROOTFS_ARG mixtar.overlay=readonly mixtar.fallback=previous mixtar.handoff=boot"

sudo -n efibootmgr -c -d /dev/nvme0n1 -p 1 -L "$LABEL" -l "$LOADER" -u "$cmdline" >/tmp/mixtar-0066-efibootmgr-create.log 2>&1 || {
	cat /tmp/mixtar-0066-efibootmgr-create.log
	exit 1
}

created=$(sudo -n efibootmgr | awk -v label="$LABEL" 'index($0,label) { gsub(/^Boot/, "", $1); gsub(/\*/, "", $1); print $1 }' | tail -1)
if [ -z "$created" ]; then
	echo "created boot entry not found" >&2
	exit 1
fi

sudo -n efibootmgr -o "$before_order" >/tmp/mixtar-0066-efibootmgr-order.log 2>&1 || {
	cat /tmp/mixtar-0066-efibootmgr-order.log
	exit 1
}

after_order=$(sudo -n efibootmgr | awk -F': ' '/^BootOrder:/ { print $2; exit }')
after_next=$(sudo -n efibootmgr | awk -F': ' '/^BootNext:/ { print $2; exit }')

{
	echo "stage=0066-diagnostic-devtmpfs-image-root"
	echo "status=verified"
	echo "rootfs_source=$ROOTFS_SRC"
	echo "rootfs_source_sha256=$rootfs_src_sha"
	echo "rootfs_target=$ROOTFS_OUT"
	echo "rootfs_target_sha256=$rootfs_out_sha"
	echo "rootfs_target_size_bytes=$rootfs_out_size"
	echo "initrd_source=$INITRD_SRC"
	echo "initrd_source_sha256=$initrd_src_sha"
	echo "rootfs_arg=$ROOTFS_ARG"
	echo "overlay_mode=readonly"
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
	echo "verify_rootfs_service_begin"
	printf '%s\n' "$verify_rootfs_service"
	echo "verify_rootfs_service_end"
	echo "next_required_stage=0067-set-bootnext-one-shot-devtmpfs-image-root-test"
} | sudo -n tee "$REPORT" >/dev/null

cat "$REPORT"
printf 'EFIBOOT_FILTERED=\n'
sudo -n efibootmgr | awk -v boot="Boot$created" '/^BootCurrent:|^BootNext:|^BootOrder:/ { print } index($0, boot) == 1 { print } /^Boot0006\*/ { print }'
