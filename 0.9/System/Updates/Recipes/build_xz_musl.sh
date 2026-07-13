#!/System/Shells/zsh.apx/Program/zsh
set -eu

if (( $# != 3 )); then
    print -u2 -- "usage: build_xz_musl.sh SOURCE_DIR WORK_DIR OUTPUT_ROOT"
    exit 64
fi

source_dir=$1
work_dir=$2
output_root=$3
source_copy=$work_dir/source
build_dir=$work_dir/build
stage_dir=$work_dir/stage
library_prefix=/System/Libraries/XZ/5.8.3
install_prefix=/System/Compilers/XZ/5.8.3/bin
binary_path="$output_root$install_prefix/xz"

if [[ -z ${MIXTAR_TOOLCHAIN:-} || -z ${CC:-} || -z ${AR:-} || -z ${RANLIB:-} || -z ${LD:-} ]]; then
    print -u2 -- "build-xz-musl: toolchain environment is incomplete"
    exit 69
fi

for required in \
    /System/Compilers/GNU/4.4.1/bin/gmake \
    $MIXTAR_TOOLCHAIN \
    /System/Userland/cp \
    /System/Userland/chmod \
    /System/Userland/mkdir \
    /System/Userland/rm
do
    if [[ ! -x $required ]]; then
        print -u2 -- "build-xz-musl: missing required tool: $required"
        exit 69
    fi
done

if [[ ! -f $source_dir/configure || ! -f $source_dir/src/xz/main.c ]]; then
    print -u2 -- "build-xz-musl: invalid XZ source tree: $source_dir"
    exit 66
fi

case $work_dir in
    /Temporary/Work/*) ;;
    *)
        print -u2 -- "build-xz-musl: work directory is outside the update workspace"
        exit 73
        ;;
esac

case $output_root in
    /Temporary/Work/*) ;;
    *)
        print -u2 -- "build-xz-musl: output directory is outside the update workspace"
        exit 73
        ;;
esac

/System/Userland/rm -rf -- "$source_copy" "$build_dir" "$stage_dir" "$output_root"
/System/Userland/mkdir -p -- "$source_copy" "$build_dir" "$stage_dir" "$output_root$library_prefix/include" "$output_root$library_prefix/lib" "$output_root$install_prefix"
/System/Userland/cp -Rp -- "$source_dir/." "$source_copy/"

cd "$build_dir"

CC="$CC" \
AR="$AR" \
RANLIB="$RANLIB" \
LD="$LD" \
MAKE='/System/Compilers/GNU/4.4.1/bin/gmake' \
CFLAGS='-O3 -fstack-protector-strong -D_FORTIFY_SOURCE=2 -Wall -Wextra -Werror' \
LDFLAGS='-static' \
CONFIG_SHELL=/bin/sh \
SHELL=/bin/sh \
"$source_copy/configure" \
    --prefix="$library_prefix" \
    --disable-shared \
    --enable-static \
    --disable-nls \
    --disable-doc \
    --disable-scripts \
    --disable-xzdec \
    --disable-lzmadec \
    --disable-lzmainfo \
    --disable-dependency-tracking

/System/Compilers/GNU/4.4.1/bin/gmake -j2 SHELL=/bin/sh CONFIG_SHELL=/bin/sh
/System/Compilers/GNU/4.4.1/bin/gmake DESTDIR="$stage_dir" install SHELL=/bin/sh CONFIG_SHELL=/bin/sh

xz_binary=$stage_dir$library_prefix/bin/xz
lzma_archive=$stage_dir$library_prefix/lib/liblzma.a
lzma_headers=$stage_dir$library_prefix/include
if [[ ! -x $xz_binary || ! -f $lzma_archive || ! -d $lzma_headers/lzma ]]; then
    print -u2 -- "build-xz-musl: expected output was not produced"
    exit 70
fi

/System/Userland/cp -- "$xz_binary" "$binary_path"
/System/Userland/cp -- "$lzma_archive" "$output_root$library_prefix/lib/liblzma.a"
/System/Userland/cp -Rp -- "$lzma_headers/." "$output_root$library_prefix/include/"
/System/Userland/chmod 0755 "$binary_path"

"$binary_path" --version >"$work_dir/xz-version.txt"
print -- "build-xz-musl: PASS"

