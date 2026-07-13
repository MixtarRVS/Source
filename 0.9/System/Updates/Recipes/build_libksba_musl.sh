#!/System/Shells/zsh.apx/Program/zsh
set -eu

if (( $# != 3 )); then
    print -u2 -- "usage: build_libksba_musl.sh SOURCE_DIR WORK_DIR OUTPUT_ROOT"
    exit 64
fi

source_dir=$1
work_dir=$2
output_root=$3
source_copy=$work_dir/source
build_dir=$work_dir/build
gpg_error_prefix=/System/Libraries/LibgpgError/1.61
final_prefix=/System/Libraries/Libksba/1.8.0
stage_prefix=$output_root$final_prefix

if [[ -z ${MIXTAR_TOOLCHAIN:-} || -z ${CC:-} || -z ${AR:-} || -z ${RANLIB:-} || -z ${LD:-} ]]; then
    print -u2 -- "build-libksba-musl: toolchain environment is incomplete"
    exit 69
fi
for required in $MIXTAR_TOOLCHAIN /System/Compilers/GNU/4.4.1/bin/gmake /System/Userland/cp /System/Userland/chmod /System/Userland/mkdir /System/Userland/rm
do
    if [[ ! -x $required ]]; then
        print -u2 -- "build-libksba-musl: missing required tool: $required"
        exit 69
    fi
done
if [[ ! -x $source_dir/configure || ! -f $source_dir/src/ksba.h.in ]]; then
    print -u2 -- "build-libksba-musl: invalid libksba source tree: $source_dir"
    exit 66
fi
if [[ ! -f $gpg_error_prefix/lib/libgpg-error.a || ! -x $gpg_error_prefix/bin/gpg-error-config ]]; then
    print -u2 -- "build-libksba-musl: libgpg-error dependency is missing"
    exit 69
fi
case $work_dir:$output_root in
    /Temporary/Work/*:/Temporary/Work/*) ;;
    *) print -u2 -- "build-libksba-musl: workspace is outside /Temporary/Work"; exit 73 ;;
esac

/System/Userland/rm -rf -- "$source_copy" "$build_dir" "$output_root"
/System/Userland/mkdir -p -- "$source_copy" "$build_dir" "$stage_prefix/include" "$stage_prefix/lib" "$stage_prefix/bin"
/System/Userland/cp -Rp -- "$source_dir/." "$source_copy/"
cd "$build_dir"

CC="$CC" AR="$AR" RANLIB="$RANLIB" LD="$LD" MAKE=/System/Compilers/GNU/4.4.1/bin/gmake \
GPG_ERROR_CONFIG="$gpg_error_prefix/bin/gpg-error-config" \
CPPFLAGS="-I$gpg_error_prefix/include" \
CFLAGS='-O3 -D_FILE_OFFSET_BITS=64 -fstack-protector-strong -D_FORTIFY_SOURCE=2 -Wall -Wextra' \
LDFLAGS="-static -L$gpg_error_prefix/lib" LIBS='-lgpg-error -pthread' \
CONFIG_SHELL=/bin/sh SHELL=/bin/sh \
"$source_copy/configure" --host=x86_64-linux-musl --prefix="$final_prefix" --disable-shared --enable-static --disable-doc --disable-dependency-tracking \
    --with-libgpg-error-prefix="$gpg_error_prefix"

# libksba's BER decoder intentionally crosses unsigned wire buffers with the
# historical char-based reader/OID API and compares signed cursors with encoded
# lengths. Its generated yacc parser also maintains an error counter unused by
# this build. CMS tables intentionally use zero-filled trailing structure fields
# and fixed-width DER byte arrays without a trailing NUL. Keep every other
# warning fatal while documenting those upstream boundaries explicitly.
/System/Compilers/GNU/4.4.1/bin/gmake -j1 CFLAGS='-O3 -D_FILE_OFFSET_BITS=64 -fstack-protector-strong -D_FORTIFY_SOURCE=2 -Wall -Wextra -Werror -Wno-error=pointer-sign -Wno-error=sign-compare -Wno-error=unused-but-set-variable -Wno-error=missing-field-initializers -Wno-error=unterminated-string-initialization' SHELL=/bin/sh CONFIG_SHELL=/bin/sh
/System/Compilers/GNU/4.4.1/bin/gmake -j1 check SHELL=/bin/sh CONFIG_SHELL=/bin/sh

test_archive=$build_dir/src/.libs/libksba.a
test_header=$build_dir/src/ksba.h
test_config=$build_dir/src/ksba-config
if [[ ! -f $test_archive || ! -f $test_header || ! -f $test_config ]]; then
    print -u2 -- "build-libksba-musl: expected static outputs were not produced"
    exit 70
fi
/System/Userland/cp -- "$test_archive" "$stage_prefix/lib/libksba.a"
/System/Userland/cp -- "$test_header" "$stage_prefix/include/ksba.h"
/System/Userland/cp -- "$test_config" "$stage_prefix/bin/ksba-config"
/System/Userland/chmod 0755 "$stage_prefix/bin/ksba-config"

smoke_source=$work_dir/libksba-smoke.c
smoke_binary=$work_dir/libksba-smoke
print -r -- '#include <ksba.h>' >"$smoke_source"
print -r -- 'int main(void) { return ksba_check_version(KSBA_VERSION) ? 0 : 1; }' >>"$smoke_source"
cc_command=(${=CC})
"$cc_command[@]" -std=c23 -O3 -Wall -Wextra -Werror -pedantic -static \
    -I"$stage_prefix/include" -I"$gpg_error_prefix/include" "$smoke_source" \
    "$stage_prefix/lib/libksba.a" "$gpg_error_prefix/lib/libgpg-error.a" -pthread -o "$smoke_binary"
"$smoke_binary"
print -- "build-libksba-musl: PASS"

