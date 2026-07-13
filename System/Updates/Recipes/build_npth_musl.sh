#!/System/Shells/zsh.apx/Program/zsh
set -eu

if (( $# != 3 )); then
    print -u2 -- "usage: build_npth_musl.sh SOURCE_DIR WORK_DIR OUTPUT_ROOT"
    exit 64
fi

source_dir=$1
work_dir=$2
output_root=$3
source_copy=$work_dir/source
build_dir=$work_dir/build
final_prefix=/System/Libraries/Npth/1.8
stage_prefix=$output_root$final_prefix

if [[ -z ${MIXTAR_TOOLCHAIN:-} || -z ${CC:-} || -z ${AR:-} || -z ${RANLIB:-} || -z ${LD:-} ]]; then
    print -u2 -- "build-npth-musl: toolchain environment is incomplete"
    exit 69
fi
for required in $MIXTAR_TOOLCHAIN /System/Compilers/GNU/4.4.1/bin/gmake /System/Userland/cp /System/Userland/chmod /System/Userland/mkdir /System/Userland/rm
do
    if [[ ! -x $required ]]; then
        print -u2 -- "build-npth-musl: missing required tool: $required"
        exit 69
    fi
done
if [[ ! -x $source_dir/configure || ! -f $source_dir/src/npth.h.in ]]; then
    print -u2 -- "build-npth-musl: invalid npth source tree: $source_dir"
    exit 66
fi
case $work_dir:$output_root in
    /Temporary/Work/*:/Temporary/Work/*) ;;
    *) print -u2 -- "build-npth-musl: workspace is outside /Temporary/Work"; exit 73 ;;
esac

/System/Userland/rm -rf -- "$source_copy" "$build_dir" "$output_root"
/System/Userland/mkdir -p -- "$source_copy" "$build_dir" "$stage_prefix/include" "$stage_prefix/lib" "$stage_prefix/bin"
/System/Userland/cp -Rp -- "$source_dir/." "$source_copy/"
cd "$build_dir"

CC="$CC" AR="$AR" RANLIB="$RANLIB" LD="$LD" MAKE=/System/Compilers/GNU/4.4.1/bin/gmake \
CFLAGS='-O3 -D_FILE_OFFSET_BITS=64 -fstack-protector-strong -D_FORTIFY_SOURCE=2 -Wall -Wextra' \
LDFLAGS='-static' CONFIG_SHELL=/bin/sh SHELL=/bin/sh \
"$source_copy/configure" --host=x86_64-linux-musl --prefix="$final_prefix" \
    --disable-shared --enable-static --disable-dependency-tracking

# The result of a successful pthread cancellation probe is retained for the
# fallback path but unused when musl exposes the direct operation.  Upstream
# test thread callbacks retain the mandatory pthread argument in their ABI.
/System/Compilers/GNU/4.4.1/bin/gmake -j1 CFLAGS='-O3 -D_FILE_OFFSET_BITS=64 -fstack-protector-strong -D_FORTIFY_SOURCE=2 -Wall -Wextra -Werror -Wno-error=unused-but-set-variable -Wno-error=unused-parameter' SHELL=/bin/sh CONFIG_SHELL=/bin/sh
/System/Compilers/GNU/4.4.1/bin/gmake -j1 check SHELL=/bin/sh CONFIG_SHELL=/bin/sh

test_archive=$build_dir/src/.libs/libnpth.a
test_header=$build_dir/src/npth.h
test_config=$build_dir/npth-config
if [[ ! -f $test_archive || ! -f $test_header || ! -f $test_config ]]; then
    print -u2 -- "build-npth-musl: expected static outputs were not produced"
    exit 70
fi
/System/Userland/cp -- "$test_archive" "$stage_prefix/lib/libnpth.a"
/System/Userland/cp -- "$test_header" "$stage_prefix/include/npth.h"
/System/Userland/cp -- "$test_config" "$stage_prefix/bin/npth-config"
/System/Userland/chmod 0755 "$stage_prefix/bin/npth-config"

smoke_source=$work_dir/npth-smoke.c
smoke_binary=$work_dir/npth-smoke
print -r -- '#include <npth.h>' >"$smoke_source"
print -r -- 'int main(void) { return npth_init() == 0 ? 0 : 1; }' >>"$smoke_source"
cc_command=(${=CC})
"$cc_command[@]" -std=c23 -O3 -Wall -Wextra -Werror -pedantic -static \
    -I"$stage_prefix/include" "$smoke_source" "$stage_prefix/lib/libnpth.a" -pthread -o "$smoke_binary"
"$smoke_binary"
print -- "build-npth-musl: PASS"

