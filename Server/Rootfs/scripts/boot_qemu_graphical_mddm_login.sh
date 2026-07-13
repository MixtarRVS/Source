#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"
log_dir="$repo_root/Server/Rootfs/Generated/boot"
log="$log_dir/boot-graphical-mddm-login.log"

mkdir -p "$log_dir"

if [[ -z "${MIXTAR_ADMIN_PASSWORD_HASH_FILE:-}" && -z "${MIXTAR_ADMIN_PASSWORD_HASH:-}" ]]; then
  cat >&2 <<'EOF'
boot-graphical-mddm-login: missing Administrator password hash

Provide one of:
  MIXTAR_ADMIN_PASSWORD_HASH_FILE=/path/to/hash-file
  MIXTAR_ADMIN_PASSWORD_HASH='$6$...'

Local hash helper:
  read -rsp "Administrator password: " pass; echo
  hash="$(printf '%s' "$pass" | openssl passwd -6 -stdin)"
  unset pass
  MIXTAR_ADMIN_PASSWORD_HASH="$hash" bash Server/Rootfs/scripts/boot_qemu_graphical_mddm_login.sh
EOF
  exit 2
fi

MIXTAR_DESKTOP_PROFILE=rich \
MIXTAR_MDDM_AUTH_TEST_MODE=OFF \
  bash "$script_dir/build_graphical_initramfs.sh"

echo "boot-graphical-mddm-login: log=$log" >&2
echo "boot-graphical-mddm-login: connect SPICE with virt-viewer if MIXTAR_QEMU_SPICE=1" >&2

MIXTAR_QEMU_APPEND_EXTRA="mixtar.target=graphical mixtar.dbus=1 mixtar.mddm=1" \
MIXTAR_QEMU_DISPLAY="${MIXTAR_QEMU_DISPLAY:-gtk,gl=off}" \
MIXTAR_QEMU_SPICE="${MIXTAR_QEMU_SPICE:-1}" \
  bash "$script_dir/boot_qemu_graphical.sh" 2>&1 | tee "$log"
