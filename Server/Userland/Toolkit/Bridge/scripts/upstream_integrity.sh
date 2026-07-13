#!/usr/bin/env bash
set -euo pipefail

mode="${1:-verify}"
manifest="Server/Userland/Manifests/upstream-integrity.sha256"
roots=(
  "Server/Userland/Toolkit/OpenBSD/src"
  "Server/Userland/Toolkit/FreeBSD/freebsd-src"
)

write_current_manifest() {
  local out="$1"
  : > "$out"
  for root in "${roots[@]}"; do
    if [[ -d "$root" ]]; then
      find "$root" -type f ! -path '*/.git/*' -print
    fi
  done | LC_ALL=C sort | while IFS= read -r path; do
    sha256sum "$path"
  done >> "$out"
}

write_current_paths() {
  local out="$1"
  : > "$out"
  for root in "${roots[@]}"; do
    if [[ -d "$root" ]]; then
      find "$root" -type f ! -path '*/.git/*' -print
    fi
  done | LC_ALL=C sort > "$out"
}

case "$mode" in
  refresh)
    mkdir -p "$(dirname "$manifest")"
    tmp="$(mktemp)"
    write_current_manifest "$tmp"
    mv "$tmp" "$manifest"
    count="$(wc -l < "$manifest" | tr -d ' ')"
    echo "upstream-integrity: refreshed $manifest ($count files)"
    ;;
  verify)
    if [[ ! -f "$manifest" ]]; then
      echo "upstream-integrity: missing $manifest" >&2
      echo "upstream-integrity: run toolkit_build refresh-upstream-manifest once after importing upstream mirrors" >&2
      exit 1
    fi

    expected_paths="$(mktemp)"
    current_paths="$(mktemp)"
    cleanup() {
      rm -f "$expected_paths" "$current_paths"
    }
    trap cleanup EXIT

    sed 's/^[0-9a-fA-F]\{64\}  //' "$manifest" | LC_ALL=C sort > "$expected_paths"
    write_current_paths "$current_paths"

    if ! cmp -s "$expected_paths" "$current_paths"; then
      echo "upstream-integrity: upstream mirror file set changed" >&2
      diff -u "$expected_paths" "$current_paths" >&2 || true
      exit 1
    fi

    if ! sha256sum --status -c "$manifest"; then
      echo "upstream-integrity: upstream mirror content changed" >&2
      sha256sum -c "$manifest" | awk '$NF != "OK" { print }' >&2
      exit 1
    fi

    count="$(wc -l < "$manifest" | tr -d ' ')"
    echo "upstream-integrity: verified unchanged upstream mirrors ($count files)"
    ;;
  *)
    echo "Usage: upstream_integrity.sh [verify|refresh]" >&2
    exit 2
    ;;
esac
