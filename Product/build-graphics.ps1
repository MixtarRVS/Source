[CmdletBinding()]
param(
    [string]$Configuration = "Product/Graphics.config",
    [string]$WslDistribution = $env:MIXTAR_WSL_DISTRIBUTION,
    [int]$Jobs = 0
)

$ErrorActionPreference = "Stop"
$repository = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($WslDistribution)) {
    $WslDistribution = "Debian"
}

Push-Location -LiteralPath $repository
try {
    $arguments = @(
        "Product/build_graphics.py",
        "--config", $Configuration,
        "--wsl-distribution", $WslDistribution
    )
    if ($Jobs -gt 0) {
        $arguments += @("--jobs", $Jobs)
    }
    & py -3 @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "MixtarRVS graphics build failed with exit code $LASTEXITCODE."
    }
}
finally {
    Pop-Location
}
