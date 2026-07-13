#!/bin/sh
set -u

STAGE=0010-package-generation-backend-boundary
BASE=/System/Base/Closure/$STAGE
SYSTEM_TOOL=/System/SystemTools/mixtar-generation
GENERATION_DIR=/System/Config/Generation
RUNNER_NAME=mixtar-generation.sh
PROFILE_NAME=current.generation

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
	if [ -f "/tmp/mixtar-generation-profiles/$PROFILE_NAME" ]; then
		printf '/tmp/mixtar-generation-profiles/%s\n' "$PROFILE_NAME"
		return 0
	fi
	return 1
}

write_contract() {
	cat <<EOF
MixtarRVS package/generation boundary, stage 0010

Installed interface:
  /System/SystemTools/mixtar-generation

Installed profile:
  /System/Config/Generation/current.generation

Commands:
  mixtar-generation contract
  mixtar-generation check
  mixtar-generation status
  mixtar-generation profile
  mixtar-generation world
  mixtar-generation repos
  mixtar-generation packages
  mixtar-generation backend
  mixtar-generation closure

Current backend:
  apk-tools as hidden compatibility backend

This stage is non-activating:
  no packages are installed
  no packages are removed
  apk upgrade is not run
  /etc/apk/world is not rewritten
  /etc/apk/repositories is not rewritten
  no new boot generation is created
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
	if [ -f "$GENERATION_DIR/$PROFILE_NAME" ]; then
		cat "$GENERATION_DIR/$PROFILE_NAME"
	else
		printf 'missing %s/%s\n' "$GENERATION_DIR" "$PROFILE_NAME"
	fi

	printf '\n## check\n'
	"$SYSTEM_TOOL" check 2>&1 || true

	printf '\n## status\n'
	"$SYSTEM_TOOL" status 2>&1 || true

	printf '\n## backend\n'
	"$SYSTEM_TOOL" backend 2>&1 || true

	printf '\n## closure\n'
	"$SYSTEM_TOOL" closure 2>&1 || true
}

verify() {
	rc=0
	if [ ! -x "$SYSTEM_TOOL" ]; then
		printf 'verify: missing runner %s\n' "$SYSTEM_TOOL" >&2
		rc=1
	fi
	if [ ! -f "$GENERATION_DIR/$PROFILE_NAME" ]; then
		printf 'verify: missing profile %s/%s\n' "$GENERATION_DIR" "$PROFILE_NAME" >&2
		rc=1
	fi
	if ! "$SYSTEM_TOOL" check >/dev/null 2>&1; then
		printf 'verify: mixtar-generation check failed\n' >&2
		rc=1
	fi
	if ! "$SYSTEM_TOOL" status >/dev/null 2>&1; then
		printf 'verify: mixtar-generation status failed\n' >&2
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
		printf 'stage: missing %s next to this script or in /tmp/mixtar-generation-profiles\n' "$PROFILE_NAME" >&2
		return 1
	}
	install -d -m 0755 "$BASE" /System/SystemTools "$GENERATION_DIR"
	install -m 0755 "$runner" "$SYSTEM_TOOL"
	install -m 0644 "$profile" "$GENERATION_DIR/$PROFILE_NAME"
	write_contract > "$BASE/package-generation-contract.txt"
	"$SYSTEM_TOOL" check > "$BASE/generation-check.txt" 2>&1 || true
	"$SYSTEM_TOOL" status > "$BASE/generation-status.txt" 2>&1 || true
	"$SYSTEM_TOOL" profile > "$BASE/generation-profile.txt" 2>&1 || true
	"$SYSTEM_TOOL" world > "$BASE/apk-world.txt" 2>&1 || true
	"$SYSTEM_TOOL" repos > "$BASE/apk-repositories.txt" 2>&1 || true
	"$SYSTEM_TOOL" packages > "$BASE/apk-packages.txt" 2>&1 || true
	"$SYSTEM_TOOL" backend > "$BASE/generation-backend.txt" 2>&1 || true
	"$SYSTEM_TOOL" closure > "$BASE/generation-closure.txt" 2>&1 || true
	audit > "$BASE/generation-audit.txt"
	if verify; then
		printf 'verified\n' > "$BASE/package-generation-status.txt"
	else
		printf 'incomplete\n' > "$BASE/package-generation-status.txt"
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
