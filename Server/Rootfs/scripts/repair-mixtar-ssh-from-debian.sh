#!/bin/sh
set -eu

ROOT_PART="${1:-/dev/nvme0n1p3}"
MNT="${MNT:-/mnt/mixtar-repair}"

if [ "$(id -u)" != "0" ]; then
  echo "run as root" >&2
  exit 1
fi

case "$ROOT_PART" in
  /dev/*) ;;
  *) echo "refusing non-device root path: $ROOT_PART" >&2; exit 1 ;;
esac

mkdir -p "$MNT"

if ! mountpoint -q "$MNT" 2>/dev/null; then
  mount -o rw "$ROOT_PART" "$MNT"
fi

if [ ! -d "$MNT/etc" ] || [ ! -d "$MNT/System" ]; then
  echo "mounted path does not look like MixtarRVS root: $MNT" >&2
  exit 1
fi

echo "mounted $ROOT_PART at $MNT"

mkdir -p "$MNT/etc/ssh" "$MNT/run/sshd" "$MNT/Users/vxz/.ssh"
chown 0:0 "$MNT/etc/ssh" "$MNT/run/sshd"
chmod 755 "$MNT/etc/ssh" "$MNT/run" "$MNT/run/sshd"

if [ -f "$MNT/etc/ssh/sshd_config" ]; then
  cp -p "$MNT/etc/ssh/sshd_config" "$MNT/etc/ssh/sshd_config.before-mixtar-repair"
else
  cat > "$MNT/etc/ssh/sshd_config" <<'SSHD_CONFIG'
Port 22
AddressFamily any
ListenAddress 0.0.0.0
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key
AuthorizedKeysFile .ssh/authorized_keys
PermitRootLogin prohibit-password
PubkeyAuthentication yes
PasswordAuthentication yes
KbdInteractiveAuthentication no
UseDNS no
Subsystem sftp internal-sftp
SSHD_CONFIG
fi

chown 0:0 "$MNT/etc/ssh/sshd_config"
chmod 644 "$MNT/etc/ssh/sshd_config"

for key in "$MNT"/etc/ssh/ssh_host_*_key; do
  [ -e "$key" ] || continue
  chown 0:0 "$key"
  chmod 600 "$key"
done

for pub in "$MNT"/etc/ssh/ssh_host_*_key.pub; do
  [ -e "$pub" ] || continue
  chown 0:0 "$pub"
  chmod 644 "$pub"
done

if [ -e "$MNT/Users/vxz" ]; then
  chown 1000:1000 "$MNT/Users/vxz" 2>/dev/null || true
  chmod 755 "$MNT/Users/vxz" 2>/dev/null || true
fi

if [ -d "$MNT/Users/vxz/.ssh" ]; then
  chown 1000:1000 "$MNT/Users/vxz/.ssh" 2>/dev/null || true
  chmod 700 "$MNT/Users/vxz/.ssh" 2>/dev/null || true
fi

if [ -f "$MNT/Users/vxz/.ssh/authorized_keys" ]; then
  chown 1000:1000 "$MNT/Users/vxz/.ssh/authorized_keys" 2>/dev/null || true
  chmod 600 "$MNT/Users/vxz/.ssh/authorized_keys" 2>/dev/null || true
fi

for d in "$MNT"/tmp/mixtar-rootfs-selftest-*; do
  [ -d "$d" ] || continue
  case "$d" in
    "$MNT"/tmp/mixtar-rootfs-selftest-*) rm -rf "$d" ;;
    *) echo "refusing unsafe cleanup path: $d" >&2; exit 1 ;;
  esac
done

for d in dev proc sys run; do
  mkdir -p "$MNT/$d"
done

mounted_dev=0
mounted_proc=0
mounted_sys=0

if ! mountpoint -q "$MNT/dev" 2>/dev/null; then
  mount --bind /dev "$MNT/dev"
  mounted_dev=1
fi

if ! mountpoint -q "$MNT/proc" 2>/dev/null; then
  mount -t proc proc "$MNT/proc"
  mounted_proc=1
fi

if ! mountpoint -q "$MNT/sys" 2>/dev/null; then
  mount -t sysfs sys "$MNT/sys"
  mounted_sys=1
fi

if [ -x "$MNT/usr/bin/ssh-keygen" ]; then
  chroot "$MNT" /usr/bin/ssh-keygen -A || true
fi

if [ -x "$MNT/usr/sbin/sshd" ]; then
  chroot "$MNT" /usr/sbin/sshd -t -f /etc/ssh/sshd_config
  echo "sshd_config check: ok"
else
  echo "warning: /usr/sbin/sshd not found in Mixtar root" >&2
fi

if [ "$mounted_sys" = "1" ]; then umount "$MNT/sys"; fi
if [ "$mounted_proc" = "1" ]; then umount "$MNT/proc"; fi
if [ "$mounted_dev" = "1" ]; then umount "$MNT/dev"; fi

sync

echo "repaired ssh permissions under $MNT"
echo "next: reboot into MixtarRVS fallback Boot0006"
