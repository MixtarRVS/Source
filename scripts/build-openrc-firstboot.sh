#!/usr/bin/env bash
set -euo pipefail

readonly SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:?SOURCE_DATE_EPOCH is required}"
readonly MIXTAR_TEST_COMMAND_LINE_KEY="${MIXTAR_TEST_COMMAND_LINE_KEY:?MIXTAR_TEST_COMMAND_LINE_KEY is required}"
readonly MIXTAR_TEST_POWEROFF_MODE="${MIXTAR_TEST_POWEROFF_MODE:?MIXTAR_TEST_POWEROFF_MODE is required}"
readonly MIXTAR_TEST_REBOOT_MODE="${MIXTAR_TEST_REBOOT_MODE:?MIXTAR_TEST_REBOOT_MODE is required}"

for value in \
	"$MIXTAR_TEST_COMMAND_LINE_KEY" \
	"$MIXTAR_TEST_POWEROFF_MODE" \
	"$MIXTAR_TEST_REBOOT_MODE"; do
	case "$value" in
		''|*[!A-Za-z0-9_.-]*)
			printf 'Invalid first-boot test value: %s\n' "$value" >&2
			exit 2
			;;
	esac
done

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
OPENRC_STAGE="${MIXTAR_OPENRC_STAGE:-$CACHE_ROOT/openrc/stage}"
BUSYBOX_STAGE="${MIXTAR_BUSYBOX_STAGE:-$CACHE_ROOT/busybox/stage}"
PLATFORM_ROOT="$REPO_ROOT/Root"
WORK="${MIXTAR_FIRSTBOOT_WORK:-$CACHE_ROOT/firstboot}"
ROOT="$WORK/root"
INITRAMFS="$WORK/MixtarRVS-firstboot.cpio.gz"

WORK="$(realpath -m -- "$WORK")"
[ "$WORK" = "$CACHE_ROOT/firstboot" ] || {
	printf 'Refusing unsafe first-boot work directory: %s\n' "$WORK" >&2
	exit 2
}

for tool in cpio find gzip sort touch; do
	command -v "$tool" >/dev/null 2>&1 || {
		printf 'Missing image tool: %s\n' "$tool" >&2
		exit 2
	}
done

for required in \
	"$OPENRC_STAGE/System/Init/MixtarRVS" \
	"$OPENRC_STAGE/System/Libraries/Loader/ld-linux-x86-64.so.2" \
	"$BUSYBOX_STAGE/System/Core/BusyBox/busybox" \
	"$BUSYBOX_STAGE/System/Terminal/POSIX/sh" \
	"$PLATFORM_ROOT/System/Core/Platform/initialize"; do
	[ -e "$required" ] || {
		printf 'Missing staged boot component: %s\n' "$required" >&2
		exit 2
	}
done

rm -rf -- "$ROOT"
mkdir -p "$ROOT"
cp -a "$OPENRC_STAGE/." "$ROOT/"
cp -a "$BUSYBOX_STAGE/." "$ROOT/"
cp -a "$PLATFORM_ROOT/." "$ROOT/"
find "$ROOT/System/Core/Platform" -type f -exec chmod 0755 {} +

RUNLEVELS="$ROOT/System/Configuration/OpenRC/runlevels"
INIT_D="$ROOT/System/Configuration/OpenRC/init.d"
for level in sysinit boot default single reboot shutdown; do
	rm -rf -- "$RUNLEVELS/$level"
	mkdir -p "$RUNLEVELS/$level"
done
rm -rf -- "$INIT_D"
mkdir -p "$INIT_D"

mkdir -p \
	"$ROOT/System/Devices" \
	"$ROOT/System/Hardware" \
	"$ROOT/System/Processes" \
	"$ROOT/System/Runtime/OpenRC" \
	"$ROOT/System/State/OpenRC" \
	"$ROOT/System/Terminal/POSIX" \
	"$ROOT/Temporary"

cat >"$ROOT/System/Configuration/OpenRC/rc.conf" <<'EOF'
rc_parallel="NO"
rc_logger="NO"
unicode="YES"
EOF

# The native platform bootstrap runs before OpenRC enters any runlevel. It is
# the single owner of Mixtar's virtual kernel filesystems and compatibility
# aliases.
cat >"$ROOT/System/Core/rc/sh/init.sh" <<'EOF'
#!/System/Terminal/POSIX/sh
/System/Core/Platform/initialize
printf '%s\n' sysinit > /System/Runtime/OpenRC/softlevel
exit 0
EOF
chmod 0755 "$ROOT/System/Core/rc/sh/init.sh"

cat >"$INIT_D/zsh-proof" <<'EOF'
#!/System/Init/openrc-run
description="Prove the Mixtar OpenRC to zsh hand-off"

depend() {
	return 0
}

start() {
	ebegin "Starting Mixtar user shell proof"
	printf '%s\n' 'MixtarRVS: OpenRC service start'
	/System/Terminal/ZSH/zsh -fc \
		'printf "MixtarRVS: zsh %s ready\n" "$ZSH_VERSION"'
	eend $?
}
EOF
chmod 0755 "$INIT_D/zsh-proof"
ln -s ../../init.d/zsh-proof "$RUNLEVELS/default/zsh-proof"

cat >"$INIT_D/firstboot-shutdown-proof" <<'EOF'
#!/System/Init/openrc-run
description="Finish an automated Mixtar shutdown proof"

depend() {
	need zsh-proof
}

start() {
	if /System/Commands/grep -qw '@MIXTAR_TEST_KEY@=@MIXTAR_REBOOT_MODE@' \
		/System/Processes/cmdline; then
		action='reboot'
		shutdown_flag='-r'
	elif /System/Commands/grep -qw '@MIXTAR_TEST_KEY@=@MIXTAR_POWEROFF_MODE@' \
		/System/Processes/cmdline; then
		action='poweroff'
		shutdown_flag='-p'
	else
		return 0
	fi

	ebegin "Completing Mixtar ${action} proof"
	printf 'MixtarRVS: requesting controlled %s\n' "$action"
	/System/Init/openrc-shutdown "$shutdown_flag" now
	eend $?
}
EOF
sed -i \
	-e "s|@MIXTAR_TEST_KEY@|$MIXTAR_TEST_COMMAND_LINE_KEY|g" \
	-e "s|@MIXTAR_REBOOT_MODE@|$MIXTAR_TEST_REBOOT_MODE|g" \
	-e "s|@MIXTAR_POWEROFF_MODE@|$MIXTAR_TEST_POWEROFF_MODE|g" \
	"$INIT_D/firstboot-shutdown-proof"
chmod 0755 "$INIT_D/firstboot-shutdown-proof"
ln -s ../../init.d/firstboot-shutdown-proof \
	"$RUNLEVELS/default/firstboot-shutdown-proof"

mknod -m 0600 "$ROOT/System/Devices/console" c 5 1
mknod -m 0666 "$ROOT/System/Devices/null" c 1 3

for forbidden_root in proc sys dev run usr etc lib var; do
	[ ! -e "$ROOT/$forbidden_root" ] || {
		printf 'Forbidden public root in initramfs: /%s\n' \
			"$forbidden_root" >&2
		exit 2
	}
done

find "$ROOT" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
mkdir -p "$WORK"
(
	cd "$ROOT"
	find . -print0 \
		| LC_ALL=C sort -z \
		| cpio --null --create --format=newc --owner=0:0 --reproducible
) | gzip -9n >"$INITRAMFS"

printf '%s\n' "$INITRAMFS"
