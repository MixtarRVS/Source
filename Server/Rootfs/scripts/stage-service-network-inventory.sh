#!/bin/sh
set -u

STAGE=0006-service-and-network-closure-inventory
BASE=/System/Base/Closure/$STAGE
EXPECTED_KERNEL=7.1.2-mixtar-rt
EXPECTED_PROFILE=Profiles/rt-7.1.2-mixtar-rt

commands='openrc rc-status rc-service openrc-run dhcpcd iwd iwctl dbus-daemon sshd apk busybox ip ifconfig udhcpc wpa_supplicant'
paths='/sbin/openrc /bin/rc-status /sbin/rc-service /sbin/openrc-run /sbin/dhcpcd /usr/libexec/iwd /usr/sbin/iwd /usr/bin/iwctl /usr/bin/dbus-daemon /usr/sbin/sshd /sbin/apk /bin/busybox /sbin/ip /bin/ip /sbin/ifconfig /sbin/udhcpc /usr/sbin/wpa_supplicant /etc/init.d/iwd /etc/init.d/dhcpcd /etc/init.d/sshd /etc/init.d/dbus /etc/init.d/mixtar-boot-profiler /etc/init.d/mixtar-firstboot-report /etc/init.d/mixtar-realtime-tune'

audit_runtime() {
	printf '## stage\n'
	printf 'STAGE=%s\n' "$STAGE"
	printf 'BASE=%s\n' "$BASE"

	printf '\n## kernel\n'
	printf 'UNAME_R='
	uname -r 2>/dev/null || true
	printf 'CURRENT_KERNEL='
	readlink /System/Kernel/Current 2>/dev/null || true
	printf 'CMDLINE='
	cat /proc/cmdline 2>/dev/null || true

	printf '\n## pid1\n'
	printf 'PID1='
	cat /proc/1/comm 2>/dev/null || true
	printf 'INIT_LINK='
	ls -l /sbin/init 2>/dev/null || true
	printf 'SYSTEM_INIT_LINK='
	ls -l /System/SystemTools/init 2>/dev/null || true

	printf '\n## openrc_status\n'
	rc-status 2>/dev/null || true

	printf '\n## openrc_all\n'
	rc-status -a 2>/dev/null || true

	printf '\n## rc_update\n'
	rc-update show 2>/dev/null || true

	printf '\n## commands\n'
	for c in $commands; do
		p=$(command -v "$c" 2>/dev/null || true)
		if [ -n "$p" ]; then
			printf '%s=%s\n' "$c" "$p"
		else
			printf '%s=MISSING\n' "$c"
		fi
	done

	printf '\n## network\n'
	ip addr 2>/dev/null || true
	ip route 2>/dev/null || true

	printf '\n## resolver\n'
	cat /etc/resolv.conf 2>/dev/null || true
}

audit_owners() {
	printf '## package_owners\n'
	for p in $paths; do
		if [ -e "$p" ]; then
			printf '%s: ' "$p"
			apk info -W "$p" 2>/dev/null || true
		else
			printf '%s: MISSING\n' "$p"
		fi
	done

	printf '\n## linked_libraries\n'
	for p in /sbin/openrc /sbin/dhcpcd /usr/libexec/iwd /usr/bin/dbus-daemon /usr/sbin/sshd /sbin/apk /bin/busybox; do
		if [ -x "$p" ]; then
			printf '\n### %s\n' "$p"
			ldd "$p" 2>/dev/null || true
		fi
	done
}

write_closure_plan() {
	cat <<EOF
MixtarRVS service/network closure inventory, stage 0006

Live bootstrap responsibilities still owned by Alpine/OpenRC packages:
  service supervisor:
    openrc, rc-status, rc-service, openrc-run
  PID 1 / compatibility applets:
    busybox, /sbin/init -> /bin/busybox
  sysinit/device setup:
    devfs, procfs, sysfs, dmesg, mdev, hwdrivers
  network:
    dhcpcd for DHCP, route, resolver generation
    iwd for Wi-Fi
    busybox ip/ifconfig/udhcpc applets available
  remote access:
    OpenSSH sshd
  system bus:
    dbus-daemon
  package/bootstrap:
    apk-tools

Minimum MixtarRVS replacements before Alpine can stop being identity:
  1. Mixtar service runner:
       list/start/stop/status
       ordered startup
       shutdown hooks
       log capture
       explicit fallback to OpenRC while incomplete
  2. Mixtar runtime/device setup:
       owns or verifies /dev, /proc, /sys, /run, /tmp
       exposes /System/Devices, /System/Process, /System/Hardware
  3. Mixtar network layer:
       reads network profiles
       discovers interfaces
       invokes DHCP/static backend
       audits route and resolver state
       keeps dhcpcd as backend until replaced
  4. Mixtar Wi-Fi layer:
       owns Wi-Fi profiles/state
       uses iwd as backend until replaced
  5. Mixtar remote access policy:
       service manifest for sshd now
       future Mixtar agent optional
  6. Mixtar package/generation control:
       apk allowed as hidden backend
       user-facing identity must be Mixtar builder/generation manager
  7. D-Bus policy:
       declare dbus as base dependency, workstation dependency, or backend-only dependency

Stage 0006 is non-activating:
  it does not restart services
  it does not change runlevels
  it does not change network config
  it does not replace PID 1
EOF
}

service_started() {
	name=$1
	rc-status 2>/dev/null | grep -q "^ $name[[:space:]].*started"
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
	for path in \
		/System/Base/Closure/0001-audit/manifest.json \
		/System/Base/Closure/0002-mixtar-session-path/manifest.json \
		/System/Base/Closure/0003-shell-runtime-and-libraries-profile/manifest.json \
		/System/Base/Closure/0004-initramfs-loader-path-and-kernel-profile/manifest.json \
		/System/Base/Closure/0005-initramfs-contract-and-fallback-init-shim/manifest.json \
		/System/SystemTools/mixtar-fallback-init \
		/sbin/openrc \
		/bin/rc-status \
		/sbin/rc-service \
		/sbin/openrc-run \
		/bin/busybox \
		/sbin/init \
		/sbin/dhcpcd \
		/usr/libexec/iwd \
		/usr/bin/iwctl \
		/usr/bin/dbus-daemon \
		/usr/sbin/sshd \
		/sbin/apk
	do
		if [ ! -e "$path" ]; then
			printf 'verify: missing %s\n' "$path" >&2
			rc=1
		fi
	done
	for svc in sshd dbus iwd dhcpcd; do
		if ! service_started "$svc"; then
			printf 'verify: service not started: %s\n' "$svc" >&2
			rc=1
		fi
	done
	if ! ip route 2>/dev/null | grep -q '^default '; then
		printf 'verify: missing default route\n' >&2
		rc=1
	fi
	if ! ip addr 2>/dev/null | grep -q '192\.168\.99\.110/24'; then
		printf 'verify: expected wlan address not found\n' >&2
		rc=1
	fi
	return "$rc"
}

stage() {
	install -d -m 0755 "$BASE"
	audit_runtime > "$BASE/service-network-runtime.txt"
	audit_owners > "$BASE/service-network-owners.txt"
	write_closure_plan > "$BASE/service-network-closure-plan.txt"
	if verify; then
		printf 'verified\n' > "$BASE/service-network-status.txt"
	else
		printf 'incomplete\n' > "$BASE/service-network-status.txt"
		return 1
	fi
}

mode=${1:-}
if [ -z "$mode" ]; then
	mode=--audit
fi

case "$mode" in
	--audit)
		audit_runtime
		;;
	--owners)
		audit_owners
		;;
	--plan)
		write_closure_plan
		;;
	--verify)
		verify
		;;
	--stage)
		stage
		;;
	*)
		printf 'usage: %s [--audit|--owners|--plan|--verify|--stage]\n' "$0" >&2
		exit 2
		;;
esac
