[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$Sdk,
    [Parameter(Mandatory)] [string]$SigningKey,
    [Parameter(Mandatory)] [string]$SigningCertificate,
    [string]$WslDistro = "Debian",
    [string]$Report = "Output/P3/Module-SDK.json"
)
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$Repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
function WslPath([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    $value = @(& wsl.exe -d $WslDistro -e wslpath -a -u $full)
    if ($LASTEXITCODE -ne 0) { throw "wslpath failed for $full" }
    return (@($value) -join "`n").Trim()
}
$sdkPath = WslPath $Sdk
$keyPath = WslPath $SigningKey
$certificatePath = WslPath $SigningCertificate
$probePath = WslPath (Join-Path $Repository "Tests\ExternalModule")
$started = [Diagnostics.Stopwatch]::StartNew()
$command = @(
    'set -euo pipefail'
    'work=$(mktemp -d /tmp/mixtar-sdk.XXXXXX)'
    'trap ''rm -rf -- "$work"'' EXIT'
    'cp "$MIXTAR_PROBE/Makefile" "$MIXTAR_PROBE/mixtar_probe.c" "$work/"'
    'make -s -C "$MIXTAR_SDK" M="$work" modules'
    '"$MIXTAR_SDK/scripts/sign-file" sha256 "$MIXTAR_KEY" "$MIXTAR_CERTIFICATE" "$work/mixtar_probe.ko"'
    'grep -a -q "~Module signature appended~" "$work/mixtar_probe.ko"'
    'sha256sum "$work/mixtar_probe.ko"'
) -join "`n"
$commandFile = Join-Path ([IO.Path]::GetTempPath()) ("mixtar-sdk-{0}.sh" -f [Guid]::NewGuid().ToString("N"))
[IO.File]::WriteAllText($commandFile, $command + "`n", [Text.UTF8Encoding]::new($false))
$commandPath = WslPath $commandFile
try {
    $output = @(& wsl.exe -d $WslDistro -- env `
        "MIXTAR_SDK=$sdkPath" `
        "MIXTAR_KEY=$keyPath" `
        "MIXTAR_CERTIFICATE=$certificatePath" `
        "MIXTAR_PROBE=$probePath" `
        bash $commandPath 2>&1)
    $exitCode = $LASTEXITCODE
} finally {
    [IO.File]::Delete($commandFile)
}
$started.Stop()
$passed = $exitCode -eq 0
$payload = [ordered]@{
    schema = "mixtar.m1-module-sdk-test.v1"
    passed = $passed
    exit_code = $exitCode
    duration_seconds = [Math]::Round($started.Elapsed.TotalSeconds, 3)
    output = @($output | ForEach-Object { $_.ToString() })
}
$reportPath = [IO.Path]::GetFullPath((Join-Path $Repository $Report))
[IO.Directory]::CreateDirectory((Split-Path -Parent $reportPath)) | Out-Null
[IO.File]::WriteAllText($reportPath, ($payload | ConvertTo-Json -Depth 5) + "`n", [Text.UTF8Encoding]::new($false))
if (-not $passed) { throw "External module SDK acceptance failed." }
Write-Host "MIXTAR_M1_MODULE_SDK_OK"
