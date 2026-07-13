#!/System/Shells/zsh.apx/Program/zsh
set -eu

if (( $# != 3 )); then
    print -u2 -- "usage: build_libressl_musl.sh SOURCE_DIR WORK_DIR OUTPUT_ROOT"
    exit 64
fi

source_dir=$1
work_dir=$2
output_root=$3
source_copy=$work_dir/source
build_dir=$work_dir/build
library_prefix=/System/Libraries/LibreSSL/4.3.2

if [[ -z ${MIXTAR_TOOLCHAIN:-} || -z ${CC:-} || -z ${AR:-} || -z ${RANLIB:-} || -z ${LD:-} ]]; then
    print -u2 -- "build-libressl-musl: toolchain environment is incomplete"
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
        print -u2 -- "build-libressl-musl: missing required tool: $required"
        exit 69
    fi
done

if [[ ! -f $source_dir/configure || ! -f $source_dir/tls/tls.c ]]; then
    print -u2 -- "build-libressl-musl: invalid LibreSSL source tree: $source_dir"
    exit 66
fi

case $work_dir:$output_root in
    /Temporary/Work/*:/Temporary/Work/*) ;;
    *)
        print -u2 -- "build-libressl-musl: work or output directory is outside the update workspace"
        exit 73
        ;;
esac

/System/Userland/rm -rf -- "$source_copy" "$build_dir" "$output_root"
/System/Userland/mkdir -p -- "$source_copy" "$build_dir" "$output_root$library_prefix/include" "$output_root$library_prefix/lib"
/System/Userland/cp -Rp -- "$source_dir/." "$source_copy/"

cd "$build_dir"

CC="$CC" \
AR="$AR" \
RANLIB="$RANLIB" \
LD="$LD" \
MAKE='/System/Compilers/GNU/4.4.1/bin/gmake' \
CFLAGS='-O3 -fstack-protector-strong -D_FORTIFY_SOURCE=2 -Wall -Wextra' \
LDFLAGS='-static' \
CONFIG_SHELL=/bin/sh \
SHELL=/bin/sh \
"$source_copy/configure" \
    --prefix="$library_prefix" \
    --disable-shared \
    --enable-static \
    --disable-dependency-tracking

/System/Compilers/GNU/4.4.1/bin/gmake -j2 \
    CFLAGS='-O3 -fstack-protector-strong -D_FORTIFY_SOURCE=2 -Wall -Wextra -Werror -Wno-error=sign-compare -Wno-error=unused-parameter -Wno-error=pointer-sign -Wno-error=unterminated-string-initialization -Wno-error=cast-function-type-mismatch -Wno-error=missing-field-initializers' \
    SHELL=/bin/sh CONFIG_SHELL=/bin/sh
/System/Compilers/GNU/4.4.1/bin/gmake check SHELL=/bin/sh CONFIG_SHELL=/bin/sh

crypto_archive=$build_dir/crypto/.libs/libcrypto.a
ssl_archive=$build_dir/ssl/.libs/libssl.a
tls_archive=$build_dir/tls/.libs/libtls.a
if [[ ! -f $crypto_archive || ! -f $ssl_archive || ! -f $tls_archive ]]; then
    print -u2 -- "build-libressl-musl: expected static libraries were not produced"
    exit 70
fi
/System/Userland/cp -- "$crypto_archive" "$output_root$library_prefix/lib/libcrypto.a"
/System/Userland/cp -- "$ssl_archive" "$output_root$library_prefix/lib/libssl.a"
/System/Userland/cp -- "$tls_archive" "$output_root$library_prefix/lib/libtls.a"

if [[ ! -f $source_copy/include/tls.h || ! -d $source_copy/include/openssl ]]; then
    print -u2 -- "build-libressl-musl: expected headers were not produced"
    exit 70
fi
/System/Userland/cp -Rp -- "$source_copy/include/." "$output_root$library_prefix/include/"
print -- "build-libressl-musl: PASS"

