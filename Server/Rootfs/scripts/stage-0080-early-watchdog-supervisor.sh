#!/bin/sh
set -eu

STAGE="0080"
LABEL="MixtarRVS RT Candidate 0080 early watchdog supervisor"
ROOT_DEV="/dev/nvme0n1"
ROOT_PART="/dev/nvme0n1p3"
ESP_PART_NUM="1"
ESP_PART="/dev/nvme0n1p1"
STABLE_ORDER="0006,0003,0004,0005,0017,0018,0019,001A,001B,001C,001D,001E,001F"

SYSTEM_ROOT="/System"
if mountpoint -q /System/Runtime/initramfs/base 2>/dev/null && [ -d /System/Runtime/initramfs/base/System/Generations ]; then
  SYSTEM_ROOT="/System/Runtime/initramfs/base/System"
fi

SRC="$SYSTEM_ROOT/Generations/0032-rootfs-image-bounded-local-health-supervisor/rootfs.squashfs"
if [ ! -f "$SRC" ]; then
  SRC="$SYSTEM_ROOT/Generations/0031-rootfs-image-local-health-supervisor/rootfs.squashfs"
fi
if [ ! -f "$SRC" ]; then
  SRC="$SYSTEM_ROOT/Generations/0030-rootfs-image-runtime-closure-confirmed-supervisor/rootfs.squashfs"
fi

TARGET_DIR="$SYSTEM_ROOT/Generations/0033-rootfs-image-early-watchdog-supervisor"
TARGET="$TARGET_DIR/rootfs.squashfs"
WORK="/tmp/mixtar-stage-0080"
ESP="/tmp/mixtar-esp-0080"

require() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required tool: $1" >&2
    exit 1
  fi
}

safe_rm_work() {
  case "$1" in
    /tmp/mixtar-stage-0080|/tmp/mixtar-stage-0080/*) rm -rf "$1" ;;
    *) echo "refusing to remove unsafe path: $1" >&2; exit 1 ;;
  esac
}

delete_existing_candidate() {
  ids="$(efibootmgr | awk -v label="$LABEL" 'index($0, label) { id=$1; sub(/^Boot/, "", id); sub(/\*$/, "", id); print id }')"
  for id in $ids; do
    efibootmgr -b "$id" -B >/dev/null 2>&1 || true
  done
}

write_stage_init() {
  root="$1"
  mkdir -p \
    "$root/dev" \
    "$root/proc" \
    "$root/sys" \
    "$root/run" \
    "$root/tmp" \
    "$root/Users" \
    "$root/System/Base/Closure" \
    "$root/System/Logs" \
    "$root/System/Runtime/initramfs/base" \
    "$root/System/Shells" \
    "$root/var/lib/iwd" \
    "$root/var/lib/dhcpcd" \
    "$root/var/log" \
    "$root/etc/ssh" \
    "$root/etc/sudoers.d"

  [ -e "$root/dev/console" ] || mknod -m 600 "$root/dev/console" c 5 1 2>/dev/null || true
  [ -e "$root/dev/null" ] || mknod -m 666 "$root/dev/null" c 1 3 2>/dev/null || true
  [ -e "$root/dev/zero" ] || mknod -m 666 "$root/dev/zero" c 1 5 2>/dev/null || true
  [ -e "$root/dev/tty" ] || mknod -m 666 "$root/dev/tty" c 5 0 2>/dev/null || true
  [ -e "$root/dev/tty0" ] || mknod -m 620 "$root/dev/tty0" c 4 0 2>/dev/null || true
  [ -e "$root/dev/tty1" ] || mknod -m 620 "$root/dev/tty1" c 4 1 2>/dev/null || true

  rm -rf "$root/home"
  ln -s Users "$root/home"

  touch \
    "$root/etc/passwd" \
    "$root/etc/group" \
    "$root/etc/shadow" \
    "$root/etc/gshadow" \
    "$root/etc/sudoers" \
    "$root/etc/shells" \
    "$root/etc/resolv.conf"

  cat > "$root/System/Base/Closure/0080-early-watchdog.manifest" <<'MANIFEST'
stage=0080
identity=MixtarRVS
root_model=readonly-squashfs-image-root
persistent_base=/System/Runtime/initramfs/base
supervisor=/sbin/init
service_backend=OpenRC-bootstrap
openrc_scope=boot,default
sysinit_policy=owned-by-mixtar-pid1-before-openrc-boot
runtime_mounts=/dev,/proc,/sys,/run,/tmp
persistent_dirs=/Users,/var/lib/iwd,/var/lib/dhcpcd,/System/Logs,/var/log,/etc/ssh,/etc/sudoers.d
persistent_files=/etc/passwd,/etc/group,/etc/shadow,/etc/gshadow,/etc/sudoers,/etc/shells,/etc/resolv.conf
account_source=current-base-bind
ssh_source=current-base-bind
network_source=current-base-bind
fallback_preserved=true
alpine_role=bootstrap-compatibility-source-not-visible-identity
MANIFEST

  cat > "$root/sbin/init" <<'INIT'
#!/bin/sh

PATH=/System/Tools:/System/SystemTools:/bin:/sbin:/usr/bin:/usr/sbin
export PATH

STAGE="0080"
BASE="/System/Runtime/initramfs/base"
LOG_DIR="$BASE/System/Base/Closure"
LOG="$LOG_DIR/0080-early-watchdog.log"

write_log() {
  mkdir -p "$LOG_DIR" 2>/dev/null || true
  printf '%s\n' "$*" >> "$LOG" 2>/dev/null || true
}

run_log() {
  write_log "### $*"
  "$@" >> "$LOG" 2>&1
  rc=$?
  write_log "### rc=$rc: $*"
  return "$rc"
}

mount_if_needed() {
  target="$1"
  shift
  mountpoint -q "$target" 2>/dev/null && return 0
  mount "$@" "$target" >> "$LOG" 2>&1 || true
}

bind_dir() {
  src="$1"
  dst="$2"
  [ -d "$src" ] || return 0
  mkdir -p "$dst" 2>/dev/null || true
  mountpoint -q "$dst" 2>/dev/null && return 0
  mount -o bind "$src" "$dst" >> "$LOG" 2>&1 || true
}

bind_file() {
  src="$1"
  dst="$2"
  [ -f "$src" ] || return 0
  [ -e "$dst" ] || return 0
  mount -o bind "$src" "$dst" >> "$LOG" 2>&1 || true
}

start_watchdog() {
  (
    for n in $(seq 1 180); do
      if [ -e /run/mixtar-ssh-confirmed ]; then
        write_log "ssh confirmed; early watchdog disabled"
        exit 0
      fi
      sleep 1
    done
    write_log "early watchdog timeout; rebooting to fallback"
    sync
    reboot -f
  ) &
}

health_gate() {
  failures=""
  cmdline="$(cat /proc/cmdline 2>/dev/null || true)"
  case "$cmdline" in
    *0033-rootfs-image-early-watchdog-supervisor*) ;;
    *) failures="$failures rootfs" ;;
  esac
  if ! ip -4 addr show 2>/dev/null | grep ' inet ' | grep -v '127.0.0.1' >/dev/null 2>&1; then
    failures="$failures ipv4"
  fi
  listen="$(ss -ltn 2>/dev/null || netstat -ltn 2>/dev/null || true)"
  if ! printf '%s\n' "$listen" | grep -q ':22'; then
    failures="$failures sshd-listen"
  fi
  if ! getent passwd vxz >/dev/null 2>&1 && ! grep -q '^vxz:' /etc/passwd 2>/dev/null; then
    failures="$failures user-vxz"
  fi
  if [ ! -s /Users/vxz/.ssh/authorized_keys ]; then
    failures="$failures authorized-keys"
  fi
  if [ -z "$failures" ]; then
    write_log "health gate ok; creating /run/mixtar-ssh-confirmed"
    touch /run/mixtar-ssh-confirmed 2>/dev/null || true
    return 0
  fi
  write_log "health gate failed:$failures"
  return 1
}
runtime_snapshot() {
  {
    echo "stage=$STAGE"
    echo "cmdline=$(cat /proc/cmdline 2>/dev/null || true)"
    echo "root=$(awk '$2 == "/" { print; exit }' /proc/mounts 2>/dev/null || true)"
    echo "base=$(awk '$2 == "/System/Runtime/initramfs/base" { print; exit }' /proc/mounts 2>/dev/null || true)"
    echo "mounts="
    mount | grep -E ' / |/System/Runtime/initramfs/base|/Users|/var/lib/iwd|/var/lib/dhcpcd|/System/Logs|/var/log|/etc/ssh|/etc/passwd|/etc/group|/etc/shadow|/etc/sudoers|/etc/shells|/etc/resolv.conf' || true
    echo "user="
    getent passwd vxz 2>/dev/null || grep '^vxz:' /etc/passwd 2>/dev/null || true
    id vxz 2>/dev/null || true
    echo "ssh_keys="
    ls -ldn /Users/vxz/.ssh /Users/vxz/.ssh/authorized_keys 2>/dev/null || true
    sha256sum /Users/vxz/.ssh/authorized_keys 2>/dev/null || true
    echo "network="
    ip -4 addr 2>/dev/null || true
    ip route 2>/dev/null || true
    echo "services="
    rc-status 2>/dev/null || true
  } >> "$LOG" 2>&1
}

mkdir -p "$LOG_DIR" /run /tmp /dev /proc /sys 2>/dev/null || true
: > "$LOG" 2>/dev/null || true
write_log "mixtar $STAGE local health supervisor started"

mount_if_needed /dev -t devtmpfs devtmpfs
mount_if_needed /proc -t proc proc
mount_if_needed /sys -t sysfs sysfs
mount_if_needed /run -t tmpfs tmpfs
mount_if_needed /tmp -t tmpfs tmpfs
mkdir -p /run/openrc /run/lock /var/run 2>/dev/null || true
ip link set lo up >> "$LOG" 2>&1 || true
start_watchdog

bind_dir "$BASE/Users" /Users
bind_dir "$BASE/var/lib/iwd" /var/lib/iwd
bind_dir "$BASE/var/lib/dhcpcd" /var/lib/dhcpcd
bind_dir "$BASE/System/Logs" /System/Logs
bind_dir "$BASE/var/log" /var/log
bind_dir "$BASE/etc/ssh" /etc/ssh
bind_dir "$BASE/etc/sudoers.d" /etc/sudoers.d
bind_file "$BASE/etc/passwd" /etc/passwd
bind_file "$BASE/etc/group" /etc/group
bind_file "$BASE/etc/shadow" /etc/shadow
bind_file "$BASE/etc/gshadow" /etc/gshadow
bind_file "$BASE/etc/sudoers" /etc/sudoers
bind_file "$BASE/etc/shells" /etc/shells
bind_file "$BASE/etc/resolv.conf" /etc/resolv.conf

runtime_snapshot

run_log /sbin/openrc sysinit || true
run_log /sbin/openrc boot || true
run_log /sbin/openrc default || true

for n in $(seq 1 45); do
  write_log "health attempt $n"
  if health_gate; then
    break
  fi
  sleep 1
done

runtime_snapshot

while :; do
  sleep 60
done
INIT

  chmod +x "$root/sbin/init"
  printf 'MixtarRVS stage %s\n' "$STAGE" > "$root/etc/mixtar-stage"
}

require unsquashfs
require mksquashfs
require efibootmgr
require blkid

if [ "$(id -u)" != "0" ]; then
  echo "run as root" >&2
  exit 1
fi

if [ ! -f "$SRC" ]; then
  echo "source rootfs not found: $SRC" >&2
  exit 1
fi

safe_rm_work "$WORK"
mkdir -p "$WORK" "$TARGET_DIR"

echo "system_root=$SYSTEM_ROOT"
echo "source=$SRC"
echo "target=$TARGET"
unsquashfs -d "$WORK/root" "$SRC" >/dev/null
write_stage_init "$WORK/root"

tmp_target="$TARGET.tmp"
rm -f "$tmp_target"
mksquashfs "$WORK/root" "$tmp_target" -noappend >/dev/null
mv "$tmp_target" "$TARGET"

cat > "$TARGET_DIR/manifest.txt" <<EOF
stage=$STAGE
source=$SRC
target=$TARGET
label=$LABEL
system_root=$SYSTEM_ROOT
created_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

delete_existing_candidate

mkdir -p "$ESP"
if ! mountpoint -q "$ESP" 2>/dev/null; then
  mount -t vfat "$ESP_PART" "$ESP" 2>/dev/null || mount "$ESP_PART" "$ESP"
fi

if [ ! -f "$ESP/EFI/mixtarrvs-rt/vmlinuz.efi" ]; then
  echo "missing EFI kernel: $ESP/EFI/mixtarrvs-rt/vmlinuz.efi" >&2
  exit 1
fi

if [ ! -f "$ESP/EFI/mixtarrvs-rt/initrd-mixtar-candidate-0069.img" ]; then
  echo "missing Mixtar candidate initrd: $ESP/EFI/mixtarrvs-rt/initrd-mixtar-candidate-0069.img" >&2
  exit 1
fi

ROOT_UUID="$(blkid -s UUID -o value "$ROOT_PART")"
CMDLINE="initrd=\\EFI\\mixtarrvs-rt\\initrd-mixtar-candidate-0069.img rdinit=/mixtar-init root=UUID=$ROOT_UUID rootfstype=ext4 rootflags=ro modules=nvme,ext4,jbd2,mbcache rootwait ro quiet loglevel=3 threadirqs mixtar.profile=rt-7.1.2-mixtar-rt mixtar.rootfs=/System/Generations/0033-rootfs-image-early-watchdog-supervisor/rootfs.squashfs mixtar.overlay=readonly mixtar.fallback=previous mixtar.handoff=boot"

efibootmgr \
  -c \
  -d "$ROOT_DEV" \
  -p "$ESP_PART_NUM" \
  -L "$LABEL" \
  -l "\\EFI\\mixtarrvs-rt\\vmlinuz.efi" \
  -u "$CMDLINE" >/dev/null

BOOT_ID="$(efibootmgr | awk -v label="$LABEL" 'index($0, label) { id=$1; sub(/^Boot/, "", id); sub(/\*$/, "", id); print id; exit }')"
efibootmgr -o "$STABLE_ORDER" >/dev/null 2>&1 || true

echo "BOOT_ID=$BOOT_ID"
echo "TARGET=$TARGET"
echo "LOG_AFTER_BOOT=/System/Runtime/initramfs/base/System/Base/Closure/0080-early-watchdog.log"
echo "default BootOrder restored to $STABLE_ORDER"
