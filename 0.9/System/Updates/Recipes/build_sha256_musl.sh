#!/bin/sh
set -eu

fail()
{
    printf '%s\n' "build-sha256-musl: $*" >&2
    exit 1
}

inside=0
if [ "$#" -eq 4 ] && [ "$1" = "--inside" ]; then
    inside=1
    shift
fi

[ "$#" -eq 3 ] ||
    fail "usage: build_sha256_musl.sh ZIG OPENBSD-SOURCE WORK"

zig=$1
source_root=$2
work=$3

for path in "$zig" "$source_root" "$work"; do
    case "$path" in
        /*) ;;
        *) fail "all paths must be absolute" ;;
    esac
done

script=$0
case "$script" in
    /*) ;;
    *) script=$(pwd)/$script ;;
esac
script_dir=$(CDPATH= cd -- "$(dirname "$script")" && pwd)
compatibility=$(CDPATH= cd -- "$script_dir/../Compatibility/SHA256" && pwd)

if [ "$inside" -eq 0 ]; then
    command -v bwrap >/dev/null 2>&1 || fail "bubblewrap is required"
    [ -x "$zig" ] || fail "Zig executable is missing"
    [ -f "$source_root/lib/libc/hash/sha2.c" ] || fail "OpenBSD sha2.c is missing"
    [ -f "$source_root/include/sha2.h" ] || fail "OpenBSD sha2.h is missing"
    [ ! -e "$work" ] || fail "work path already exists"
    mkdir -p "$work/include"
    cp "$source_root/include/sha2.h" "$work/include/sha2.h"
    exec bwrap \
        --die-with-parent \
        --unshare-net \
        --ro-bind / / \
        --dev /dev \
        --proc /proc \
        --tmpfs /tmp \
        --bind "$work" "$work" \
        --clearenv \
        --setenv HOME /tmp \
        --setenv LC_ALL C \
        /bin/sh "$script" --inside "$zig" "$source_root" "$work"
fi

output_root="$work/stage/System/Userland"
output="$output_root/mixtar-sha256"
cache="$work/zig-cache"
mkdir -p "$output_root" "$cache"
ZIG_GLOBAL_CACHE_DIR="$cache" timeout 20 "$zig" cc \
    -target x86_64-linux-musl \
    -std=c23 \
    -O3 \
    -Wall \
    -Wextra \
    -Werror \
    -pedantic \
    -static \
    -D_GNU_SOURCE \
    -DSHA2_SMALL \
    -include "$compatibility/mixtar_sha256_compat.h" \
    -I"$work/include" \
    "$compatibility/mixtar_sha256.c" \
    "$source_root/lib/libc/hash/sha2.c" \
    -Wl,--strip-all \
    -o "$output"

printf test > "$work/test-input"
actual=$(timeout 5 "$output" "$work/test-input") || fail "hash smoke test failed"
[ "$actual" = "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08" ] ||
    fail "hash smoke test mismatch"
printf '%s\n' "build-sha256-musl: PASS"
printf '%s\n' "artifact=$output"
