[CmdletBinding()]
param(
    [string]$WslDistro = "Debian",
    [ValidateRange(0, 512)]
    [int]$Jobs = 0,
    [switch]$Refresh
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot

if (-not (Test-Path -LiteralPath (Join-Path $repo "out\Product\GraphicsStack\Build.json"))) {
    & (Join-Path $PSScriptRoot "build-graphics.ps1")
}

if (-not (Test-Path -LiteralPath (Join-Path $repo "out\Product\MWMStack\Build.json"))) {
    & (Join-Path $PSScriptRoot "build-mwm.ps1")
}

$linuxRepo = (& wsl.exe -d $WslDistro -e wslpath -a $repo).Trim()
if (-not $linuxRepo) {
    throw "Could not resolve the repository path inside WSL."
}

$arguments = @(
    "-d", $WslDistro,
    "-e", "python3",
    "$linuxRepo/Product/build_mddm.py"
)

if ($Jobs -gt 0) {
    $arguments += @("--jobs", $Jobs)
}
if ($Refresh) {
    $arguments += "--refresh"
}

& wsl.exe @arguments
if ($LASTEXITCODE -ne 0) {
    throw "MDDM build failed with exit code $LASTEXITCODE."
}
