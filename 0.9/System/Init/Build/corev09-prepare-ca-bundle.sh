#!/usr/bin/env bash
set -Eeuo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/../../.." && pwd)
output_dir=${1:-"$repo_root/out/server/corev09-inputs/Configuration/TLS"}
curl_tool=${MIXTAR_CA_CURL:-"$repo_root/out/server/corev09-inputs/Userland/curl"}
sha256_tool=${MIXTAR_CA_SHA256:-"$repo_root/out/server/corev09-inputs/Updaters/mixtar-sha256"}
bootstrap_ca=${MIXTAR_BUILDHOST_CA:-/etc/ssl/certs/ca-certificates.crt}
schema="$repo_root/Server/Updates/Schema/Updates.schema.sql"
seed="$repo_root/Server/Updates/Schema/Updates.seed.sql"

fail() {
    printf 'corev09-prepare-ca-bundle: %s\n' "$*" >&2
    exit 1
}

for required in "$curl_tool" "$sha256_tool" "$bootstrap_ca" "$schema" "$seed"; do
    [ -f "$required" ] || fail "missing input: $required"
done
[ -x "$curl_tool" ] || fail "curl input is not executable: $curl_tool"
[ -x "$sha256_tool" ] || fail "SHA-256 input is not executable: $sha256_tool"

mkdir -p "$repo_root/out/server"
work=$(mktemp -d "$repo_root/out/server/corev09-ca-bundle.XXXXXX")
case "$work" in
    "$repo_root"/out/server/corev09-ca-bundle.*) ;;
    *) fail "unsafe temporary directory: $work" ;;
esac
cleanup() {
    rm -rf -- "$work"
}
trap cleanup EXIT

policy_db="$work/Updates.config"
python3 - "$schema" "$seed" "$policy_db" <<'PY'
import pathlib
import sqlite3
import sys

schema = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
seed = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8")
database = sqlite3.connect(sys.argv[3])
try:
    database.executescript(schema)
    database.executescript(seed)
finally:
    database.close()
PY

mapfile -t policy < <(python3 - "$policy_db" <<'PY'
import sqlite3
import sys

database = sqlite3.connect(sys.argv[1])
row = database.execute(
    """
    SELECT source.artifact_uri_template,
           source.signature_uri_template,
           anchor.fingerprint,
           anchor.material_sha256,
           component.installed_version
      FROM component
      JOIN component_source AS source ON source.component_id = component.id
      JOIN trust_anchor AS anchor ON anchor.id = source.trust_anchor_id
     WHERE component.id = 'ca-bundle'
       AND source.role = 'published-bundle'
       AND component.enabled = 1
       AND anchor.enabled = 1
    """
).fetchone()
if row is None:
    raise SystemExit("enabled ca-bundle policy is missing")
bundle_uri, digest_uri, fingerprint, sidecar_hash, version = row
prefix = "SHA256:"
if not fingerprint.startswith(prefix):
    raise SystemExit("ca-bundle fingerprint is not SHA256")
for value in (bundle_uri, digest_uri, fingerprint[len(prefix):], sidecar_hash, version):
    print(value)
PY
)
[ "${#policy[@]}" -eq 5 ] || fail "incomplete ca-bundle policy"

bundle_uri=${policy[0]}
digest_uri=${policy[1]}
expected_bundle_hash=${policy[2],,}
expected_sidecar_hash=${policy[3],,}
bundle_version=${policy[4]}
bundle_output="$output_dir/cacert.pem"
sidecar_output="$output_dir/cacert.pem.sha256"

verify_pair() {
    bundle=$1
    sidecar=$2
    [ -s "$bundle" ] && [ -s "$sidecar" ] || return 1
    [ "$($sha256_tool "$bundle")" = "$expected_bundle_hash" ] || return 1
    [ "$($sha256_tool "$sidecar")" = "$expected_sidecar_hash" ] || return 1
    declared=$(tr -cs '0-9A-Fa-f' '\n' <"$sidecar" | awk 'length($0) == 64 { print tolower($0); exit }')
    [ "$declared" = "$expected_bundle_hash" ] || return 1
    certificate_count=$(grep -c -- 'BEGIN CERTIFICATE' "$bundle" || true)
    [ "$certificate_count" -gt 0 ] || return 1
}

if verify_pair "$bundle_output" "$sidecar_output"; then
    printf 'CA_BUNDLE_VERSION=%s\n' "$bundle_version"
    printf 'CA_BUNDLE_SHA256=%s\n' "$expected_bundle_hash"
    printf 'CA_BUNDLE_CERTIFICATES=%s\n' "$certificate_count"
    echo CORE_V09_CA_BUNDLE_CACHE_GATE=PASS
    exit 0
fi

"$curl_tool" --fail --silent --show-error --location \
    --proto '=https' --tlsv1.2 --cacert "$bootstrap_ca" \
    --output "$work/cacert.pem" "$bundle_uri"
"$curl_tool" --fail --silent --show-error --location \
    --proto '=https' --tlsv1.2 --cacert "$bootstrap_ca" \
    --output "$work/cacert.pem.sha256" "$digest_uri"

verify_pair "$work/cacert.pem" "$work/cacert.pem.sha256" || \
    fail "official CA bundle does not match pinned Updates.config policy"

mkdir -p "$output_dir"
install -m 0644 "$work/cacert.pem" "$output_dir/.cacert.pem.next.$$"
install -m 0644 "$work/cacert.pem.sha256" "$output_dir/.cacert.pem.sha256.next.$$"
mv -f -- "$output_dir/.cacert.pem.next.$$" "$bundle_output"
mv -f -- "$output_dir/.cacert.pem.sha256.next.$$" "$sidecar_output"

printf 'CA_BUNDLE_VERSION=%s\n' "$bundle_version"
printf 'CA_BUNDLE_SHA256=%s\n' "$expected_bundle_hash"
printf 'CA_BUNDLE_CERTIFICATES=%s\n' "$certificate_count"
echo CORE_V09_CA_BUNDLE_FETCH_GATE=PASS
