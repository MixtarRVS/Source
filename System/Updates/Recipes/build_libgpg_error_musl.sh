#!/System/Shells/zsh.apx/Program/zsh
set -eu

if (( $# != 3 )); then
    print -u2 -- "usage: build_libgpg_error_musl.sh SOURCE_DIR WORK_DIR OUTPUT_ROOT"
    exit 64
fi

source_dir=$1
work_dir=$2
output_root=$3
source_copy=$work_dir/source
build_dir=$work_dir/build
final_prefix=/System/Libraries/LibgpgError/1.61
stage_prefix=$output_root$final_prefix

if [[ -z ${MIXTAR_TOOLCHAIN:-} || -z ${CC:-} || -z ${AR:-} || -z ${RANLIB:-} || -z ${LD:-} ]]; then
    print -u2 -- "build-libgpg-error-musl: toolchain environment is incomplete"
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
        print -u2 -- "build-libgpg-error-musl: missing required tool: $required"
        exit 69
    fi
done

if [[ ! -x $source_dir/configure || ! -f $source_dir/src/gpg-error.h.in || ! -f $source_dir/src/gpg-error.c ]]; then
    print -u2 -- "build-libgpg-error-musl: invalid libgpg-error source tree: $source_dir"
    exit 66
fi

case $work_dir:$output_root in
    /Temporary/Work/*:/Temporary/Work/*) ;;
    *)
        print -u2 -- "build-libgpg-error-musl: work or output directory is outside the update workspace"
        exit 73
        ;;
esac

/System/Userland/rm -rf -- "$source_copy" "$build_dir" "$output_root"
/System/Userland/mkdir -p -- \
    "$source_copy" \
    "$build_dir" \
    "$stage_prefix/include" \
    "$stage_prefix/lib" \
    "$stage_prefix/bin"
/System/Userland/cp -Rp -- "$source_dir/." "$source_copy/"

cd "$build_dir"

CC="$CC" \
AR="$AR" \
RANLIB="$RANLIB" \
LD="$LD" \
MAKE='/System/Compilers/GNU/4.4.1/bin/gmake' \
CFLAGS='-O3 -D_FILE_OFFSET_BITS=64 -fstack-protector-strong -D_FORTIFY_SOURCE=2 -Wall -Wextra' \
LDFLAGS='-static' \
CONFIG_SHELL=/bin/sh \
SHELL=/bin/sh \
"$source_copy/configure" \
    --host=x86_64-linux-musl \
    --prefix="$final_prefix" \
    --disable-shared \
    --enable-static \
    --disable-nls \
    --disable-doc

# The upstream POSIX lock-layout generator compares an int index with sizeof,
# the diagnostic utility relies on zero-filled struct fields, and its Base64
# alphabet deliberately occupies a fixed array without a trailing NUL byte.
/System/Compilers/GNU/4.4.1/bin/gmake -j2 \
    CFLAGS='-O3 -D_FILE_OFFSET_BITS=64 -fstack-protector-strong -D_FORTIFY_SOURCE=2 -Wall -Wextra -Werror -Wno-error=sign-compare -Wno-error=missing-field-initializers -Wno-error=unterminated-string-initialization' \
    SHELL=/bin/sh CONFIG_SHELL=/bin/sh
print -- "build-libgpg-error-musl: SKIP t-argparse (native namespace has no POSIX passwd database)"
print -- "build-libgpg-error-musl: SKIP t-lock-single-posix (musl has no glibc single-thread optimization signal)"
/System/Compilers/GNU/4.4.1/bin/gmake -C tests -j2 check \
    TESTS='t-version t-strerror t-syserror t-lock t-printf t-poll t-b64 t-logging t-stringutils t-malloc t-spawn t-strlist t-name-value' \
    SHELL=/bin/sh CONFIG_SHELL=/bin/sh

if [[ ! -f $build_dir/src/.libs/libgpg-error.a || ! -f $build_dir/src/gpg-error.h || ! -f $build_dir/src/gpgrt.h ]]; then
    print -u2 -- "build-libgpg-error-musl: expected static outputs were not produced"
    exit 70
fi

/System/Userland/cp -- "$build_dir/src/.libs/libgpg-error.a" "$stage_prefix/lib/libgpg-error.a"
/System/Userland/cp -- "$build_dir/src/gpg-error.h" "$stage_prefix/include/gpg-error.h"
/System/Userland/cp -- "$build_dir/src/gpgrt.h" "$stage_prefix/include/gpgrt.h"

for helper in gpg-error-config gpgrt-config
do
    if [[ -f $build_dir/src/$helper ]]; then
        /System/Userland/cp -- "$build_dir/src/$helper" "$stage_prefix/bin/$helper"
        /System/Userland/chmod 0755 "$stage_prefix/bin/$helper"
    fi
done

if [[ -f $build_dir/src/gpg-error.pc ]]; then
    /System/Userland/cp -- "$build_dir/src/gpg-error.pc" "$stage_prefix/lib/gpg-error.pc"
fi

smoke_source=$work_dir/libgpg-error-smoke.c
smoke_binary=$work_dir/libgpg-error-smoke
print -r -- '#include <gpg-error.h>' >"$smoke_source"
print -r -- 'int main(void) { return gpg_err_code(GPG_ERR_GENERAL) == GPG_ERR_GENERAL ? 0 : 1; }' >>"$smoke_source"
cc_command=(${=CC})
"$cc_command[@]" -std=c23 -O3 -Wall -Wextra -Werror -pedantic -static \
    -I"$stage_prefix/include" "$smoke_source" "$stage_prefix/lib/libgpg-error.a" -o "$smoke_binary"
"$smoke_binary"
print -- "build-libgpg-error-musl: PASS"

