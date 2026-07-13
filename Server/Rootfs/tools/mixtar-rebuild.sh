#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
usage:
  mixtar-rebuild.sh build [manifest]
  mixtar-rebuild.sh status [manifest]
  mixtar-rebuild.sh readiness-report [manifest]
  mixtar-rebuild.sh operator-runbook [manifest]
  mixtar-rebuild.sh preflight [manifest]
  mixtar-rebuild.sh install-plan [manifest]
  mixtar-rebuild.sh image-plan [manifest]
  mixtar-rebuild.sh install-image [manifest] --erase-image
  mixtar-rebuild.sh login-plan [manifest]
  mixtar-rebuild.sh set-login [manifest] <first-user> --hash-stdin
  mixtar-rebuild.sh image-verify [manifest]
  mixtar-rebuild.sh qemu-plan [manifest]
  mixtar-rebuild.sh qemu-rescue-smoke [manifest]
  mixtar-rebuild.sh qemu-init-smoke [manifest]
  mixtar-rebuild.sh preinstall-gate [manifest]
  mixtar-rebuild.sh install-rootfs [manifest] --erase-device
  mixtar-rebuild.sh grub-plan [manifest]
  mixtar-rebuild.sh grub-install [manifest] --write-grub
  mixtar-rebuild.sh grub-rollback-plan [manifest]
  mixtar-rebuild.sh physical-plan [manifest]
  mixtar-rebuild.sh physical-install [manifest] --erase-device --write-grub
  mixtar-rebuild.sh approval-pack [manifest]
  mixtar-rebuild.sh install-ready-pack [manifest]

Pre-v0 Mixtar system builder wrapper. It coordinates rootfs build, preflight,
install planning, and GRUB planning without Nix.
EOF
}

die() {
  printf '%s\n' "error: $*" >&2
  exit 1
}

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
default_manifest="$script_dir/../manifests/t480-pre-v0.mixtar.conf"

command_name="${1:-help}"
manifest_path="${2:-$default_manifest}"
guard_flag="${3:-}"
extra_arg="${4:-}"

case "$command_name" in
  build|status|readiness-report|operator-runbook|preflight|install-plan|image-plan|install-image|login-plan|set-login|image-verify|qemu-plan|qemu-rescue-smoke|qemu-init-smoke|preinstall-gate|install-rootfs|grub-plan|grub-install|grub-rollback-plan|physical-plan|physical-install|approval-pack|install-ready-pack|help) ;;
  *) usage; die "unknown command: $command_name" ;;
esac

if [ "$command_name" = "help" ]; then
  usage
  exit 0
fi

case "$manifest_path" in
  /*) ;;
  *)
    manifest_dir=$(dirname -- "$manifest_path")
    manifest_base=$(basename -- "$manifest_path")
    if [ -d "$manifest_dir" ]; then
      manifest_path="$(CDPATH= cd -- "$manifest_dir" && pwd)/$manifest_base"
    fi
    ;;
esac

[ -f "$manifest_path" ] || die "missing manifest: $manifest_path"

# shellcheck disable=SC1090
. "$manifest_path"

build_dir="${MIXTAR_BUILD_DIR:-}"
image_path="${MIXTAR_IMAGE_PATH:-}"
image_size="${MIXTAR_IMAGE_SIZE:-512M}"
target_device="${MIXTAR_TARGET_DEVICE:-}"
root_label="${MIXTAR_ROOT_LABEL:-MIXTARROOT}"
kernel_release="${MIXTAR_KERNEL_RELEASE:-$(uname -r)}"
first_user="${MIXTAR_FIRST_USER:-}"
first_password_hash="${MIXTAR_FIRST_PASSWORD_HASH:-}"

export MIXTAR_EXPECTED_HOSTNAME="${MIXTAR_EXPECTED_HOSTNAME:-}"
export MIXTAR_EXPECTED_SYS_VENDOR="${MIXTAR_EXPECTED_SYS_VENDOR:-}"
export MIXTAR_EXPECTED_PRODUCT_NAME="${MIXTAR_EXPECTED_PRODUCT_NAME:-}"
export MIXTAR_EXPECTED_PRODUCT_VERSION="${MIXTAR_EXPECTED_PRODUCT_VERSION:-}"
export MIXTAR_EXPECTED_CHASSIS_TYPE="${MIXTAR_EXPECTED_CHASSIS_TYPE:-}"
export MIXTAR_EXPECTED_TARGET_DEVICE="${MIXTAR_EXPECTED_TARGET_DEVICE:-}"

[ -n "$build_dir" ] || die "MIXTAR_BUILD_DIR is required"
[ -n "$target_device" ] || die "MIXTAR_TARGET_DEVICE is required"

bootstrap_tool="$script_dir/mixtar-bootstrap-rootfs.sh"
install_tool="$script_dir/mixtar-install-rootfs.sh"
grub_tool="$script_dir/mixtar-plan-grub-entry.sh"
qemu_tool="$script_dir/mixtar-qemu-smoke.sh"
verify_tool="$script_dir/mixtar-verify-image.sh"
set_login_tool="$script_dir/mixtar-set-login.sh"
physical_tool="$script_dir/mixtar-physical-install.sh"
approval_pack_tool="$script_dir/mixtar-install-approval-pack.sh"
install_ready_pack_tool="$script_dir/mixtar-install-ready-pack.sh"

[ -f "$bootstrap_tool" ] || die "missing tool: $bootstrap_tool"
[ -f "$install_tool" ] || die "missing tool: $install_tool"
[ -f "$grub_tool" ] || die "missing tool: $grub_tool"
[ -f "$qemu_tool" ] || die "missing tool: $qemu_tool"
[ -f "$verify_tool" ] || die "missing tool: $verify_tool"
[ -f "$set_login_tool" ] || die "missing tool: $set_login_tool"
[ -f "$physical_tool" ] || die "missing tool: $physical_tool"
[ -f "$approval_pack_tool" ] || die "missing tool: $approval_pack_tool"
[ -f "$install_ready_pack_tool" ] || die "missing tool: $install_ready_pack_tool"

print_summary() {
  printf '%s\n' "Mixtar rebuild summary"
  printf '%s\n' "system=${MIXTAR_SYSTEM_NAME:-unknown}"
  printf '%s\n' "build_dir=$build_dir"
  printf '%s\n' "image_path=${image_path:-absent}"
  printf '%s\n' "image_size=$image_size"
  printf '%s\n' "target_device=$target_device"
  printf '%s\n' "root_label=$root_label"
  printf '%s\n' "kernel_release=$kernel_release"
  printf '%s\n' "substrate=${MIXTAR_SUBSTRATE:-unknown}"
  printf '%s\n' "libc=${MIXTAR_LIBC:-unknown}"
  printf '%s\n' "package_backend=${MIXTAR_PACKAGE_BACKEND:-unknown}"
  printf '%s\n' "init=${MIXTAR_INIT:-unknown}"
  printf '%s\n' "user_shell=${MIXTAR_USER_SHELL:-unknown}"
  printf '%s\n' "layout_mode=${MIXTAR_LAYOUT_MODE:-unknown}"
  printf '%s\n' "first_user=${first_user:-absent}"
  printf '%s\n' "expected_hostname=${MIXTAR_EXPECTED_HOSTNAME:-absent}"
  printf '%s\n' "expected_product=${MIXTAR_EXPECTED_PRODUCT_VERSION:-absent}"
}

case "$command_name" in
  status)
    print_summary
    if [ -f "$build_dir/generations/0002-alpine-openrc/manifest.json" ]; then
      printf '\n%s\n' "generation manifest:"
      sed -n '1,120p' "$build_dir/generations/0002-alpine-openrc/manifest.json"
    fi
    if [ -f "$build_dir/images/mixtar-0002-alpine-openrc-rootfs.squashfs" ]; then
      printf '\n%s\n' "image:"
      ls -lh "$build_dir/images/mixtar-0002-alpine-openrc-rootfs.squashfs"
    fi
    ;;
  readiness-report)
    print_summary
    printf '\n%s\n' "Readiness state"
    if [ -f "$image_path" ]; then
      printf '%s\n' "image_artifact=present"
    else
      printf '%s\n' "image_artifact=missing"
    fi
    if [ -z "$first_user" ]; then
      printf '%s\n' "login_state=rescue-first-no-user"
    elif [ -z "$first_password_hash" ]; then
      printf '%s\n' "login_state=user-present-password-locked"
    else
      printf '%s\n' "login_state=login-ready"
    fi
  printf '%s\n' "physical_install=not-approved-by-tool"
  printf '%s\n' "install_approval=missing"
    printf '\n%s\n' "Next safe commands"
    printf '%s\n' "  sh $0 login-plan '$manifest_path'"
    printf '%s\n' "  sh $0 image-plan '$manifest_path'"
    printf '%s\n' "  sh $0 install-image '$manifest_path' --erase-image"
    printf '%s\n' "  sh $0 preinstall-gate '$manifest_path'"
    printf '%s\n' "  sh $0 physical-plan '$manifest_path'"
    printf '%s\n' "  sh $0 grub-rollback-plan '$manifest_path'"
  printf '\n%s\n' "Destructive command requires explicit approval and exact phrase"
  printf '%s\n' "Image-ready and preinstall-gate-ok are technical evidence only; they are not install approval."
  printf '%s\n' "  sh $0 physical-install '$manifest_path' --erase-device --write-grub"
    printf '%s\n' "  phrase: FORMAT $target_device AS $root_label"
    ;;
  operator-runbook)
    printf '%s\n' "# MixtarRVS pre-v0 operator runbook"
    printf '%s\n' ""
    printf '%s\n' "Manifest:"
    printf '%s\n' ""
    printf '%s\n' '```text'
    printf '%s\n' "$manifest_path"
    printf '%s\n' '```'
    printf '%s\n' ""
    printf '%s\n' "Target:"
    printf '%s\n' ""
    printf '%s\n' '```text'
    printf '%s\n' "device=$target_device"
    printf '%s\n' "label=$root_label"
    printf '%s\n' "kernel=$kernel_release"
    printf '%s\n' "image=${image_path:-absent}"
    printf '%s\n' "first_user=${first_user:-absent}"
    if [ -z "$first_password_hash" ]; then
      printf '%s\n' "login_state=user-present-password-locked"
    else
      printf '%s\n' "login_state=login-ready"
    fi
    printf '%s\n' '```'
    printf '%s\n' ""
    printf '%s\n' "Safe sequence:"
    printf '%s\n' ""
    printf '%s\n' '```sh'
    printf '%s\n' "sh $0 readiness-report '$manifest_path'"
    printf '%s\n' "sh $0 login-plan '$manifest_path'"
    printf '%s\n' "sh $0 image-plan '$manifest_path'"
    printf '%s\n' "sh $0 install-image '$manifest_path' --erase-image"
    printf '%s\n' "sh $0 preinstall-gate '$manifest_path'"
    printf '%s\n' "sh $0 approval-pack '$manifest_path'"
    printf '%s\n' "sh $0 physical-plan '$manifest_path'"
    printf '%s\n' "sh $0 grub-rollback-plan '$manifest_path'"
    printf '%s\n' '```'
    printf '%s\n' ""
    printf '%s\n' "Optional login-ready setup:"
    printf '%s\n' ""
    printf '%s\n' '```sh'
    printf '%s\n' "sh $script_dir/mixtar-password-hash.sh | sh $0 set-login '$manifest_path' '${first_user:-vxz}' --hash-stdin"
    printf '%s\n' "sh $0 build '$manifest_path'"
    printf '%s\n' "sh $0 install-image '$manifest_path' --erase-image"
    printf '%s\n' "sh $0 preinstall-gate '$manifest_path'"
    printf '%s\n' '```'
    printf '%s\n' ""
  printf '%s\n' "Destructive install, only after explicit approval:"
  printf '%s\n' "Image-ready and preinstall-gate-ok are technical evidence only; they are not install approval."
    printf '%s\n' ""
    printf '%s\n' '```sh'
    printf '%s\n' "sh $0 physical-install '$manifest_path' --erase-device --write-grub"
    printf '%s\n' '```'
    printf '%s\n' ""
    printf '%s\n' "Required phrase:"
    printf '%s\n' ""
    printf '%s\n' '```text'
    printf '%s\n' "FORMAT $target_device AS $root_label"
    printf '%s\n' '```'
    ;;
  build)
    print_summary
    printf '\n%s\n' "building rootfs..."
    MIXTAR_FIRST_USER="$first_user" \
    MIXTAR_FIRST_PASSWORD_HASH="$first_password_hash" \
      sh "$bootstrap_tool" build-alpine "$build_dir"
    ;;
  preflight)
    sh "$install_tool" preflight "$build_dir" "$target_device" "$root_label" "$kernel_release"
    ;;
  install-plan)
    sh "$install_tool" plan "$build_dir" "$target_device" "$root_label" "$kernel_release"
    ;;
  image-plan)
    [ -n "$image_path" ] || die "MIXTAR_IMAGE_PATH is required"
    sh "$install_tool" image-plan "$build_dir" "$image_path" "$image_size" "$root_label" "$kernel_release"
    ;;
  install-image)
    [ "$guard_flag" = "--erase-image" ] || die "install-image requires explicit --erase-image"
    [ -n "$image_path" ] || die "MIXTAR_IMAGE_PATH is required"
    sh "$install_tool" install-ext4-image "$build_dir" "$image_path" "$image_size" "$root_label" "$kernel_release" --erase-image
    ;;
  login-plan)
    printf '%s\n' "Mixtar login plan"
    printf '%s\n' "first_user=${first_user:-absent}"
    if [ -z "$first_user" ]; then
      printf '%s\n' "state=rescue-first"
      printf '%s\n' "Set MIXTAR_FIRST_USER=\"vxz\" in the manifest to create the normal user."
    elif [ -z "$first_password_hash" ]; then
      printf '%s\n' "state=user-present-password-locked"
      printf '%s\n' "The user will exist with /Users/$first_user and /System/Shells/zsh, but normal password login is not ready."
      printf '%s\n' ""
      printf '%s\n' "To make the image login-ready:"
      printf '%s\n' "1. Preferred helper:"
      printf '%s\n' "   sh $script_dir/mixtar-t480-firstboot.sh setup-login --manifest='$manifest_path' --first-user='$first_user'"
      printf '%s\n' "2. Or pipe the resulting SHA-512 crypt hash into:"
      printf '%s\n' "   sh $script_dir/mixtar-password-hash.sh | sh $0 set-login '$manifest_path' '$first_user' --hash-stdin"
      printf '%s\n' "3. Rebuild:"
      printf '%s\n' "   sh $0 build '$manifest_path'"
      printf '%s\n' "   sh $0 install-image '$manifest_path' --erase-image"
      printf '%s\n' "   sh $0 preinstall-gate '$manifest_path'"
    else
      printf '%s\n' "state=login-ready"
      printf '%s\n' "Normal login should be available for $first_user with /System/Shells/zsh."
    fi
    ;;
  set-login)
    [ -n "$guard_flag" ] || die "set-login requires first-user"
    [ "$extra_arg" = "--hash-stdin" ] || die "set-login requires --hash-stdin"
    sh "$set_login_tool" "$manifest_path" "$guard_flag" --hash-stdin
    ;;
  image-verify)
    [ -n "$image_path" ] || die "MIXTAR_IMAGE_PATH is required"
    sh "$verify_tool" verify-ext4 "$image_path" "$root_label" "$kernel_release" "$first_user"
    ;;
  qemu-plan)
    [ -n "$image_path" ] || die "MIXTAR_IMAGE_PATH is required"
    sh "$qemu_tool" plan "$image_path" "$kernel_release" "$root_label"
    ;;
  qemu-rescue-smoke)
    [ -n "$image_path" ] || die "MIXTAR_IMAGE_PATH is required"
    sh "$qemu_tool" rescue-image-smoke "$image_path" "$kernel_release" "$root_label"
    ;;
  qemu-init-smoke)
    [ -n "$image_path" ] || die "MIXTAR_IMAGE_PATH is required"
    sh "$qemu_tool" init-image-smoke "$image_path" "$kernel_release" "$root_label"
    ;;
  preinstall-gate)
    [ -n "$image_path" ] || die "MIXTAR_IMAGE_PATH is required"
    printf '%s\n' "[1/6] preflight"
    sh "$install_tool" preflight "$build_dir" "$target_device" "$root_label" "$kernel_release"
    printf '\n%s\n' "[2/6] image contract"
    sh "$verify_tool" verify-ext4 "$image_path" "$root_label" "$kernel_release" "$first_user"
  printf '\n%s\n' "[3/6] QEMU rescue smoke"
    sh "$qemu_tool" rescue-image-smoke "$image_path" "$kernel_release" "$root_label"
    printf '\n%s\n' "[4/6] QEMU init/OpenRC smoke"
    sh "$qemu_tool" init-image-smoke "$image_path" "$kernel_release" "$root_label"
    printf '\n%s\n' "[5/6] install plan"
    sh "$install_tool" plan "$build_dir" "$target_device" "$root_label" "$kernel_release"
    printf '\n%s\n' "[6/6] GRUB plan"
    sh "$grub_tool" plan "$root_label" "$kernel_release"
    printf '\n%s\n' "preinstall-gate: ok"
    printf '%s\n' "Destructive install still requires explicit commands:"
    printf '%s\n' "  sh $0 install-rootfs '$manifest_path' --erase-device"
    printf '%s\n' "  sh $0 grub-install '$manifest_path' --write-grub"
    ;;
  install-rootfs)
    [ "$guard_flag" = "--erase-device" ] || die "install-rootfs requires explicit --erase-device"
    sh "$install_tool" install-ext4-rootfs "$build_dir" "$target_device" "$root_label" "$kernel_release" --erase-device
    ;;
  grub-plan)
    sh "$grub_tool" plan "$root_label" "$kernel_release"
    ;;
  grub-install)
    [ "$guard_flag" = "--write-grub" ] || die "grub-install requires explicit --write-grub"
    sh "$grub_tool" install "$root_label" "$kernel_release" --write-grub
    ;;
  grub-rollback-plan)
    printf '%s\n' "Mixtar GRUB rollback plan"
    printf '%s\n' ""
    printf '%s\n' "This is a plan only. It does not modify /etc/grub.d/40_custom."
    printf '%s\n' "It removes only the marked Mixtar block:"
    printf '%s\n' "  # BEGIN MIXTARRVS PRE-V0"
    printf '%s\n' "  # END MIXTARRVS PRE-V0"
    printf '%s\n' ""
    printf '%s\n' "Manual rollback commands, if Mixtar GRUB entry must be removed:"
    printf '%s\n' '```sh'
    printf '%s\n' "sudo cp /etc/grub.d/40_custom /etc/grub.d/40_custom.before-mixtar-rollback"
    printf '%s\n' "sudo awk '"
    printf '%s\n' '  $0 == "# BEGIN MIXTARRVS PRE-V0" { skip = 1; next }'
    printf '%s\n' '  $0 == "# END MIXTARRVS PRE-V0" { skip = 0; next }'
    printf '%s\n' '  skip != 1 { print }'
    printf '%s\n' "' /etc/grub.d/40_custom | sudo tee /etc/grub.d/40_custom.mixtar-rollback >/dev/null"
    printf '%s\n' "sudo cp /etc/grub.d/40_custom.mixtar-rollback /etc/grub.d/40_custom"
    printf '%s\n' "sudo chmod 755 /etc/grub.d/40_custom"
    printf '%s\n' "sudo update-grub"
    printf '%s\n' '```'
    ;;
  physical-plan)
    sh "$physical_tool" plan "$manifest_path"
    ;;
  physical-install)
    [ "$guard_flag" = "--erase-device" ] || die "physical-install requires explicit --erase-device"
    [ "$extra_arg" = "--write-grub" ] || die "physical-install requires explicit --write-grub"
    sh "$physical_tool" install "$manifest_path" --erase-device --write-grub
    ;;
  approval-pack)
    sh "$approval_pack_tool" "$manifest_path"
    ;;
  install-ready-pack)
    sh "$install_ready_pack_tool" "$manifest_path"
    ;;
esac
