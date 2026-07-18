#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 5 ]]; then
    echo "usage: publish-executor.sh PROJECT RUNTIME CONFIGURATION OUTPUT SDK_CHANNEL" >&2
    exit 64
fi

repository="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
project="$repository/$1"
runtime="$2"
configuration="$3"
output="$repository/$4"
sdk_channel="$5"

case "$project" in
    "$repository"/*) ;;
    *) echo "Executor project escapes the repository" >&2; exit 65 ;;
esac
case "$output" in
    "$repository"/out/*) ;;
    *) echo "Executor output must be below out/" >&2; exit 65 ;;
esac
if [[ ! -f "$project" ]]; then
    echo "Executor project does not exist: $project" >&2
    exit 66
fi

export DOTNET_CLI_TELEMETRY_OPTOUT=1
export DOTNET_NOLOGO=1
export DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1
if ! command -v dotnet >/dev/null 2>&1; then
    if [[ -x "$HOME/.dotnet/dotnet" ]]; then
        export DOTNET_ROOT="$HOME/.dotnet"
        export PATH="$DOTNET_ROOT:$DOTNET_ROOT/tools:$PATH"
    else
        echo "A stable .NET SDK is required in PATH or at $HOME/.dotnet/dotnet" >&2
        exit 69
    fi
fi

cd "$repository/Product"
selected_sdk="$(dotnet --version)"
escaped_channel="${sdk_channel//./\.}"
if [[ ! "$selected_sdk" =~ ^${escaped_channel}\.[0-9]+$ ]] || [[ "$selected_sdk" == *-* ]]; then
    echo "A stable .NET SDK from channel $sdk_channel is required; selected: $selected_sdk" >&2
    exit 69
fi

rm -rf -- "$output"
mkdir -p -- "$output"
dotnet restore "$project" --runtime "$runtime" --locked-mode
dotnet publish "$project"     --configuration "$configuration"     --runtime "$runtime"     --self-contained true     --no-restore     --output "$output"     -p:PublishAot=true     -p:ContinuousIntegrationBuild=true

binary="$output/Executor"
if [[ ! -x "$binary" ]]; then
    echo "Native Executor was not produced: $binary" >&2
    exit 70
fi
if readelf -l "$binary" | grep -q 'INTERP'; then
    echo "Executor requires an external ELF interpreter; Mixtar Core accepts only static Native AOT" >&2
    exit 70
fi
if readelf -d "$binary" 2>/dev/null | grep -q '(NEEDED)'; then
    echo "Executor requires external shared libraries; Mixtar Core accepts only static Native AOT" >&2
    exit 70
fi
