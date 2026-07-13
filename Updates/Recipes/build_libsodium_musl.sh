#!/bin/sh
set -eu

fail()
{
    printf '%s\n' "build-libsodium-musl: $*" >&2
    exit 1
}

inside=0
if [ "$#" -eq 5 ] && [ "$1" = "--inside" ]; then
    inside=1
    shift
fi

[ "$#" -eq 4 ] ||
    fail "usage: build_libsodium_musl.sh ZIG SOURCE VERSION WORK"

zig=$1
source_root=$2
version=$3
work=$4

for path in "$zig" "$source_root" "$work"; do
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
    [ -f "$source_root/build.zig" ] || fail "libsodium build.zig is missing"
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
        /bin/sh "$script" --inside "$zig" "$work/source" "$version" "$work"
fi

prefix="$work/stage/System/Libraries/libsodium/$version"
cache="$work/zig-cache"
mkdir -p "$prefix" "$cache"
cd "$source_root"
ZIG_GLOBAL_CACHE_DIR="$cache" timeout 60 "$zig" build \
    -Dtarget=x86_64-linux-musl \
    -Doptimize=ReleaseSmall \
    -Dstatic=true \
    -Dshared=false \
    -Dtest=false \
    --prefix "$prefix"

[ -s "$prefix/lib/libsodium.a" ] || fail "static libsodium artifact is missing"
[ -s "$prefix/include/sodium.h" ] || fail "libsodium headers are missing"
printf '%s\n' "build-libsodium-musl: PASS"
printf '%s\n' "artifact=$prefix/lib/libsodium.a"
