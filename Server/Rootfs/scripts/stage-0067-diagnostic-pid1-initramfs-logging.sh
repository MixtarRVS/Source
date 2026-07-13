#!/bin/sh
set -eu

ROOTFS_SRC=/System/Generations/0020-rootfs-image-diagnostic-devtmpfs/rootfs.squashfs

INITRD_SRC=/System/Initramfs/Candidates/0065-diagnostic-image-root-candidate-no-install/initramfs.img
INITRD_CAND=/System/Initramfs/Candidates/0067-pid1-initramfs-persistent-logging-candidate-no-install
INITRD_OUT=$INITRD_CAND/initramfs.img

REPORT=/System/Base/Closure/0067-diagnostic-pid1-initramfs-logging.report
INIT_WORK=/tmp/mixtar-initramfs-0067.$$
VERIFY=/tmp/mixtar-0067-verify.$$

ESP_DEV=/dev/nvme0n1p1
ESP_MOUNT=/tmp/mixtar-esp-0067
ESP_INITRD_NAME=initrd-mixtar-candidate-0067.img

LABEL="MixtarRVS RT Candidate 0067 pid1 initramfs logging"
LOADER="\\EFI\\mixtarrvs-rt\\vmlinuz.efi"
INITRD="\\EFI\\mixtarrvs-rt\\initrd-mixtar-candidate-0067.img"
ROOTFS_ARG=/System/Generations/0020-rootfs-image-diagnostic-devtmpfs/rootfs.squashfs

mounted_by_script=false

cleanup() {
	if [ "$mounted_by_script" = true ]; then
		sudo -n umount "$ESP_MOUNT" >/dev/null 2>&1 || true
	fi
	sudo -n rmdir "$ESP_MOUNT" >/dev/null 2>&1 || true
	sudo -n umount "$VERIFY/rootfs" >/dev/null 2>&1 || true
	sudo -n rm -rf "$INIT_WORK" "$VERIFY"
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
need_absent "$INITRD_CAND"

sudo -n mkdir -p /System/Base/Closure "$INITRD_CAND"
sudo -n mkdir -p "$INIT_WORK" "$VERIFY/rootfs" "$VERIFY/initrd"

rootfs_src_sha=$(sha256sum "$ROOTFS_SRC" | awk '{ print $1 }')
initrd_src_sha=$(sha256sum "$INITRD_SRC" | awk '{ print $1 }')

sudo -n mount -o loop,ro -t squashfs "$ROOTFS_SRC" "$VERIFY/rootfs"
verify_rootfs_marker=$(sudo -n cat "$VERIFY/rootfs/System/Runtime/rootfs-image-mode" 2>/dev/null || true)
verify_rootfs_init=$(sudo -n grep -n -E 'devtmpfs|tty0|mdev|busybox init|0066-after-switch-root' "$VERIFY/rootfs/sbin/init" 2>/dev/null || true)
sudo -n umount "$VERIFY/rootfs"

printf '%s\n' "$verify_rootfs_marker" | grep -q 'diagnostic_init_devtmpfs=true' || {
	echo "rootfs 0020 diagnostic init marker missing" >&2
	exit 1
}
printf '%s\n' "$verify_rootfs_init" | grep -q 'tty0' || {
	echo "rootfs 0020 diagnostic init tty0 bootstrap missing" >&2
	exit 1
}

sudo -n sh -c "cd '$INIT_WORK' && gzip -dc '$INITRD_SRC' | cpio -idmu" >/tmp/mixtar-0067-cpio-in.log 2>&1 || {
	cat /tmp/mixtar-0067-cpio-in.log
	exit 1
}

HANDOFF=$INIT_WORK/usr/bin/mixtar-initramfs-handoff
need_file "$HANDOFF"
sudo -n cp "$HANDOFF" "$HANDOFF.before-0067"

sudo -n sed \
	-e 's|^PRIMARY_INIT=/sbin/openrc-init$|PRIMARY_INIT=/sbin/init|' \
	-e 's|^FALLBACK_INIT=/sbin/init$|FALLBACK_INIT=/sbin/openrc-init|' \
	"$HANDOFF" | sudo -n tee "$HANDOFF.pid1" >/dev/null

sudo -n awk '
	/printf '\''mixtar-handoff: %s\\n'\'' "\$msg"/ && log_inserted == 0 {
		print
		print "\tfor logdir in /MixtarBase/System/Base/Closure /MixtarImage/System/Runtime/initramfs/base/System/Base/Closure; do"
		print "\t\tif [ -d \"$logdir\" ]; then"
		print "\t\t\tprintf '\''mixtar-handoff: %s\\n'\'' \"$msg\" >> \"$logdir/0067-initramfs-handoff.log\" 2>/dev/null || true"
		print "\t\tfi"
		print "\tdone"
		log_inserted = 1
		next
	}
	/log_msg "switch_root target=\$target_root init=\$init_path"/ && snapshot_inserted == 0 {
		print
		print "\tfor logdir in /MixtarBase/System/Base/Closure /MixtarImage/System/Runtime/initramfs/base/System/Base/Closure; do"
		print "\t\tif [ -d \"$logdir\" ]; then"
		print "\t\t\t{"
		print "\t\t\t\techo \"stage=0067-before-switch-root\""
		print "\t\t\t\techo \"pid=$$\""
		print "\t\t\t\techo \"target_root=$target_root\""
		print "\t\t\t\techo \"init_path=$init_path\""
		print "\t\t\t\techo \"cmdline=$(cat /proc/cmdline 2>/dev/null || true)\""
		print "\t\t\t\techo \"runtime_mounts_begin\""
		print "\t\t\t\tcat /proc/mounts 2>/dev/null || true"
		print "\t\t\t\techo \"runtime_mounts_end\""
		print "\t\t\t\techo \"target_dev_nodes_begin\""
		print "\t\t\t\tls -l \"$target_root/dev\" \"$target_root/dev/console\" \"$target_root/dev/tty\" \"$target_root/dev/tty0\" \"$target_root/dev/tty1\" 2>&1 || true"
		print "\t\t\t\techo \"target_dev_nodes_end\""
		print "\t\t\t\techo \"target_init_begin\""
		print "\t\t\t\tls -l \"$target_root/sbin/init\" \"$target_root/sbin/openrc-init\" 2>&1 || true"
		print "\t\t\t\techo \"target_init_end\""
		print "\t\t\t} >> \"$logdir/0067-before-switch-root.log\" 2>&1 || true"
		print "\t\tfi"
		print "\tdone"
		print "\tsync"
		snapshot_inserted = 1
		next
	}
	{ print }
' "$HANDOFF.pid1" | sudo -n tee "$HANDOFF.new" >/dev/null

sudo -n mv "$HANDOFF.new" "$HANDOFF"
sudo -n chmod 755 "$HANDOFF"

verify_patch=$(sudo -n grep -n -E 'PRIMARY_INIT=/sbin/init|FALLBACK_INIT=/sbin/openrc-init|0067-initramfs-handoff|0067-before-switch-root|switch_root' "$HANDOFF" || true)
printf '%s\n' "$verify_patch" | grep -q 'PRIMARY_INIT=/sbin/init' || {
	echo "PRIMARY_INIT patch verification failed" >&2
	exit 1
}
printf '%s\n' "$verify_patch" | grep -q '0067-before-switch-root' || {
	echo "before-switch-root logging patch verification failed" >&2
	exit 1
}

sudo -n sh -c "cd '$INIT_WORK' && find . | cpio -o -H newc | gzip -9 > '$INITRD_OUT'" >/tmp/mixtar-0067-cpio-out.log 2>&1 || {
	cat /tmp/mixtar-0067-cpio-out.log
	exit 1
}

initrd_out_sha=$(sha256sum "$INITRD_OUT" | awk '{ print $1 }')
initrd_out_size=$(wc -c <"$INITRD_OUT" | tr -d ' ')

sudo -n sh -c "cd '$VERIFY/initrd' && gzip -dc '$INITRD_OUT' | cpio -idmu" >/tmp/mixtar-0067-verify-initrd.log 2>&1 || {
	cat /tmp/mixtar-0067-verify-initrd.log
	exit 1
}

verify_handoff=$(sudo -n grep -n -E 'PRIMARY_INIT=/sbin/init|FALLBACK_INIT=/sbin/openrc-init|0067-initramfs-handoff|0067-before-switch-root|busybox switch_root' "$VERIFY/initrd/usr/bin/mixtar-initramfs-handoff" || true)
printf '%s\n' "$verify_handoff" | grep -q 'PRIMARY_INIT=/sbin/init' || {
	echo "verified initrd PRIMARY_INIT patch missing" >&2
	exit 1
}
printf '%s\n' "$verify_handoff" | grep -q '0067-before-switch-root' || {
	echo "verified initrd persistent snapshot patch missing" >&2
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

sudo -n efibootmgr -c -d /dev/nvme0n1 -p 1 -L "$LABEL" -l "$LOADER" -u "$cmdline" >/tmp/mixtar-0067-efibootmgr-create.log 2>&1 || {
	cat /tmp/mixtar-0067-efibootmgr-create.log
	exit 1
}

created=$(sudo -n efibootmgr | awk -v label="$LABEL" 'index($0,label) { gsub(/^Boot/, "", $1); gsub(/\*/, "", $1); print $1 }' | tail -1)
if [ -z "$created" ]; then
	echo "created boot entry not found" >&2
	exit 1
fi

sudo -n efibootmgr -o "$before_order" >/tmp/mixtar-0067-efibootmgr-order.log 2>&1 || {
	cat /tmp/mixtar-0067-efibootmgr-order.log
	exit 1
}

after_order=$(sudo -n efibootmgr | awk -F': ' '/^BootOrder:/ { print $2; exit }')
after_next=$(sudo -n efibootmgr | awk -F': ' '/^BootNext:/ { print $2; exit }')

{
	echo "stage=0067-diagnostic-pid1-initramfs-logging"
	echo "status=verified"
	echo "rootfs_source=$ROOTFS_SRC"
	echo "rootfs_source_sha256=$rootfs_src_sha"
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
	echo "next_required_stage=0068-set-bootnext-one-shot-pid1-logging-test"
} | sudo -n tee "$REPORT" >/dev/null

cat "$REPORT"
printf 'EFIBOOT_FILTERED=\n'
sudo -n efibootmgr | awk -v boot="Boot$created" '/^BootCurrent:|^BootNext:|^BootOrder:/ { print } index($0, boot) == 1 { print } /^Boot0006\*/ { print }'
