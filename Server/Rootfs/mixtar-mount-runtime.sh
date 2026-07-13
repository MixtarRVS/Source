#!/bin/sh
set -eu

mode=apply
if [ "${1:-}" = "--check" ]; then
    mode=check
elif [ "${1:-}" = "--dry-run" ]; then
    mode=dry-run
fi

log_dir=/System/Runtime
log_file=$log_dir/mount-runtime.log

say() {
    printf '%s\n' "$*"
}

note() {
    say "$*"
    if [ "$mode" = "apply" ]; then
        if mkdir -p "$log_dir" 2>/dev/null && [ -w "$log_dir" ]; then
            printf '%s\n' "$*" >> "$log_file" 2>/dev/null || true
        fi
    fi
}

mounted() {
    target=$1
    if [ ! -r /proc/mounts ]; then
        [ "$target" = "/proc" ] && return 1
        return 1
    fi
    grep -qs " $target " /proc/mounts
}

ensure_dir() {
    path=$1
    if [ "$mode" = "dry-run" ]; then
        say "mkdir -p $path"
    else
        mkdir -p "$path"
    fi
}

ensure_mount() {
    type=$1
    source=$2
    target=$3
    opts=${4:-}

    ensure_dir "$target"
    if mounted "$target"; then
        note "$target already mounted"
        return 0
    fi

    if [ "$mode" = "check" ]; then
        note "$target missing"
        return 1
    fi

    if [ "$mode" = "dry-run" ]; then
        if [ -n "$opts" ]; then
            say "mount -t $type -o $opts $source $target"
        else
            say "mount -t $type $source $target"
        fi
        return 0
    fi

    if [ -n "$opts" ]; then
        mount -t "$type" -o "$opts" "$source" "$target"
    else
        mount -t "$type" "$source" "$target"
    fi
    note "$target mounted as $type"
}

main() {
    note "mixtar-mount-runtime mode=$mode"

    ensure_mount proc proc /proc nosuid,noexec,nodev
    ensure_mount sysfs sysfs /sys nosuid,noexec,nodev
    ensure_mount devtmpfs devtmpfs /dev mode=0755,nosuid
    ensure_mount tmpfs tmpfs /run mode=0755,nosuid,nodev
    ensure_mount devpts devpts /dev/pts gid=5,mode=620
    ensure_mount tmpfs tmpfs /dev/shm mode=1777,nosuid,nodev

    note "mixtar-mount-runtime complete"
}

main "$@"
