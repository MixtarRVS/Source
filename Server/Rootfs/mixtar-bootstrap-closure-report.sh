#!/bin/sh
set -u

ROOT="${1:-/}"

trim_root() {
  path="$1"
  if [ "$ROOT" = "/" ]; then
    printf '%s\n' "$path"
  else
    printf '%s%s\n' "$ROOT" "$path"
  fi
}

print_file_state() {
  label="$1"
  path="$2"
  full="$(trim_root "$path")"
  if [ -L "$full" ]; then
    target="$(readlink "$full" 2>/dev/null || true)"
    printf '%s %s link=%s\n' "$label" "$path" "$target"
  elif [ -x "$full" ]; then
    printf '%s %s executable\n' "$label" "$path"
  elif [ -f "$full" ]; then
    printf '%s %s file\n' "$label" "$path"
  elif [ -d "$full" ]; then
    printf '%s %s directory\n' "$label" "$path"
  else
    printf '%s %s missing\n' "$label" "$path"
  fi
}

print_cmd_provider() {
  name="$1"
  path="$2"
  full="$(trim_root "$path")"
  if [ ! -e "$full" ]; then
    printf '%s %s missing\n' "$name" "$path"
    return
  fi
  if [ -L "$full" ]; then
    target="$(readlink "$full" 2>/dev/null || true)"
    printf '%s %s link=%s\n' "$name" "$path" "$target"
    return
  fi
  if [ -x "$full" ]; then
    if command -v file >/dev/null 2>&1; then
      kind="$(file -b "$full" 2>/dev/null || true)"
      printf '%s %s executable kind=%s\n' "$name" "$path" "$kind"
    else
      printf '%s %s executable\n' "$name" "$path"
    fi
    return
  fi
  printf '%s %s present-not-executable\n' "$name" "$path"
}

print_section() {
  printf '\n[%s]\n' "$1"
}

printf '# MixtarRVS bootstrap closure report\n'
printf 'generated_utc='
date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || printf 'unknown\n'
printf 'root=%s\n' "$ROOT"

print_section identity
print_file_state system_tools_current /System/Tools/Current
print_file_state mixtar_tools /System/Tools/MixtarRVS/bin
print_file_state userland_manifest /System/Config/MixtarRVS/userland-source-only.manifest
print_file_state source_tools /System/Config/MixtarRVS/userland-source-tools.txt
print_file_state alpine_bin /Compatibility/POSIX/Alpine/3.24/bin
print_file_state alpine_sbin /Compatibility/POSIX/Alpine/3.24/sbin
print_file_state bin /bin
print_file_state sbin /sbin
print_file_state lib /lib
print_file_state usr_bin /usr/bin
print_file_state usr_sbin /usr/sbin
print_file_state usr_lib /usr/lib

print_section live_runtime_mounts
if [ "$ROOT" = "/" ]; then
  if command -v findmnt >/dev/null 2>&1; then
    for m in / /dev /proc /sys /run /tmp; do
      printf '%s ' "$m"
      findmnt -no SOURCE,FSTYPE,OPTIONS "$m" 2>/dev/null || printf 'missing\n'
    done
  else
    mount 2>/dev/null | sed -n '1,40p'
  fi
else
  printf 'not-live-root\n'
fi

print_section critical_bootstrap_commands
print_cmd_provider sh /bin/sh
print_cmd_provider init /sbin/init
print_cmd_provider reboot /sbin/reboot
print_cmd_provider poweroff /sbin/poweroff
print_cmd_provider mount /bin/mount
print_cmd_provider mount_sbin /sbin/mount
print_cmd_provider umount /bin/umount
print_cmd_provider umount_sbin /sbin/umount
print_cmd_provider mkdir /bin/mkdir
print_cmd_provider mdev /sbin/mdev
print_cmd_provider modprobe /sbin/modprobe
print_cmd_provider depmod /sbin/depmod
print_cmd_provider ip /sbin/ip
print_cmd_provider ifconfig /sbin/ifconfig
print_cmd_provider route /sbin/route
print_cmd_provider openrc /sbin/openrc
print_cmd_provider rc-service /sbin/rc-service
print_cmd_provider rc-status /bin/rc-status
print_cmd_provider rc-update /sbin/rc-update
print_cmd_provider start-stop-daemon /sbin/start-stop-daemon
print_cmd_provider apk /sbin/apk

print_section service_supervisor
print_file_state openrc_conf /etc/rc.conf
print_file_state inittab /etc/inittab
print_file_state runlevels /etc/runlevels
for level in sysinit boot default shutdown; do
  dir="$(trim_root "/etc/runlevels/$level")"
  if [ -d "$dir" ]; then
    printf 'runlevel %s\n' "$level"
    find "$dir" -maxdepth 1 -type l -printf '%f -> %l\n' 2>/dev/null | sort
  fi
done

print_section network_closure
print_cmd_provider iwd /usr/libexec/iwd
print_cmd_provider iwctl /usr/bin/iwctl
print_cmd_provider dhcpcd /sbin/dhcpcd
print_cmd_provider resolvconf /sbin/resolvconf
print_file_state iwd_config /etc/iwd
print_file_state dhcpcd_conf /etc/dhcpcd.conf
print_file_state resolv_conf /etc/resolv.conf

print_section remote_closure
print_cmd_provider sshd /usr/sbin/sshd
print_cmd_provider ssh_keygen /usr/bin/ssh-keygen
print_file_state sshd_config /etc/ssh/sshd_config
print_file_state ssh_host_ed25519 /etc/ssh/ssh_host_ed25519_key
print_file_state ssh_host_rsa /etc/ssh/ssh_host_rsa_key
print_file_state vxz_authorized_keys /Users/vxz/.ssh/authorized_keys

print_section library_runtime
for path in \
  /bin/busybox \
  /sbin/openrc \
  /sbin/rc-service \
  /usr/sbin/sshd \
  /usr/libexec/iwd \
  /sbin/dhcpcd \
  /usr/bin/dbus-daemon \
  /System/Tools/Current/bin/ls \
  /System/Tools/Current/bin/sh
do
  full="$(trim_root "$path")"
  [ -e "$full" ] || continue
  printf '%s\n' "$path"
  if [ "$ROOT" = "/" ] && command -v ldd >/dev/null 2>&1; then
    ldd "$full" 2>/dev/null | sed 's/^/  /' || true
  else
    printf '  ldd skipped\n'
  fi
done

print_section alpine_identity_blockers
printf 'blocker=pid1 provider=/sbin/init reason=OpenRC/BusyBox still owns boot supervision\n'
printf 'blocker=shell provider=/bin/sh reason=init scripts and service scripts still require POSIX sh\n'
printf 'blocker=mount provider=/bin/mount,/sbin/mount reason=early tmpfs/dev/proc/sys/root mount flow needs Linux-compatible mount\n'
printf 'blocker=device_nodes provider=/sbin/mdev reason=/dev hotplug and coldplug are still Alpine/BusyBox-managed\n'
printf 'blocker=kernel_modules provider=/sbin/modprobe,/sbin/depmod reason=module loading is not Mixtar-owned yet\n'
printf 'blocker=services provider=/sbin/openrc,/sbin/rc-service reason=service graph and runlevels are OpenRC-owned\n'
printf 'blocker=network provider=/usr/libexec/iwd,/sbin/dhcpcd reason=network bring-up is not Mixtar-owned yet\n'
printf 'blocker=remote provider=/usr/sbin/sshd reason=remote access is OpenSSH/Alpine-packaged runtime\n'
printf 'blocker=packages provider=/sbin/apk reason=package substrate is still Alpine apk\n'
printf 'blocker=libraries provider=/lib,/usr/lib,/System/Libraries reason=musl and service libs are copied but not Mixtar-built\n'

print_section replacement_order
printf '1 initramfs-runtime: mount /dev /proc /sys /run and root rw from Mixtar-owned script\n'
printf '2 pid1-supervisor: replace OpenRC as boot/service supervisor, keep OpenRC as compatibility fallback\n'
printf '3 device-and-module-tools: replace mdev/modprobe/depmod dependency or wrap them as explicit compatibility tools\n'
printf '4 network: Mixtar network bring-up wrapper with iwd/dhcpcd as explicit backend, then replace backend later\n'
printf '5 remote: Mixtar remote agent or strict sshd wrapper, then replace OpenSSH packaging later\n'
printf '6 package-source: stop treating apk as identity; keep it under compatibility/backend only\n'

print_section conclusion
printf 'status=not-closed\n'
printf 'reason=MixtarRVS userland identity is active, but boot, services, network, remote access, and package substrate still depend on Alpine compatibility.\n'
