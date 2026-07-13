#!/bin/sh
set -eu

BIN=${MIXTAR_USERLAND_BIN:-/System/Tools/MixtarRVS/bin}
TOOLS=${MIXTAR_USERLAND_TOOLS:-/System/Config/MixtarRVS/userland-source-tools.txt}
MANIFEST=${MIXTAR_USERLAND_MANIFEST:-/System/Config/MixtarRVS/userland-source-only.manifest}

failures=0

ok() {
    printf 'ok: %s\n' "$*"
}

fail() {
    printf 'fail: %s\n' "$*" >&2
    failures=$((failures + 1))
}

check_file() {
    path=$1
    if [ -r "$path" ]; then
        ok "readable $path"
    else
        fail "missing/read-protected $path"
    fi
}

check_dir() {
    path=$1
    if [ -d "$path" ]; then
        ok "directory $path"
    else
        fail "missing directory $path"
    fi
}

check_counts() {
    expected=$(wc -l < "$TOOLS" 2>/dev/null || echo 0)
    actual=$(find "$BIN" -maxdepth 1 -type f 2>/dev/null | wc -l)
    if [ "$expected" = "$actual" ]; then
        ok "tool count $actual matches manifest"
    else
        fail "tool count mismatch: expected $expected actual $actual"
    fi
}

check_missing_tools() {
    while IFS= read -r tool; do
        [ -n "$tool" ] || continue
        if [ -x "$BIN/$tool" ]; then
            :
        else
            fail "manifest tool not executable: $tool"
        fi
    done < "$TOOLS"
}

check_extra_tools() {
    for path in "$BIN"/*; do
        [ -f "$path" ] || continue
        name=$(basename "$path")
        if grep -qx "$name" "$TOOLS"; then
            :
        else
            fail "non-manifest tool present: $name"
        fi
    done
}

check_path_resolution() {
    PATH="$BIN:/bin:/sbin:/usr/bin:/usr/sbin"
    export PATH
    for tool in uname ls cat cp mv rm grep sed awk ps find sort wc head tail chmod ln mkdir rmdir; do
        resolved=$(command -v "$tool" 2>/dev/null || true)
        case "$resolved" in
            "$BIN/"*)
                ok "PATH $tool -> $resolved"
                ;;
            *)
                fail "PATH $tool not from Mixtar userland: ${resolved:-missing}"
                ;;
        esac
    done
}

check_boot_boundary() {
    bin_link=$(readlink /bin 2>/dev/null || true)
    sbin_link=$(readlink /sbin 2>/dev/null || true)
    case "$bin_link" in
        *Compatibility/POSIX/Alpine/3.24/bin)
            ok "/bin remains bootstrap compatibility"
            ;;
        *)
            fail "/bin is not expected bootstrap compatibility link: ${bin_link:-not-a-link}"
            ;;
    esac
    case "$sbin_link" in
        *Compatibility/POSIX/Alpine/3.24/sbin)
            ok "/sbin remains bootstrap compatibility"
            ;;
        *)
            fail "/sbin is not expected bootstrap compatibility link: ${sbin_link:-not-a-link}"
            ;;
    esac
}

main() {
    check_dir "$BIN"
    check_file "$TOOLS"
    check_file "$MANIFEST"
    check_counts
    check_missing_tools
    check_extra_tools
    check_path_resolution
    check_boot_boundary

    if [ "$failures" -eq 0 ]; then
        echo "MixtarRVS userland verify: PASS"
        return 0
    fi
    echo "MixtarRVS userland verify: FAIL ($failures)" >&2
    return 1
}

main "$@"
