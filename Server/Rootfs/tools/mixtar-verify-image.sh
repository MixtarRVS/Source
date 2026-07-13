#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
usage:
  mixtar-verify-image.sh verify-ext4 <image-file> [root-label] [kernel-release] [first-user]

Verifies a Mixtar ext4 image without touching physical disks. It prefers
debugfs. If debugfs is unavailable, it falls back to a temporary read-only loop
mount.
EOF
}

die() {
  printf '%s\n' "error: $*" >&2
  exit 1
}

root_cmd() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    command -v sudo >/dev/null 2>&1 || die "sudo is required for this step"
    sudo "$@"
  fi
}

ok() {
  printf '%s\n' "ok: $*"
}

fail() {
  printf '%s\n' "FAIL: $*" >&2
  failures=$((failures + 1))
}

need_tool() {
  command -v "$1" >/dev/null 2>&1 || die "missing required tool: $1"
}

find_tool() {
  if command -v "$1" >/dev/null 2>&1; then
    command -v "$1"
    return 0
  fi

  if [ -x "/usr/sbin/$1" ]; then
    printf '%s\n' "/usr/sbin/$1"
    return 0
  fi

  if [ -x "/sbin/$1" ]; then
    printf '%s\n' "/sbin/$1"
    return 0
  fi

  return 1
}

cleanup() {
  if [ "${mounted:-0}" = "1" ]; then
    sudo umount "$mount_dir" >/dev/null 2>&1 || true
  fi
  if [ -n "${mount_dir:-}" ]; then
    rmdir "$mount_dir" >/dev/null 2>&1 || true
  fi
}

stat_text() {
  if [ "$backend" = "debugfs" ]; then
    "$debugfs_tool" -R "stat $1" "$image_path" 2>/dev/null || true
    return
  fi

  mounted_path="$mount_dir$1"
  if root_cmd test -e "$mounted_path" || root_cmd test -L "$mounted_path"; then
    printf '%s\n' "Inode: mounted"
  fi
}

cat_text() {
  if [ "$backend" = "debugfs" ]; then
    "$debugfs_tool" -R "cat $1" "$image_path" 2>/dev/null || true
    return
  fi

  root_cmd cat "$mount_dir$1" 2>/dev/null || true
}

read_label() {
  if command -v tune2fs >/dev/null 2>&1; then
    tune2fs -l "$image_path" 2>/dev/null | awk -F: '/Filesystem volume name/ {gsub(/^[ \t]+/, "", $2); print $2; exit}'
    return
  fi

  if command -v blkid >/dev/null 2>&1; then
    blkid -p -s LABEL -o value "$image_path" 2>/dev/null || true
    return
  fi

  if command -v dd >/dev/null 2>&1 && command -v tr >/dev/null 2>&1; then
    # ext2/3/4 superblock starts at byte 1024. s_volume_name is 16 bytes at
    # offset 120 inside the superblock.
    dd if="$image_path" bs=1 skip=1144 count=16 2>/dev/null | tr -d '\000'
    return
  fi

  printf '%s\n' ""
}

must_exist() {
  path="$1"
  label="$2"
  text=$(stat_text "$path")
  if printf '%s\n' "$text" | grep -q '^Inode:'; then
    ok "$label"
  else
    fail "$label missing ($path)"
  fi
}

must_contain_fixed() {
  path="$1"
  needle="$2"
  label="$3"
  if cat_text "$path" | grep -Fq "$needle"; then
    ok "$label"
  else
    fail "$label missing '$needle' in $path"
  fi
}

must_match() {
  path="$1"
  pattern="$2"
  label="$3"
  if cat_text "$path" | grep -Eq "$pattern"; then
    ok "$label"
  else
    fail "$label pattern not found in $path"
  fi
}

command_name="${1:-help}"
image_path="${2:-}"
root_label="${3:-MIXTARROOT}"
kernel_release="${4:-$(uname -r)}"
first_user="${5:-}"

case "$command_name" in
  verify-ext4|help) ;;
  *) usage; die "unknown command: $command_name" ;;
esac

if [ "$command_name" = "help" ]; then
  usage
  exit 0
fi

[ -n "$image_path" ] || die "missing image-file"
[ -f "$image_path" ] || die "missing image-file: $image_path"

case "$first_user" in
  *[!A-Za-z0-9_.-]*)
    die "first-user contains unsupported characters for verifier: $first_user"
    ;;
esac

backend="debugfs"
mounted=0
mount_dir=""

debugfs_tool=$(find_tool debugfs || true)
if [ -n "$debugfs_tool" ]; then
  if ! "$debugfs_tool" -R "stat /" "$image_path" 2>/dev/null | grep -q '^Inode:'; then
    debugfs_tool=""
  fi
fi

if [ -z "$debugfs_tool" ]; then
  backend="mount"
  need_tool sudo
  need_tool mount
  need_tool mktemp
  mount_dir=$(mktemp -d)
  trap cleanup EXIT INT TERM
  root_cmd mount -o loop,ro "$image_path" "$mount_dir" || die "failed to read-only mount image: $image_path"
  mounted=1
fi

failures=0

actual_label=$(read_label)
if [ "$actual_label" = "$root_label" ]; then
  ok "filesystem label is $root_label"
else
  fail "filesystem label is '$actual_label', expected '$root_label'"
fi

must_exist /etc/mixtar-release "Mixtar release marker"
must_exist /etc/alpine-release "Alpine release marker"
must_exist /sbin/apk "apk package manager"
must_exist /lib/ld-musl-x86_64.so.1 "musl dynamic linker"
must_exist /sbin/openrc "OpenRC binary"
must_exist /bin/zsh "zsh binary"
must_exist /usr/sbin/sshd "OpenSSH server binary"
must_exist /sbin/init "init entrypoint"
must_exist /etc/init.d/sshd "OpenSSH OpenRC service"
must_exist /etc/runlevels/default/sshd "OpenSSH default runlevel"
must_exist /etc/init.d/iwd "iwd OpenRC service"
must_exist /etc/runlevels/default/iwd "iwd default runlevel"
must_exist /etc/init.d/dhcpcd "dhcpcd OpenRC service"
must_exist /etc/runlevels/default/dhcpcd "dhcpcd default runlevel"
must_exist /etc/init.d/mixtar-firstboot-report "Mixtar first-boot OpenRC service"
must_exist /etc/runlevels/default/mixtar-firstboot-report "Mixtar first-boot OpenRC default runlevel"

must_exist /System "Mixtar /System"
must_exist /System/Current "Mixtar active generation link"
must_exist /System/Generations "Mixtar generations directory"
must_exist /System/Kernel "Mixtar /System/Kernel"
must_exist /System/Runtime "Mixtar /System/Runtime"
must_exist /System/Runtime/generation.env "Mixtar generation runtime contract"
must_exist /System/Tools "Mixtar /System/Tools"
must_exist /System/SystemTools "Mixtar /System/SystemTools"
must_exist /System/Shells "Mixtar /System/Shells"
must_exist /System/Shells/zsh "Mixtar zsh shell path"
must_exist /System/Tools/mixtar-postboot-report "Mixtar post-boot report tool"
must_exist /System/Tools/mixtar-firstboot-verify "Mixtar first-boot verifier"
must_exist /System/Tools/mixtar-generation-report "Mixtar generation report tool"
must_exist /Applications "Mixtar /Applications"
must_exist /Programs "Mixtar /Programs"
must_exist /Users "Mixtar /Users"

must_exist /Compatibility "Compatibility root"
must_exist /Compatibility/Alpine "Compatibility Alpine"
must_exist /Compatibility/Chimera "Compatibility Chimera"
must_exist /Compatibility/Debian "Compatibility Debian"
must_exist /Compatibility/FreeBSD "Compatibility FreeBSD"
must_exist /Compatibility/OpenBSD "Compatibility OpenBSD"
must_exist /Compatibility/Void "Compatibility Void"

must_exist "/lib/modules/$kernel_release" "kernel module tree for $kernel_release"
must_exist "/boot/vmlinuz-$kernel_release" "boot kernel for $kernel_release"
must_exist "/boot/initrd.img-$kernel_release" "boot initrd for $kernel_release"

must_contain_fixed /etc/fstab "LABEL=$root_label" "fstab root label"
must_contain_fixed /etc/shells "/System/Shells/zsh" "zsh listed as valid shell"
must_contain_fixed /etc/inittab "openrc sysinit" "OpenRC sysinit wiring"
must_contain_fixed /etc/inittab "openrc boot" "OpenRC boot wiring"
must_contain_fixed /etc/inittab "openrc default" "OpenRC default wiring"

if [ -n "$first_user" ]; then
  must_match /etc/passwd "^$first_user:.*:/Users/$first_user:/System/Shells/zsh$" "first user $first_user uses Mixtar zsh"
  must_exist "/Users/$first_user/.ssh/authorized_keys" "first user $first_user authorized SSH keys"
else
  must_match /etc/passwd '^root:.*:/System/Shells/zsh$' "root rescue shell uses Mixtar zsh"
fi

must_exist /etc/iwd/main.conf "iwd network configuration"
must_exist /etc/ssh/sshd_config "OpenSSH server configuration"

if [ "$failures" -eq 0 ]; then
  printf '%s\n' "image-verify: ok"
  exit 0
fi

printf '%s\n' "image-verify: failed checks=$failures" >&2
exit 1
