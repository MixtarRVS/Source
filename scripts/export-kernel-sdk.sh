#!/usr/bin/env bash
set -euo pipefail
readonly SOURCE="${1:?kernel source is required}"
readonly BUILD="${2:?kernel build is required}"
readonly DESTINATION="${3:?SDK destination is required}"
for path in "$SOURCE" "$BUILD"; do [ -d "$path" ] || exit 2; done
rm -rf -- "$DESTINATION"
mkdir -p "$DESTINATION/arch/x86"
for item in Makefile Kconfig Kbuild include scripts; do
  cp -a "$SOURCE/$item" "$DESTINATION/"
done
find "$SOURCE/arch/x86" -maxdepth 1 -type f \( -name 'Makefile*' -o -name 'Kconfig*' \) \
  -exec cp -a {} "$DESTINATION/arch/x86/" \;
cp -a "$SOURCE/arch/x86/include" "$DESTINATION/arch/x86/"
for item in .config Module.symvers System.map modules.order; do
  [ -e "$BUILD/$item" ] && cp -a "$BUILD/$item" "$DESTINATION/$item"
done
for item in include arch/x86/include/generated scripts; do
  [ -d "$BUILD/$item" ] || continue
  mkdir -p "$DESTINATION/$(dirname "$item")"
  cp -a "$BUILD/$item/." "$DESTINATION/$item/"
done
for item in tools/objtool/objtool tools/bpf/resolve_btfids/resolve_btfids; do
  [ -x "$BUILD/$item" ] || continue
  mkdir -p "$DESTINATION/$(dirname "$item")"
  cp -a "$BUILD/$item" "$DESTINATION/$item"
done
find "$DESTINATION" -type f \( \
  -name fixdep -o \
  -name modpost -o \
  -name genksyms -o \
  -name objtool -o \
  -name resolve_btfids \
\) -exec chmod 0755 {} +
printf '%s\n' "$DESTINATION"
