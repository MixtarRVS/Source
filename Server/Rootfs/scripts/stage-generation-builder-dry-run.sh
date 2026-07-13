#!/bin/sh
set -u

STAGE=0011-mixtar-generation-builder-dry-run
BASE=/System/Base/Closure/$STAGE
SYSTEM_TOOL=/System/SystemTools/mixtar-generation
RUNNER_NAME=mixtar-generation.sh

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

write_contract() {
	cat <<EOF
MixtarRVS generation builder dry-run, stage 0011

Installed interface:
  /System/SystemTools/mixtar-generation

New command:
  mixtar-generation build --dry-run

Dry-run guarantees:
  no generation directory is created
  /System/Current is not switched
  apk add/del/upgrade is not run
  /etc/apk/world is not rewritten
  /etc/apk/repositories is not rewritten
  rootfs is not rebuilt
  initramfs is not rebuilt
  bootloader state is not changed

The dry-run plan must collect:
  current generation link
  kernel profile
  Toolkit count
  apk package inventory
  apk world and repositories
  service/network/remote checks
  runtime library path
  initramfs contract presence
  image builder availability
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

	printf '\n## check\n'
	"$SYSTEM_TOOL" check 2>&1 || true

	printf '\n## dry_run\n'
	"$SYSTEM_TOOL" build --dry-run 2>&1 || true
}

verify() {
	rc=0
	if [ ! -x "$SYSTEM_TOOL" ]; then
		printf 'verify: missing runner %s\n' "$SYSTEM_TOOL" >&2
		rc=1
	fi
	if ! "$SYSTEM_TOOL" check >/dev/null 2>&1; then
		printf 'verify: mixtar-generation check failed\n' >&2
		rc=1
	fi
	if ! "$SYSTEM_TOOL" build --dry-run >/dev/null 2>&1; then
		printf 'verify: dry-run failed\n' >&2
		rc=1
	fi
	for token in \
		'plan=mixtar-generation-build' \
		'mode=dry-run' \
		'would_create_generation=false' \
		'would_activate_generation=false' \
		'toolkit_count=158' \
		'package_backend=apk' \
		'generation_check=ok generation=current' \
		'service_check=ok service-manifests=7 backend=openrc' \
		'network_check=ok profile=current interface=wlan0 backend=dhcpcd+iwd remote=sshd' \
		'remote_check=ok remote=ssh user=vxz host=192.168.99.110 port=22 backend=openssh' \
		'image_builder_ready=false' \
		'missing_image_builder=mksquashfs' \
		'dry_run_result=plan-generated'
	do
		if ! grep -F "$token" "$BASE/generation-build-dry-run.txt" >/dev/null 2>&1; then
			printf 'verify: dry-run output missing token: %s\n' "$token" >&2
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
	install -d -m 0755 "$BASE" /System/SystemTools
	install -m 0755 "$runner" "$SYSTEM_TOOL"
	write_contract > "$BASE/generation-builder-dry-run-contract.txt"
	"$SYSTEM_TOOL" check > "$BASE/generation-check.txt" 2>&1 || true
	"$SYSTEM_TOOL" build --dry-run > "$BASE/generation-build-dry-run.txt" 2>&1 || true
	audit > "$BASE/generation-builder-dry-run-audit.txt"
	if verify; then
		printf 'verified\n' > "$BASE/generation-builder-dry-run-status.txt"
	else
		printf 'incomplete\n' > "$BASE/generation-builder-dry-run-status.txt"
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
