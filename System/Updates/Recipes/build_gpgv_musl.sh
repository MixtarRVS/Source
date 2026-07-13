#!/System/Shells/zsh.apx/Program/zsh

emulate -L zsh
setopt ERR_EXIT NO_UNSET PIPE_FAIL

if (( $# != 3 )); then
    print -u2 -- "usage: build_gpgv_musl.sh SOURCE_DIR WORK_DIR OUTPUT_ROOT"
    exit 64
fi

source_dir=$1
work_dir=$2
output_root=$3

if [[ $source_dir != /Temporary/Work/* || $work_dir != /Temporary/Work/* || $output_root != /Temporary/Work/* ]]; then
    print -u2 -- "build-gpgv-musl: all mutable paths must stay below /Temporary/Work"
    exit 65
fi
if [[ $source_dir == /Temporary/Work || $work_dir == /Temporary/Work || $output_root == /Temporary/Work ]]; then
    print -u2 -- "build-gpgv-musl: refusing a workspace root as a mutable target"
    exit 65
fi
if [[ -z ${MIXTAR_TOOLCHAIN:-} || -z ${CC:-} || -z ${AR:-} || -z ${RANLIB:-} || -z ${LD:-} ]]; then
    print -u2 -- "build-gpgv-musl: toolchain environment is incomplete"
    exit 69
fi

for required in \
    $MIXTAR_TOOLCHAIN \
    /System/Compilers/GNU/4.4.1/bin/gmake \
    /System/Userland/cp \
    /System/Userland/chmod \
    /System/Userland/mkdir \
    /System/Userland/rm
do
    if [[ ! -x $required ]]; then
        print -u2 -- "build-gpgv-musl: missing required tool: $required"
        exit 69
    fi
done
if [[ ! -x $source_dir/configure ]]; then
    print -u2 -- "build-gpgv-musl: configure is missing from source tree"
    exit 66
fi

gpg_error_prefix=/System/Libraries/LibgpgError/1.61
gcrypt_prefix=/System/Libraries/Libgcrypt/1.12.2
assuan_prefix=/System/Libraries/Libassuan/3.0.2
ksba_prefix=/System/Libraries/Libksba/1.8.0
npth_prefix=/System/Libraries/Npth/1.8
zlib_prefix=/System/Libraries/Zlib/1.3.2

for dependency in \
    $gpg_error_prefix/lib/libgpg-error.a \
    $gcrypt_prefix/lib/libgcrypt.a \
    $assuan_prefix/lib/libassuan.a \
    $ksba_prefix/lib/libksba.a \
    $npth_prefix/lib/libnpth.a \
    $zlib_prefix/lib/libz.a
do
    if [[ ! -f $dependency ]]; then
        print -u2 -- "build-gpgv-musl: missing static dependency: $dependency"
        exit 69
    fi
done

/System/Userland/rm -rf -- "$work_dir" "$output_root"
/System/Userland/mkdir -p -- "$work_dir/source" "$work_dir/build" "$output_root/System/Userland"
/System/Userland/cp -Rp -- "$source_dir/." "$work_dir/source/"

source_copy=$work_dir/source
build_dir=$work_dir/build
configure_cflags='-O3 -D_FILE_OFFSET_BITS=64 -fstack-protector-strong -D_FORTIFY_SOURCE=2 -Wall -Wextra'
# GnuPG's table walkers use signed loop cursors against compile-time size_t
# dimensions, its historical byte typedef crosses a few char-string APIs, and
# platform-neutral signal hooks leave parameters unused on musl. Its static
# lookup tables also rely on C zero-initialization for omitted trailing fields
# and fixed-width byte alphabets without a trailing NUL. Keep those upstream
# portability warnings visible but non-fatal.
strict_cflags='-O3 -D_FILE_OFFSET_BITS=64 -fstack-protector-strong -D_FORTIFY_SOURCE=2 -Wall -Wextra -Werror -Wno-error=sign-compare -Wno-error=pointer-sign -Wno-error=unused-parameter -Wno-error=missing-field-initializers -Wno-error=unterminated-string-initialization'
dependency_cppflags="-I$gpg_error_prefix/include -I$gcrypt_prefix/include -I$assuan_prefix/include -I$ksba_prefix/include -I$npth_prefix/include -I$zlib_prefix/include"
dependency_ldflags="-static -L$gpg_error_prefix/lib -L$gcrypt_prefix/lib -L$assuan_prefix/lib -L$ksba_prefix/lib -L$npth_prefix/lib -L$zlib_prefix/lib"

cd "$build_dir"
CC="$CC" AR="$AR" RANLIB="$RANLIB" LD="$LD" MAKE=/System/Compilers/GNU/4.4.1/bin/gmake \
GPG_ERROR_CONFIG="$gpg_error_prefix/bin/gpg-error-config" \
LIBGCRYPT_CONFIG="$gcrypt_prefix/bin/libgcrypt-config" \
LIBASSUAN_CONFIG="$assuan_prefix/bin/libassuan-config" \
KSBA_CONFIG="$ksba_prefix/bin/ksba-config" \
NPTH_CONFIG="$npth_prefix/bin/npth-config" \
CPPFLAGS="$dependency_cppflags" CFLAGS="$configure_cflags" \
LDFLAGS="$dependency_ldflags" LIBS='-pthread' \
CONFIG_SHELL=/bin/sh SHELL=/bin/sh \
"$source_copy/configure" \
    --host=x86_64-linux-musl \
    --prefix=/System \
    --bindir=/System/Userland \
    --libexecdir=/System/Userland \
    --sysconfdir=/System/Configuration/GnuPG \
    --localstatedir=/System/Runtime/GnuPG \
    --datadir=/System/Resources/GnuPG \
    --disable-gpgsm \
    --disable-scdaemon \
    --disable-dirmngr \
    --disable-dirmngr-auto-start \
    --disable-keyboxd \
    --disable-doc \
    --disable-gpgtar \
    --disable-wks-tools \
    --disable-tests \
    --disable-nls \
    --disable-bzip2 \
    --disable-exec \
    --disable-photo-viewers \
    --disable-card-support \
    --disable-ccid-driver \
    --disable-sqlite \
    --disable-ntbtls \
    --disable-ldap \
    --disable-tofu \
    --disable-trust-models \
    --without-readline \
    --with-zlib="$zlib_prefix" \
    --with-libgpg-error-prefix="$gpg_error_prefix" \
    --with-libgcrypt-prefix="$gcrypt_prefix" \
    --with-libassuan-prefix="$assuan_prefix" \
    --with-ksba-prefix="$ksba_prefix" \
    --with-npth-prefix="$npth_prefix"

# Build only the internal archives needed by gpgv and the gpgv target itself.
# The full GnuPG application suite is intentionally not part of Mixtar userland.
/System/Compilers/GNU/4.4.1/bin/gmake -j1 -C common libcommonpth.a libgpgrl.a CFLAGS="$strict_cflags" SHELL=/bin/sh CONFIG_SHELL=/bin/sh
/System/Compilers/GNU/4.4.1/bin/gmake -j1 -C regexp libregexp.a CFLAGS="$strict_cflags" SHELL=/bin/sh CONFIG_SHELL=/bin/sh
/System/Compilers/GNU/4.4.1/bin/gmake -j1 -C kbx libkeybox.a CFLAGS="$strict_cflags" SHELL=/bin/sh CONFIG_SHELL=/bin/sh
/System/Compilers/GNU/4.4.1/bin/gmake -j1 -C g10 gpgv CFLAGS="$strict_cflags" SHELL=/bin/sh CONFIG_SHELL=/bin/sh

gpgv_binary=$build_dir/g10/gpgv
if [[ ! -x $gpgv_binary ]]; then
    print -u2 -- "build-gpgv-musl: gpgv target was not produced"
    exit 70
fi
"$gpgv_binary" --version
/System/Userland/cp -- "$gpgv_binary" "$output_root/System/Userland/gpgv"
/System/Userland/chmod 0755 "$output_root/System/Userland/gpgv"
print -- "build-gpgv-musl: PASS"

