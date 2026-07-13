#!/System/Shells/zsh.apx/Program/zsh
set -eu

if (( $# != 3 )); then
    print -u2 -- "usage: build_libgcrypt_musl.sh SOURCE_DIR WORK_DIR OUTPUT_ROOT"
    exit 64
fi

source_dir=$1
work_dir=$2
output_root=$3
source_copy=$work_dir/source
build_dir=$work_dir/build
gpg_error_prefix=/System/Libraries/LibgpgError/1.61
final_prefix=/System/Libraries/Libgcrypt/1.12.2
stage_prefix=$output_root$final_prefix

if [[ -z ${MIXTAR_TOOLCHAIN:-} || -z ${CC:-} || -z ${AR:-} || -z ${RANLIB:-} || -z ${LD:-} ]]; then
    print -u2 -- "build-libgcrypt-musl: toolchain environment is incomplete"
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
        print -u2 -- "build-libgcrypt-musl: missing required tool: $required"
        exit 69
    fi
done

if [[ ! -x $source_dir/configure || ! -f $source_dir/src/gcrypt.h.in || ! -f $source_dir/src/global.c ]]; then
    print -u2 -- "build-libgcrypt-musl: invalid libgcrypt source tree: $source_dir"
    exit 66
fi

if [[ ! -f $gpg_error_prefix/lib/libgpg-error.a || ! -f $gpg_error_prefix/include/gpg-error.h ]]; then
    print -u2 -- "build-libgcrypt-musl: libgpg-error dependency is missing"
    exit 69
fi

case $work_dir:$output_root in
    /Temporary/Work/*:/Temporary/Work/*) ;;
    *)
        print -u2 -- "build-libgcrypt-musl: work or output directory is outside the update workspace"
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
GPG_ERROR_CONFIG="$gpg_error_prefix/bin/gpg-error-config" \
CPPFLAGS="-I$gpg_error_prefix/include" \
CFLAGS='-O3 -D_FILE_OFFSET_BITS=64 -fstack-protector-strong -D_FORTIFY_SOURCE=2 -fno-sanitize=undefined -Wall -Wextra' \
LDFLAGS="-static -L$gpg_error_prefix/lib" \
LIBS='-lgpg-error -pthread' \
CONFIG_SHELL=/bin/sh \
SHELL=/bin/sh \
"$source_copy/configure" \
    --host=x86_64-linux-musl \
    --prefix="$final_prefix" \
    --disable-shared \
    --enable-static \
    --disable-doc \
    --with-libgpg-error-prefix="$gpg_error_prefix"

# The MPI ABI mixes signed limb counts with unsigned bit and limb indexes,
# the ECC sentinel table relies on C zero-filling omitted fields, and fixed
# cryptographic byte vectors deliberately omit a trailing NUL byte, and one
# McEliece helper is unused for the selected optimized implementation, and
# jitter entropy uses the valid integer-zero null pointer constant spelling,
# the upstream prime test retains a diagnostic result variable, and two test
# callbacks retain an unused key-count parameter as part of their signature,
# and the upstream benchmark initializes a const scratch array through its
# benchmark operation rather than at declaration time.
# Keep the cryptographic build sequential to bound temporary storage and retain
# every upstream test in the isolated build gate.
/System/Compilers/GNU/4.4.1/bin/gmake -j1 \
    CFLAGS='-O3 -D_FILE_OFFSET_BITS=64 -fstack-protector-strong -D_FORTIFY_SOURCE=2 -fno-sanitize=undefined -Wall -Wextra -Werror -Wno-error=sign-compare -Wno-error=missing-field-initializers -Wno-error=unterminated-string-initialization -Wno-error=unused-function -Wno-error=non-literal-null-conversion -Wno-error=unused-but-set-variable -Wno-error=unused-parameter -Wno-error=default-const-init-var-unsafe' \
    SHELL=/bin/sh CONFIG_SHELL=/bin/sh
/System/Compilers/GNU/4.4.1/bin/gmake -j1 check SHELL=/bin/sh CONFIG_SHELL=/bin/sh

if [[ ! -f $build_dir/src/.libs/libgcrypt.a || ! -f $build_dir/src/gcrypt.h ]]; then
    print -u2 -- "build-libgcrypt-musl: expected static outputs were not produced"
    exit 70
fi

/System/Userland/cp -- "$build_dir/src/.libs/libgcrypt.a" "$stage_prefix/lib/libgcrypt.a"
/System/Userland/cp -- "$build_dir/src/gcrypt.h" "$stage_prefix/include/gcrypt.h"

if [[ -f $build_dir/src/libgcrypt-config ]]; then
    /System/Userland/cp -- "$build_dir/src/libgcrypt-config" "$stage_prefix/bin/libgcrypt-config"
    /System/Userland/chmod 0755 "$stage_prefix/bin/libgcrypt-config"
fi
if [[ -f $build_dir/src/libgcrypt.pc ]]; then
    /System/Userland/cp -- "$build_dir/src/libgcrypt.pc" "$stage_prefix/lib/libgcrypt.pc"
fi

smoke_source=$work_dir/libgcrypt-smoke.c
smoke_binary=$work_dir/libgcrypt-smoke
print -r -- '#include <gcrypt.h>' >"$smoke_source"
print -r -- 'int main(void) { return gcry_check_version(GCRYPT_VERSION) ? 0 : 1; }' >>"$smoke_source"
cc_command=(${=CC})
"$cc_command[@]" -std=c23 -O3 -Wall -Wextra -Werror -pedantic -static \
    -I"$stage_prefix/include" -I"$gpg_error_prefix/include" \
    "$smoke_source" "$stage_prefix/lib/libgcrypt.a" "$gpg_error_prefix/lib/libgpg-error.a" \
    -pthread -o "$smoke_binary"
"$smoke_binary"
print -- "build-libgcrypt-musl: PASS"

