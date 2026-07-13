#!/bin/sh
set -eu

ROOTFS_SRC=/System/Generations/0020-rootfs-image-diagnostic-devtmpfs/rootfs.squashfs
ROOTFS_GEN=/System/Generations/0021-rootfs-image-pid1-log-autoreboot
ROOTFS_OUT=$ROOTFS_GEN/rootfs.squashfs

INITRD_SRC=/System/Initramfs/Candidates/0067-pid1-initramfs-persistent-logging-candidate-no-install/initramfs.img
INITRD_CAND=/System/Initramfs/Candidates/0068-pid1-log-autoreboot-candidate-no-install
INITRD_OUT=$INITRD_CAND/initramfs.img

REPORT=/System/Base/Closure/0068-pid1-log-autoreboot.report
ROOT_WORK=/tmp/mixtar-rootfs-0021.$$
INIT_WORK=/tmp/mixtar-initramfs-0068.$$
VERIFY=/tmp/mixtar-0068-verify.$$

ESP_DEV=/dev/nvme0n1p1
ESP_MOUNT=/tmp/mixtar-esp-0068
ESP_INITRD_NAME=initrd-mixtar-candidate-0068.img

LABEL="MixtarRVS RT Candidate 0068 pid1 log autoreboot"
LOADER="\\EFI\\mixtarrvs-rt\\vmlinuz.efi"
INITRD="\\EFI\\mixtarrvs-rt\\initrd-mixtar-candidate-0068.img"
ROOTFS_ARG=/System/Generations/0021-rootfs-image-pid1-log-autoreboot/rootfs.squashfs

mounted_by_script=false

cleanup() {
	if [ "$mounted_by_script" = true ]; then
		sudo -n umount "$ESP_MOUNT" >/dev/null 2>&1 || true
	fi
	sudo -n rmdir "$ESP_MOUNT" >/dev/null 2>&1 || true
	sudo -n umount "$VERIFY/rootfs" >/dev/null 2>&1 || true
	sudo -n rm -rf "$ROOT_WORK" "$INIT_WORK" "$VERIFY"
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
need_absent "$INITRD_CAND"

sudo -n mkdir -p /System/Base/Closure "$ROOTFS_GEN" "$INITRD_CAND"
sudo -n mkdir -p "$ROOT_WORK/root" "$INIT_WORK" "$VERIFY/rootfs" "$VERIFY/initrd"

rootfs_src_sha=$(sha256sum "$ROOTFS_SRC" | awk '{ print $1 }')
initrd_src_sha=$(sha256sum "$INITRD_SRC" | awk '{ print $1 }')

sudo -n unsquashfs -d "$ROOT_WORK/root" "$ROOTFS_SRC" >/tmp/mixtar-0068-unsquashfs.log 2>&1 || {
	cat /tmp/mixtar-0068-unsquashfs.log
	exit 1
}

sudo -n mkdir -p "$ROOT_WORK/root/System/Runtime/initramfs/base"
sudo -n mkdir -p "$ROOT_WORK/root/System/Runtime/diagnostics"

sudo -n rm -f "$ROOT_WORK/root/sbin/init"
sudo -n tee "$ROOT_WORK/root/sbin/init" >/dev/null <<'EOS'
#!/bin/sh

BASE_LOG_DIR=/System/Runtime/initramfs/base/System/Base/Closure
LOG=$BASE_LOG_DIR/0068-after-switch-root.log

append_log() {
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
		echo "stage=0068-after-switch-root"
		echo "pid=$$"
		echo "cmdline=$(cat /proc/cmdline 2>/dev/null || true)"
		echo "root_mount=$(awk '$2 == "/" { print; exit }' /proc/mounts 2>/dev/null || true)"
		echo "base_mount=$(awk '$2 == "/System/Runtime/initramfs/base" { print; exit }' /proc/mounts 2>/dev/null || true)"
		echo "dev_mount=$(awk '$2 == "/dev" { print; exit }' /proc/mounts 2>/dev/null || true)"
		echo "proc_mount=$(awk '$2 == "/proc" { print; exit }' /proc/mounts 2>/dev/null || true)"
		echo "sys_mount=$(awk '$2 == "/sys" { print; exit }' /proc/mounts 2>/dev/null || true)"
		echo "dev_nodes_begin"
		ls -l /dev /dev/console /dev/tty /dev/tty0 /dev/tty1 /dev/null /dev/zero 2>&1 || true
		echo "dev_nodes_end"
		echo "init_files_begin"
		ls -l /sbin/init /sbin/openrc-init /bin/busybox 2>&1 || true
		echo "init_files_end"
		echo "rootfs_marker_begin"
		cat /System/Runtime/rootfs-image-mode 2>/dev/null || true
		echo "rootfs_marker_end"
		echo "mounts_begin"
		cat /proc/mounts 2>/dev/null || true
		echo "mounts_end"
	} >>"$LOG" 2>&1 || true
}

mkdir -p "$BASE_LOG_DIR" 2>/dev/null || true
append_log "0068 diagnostic pid1 started"

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
ensure_node /dev/null 666 1 3
ensure_node /dev/zero 666 1 5
ensure_node /dev/random 666 1 8
ensure_node /dev/urandom 666 1 9

if command -v mdev >/dev/null 2>&1; then
	mdev -s >>"$LOG" 2>&1 || true
fi

write_snapshot
append_log "0068 diagnostic pid1 syncing and rebooting to firmware default"
sync
sleep 8

if [ -w /proc/sysrq-trigger ]; then
	echo b > /proc/sysrq-trigger
fi

/bin/busybox reboot -f >>"$LOG" 2>&1 || true
reboot -f >>"$LOG" 2>&1 || true

while :; do
	sleep 60
done
EOS

sudo -n chmod 755 "$ROOT_WORK/root/sbin/init"

sudo -n tee "$ROOT_WORK/root/System/Runtime/rootfs-image-mode" >/dev/null <<'EOS'
rootfs_mode=image-readonly-pid1-log-autoreboot
source_generation=0020-rootfs-image-diagnostic-devtmpfs
fstab_block_root_disabled=true
openrc_root_service=not-started
base_preserve_mountpoint=/System/Runtime/initramfs/base
diagnostic_init=/sbin/init
diagnostic_pid1_autoreboot=true
EOS

sudo -n mksquashfs "$ROOT_WORK/root" "$ROOTFS_OUT" -noappend -no-progress >/tmp/mixtar-0068-mksquashfs.log 2>&1 || {
	cat /tmp/mixtar-0068-mksquashfs.log
	exit 1
}

rootfs_out_sha=$(sha256sum "$ROOTFS_OUT" | awk '{ print $1 }')
rootfs_out_size=$(wc -c <"$ROOTFS_OUT" | tr -d ' ')

sudo -n mount -o loop,ro -t squashfs "$ROOTFS_OUT" "$VERIFY/rootfs"
verify_rootfs_marker=$(sudo -n cat "$VERIFY/rootfs/System/Runtime/rootfs-image-mode" 2>/dev/null || true)
verify_rootfs_init=$(sudo -n grep -n -E '0068-after-switch-root|sysrq-trigger|reboot -f|tty0|diagnostic pid1' "$VERIFY/rootfs/sbin/init" 2>/dev/null || true)
sudo -n umount "$VERIFY/rootfs"

printf '%s\n' "$verify_rootfs_marker" | grep -q 'diagnostic_pid1_autoreboot=true' || {
	echo "rootfs 0021 autoreboot marker missing" >&2
	exit 1
}
printf '%s\n' "$verify_rootfs_init" | grep -q '0068-after-switch-root' || {
	echo "rootfs 0021 diagnostic init log marker missing" >&2
	exit 1
}

sudo -n sh -c "cd '$INIT_WORK' && gzip -dc '$INITRD_SRC' | cpio -idmu" >/tmp/mixtar-0068-cpio-in.log 2>&1 || {
	cat /tmp/mixtar-0068-cpio-in.log
	exit 1
}

HANDOFF=$INIT_WORK/usr/bin/mixtar-initramfs-handoff
need_file "$HANDOFF"
sudo -n cp "$HANDOFF" "$HANDOFF.before-0068"

sudo -n awk '
	/log_msg "mounting base root \$root_device"/ && inserted == 0 {
		print
		print "\tbase_diag=/MixtarBase/System/Base/Closure"
		print "\tmkdir -p \"$base_diag\" 2>/dev/null || true"
		print "\tmount -o remount,rw /MixtarBase 2>/dev/null || true"
		print "\tmkdir -p \"$base_diag\" 2>/dev/null || true"
		print "\t{"
		print "\t\techo \"stage=0068-after-base-root-mount\""
		print "\t\techo \"pid=$$\""
		print "\t\techo \"cmdline=$(cat /proc/cmdline 2>/dev/null || true)\""
		print "\t\techo \"base_mount=$(awk '\''$2 == \"/MixtarBase\" { print; exit }'\'' /proc/mounts 2>/dev/null || true)\""
		print "\t\techo \"base_writable_probe_begin\""
		print "\t\tprobe=\"$base_diag/0068-rw-probe.$$\""
		print "\t\tif printf probe > \"$probe\" 2>/dev/null; then echo writable=true; rm -f \"$probe\"; else echo writable=false; fi"
		print "\t\techo \"base_writable_probe_end\""
		print "\t} >> \"$base_diag/0068-initramfs-handoff.log\" 2>&1 || true"
		print "\tsync"
		inserted = 1
		next
	}
	{ print }
' "$HANDOFF" | sudo -n tee "$HANDOFF.new" >/dev/null

sudo -n mv "$HANDOFF.new" "$HANDOFF"
sudo -n chmod 755 "$HANDOFF"

verify_patch=$(sudo -n grep -n -E '0068-after-base-root-mount|0068-initramfs-handoff|PRIMARY_INIT=/sbin/init|0067-before-switch-root|switch_root' "$HANDOFF" || true)
printf '%s\n' "$verify_patch" | grep -q '0068-initramfs-handoff' || {
	echo "0068 handoff rw logging patch verification failed" >&2
	exit 1
}
printf '%s\n' "$verify_patch" | grep -q 'PRIMARY_INIT=/sbin/init' || {
	echo "0068 primary init verification failed" >&2
	exit 1
}

sudo -n sh -c "cd '$INIT_WORK' && find . | cpio -o -H newc | gzip -9 > '$INITRD_OUT'" >/tmp/mixtar-0068-cpio-out.log 2>&1 || {
	cat /tmp/mixtar-0068-cpio-out.log
	exit 1
}

initrd_out_sha=$(sha256sum "$INITRD_OUT" | awk '{ print $1 }')
initrd_out_size=$(wc -c <"$INITRD_OUT" | tr -d ' ')

sudo -n sh -c "cd '$VERIFY/initrd' && gzip -dc '$INITRD_OUT' | cpio -idmu" >/tmp/mixtar-0068-verify-initrd.log 2>&1 || {
	cat /tmp/mixtar-0068-verify-initrd.log
	exit 1
}

verify_handoff=$(sudo -n grep -n -E '0068-after-base-root-mount|0068-initramfs-handoff|PRIMARY_INIT=/sbin/init|0067-before-switch-root|busybox switch_root' "$VERIFY/initrd/usr/bin/mixtar-initramfs-handoff" || true)
printf '%s\n' "$verify_handoff" | grep -q '0068-initramfs-handoff' || {
	echo "verified initrd 0068 rw logging patch missing" >&2
	exit 1
}

sudo -n mkdir -p "$ESP_MOUNT"
if ! awk -v d="$ESP_DEV" '$1 == d { found=1 } END { exit found ? 0 : 1 }' /proc/mounts; then
	sudo -n mount -t vfat "$ESP_DEV" "$ESP_MOUNT"
	mounted_by_script=true
else
	ESP_MOUNT=$(awk -v d="$ESP_DEV" '$1 == d { print $2; exit }' /proc/mounts)
fi

sudo -n mkdir -p "$ESP_MOUNT/EFI/mixtarrvs-rt"
sudo -n cp "$INITRD_OUT" "$ESP_MOUNT/EFI/mixtarrvs-rt/$ESP_INITRD_NAME"
esp_sha=$(sha256sum "$ESP_MOUNT/EFI/mixtarrvs-rt/$ESP_INITRD_NAME" | awk '{ print $1 }')
if [ "$esp_sha" != "$initrd_out_sha" ]; then
	echo "ESP copy hash mismatch" >&2
	exit 1
fi

need_file "$ESP_MOUNT/EFI/mixtarrvs-rt/vmlinuz.efi"

root_uuid=$(blkid -s UUID -o value /dev/nvme0n1p3 2>/dev/null || true)
if [ -z "$root_uuid" ]; then
	echo "root UUID not found" >&2
	exit 1
fi

before_order=$(sudo -n efibootmgr | awk -F': ' '/^BootOrder:/ { print $2; exit }')
before_next=$(sudo -n efibootmgr | awk -F': ' '/^BootNext:/ { print $2; exit }')

cmdline="initrd=$INITRD rdinit=/mixtar-init root=UUID=$root_uuid rootfstype=ext4 rootflags=ro modules=nvme,ext4,jbd2,mbcache rootwait ro quiet loglevel=3 threadirqs mixtar.profile=rt-7.1.2-mixtar-rt mixtar.rootfs=$ROOTFS_ARG mixtar.overlay=readonly mixtar.fallback=previous mixtar.handoff=boot"

sudo -n efibootmgr -c -d /dev/nvme0n1 -p 1 -L "$LABEL" -l "$LOADER" -u "$cmdline" >/tmp/mixtar-0068-efibootmgr-create.log 2>&1 || {
	cat /tmp/mixtar-0068-efibootmgr-create.log
	exit 1
}

created=$(sudo -n efibootmgr | awk -v label="$LABEL" 'index($0,label) { gsub(/^Boot/, "", $1); gsub(/\*/, "", $1); print $1 }' | tail -1)
if [ -z "$created" ]; then
	echo "created boot entry not found" >&2
	exit 1
fi

sudo -n efibootmgr -o "$before_order" >/tmp/mixtar-0068-efibootmgr-order.log 2>&1 || {
	cat /tmp/mixtar-0068-efibootmgr-order.log
	exit 1
}

after_order=$(sudo -n efibootmgr | awk -F': ' '/^BootOrder:/ { print $2; exit }')
after_next=$(sudo -n efibootmgr | awk -F': ' '/^BootNext:/ { print $2; exit }')

{
	echo "stage=0068-pid1-log-autoreboot"
	echo "status=verified"
	echo "rootfs_source=$ROOTFS_SRC"
	echo "rootfs_source_sha256=$rootfs_src_sha"
	echo "rootfs_target=$ROOTFS_OUT"
	echo "rootfs_target_sha256=$rootfs_out_sha"
	echo "rootfs_target_size_bytes=$rootfs_out_size"
	echo "initrd_source=$INITRD_SRC"
	echo "initrd_source_sha256=$initrd_src_sha"
	echo "initrd_target=$INITRD_OUT"
	echo "initrd_target_sha256=$initrd_out_sha"
	echo "initrd_target_size_bytes=$initrd_out_size"
	echo "esp_sha256=$esp_sha"
	echo "copy_hash_match=true"
	echo "rootfs_arg=$ROOTFS_ARG"
	echo "overlay_mode=readonly"
	echo "primary_init=/sbin/init"
	echo "fallback_init=/sbin/openrc-init"
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
	echo "verify_handoff_begin"
	printf '%s\n' "$verify_handoff"
	echo "verify_handoff_end"
	echo "next_required_stage=0069-set-bootnext-one-shot-pid1-log-autoreboot-test"
} | sudo -n tee "$REPORT" >/dev/null

cat "$REPORT"
printf 'EFIBOOT_FILTERED=\n'
sudo -n efibootmgr | awk -v boot="Boot$created" '/^BootCurrent:|^BootNext:|^BootOrder:/ { print } index($0, boot) == 1 { print } /^Boot0006\*/ { print }'
