#!/usr/bin/env bash
set -euo pipefail

readonly BUSYBOX_COMMIT="${MIXTAR_BUSYBOX_COMMIT:?MIXTAR_BUSYBOX_COMMIT is required}"
readonly BUSYBOX_REPOSITORY="${MIXTAR_BUSYBOX_REPOSITORY:?MIXTAR_BUSYBOX_REPOSITORY is required}"
readonly SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:?SOURCE_DATE_EPOCH is required}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
case "$CACHE_HOME" in
	/*) ;;
	*)
		printf 'Refusing non-absolute cache home: %s\n' "$CACHE_HOME" >&2
		exit 2
		;;
esac
CACHE_HOME="$(realpath -m -- "$CACHE_HOME")"
[ "$CACHE_HOME" != / ] || {
	printf 'Refusing filesystem root as cache home\n' >&2
	exit 2
}
CACHE_ROOT="$CACHE_HOME/mixtar"
WORK="${MIXTAR_BUSYBOX_WORK:-$CACHE_ROOT/busybox}"
MIRROR="$WORK/upstream.git"
SOURCE="$WORK/source"
BUILD="$WORK/build"
STAGE="$WORK/stage"

WORK="$(realpath -m -- "$WORK")"
[ "$WORK" = "$CACHE_ROOT/busybox" ] || {
	printf 'Refusing unsafe BusyBox work directory: %s\n' "$WORK" >&2
	exit 2
}

for tool in date git make musl-gcc readelf sha256sum; do
	command -v "$tool" >/dev/null 2>&1 || {
		printf 'Missing build tool: %s\n' "$tool" >&2
		exit 2
	}
done

mkdir -p "$WORK"
if [ ! -d "$MIRROR" ]; then
	git clone --mirror "$BUSYBOX_REPOSITORY" "$MIRROR"
elif ! git --git-dir="$MIRROR" cat-file -e "$BUSYBOX_COMMIT^{commit}" 2>/dev/null; then
	git --git-dir="$MIRROR" fetch --prune origin
fi

git --git-dir="$MIRROR" cat-file -e "$BUSYBOX_COMMIT^{commit}"
rm -rf -- "$SOURCE" "$BUILD" "$STAGE"
mkdir -p "$SOURCE" "$BUILD" "$STAGE"
git --git-dir="$MIRROR" archive "$BUSYBOX_COMMIT" | tar -x -C "$SOURCE"

BUSYBOX_HEADER="$SOURCE/include/libbb.h"
grep -Fq '#define bb_dev_null "/dev/null"' "$BUSYBOX_HEADER" || {
    printf 'BusyBox no longer exposes the expected bb_dev_null constant\n' >&2
    exit 2
}
sed -i \
    's|#define bb_dev_null "/dev/null"|#define bb_dev_null "/System/Devices/null"|' \
    "$BUSYBOX_HEADER"

export ARCH=x86_64
export KBUILD_BUILD_HOST=builder
export KBUILD_BUILD_TIMESTAMP
KBUILD_BUILD_TIMESTAMP="$(date -u -d "@$SOURCE_DATE_EPOCH" '+%Y-%m-%d %H:%M:%S UTC')"
export KBUILD_BUILD_USER=mixtar
export KCONFIG_NOTIMESTAMP=1
export LC_ALL=C
export SOURCE_DATE_EPOCH

make -C "$SOURCE" O="$BUILD" allnoconfig
sed -i \
	-e 's/^# CONFIG_STATIC is not set$/CONFIG_STATIC=y/' \
	-e 's/^CONFIG_STATIC=n$/CONFIG_STATIC=y/' \
	-e 's/^CONFIG_TC=y$/# CONFIG_TC is not set/' \
	"$BUILD/.config"

mapfile -t BUSYBOX_SYMBOLS < <(
	python3 "$REPO_ROOT/Scripts/mixtar_config.py" get-list \
		components.busybox.kconfig_symbols
)
MODULES_DIRECTORY="$(
	python3 "$REPO_ROOT/Scripts/mixtar_config.py" get \
		components.busybox.modules_directory
)"
DEPMOD_FILE="$(
	python3 "$REPO_ROOT/Scripts/mixtar_config.py" get \
		components.busybox.depmod_file
)"
for symbol in "${BUSYBOX_SYMBOLS[@]}"; do
	if grep -qx "# $symbol is not set" "$BUILD/.config"; then
		sed -i "s/^# $symbol is not set$/$symbol=y/" "$BUILD/.config"
	elif ! grep -qx "$symbol=y" "$BUILD/.config"; then
		printf 'Unknown BusyBox Kconfig symbol: %s\n' "$symbol" >&2
		exit 2
	fi
done

set_string_config() {
	local symbol="$1"
	local value="$2"
	if grep -q "^$symbol=" "$BUILD/.config"; then
		sed -i "s#^$symbol=.*#$symbol=\"$value\"#" "$BUILD/.config"
	else
		printf '%s="%s"\n' "$symbol" "$value" >>"$BUILD/.config"
	fi
}
set_string_config CONFIG_DEFAULT_MODULES_DIR "$MODULES_DIRECTORY"
set_string_config CONFIG_DEFAULT_DEPMOD_FILE "$DEPMOD_FILE"

set +o pipefail
yes '' | make -C "$SOURCE" O="$BUILD" oldconfig >/dev/null
oldconfig_status=${PIPESTATUS[1]}
set -o pipefail
[ "$oldconfig_status" -eq 0 ] || exit "$oldconfig_status"

python3 "$SCRIPT_DIR/patch-busybox-native-paths.py" "$SOURCE" "$BUILD"

for required_config in \
	CONFIG_BUSYBOX \
	CONFIG_STATIC \
	CONFIG_ASH \
	CONFIG_SH_IS_ASH \
	CONFIG_MKDIR \
	CONFIG_MOUNT \
	CONFIG_MOUNTPOINT \
	CONFIG_GREP \
	CONFIG_POWEROFF \
	CONFIG_SYNC \
	CONFIG_CTTYHACK \
	CONFIG_SETSID \
	CONFIG_MODPROBE \
	CONFIG_INSMOD \
	CONFIG_RMMOD \
	CONFIG_LSMOD \
	CONFIG_DEPMOD; do
	grep -qx "$required_config=y" "$BUILD/.config" || {
		printf 'BusyBox is missing required platform option: %s\n' \
			"$required_config" >&2
		exit 1
	}
done

grep -Fqx "CONFIG_DEFAULT_MODULES_DIR=\"$MODULES_DIRECTORY\"" \
	"$BUILD/.config" || {
	printf '%s\n' 'BusyBox module directory is not Mixtar-native' >&2
	exit 1
}
grep -Fqx "CONFIG_DEFAULT_DEPMOD_FILE=\"$DEPMOD_FILE\"" \
	"$BUILD/.config" || {
	printf '%s\n' 'BusyBox depmod index name is invalid' >&2
	exit 1
}

make -C "$SOURCE" O="$BUILD" \
	CC='musl-gcc -idirafter /usr/include -idirafter /usr/include/x86_64-linux-gnu' \
	-j"${MIXTAR_JOBS:-$(nproc)}"

if readelf -l "$BUILD/busybox" | grep -q 'Requesting program interpreter'; then
	printf 'BusyBox is dynamically linked; refusing the stage.\n' >&2
	exit 1
fi

install -Dm0755 "$BUILD/busybox" "$STAGE/System/Core/BusyBox/busybox"
install -d \
	"$STAGE/System/Commands" \
	"$STAGE/System/Terminal/POSIX"

while IFS= read -r applet; do
	case "$applet" in
		ash|init|linuxrc|sh) continue ;;
	esac
	ln -s ../Core/BusyBox/busybox "$STAGE/System/Commands/$applet"
done < <("$BUILD/busybox" --list)

ln -s ../Core/BusyBox/busybox "$STAGE/System/Commands/ash"
ln -s ../Core/BusyBox/busybox "$STAGE/System/Commands/sh"
ln -s ../../Core/BusyBox/busybox "$STAGE/System/Terminal/POSIX/ash"
ln -s ../../Core/BusyBox/busybox "$STAGE/System/Terminal/POSIX/sh"

printf 'BusyBox %s staged at %s\n' \
	"$("$BUILD/busybox" | sed -n '1s/.*BusyBox v\([^ ]*\).*/\1/p')" \
	"$STAGE"
sha256sum "$STAGE/System/Core/BusyBox/busybox"
