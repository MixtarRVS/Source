#!/bin/sh
set -eu

fail()
{
    printf '%s\n' "build-minisign-musl: $*" >&2
    exit 1
}

inside=0
if [ "$#" -eq 6 ] && [ "$1" = "--inside" ]; then
    inside=1
    shift
fi

[ "$#" -eq 5 ] ||
    fail "usage: build_minisign_musl.sh ZIG SOURCE SODIUM VERSION WORK"

zig=$1
source_root=$2
sodium_root=$3
version=$4
work=$5

for path in "$zig" "$source_root" "$sodium_root" "$work"; do
    case "$path" in
        /*) ;;
        *) fail "all paths must be absolute" ;;
    esac
done
case "$version" in
    ''|*[!0-9A-Za-z.-]*) fail "invalid version" ;;
esac

script=$0
case "$script" in
    /*) ;;
    *) script=$(pwd)/$script ;;
esac

if [ "$inside" -eq 0 ]; then
    command -v bwrap >/dev/null 2>&1 || fail "bubblewrap is required"
    [ -x "$zig" ] || fail "Zig executable is missing"
    [ -f "$source_root/src/minisign.c" ] || fail "minisign source is missing"
    [ -s "$sodium_root/lib/libsodium.a" ] || fail "static libsodium is missing"
    [ ! -e "$work" ] || fail "work path already exists"
    mkdir -p "$work/source"
    cp -a "$source_root/." "$work/source/"
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
        /bin/sh "$script" --inside "$zig" "$work/source" "$sodium_root" "$version" "$work"
fi

output_root="$work/stage/System/Compilers/minisign/$version"
output="$output_root/minisign"
cache="$work/zig-cache"
mkdir -p "$output_root" "$cache"
cd "$source_root"
ZIG_GLOBAL_CACHE_DIR="$cache" timeout 30 "$zig" cc \
    -target x86_64-linux-musl \
    -static \
    -O3 \
    -D_GNU_SOURCE \
    -Isrc \
    -I"$sodium_root/include" \
    src/base64.c \
    src/get_line.c \
    src/helpers.c \
    src/minisign.c \
    "$sodium_root/lib/libsodium.a" \
    -lpthread \
    -Wl,--strip-all \
    -o "$output"

[ -s "$output" ] || fail "minisign artifact is missing"
version_output=$(timeout 5 "$output" -v 2>&1) || fail "minisign smoke test failed"
printf '%s\n' "$version_output" | grep -F "minisign $version" >/dev/null ||
    fail "unexpected minisign version"
printf '%s\n' "build-minisign-musl: PASS"
printf '%s\n' "artifact=$output"
