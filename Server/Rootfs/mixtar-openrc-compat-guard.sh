#!/bin/sh
set -eu

COMPAT_ROOT=${MIXTAR_COMPAT_ROOT:-/Compatibility/POSIX/Alpine/3.24}
BUSYBOX=${MIXTAR_BUSYBOX:-/bin/busybox}

require_root() {
    if [ "$(id -u)" != "0" ]; then
        echo "mixtar-openrc-compat-guard: root required" >&2
        return 1
    fi
}

force_busybox_link() {
    path=$1
    if [ -e "$path" ] && [ ! -L "$path" ]; then
        backup=/System/Logs/openrc-compat-guard/$(basename "$path").previous
        mkdir -p /System/Logs/openrc-compat-guard
        mv "$path" "$backup"
    fi
    ln -sfn "$BUSYBOX" "$path"
}

require_root

if [ ! -x "$BUSYBOX" ]; then
    echo "mixtar-openrc-compat-guard: missing $BUSYBOX" >&2
    exit 1
fi

mkdir -p "$COMPAT_ROOT/bin" "$COMPAT_ROOT/sbin" /System/Runtime/run /System/Logs

if [ -L /run ]; then
    rm -f /run
fi
mkdir -p /run
chmod 0755 /run /System/Runtime/run

for app in sh mount umount mkdir rmdir ln rm cp mv cat chmod chown grep sed awk sleep true false echo uname dmesg ps kill hostname sync; do
    force_busybox_link "$COMPAT_ROOT/bin/$app"
done

for app in mount umount mdev modprobe depmod ifconfig ip route; do
    force_busybox_link "$COMPAT_ROOT/sbin/$app"
done

if [ -L /bin ]; then
    ln -sfn "${COMPAT_ROOT#/}/bin" /bin
fi

if [ -L /sbin ]; then
    ln -sfn "${COMPAT_ROOT#/}/sbin" /sbin
fi

echo "mixtar-openrc-compat-guard: ok"
