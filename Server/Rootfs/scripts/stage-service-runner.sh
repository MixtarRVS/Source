#!/bin/sh
set -u

STAGE=0007-mixtar-service-runner-skeleton
BASE=/System/Base/Closure/$STAGE
SYSTEM_TOOL=/System/SystemTools/mixtar-service
SERVICE_DIR=/System/Config/Services
RUNNER_NAME=mixtar-service.sh

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

services_source() {
	dir=$(script_dir)
	if [ -d "$dir/services" ]; then
		printf '%s/services\n' "$dir"
		return 0
	fi
	if [ -d /tmp/mixtar-services ]; then
		printf '/tmp/mixtar-services\n'
		return 0
	fi
	return 1
}

write_contract() {
	cat <<EOF
MixtarRVS service runner skeleton, stage 0007

Installed interface:
  /System/SystemTools/mixtar-service

Installed manifests:
  /System/Config/Services/*.service

Commands:
  mixtar-service contract
  mixtar-service check
  mixtar-service list
  mixtar-service status <service>
  mixtar-service start <service>
  mixtar-service stop <service>

Current backend:
  OpenRC through /sbin/rc-service and /bin/rc-status

This stage is non-activating:
  no services are restarted
  no runlevels are changed
  PID 1 remains unchanged
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

	printf '\n## manifests\n'
	ls -l "$SERVICE_DIR"/*.service 2>/dev/null || true

	printf '\n## runner_check\n'
	"$SYSTEM_TOOL" check 2>&1 || true

	printf '\n## runner_list\n'
	"$SYSTEM_TOOL" list 2>&1 || true

	printf '\n## backend_status\n'
	rc-status default 2>/dev/null || true
}

verify() {
	rc=0
	if [ ! -x "$SYSTEM_TOOL" ]; then
		printf 'verify: missing runner %s\n' "$SYSTEM_TOOL" >&2
		rc=1
	fi
	if ! "$SYSTEM_TOOL" check >/dev/null 2>&1; then
		printf 'verify: runner check failed\n' >&2
		rc=1
	fi
	for service in sshd dbus wifi network boot-profiler firstboot-report realtime-tune; do
		if [ ! -f "$SERVICE_DIR/$service.service" ]; then
			printf 'verify: missing service manifest %s\n' "$service" >&2
			rc=1
		fi
	done
	for service in sshd dbus wifi network; do
		if ! "$SYSTEM_TOOL" status "$service" >/dev/null 2>&1; then
			printf 'verify: status failed for %s\n' "$service" >&2
			rc=1
		fi
	done
	return "$rc"
}

stage() {
	runner=$(runner_source) || {
		printf 'stage: missing %s next to this script or in /tmp\n' "$RUNNER_NAME" >&2
		return 1
	}
	services=$(services_source) || {
		printf 'stage: missing service manifests next to this script or in /tmp/mixtar-services\n' >&2
		return 1
	}
	install -d -m 0755 "$BASE" /System/SystemTools "$SERVICE_DIR"
	install -m 0755 "$runner" "$SYSTEM_TOOL"
	for file in "$services"/*.service; do
		[ -f "$file" ] || continue
		install -m 0644 "$file" "$SERVICE_DIR/$(basename "$file")"
	done
	write_contract > "$BASE/service-runner-contract.txt"
	"$SYSTEM_TOOL" check > "$BASE/service-runner-check.txt" 2>&1 || true
	"$SYSTEM_TOOL" list > "$BASE/service-runner-list.txt" 2>&1 || true
	for service in sshd dbus wifi network; do
		"$SYSTEM_TOOL" status "$service" > "$BASE/service-status-$service.txt" 2>&1 || true
	done
	audit > "$BASE/service-runner-audit.txt"
	if verify; then
		printf 'verified\n' > "$BASE/service-runner-status.txt"
	else
		printf 'incomplete\n' > "$BASE/service-runner-status.txt"
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
