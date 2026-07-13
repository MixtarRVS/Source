#!/bin/sh
set -u

STAGE=0005-initramfs-contract-and-fallback-init-shim
BASE=/System/Base/Closure/$STAGE
SHIM_NAME=mixtar-fallback-init.sh
SYSTEM_SHIM=/System/SystemTools/mixtar-fallback-init
EXPECTED_KERNEL=7.1.2-mixtar-rt
EXPECTED_PROFILE=Profiles/rt-7.1.2-mixtar-rt

script_dir() {
	dir=$(dirname "$0")
	cd "$dir" 2>/dev/null && pwd
}

shim_source() {
	dir=$(script_dir)
	if [ -f "$dir/$SHIM_NAME" ]; then
		printf '%s/%s\n' "$dir" "$SHIM_NAME"
		return 0
	fi
	if [ -f "/tmp/$SHIM_NAME" ]; then
		printf '/tmp/%s\n' "$SHIM_NAME"
		return 0
	fi
	return 1
}

write_contract() {
	cat <<EOF
MixtarRVS initramfs handoff contract, stage 0005

The future Mixtar-owned initramfs must:
  1. Parse /proc/cmdline and require mixtar.profile=rt-7.1.2-mixtar-rt for this profile.
  2. Mount the selected root filesystem read-only first.
  3. Mount or preserve /dev, /proc, /sys, /run, and /tmp.
  4. Expose Mixtar native runtime views:
       /System/Devices -> /dev
       /System/Process -> /proc
       /System/Hardware -> /sys
       /System/Runtime/run -> /run
       /Temporary -> /tmp
  5. Export PATH with /System/Tools/Current/bin before compatibility paths.
  6. Keep /System/Libraries/MixtarRVS/Runtime/0003/lib as the staged Mixtar runtime library root.
  7. Exec /System/SystemTools/mixtar-fallback-init --exec.
  8. Allow /System/SystemTools/mixtar-fallback-init to fall back to /sbin/init while OpenRC remains the live supervisor.

This stage does not rebuild or activate initramfs.img.
EOF
}

audit() {
	printf '## stage\n'
	printf 'STAGE=%s\n' "$STAGE"
	printf 'BASE=%s\n' "$BASE"

	printf '\n## kernel\n'
	printf 'UNAME_R='
	uname -r 2>/dev/null || true
	printf 'CMDLINE='
	cat /proc/cmdline 2>/dev/null || true
	printf 'CURRENT_KERNEL='
	readlink /System/Kernel/Current 2>/dev/null || true

	printf '\n## pid1\n'
	printf 'PID1='
	cat /proc/1/comm 2>/dev/null || true

	printf '\n## root_mount\n'
	awk '$2 == "/" { print }' /proc/mounts 2>/dev/null || true

	printf '\n## runtime_mounts\n'
	awk '$2 == "/dev" || $2 == "/proc" || $2 == "/sys" || $2 == "/run" || $2 == "/tmp" { print }' /proc/mounts 2>/dev/null || true

	printf '\n## native_runtime_views\n'
	for path in /System/Devices /System/Process /System/Hardware /System/Runtime /System/Runtime/run /Temporary; do
		if [ -e "$path" ]; then
			printf 'present %s\n' "$path"
		else
			printf 'missing %s\n' "$path"
		fi
	done

	printf '\n## handoff_tools\n'
	for path in /System/Tools/Current/bin/sh /System/Libraries/MixtarRVS/Runtime/0003/lib /System/SystemTools /sbin/init /sbin/openrc-run /usr/sbin/sshd /sbin/dhcpcd /sbin/apk; do
		if [ -e "$path" ]; then
			printf 'present %s\n' "$path"
		else
			printf 'missing %s\n' "$path"
		fi
	done

	printf '\n## initramfs_profile\n'
	for path in /System/Kernel/Current/initramfs.img /System/Kernel/Current/vmlinuz /System/Kernel/Current/modules /System/Kernel/Current/profile.json; do
		if [ -e "$path" ]; then
			ls -ld "$path"
		else
			printf 'missing %s\n' "$path"
		fi
	done
}

verify() {
	rc=0
	if [ "$(uname -r 2>/dev/null || true)" != "$EXPECTED_KERNEL" ]; then
		printf 'verify: kernel mismatch\n' >&2
		rc=1
	fi
	if [ "$(readlink /System/Kernel/Current 2>/dev/null || true)" != "$EXPECTED_PROFILE" ]; then
		printf 'verify: kernel profile mismatch\n' >&2
		rc=1
	fi
	if ! grep -q 'mixtar.profile=rt-7.1.2-mixtar-rt' /proc/cmdline 2>/dev/null; then
		printf 'verify: missing cmdline profile token\n' >&2
		rc=1
	fi
	for path in \
		/System/Base/Closure/0001-audit/manifest.json \
		/System/Base/Closure/0002-mixtar-session-path/manifest.json \
		/System/Base/Closure/0003-shell-runtime-and-libraries-profile/manifest.json \
		/System/Base/Closure/0004-initramfs-loader-path-and-kernel-profile/manifest.json \
		/System/Tools/Current/bin/sh \
		/System/Libraries/MixtarRVS/Runtime/0003/lib \
		/System/SystemTools \
		/System/SystemTools/mixtar-fallback-init \
		/System/Devices \
		/System/Process \
		/System/Hardware \
		/System/Runtime \
		/System/Runtime/run \
		/Temporary \
		/dev \
		/proc \
		/sys \
		/run \
		/tmp \
		/sbin/init
	do
		if [ ! -e "$path" ]; then
			printf 'verify: missing %s\n' "$path" >&2
			rc=1
		fi
	done
	if ! /System/SystemTools/mixtar-fallback-init --check >/dev/null 2>&1; then
		printf 'verify: shim check failed\n' >&2
		rc=1
	fi
	return "$rc"
}

stage() {
	source=$(shim_source) || {
		printf 'stage: missing %s next to this script or in /tmp\n' "$SHIM_NAME" >&2
		return 1
	}
	install -d -m 0755 "$BASE"
	install -d -m 0755 /System/SystemTools /System/Devices /System/Process /System/Hardware /System/Runtime /System/Runtime/run
	install -d -m 1777 /Temporary
	if [ "$source" != "$BASE/$SHIM_NAME" ]; then
		install -m 0755 "$source" "$BASE/$SHIM_NAME"
	fi
	install -m 0755 "$source" "$SYSTEM_SHIM"
	write_contract > "$BASE/initramfs-contract.txt"
	audit > "$BASE/runtime-initramfs-audit.txt"
	"$SYSTEM_SHIM" --contract > "$BASE/fallback-init-contract.txt"
	if "$SYSTEM_SHIM" --check > "$BASE/fallback-init-check.txt" 2>&1 && verify; then
		printf 'verified\n' > "$BASE/initramfs-contract-status.txt"
	else
		printf 'incomplete\n' > "$BASE/initramfs-contract-status.txt"
		return 1
	fi
}

mode=${1:-}
if [ -z "$mode" ]; then
	mode=--audit
fi

case "$mode" in
	--audit)
		audit
		;;
	--contract)
		write_contract
		;;
	--verify)
		verify
		;;
	--stage)
		stage
		;;
	*)
		printf 'usage: %s [--audit|--contract|--verify|--stage]\n' "$0" >&2
		exit 2
		;;
esac
