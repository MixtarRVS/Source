#!/usr/bin/env bash
set -euo pipefail

readonly RUNTIME_ROOT="${1:?runtime root is required}"
readonly OPENZFS_ROOT="${2:?OpenZFS root is required}"
readonly OPENZFS_MODULES="${3:?OpenZFS modules are required}"
readonly RELEASE="${4:?kernel release is required}"
readonly OUTPUT="${5:?output initramfs is required}"
readonly SOURCE_DATE_EPOCH="${6:?source date epoch is required}"
readonly POOL="${7:?pool name is required}"
readonly ROOT_DATASET="${8:?root dataset is required}"
readonly ASHIFT="${9:?ashift is required}"
readonly COMPRESSION="${10:?compression is required}"
readonly RELEASE_SLOT="${11:?release slot is required}"
readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for path in "$RUNTIME_ROOT" "$OPENZFS_ROOT" "$OPENZFS_MODULES"; do
	[ -d "$path" ] || {
		printf 'Missing ZFS initramfs input: %s\n' "$path" >&2
		exit 2
	}
done
busybox="$RUNTIME_ROOT/System/Core/BusyBox/busybox"
zpool_binary="$OPENZFS_ROOT/System/Storage/OpenZFS/Commands/zpool"
zfs_binary="$OPENZFS_ROOT/System/Storage/OpenZFS/Commands/zfs"
for file in "$busybox" "$zpool_binary" "$zfs_binary"; do
	[ -f "$file" ] || {
		printf 'Missing ZFS initramfs file: %s\n' "$file" >&2
		exit 2
	}
done

work="$(mktemp -d /tmp/mixtar-zfs-initramfs.XXXXXX)"
cleanup() {
	case "$work" in
		/tmp/mixtar-zfs-initramfs.*) rm -rf -- "$work" ;;
	esac
}
trap cleanup EXIT
root="$work/Root"
mkdir -p \
	"$root/System/Commands" \
	"$root/System/Configuration/OpenZFS" \
	"$root/System/Core/BusyBox" \
	"$root/System/Devices" \
	"$root/System/Hardware" \
	"$root/System/Init" \
	"$root/System/Kernel/Linux/$RELEASE" \
	"$root/System/Libraries" \
	"$root/System/Mount" \
	"$root/System/Processes" \
	"$root/System/Runtime" \
	"$root/System/Storage" \
	"$root/System/Terminal/POSIX" \
	"$root/Target" \
	"$root/Payload" \
	"$root/etc"

install -m0755 "$busybox" "$root/System/Core/BusyBox/busybox"
for applet in \
	ash cat cp grep mdev mkdir mknod modprobe mount poweroff sh sleep \
	rm switch_root sync tar test umount; do
	ln -s ../Core/BusyBox/busybox "$root/System/Commands/$applet"
done
ln -s ../../Core/BusyBox/busybox "$root/System/Terminal/POSIX/ash"
ln -s ../../Core/BusyBox/busybox "$root/System/Terminal/POSIX/sh"

cp -a "$OPENZFS_ROOT/System/Storage/." "$root/System/Storage/"
cp -a "$OPENZFS_ROOT/System/Libraries/." "$root/System/Libraries/"
cp -a "$OPENZFS_MODULES/." "$root/System/Kernel/Linux/$RELEASE/"
rm -f \
	"$root/System/Kernel/Linux/$RELEASE/build" \
	"$root/System/Kernel/Linux/$RELEASE/source"
/usr/sbin/depmod \
	--basedir "$root" \
	--moduledir /System/Kernel/Linux \
	"$RELEASE"

printf '\115\130\124\122' >"$root/etc/hostid"
cp "$root/etc/hostid" "$root/System/Configuration/OpenZFS/hostid"
ln -s System/Devices "$root/dev"
ln -s System/Hardware "$root/sys"
ln -s System/Processes "$root/proc"
ln -s System/Runtime "$root/run"

python3 - \
  "$REPO_ROOT/Root/System/Configuration/Layout.config" \
  "$root/System/Configuration/OpenZFS/lifecycle.datasets" <<'PY'
from __future__ import annotations

import re
import sys
import tomllib
from pathlib import Path, PurePosixPath

source = Path(sys.argv[1])
destination = Path(sys.argv[2])
configuration = tomllib.loads(source.read_text(encoding="utf-8"))
openzfs = configuration["components"]["openzfs"]
pool = openzfs["pool"]
datasets = openzfs.get("lifecycle_datasets")

if not isinstance(pool, str) or not re.fullmatch(r"[A-Za-z0-9_.-]+", pool):
    raise SystemExit("components.openzfs.pool is not a valid ZFS pool name")
if not isinstance(datasets, list) or not datasets:
    raise SystemExit("components.openzfs.lifecycle_datasets must be a non-empty array")

allowed_targets = {"/Users", "/System/State", "/System/Logs", "/System/Cache"}
allowed_lifecycles = {"persistent", "rebuildable"}
seen_paths: set[str] = set()
seen_targets: set[str] = set()
lines: list[str] = []

for index, entry in enumerate(datasets):
    if not isinstance(entry, dict):
        raise SystemExit(f"lifecycle dataset #{index + 1} must be a table")

    path = entry.get("path")
    target = entry.get("target")
    lifecycle = entry.get("lifecycle")

    if not isinstance(path, str) or not re.fullmatch(
        r"[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*", path
    ):
        raise SystemExit(f"invalid lifecycle dataset path at index {index}")
    if any(part in {"", ".", ".."} for part in path.split("/")):
        raise SystemExit(f"dataset path {path!r} contains an invalid component")
    if target not in allowed_targets or str(PurePosixPath(target)) != target:
        raise SystemExit(f"unsupported native mount target {target!r}")
    if lifecycle not in allowed_lifecycles:
        raise SystemExit(f"unsupported lifecycle {lifecycle!r} for {path!r}")
    if path in seen_paths or target in seen_targets:
        raise SystemExit(f"duplicate lifecycle dataset path or target: {path!r}, {target!r}")

    seen_paths.add(path)
    seen_targets.add(target)
    lines.append(f"{pool}/{path}\t{target}\t{lifecycle}")

if seen_targets != allowed_targets:
    missing = ", ".join(sorted(allowed_targets - seen_targets))
    raise SystemExit(f"missing native lifecycle dataset targets: {missing}")

destination.write_text("\n".join(lines) + "\n", encoding="ascii")
PY

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
ROOT_DATASET='$ROOT_DATASET'
RELEASE_SLOT='$RELEASE_SLOT'

zpool() {
  "\$LOADER" --library-path "\$LIBRARIES" "\$ZPOOL_BINARY" "\$@"
}

zfs() {
  "\$LOADER" --library-path "\$LIBRARIES" "\$ZFS_BINARY" "\$@"
}

rescue() {
  code="\$?"
  printf 'MixtarRVS: ZFS bootstrap failed (%s)\n' "\$code"
  exec /System/Commands/sh </System/Devices/console \
    >/System/Devices/console 2>&1
}
trap rescue EXIT

readonly DATASET_PLAN=/System/Configuration/OpenZFS/lifecycle.datasets

create_lifecycle_datasets() {
  while IFS="\$(printf '\t')" read -r dataset target lifecycle; do
    [ -n "\$dataset" ] || continue
    zfs create -p \
      -o canmount=noauto \
      -o mountpoint=legacy \
      -o "org.mixtar:lifecycle=\$lifecycle" \
      "\$dataset"
  done < "\$DATASET_PLAN"
}

seed_and_mount_lifecycle_datasets() {
  prefix="\$1"
  staging=/System/Runtime/LifecycleDataset
  mkdir -p "\$staging"

  while IFS="\$(printf '\t')" read -r dataset target lifecycle; do
    [ -n "\$dataset" ] || continue
    mkdir -p "\$prefix\$target"
    mount -t zfs "\$dataset" "\$staging"
    cp -a "\$prefix\$target/." "\$staging/"
    umount "\$staging"
    mount -t zfs "\$dataset" "\$prefix\$target"
  done < "\$DATASET_PLAN"
}

mount_lifecycle_datasets() {
  prefix="\$1"
  while IFS="\$(printf '\t')" read -r dataset target lifecycle; do
    [ -n "\$dataset" ] || continue
    mkdir -p "\$prefix\$target"
    mount -t zfs "\$dataset" "\$prefix\$target"
  done < "\$DATASET_PLAN"
}

unmount_lifecycle_datasets() {
  prefix="\$1"
  while IFS="\$(printf '\t')" read -r dataset target lifecycle; do
    [ -n "\$dataset" ] || continue
    umount "\$prefix\$target"
  done < "\$DATASET_PLAN"
}

verify_lifecycle_persistence() {
  pending=/System/Mount/System/State/Acceptance/P2-persistence-pending
  [ -f "\$pending" ] || return 0

  grep -qx mixtar-p2-persistence-v1 "\$pending"
  grep -qx mixtar-p2-persistence-v1 /System/Mount/Users/.Mixtar-P2-persistence
  grep -qx mixtar-p2-persistence-v1 /System/Mount/System/State/P2-persistence
  grep -qx mixtar-p2-persistence-v1 /System/Mount/System/Logs/P2-persistence

  mkdir -p /System/Mount/System/State/Acceptance
  printf '%s\n' complete \
    >/System/Mount/System/State/Acceptance/P2-lifecycle-persistence
  sync
  rm -f "\$pending"
  sync
  rm -f \
    /System/Mount/Users/.Mixtar-P2-persistence \
    /System/Mount/System/State/P2-persistence \
    /System/Mount/System/Logs/P2-persistence
  printf '%s\n' 'MixtarRVS: P2 lifecycle persistence ok'
}

shutdown_from_initramfs() {
  sync
  unmount_lifecycle_datasets /System/Mount
  umount /System/Mount
  zpool export "\$POOL"
  trap - EXIT
  poweroff -f
}

mount -t devtmpfs devtmpfs /System/Devices
mount -t proc proc /System/Processes
mount -t sysfs sysfs /System/Hardware
mount -t tmpfs tmpfs /System/Runtime
mdev -s
modprobe zfs

if grep -qw 'mixtar.zfs.provision=1' /System/Processes/cmdline; then
  zpool create -f \
    -o ashift='$ASHIFT' \
    -o cachefile=none \
    -O acltype=posixacl \
    -O atime=off \
    -O canmount=off \
    -O compression='$COMPRESSION' \
    -O mountpoint=none \
    "\$POOL" /dev/vda2
  zfs create -o canmount=off -o mountpoint=none "\$POOL/ROOT"
  zfs create -o canmount=noauto -o mountpoint=legacy "\$ROOT_DATASET"
  create_lifecycle_datasets
  zpool set bootfs="\$ROOT_DATASET" "\$POOL"
  mount -t zfs "\$ROOT_DATASET" /Target
  mount -t vfat /dev/vdb /Payload
  tar -xf /Payload/root.tar -C /Target
  seed_and_mount_lifecycle_datasets /Target
  mkdir -p /Target/System/Configuration/OpenZFS
  printf '%s\n' initial >/Target/System/Configuration/OpenZFS/P1-acceptance
  sync
  zfs snapshot "\$ROOT_DATASET@p1-acceptance"
  printf '%s\n' modified >/Target/System/Configuration/OpenZFS/P1-acceptance
  zfs rollback "\$ROOT_DATASET@p1-acceptance"
  grep -qx initial /Target/System/Configuration/OpenZFS/P1-acceptance
  printf '%s\n' 'MixtarRVS: ZFS snapshot rollback ok'
  mkdir -p /Target/System/State/Acceptance
  printf '%s\n' mixtar-p2-persistence-v1 \
    >/Target/System/State/Acceptance/P2-persistence-pending
  printf '%s\n' mixtar-p2-persistence-v1 \
    >/Target/Users/.Mixtar-P2-persistence
  printf '%s\n' mixtar-p2-persistence-v1 \
    >/Target/System/State/P2-persistence
  printf '%s\n' mixtar-p2-persistence-v1 \
    >/Target/System/Logs/P2-persistence
  sync
  umount /Payload
  unmount_lifecycle_datasets /Target
  umount /Target
  zfs set readonly=on "\$ROOT_DATASET"
  zfs snapshot "\$ROOT_DATASET@accepted"
  zpool scrub -w "\$POOL"
  printf '%s\n' 'MixtarRVS: ZFS scrub ok'
  zpool export "\$POOL"
  printf '%s\n' 'MixtarRVS: ZFS provision complete'
  trap - EXIT
  sync
  poweroff -f
fi

printf 'MixtarRVS: boot slot %s\n' "\$RELEASE_SLOT"
zpool import -N -o cachefile=none "\$POOL"
[ "\$(zfs get -H -o value readonly "\$ROOT_DATASET")" = on ] || {
  printf '%s\n' 'MixtarRVS: system dataset is not immutable' >&2
  exit 1
}
mount -t zfs "\$ROOT_DATASET" /System/Mount
mount_lifecycle_datasets /System/Mount
verify_lifecycle_persistence
printf '%s\n' 'MixtarRVS: immutable ZFS root and lifecycle datasets mounted'

if grep -qw 'mixtar.p2.persistence=write' /System/Processes/cmdline; then
  mkdir -p \
    /System/Mount/System/Configuration \
    /System/Mount/System/State/Acceptance \
    /System/Mount/Users
  printf '%s\n' 'mixtar-p2-persistence-v1' \
    >/System/Mount/System/State/Acceptance/P2-Persistence.config
  printf '%s\n' 'mixtar-p2-persistence-v1' \
    >/System/Mount/System/State/P2-Persistence.state
  printf '%s\n' 'mixtar-p2-persistence-v1' \
    >/System/Mount/Users/P2-Persistence.user
  printf '%s\n' 'MixtarRVS: P2 persistence markers written'
  shutdown_from_initramfs
fi

if grep -qw 'mixtar.p2.persistence=verify' /System/Processes/cmdline; then
  grep -qx 'mixtar-p2-persistence-v1' \
    /System/Mount/System/State/Acceptance/P2-Persistence.config
  grep -qx 'mixtar-p2-persistence-v1' \
    /System/Mount/System/State/P2-Persistence.state
  grep -qx 'mixtar-p2-persistence-v1' \
    /System/Mount/Users/P2-Persistence.user
  printf '%s\n' 'MixtarRVS: P2 persistence verified'
  shutdown_from_initramfs
fi

mkdir -p /System/Runtime/Volumes
mount --move /System/Devices /System/Mount/System/Devices
mount --move /System/Processes /System/Mount/System/Processes
mount --move /System/Hardware /System/Mount/System/Hardware
mount --move /System/Runtime /System/Mount/System/Runtime
mount --bind /System/Mount/System/Runtime/Volumes /System/Mount/Volumes
trap - EXIT
exec /System/Commands/switch_root \
  /System/Mount /System/Init/MixtarRVS
EOF
chmod 0755 "$root/System/Init/MixtarRVS"
cat >"$root/init" <<'EOF'
#!/System/Terminal/POSIX/sh
exec /System/Init/MixtarRVS "$@"
EOF
chmod 0755 "$root/init"
mknod -m 0600 "$root/System/Devices/console" c 5 1
mknod -m 0666 "$root/System/Devices/null" c 1 3

find "$root" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
mkdir -p "$(dirname "$OUTPUT")"
(
	cd "$root"
	find . -print0 \
		| LC_ALL=C sort -z \
		| cpio --null --create --format=newc --owner=0:0 --reproducible
) >"$OUTPUT"
printf '%s\n' "$OUTPUT"



