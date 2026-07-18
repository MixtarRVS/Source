#!/usr/bin/env bash
set -euo pipefail

readonly OPENRC_COMMIT="a63d68f5c1e250ebdf9ff2c848add4dcba430ea2"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
CACHE_ROOT="${XDG_CACHE_HOME:-$HOME/.cache}/mixtar"
MIRROR="$CACHE_ROOT/openrc/upstream.git"
OUTPUT="$REPO_ROOT/Patches/OpenRC/0003-mixtar-virtual-filesystems.patch"
SOURCE="$(mktemp -d "$CACHE_ROOT/openrc-paths.XXXXXX")"

cleanup() {
	rm -rf -- "$SOURCE"
}
trap cleanup EXIT

[ -d "$MIRROR" ] || {
	printf 'Missing OpenRC mirror: %s\n' "$MIRROR" >&2
	exit 2
}

git --git-dir="$MIRROR" archive "$OPENRC_COMMIT" | tar -x -C "$SOURCE"
git -C "$SOURCE" init -q
git -C "$SOURCE" add .
git -C "$SOURCE" -c user.name=Mixtar \
	-c user.email=builder@mixtar.invalid commit -qm upstream

git -C "$SOURCE" apply "$REPO_ROOT/Patches/OpenRC/0001-mixtar-layout.patch"
git -C "$SOURCE" apply "$REPO_ROOT/Patches/OpenRC/0002-direct-gendep-exec.patch"
git -C "$SOURCE" add .
git -C "$SOURCE" -c user.name=Mixtar \
	-c user.email=builder@mixtar.invalid commit -qm prerequisites

while IFS= read -r -d '' file; do
	if grep -Iq . "$file" && grep -Eq '/proc|/sys|/dev|/run|/var/run|/usr/(local/)?lib/binfmt\.d|/etc/binfmt\.d' "$file"; then
		perl -0pi -e '
			s{binfmt_dirs=\x27/usr/lib/binfmt\.d/ /usr/local/lib/binfmt\.d/ /System/Runtime/binfmt\.d/ /etc/binfmt\.d/\x27}{binfmt_dirs=\x27/System/Configuration/Binfmt/ /System/Runtime/Binfmt/\x27}g;
			s{/usr/(?:local/)?lib/binfmt\.d}{/System/Configuration/Binfmt}g;
			s{/etc/binfmt\.d}{/System/Configuration/Binfmt}g;
			s{/System/Runtime/binfmt\.d}{/System/Runtime/Binfmt}g;
			s{(?<![A-Za-z0-9_])/var/run(?=$|[/"\x27\s;,)])}{/System/Runtime}g;
			s{(?<![A-Za-z0-9_])/proc(?=$|[/"\x27\s;,)])}{/System/Processes}g;
			s{(?<![A-Za-z0-9_])/sys(?=$|[/"\x27\s;,)])}{/System/Hardware}g;
			s{(?<![A-Za-z0-9_])/dev(?=$|[/"\x27\s;,)])}{/System/Devices}g;
			s{(?<![A-Za-z0-9_])/run(?=$|[/"\x27\s;,)])}{/System/Runtime}g;
		' "$file"
	fi
done < <(find "$SOURCE/sh" "$SOURCE/src" -type f -print0)

git -C "$SOURCE" diff --binary >"$OUTPUT"
printf '%s\n' "$OUTPUT"
