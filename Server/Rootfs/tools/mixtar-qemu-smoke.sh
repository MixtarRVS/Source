#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
usage:
  mixtar-qemu-smoke.sh plan <image-file> [kernel-release] [root-label]
  mixtar-qemu-smoke.sh rescue-image-smoke <image-file> [kernel-release] [root-label]
  mixtar-qemu-smoke.sh init-image-smoke <image-file> [kernel-release] [root-label]

Boots a Mixtar ext4 image in QEMU without touching physical disks.

rescue-image-smoke uses init=/bin/sh and proves the rootfs is reachable.
init-image-smoke uses the image's normal /sbin/init path and proves the boot
gets far enough to start BusyBox/OpenRC userspace.
EOF
}

die() {
  printf '%s\n' "error: $*" >&2
  exit 1
}

command_name="${1:-help}"
image_path="${2:-}"
kernel_release="${3:-$(uname -r)}"
root_label="${4:-MIXTARROOT}"

case "$command_name" in
  plan|rescue-image-smoke|init-image-smoke|help) ;;
  *) usage; die "unknown command: $command_name" ;;
esac

if [ "$command_name" = "help" ]; then
  usage
  exit 0
fi

[ -n "$image_path" ] || die "missing image-file"
[ -f "$image_path" ] || die "missing image-file: $image_path"

qemu=$(command -v qemu-system-x86_64 || true)
[ -n "$qemu" ] || die "missing required tool: qemu-system-x86_64"

kernel="/boot/vmlinuz-$kernel_release"
initrd="/boot/initrd.img-$kernel_release"

[ -f "$kernel" ] || die "missing kernel: $kernel"
[ -f "$initrd" ] || die "missing initrd: $initrd"

log_dir="$(dirname "$image_path")/qemu-smoke"
case "$command_name" in
  init-image-smoke)
    log_file="$log_dir/init-image-smoke.log"
    append_args="console=ttyS0 root=LABEL=$root_label ro rootwait panic=-1"
    smoke_name="init-image-smoke"
    ;;
  *)
    log_file="$log_dir/rescue-image-smoke.log"
    append_args="console=ttyS0 root=LABEL=$root_label ro rootwait init=/bin/sh panic=-1"
    smoke_name="rescue-image-smoke"
    ;;
esac
mkdir -p "$log_dir"
drive_if="${MIXTAR_QEMU_DRIVE_IF:-nvme}"

kvm_args=""
if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
  kvm_args="-enable-kvm -cpu host"
fi

print_plan() {
  printf '%s\n' "Mixtar QEMU smoke plan"
  printf '%s\n' ""
  printf '%s\n' "Mode:   $smoke_name"
  printf '%s\n' "Image:  $image_path"
  printf '%s\n' "Label:  $root_label"
  printf '%s\n' "Kernel: $kernel"
  printf '%s\n' "Initrd: $initrd"
  printf '%s\n' "Log:    $log_file"
  printf '%s\n' "Drive:  if=$drive_if"
  printf '%s\n' ""
  printf '%s\n' "Command:"
  case "$drive_if" in
    nvme)
      printf '%s\n' "$qemu $kvm_args -snapshot -m 1024 -nographic -no-reboot -kernel '$kernel' -initrd '$initrd' -append '$append_args' -drive file='$image_path',format=raw,if=none,id=mixtarroot -device nvme,drive=mixtarroot,serial=mixtarroot"
      ;;
    *)
      printf '%s\n' "$qemu $kvm_args -snapshot -m 1024 -nographic -no-reboot -kernel '$kernel' -initrd '$initrd' -append '$append_args' -drive file='$image_path',format=raw,if=$drive_if"
      ;;
  esac
}

if [ "$command_name" = "plan" ]; then
  print_plan
  exit 0
fi

rm -f "$log_file"

set +e
case "$drive_if" in
  nvme)
    timeout 45s "$qemu" $kvm_args \
      -snapshot \
      -m 1024 \
      -nographic \
      -no-reboot \
      -kernel "$kernel" \
      -initrd "$initrd" \
      -append "$append_args" \
      -drive "file=$image_path,format=raw,if=none,id=mixtarroot" \
      -device "nvme,drive=mixtarroot,serial=mixtarroot" \
      >"$log_file" 2>&1
    rc=$?
    ;;
  *)
    timeout 45s "$qemu" $kvm_args \
      -snapshot \
      -m 1024 \
      -nographic \
      -no-reboot \
      -kernel "$kernel" \
      -initrd "$initrd" \
      -append "$append_args" \
      -drive "file=$image_path,format=raw,if=$drive_if" \
      >"$log_file" 2>&1
    rc=$?
    ;;
esac
set -e

printf '%s\n' "qemu rc=$rc"
printf '%s\n' "log=$log_file"

if grep -Eq 'Run /bin/sh as init process|sh: can.t access tty|/ #' "$log_file"; then
  printf '%s\n' "rescue-image-smoke: ok"
  exit 0
fi

if [ "$command_name" = "init-image-smoke" ]; then
  if grep -Eq 'init started: BusyBox|Welcome to Alpine Linux|Caching service dependencies|OpenRC|login:' "$log_file"; then
    printf '%s\n' "init-image-smoke: ok"
    exit 0
  fi
fi

printf '%s\n' "$smoke_name: not proven"
printf '%s\n' "--- log tail ---"
tail -80 "$log_file" || true
exit 1
