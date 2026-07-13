#!/bin/sh
set -u

MIXTAR_STAGE=0002-mixtar-session-path
MIXTAR_TOOLS=/System/Tools/MixtarRVS/bin
MIXTAR_CURRENT=/System/Tools/Current/bin
MIXTAR_FALLBACK_PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
MIXTAR_PATH=$MIXTAR_CURRENT:$MIXTAR_TOOLS:$MIXTAR_FALLBACK_PATH
MIXTAR_SHELL=$MIXTAR_CURRENT/sh

export MIXTAR_STAGE
export MIXTAR_TOOLS
export MIXTAR_CURRENT
export MIXTAR_FALLBACK_PATH
export PATH=$MIXTAR_PATH
export SHELL=$MIXTAR_SHELL

mixtar_done() {
	return "$1" 2>/dev/null || exit "$1"
}

if command -v hash >/dev/null 2>&1; then
	hash -r 2>/dev/null || true
fi

print_resolution() {
	for c in sh ls uname vi login passwd mount rc-status apk openrc-run sshd dhcpcd; do
		printf '%s=' "$c"
		command -v "$c" 2>/dev/null || printf 'MISSING\n'
	done
}

case "${1:-}" in
	--check)
		printf 'MIXTAR_STAGE=%s\n' "$MIXTAR_STAGE"
		printf 'PATH=%s\n' "$PATH"
		printf 'SHELL=%s\n' "$SHELL"
		print_resolution
		mixtar_done 0
		;;
	--print-env)
		printf 'export MIXTAR_STAGE=%s\n' "$MIXTAR_STAGE"
		printf 'export MIXTAR_TOOLS=%s\n' "$MIXTAR_TOOLS"
		printf 'export MIXTAR_CURRENT=%s\n' "$MIXTAR_CURRENT"
		printf 'export PATH=%s\n' "$PATH"
		printf 'export SHELL=%s\n' "$SHELL"
		mixtar_done 0
		;;
	--shell)
		shift
		exec "$MIXTAR_SHELL" "$@"
		;;
	--)
		shift
		exec "$@"
		;;
	"")
		cat <<EOF
MixtarRVS session profile is ready.

Run checks:
  sh $0 --check

Run one command with MixtarRVS PATH first:
  sh $0 -- uname -a

Start MixtarRVS sh:
  sh $0 --shell

Source the environment into the current shell:
  . $0 --print-env
EOF
		mixtar_done 0
		;;
	*)
		exec "$@"
		;;
esac
