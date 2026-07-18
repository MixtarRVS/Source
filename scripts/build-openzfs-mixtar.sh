#!/usr/bin/env bash
set -euo pipefail

readonly VERSION="${1:?OpenZFS version is required}"
readonly ARCHIVE_URL="${2:?OpenZFS archive URL is required}"
readonly ARCHIVE_SHA256="${3:?OpenZFS archive SHA-256 is required}"
readonly LINUX_SOURCE="${4:?Linux source is required}"
readonly LINUX_BUILD="${5:?Linux build is required}"
readonly RELEASE="${6:?Linux release is required}"
readonly OUTPUT="${7:?output is required}"
readonly SOURCE_DATE_EPOCH="${8:?source date epoch is required}"
readonly JOBS="${9:?job count is required}"
readonly SIGNING_KEY="${10:-}"
readonly SIGNING_CERTIFICATE="${11:-}"
readonly MIXTAR_PATCH="${12:?Mixtar OpenZFS patch is required}"
readonly MIXTAR_PATCH_SHA256="${13:?Mixtar OpenZFS patch SHA-256 is required}"
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

case "$VERSION:$RELEASE:$JOBS" in
	*[!A-Za-z0-9._:+-]*)
		printf '%s\n' 'Invalid OpenZFS build identifier' >&2
		exit 2
		;;
esac
case "$ARCHIVE_SHA256" in
	*[!0-9a-f]*|'')
		printf '%s\n' 'Invalid OpenZFS archive SHA-256' >&2
		exit 2
		;;
esac
case "$MIXTAR_PATCH_SHA256" in
	*[!0-9a-f]*|'')
		printf '%s\n' 'Invalid Mixtar OpenZFS patch SHA-256' >&2
		exit 2
		;;
esac
[ -f "$MIXTAR_PATCH" ] || {
	printf 'Missing Mixtar OpenZFS patch: %s\n' "$MIXTAR_PATCH" >&2
	exit 2
}
for path in "$LINUX_SOURCE" "$LINUX_BUILD"; do
	[ -d "$path" ] || {
		printf 'Missing OpenZFS kernel input: %s\n' "$path" >&2
		exit 2
	}
done

for tool in curl make patch rsync sha256sum tar ldd awk sed sort; do
	command -v "$tool" >/dev/null 2>&1 || {
		printf 'Missing OpenZFS build tool: %s\n' "$tool" >&2
		exit 2
	}
done

cache="${XDG_CACHE_HOME:-$HOME/.cache}/mixtar/openzfs"
archive="$cache/zfs-$VERSION.tar.gz"
source="$cache/source-$VERSION-$ARCHIVE_SHA256-$MIXTAR_PATCH_SHA256"
config_hash="$({ grep -v '^CONFIG_INITRAMFS_' "$LINUX_BUILD/.config" || true; } | sha256sum | awk '{print $1}')"
key="$(printf '%s\n' 'mixtar-openzfs-v2' "$ARCHIVE_SHA256" "$MIXTAR_PATCH_SHA256" "$RELEASE" "$config_hash" | sha256sum | awk '{print substr($1,1,20)}')"
build="$cache/build-$key"
stage="$cache/stage-$key"
marker="$stage/.mixtar-openzfs-complete"

printf '%s  %s\n' "$MIXTAR_PATCH_SHA256" "$MIXTAR_PATCH" | sha256sum -c -
mkdir -p "$cache"
download_started=$(date +%s)
if [ ! -f "$archive" ]; then
	curl -L --fail --retry 3 -o "$archive" "$ARCHIVE_URL"
fi
printf '%s  %s\n' "$ARCHIVE_SHA256" "$archive" | sha256sum -c -
download_seconds=$(( $(date +%s) - download_started ))
build_started=$(date +%s)

if [ ! -x "$source/configure" ]; then
	rm -rf -- "$source"
	mkdir -p "$source"
	tar -xzf "$archive" --strip-components=1 -C "$source"
patch --directory="$source" --strip=1 --input="$MIXTAR_PATCH"
fi

if [ ! -f "$marker" ]; then
	rm -rf -- "$build" "$stage"
	mkdir -p "$build" "$stage"
	cd "$build"
	if ! "$source/configure" \
		--with-config=all \
		--with-linux="$LINUX_SOURCE" \
		--with-linux-obj="$LINUX_BUILD" \
		--enable-linux-experimental \
		--prefix=/System/Storage/OpenZFS \
		--sbindir=/System/Storage/OpenZFS/Commands \
		--libdir=/System/Storage/OpenZFS/Libraries \
		--sysconfdir=/System/Configuration/OpenZFS \
		--runstatedir=/System/Runtime/OpenZFS \
		--disable-systemd \
		--disable-pyzfs \
		>configure.log 2>&1; then
		tail -120 configure.log >&2
		exit 1
	fi
	if ! make -s -j"$JOBS" >build.log 2>&1; then
		tail -160 build.log >&2
		exit 1
	fi
	if ! make -s DESTDIR="$stage" install >install.log 2>&1; then
		tail -160 install.log >&2
		exit 1
	fi
	touch -d "@$SOURCE_DATE_EPOCH" "$marker"
fi

root="$OUTPUT/Root"
modules="$OUTPUT/Modules"
rm -rf -- "$OUTPUT"
mkdir -p \
	"$root/System/Commands" \
	"$root/System/Libraries/Loader" \
	"$root/System/Storage" \
	"$modules"
cp -a "$stage/System/Storage/." "$root/System/Storage/"
if [ -d "$stage/System/Configuration" ]; then
	mkdir -p "$root/System/Configuration"
	cp -a "$stage/System/Configuration/." "$root/System/Configuration/"
fi

module_root="$stage/lib/modules/$RELEASE"
[ -d "$module_root" ] || {
	printf 'OpenZFS module install is missing for Linux %s\n' "$RELEASE" >&2
	exit 1
}
rsync -a --include='*/' --include='*.ko' --exclude='*' \
	"$module_root/" "$modules/"
modules_signed=false
if [ -n "$SIGNING_KEY" ] || [ -n "$SIGNING_CERTIFICATE" ]; then
	[ -n "$SIGNING_KEY" ] && [ -n "$SIGNING_CERTIFICATE" ] || {
		printf '%s\n' 'OpenZFS signing key and certificate must be supplied together' >&2
		exit 2
	}
	bash "$REPO_ROOT/scripts/sign-kernel-modules.sh" \
		"$LINUX_BUILD/scripts/sign-file" \
		"$SIGNING_KEY" "$SIGNING_CERTIFICATE" "$modules"
	modules_signed=true
fi
module_count="$(find "$modules" -type f -name '*.ko' | wc -l)"
[ "$module_count" -gt 0 ] || {
	printf '%s\n' 'OpenZFS produced no kernel modules' >&2
	exit 1
}

openzfs_lib="$stage/System/Storage/OpenZFS/Libraries"
commands="$stage/System/Storage/OpenZFS/Commands"
for command in zpool zfs; do
	[ -x "$commands/$command" ] || {
		printf 'OpenZFS command is missing: %s\n' "$command" >&2
		exit 1
	}
done

dependency_report="$build/mixtar-ldd.txt"
LD_LIBRARY_PATH="$openzfs_lib" ldd "$commands/zpool" "$commands/zfs" \
	>"$dependency_report"
if grep -q 'not found' "$dependency_report"; then
	cat "$dependency_report" >&2
	exit 1
fi
awk '
	/=> \/.* \(/ { print $3 }
	/^[[:space:]]*\/.+ \(/ { print $1 }
' "$dependency_report" | sort -u | while IFS= read -r library; do
	[ -f "$library" ] || continue
	case "$(basename "$library")" in
		ld-linux-*.so.*)
			cp -L "$library" "$root/System/Libraries/Loader/ld-linux-x86-64.so.2"
			;;
		*)
			cp -L "$library" "$root/System/Libraries/$(basename "$library")"
			;;
	esac
done
loader="$root/System/Libraries/Loader/ld-linux-x86-64.so.2"
[ -x "$loader" ] || {
	cat "$dependency_report" >&2
	printf '%s\n' 'OpenZFS runtime loader was not packaged' >&2
	exit 1
}

for command in zpool zfs; do
	cat >"$root/System/Commands/$command" <<EOF
#!/System/Terminal/POSIX/sh
exec /System/Libraries/Loader/ld-linux-x86-64.so.2 \\
  --library-path /System/Storage/OpenZFS/Libraries:/System/Libraries \\
  /System/Storage/OpenZFS/Commands/$command "\$@"
EOF
	chmod 0755 "$root/System/Commands/$command"
done

build_seconds=$(( $(date +%s) - build_started ))
cat >"$OUTPUT/Build.json" <<EOF
{
  "schema": "mixtar.openzfs-build.v1",
  "version": "$VERSION",
  "archive_url": "$ARCHIVE_URL",
  "archive_sha256": "$ARCHIVE_SHA256",
  "mixtar_patch_sha256": "$MIXTAR_PATCH_SHA256",
  "device_namespace": "/System/Devices",
  "hardware_namespace": "/System/Hardware",
  "process_namespace": "/System/Processes",
  "hostid_path": "/System/Configuration/OpenZFS/hostid",
  "kernel_release": "$RELEASE",
  "kernel_configuration_sha256": "$config_hash",
  "experimental_kernel_compatibility": true,
  "module_count": $module_count,
  "modules_signed": $modules_signed,
  "download_seconds": $download_seconds,
  "build_seconds": $build_seconds
}
EOF
printf '%s\n' "$OUTPUT/Build.json"
