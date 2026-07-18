#!/usr/bin/env bash
set -euo pipefail
readonly RUNTIME_ROOT="${1:?runtime root is required}"
readonly OPENZFS_ROOT="${2:?OpenZFS root is required}"
readonly OPENZFS_MODULES="${3:?OpenZFS modules are required}"
readonly RELEASE="${4:?kernel release is required}"
readonly OUTPUT="${5:?output initramfs is required}"
readonly SOURCE_DATE_EPOCH="${6:?source date epoch is required}"
readonly POOL="${7:?pool name is required}"
readonly STATE_DATASET="${8:?state dataset is required}"
work="$(mktemp -d /tmp/mixtar-recovery.XXXXXX)"
cleanup() { case "$work" in /tmp/mixtar-recovery.*) rm -rf -- "$work" ;; esac; }
trap cleanup EXIT
root="$work/Root"
mkdir -p "$root/System/Commands" "$root/System/Configuration/OpenZFS" \
  "$root/System/Core/BusyBox" "$root/System/Devices" "$root/System/Hardware" \
  "$root/System/Init" "$root/System/Kernel/Linux/$RELEASE" \
  "$root/System/Libraries" "$root/System/Processes" "$root/System/Runtime" \
  "$root/System/Storage" "$root/System/Terminal/POSIX" "$root/EFI" "$root/State" "$root/etc"
busybox="$RUNTIME_ROOT/System/Core/BusyBox/busybox"
install -m0755 "$busybox" "$root/System/Core/BusyBox/busybox"
for applet in ash blkid cat cp cut grep mdev mkdir modprobe mount mv poweroff sed sh sha256sum sync test umount; do
  ln -s ../Core/BusyBox/busybox "$root/System/Commands/$applet"
done
ln -s ../../Core/BusyBox/busybox "$root/System/Terminal/POSIX/sh"
cp -a "$OPENZFS_ROOT/System/Storage/." "$root/System/Storage/"
cp -a "$OPENZFS_ROOT/System/Libraries/." "$root/System/Libraries/"
cp -a "$OPENZFS_MODULES/." "$root/System/Kernel/Linux/$RELEASE/"
rm -f "$root/System/Kernel/Linux/$RELEASE/build" "$root/System/Kernel/Linux/$RELEASE/source"
/usr/sbin/depmod --basedir "$root" --moduledir /System/Kernel/Linux "$RELEASE"
printf '\115\130\124\122' >"$root/etc/hostid"
cp "$root/etc/hostid" "$root/System/Configuration/OpenZFS/hostid"
ln -s System/Devices "$root/dev"
ln -s System/Hardware "$root/sys"
ln -s System/Processes "$root/proc"
ln -s System/Runtime "$root/run"
cat >"$root/System/Init/MixtarRVS" <<EOF
#!/System/Terminal/POSIX/sh
set -eu
PATH=/System/Commands
export PATH
LOADER=/System/Libraries/Loader/ld-linux-x86-64.so.2
LIBRARIES=/System/Storage/OpenZFS/Libraries:/System/Libraries
ZPOOL_BINARY=/System/Storage/OpenZFS/Commands/zpool
ZFS_BINARY=/System/Storage/OpenZFS/Commands/zfs
POOL='$POOL'
STATE_DATASET='$STATE_DATASET'
zpool() { "\$LOADER" --library-path "\$LIBRARIES" "\$ZPOOL_BINARY" "\$@"; }
zfs() { "\$LOADER" --library-path "\$LIBRARIES" "\$ZFS_BINARY" "\$@"; }
value() { sed -n "s/^\$1 = \"\\([^\"]*\\)\"\$/\\1/p" "\$2"; }
find_esp() {
  for device in /System/Devices/vd*[0-9] /System/Devices/sd*[0-9] /System/Devices/nvme*n*p*; do
    [ -b "\$device" ] || continue
    label=\$(blkid "\$device" 2>/System/Devices/null | sed -n 's/.*LABEL="\\([^\"]*\\)".*/\\1/p' || true)
    [ "\$label" = MIXTARRVS ] && { printf '%s\n' "\$device"; return 0; }
  done
  return 1
}
rollback() {
  transaction=/State/Update/Transaction.config
  [ -f "\$transaction" ] || { printf '%s\n' 'MixtarRVS recovery: no transaction'; return 1; }
  previous=\$(value previous_dataset "\$transaction")
  candidate=\$(value candidate_dataset "\$transaction")
  case "\$previous" in mixtar/ROOT/M1-A|mixtar/ROOT/M1-B) ;; *) return 1 ;; esac
  case "\$candidate" in mixtar/ROOT/M1-A|mixtar/ROOT/M1-B) ;; *) return 1 ;; esac
  esp=\$(find_esp) || return 1
  mount -t vfat "\$esp" /EFI
  [ -s /EFI/EFI/Mixtar/Previous.EFI ] || return 1
  cp /EFI/EFI/Mixtar/Previous.EFI /EFI/EFI/BOOT/BOOTX64.EFI.new
  sync
  mv /EFI/EFI/BOOT/BOOTX64.EFI.new /EFI/EFI/BOOT/BOOTX64.EFI
  sync
  umount /EFI
  zpool set bootfs="\$previous" "\$POOL"
  printf '%s\n' rolled-back >/State/Update/Rollback
  sync
  printf 'MixtarRVS: recovery restored %s\n' "\$previous"
}
mount -t devtmpfs devtmpfs /System/Devices
mount -t proc proc /System/Processes
mount -t sysfs sysfs /System/Hardware
mount -t tmpfs tmpfs /System/Runtime
mdev -s
modprobe zfs
zpool import -N -o cachefile=none "\$POOL"
mount -t zfs "\$STATE_DATASET" /State
if grep -qw 'mixtar.recovery=rollback' /System/Processes/cmdline; then
  rollback
  umount /State
  zpool export "\$POOL"
  sync
  poweroff -f
fi
printf '%s\n' 'MixtarRVS recovery console'
printf '%s\n' 'Type rollback to restore the previous accepted release, or shell.'
while read -r command; do
  case "\$command" in
    rollback) rollback && poweroff -f ;;
    shell) exec /System/Commands/sh </System/Devices/console >/System/Devices/console 2>&1 ;;
    *) printf '%s\n' 'Commands: rollback, shell' ;;
  esac
done </System/Devices/console >/System/Devices/console 2>&1
EOF
chmod 0755 "$root/System/Init/MixtarRVS"
cat >"$root/init" <<'EOF'
#!/System/Terminal/POSIX/sh
exec /System/Init/MixtarRVS "$@"
EOF
chmod 0755 "$root/init"
mknod -m0600 "$root/System/Devices/console" c 5 1
mknod -m0666 "$root/System/Devices/null" c 1 3
find "$root" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
mkdir -p "$(dirname "$OUTPUT")"
( cd "$root"; find . -print0 | LC_ALL=C sort -z | cpio --null --create --format=newc --owner=0:0 --reproducible ) >"$OUTPUT"
printf '%s\n' "$OUTPUT"
