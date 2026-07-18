#!/usr/bin/env bash
set -Eeuo pipefail

readonly project="${1:?Workbench project is required}"
readonly runtime="${2:?runtime identifier is required}"
readonly configuration="${3:?configuration is required}"
readonly output="${4:?publish output is required}"
readonly sdk_channel="${5:?SDK channel is required}"

if command -v dotnet >/dev/null 2>&1; then
    dotnet_command="$(command -v dotnet)"
elif [[ -x "${HOME}/.dotnet/dotnet" ]]; then
    dotnet_command="${HOME}/.dotnet/dotnet"
else
    printf 'The stable .NET SDK is not installed.\n' >&2
    exit 2
fi

actual_sdk="$("${dotnet_command}" --version)"
if [[ "${actual_sdk}" != "${sdk_channel}."* ]]; then
    printf 'Expected .NET SDK channel %s, found %s.\n' "${sdk_channel}" "${actual_sdk}" >&2
    exit 2
fi

"${dotnet_command}" restore "${project}" \
    --runtime "${runtime}" \
    --locked-mode

mkdir -p "${output}"
rm -f -- \
    "${output}/Workbench" \
    "${output}/Workbench.dbg" \
    "${output}/libSkiaSharp.so" \
    "${output}/libHarfBuzzSharp.so"

"${dotnet_command}" publish "${project}" \
    --configuration "${configuration}" \
    --runtime "${runtime}" \
    --self-contained true \
    --no-restore \
    --output "${output}" \
    -p:PublishAot=true

[[ -x "${output}/Workbench" ]] || {
    printf 'Native AOT Workbench was not produced.\n' >&2
    exit 3
}
[[ -f "${output}/Workbench.dbg" ]] || {
    printf 'Native AOT Workbench debug symbols were not produced.\n' >&2
    exit 3
}

build_id() {
    readelf -n "$1" | awk '/Build ID:/ { print $3; exit }'
}

binary_build_id="$(build_id "${output}/Workbench")"
debug_build_id="$(build_id "${output}/Workbench.dbg")"
if [[ -z "${binary_build_id}" || "${binary_build_id}" != "${debug_build_id}" ]]; then
    printf 'Native AOT build-id mismatch: binary=%s debug=%s\n' \
        "${binary_build_id:-missing}" "${debug_build_id:-missing}" >&2
    exit 3
fi
