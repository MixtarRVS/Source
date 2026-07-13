#!/bin/sh
set -u

STAGE=0008-mixtar-network-profile-layer
BASE=/System/Base/Closure/$STAGE
SYSTEM_TOOL=/System/SystemTools/mixtar-network
NETWORK_DIR=/System/Config/Network
RUNNER_NAME=mixtar-network.sh
PROFILE_NAME=current.network

script_dir() {
	dir=$(dirname "$0")
	cd "$dir" 2>/dev/null && pwd
}

runner_source() {
	dir=$(script_dir)
	if [ -f "$dir/$RUNNER_NAME" ]; then
		printf '%s/%s\n' "$dir" "$RUNNER_NAME"
		return 0
	fi
	if [ -f "/tmp/$RUNNER_NAME" ]; then
		printf '/tmp/%s\n' "$RUNNER_NAME"
		return 0
	fi
	return 1
}

profile_source() {
	dir=$(script_dir)
	if [ -f "$dir/$PROFILE_NAME" ]; then
		printf '%s/%s\n' "$dir" "$PROFILE_NAME"
		return 0
	fi
	if [ -f "/tmp/mixtar-network-profiles/$PROFILE_NAME" ]; then
		printf '/tmp/mixtar-network-profiles/%s\n' "$PROFILE_NAME"
		return 0
	fi
	return 1
}

write_contract() {
	cat <<EOF
MixtarRVS network profile layer, stage 0008

Installed interface:
  /System/SystemTools/mixtar-network

Installed profile:
  /System/Config/Network/current.network

Commands:
  mixtar-network contract
  mixtar-network check
  mixtar-network status
  mixtar-network profile
  mixtar-network interfaces
  mixtar-network routes
  mixtar-network dns
  mixtar-network wifi
  mixtar-network backend

Current backend:
  DHCP: dhcpcd
  Wi-Fi: iwd via iwctl
  remote access: sshd
  service status: mixtar-service over OpenRC

This stage is non-activating:
  no network service is restarted
  no route or address is changed
  no Wi-Fi credential is changed
  /etc/resolv.conf is not rewritten
EOF
}

audit() {
	printf '## stage\n'
	printf 'STAGE=%s\n' "$STAGE"
	printf 'BASE=%s\n' "$BASE"

	printf '\n## runner\n'
	if [ -x "$SYSTEM_TOOL" ]; then
		ls -l "$SYSTEM_TOOL"
	else
		printf 'missing %s\n' "$SYSTEM_TOOL"
	fi

	printf '\n## profile\n'
	if [ -f "$NETWORK_DIR/$PROFILE_NAME" ]; then
		cat "$NETWORK_DIR/$PROFILE_NAME"
	else
		printf 'missing %s/%s\n' "$NETWORK_DIR" "$PROFILE_NAME"
	fi

	printf '\n## check\n'
	"$SYSTEM_TOOL" check 2>&1 || true

	printf '\n## status\n'
	"$SYSTEM_TOOL" status 2>&1 || true

	printf '\n## backend\n'
	"$SYSTEM_TOOL" backend 2>&1 || true

	printf '\n## routes\n'
	"$SYSTEM_TOOL" routes 2>&1 || true

	printf '\n## dns\n'
	"$SYSTEM_TOOL" dns 2>&1 || true
}

verify() {
	rc=0
	if [ ! -x "$SYSTEM_TOOL" ]; then
		printf 'verify: missing runner %s\n' "$SYSTEM_TOOL" >&2
		rc=1
	fi
	if [ ! -f "$NETWORK_DIR/$PROFILE_NAME" ]; then
		printf 'verify: missing profile %s/%s\n' "$NETWORK_DIR" "$PROFILE_NAME" >&2
		rc=1
	fi
	if ! "$SYSTEM_TOOL" check >/dev/null 2>&1; then
		printf 'verify: mixtar-network check failed\n' >&2
		rc=1
	fi
	if ! "$SYSTEM_TOOL" status >/dev/null 2>&1; then
		printf 'verify: mixtar-network status failed\n' >&2
		rc=1
	fi
	if ! /System/SystemTools/mixtar-service status network >/dev/null 2>&1; then
		printf 'verify: network service status failed\n' >&2
		rc=1
	fi
	if ! /System/SystemTools/mixtar-service status wifi >/dev/null 2>&1; then
		printf 'verify: wifi service status failed\n' >&2
		rc=1
	fi
	return "$rc"
}

stage() {
	runner=$(runner_source) || {
		printf 'stage: missing %s next to this script or in /tmp\n' "$RUNNER_NAME" >&2
		return 1
	}
	profile=$(profile_source) || {
		printf 'stage: missing %s next to this script or in /tmp/mixtar-network-profiles\n' "$PROFILE_NAME" >&2
		return 1
	}
	install -d -m 0755 "$BASE" /System/SystemTools "$NETWORK_DIR"
	install -m 0755 "$runner" "$SYSTEM_TOOL"
	install -m 0644 "$profile" "$NETWORK_DIR/$PROFILE_NAME"
	write_contract > "$BASE/network-profile-contract.txt"
	"$SYSTEM_TOOL" check > "$BASE/network-check.txt" 2>&1 || true
	"$SYSTEM_TOOL" status > "$BASE/network-status.txt" 2>&1 || true
	"$SYSTEM_TOOL" profile > "$BASE/network-profile.txt" 2>&1 || true
	"$SYSTEM_TOOL" interfaces > "$BASE/network-interfaces.txt" 2>&1 || true
	"$SYSTEM_TOOL" routes > "$BASE/network-routes.txt" 2>&1 || true
	"$SYSTEM_TOOL" dns > "$BASE/network-dns.txt" 2>&1 || true
	"$SYSTEM_TOOL" wifi > "$BASE/network-wifi.txt" 2>&1 || true
	"$SYSTEM_TOOL" backend > "$BASE/network-backend.txt" 2>&1 || true
	audit > "$BASE/network-audit.txt"
	if verify; then
		printf 'verified\n' > "$BASE/network-profile-status.txt"
	else
		printf 'incomplete\n' > "$BASE/network-profile-status.txt"
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
