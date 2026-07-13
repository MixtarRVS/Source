#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"
manifest="$repo_root/System/Kernel/Manifests/linux-kernel.json"

usage() {
  cat <<'EOF'
Usage: kernel_fetch.sh [status|fetch|verify|extract|all] [target-id]

Targets are defined in System/Kernel/Manifests/linux-kernel.json.
Default target: linux-longterm.

Generated files are stored under System/Kernel/Generated/.
EOF
}

command="${1:-status}"
target_id="${2:-}"

if [[ "$command" == "help" || "$command" == "--help" || "$command" == "-h" ]]; then
  usage
  exit 0
fi

if [[ ! -f "$manifest" ]]; then
  echo "kernel-fetch: missing manifest: $manifest" >&2
  exit 1
fi

if [[ -z "$target_id" ]]; then
  target_id="$(python3 - "$manifest" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    data = json.load(handle)
print(data["policy"]["default_target"])
PY
)"
fi

eval "$(
  python3 - "$manifest" "$target_id" <<'PY'
import json
import shlex
import sys

manifest_path, target_id = sys.argv[1], sys.argv[2]
with open(manifest_path, "r", encoding="utf-8") as handle:
    data = json.load(handle)

target = None
for candidate in data["targets"]:
    if candidate["id"] == target_id:
        target = candidate
        break

if target is None:
    known = ", ".join(item["id"] for item in data["targets"])
    raise SystemExit(f"kernel-fetch: unknown target {target_id!r}; known: {known}")

fields = {
    "target_id": target["id"],
    "channel": target["channel"],
    "version": target["version"],
    "archive_url": target["archive_url"],
    "signature_url": target["signature_url"],
    "archive_name": target["archive_name"],
    "signature_name": target["signature_name"],
    "expected_sha256": target.get("sha256", ""),
    "extract_dir": target["extract_dir"],
}

for key, value in fields.items():
    print(f"{key}={shlex.quote(value)}")
PY
)"

generated_dir="$repo_root/System/Kernel/Generated"
source_dir="$generated_dir/sources"
src_root="$repo_root/$extract_dir"
archive_path="$source_dir/$archive_name"
signature_path="$source_dir/$signature_name"
sha256_path="$archive_path.sha256"

status() {
  echo "kernel-fetch: target=$target_id channel=$channel version=$version"
  echo "kernel-fetch: archive=$archive_url"
  echo "kernel-fetch: generated=$generated_dir"
  if [[ -f "$archive_path" ]]; then
    echo "kernel-fetch: archive-present=$archive_path"
  else
    echo "kernel-fetch: archive-missing=$archive_path"
  fi
  if [[ -d "$src_root" ]]; then
    echo "kernel-fetch: source-present=$src_root"
  else
    echo "kernel-fetch: source-missing=$src_root"
  fi
}

fetch() {
  mkdir -p "$source_dir"
  echo "kernel-fetch: downloading $archive_url"
  curl -L --fail --retry 3 --output "$archive_path" "$archive_url"
  echo "kernel-fetch: downloading $signature_url"
  curl -L --fail --retry 3 --output "$signature_path" "$signature_url"
}

verify() {
  if [[ ! -f "$archive_path" ]]; then
    echo "kernel-fetch: cannot verify; archive missing: $archive_path" >&2
    exit 1
  fi
  mkdir -p "$source_dir"
  sha256sum "$archive_path" | tee "$sha256_path"
  actual_sha256="$(cut -d ' ' -f 1 "$sha256_path")"
  if [[ -n "$expected_sha256" && "$actual_sha256" != "$expected_sha256" ]]; then
    echo "kernel-fetch: sha256 mismatch" >&2
    echo "kernel-fetch: expected $expected_sha256" >&2
    echo "kernel-fetch: actual   $actual_sha256" >&2
    exit 1
  fi
  if [[ -n "$expected_sha256" ]]; then
    echo "kernel-fetch: sha256 matches manifest"
  fi
  if [[ -f "$signature_path" && -x "$(command -v gpg || true)" ]]; then
    echo "kernel-fetch: checking kernel.org signature if local kernel signing keys are trusted"
    if xz -cd "$archive_path" | gpg --verify "$signature_path" -; then
      echo "kernel-fetch: gpg signature ok"
    else
      echo "kernel-fetch: gpg signature could not be verified with local keyring; sha256 recorded" >&2
    fi
  else
    echo "kernel-fetch: signature check skipped; gpg or signature file missing" >&2
  fi
}

extract() {
  if [[ ! -f "$archive_path" ]]; then
    echo "kernel-fetch: cannot extract; archive missing: $archive_path" >&2
    exit 1
  fi
  mkdir -p "$repo_root/System/Kernel/Generated/src"
  if [[ -d "$src_root" ]]; then
    echo "kernel-fetch: source already extracted: $src_root"
    return 0
  fi
  echo "kernel-fetch: extracting $archive_path"
  tar -xJf "$archive_path" -C "$repo_root/System/Kernel/Generated/src"
}

case "$command" in
  status)
    status
    ;;
  fetch)
    fetch
    ;;
  verify)
    verify
    ;;
  extract)
    extract
    ;;
  all)
    fetch
    verify
    extract
    status
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
