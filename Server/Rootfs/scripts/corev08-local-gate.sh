#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../../.." && pwd)

if [ -z "${MIXTARRVS_COREV07_KERNEL_WORKSPACE:-}" ]; then
    case "$repo_root" in
        /mnt/c/Users/*/source/repos/MixtarRVS)
            windows_user=${repo_root#/mnt/c/Users/}
            windows_user=${windows_user%%/*}
            user_kernel_workspace="/home/$windows_user/.cache/mixtarrvs-corev07/kernel"
            if [ -d "$user_kernel_workspace" ]; then
                export MIXTARRVS_COREV07_KERNEL_WORKSPACE="$user_kernel_workspace"
            fi
            ;;
    esac
fi

usage() {
    cat <<EOF
usage: corev08-local-gate.sh [--root PATH] [--efi-stage PATH] [--efi-source PATH]

Runs the local CoreV08 gate:
  1. CoreV07 plan/stage/verify/preflight pipeline
  2. CoreV08 chroot userland/status gate

This is not an installer and not a deployment tool.
It does not modify Debian, ESP, EFI variables, boot order, or a live root.
EOF
}

case "${1:-}" in
    -h|--help)
        usage
        exit 0
        ;;
esac

sh "$script_dir/corev07-local-gate.sh" "$@"
sh "$script_dir/corev07-chroot-gate.sh" "$@"
