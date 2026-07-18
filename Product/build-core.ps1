[CmdletBinding()]
param(
    [string]$Configuration = "Product/Core.config",
    [string]$WslDistribution = $env:MIXTAR_WSL_DISTRIBUTION,
    [switch]$Image
)

$ErrorActionPreference = "Stop"
$repository = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($WslDistribution)) {
    $WslDistribution = "Debian"
}

Push-Location -LiteralPath $repository
try {
    & py -3 Product/build_core.py `
        --config $Configuration `
        --wsl-distribution $WslDistribution
    if ($LASTEXITCODE -ne 0) {
        throw "MixtarRVS Core build failed with exit code $LASTEXITCODE."
    }

    if ($Image) {
        & py -3 Product/build_core_image.py `
            --config $Configuration `
            --wsl-distribution $WslDistribution
        if ($LASTEXITCODE -ne 0) {
            throw "MixtarRVS Core image build failed with exit code $LASTEXITCODE."
        }
    }

    $validationArguments = @(
        "Product/validate_core.py",
        "--config",
        $Configuration
    )
    if ($Image) {
        $validationArguments += "--require-image"
    }
    & py -3 @validationArguments
    if ($LASTEXITCODE -ne 0) {
        throw "MixtarRVS Core validation failed with exit code $LASTEXITCODE."
    }
}
finally {
    Pop-Location
}
