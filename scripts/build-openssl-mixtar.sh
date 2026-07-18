#!/usr/bin/env bash
set -euo pipefail

readonly VERSION="${1:?OpenSSL version is required}"
readonly URL="${2:?OpenSSL URL is required}"
readonly EXPECTED="${3:?OpenSSL SHA-256 is required}"
readonly OUTPUT="${4:?output is required}"
readonly SOURCE_DATE_EPOCH="${5:?source date epoch is required}"
readonly JOBS="${6:?job count is required}"
cache="${XDG_CACHE_HOME:-$HOME/.cache}/mixtar/openssl"
archive="$cache/openssl-$VERSION.tar.gz"
source="$cache/source-$VERSION-$EXPECTED"
build="$cache/build-$VERSION-$EXPECTED"
stage="$cache/stage-$VERSION-$EXPECTED"
marker="$stage/.mixtar-openssl-complete"
mkdir -p "$cache"
download_started=$(date +%s)
if [ ! -f "$archive" ]; then
  curl -L --fail --retry 3 -o "$archive" "$URL"
fi
printf '%s  %s\n' "$EXPECTED" "$archive" | sha256sum -c -
download_seconds=$(( $(date +%s) - download_started ))
if [ ! -f "$source/Configure" ]; then
  rm -rf -- "$source"
  mkdir -p "$source"
  tar -xzf "$archive" --strip-components=1 -C "$source"
fi
build_started=$(date +%s)
if [ ! -f "$marker" ]; then
  rm -rf -- "$build" "$stage"
  mkdir -p "$build" "$stage"
  cd "$build"
  "$source/Configure" \
    linux-x86_64 no-shared no-tests no-module no-legacy \
    --prefix=/System/Security/OpenSSL \
    --openssldir=/System/Configuration/OpenSSL
  make -s -j"$JOBS" build_sw
  make -s DESTDIR="$stage" install_sw
  touch -d "@$SOURCE_DATE_EPOCH" "$marker"
fi
build_seconds=$(( $(date +%s) - build_started ))
binary="$stage/System/Security/OpenSSL/bin/openssl"
[ -x "$binary" ] || { printf '%s\n' 'OpenSSL binary is missing' >&2; exit 1; }
patchelf --set-interpreter /System/Libraries/Loader/ld-linux-x86-64.so.2 \
  --set-rpath /System/Libraries "$binary"
rm -rf -- "$OUTPUT"
mkdir -p "$OUTPUT/Root/System/Commands" "$OUTPUT/Root/System/Security/OpenSSL"
cp "$binary" "$OUTPUT/Root/System/Security/OpenSSL/openssl"
cat >"$OUTPUT/Root/System/Commands/openssl" <<'EOF'
#!/System/Terminal/POSIX/sh
exec /System/Security/OpenSSL/openssl "$@"
EOF
chmod 0755 "$OUTPUT/Root/System/Commands/openssl"
cp "$source/LICENSE.txt" "$OUTPUT/Root/System/Security/OpenSSL/LICENSE.txt"
cat >"$OUTPUT/Build.json" <<EOF
{
  "schema": "mixtar.openssl-build.v1",
  "version": "$VERSION",
  "archive_url": "$URL",
  "archive_sha256": "$EXPECTED",
  "binary_sha256": "$(sha256sum "$binary" | awk '{print $1}')",
  "download_seconds": $download_seconds,
  "build_seconds": $build_seconds
}
EOF
printf '%s\n' "$OUTPUT/Build.json"
