#!/System/Shells/zsh.apx/Program/zsh
set -eu

if (( $# != 3 )); then
    print -u2 -- "usage: build_cares_musl.sh SOURCE_DIR WORK_DIR OUTPUT_ROOT"
    exit 64
fi

source_dir=$1
work_dir=$2
output_root=$3
source_copy=$work_dir/source
build_dir=$work_dir/build
install_prefix=/System/Libraries/CAres/1.34.8
staged_prefix=$output_root$install_prefix

if (( ! $+MIXTAR_TOOLCHAIN || ! $+CC || ! $+AR || ! $+RANLIB || ! $+LD )); then
    print -u2 -- "build-cares-musl: toolchain environment is incomplete"
    exit 69
fi

for required in \
    /System/Compilers/GNU/4.4.1/bin/gmake \
    $MIXTAR_TOOLCHAIN \
    /System/Userland/cp \
    /System/Userland/mkdir \
    /System/Userland/rm
do
    if [[ ! -x $required ]]; then
        print -u2 -- "build-cares-musl: missing required tool: $required"
        exit 69
    fi
done

if [[ ! -f $source_dir/configure || ! -f $source_dir/include/ares.h ]]; then
    print -u2 -- "build-cares-musl: invalid c-ares source tree: $source_dir"
    exit 66
fi

case $work_dir:$output_root in
    /Temporary/Updates/Work/*:/Temporary/Updates/Work/*) ;;
    *)
        print -u2 -- "build-cares-musl: work or output directory is outside the update workspace"
        exit 73
        ;;
esac

/System/Userland/rm -rf -- "$source_copy" "$build_dir" "$output_root"
/System/Userland/mkdir -p -- "$source_copy" "$build_dir" "$output_root"
/System/Userland/cp -Rp -- "$source_dir/." "$source_copy/"

cd "$build_dir"

CC="$CC" \
AR="$AR" \
RANLIB="$RANLIB" \
LD="$LD" \
MAKE=/System/Compilers/GNU/4.4.1/bin/gmake \
PKG_CONFIG=/System/Userland/false \
CFLAGS='-O3 -fstack-protector-strong -D_FORTIFY_SOURCE=2 -Wall -Wextra' \
LDFLAGS='-static' \
CONFIG_SHELL=/bin/sh \
SHELL=/bin/sh \
"$source_copy/configure" \
    --prefix="$install_prefix" \
    --disable-shared \
    --enable-static \
    --disable-tests

/System/Compilers/GNU/4.4.1/bin/gmake -C src/lib -j2 \
    CFLAGS='-O3 -fstack-protector-strong -D_FORTIFY_SOURCE=2 -Wall -Wextra -Werror -Wno-error=cast-qual' \
    SHELL=/bin/sh CONFIG_SHELL=/bin/sh

/System/Userland/mkdir -p -- "$staged_prefix/lib" "$staged_prefix/include"
/System/Userland/cp -- "$build_dir/src/lib/.libs/libcares.a" "$staged_prefix/lib/libcares.a"
/System/Userland/cp -- "$source_copy/include/"*.h "$staged_prefix/include/"
/System/Userland/cp -- "$build_dir/include/ares_build.h" "$staged_prefix/include/ares_build.h"

if [[ ! -f $staged_prefix/lib/libcares.a || ! -f $staged_prefix/include/ares.h ]]; then
    print -u2 -- "build-cares-musl: expected static library or public header was not produced"
    exit 70
fi

print -- "build-cares-musl: PASS"
