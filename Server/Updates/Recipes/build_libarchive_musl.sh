#!/System/Shells/zsh.apx/Program/zsh
set -eu

if (( $# != 3 )); then
    print -u2 -- "usage: build_libarchive_musl.sh SOURCE_DIR WORK_DIR OUTPUT_ROOT"
    exit 64
fi

source_dir=$1
work_dir=$2
output_root=$3
source_copy=$work_dir/source
build_dir=$work_dir/build
zlib_prefix=/System/Libraries/Zlib/1.3.2
xz_prefix=/System/Libraries/XZ/5.8.3
archive_prefix=/System/Compilers/BSDTar/3.8.8
binary_path="$output_root$archive_prefix/bin/bsdtar"

if [[ -z ${MIXTAR_TOOLCHAIN:-} || -z ${CC:-} || -z ${AR:-} || -z ${RANLIB:-} || -z ${LD:-} ]]; then
    print -u2 -- "build-libarchive-musl: toolchain environment is incomplete"
    exit 69
fi

for required in \
    /System/Compilers/GNU/4.4.1/bin/gmake \
    $MIXTAR_TOOLCHAIN \
    /System/Userland/cp \
    /System/Userland/chmod \
    /System/Userland/cmp \
    /System/Userland/mkdir \
    /System/Userland/rm
do
    if [[ ! -x $required ]]; then
        print -u2 -- "build-libarchive-musl: missing required tool: $required"
        exit 69
    fi
done

if [[ ! -f $source_dir/configure || ! -f $source_dir/tar/bsdtar.c ]]; then
    print -u2 -- "build-libarchive-musl: invalid libarchive source tree: $source_dir"
    exit 66
fi

if [[ ! -f $zlib_prefix/lib/libz.a || ! -f $xz_prefix/lib/liblzma.a ]]; then
    print -u2 -- "build-libarchive-musl: static compression dependencies are missing"
    exit 69
fi

case $work_dir:$output_root in
    /Temporary/Work/*:/Temporary/Work/*) ;;
    *)
        print -u2 -- "build-libarchive-musl: work or output directory is outside the update workspace"
        exit 73
        ;;
esac

/System/Userland/rm -rf -- "$source_copy" "$build_dir" "$output_root"
/System/Userland/mkdir -p -- "$source_copy" "$build_dir" "$output_root$archive_prefix/bin" "$work_dir/smoke"
/System/Userland/cp -Rp -- "$source_dir/." "$source_copy/"

cd "$build_dir"

CC="$CC" \
AR="$AR" \
RANLIB="$RANLIB" \
LD="$LD" \
MAKE='/System/Compilers/GNU/4.4.1/bin/gmake' \
CPPFLAGS="-I$zlib_prefix/include -I$xz_prefix/include" \
CFLAGS='-O3 -fstack-protector-strong -D_FORTIFY_SOURCE=2 -Wall -Wextra' \
LDFLAGS="-static -L$zlib_prefix/lib -L$xz_prefix/lib" \
LIBS='-llzma -lz -pthread' \
PKG_CONFIG=/System/Userland/false \
CONFIG_SHELL=/bin/sh \
SHELL=/bin/sh \
"$source_copy/configure" \
    --prefix=/System/Libraries/Libarchive/3.8.8 \
    --disable-shared \
    --enable-static \
    --disable-dependency-tracking \
    --disable-bsdcat \
    --disable-bsdcpio \
    --disable-bsdunzip \
    --without-bz2lib \
    --without-lz4 \
    --without-zstd \
    --without-openssl \
    --without-xml2 \
    --without-expat

/System/Compilers/GNU/4.4.1/bin/gmake -j2 bsdtar \
    CFLAGS='-O3 -fstack-protector-strong -D_FORTIFY_SOURCE=2 -Wall -Wextra -Werror -Wno-error=unused-variable' \
    SHELL=/bin/sh CONFIG_SHELL=/bin/sh

candidate=$build_dir/bsdtar
if [[ ! -x $candidate ]]; then
    print -u2 -- "build-libarchive-musl: expected bsdtar output was not produced"
    exit 70
fi

/System/Userland/cp -- "$candidate" "$binary_path"
/System/Userland/chmod 0755 "$binary_path"

smoke=$work_dir/smoke
/System/Userland/mkdir -p -- "$smoke/input" "$smoke/gzip" "$smoke/xz"
print -- "MixtarRVS archive smoke" >"$smoke/input/payload.txt"
"$binary_path" -czf "$smoke/payload.tar.gz" -C "$smoke/input" payload.txt
"$binary_path" -xzf "$smoke/payload.tar.gz" -C "$smoke/gzip"
/System/Userland/cmp "$smoke/input/payload.txt" "$smoke/gzip/payload.txt"
"$binary_path" -cJf "$smoke/payload.tar.xz" -C "$smoke/input" payload.txt
"$binary_path" -xJf "$smoke/payload.tar.xz" -C "$smoke/xz"
/System/Userland/cmp "$smoke/input/payload.txt" "$smoke/xz/payload.txt"

print -- "build-libarchive-musl: PASS"

