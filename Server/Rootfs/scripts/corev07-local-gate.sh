#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

usage() {
    cat <<EOF
usage: corev07-local-gate.sh [--root PATH] [--efi-stage PATH] [--efi-source PATH]

Runs the local CoreV07 gate only:
  1. plan
  2. stage
  3. verify

This script is not an installer and not a deployment tool.
It does not modify Debian, ESP, EFI variables, boot order, or a live root.
EOF
}

case "${1:-}" in
    -h|--help)
        usage
        exit 0
        ;;
esac

sh "$script_dir/corev07-stage-root.sh" plan "$@"
sh "$script_dir/corev07-stage-root.sh" stage "$@"
sh "$script_dir/corev07-stage-root.sh" verify "$@"
sh "$script_dir/corev07-boot-preflight.sh" "$@"
