#!/bin/sh
set -eu

: "${MIXTAR_OPENRC_COMMIT:?MIXTAR_OPENRC_COMMIT is required}"
: "${MIXTAR_OPENRC_REPOSITORY:?MIXTAR_OPENRC_REPOSITORY is required}"
: "${MIXTAR_JOBS:?MIXTAR_JOBS is required}"
OPENRC_COMMIT=$MIXTAR_OPENRC_COMMIT
OPENRC_REPOSITORY=$MIXTAR_OPENRC_REPOSITORY
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
CACHE_HOME=${XDG_CACHE_HOME:-"$HOME/.cache"}
case "$CACHE_HOME" in
  /*) ;;
  *)
    printf '%s\n' "Refusing non-absolute cache home: $CACHE_HOME" >&2
    exit 1
    ;;
esac
CACHE_HOME=$(realpath -m -- "$CACHE_HOME")
[ "$CACHE_HOME" != / ] || {
  printf '%s\n' "Refusing filesystem root as cache home" >&2
  exit 1
}
CACHE_ROOT="$CACHE_HOME/mixtar"
WORK=${1:-"$CACHE_ROOT/openrc"}
REPOSITORY=${2:-"$REPO_ROOT"}
MIRROR="$WORK/upstream.git"
SOURCE="$WORK/prepared-source"
BUILD="$WORK/build"
STAGE="$WORK/stage"
PATCH_DIR="$REPOSITORY/Patches/OpenRC"

WORK=$(realpath -m -- "$WORK")
[ "$WORK" = "$CACHE_ROOT/openrc" ] || {
  printf '%s\n' "Refusing unsafe OpenRC work directory: $WORK" >&2
  exit 1
}

if [ ! -d "$MIRROR" ]; then
  git clone --mirror "$OPENRC_REPOSITORY" "$MIRROR"
fi
git -C "$MIRROR" fetch --quiet origin "$OPENRC_COMMIT"
rm -rf "$SOURCE" "$BUILD" "$STAGE"
mkdir -p "$SOURCE" "$STAGE"
git -C "$MIRROR" archive "$OPENRC_COMMIT" | tar -x -C "$SOURCE"
git -C "$MIRROR" show "$OPENRC_COMMIT:LICENSE" > "$STAGE/OpenRC.LICENSE"
for patch in "$PATCH_DIR"/*.patch; do
  git -C "$SOURCE" apply --check "$patch"
  git -C "$SOURCE" apply "$patch"
done
chmod +x "$SOURCE/man/meson_man_links.sh" "$SOURCE/tools/meson_final.sh"

meson setup "$BUILD" "$SOURCE" \
  --buildtype=release \
  --prefix=/System \
  --bindir=Commands \
  --sbindir=Init \
  --libdir=Libraries \
  --libexecdir=Core \
  --sysconfdir=/System/Configuration/OpenRC \
  --localstatedir=/System/State/OpenRC \
  -Daudit=disabled \
  -Dpam=false \
  -Dselinux=disabled \
  -Dnewnet=false \
  -Dpkgconfig=false \
  -Dbash-completions=false \
  -Dzsh-completions=false \
  -Dshell=/System/Terminal/POSIX/sh \
  -Dlocal_prefix=/System/Local

meson compile -C "$BUILD" -j "$MIXTAR_JOBS"
DESTDIR="$STAGE" meson install -C "$BUILD"

grep -Ilr '^#!/bin/sh$' "$STAGE" | while IFS= read -r script; do
  sed -i '1s|^#!/bin/sh$|#!/System/Terminal/POSIX/sh|' "$script"
done

mv "$STAGE/System/Init/openrc-init" "$STAGE/System/Init/MixtarRVS"
patchelf --set-interpreter /System/Libraries/Loader/ld-linux-x86-64.so.2 \
  --set-rpath /System/Libraries "$STAGE/System/Init/MixtarRVS"

for binary in \
  "$STAGE"/System/Init/* \
  "$STAGE"/System/Commands/* \
  "$STAGE"/System/Core/rc/bin/* \
  "$STAGE"/System/Core/rc/sbin/*; do
  if file "$binary" | grep -q 'dynamically linked'; then
    patchelf --set-interpreter /System/Libraries/Loader/ld-linux-x86-64.so.2 \
      --set-rpath /System/Libraries "$binary"
  fi
done

mkdir -p "$STAGE/System/Libraries/Loader" "$STAGE/System/Runtime/OpenRC"
LIBC_SOURCE="$(cc -print-file-name=libc.so.6)"
[ -f "$LIBC_SOURCE" ] || {
	printf 'Unable to locate the build-host libc.so.6\n' >&2
	exit 2
}
cp "$LIBC_SOURCE" "$STAGE/System/Libraries/libc.so.6"
LOADER_SOURCE="$(dirname -- "$LIBC_SOURCE")/ld-linux-x86-64.so.2"
[ -f "$LOADER_SOURCE" ] || {
	printf 'Unable to locate the build-host ELF loader\n' >&2
	exit 2
}
cp "$LOADER_SOURCE" "$STAGE/System/Libraries/Loader/ld-linux-x86-64.so.2"

printf '%s\n' 'OpenRC Mixtar stage ready:'
file "$STAGE/System/Init/MixtarRVS"
