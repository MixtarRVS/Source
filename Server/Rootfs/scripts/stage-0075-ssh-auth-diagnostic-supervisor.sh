#!/bin/sh
set -eu

STAGE="0075"
LABEL="MixtarRVS RT Candidate 0075 ssh auth diagnostic"
ROOT_DEV="/dev/nvme0n1"
ROOT_PART="/dev/nvme0n1p3"
ESP_PART_NUM="1"
ESP_PART="/dev/nvme0n1p1"
STABLE_ORDER="0006,0003,0004,0005,0017,0018,0019,001A,001B,001C,001D,001E,001F"

SRC="/System/Generations/0027-rootfs-image-users-users-network-ready-supervisor/rootfs.squashfs"
if [ ! -f "$SRC" ]; then
  SRC="/System/Generations/0026-rootfs-image-network-ready-supervisor/rootfs.squashfs"
fi

TARGET_DIR="/System/Generations/0028-rootfs-image-ssh-auth-diagnostic-supervisor"
TARGET="$TARGET_DIR/rootfs.squashfs"
WORK="/tmp/mixtar-stage-0075"
ESP="/tmp/mixtar-esp-0075"

require() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required tool: $1" >&2
    exit 1
  fi
}

safe_rm_work() {
  case "$1" in
    /tmp/mixtar-stage-0075|/tmp/mixtar-stage-0075/*) rm -rf "$1" ;;
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
    "$root/home" \
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

  rm -rf "$root/home"
  ln -s Users "$root/home"

  if [ ! -x "$root/System/Shells/zsh" ]; then
    if [ -x "$root/bin/zsh" ]; then
      ln -sf /bin/zsh "$root/System/Shells/zsh"
    elif [ -x "$root/usr/bin/zsh" ]; then
      ln -sf /usr/bin/zsh "$root/System/Shells/zsh"
    elif [ -x "$root/System/Tools/zsh" ]; then
      ln -sf /System/Tools/zsh "$root/System/Shells/zsh"
    fi
  fi

  touch \
    "$root/etc/passwd" \
    "$root/etc/group" \
    "$root/etc/shadow" \
    "$root/etc/gshadow" \
    "$root/etc/sudoers" \
    "$root/etc/shells" \
    "$root/etc/resolv.conf"

  if ! grep -qx '/System/Shells/zsh' "$root/etc/shells" 2>/dev/null; then
    printf '%s\n' '/System/Shells/zsh' >> "$root/etc/shells"
  fi

  cat > "$root/sbin/init" <<'INIT'
#!/bin/sh

PATH=/System/Tools:/System/SystemTools:/bin:/sbin:/usr/bin:/usr/sbin
export PATH

STAGE="0075"
BASE="/System/Runtime/initramfs/base"
LOG_DIR="$BASE/System/Base/Closure"
LOG="$LOG_DIR/0075-init.log"

write_log() {
  mkdir -p "$LOG_DIR" 2>/dev/null || true
  printf '%s\n' "$*" >> "$LOG" 2>/dev/null || printf '%s\n' "$*"
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

diag_auth() {
  write_log "--- auth diag: $1 ---"
  {
    echo "cmdline=$(cat /proc/cmdline 2>/dev/null)"
    echo "mounts:"
    mount
    echo "passwd:"
    getent passwd vxz 2>/dev/null || grep '^vxz:' /etc/passwd 2>/dev/null || true
    id vxz 2>/dev/null || true
    echo "paths:"
    for p in /Users /home /Users/vxz /home/vxz /Users/vxz/.ssh /Users/vxz/.ssh/authorized_keys /home/vxz/.ssh /home/vxz/.ssh/authorized_keys /System/Shells/zsh; do
      ls -ldn "$p" 2>/dev/null || echo "missing $p"
    done
    echo "stat:"
    for p in /Users /home /Users/vxz /home/vxz /Users/vxz/.ssh /Users/vxz/.ssh/authorized_keys /home/vxz/.ssh /home/vxz/.ssh/authorized_keys /System/Shells/zsh; do
      stat -c '%a %U %G %n' "$p" 2>/dev/null || true
    done
    echo "keyhash:"
    sha256sum /Users/vxz/.ssh/authorized_keys 2>/dev/null || true
    sha256sum /home/vxz/.ssh/authorized_keys 2>/dev/null || true
    echo "sshd effective:"
    if [ -x /usr/sbin/sshd ]; then
      /usr/sbin/sshd -T 2>/dev/null | grep -Ei 'authorizedkeysfile|pubkeyauthentication|passwordauthentication|permitrootlogin|strictmodes|usepam|chrootdirectory|allowusers|denyusers|allowgroups|denygroups' || true
    fi
    echo "sshd listen:"
    ps | grep '[s]shd' || true
    ss -ltnp 2>/dev/null | grep ':22' || netstat -ltnp 2>/dev/null | grep ':22' || true
    echo "network:"
    ip addr 2>/dev/null || true
    ip route 2>/dev/null || true
    echo "services:"
    rc-status 2>/dev/null || true
  } >> "$LOG" 2>&1
}

mkdir -p "$LOG_DIR" /run /tmp /dev /proc /sys 2>/dev/null || true
mount_if_needed /dev -t devtmpfs devtmpfs
mount_if_needed /proc -t proc proc
mount_if_needed /sys -t sysfs sysfs
mount_if_needed /run -t tmpfs tmpfs
mount_if_needed /tmp -t tmpfs tmpfs
mkdir -p /run/openrc /run/lock /var/run 2>/dev/null || true

write_log "mixtar $STAGE init started"
write_log "pid=$$"
write_log "base=$BASE"

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

diag_auth "before-openrc"

run_log /sbin/openrc sysinit || true
run_log /sbin/openrc boot || true
run_log /sbin/openrc default || true

for n in $(seq 1 90); do
  ip -4 addr show 2>/dev/null | grep -q ' inet ' && break
  sleep 1
done

diag_auth "after-openrc"

(
  for n in $(seq 1 360); do
    if [ -e /run/mixtar-ssh-confirmed ]; then
      write_log "ssh confirmed; watchdog disabled"
      exit 0
    fi
    sleep 1
  done
  write_log "ssh was not confirmed within watchdog window; rebooting to fallback"
  sync
  reboot -f
) &

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
CMDLINE="initrd=\\EFI\\mixtarrvs-rt\\initrd-mixtar-candidate-0069.img rdinit=/mixtar-init root=UUID=$ROOT_UUID rootfstype=ext4 rootflags=ro modules=nvme,ext4,jbd2,mbcache rootwait ro quiet loglevel=3 threadirqs mixtar.profile=rt-7.1.2-mixtar-rt mixtar.rootfs=$TARGET mixtar.overlay=readonly mixtar.fallback=previous mixtar.handoff=boot"

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
echo "LOG_AFTER_BOOT=/System/Base/Closure/0075-init.log"
echo "default BootOrder restored to $STABLE_ORDER"
