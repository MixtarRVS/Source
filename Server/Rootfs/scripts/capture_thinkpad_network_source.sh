#!/usr/bin/env bash
set -euo pipefail

archive="${1:-/tmp/mixtar-wifi-source.tar.gz}"
paths=()

add_path() {
  local p="$1"
  if [[ -e "$p" ]]; then
    paths+=("$p")
  fi
}

add_binary_with_runtime() {
  local bin="$1"
  if [[ -z "$bin" || ! -x "$bin" ]]; then
    return 0
  fi
  add_path "$bin"
  while read -r lib; do
    [[ -n "$lib" && -e "$lib" ]] && paths+=("$lib")
  done < <(ldd "$bin" 2>/dev/null | awk '/^[[:space:]]*\// { print $1; next } /=>[[:space:]]*\// { print $3; next }')
}

iwd_bin=""
for candidate in /usr/libexec/iwd /usr/lib/iwd/iwd "$(command -v iwd 2>/dev/null || true)"; do
  if [[ -x "$candidate" ]]; then
    iwd_bin="$candidate"
    break
  fi
done

dbus_bin="$(command -v dbus-daemon 2>/dev/null || true)"
modprobe_bin="$(command -v modprobe 2>/dev/null || true)"
if [[ -z "$modprobe_bin" && -x /usr/sbin/modprobe ]]; then
  modprobe_bin=/usr/sbin/modprobe
fi

add_binary_with_runtime "$iwd_bin"
add_binary_with_runtime "$dbus_bin"
add_binary_with_runtime "$modprobe_bin"

for loader in /lib64/ld-linux-x86-64.so.2 /lib/x86_64-linux-gnu/ld-linux-x86-64.so.2; do
  add_path "$loader"
done

for fw in /lib/firmware/iwlwifi-8265-*.ucode; do
  add_path "$fw"
done

add_path /etc/iwd
add_path /var/lib/iwd
add_path /etc/modprobe.d

module_dirs=()
for d in /lib/modules/*mixtar* /lib/modules/"$(uname -r)"; do
  [[ -d "$d" ]] && module_dirs+=("$d")
done
if [[ "${#module_dirs[@]}" -eq 0 ]]; then
  for d in /lib/modules/*; do
    [[ -d "$d" ]] && module_dirs+=("$d")
  done
fi
for d in "${module_dirs[@]}"; do
  add_path "$d"
done

if [[ -z "$iwd_bin" ]]; then
  echo "capture-network: missing iwd binary" >&2
  exit 1
fi
if [[ -z "$dbus_bin" ]]; then
  echo "capture-network: missing dbus-daemon" >&2
  exit 1
fi
if [[ -z "$modprobe_bin" ]]; then
  echo "capture-network: missing modprobe" >&2
  exit 1
fi
if ! compgen -G "/lib/firmware/iwlwifi-8265-*.ucode" >/dev/null; then
  echo "capture-network: missing iwlwifi-8265 firmware" >&2
  exit 1
fi

rm -f "$archive"
rel=()
for p in "${paths[@]}"; do
  [[ -e "$p" ]] && rel+=("${p#/}")
done
tar -C / -czhf "$archive" "${rel[@]}"
chmod 0600 "$archive"
if id vxz >/dev/null 2>&1; then
  chown vxz "$archive" || true
fi

ls -lh "$archive"
printf 'captured=%s\n' "${#rel[@]}"
printf 'iwd=%s\n' "$iwd_bin"
printf 'dbus=%s\n' "$dbus_bin"
printf 'modprobe=%s\n' "$modprobe_bin"
printf 'modules=%s\n' "${module_dirs[*]}"
