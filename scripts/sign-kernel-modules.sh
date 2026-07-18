#!/usr/bin/env bash
set -euo pipefail
readonly SIGN_FILE="${1:?sign-file is required}"
readonly PRIVATE_KEY="${2:?private key is required}"
readonly CERTIFICATE="${3:?certificate is required}"
readonly MODULE_ROOT="${4:?module root is required}"
for file in "$SIGN_FILE" "$PRIVATE_KEY" "$CERTIFICATE"; do [ -f "$file" ] || exit 2; done
[ -d "$MODULE_ROOT" ] || exit 2
count=0
while IFS= read -r -d '' module; do
  "$SIGN_FILE" sha256 "$PRIVATE_KEY" "$CERTIFICATE" "$module"
  count=$((count + 1))
done < <(find "$MODULE_ROOT" -type f -name '*.ko' -print0)
[ "$count" -gt 0 ] || { printf '%s\n' 'No modules were available for signing' >&2; exit 1; }
printf 'Signed %s kernel modules\n' "$count"
