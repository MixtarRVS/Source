#!/bin/sh
set -eu

STAGE="0083"
LABEL="MixtarRVS RT Candidate 0083 static network selftest supervisor"
ROOT_DEV="/dev/nvme0n1"
ROOT_PART="/dev/nvme0n1p3"
ESP_PART_NUM="1"
ESP_PART="/dev/nvme0n1p1"
STABLE_ORDER="0006,0003,0004,0005,0017,0018,0019,001A,001B,001C,001D,001E,001F"

SYSTEM_ROOT="/System"
if mountpoint -q /System/Runtime/initramfs/base 2>/dev/null && [ -d /System/Runtime/initramfs/base/System/Generations ]; then
  SYSTEM_ROOT="/System/Runtime/initramfs/base/System"
fi

SRC="$SYSTEM_ROOT/Generations/0033-rootfs-image-direct-service-supervisor/rootfs.squashfs"
if [ ! -f "$SRC" ]; then
  SRC="$SYSTEM_ROOT/Generations/0033-rootfs-image-hard-trace-pid1-supervisor/rootfs.squashfs"
fi
if [ ! -f "$SRC" ]; then
  SRC="$SYSTEM_ROOT/Generations/0033-rootfs-image-early-watchdog-supervisor/rootfs.squashfs"
fi

TARGET_DIR="$SYSTEM_ROOT/Generations/0034-rootfs-image-static-network-selftest-supervisor"
TARGET="$TARGET_DIR/rootfs.squashfs"
WORK="/tmp/mixtar-stage-0083"
ESP="/tmp/mixtar-esp-0083"

require() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required tool: $1" >&2
    exit 1
  fi
}

safe_rm_work() {
  case "$1" in
    /tmp/mixtar-stage-0083|/tmp/mixtar-stage-0083/*) rm -rf "$1" ;;
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

  cat > "$root/System/Base/Closure/0083-static-network-selftest.manifest" <<'MANIFEST'
stage=0083
identity=MixtarRVS
root_model=readonly-squashfs-image-root
persistent_base=/System/Runtime/initramfs/base
supervisor=/sbin/init
service_backend=direct-mixtar-pid1
openrc_scope=not-used
network_policy=static-ip-after-iwd
default_ipv4=192.168.99.110/24
fallback_preserved=true
selftest=/sbin/init --self-test
chroot_test=Server/Rootfs/scripts/rootfs-selftest-chroot.sh
alpine_role=bootstrap-compatibility-source-not-visible-identity
MANIFEST

  cat > "$root/sbin/init" <<'INIT'
#!/bin/sh

PATH=/System/Tools:/System/SystemTools:/bin:/sbin:/usr/bin:/usr/sbin
export PATH

STAGE="0083"
BASE="${MIXTAR_BASE:-/System/Runtime/initramfs/base}"
LOG_DIR="$BASE/System/Base/Closure"
LOG="$LOG_DIR/0083-static-network-selftest.log"
SSHD_LOG="$LOG_DIR/0083-sshd.log"
STATIC_ADDR="${MIXTAR_STATIC_ADDR:-192.168.99.110/24}"
STATIC_GW="${MIXTAR_STATIC_GW:-192.168.99.1}"
WIFI_IF="${MIXTAR_WIFI_IF:-wlan0}"

log() {
  printf '%s\n' "$*" >> "$LOG" 2>/dev/null
  sync 2>/dev/null || true
}

start_log() {
  mkdir -p "$LOG_DIR" /run /tmp /dev /proc /sys 2>/dev/null
  printf '0083 static network selftest pid1 start\n' > "$LOG" 2>/dev/null
  printf 'cmdline=' >> "$LOG" 2>/dev/null
  cat /proc/cmdline >> "$LOG" 2>/dev/null || true
  printf '\n' >> "$LOG" 2>/dev/null
  sync 2>/dev/null || true
}

need_path() {
  p="$1"
  if [ ! -e "$p" ]; then
    echo "missing: $p"
    return 1
  fi
  echo "ok: $p"
  return 0
}

self_test() {
  rc=0
  echo "MixtarRVS $STAGE self-test"
  if [ "${MIXTAR_SELFTEST_PREPARED:-0}" != "1" ]; then
    start_log
    mount_basic
    bind_state
  fi
  mkdir -p /run/sshd /run/dbus /var/run/dbus 2>/dev/null || true
  for p in \
    /bin/sh \
    /sbin/ip \
    /sbin/modprobe \
    /sbin/mdev \
    /usr/bin/dbus-daemon \
    /usr/libexec/iwd \
    /usr/sbin/sshd \
    /usr/bin/ssh-keygen \
    /bin/netstat
  do
    need_path "$p" || rc=1
  done
  for p in \
    /dev/console \
    /dev/null \
    /dev/tty \
    /System/Runtime/initramfs/base \
    /System/Base/Closure
  do
    need_path "$p" || rc=1
  done
  /usr/sbin/sshd -t >/dev/null 2>&1 || {
    echo "sshd config check failed"
    rc=1
  }
  if grep -q '^vxz:' /etc/passwd 2>/dev/null; then
    echo "ok: user vxz"
  else
    echo "missing: user vxz"
    rc=1
  fi
  return "$rc"
}

mount_basic() {
  log "phase mount_basic"
  mountpoint -q /dev 2>/dev/null || mount -t devtmpfs devtmpfs /dev >> "$LOG" 2>&1 || true
  mountpoint -q /proc 2>/dev/null || mount -t proc proc /proc >> "$LOG" 2>&1 || true
  mountpoint -q /sys 2>/dev/null || mount -t sysfs sysfs /sys >> "$LOG" 2>&1 || true
  mountpoint -q /run 2>/dev/null || mount -t tmpfs tmpfs /run >> "$LOG" 2>&1 || true
  mountpoint -q /tmp 2>/dev/null || mount -t tmpfs tmpfs /tmp >> "$LOG" 2>&1 || true
  mkdir -p /run/dbus /run/sshd /var/run/dbus /run/lock /var/run 2>/dev/null || true
  ip link set lo up >> "$LOG" 2>&1 || true
  log "phase mount_basic done"
}

bind_dir() {
  src="$1"
  dst="$2"
  [ -d "$src" ] || return 0
  mkdir -p "$dst" 2>/dev/null || true
  mountpoint -q "$dst" 2>/dev/null || mount -o bind "$src" "$dst" >> "$LOG" 2>&1 || true
}

bind_file() {
  src="$1"
  dst="$2"
  [ -f "$src" ] || return 0
  [ -e "$dst" ] || return 0
  mount -o bind "$src" "$dst" >> "$LOG" 2>&1 || true
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

run_cmd() {
  log "### begin: $*"
  "$@" >> "$LOG" 2>&1
  rc=$?
  log "### rc=$rc: $*"
  return 0
}

run_bg() {
  name="$1"
  shift
  log "### start-bg $name: $*"
  "$@" >> "$LOG" 2>&1 &
  log "### pid $name=$!"
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
    printf '0083 watchdog timeout; rebooting fallback\n' >> "$LOG" 2>/dev/null
    sync 2>/dev/null || true
    reboot -f
  ) &
}

snapshot() {
  {
    echo "SNAPSHOT"
    echo "stage=$STAGE"
    echo "root=$(awk '$2 == "/" { print; exit }' /proc/mounts 2>/dev/null)"
    echo "base=$(awk -v b="$BASE" '$2 == b { print; exit }' /proc/mounts 2>/dev/null)"
    echo "links="
    ip link show 2>/dev/null
    echo "ipv4="
    ip -4 addr 2>/dev/null
    echo "routes="
    ip route 2>/dev/null
    echo "listen="
    netstat -ltn 2>/dev/null
    echo "processes="
    ps 2>/dev/null
  } >> "$LOG" 2>&1
  sync 2>/dev/null || true
}

load_wifi_runtime() {
  log "phase load_wifi_runtime"
  modprobe cfg80211 >> "$LOG" 2>&1 || true
  modprobe mac80211 >> "$LOG" 2>&1 || true
  modprobe iwlwifi >> "$LOG" 2>&1 || true
  modprobe iwlmvm >> "$LOG" 2>&1 || true
  mdev -s >> "$LOG" 2>&1 || true
  rfkill unblock all >> "$LOG" 2>&1 || true
  ip link set "$WIFI_IF" up >> "$LOG" 2>&1 || true
  log "phase load_wifi_runtime done"
}

start_services() {
  log "phase start_services"
  [ -x /usr/bin/dbus-daemon ] && run_cmd /usr/bin/dbus-daemon --system --fork
  load_wifi_runtime
  [ -x /usr/libexec/iwd ] && run_bg iwd /usr/libexec/iwd
  sleep 10
  ip addr replace "$STATIC_ADDR" dev "$WIFI_IF" >> "$LOG" 2>&1 || true
  ip route replace default via "$STATIC_GW" dev "$WIFI_IF" >> "$LOG" 2>&1 || true
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
  if ! ip -4 addr show "$WIFI_IF" 2>/dev/null | grep -q ' inet '; then
    failures="$failures ipv4-$WIFI_IF"
  fi
  if ! netstat -ltn 2>/dev/null | grep -q ':22'; then
    failures="$failures sshd-listen"
  fi
  if ! grep -q '^vxz:' /etc/passwd 2>/dev/null; then
    failures="$failures user-vxz"
  fi
  if [ ! -s /Users/vxz/.ssh/authorized_keys ]; then
    failures="$failures authorized-keys"
  fi
  if [ -z "$failures" ]; then
    log "health ok"
    touch /run/mixtar-ssh-confirmed 2>/dev/null || true
    return 0
  fi
  log "health failed:$failures"
  return 1
}

run_pid1() {
  start_log
  printf 'MixtarRVS 0083 static network pid1 start\n' >/dev/console 2>/dev/null || true
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
}

case "${1:-}" in
  --self-test) self_test ;;
  --pid1|"") run_pid1 ;;
  *) echo "usage: /sbin/init [--self-test|--pid1]" >&2; exit 2 ;;
esac
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

if [ "${MIXTAR_BUILD_ONLY:-0}" = "1" ]; then
  echo "TARGET=$TARGET"
  echo "SELF_TEST=/sbin/init --self-test"
  echo "BUILD_ONLY=1"
  echo "EFI candidate was not created"
  exit 0
fi

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
CMDLINE="initrd=\\EFI\\mixtarrvs-rt\\initrd-mixtar-candidate-0069.img rdinit=/mixtar-init root=UUID=$ROOT_UUID rootfstype=ext4 rootflags=ro modules=nvme,ext4,jbd2,mbcache rootwait ro quiet loglevel=3 threadirqs mixtar.profile=rt-7.1.2-mixtar-rt mixtar.rootfs=/System/Generations/0034-rootfs-image-static-network-selftest-supervisor/rootfs.squashfs mixtar.overlay=readonly mixtar.fallback=previous mixtar.handoff=boot"

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
echo "SELF_TEST=/sbin/init --self-test"
echo "LOG_AFTER_BOOT=/System/Runtime/initramfs/base/System/Base/Closure/0083-static-network-selftest.log"
echo "default BootOrder restored to $STABLE_ORDER"
