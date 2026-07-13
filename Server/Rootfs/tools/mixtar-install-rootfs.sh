#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
usage:
  mixtar-install-rootfs.sh preflight <build-dir> <block-device> [root-label] [kernel-release]
  mixtar-install-rootfs.sh plan <build-dir> <block-device> [root-label] [kernel-release]
  mixtar-install-rootfs.sh image-plan <build-dir> <image-file> [image-size] [root-label] [kernel-release]
  mixtar-install-rootfs.sh install-ext4-rootfs <build-dir> <block-device> [root-label] [kernel-release] --erase-device
  mixtar-install-rootfs.sh install-ext4-image <build-dir> <image-file> [image-size] [root-label] [kernel-release] --erase-image

Installs a built Mixtar rootfs artifact onto a target ext4 partition or ext4
image file. The default workflow is plan-only. Bootloader changes are
intentionally not made by this script.
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

read_dmi_value() {
  name="$1"
  path="/sys/class/dmi/id/$name"
  if [ -r "$path" ]; then
    tr -d '\000' < "$path" 2>/dev/null || true
  fi
}

assert_equals_if_set() {
  label="$1"
  expected="$2"
  actual="$3"
  if [ -n "$expected" ] && [ "$actual" != "$expected" ]; then
    die "target identity mismatch for $label: expected '$expected', got '$actual'"
  fi
}

assert_target_identity() {
  actual_hostname=$(hostname 2>/dev/null || true)
  actual_sys_vendor=$(read_dmi_value sys_vendor)
  actual_product_name=$(read_dmi_value product_name)
  actual_product_version=$(read_dmi_value product_version)
  actual_chassis_type=$(read_dmi_value chassis_type)
  root_source=$(findmnt -no SOURCE / 2>/dev/null || true)

  assert_equals_if_set "hostname" "${MIXTAR_EXPECTED_HOSTNAME:-}" "$actual_hostname"
  assert_equals_if_set "sys_vendor" "${MIXTAR_EXPECTED_SYS_VENDOR:-}" "$actual_sys_vendor"
  assert_equals_if_set "product_name" "${MIXTAR_EXPECTED_PRODUCT_NAME:-}" "$actual_product_name"
  assert_equals_if_set "product_version" "${MIXTAR_EXPECTED_PRODUCT_VERSION:-}" "$actual_product_version"
  assert_equals_if_set "chassis_type" "${MIXTAR_EXPECTED_CHASSIS_TYPE:-}" "$actual_chassis_type"
  assert_equals_if_set "target_device" "${MIXTAR_EXPECTED_TARGET_DEVICE:-}" "$target"

  if [ "$root_source" = "$target" ]; then
    die "target device is current root filesystem: $target"
  fi
}

command_name="${1:-help}"
build_dir="${2:-}"
target="${3:-}"
arg4="${4:-}"
arg5="${5:-}"
arg6="${6:-}"
arg7="${7:-}"

case "$command_name" in
  preflight|plan|image-plan|install-ext4-rootfs|install-ext4-image|help) ;;
  *) usage; die "unknown command: $command_name" ;;
esac

if [ "$command_name" = "help" ]; then
  usage
  exit 0
fi

[ -n "$build_dir" ] || die "missing build-dir"
[ -n "$target" ] || die "missing target"
[ -d "$build_dir/rootfs" ] || die "missing rootfs: $build_dir/rootfs"
[ -f "$build_dir/generations/0002-alpine-openrc/manifest.json" ] || die "missing 0002 manifest"

need_tool findmnt
need_tool tar
mkfs_ext4=$(find_tool mkfs.ext4) || die "missing required tool: mkfs.ext4"

root_label="MIXTARROOT"
kernel_release="$(uname -r)"
image_size="512M"

case "$command_name" in
  preflight)
    root_label="${arg4:-MIXTARROOT}"
    kernel_release="${arg5:-$(uname -r)}"
    ;;
  plan)
    root_label="${arg4:-MIXTARROOT}"
    kernel_release="${arg5:-$(uname -r)}"
    ;;
  image-plan)
    image_size="${arg4:-512M}"
    root_label="${arg5:-MIXTARROOT}"
    kernel_release="${arg6:-$(uname -r)}"
    ;;
  install-ext4-image)
    image_size="${arg4:-512M}"
    if [ "${arg5:-}" = "--erase-image" ]; then
      image_confirm_flag="$arg5"
    elif [ "${arg6:-}" = "--erase-image" ]; then
      kernel_release="${arg5:-$(uname -r)}"
      image_confirm_flag="$arg6"
    else
      root_label="${arg5:-MIXTARROOT}"
      kernel_release="${arg6:-$(uname -r)}"
      image_confirm_flag="${arg7:-}"
    fi
    ;;
  install-ext4-rootfs)
    if [ "${arg4:-}" = "--erase-device" ]; then
      device_confirm_flag="$arg4"
    elif [ "${arg5:-}" = "--erase-device" ]; then
      kernel_release="${arg4:-$(uname -r)}"
      device_confirm_flag="$arg5"
    else
      root_label="${arg4:-MIXTARROOT}"
      kernel_release="${arg5:-$(uname -r)}"
      device_confirm_flag="${arg6:-}"
    fi
    ;;
esac

safe_block_device() {
  assert_target_identity
  device="$1"
  [ -b "$device" ] || die "not a block device: $device"
  if findmnt -rn --source "$device" >/dev/null 2>&1; then
    die "target device is mounted: $device"
  fi
}

safe_image_path() {
  image_path="$1"

  case "$image_path" in
    ""|"/"|"/."|"/.."|"/bin"|"/sbin"|"/usr"|"/etc"|"/lib"|"/home"|"/root"|"/var"|"/tmp")
      die "refusing unsafe image path: $image_path"
      ;;
  esac

  if [ -b "$image_path" ]; then
    die "image target is a block device, use install-ext4-rootfs instead: $image_path"
  fi

  image_parent=$(dirname "$image_path")
  mkdir -p "$image_parent"
  image_parent_abs=$(cd "$image_parent" && pwd)
  image_base=$(basename "$image_path")
  printf '%s/%s\n' "$image_parent_abs" "$image_base"
}

install_rootfs_into_mount() {
  mount_dir="$1"

  root_cmd sh -c "cd '$build_dir/rootfs' && tar -cpf - . | tar -xpf - -C '$mount_dir'"

  [ -d "/lib/modules/$kernel_release" ] || die "missing kernel modules: /lib/modules/$kernel_release"
  [ -f "/boot/vmlinuz-$kernel_release" ] || die "missing kernel: /boot/vmlinuz-$kernel_release"
  [ -f "/boot/initrd.img-$kernel_release" ] || die "missing initrd: /boot/initrd.img-$kernel_release"

  root_cmd mkdir -p "$mount_dir/lib/modules"
  root_cmd sh -c "cd '/lib/modules' && tar -cpf - '$kernel_release' | tar -xpf - -C '$mount_dir/lib/modules'"

  root_cmd mkdir -p "$mount_dir/boot"
  root_cmd cp "/boot/vmlinuz-$kernel_release" "$mount_dir/boot/vmlinuz-$kernel_release"
  root_cmd cp "/boot/initrd.img-$kernel_release" "$mount_dir/boot/initrd.img-$kernel_release"

  root_cmd mkdir -p "$mount_dir/etc"
  root_cmd sh -c "cat > '$mount_dir/etc/fstab' <<EOF
LABEL=$root_label / ext4 defaults 0 1
proc /proc proc defaults 0 0
sysfs /sys sysfs defaults 0 0
devtmpfs /dev devtmpfs defaults 0 0
tmpfs /run tmpfs defaults 0 0
tmpfs /tmp tmpfs defaults 0 0
EOF"
}

preflight() {
  safe_block_device "$target"

  rootfs="$build_dir/rootfs"
  manifest="$build_dir/generations/0002-alpine-openrc/manifest.json"
  kernel="/boot/vmlinuz-$kernel_release"
  initrd="/boot/initrd.img-$kernel_release"
  status="ok"
  login_status="ready"

  printf '%s\n' "Mixtar preflight"
  printf '%s\n' ""
  printf '%s\n' "Build:   $build_dir"
  printf '%s\n' "Rootfs:  $rootfs"
  printf '%s\n' "Target:  $target"
  printf '%s\n' "Label:   $root_label"
  printf '%s\n' "Kernel:  $kernel"
  printf '%s\n' "Initrd:  $initrd"
  printf '%s\n' ""

  [ -f "$manifest" ] || { printf '%s\n' "BLOCKER: missing manifest: $manifest"; status="blocked"; }
  { [ -L "$rootfs/sbin/init" ] || [ -x "$rootfs/sbin/init" ]; } || { printf '%s\n' "BLOCKER: missing /sbin/init in rootfs"; status="blocked"; }
  [ -x "$rootfs/System/Shells/zsh" ] || { printf '%s\n' "BLOCKER: missing executable /System/Shells/zsh in rootfs"; status="blocked"; }
  [ -f "$rootfs/etc/mixtar-release" ] || { printf '%s\n' "BLOCKER: missing /etc/mixtar-release in rootfs"; status="blocked"; }
  [ -f "$kernel" ] || { printf '%s\n' "BLOCKER: missing kernel: $kernel"; status="blocked"; }
  [ -f "$initrd" ] || { printf '%s\n' "BLOCKER: missing initrd: $initrd"; status="blocked"; }

  if [ -f "$rootfs/etc/shadow" ]; then
    root_shadow=$(root_cmd awk -F: '$1 == "root" { print $2 }' "$rootfs/etc/shadow")
    case "$root_shadow" in
      ""|"!"|"*")
        printf '%s\n' "WARN: root login is locked"
        ;;
    esac
  else
    printf '%s\n' "BLOCKER: missing /etc/shadow in rootfs"
    status="blocked"
  fi

  first_user=$(sed -n 's/.*"first_user": "\([^"]*\)".*/\1/p' "$manifest" 2>/dev/null | sed -n '1p')
  if [ -z "$first_user" ] || [ "$first_user" = "absent" ]; then
    printf '%s\n' "WARN: no first user configured"
    login_status="rescue-only"
  elif [ -f "$rootfs/etc/shadow" ]; then
    first_shadow=$(root_cmd awk -F: -v user="$first_user" '$1 == user { print $2 }' "$rootfs/etc/shadow")
    case "$first_shadow" in
      ""|"!"|"*")
        printf '%s\n' "WARN: first user login is locked: $first_user"
        login_status="rescue-only"
        ;;
      *)
        printf '%s\n' "OK: first user appears login-capable: $first_user"
        ;;
    esac
  fi

  printf '%s\n' ""
  printf '%s\n' "Target device:"
  lsblk -f "$target"
  printf '%s\n' ""

  if [ "$status" = "blocked" ]; then
    printf '%s\n' "preflight: blocked"
    exit 1
  fi

  if [ "$login_status" = "rescue-only" ]; then
    printf '%s\n' "preflight: ok-with-rescue"
    printf '%s\n' "normal login is not ready; use the rescue GRUB entry or rebuild with MIXTAR_FIRST_PASSWORD_HASH"
  else
    printf '%s\n' "preflight: ok"
  fi
}

print_plan() {
  safe_block_device "$target"

  printf '%s\n' "Mixtar install plan"
  printf '%s\n' ""
  printf '%s\n' "Build:  $build_dir"
  printf '%s\n' "Rootfs: $build_dir/rootfs"
  printf '%s\n' "Target: $target"
  printf '%s\n' ""
  lsblk -f "$target"
  printf '%s\n' ""
  printf '%s\n' "Planned rootfs install actions:"
  printf '%s\n' "1. format $target as ext4 with label $root_label"
  printf '%s\n' "2. mount it in a temporary directory"
  printf '%s\n' "3. extract $build_dir/rootfs into it"
  printf '%s\n' "4. copy /lib/modules/$kernel_release if available"
  printf '%s\n' "5. copy /boot/vmlinuz-$kernel_release and /boot/initrd.img-$kernel_release"
  printf '%s\n' "6. write /etc/fstab using LABEL=$root_label"
  printf '%s\n' "7. unmount the target"
  printf '%s\n' ""
  printf '%s\n' "Bootloader changes are not performed by this script yet."
}

print_image_plan() {
  image_path=$(safe_image_path "$target")

  printf '%s\n' "Mixtar image install plan"
  printf '%s\n' ""
  printf '%s\n' "Build:  $build_dir"
  printf '%s\n' "Rootfs: $build_dir/rootfs"
  printf '%s\n' "Image:  $image_path"
  printf '%s\n' "Size:   $image_size"
  printf '%s\n' ""
  printf '%s\n' "Planned image actions:"
  printf '%s\n' "1. create or truncate $image_path to $image_size"
  printf '%s\n' "2. format the image as ext4 with label $root_label"
  printf '%s\n' "3. mount it through a loop device"
  printf '%s\n' "4. extract $build_dir/rootfs into it"
  printf '%s\n' "5. copy /lib/modules/$kernel_release if available"
  printf '%s\n' "6. copy /boot/vmlinuz-$kernel_release and /boot/initrd.img-$kernel_release"
  printf '%s\n' "7. write /etc/fstab using LABEL=$root_label"
  printf '%s\n' "8. unmount the image"
}

case "$command_name" in
  preflight)
    preflight
    exit 0
    ;;
  plan)
    print_plan
    exit 0
    ;;
  image-plan)
    print_image_plan
    exit 0
    ;;
  install-ext4-rootfs)
    safe_block_device "$target"
    if [ "${device_confirm_flag:-}" != "--erase-device" ]; then
      print_plan
      die "install requires explicit --erase-device"
    fi
    ;;
  install-ext4-image)
    if [ "${image_confirm_flag:-}" != "--erase-image" ]; then
      print_image_plan
      die "image install requires explicit --erase-image"
    fi
    ;;
esac

if [ "$command_name" = "install-ext4-image" ]; then
  need_tool truncate
  image_path=$(safe_image_path "$target")
  mount_dir=$(mktemp -d "${TMPDIR:-/tmp}/mixtar-image-install.XXXXXX")

  cleanup_image() {
    if findmnt -rn --target "$mount_dir" >/dev/null 2>&1; then
      root_cmd umount "$mount_dir"
    fi
    rmdir "$mount_dir" 2>/dev/null || true
  }

  trap cleanup_image EXIT INT TERM

  truncate -s "$image_size" "$image_path"
  root_cmd "$mkfs_ext4" -F -L "$root_label" "$image_path"
  root_cmd mount -o loop "$image_path" "$mount_dir"
  install_rootfs_into_mount "$mount_dir"
  sync

  printf '%s\n' "installed rootfs into image $image_path"
  exit 0
fi

mount_dir=$(mktemp -d "${TMPDIR:-/tmp}/mixtar-install.XXXXXX")

cleanup_device() {
  if findmnt -rn --target "$mount_dir" >/dev/null 2>&1; then
    root_cmd umount "$mount_dir"
  fi
  rmdir "$mount_dir" 2>/dev/null || true
}

trap cleanup_device EXIT INT TERM

root_cmd "$mkfs_ext4" -F -L "$root_label" "$target"
root_cmd mount "$target" "$mount_dir"
install_rootfs_into_mount "$mount_dir"
sync

printf '%s\n' "installed rootfs to $target"
printf '%s\n' "bootloader entry still needs to be added separately"
