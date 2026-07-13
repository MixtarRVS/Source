#!/bin/sh
set -u

STAGE=0003-shell-runtime-and-libraries-profile
BASE=/System/Base/Closure/$STAGE
LIBROOT=/System/Libraries/MixtarRVS/Runtime/0003/lib
TOOLS=/System/Tools/MixtarRVS/bin

LIBS="/lib/ld-musl-x86_64.so.1 /usr/lib/libfts.so.0 /usr/lib/libncursesw.so.6 /usr/lib/libz.so.1 /usr/lib/libcrypto.so.3 /usr/lib/libdbus-1.so.3 /usr/lib/libexpat.so.1"

audit() {
	printf '## stage\n'
	printf 'STAGE=%s\n' "$STAGE"
	printf 'BASE=%s\n' "$BASE"
	printf 'LIBROOT=%s\n' "$LIBROOT"
	printf 'TOOLS=%s\n' "$TOOLS"

	printf '\n## required_libraries\n'
	for lib in $LIBS; do
		if [ -e "$lib" ]; then
			printf 'present %s\n' "$lib"
		else
			printf 'missing %s\n' "$lib"
		fi
	done

	printf '\n## staged_libraries\n'
	if [ -d "$LIBROOT" ]; then
		find "$LIBROOT" -maxdepth 1 -type f | sort
	fi

	printf '\n## toolkit_unique_libraries\n'
	if [ -d "$TOOLS" ]; then
		for f in "$TOOLS"/*; do
			[ -f "$f" ] || continue
			ldd "$f" 2>/dev/null || true
		done | awk '
			/=> \// || /^\t\// {
				for (i = 1; i <= NF; i++) {
					if ($i ~ /^\//) print $i
				}
			}
		' | sed 's/ (.*//' | sort -u
	fi

	printf '\n## shell_smoke\n'
	if [ -x "$TOOLS/sh" ]; then
		"$TOOLS/sh" -c 'echo SH_C_OK' >/tmp/mixtar-sh-c.out 2>/tmp/mixtar-sh-c.err
		rc_c=$?
		printf 'SH_C_RC=%s\n' "$rc_c"
		cat /tmp/mixtar-sh-c.out | sed 's/^/SH_C_OUT=/'
		cat /tmp/mixtar-sh-c.err | sed 's/^/SH_C_ERR=/'

		tmp=/tmp/mixtar-sh-script-$$.sh
		printf 'x=alpha\necho script:$x\nexit 7\n' > "$tmp"
		"$TOOLS/sh" "$tmp" >/tmp/mixtar-sh-script.out 2>/tmp/mixtar-sh-script.err
		rc_script=$?
		printf 'SH_SCRIPT_RC=%s\n' "$rc_script"
		cat /tmp/mixtar-sh-script.out | sed 's/^/SH_SCRIPT_OUT=/'
		cat /tmp/mixtar-sh-script.err | sed 's/^/SH_SCRIPT_ERR=/'
		rm -f "$tmp"
	fi
}

stage() {
	install -d -m 0755 "$BASE"
	install -d -m 0755 "$LIBROOT"
	for lib in $LIBS; do
		if [ ! -e "$lib" ]; then
			printf 'missing required library: %s\n' "$lib" >&2
			return 1
		fi
		cp -f "$lib" "$LIBROOT/"
		chmod 0755 "$LIBROOT/$(basename "$lib")"
	done
	audit > "$BASE/runtime-libraries-audit.txt"
	{
		printf '%s\n' "$LIBS"
	} | tr ' ' '\n' > "$BASE/runtime-libraries.txt"
}

case "${1:---audit}" in
	--audit)
		audit
		;;
	--stage)
		stage
		;;
	*)
		printf 'usage: %s [--audit|--stage]\n' "$0" >&2
		exit 2
		;;
esac
