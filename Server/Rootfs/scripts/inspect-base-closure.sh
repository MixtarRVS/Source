#!/bin/sh
set -eu

section() {
  printf '\n## %s\n' "$*"
}

run() {
  printf '\n$ %s\n' "$*"
  "$@" 2>&1 || true
}

have() {
  command -v "$1" >/dev/null 2>&1
}

print_file() {
  path="$1"
  if [ -f "$path" ]; then
    printf '\n### %s\n' "$path"
    sed -n '1,120p' "$path" 2>&1 || true
  fi
}

owner_of() {
  path="$1"
  if have apk; then
    apk info -W "$path" 2>/dev/null || true
  fi
}

runtime_file_report() {
  path="$1"
  printf '\n### %s\n' "$path"
  if [ ! -e "$path" ]; then
    echo "missing"
    return 0
  fi
  ls -l "$path" 2>&1 || true
  if have file; then
    file "$path" 2>&1 || true
  fi
  if have ldd && [ -x "$path" ]; then
    ldd "$path" 2>&1 || true
  fi
  owner_of "$path"
}

section "MixtarRVS Base Closure Inventory"
date -u '+utc=%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || true

section "Identity"
run uname -a
run id
run hostname
print_file /etc/os-release
print_file /etc/alpine-release
print_file /etc/mixtar-release
print_file /etc/mixtar-stage

section "Boot"
run cat /proc/cmdline
if have efibootmgr; then
  run efibootmgr
fi
run findmnt /
run findmnt /System
run findmnt /System/Runtime/initramfs/base

section "Kernel modules and firmware surface"
if have lsmod; then
  run lsmod
fi
for m in iwlwifi iwlmvm mac80211 cfg80211 rfkill ext4 squashfs overlay loop nvme; do
  if have modinfo; then
    printf '\n### modinfo %s\n' "$m"
    modinfo "$m" 2>&1 | sed -n '1,80p' || true
  fi
done
if [ -d /lib/firmware ]; then
  printf '\n### firmware shallow list\n'
  find /lib/firmware -maxdepth 2 -type f 2>/dev/null | sed -n '1,160p' || true
fi

section "Runtime mountpoints"
run mount
run df -h / /System /tmp

section "Mixtar layout"
for d in /Applications /Compatibility /Programs /System /Temporary /Users /Volumes; do
  runtime_file_report "$d"
done
printf '\n### /System shallow tree\n'
find /System -maxdepth 2 -mindepth 1 2>/dev/null | sort | sed -n '1,220p' || true

section "Generations"
if [ -d /System/Generations ]; then
  run du -sh /System/Generations/*
  printf '\n### generation manifests\n'
  find /System/Generations -maxdepth 2 -name manifest.txt -type f 2>/dev/null | sort | while read -r m; do
    printf '\n--- %s\n' "$m"
    sed -n '1,80p' "$m" 2>/dev/null || true
  done
fi

section "Critical runtime binaries"
for p in \
  /bin/sh \
  /bin/busybox \
  /sbin/init \
  /sbin/openrc \
  /sbin/ip \
  /sbin/modprobe \
  /sbin/mdev \
  /sbin/dhcpcd \
  /usr/bin/dbus-daemon \
  /usr/libexec/iwd \
  /usr/sbin/sshd \
  /usr/bin/ssh-keygen \
  /bin/netstat \
  /usr/bin/zsh \
  /System/Shells/zsh
do
  runtime_file_report "$p"
done

section "Critical shared libraries"
for p in \
  /lib/ld-musl-x86_64.so.1 \
  /lib/libc.musl-x86_64.so.1 \
  /usr/lib/libcrypto.so* \
  /usr/lib/libssl.so* \
  /usr/lib/libdbus-1.so* \
  /usr/lib/libell.so*
do
  for match in $p; do
    [ -e "$match" ] && runtime_file_report "$match"
  done
done

section "Service state"
if have rc-status; then
  run rc-status -a
fi
for s in dbus iwd dhcpcd sshd; do
  if [ -e "/etc/init.d/$s" ]; then
    runtime_file_report "/etc/init.d/$s"
  fi
done

section "Network state"
run ip link show
run ip -4 addr
run ip route
if have rfkill; then
  run rfkill list
fi
if have iwctl; then
  run iwctl device list
  run iwctl station list
fi
if have netstat; then
  run netstat -ltnp
fi

section "Accounts and SSH"
run getent passwd vxz
run id vxz
runtime_file_report /Users/vxz/.ssh/authorized_keys
runtime_file_report /etc/ssh/sshd_config
for p in /etc/ssh/ssh_host_*; do
  [ -e "$p" ] && runtime_file_report "$p"
done

section "Mixtar toolkit surface"
if [ -d /System/Tools ]; then
  printf '\n### /System/Tools count\n'
  find /System/Tools -maxdepth 1 -type f -o -type l 2>/dev/null | wc -l || true
  printf '\n### /System/Tools sample\n'
  find /System/Tools -maxdepth 1 2>/dev/null | sort | sed -n '1,220p' || true
fi

section "Package ownership"
if have apk; then
  for p in \
    /bin/sh \
    /bin/busybox \
    /sbin/openrc \
    /sbin/ip \
    /sbin/modprobe \
    /sbin/mdev \
    /sbin/dhcpcd \
    /usr/bin/dbus-daemon \
    /usr/libexec/iwd \
    /usr/sbin/sshd \
    /usr/bin/zsh
  do
    [ -e "$p" ] && owner_of "$p"
  done
fi

section "End"
echo "inventory complete"
