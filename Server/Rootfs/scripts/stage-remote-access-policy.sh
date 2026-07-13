#!/bin/sh
set -u

STAGE=0009-mixtar-remote-access-policy
BASE=/System/Base/Closure/$STAGE
SYSTEM_TOOL=/System/SystemTools/mixtar-remote
REMOTE_DIR=/System/Config/RemoteAccess
RUNNER_NAME=mixtar-remote.sh
PROFILE_NAME=current.remote

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
	if [ -f "/tmp/mixtar-remote-profiles/$PROFILE_NAME" ]; then
		printf '/tmp/mixtar-remote-profiles/%s\n' "$PROFILE_NAME"
		return 0
	fi
	return 1
}

write_contract() {
	cat <<EOF
MixtarRVS remote access policy, stage 0009

Installed interface:
  /System/SystemTools/mixtar-remote

Installed profile:
  /System/Config/RemoteAccess/current.remote

Commands:
  mixtar-remote contract
  mixtar-remote check
  mixtar-remote status
  mixtar-remote profile
  mixtar-remote config
  mixtar-remote keys
  mixtar-remote listeners
  mixtar-remote backend

Current backend:
  OpenSSH sshd
  service status through mixtar-service over OpenRC
  network status through mixtar-network over dhcpcd+iwd

This stage is non-activating:
  sshd is not restarted
  /etc/ssh/sshd_config is not rewritten
  authorized_keys is not changed
  private host keys are not read
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
	if [ -f "$REMOTE_DIR/$PROFILE_NAME" ]; then
		cat "$REMOTE_DIR/$PROFILE_NAME"
	else
		printf 'missing %s/%s\n' "$REMOTE_DIR" "$PROFILE_NAME"
	fi

	printf '\n## check\n'
	"$SYSTEM_TOOL" check 2>&1 || true

	printf '\n## status\n'
	"$SYSTEM_TOOL" status 2>&1 || true

	printf '\n## backend\n'
	"$SYSTEM_TOOL" backend 2>&1 || true

	printf '\n## config\n'
	"$SYSTEM_TOOL" config 2>&1 || true

	printf '\n## keys\n'
	"$SYSTEM_TOOL" keys 2>&1 || true

	printf '\n## listeners\n'
	"$SYSTEM_TOOL" listeners 2>&1 || true
}

verify() {
	rc=0
	if [ ! -x "$SYSTEM_TOOL" ]; then
		printf 'verify: missing runner %s\n' "$SYSTEM_TOOL" >&2
		rc=1
	fi
	if [ ! -f "$REMOTE_DIR/$PROFILE_NAME" ]; then
		printf 'verify: missing profile %s/%s\n' "$REMOTE_DIR" "$PROFILE_NAME" >&2
		rc=1
	fi
	if ! "$SYSTEM_TOOL" check >/dev/null 2>&1; then
		printf 'verify: mixtar-remote check failed\n' >&2
		rc=1
	fi
	if ! "$SYSTEM_TOOL" status >/dev/null 2>&1; then
		printf 'verify: mixtar-remote status failed\n' >&2
		rc=1
	fi
	if ! /System/SystemTools/mixtar-service status sshd >/dev/null 2>&1; then
		printf 'verify: sshd service status failed\n' >&2
		rc=1
	fi
	if ! /System/SystemTools/mixtar-network check >/dev/null 2>&1; then
		printf 'verify: network status failed\n' >&2
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
		printf 'stage: missing %s next to this script or in /tmp/mixtar-remote-profiles\n' "$PROFILE_NAME" >&2
		return 1
	}
	install -d -m 0755 "$BASE" /System/SystemTools "$REMOTE_DIR"
	install -m 0755 "$runner" "$SYSTEM_TOOL"
	install -m 0644 "$profile" "$REMOTE_DIR/$PROFILE_NAME"
	write_contract > "$BASE/remote-access-contract.txt"
	"$SYSTEM_TOOL" check > "$BASE/remote-check.txt" 2>&1 || true
	"$SYSTEM_TOOL" status > "$BASE/remote-status.txt" 2>&1 || true
	"$SYSTEM_TOOL" profile > "$BASE/remote-profile.txt" 2>&1 || true
	"$SYSTEM_TOOL" config > "$BASE/remote-config.txt" 2>&1 || true
	"$SYSTEM_TOOL" keys > "$BASE/remote-keys.txt" 2>&1 || true
	"$SYSTEM_TOOL" listeners > "$BASE/remote-listeners.txt" 2>&1 || true
	"$SYSTEM_TOOL" backend > "$BASE/remote-backend.txt" 2>&1 || true
	audit > "$BASE/remote-audit.txt"
	if verify; then
		printf 'verified\n' > "$BASE/remote-access-status.txt"
	else
		printf 'incomplete\n' > "$BASE/remote-access-status.txt"
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
