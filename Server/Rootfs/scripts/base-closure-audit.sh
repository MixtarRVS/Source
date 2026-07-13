#!/bin/sh
set -u

printf '## identity\n'
uname -a 2>/dev/null || true
cat /etc/os-release 2>/dev/null || true
cat /etc/alpine-release 2>/dev/null | sed 's/^/alpine-release=/' || true
if command -v mixtar-release >/dev/null 2>&1; then
	mixtar-release 2>/dev/null || true
fi

printf '\n## path\n'
printf 'PATH=%s\n' "$PATH"

printf '\n## mixtar_tools\n'
if [ -d /System/Tools/MixtarRVS/bin ]; then
	find /System/Tools/MixtarRVS/bin -maxdepth 1 -type f | wc -l | tr -d ' '
	printf '\n'
fi
ls -ld /System /System/Tools /System/Tools/MixtarRVS /System/Tools/Current 2>/dev/null || true

printf '\n## command_resolution\n'
for c in sh ls uname vi ex rc-status apk openrc-run init sshd dhcpcd iwd dbus-daemon login passwd mount; do
	printf '%s=' "$c"
	command -v "$c" 2>/dev/null || printf 'MISSING\n'
done

printf '\n## runtime_linking\n'
for c in ls sh vi login passwd init sshd dhcpcd iwd; do
	p=$(command -v "$c" 2>/dev/null || true)
	if [ -n "$p" ] && [ -e "$p" ]; then
		printf -- '-- %s -> %s\n' "$c" "$p"
		ldd "$p" 2>&1 | sed 's/^/  /' | head -20
	fi
done

printf '\n## mounts\n'
mount 2>/dev/null || true

printf '\n## fstab_inittab\n'
printf -- '-- /etc/fstab\n'
cat /etc/fstab 2>/dev/null || true
printf -- '-- /etc/inittab\n'
cat /etc/inittab 2>/dev/null || true

printf '\n## boot\n'
ls -lah /boot 2>/dev/null || true
find /boot -maxdepth 2 -type f 2>/dev/null | sort || true

printf '\n## services\n'
rc-status 2>/dev/null || true

printf '\n## runlevels\n'
find /etc/runlevels -maxdepth 2 \( -type l -o -type f \) 2>/dev/null | sort || true

printf '\n## network\n'
ip addr 2>/dev/null || true
ip route 2>/dev/null || true

printf '\n## processes\n'
ps 2>/dev/null || true
