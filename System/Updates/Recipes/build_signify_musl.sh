#!/bin/sh
set -eu

fail()
{
    printf '%s\n' "build-signify-musl: $*" >&2
    exit 1
}

inside=0
if [ "$#" -eq 3 ] && [ "$1" = "--inside" ]; then
    inside=1
    shift
fi

[ "$#" -eq 2 ] ||
    fail "usage: build_signify_musl.sh OPENBSD-SOURCE WORK"

source_root=$1
work=$2

case "$source_root" in
    /*) ;;
    *) fail "OpenBSD source path must be absolute" ;;
esac
case "$work" in
    /*) ;;
    *) fail "work path must be absolute" ;;
esac
[ -f "$source_root/usr.bin/signify/signify.c" ] ||
    fail "OpenBSD signify source is missing"
[ -f "$source_root/lib/libc/hash/sha2.c" ] ||
    fail "OpenBSD SHA2 source is missing"
[ -f "$source_root/lib/libc/net/base64.c" ] ||
    fail "OpenBSD base64 source is missing"

script=$0
case "$script" in
    /*) ;;
    *) script=$(pwd)/$script ;;
esac
script_dir=$(CDPATH= cd -- "$(dirname "$script")" && pwd)
compatibility=$(CDPATH= cd -- "$script_dir/../Compatibility/Signify" && pwd)

if [ "$inside" -eq 0 ]; then
    command -v bwrap >/dev/null 2>&1 || fail "bubblewrap is required"
    [ ! -e "$work" ] || fail "work path already exists"
    mkdir -p "$work"
    exec bwrap \
        --die-with-parent \
        --unshare-net \
        --ro-bind / / \
        --bind "$work" "$work" \
        --dev /dev \
        --proc /proc \
        --tmpfs /tmp \
        --clearenv \
        --setenv PATH /usr/bin:/bin \
        --setenv HOME /tmp \
        --setenv LC_ALL C \
        /bin/sh "$script" --inside "$source_root" "$work"
fi

command -v musl-gcc >/dev/null 2>&1 || fail "musl-gcc is required"

signify_source="$source_root/usr.bin/signify"
output_root="$work/stage/System/Userland"
output="$output_root/signify"
mkdir -p "$output_root"

musl-gcc \
    -std=c23 \
    -O2 \
    -pipe \
    -static \
    -D_GNU_SOURCE \
    -DVERIFYONLY \
    -DSHA2_SMALL \
    -include "$compatibility/mixtar_signify_compat.h" \
    -I"$compatibility" \
    -I"$signify_source" \
    "$signify_source/signify.c" \
    "$signify_source/crypto_api.c" \
    "$signify_source/fe25519.c" \
    "$signify_source/sc25519.c" \
    "$signify_source/mod_ed25519.c" \
    "$signify_source/mod_ge25519.c" \
    "$source_root/lib/libc/hash/sha2.c" \
    "$source_root/lib/libc/net/base64.c" \
    "$compatibility/mixtar_signify_compat.c" \
    -o "$output"

file "$output" | grep -F "statically linked" >/dev/null ||
    fail "signify artifact is not statically linked"
timeout 5 "$output" 2>"$work/usage.txt" && fail "signify accepted empty input"
grep -F "usage:" "$work/usage.txt" >/dev/null ||
    fail "signify smoke test did not reach its command parser"

printf '%s\n' "build-signify-musl: PASS"
printf '%s\n' "artifact=$output"
