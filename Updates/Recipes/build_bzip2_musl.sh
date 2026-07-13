#!/System/Shells/zsh.apx/Program/zsh
set -eu

if (( $# != 3 )); then
    print -u2 -- "usage: build_bzip2_musl.sh SOURCE_DIR WORK_DIR OUTPUT_ROOT"
    exit 64
fi

source_dir=$1
work_dir=$2
output_root=$3
source_copy=$work_dir/source
build_dir=$work_dir/build
library_prefix=$output_root/System/Libraries/Bzip2/1.0.8

if [[ -z ${MIXTAR_TOOLCHAIN:-} || -z ${CC:-} || -z ${AR:-} || -z ${RANLIB:-} ]]; then
    print -u2 -- "build-bzip2-musl: toolchain environment is incomplete"
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
        print -u2 -- "build-bzip2-musl: missing required tool: $required"
        exit 69
    fi
done

if [[ ! -f $source_dir/Makefile || ! -f $source_dir/bzip2.c || ! -f $source_dir/bzlib.c || ! -f $source_dir/bzlib.h ]]; then
    print -u2 -- "build-bzip2-musl: invalid bzip2 source tree: $source_dir"
    exit 66
fi

case $work_dir:$output_root in
    /Temporary/Work/*:/Temporary/Work/*) ;;
    *)
        print -u2 -- "build-bzip2-musl: work or output directory is outside the update workspace"
        exit 73
        ;;
esac

/System/Userland/rm -rf -- "$source_copy" "$build_dir" "$output_root"
/System/Userland/mkdir -p -- \
    "$source_copy" \
    "$build_dir" \
    "$output_root/System/Userland" \
    "$library_prefix/include" \
    "$library_prefix/lib"
/System/Userland/cp -Rp -- "$source_dir/." "$source_copy/"
/System/Userland/cp -Rp -- "$source_copy/." "$build_dir/"

cd "$build_dir"

# bzip2 1.0.8 keeps unused callback parameters as part of its public ABI.
/System/Compilers/GNU/4.4.1/bin/gmake -j2 bzip2 libbz2.a \
    CC="$CC" \
    AR="$AR" \
    RANLIB="$RANLIB" \
    CFLAGS='-O3 -D_FILE_OFFSET_BITS=64 -fstack-protector-strong -D_FORTIFY_SOURCE=2 -Wall -Wextra -Werror -Wno-error=unused-parameter' \
    LDFLAGS='-static' \
    SHELL=/bin/sh

if [[ ! -x $build_dir/bzip2 || ! -f $build_dir/libbz2.a ]]; then
    print -u2 -- "build-bzip2-musl: expected static outputs were not produced"
    exit 70
fi

/System/Userland/cp -- "$build_dir/bzip2" "$output_root/System/Userland/bzip2"
/System/Userland/chmod 0755 "$output_root/System/Userland/bzip2"
/System/Userland/cp -- "$build_dir/libbz2.a" "$library_prefix/lib/libbz2.a"
/System/Userland/cp -- "$build_dir/bzlib.h" "$library_prefix/include/bzlib.h"

smoke=$work_dir/smoke
/System/Userland/mkdir -p -- "$smoke"
print -- "MixtarRVS bzip2 source-native smoke" >"$smoke/input.txt"
"$output_root/System/Userland/bzip2" -c "$smoke/input.txt" >"$smoke/input.txt.bz2"
"$output_root/System/Userland/bzip2" -dc "$smoke/input.txt.bz2" >"$smoke/output.txt"
/System/Userland/cmp "$smoke/input.txt" "$smoke/output.txt"
"$output_root/System/Userland/bzip2" -t "$smoke/input.txt.bz2"
"$output_root/System/Userland/bzip2" --version >"$work_dir/bzip2-version.txt" 2>&1
print -- "build-bzip2-musl: PASS"

