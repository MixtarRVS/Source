#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../../.." && pwd)
root="$repo_root/Server/Rootfs/Generated/corev07-root"
network_target="8.8.8.8"
network_mode="warn"
chroot_cmd=$(command -v chroot || true)

usage() {
    cat <<EOF
usage: corev07-chroot-gate.sh [--root PATH] [--network-target IPv4] [--strict-network] [--skip-network]

Runs the CoreV07 chroot userland gate:
  1. verifies the staged native root shape
  2. executes core Mixtar userland commands through chroot
  3. executes zsh through chroot
  4. optionally tests native /System/Userland/ping through chroot

This is not a boot test.
It does not modify Debian, ESP, EFI variables, boot order, or a live root.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --root)
            [ "$#" -ge 2 ] || {
                echo "missing value for --root" >&2
                exit 2
            }
            root=$2
            shift 2
            ;;
        --network-target)
            [ "$#" -ge 2 ] || {
                echo "missing value for --network-target" >&2
                exit 2
            }
            network_target=$2
            shift 2
            ;;
        --strict-network)
            network_mode="strict"
            shift
            ;;
        --skip-network)
            network_mode="skip"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

ok() {
    echo "OK: $*"
}

warn() {
    echo "WARN: $*" >&2
}

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

need_root() {
    [ -n "$chroot_cmd" ] || fail "host chroot command not found"
    if [ "$(id -u)" -eq 0 ]; then
        return 0
    fi
    if command -v sudo >/dev/null 2>&1; then
        network_arg=""
        case "$network_mode" in
            strict)
                network_arg="--strict-network"
                ;;
            skip)
                network_arg="--skip-network"
                ;;
        esac
        exec sudo -n sh "$0" --root "$root" --network-target "$network_target" $network_arg
    fi
    fail "chroot gate requires root or passwordless sudo"
}

assert_dir() {
    [ -d "$root/$1" ] || fail "missing directory: /$1"
    ok "directory present: /$1"
}

assert_absent() {
    [ ! -e "$root/$1" ] || fail "forbidden native root path exists: /$1"
    ok "forbidden native root path absent: /$1"
}

assert_exec() {
    [ -x "$root/$1" ] || fail "missing executable: /$1"
    ok "executable present: /$1"
}

assert_file() {
    [ -s "$root/$1" ] || fail "missing file: /$1"
    ok "file present: /$1"
}

run_chroot() {
    env -i \
        PATH=/System/Shells:/System/Userland \
        LD_LIBRARY_PATH=/System/Shells/Runtime \
        TERM=linux \
        HOME=/Users/vxz \
        USER=vxz \
        MIXTAR_SYSTEM_NAME=MixtarRVS \
        "$chroot_cmd" "$root" "$@"
}

capture_chroot() {
    env -i \
        PATH=/System/Shells:/System/Userland \
        LD_LIBRARY_PATH=/System/Shells/Runtime \
        TERM=linux \
        HOME=/Users/vxz \
        USER=vxz \
        MIXTAR_SYSTEM_NAME=MixtarRVS \
        "$chroot_cmd" "$root" "$@" 2>&1
}

check_shape() {
    [ -d "$root" ] || fail "staged root not found: $root"
    assert_dir Applications
    assert_dir System
    assert_dir Users
    assert_dir Volumes
    assert_dir Temporary
    assert_absent bin
    assert_absent boot
    assert_absent dev
    assert_absent etc
    assert_absent home
    assert_absent lib
    assert_absent lib64
    assert_absent proc
    assert_absent root
    assert_absent run
    assert_absent sbin
    assert_absent sys
    assert_absent tmp
    assert_absent usr
    assert_absent var
}

check_executables() {
    assert_exec System/Userland/echo
    assert_exec System/Userland/cat
    assert_exec System/Userland/pwd
    assert_exec System/Userland/ls
    assert_exec System/Userland/ping
    assert_exec System/Userland/network
    assert_exec System/Userland/security
    assert_exec System/Userland/system
    assert_exec System/Userland/updates
    assert_exec System/Shells/zsh
    assert_exec System/Runtime/Executor
    assert_file System/Configuration/System/System.config
    assert_file System/Configuration/Updates/Updates.config
}

check_userland() {
    out=$(capture_chroot /System/Userland/echo chroot-echo-ok)
    [ "$out" = "chroot-echo-ok" ] || fail "echo output mismatch: $out"
    ok "chroot echo"

    out=$(capture_chroot /System/Userland/pwd)
    [ "$out" = "/" ] || fail "pwd output mismatch: $out"
    ok "chroot pwd"

    out=$(capture_chroot /System/Userland/ls /)
    echo "$out" | grep -Fx Applications >/dev/null || fail "ls / missing Applications"
    echo "$out" | grep -Fx System >/dev/null || fail "ls / missing System"
    echo "$out" | grep -Fx Users >/dev/null || fail "ls / missing Users"
    echo "$out" | grep -Fx Volumes >/dev/null || fail "ls / missing Volumes"
    echo "$out" | grep -Fx Temporary >/dev/null || fail "ls / missing Temporary"
    if echo "$out" | grep -Ex 'bin|dev|etc|usr|var|root' >/dev/null; then
        fail "ls / exposes forbidden POSIX identity path"
    fi
    ok "chroot ls native root"
}

check_shell() {
    out=$(capture_chroot /System/Shells/zsh -f -c 'print -r -- zsh-ok; print -r -- $PATH')
    echo "$out" | grep -Fx zsh-ok >/dev/null || fail "zsh did not execute command"
    echo "$out" | grep -F "/System/Userland" >/dev/null || fail "zsh PATH does not contain /System/Userland"
    ok "chroot zsh"
}

check_corev08_status() {
    out=$(capture_chroot /System/Userland/security status)
    echo "$out" | grep -F "Security: Normal" >/dev/null || fail "security status missing Normal"
    ok "chroot security status"

    out=$(capture_chroot /System/Userland/updates status)
    echo "$out" | grep -F "Updates: Unknown" >/dev/null || fail "updates status missing Unknown"
    ok "chroot updates status"

    out=$(capture_chroot /System/Userland/system about)
    echo "$out" | grep -F "CoreV08" >/dev/null || fail "system about missing CoreV08"
    ok "chroot system about"
}

check_network() {
    if [ "$network_mode" = "skip" ]; then
        warn "network chroot test skipped"
        return 0
    fi

    if run_chroot /System/Userland/ping -c 4 "$network_target"; then
        ok "chroot native ping target=$network_target"
        return 0
    fi

    if [ "$network_mode" = "strict" ]; then
        fail "chroot native ping failed target=$network_target"
    fi
    warn "chroot native ping failed target=$network_target; boot one-shot remains authoritative for real networking"
}

need_root
echo "CoreV07 chroot gate"
echo "  root: $root"
echo "  network_target: $network_target"
echo "  network_mode: $network_mode"
check_shape
check_executables
check_userland
check_shell
check_corev08_status
check_network
echo "CoreV07 chroot gate: OK"
