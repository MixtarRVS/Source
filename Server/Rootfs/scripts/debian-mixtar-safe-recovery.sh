#!/bin/sh
# Safe Debian-side MixtarRVS recovery helper.
#
# Defaults are intentionally conservative:
# - no reboot
# - no efibootmgr / BootNext
# - no chroot
# - no bind mounts of /dev, /proc, /sys, /run, or /tmp
# - collect mode mounts the Mixtar partition read-only
#
# Usage:
#   sudo sh debian-mixtar-safe-recovery.sh collect [/dev/nvme0n1p3]
#   sudo sh debian-mixtar-safe-recovery.sh repair-ssh [/dev/nvme0n1p3]

set -eu

MODE="${1:-collect}"
DEV="${2:-/dev/nvme0n1p3}"
MNT="${MIXTAR_SAFE_MOUNT:-/mnt/mixtar-safe-recovery}"
TS="$(date +%Y%m%d-%H%M%S 2>/dev/null || printf now)"
REPORT="/tmp/mixtar-safe-report-$TS.txt"
MOUNTED_BY_THIS_SCRIPT=0

die() {
    printf '%s\n' "ERROR: $*" >&2
    exit 1
}

log() {
    printf '%s\n' "$*" | tee -a "$REPORT" >/dev/null
}

need_root() {
    [ "$(id -u)" = "0" ] || die "run as root"
}

is_mounted_at() {
    awk -v m="$MNT" '$2 == m { found = 1 } END { exit found ? 0 : 1 }' /proc/mounts
}

mount_ro() {
    mkdir -p "$MNT"
    if is_mounted_at; then
        return 0
    fi
    mount -o ro "$DEV" "$MNT"
    MOUNTED_BY_THIS_SCRIPT=1
}

mount_rw() {
    mkdir -p "$MNT"
    if is_mounted_at; then
        mount -o remount,rw "$MNT"
        return 0
    fi
    mount -o rw "$DEV" "$MNT"
    MOUNTED_BY_THIS_SCRIPT=1
}

cleanup() {
    if [ "$MOUNTED_BY_THIS_SCRIPT" = "1" ]; then
        umount "$MNT" >/dev/null 2>&1 || true
    fi
}

append_file() {
    rel="$1"
    path="$MNT/$rel"
    log ""
    log "### $rel"
    if [ -e "$path" ]; then
        sed -n '1,220p' "$path" >> "$REPORT" 2>&1 || true
    else
        log "missing"
    fi
}

append_ls() {
    title="$1"
    shift
    log ""
    log "### $title"
    ls -lah "$@" >> "$REPORT" 2>&1 || true
}

append_readlink() {
    rel="$1"
    path="$MNT/$rel"
    log ""
    log "### readlink $rel"
    if [ -e "$path" ] || [ -L "$path" ]; then
        readlink "$path" >> "$REPORT" 2>&1 || true
        ls -lah "$path" >> "$REPORT" 2>&1 || true
    else
        log "missing"
    fi
}

append_tail_glob() {
    title="$1"
    pattern="$2"
    log ""
    log "### $title"
    found=0
    for path in $pattern; do
        [ -f "$path" ] || continue
        found=1
        log ""
        log "--- ${path#$MNT/}"
        tail -n 120 "$path" >> "$REPORT" 2>&1 || true
    done
    [ "$found" = "1" ] || log "no files"
}

collect_report() {
    mount_ro
    : > "$REPORT"

    log "MixtarRVS safe recovery report"
    log "timestamp=$TS"
    log "mode=collect"
    log "device=$DEV"
    log "mount=$MNT"

    log ""
    log "### Debian host"
    uname -a >> "$REPORT" 2>&1 || true
    id >> "$REPORT" 2>&1 || true
    command -v lsblk >/dev/null 2>&1 && lsblk -f "$DEV" >> "$REPORT" 2>&1 || true
    mount | grep " $MNT " >> "$REPORT" 2>&1 || true

    append_ls "Mixtar root top level" "$MNT"
    append_ls "Mixtar native directories" \
        "$MNT/Applications" "$MNT/Compatibility" "$MNT/Programs" \
        "$MNT/System" "$MNT/Temporary" "$MNT/Users" "$MNT/Volumes"
    append_ls "POSIX compatibility entries" \
        "$MNT/bin" "$MNT/sbin" "$MNT/etc" "$MNT/lib" "$MNT/usr" \
        "$MNT/var" "$MNT/dev" "$MNT/proc" "$MNT/sys" "$MNT/run" "$MNT/tmp"

    append_readlink "System/Current"
    append_readlink "System/Previous"
    append_readlink "bin"
    append_readlink "sbin"
    append_readlink "etc"
    append_readlink "usr"
    append_readlink "lib"
    append_readlink "home"

    append_ls "System Kernel/Profile" "$MNT/System/Kernel" "$MNT/System/Runtime"
    append_ls "System Tools" "$MNT/System/Tools"
    append_ls "System SystemTools" "$MNT/System/SystemTools"
    append_ls "OpenRC default runlevel" "$MNT/etc/runlevels/default"
    append_ls "OpenRC init.d" "$MNT/etc/init.d"
    append_ls "SSH config directory" "$MNT/etc/ssh"
    append_ls "device placeholders" \
        "$MNT/dev" "$MNT/dev/null" "$MNT/dev/tty" "$MNT/dev/tty0" \
        "$MNT/System/Devices" "$MNT/System/Process" "$MNT/System/Hardware"

    append_file "etc/hostname"
    append_file "etc/alpine-release"
    append_file "etc/mixtar-release"
    append_file "etc/fstab"
    append_file "etc/inittab"
    append_file "etc/ssh/sshd_config"
    append_file "etc/network/interfaces"
    append_file "etc/dhcpcd.conf"

    append_tail_glob "Mixtar closure logs" "$MNT/System/Base/Closure/*.log"
    append_tail_glob "Mixtar runtime initramfs closure logs" "$MNT/System/Runtime/initramfs/base/System/Base/Closure/*.log"
    append_tail_glob "System logs" "$MNT/System/Logs/*.log"
    append_tail_glob "var logs" "$MNT/var/log/*"

    log ""
    log "report=$REPORT"
    printf '%s\n' "$REPORT"
}

ensure_dir() {
    path="$1"
    mkdir -p "$path"
    chmod 755 "$path" 2>/dev/null || true
}

repair_ssh() {
    mount_rw
    : > "$REPORT"

    log "MixtarRVS safe recovery report"
    log "timestamp=$TS"
    log "mode=repair-ssh"
    log "device=$DEV"
    log "mount=$MNT"

    ensure_dir "$MNT/etc"
    ensure_dir "$MNT/etc/ssh"
    ensure_dir "$MNT/etc/runlevels"
    ensure_dir "$MNT/etc/runlevels/default"
    ensure_dir "$MNT/var"
    ensure_dir "$MNT/var/empty"

    if [ ! -s "$MNT/etc/ssh/sshd_config" ]; then
        if [ -s "$MNT/System/Config/ssh/sshd_config" ]; then
            cp "$MNT/System/Config/ssh/sshd_config" "$MNT/etc/ssh/sshd_config"
            log "copied sshd_config from System/Config"
        elif [ -s "$MNT/Compatibility/POSIX/Alpine/3.24/etc/ssh/sshd_config" ]; then
            cp "$MNT/Compatibility/POSIX/Alpine/3.24/etc/ssh/sshd_config" "$MNT/etc/ssh/sshd_config"
            log "copied sshd_config from Alpine compatibility tree"
        else
            cat > "$MNT/etc/ssh/sshd_config" <<'EOF'
Port 22
Protocol 2
HostKey /etc/ssh/ssh_host_ed25519_key
HostKey /etc/ssh/ssh_host_rsa_key
PermitRootLogin prohibit-password
PubkeyAuthentication yes
PasswordAuthentication yes
KbdInteractiveAuthentication no
UsePAM no
AllowTcpForwarding yes
X11Forwarding no
PrintMotd no
Subsystem sftp internal-sftp
EOF
            log "created minimal sshd_config"
        fi
    else
        log "existing sshd_config kept"
    fi

    chmod 644 "$MNT/etc/ssh/sshd_config" 2>/dev/null || true

    if command -v ssh-keygen >/dev/null 2>&1; then
        ssh-keygen -A -f "$MNT" >> "$REPORT" 2>&1 || log "ssh-keygen -A -f failed"
    else
        log "ssh-keygen not available on Debian host"
    fi

    if [ -e "$MNT/etc/init.d/sshd" ]; then
        if [ ! -e "$MNT/etc/runlevels/default/sshd" ]; then
            ln -s /etc/init.d/sshd "$MNT/etc/runlevels/default/sshd" 2>>"$REPORT" || true
            log "enabled sshd in OpenRC default runlevel"
        else
            log "OpenRC sshd runlevel entry already exists"
        fi
    else
        log "missing etc/init.d/sshd; did not create runlevel symlink"
    fi

    append_ls "SSH config after repair" "$MNT/etc/ssh"
    append_ls "OpenRC default runlevel after repair" "$MNT/etc/runlevels/default"
    append_file "etc/ssh/sshd_config"

    sync
    log ""
    log "report=$REPORT"
    printf '%s\n' "$REPORT"
}

case "$MODE" in
    collect)
        need_root
        trap cleanup EXIT INT TERM
        collect_report
        ;;
    repair-ssh)
        need_root
        trap cleanup EXIT INT TERM
        repair_ssh
        ;;
    *)
        die "unknown mode: $MODE"
        ;;
esac
