#!/bin/sh
set -eu

ROOTFS_SRC=/System/Generations/0018-rootfs-image-readonly-base-preserve/rootfs.squashfs
ROOTFS_GEN=/System/Generations/0019-rootfs-image-diagnostic-init
ROOTFS_OUT=$ROOTFS_GEN/rootfs.squashfs

INITRD_SRC=/System/Initramfs/Candidates/0064-pid1-handoff-readonly-candidate-no-install/initramfs.img
INITRD_CAND=/System/Initramfs/Candidates/0065-diagnostic-image-root-candidate-no-install
INITRD_OUT=$INITRD_CAND/initramfs.img

REPORT=/System/Base/Closure/0065-diagnostic-image-root.report
ROOT_WORK=/tmp/mixtar-rootfs-0019.$$
INIT_WORK=/tmp/mixtar-initramfs-0065.$$
VERIFY=/tmp/mixtar-0065-verify.$$

ESP_DEV=/dev/nvme0n1p1
ESP_MOUNT=/tmp/mixtar-esp-0065
ESP_INITRD_NAME=initrd-mixtar-candidate-0065.img

LABEL="MixtarRVS RT Candidate 0065 diagnostic image-root"
LOADER="\\EFI\\mixtarrvs-rt\\vmlinuz.efi"
INITRD="\\EFI\\mixtarrvs-rt\\initrd-mixtar-candidate-0065.img"
ROOTFS_ARG=/System/Generations/0019-rootfs-image-diagnostic-init/rootfs.squashfs

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

sudo -n unsquashfs -d "$ROOT_WORK/root" "$ROOTFS_SRC" >/tmp/mixtar-0065-unsquashfs.log 2>&1 || {
	cat /tmp/mixtar-0065-unsquashfs.log
	exit 1
}

sudo -n mkdir -p "$ROOT_WORK/root/System/Runtime/initramfs/base"
sudo -n mkdir -p "$ROOT_WORK/root/System/Runtime/diagnostics"

if [ -e "$ROOT_WORK/root/sbin/init" ]; then
	sudo -n rm -f "$ROOT_WORK/root/sbin/init"
fi

sudo -n tee "$ROOT_WORK/root/sbin/init" >/dev/null <<'EOS'
#!/bin/sh

LOG=/System/Runtime/initramfs/base/System/Base/Closure/0065-after-switch-root.log

write_log() {
	mkdir -p /System/Runtime/initramfs/base/System/Base/Closure 2>/dev/null || true
	{
		echo "stage=0065-after-switch-root"
		echo "pid=$$"
		echo "cmdline=$(cat /proc/cmdline 2>/dev/null || true)"
		echo "root_mount=$(awk '$2 == "/" { print; exit }' /proc/mounts 2>/dev/null || true)"
		echo "rootfs_marker_begin"
		cat /System/Runtime/rootfs-image-mode 2>/dev/null || true
		echo "rootfs_marker_end"
		echo "mounts_begin"
		cat /proc/mounts 2>/dev/null || true
		echo "mounts_end"
		echo "filesystems_begin"
		cat /proc/filesystems 2>/dev/null || true
		echo "filesystems_end"
	} >>"$LOG" 2>&1 || true
}

write_log
exec /bin/busybox init
EOS

sudo -n chmod 755 "$ROOT_WORK/root/sbin/init"

sudo -n tee "$ROOT_WORK/root/etc/init.d/mixtar-image-root-report" >/dev/null <<'EOS'
#!/sbin/openrc-run

description="Write Mixtar image-root diagnostics to preserved base root"

depend()
{
	after root
	before dhcpcd iwd sshd
}

start()
{
	local log=/System/Runtime/initramfs/base/System/Base/Closure/0065-openrc-report.log
	ebegin "Writing Mixtar image-root diagnostics"
	mkdir -p /System/Runtime/initramfs/base/System/Base/Closure 2>/dev/null || true
	{
		echo "stage=0065-openrc-report"
		echo "service_pid=$$"
		echo "root_mount=$(awk '$2 == "/" { print; exit }' /proc/mounts 2>/dev/null || true)"
		echo "cmdline=$(cat /proc/cmdline 2>/dev/null || true)"
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
rootfs_mode=image-readonly-diagnostic
source_generation=0018-rootfs-image-readonly-base-preserve
fstab_block_root_disabled=true
openrc_root_service=noop
base_preserve_mountpoint=/System/Runtime/initramfs/base
diagnostic_init=/sbin/init
diagnostic_openrc_service=mixtar-image-root-report
EOS

sudo -n mksquashfs "$ROOT_WORK/root" "$ROOTFS_OUT" -noappend -no-progress >/tmp/mixtar-0065-mksquashfs.log 2>&1 || {
	cat /tmp/mixtar-0065-mksquashfs.log
	exit 1
}

rootfs_out_sha=$(sha256sum "$ROOTFS_OUT" | awk '{ print $1 }')
rootfs_out_size=$(wc -c <"$ROOTFS_OUT" | tr -d ' ')

sudo -n mount -o loop,ro -t squashfs "$ROOTFS_OUT" "$VERIFY/rootfs"
verify_rootfs_marker=$(sudo -n cat "$VERIFY/rootfs/System/Runtime/rootfs-image-mode" 2>/dev/null || true)
verify_rootfs_init=$(sudo -n sed -n '1,80p' "$VERIFY/rootfs/sbin/init" 2>/dev/null || true)
verify_rootfs_service=$(sudo -n ls -l "$VERIFY/rootfs/etc/runlevels/default/mixtar-image-root-report" 2>/dev/null || true)
sudo -n umount "$VERIFY/rootfs"

sudo -n sh -c "cd '$INIT_WORK' && gzip -dc '$INITRD_SRC' | cpio -idmu" >/tmp/mixtar-0065-cpio-in.log 2>&1 || {
	cat /tmp/mixtar-0065-cpio-in.log
	exit 1
}

HANDOFF=$INIT_WORK/usr/bin/mixtar-initramfs-handoff
need_file "$HANDOFF"
sudo -n cp "$HANDOFF" "$HANDOFF.before-0065"

sudo -n awk '
	/printf '\''mixtar-handoff: %s\\n'\'' "\$msg"/ && inserted == 0 {
		print
		print "\tfor logdir in /MixtarBase/System/Base/Closure /MixtarImage/System/Runtime/initramfs/base/System/Base/Closure; do"
		print "\t\tif [ -d \"$logdir\" ]; then"
		print "\t\t\tprintf '\''mixtar-handoff: %s\\n'\'' \"$msg\" >> \"$logdir/0065-initramfs-handoff.log\" 2>/dev/null || true"
		print "\t\tfi"
		print "\tdone"
		inserted = 1
		next
	}
	{ print }
' "$HANDOFF" | sudo -n tee "$HANDOFF.new" >/dev/null

sudo -n mv "$HANDOFF.new" "$HANDOFF"
sudo -n chmod 755 "$HANDOFF"

sudo -n sh -c "cd '$INIT_WORK' && find . | cpio -o -H newc | gzip -9 > '$INITRD_OUT'" >/tmp/mixtar-0065-cpio-out.log 2>&1 || {
	cat /tmp/mixtar-0065-cpio-out.log
	exit 1
}

initrd_out_sha=$(sha256sum "$INITRD_OUT" | awk '{ print $1 }')
initrd_out_size=$(wc -c <"$INITRD_OUT" | tr -d ' ')

sudo -n sh -c "cd '$VERIFY/initrd' && gzip -dc '$INITRD_OUT' | cpio -idmu" >/tmp/mixtar-0065-verify-initrd.log 2>&1 || {
	cat /tmp/mixtar-0065-verify-initrd.log
	exit 1
}

verify_handoff=$(sudo -n grep -n -E '0065-initramfs-handoff|busybox switch_root|fallback to original init from handoff|moved base root into readonly target' "$VERIFY/initrd/usr/bin/mixtar-initramfs-handoff" || true)
printf '%s\n' "$verify_handoff" | grep -q '0065-initramfs-handoff' || {
	echo "handoff persistent log verification failed" >&2
	exit 1
}
printf '%s\n' "$verify_handoff" | grep -q '/usr/bin/busybox switch_root' || {
	echo "busybox switch_root verification failed" >&2
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

sudo -n efibootmgr -c -d /dev/nvme0n1 -p 1 -L "$LABEL" -l "$LOADER" -u "$cmdline" >/tmp/mixtar-0065-efibootmgr-create.log 2>&1 || {
	cat /tmp/mixtar-0065-efibootmgr-create.log
	exit 1
}

created=$(sudo -n efibootmgr | awk -v label="$LABEL" 'index($0,label) { gsub(/^Boot/, "", $1); gsub(/\*/, "", $1); print $1 }' | tail -1)
if [ -z "$created" ]; then
	echo "created boot entry not found" >&2
	exit 1
fi

sudo -n efibootmgr -o "$before_order" >/tmp/mixtar-0065-efibootmgr-order.log 2>&1 || {
	cat /tmp/mixtar-0065-efibootmgr-order.log
	exit 1
}

after_order=$(sudo -n efibootmgr | awk -F': ' '/^BootOrder:/ { print $2; exit }')
after_next=$(sudo -n efibootmgr | awk -F': ' '/^BootNext:/ { print $2; exit }')

{
	echo "stage=0065-diagnostic-image-root"
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
	echo "verify_handoff_begin"
	printf '%s\n' "$verify_handoff"
	echo "verify_handoff_end"
	echo "next_required_stage=0066-set-bootnext-one-shot-diagnostic-image-root-test"
} | sudo -n tee "$REPORT" >/dev/null

cat "$REPORT"
printf 'EFIBOOT_FILTERED=\n'
sudo -n efibootmgr | awk -v boot="Boot$created" '/^BootCurrent:|^BootNext:|^BootOrder:/ { print } index($0, boot) == 1 { print } /^Boot0006\*/ { print }'
