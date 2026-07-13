#!/bin/sh
set -eu

STAGE="0082"
LABEL="MixtarRVS RT Candidate 0082 direct service supervisor"
ROOT_DEV="/dev/nvme0n1"
ROOT_PART="/dev/nvme0n1p3"
ESP_PART_NUM="1"
ESP_PART="/dev/nvme0n1p1"
STABLE_ORDER="0006,0003,0004,0005,0017,0018,0019,001A,001B,001C,001D,001E,001F"

SYSTEM_ROOT="/System"
if mountpoint -q /System/Runtime/initramfs/base 2>/dev/null && [ -d /System/Runtime/initramfs/base/System/Generations ]; then
  SYSTEM_ROOT="/System/Runtime/initramfs/base/System"
fi

SRC="$SYSTEM_ROOT/Generations/0033-rootfs-image-hard-trace-pid1-supervisor/rootfs.squashfs"
if [ ! -f "$SRC" ]; then
  SRC="$SYSTEM_ROOT/Generations/0033-rootfs-image-early-watchdog-supervisor/rootfs.squashfs"
fi
if [ ! -f "$SRC" ]; then
  SRC="$SYSTEM_ROOT/Generations/0032-rootfs-image-bounded-local-health-supervisor/rootfs.squashfs"
fi

TARGET_DIR="$SYSTEM_ROOT/Generations/0033-rootfs-image-direct-service-supervisor"
TARGET="$TARGET_DIR/rootfs.squashfs"
WORK="/tmp/mixtar-stage-0082"
ESP="/tmp/mixtar-esp-0082"

require() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required tool: $1" >&2
    exit 1
  fi
}

safe_rm_work() {
  case "$1" in
    /tmp/mixtar-stage-0082|/tmp/mixtar-stage-0082/*) rm -rf "$1" ;;
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

  cat > "$root/System/Base/Closure/0082-direct-service.manifest" <<'MANIFEST'
stage=0082
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

STAGE="0082"
BASE="/System/Runtime/initramfs/base"
LOG_DIR="$BASE/System/Base/Closure"
LOG="$LOG_DIR/0082-direct-service.log"
SSHD_LOG="$LOG_DIR/0082-sshd.log"

mkdir -p "$LOG_DIR" /run /tmp /dev /proc /sys 2>/dev/null
printf '0082 direct service pid1 start\n' > "$LOG" 2>/dev/null
printf 'cmdline=' >> "$LOG" 2>/dev/null
cat /proc/cmdline >> "$LOG" 2>/dev/null
printf '\n' >> "$LOG" 2>/dev/null
sync
printf 'MixtarRVS 0082 direct service pid1 start\n' >/dev/console 2>/dev/null

log() {
  printf '%s\n' "$*" >> "$LOG" 2>/dev/null
  sync
}

run_bg() {
  name="$1"
  shift
  log "### start-bg $name: $*"
  "$@" >> "$LOG" 2>&1 &
  pid=$!
  log "### pid $name=$pid"
}

run_cmd() {
  log "### begin: $*"
  "$@" >> "$LOG" 2>&1
  rc=$?
  log "### rc=$rc: $*"
  return 0
}

mount_basic() {
  log "phase mount_basic"
  mountpoint -q /dev 2>/dev/null || mount -t devtmpfs devtmpfs /dev >> "$LOG" 2>&1
  mountpoint -q /proc 2>/dev/null || mount -t proc proc /proc >> "$LOG" 2>&1
  mountpoint -q /sys 2>/dev/null || mount -t sysfs sysfs /sys >> "$LOG" 2>&1
  mountpoint -q /run 2>/dev/null || mount -t tmpfs tmpfs /run >> "$LOG" 2>&1
  mountpoint -q /tmp 2>/dev/null || mount -t tmpfs tmpfs /tmp >> "$LOG" 2>&1
  mkdir -p /run/dbus /var/run/dbus /run/dhcpcd /run/lock /var/run 2>/dev/null
  ip link set lo up >> "$LOG" 2>&1
  log "phase mount_basic done"
}

bind_dir() {
  src="$1"
  dst="$2"
  [ -d "$src" ] || return 0
  mkdir -p "$dst" 2>/dev/null
  mountpoint -q "$dst" 2>/dev/null || mount -o bind "$src" "$dst" >> "$LOG" 2>&1
}

bind_file() {
  src="$1"
  dst="$2"
  [ -f "$src" ] || return 0
  [ -e "$dst" ] || return 0
  mount -o bind "$src" "$dst" >> "$LOG" 2>&1
}

bind_state() {
  log "phase bind_state"
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
  log "phase bind_state done"
}

snapshot() {
  {
    echo "SNAPSHOT"
    echo "stage=$STAGE"
    echo "root=$(awk '$2 == "/" { print; exit }' /proc/mounts 2>/dev/null)"
    echo "base=$(awk '$2 == "/System/Runtime/initramfs/base" { print; exit }' /proc/mounts 2>/dev/null)"
    echo "processes="
    ps 2>/dev/null
    echo "network="
    ip -4 addr 2>/dev/null
    ip route 2>/dev/null
    echo "listen="
    netstat -ltn 2>/dev/null
  } >> "$LOG" 2>&1
  sync
}

start_watchdog() {
  log "phase watchdog_start"
  (
    n=0
    while [ "$n" -lt 180 ]; do
      [ -e /run/mixtar-ssh-confirmed ] && exit 0
      n=$((n + 1))
      sleep 1
    done
    printf '0082 watchdog timeout; rebooting fallback\n' >> "$LOG" 2>/dev/null
    sync
    reboot -f
  ) &
}

start_services() {
  log "phase start_services"
  [ -x /usr/bin/dbus-daemon ] && run_cmd /usr/bin/dbus-daemon --system --fork
  [ -x /usr/libexec/iwd ] && run_bg iwd /usr/libexec/iwd
  sleep 4
  [ -x /sbin/dhcpcd ] && run_cmd /sbin/dhcpcd -B -q
  [ -x /usr/bin/ssh-keygen ] && run_cmd /usr/bin/ssh-keygen -A
  if [ -x /usr/sbin/sshd ]; then
    /usr/sbin/sshd -t >> "$LOG" 2>&1
    log "sshd_config_test_rc=$?"
    /usr/sbin/sshd -E "$SSHD_LOG" >> "$LOG" 2>&1
    log "sshd_start_rc=$?"
  fi
  log "phase start_services done"
}

health_gate() {
  failures=""
  if ! ip -4 addr show 2>/dev/null | grep ' inet ' | grep -v '127.0.0.1' >/dev/null 2>&1; then
    failures="$failures ipv4"
  fi
  listen="$(netstat -ltn 2>/dev/null)"
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
    log "health ok"
    touch /run/mixtar-ssh-confirmed 2>/dev/null
    return 0
  fi
  log "health failed:$failures"
  return 1
}

log "phase pid1_start"
mount_basic
start_watchdog
bind_state
snapshot
start_services

n=0
while [ "$n" -lt 60 ]; do
  n=$((n + 1))
  log "health attempt $n"
  health_gate && break
  sleep 1
done

snapshot
log "pid1 entering idle loop"
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
CMDLINE="initrd=\\EFI\\mixtarrvs-rt\\initrd-mixtar-candidate-0069.img rdinit=/mixtar-init root=UUID=$ROOT_UUID rootfstype=ext4 rootflags=ro modules=nvme,ext4,jbd2,mbcache rootwait ro quiet loglevel=3 threadirqs mixtar.profile=rt-7.1.2-mixtar-rt mixtar.rootfs=/System/Generations/0033-rootfs-image-direct-service-supervisor/rootfs.squashfs mixtar.overlay=readonly mixtar.fallback=previous mixtar.handoff=boot"

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
echo "LOG_AFTER_BOOT=/System/Runtime/initramfs/base/System/Base/Closure/0082-direct-service.log"
echo "default BootOrder restored to $STABLE_ORDER"
