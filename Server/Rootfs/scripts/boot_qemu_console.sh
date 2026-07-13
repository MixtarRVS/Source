#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "boot-console: starting QEMU serial console"
echo "boot-console: use Ctrl-A then X to exit QEMU"

exec bash "$script_dir/boot_qemu.sh" "$@"
