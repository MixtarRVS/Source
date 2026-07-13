#!/System/Shells/zsh.apx/Program/zsh
set -eu

if (( $# != 3 )); then
    print -u2 -- "usage: build_zlib_musl.sh SOURCE_DIR WORK_DIR OUTPUT_ROOT"
    exit 64
fi

source_dir=$1
work_dir=$2
output_root=$3
source_copy=$work_dir/source
build_dir=$work_dir/build
stage_dir=$work_dir/stage
library_prefix=/System/Libraries/Zlib/1.3.2

if [[ -z ${MIXTAR_TOOLCHAIN:-} || -z ${CC:-} || -z ${AR:-} || -z ${RANLIB:-} ]]; then
    print -u2 -- "build-zlib-musl: toolchain environment is incomplete"
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
        print -u2 -- "build-zlib-musl: missing required tool: $required"
        exit 69
    fi
done

if [[ ! -f $source_dir/configure || ! -f $source_dir/zlib.h ]]; then
    print -u2 -- "build-zlib-musl: invalid zlib source tree: $source_dir"
    exit 66
fi

case $work_dir:$output_root in
    /Temporary/Work/*:/Temporary/Work/*) ;;
    *)
        print -u2 -- "build-zlib-musl: work or output directory is outside the update workspace"
        exit 73
        ;;
esac

/System/Userland/rm -rf -- "$source_copy" "$build_dir" "$stage_dir" "$output_root"
/System/Userland/mkdir -p -- "$source_copy" "$build_dir" "$stage_dir" "$output_root$library_prefix/include" "$output_root$library_prefix/lib"
/System/Userland/cp -Rp -- "$source_dir/." "$source_copy/"

cd "$build_dir"

CC="$CC" \
AR="$AR" \
RANLIB="$RANLIB" \
CFLAGS='-O3 -fstack-protector-strong -D_FORTIFY_SOURCE=2 -Wall -Wextra -Werror' \
LDFLAGS='-static' \
"$source_copy/configure" \
    --static \
    --prefix="$library_prefix"

/System/Compilers/GNU/4.4.1/bin/gmake -j2 SHELL=/bin/sh
/System/Compilers/GNU/4.4.1/bin/gmake test SHELL=/bin/sh
/System/Compilers/GNU/4.4.1/bin/gmake DESTDIR="$stage_dir" install SHELL=/bin/sh

zlib_archive=$stage_dir$library_prefix/lib/libz.a
zlib_header=$stage_dir$library_prefix/include/zlib.h
zconf_header=$stage_dir$library_prefix/include/zconf.h
if [[ ! -f $zlib_archive || ! -f $zlib_header || ! -f $zconf_header ]]; then
    print -u2 -- "build-zlib-musl: expected output was not produced"
    exit 70
fi

/System/Userland/cp -- "$zlib_archive" "$output_root$library_prefix/lib/libz.a"
/System/Userland/cp -- "$zlib_header" "$output_root$library_prefix/include/zlib.h"
/System/Userland/cp -- "$zconf_header" "$output_root$library_prefix/include/zconf.h"
print -- "build-zlib-musl: PASS"

