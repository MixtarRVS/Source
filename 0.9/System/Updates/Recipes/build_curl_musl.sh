#!/System/Shells/zsh.apx/Program/zsh
set -eu

if (( $# != 3 )); then
    print -u2 -- "usage: build_curl_musl.sh SOURCE_DIR WORK_DIR OUTPUT_ROOT"
    exit 64
fi

source_dir=$1
work_dir=$2
output_root=$3
source_copy=$work_dir/source
build_dir=$work_dir/build
tls_prefix=/System/Libraries/LibreSSL/4.3.2
zlib_prefix=/System/Libraries/Zlib/1.3.2
cares_prefix=/System/Libraries/CAres/1.34.8
ca_bundle=/System/Configuration/TLS/cacert.pem

if [[ -z ${MIXTAR_TOOLCHAIN:-} || -z ${CC:-} || -z ${AR:-} || -z ${RANLIB:-} || -z ${LD:-} ]]; then
    print -u2 -- "build-curl-musl: toolchain environment is incomplete"
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
        print -u2 -- "build-curl-musl: missing required tool: $required"
        exit 69
    fi
done

if [[ ! -f $source_dir/configure || ! -f $source_dir/src/tool_main.c ]]; then
    print -u2 -- "build-curl-musl: invalid curl source tree: $source_dir"
    exit 66
fi

if [[ ! -f $tls_prefix/lib/libssl.a || ! -f $tls_prefix/lib/libcrypto.a || \
      ! -f $zlib_prefix/lib/libz.a || ! -f $cares_prefix/lib/libcares.a || \
      ! -f $cares_prefix/include/ares.h || ! -f $ca_bundle ]]; then
    print -u2 -- "build-curl-musl: TLS, zlib, c-ares, or CA dependency is missing"
    exit 69
fi

case $work_dir:$output_root in
    /Temporary/Updates/Work/*:/Temporary/Updates/Work/*) ;;
    *)
        print -u2 -- "build-curl-musl: work or output directory is outside the update workspace"
        exit 73
        ;;
esac

/System/Userland/rm -rf -- "$source_copy" "$build_dir" "$output_root"
/System/Userland/mkdir -p -- "$source_copy" "$build_dir" "$output_root/System/Userland"
/System/Userland/cp -Rp -- "$source_dir/." "$source_copy/"

cd "$build_dir"

CC="$CC" \
AR="$AR" \
RANLIB="$RANLIB" \
LD="$LD" \
MAKE='/System/Compilers/GNU/4.4.1/bin/gmake' \
PKG_CONFIG=/System/Userland/false \
CPPFLAGS="-I$tls_prefix/include -I$zlib_prefix/include -I$cares_prefix/include" \
CFLAGS='-O3 -fstack-protector-strong -D_FORTIFY_SOURCE=2 -Wall -Wextra' \
LDFLAGS="-static -no-pie -L$tls_prefix/lib -L$zlib_prefix/lib -L$cares_prefix/lib" \
LIBS='-lcares -lssl -lcrypto -lz -pthread' \
CONFIG_SHELL=/bin/sh \
SHELL=/bin/sh \
"$source_copy/configure" \
    --disable-shared \
    --enable-static \
    --disable-dependency-tracking \
    --disable-manual \
    --disable-docs \
    --disable-ldap \
    --disable-ldaps \
    --disable-rtsp \
    --disable-dict \
    --disable-telnet \
    --disable-tftp \
    --disable-pop3 \
    --disable-imap \
    --disable-smb \
    --disable-smtp \
    --disable-gopher \
    --disable-mqtt \
    --disable-ftp \
    --without-libpsl \
    --without-libidn2 \
    --without-brotli \
    --without-zstd \
    --without-nghttp2 \
    --without-libssh2 \
    --disable-threaded-resolver \
    --enable-ares="$cares_prefix" \
    --with-openssl="$tls_prefix" \
    --with-zlib="$zlib_prefix" \
    --with-ca-bundle="$ca_bundle"

/System/Compilers/GNU/4.4.1/bin/gmake -j2 \
    CFLAGS='-O3 -fstack-protector-strong -D_FORTIFY_SOURCE=2 -Wall -Wextra -Werror' \
    curl_LDFLAGS='-all-static' \
    SHELL=/bin/sh CONFIG_SHELL=/bin/sh

candidate=$build_dir/src/curl
if [[ ! -x $candidate ]]; then
    print -u2 -- "build-curl-musl: expected curl output was not produced"
    exit 70
fi

/System/Userland/cp -- "$candidate" "$output_root/System/Userland/curl"
/System/Userland/chmod 0755 "$output_root/System/Userland/curl"

smoke=$work_dir/smoke
/System/Userland/mkdir -p -- "$smoke"
print -- "MixtarRVS curl file smoke" >"$smoke/input.txt"
"$output_root/System/Userland/curl" --dns-servers 127.0.0.1 --fail --silent --show-error \
    "file://$smoke/input.txt" --output "$smoke/output.txt"
/System/Userland/cmp "$smoke/input.txt" "$smoke/output.txt"
"$output_root/System/Userland/curl" --version >"$work_dir/curl-version.txt"
print -- "build-curl-musl: PASS"

