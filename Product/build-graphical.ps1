[CmdletBinding()]
param(
    [string]$CoreConfiguration = "Product/Core.config",
    [string]$GraphicsConfiguration = "Product/Graphics.config",
    [string]$WslDistribution = $env:MIXTAR_WSL_DISTRIBUTION,
    [int]$Jobs = 0,
    [switch]$RebuildCore,
    [switch]$Image
)

$ErrorActionPreference = "Stop"
$repository = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $repository

function Assert-ExitCode {
    param(
        [int]$ExitCode,
        [string]$Operation
    )
    if ($ExitCode -ne 0) {
        throw "$Operation failed with exit code $ExitCode."
    }
}

$coreArchive = Join-Path $repository "Output/P4/MixtarRVS-1.0-Core-x86_64.root.tar"
if ($RebuildCore -or -not (Test-Path -LiteralPath $coreArchive -PathType Leaf)) {
    $coreArguments = @{
        Configuration = $CoreConfiguration
    }
    if (-not [string]::IsNullOrWhiteSpace($WslDistribution)) {
        $coreArguments.WslDistribution = $WslDistribution
    }
    & (Join-Path $PSScriptRoot "build-core.ps1") @coreArguments
}

$graphicsArguments = @{
    Configuration = $GraphicsConfiguration
    Jobs = $Jobs
}
if (-not [string]::IsNullOrWhiteSpace($WslDistribution)) {
    $graphicsArguments.WslDistribution = $WslDistribution
}
& (Join-Path $PSScriptRoot "build-graphics.ps1") @graphicsArguments

$distroArguments = @()
if (-not [string]::IsNullOrWhiteSpace($WslDistribution)) {
    $distroArguments = @("-d", $WslDistribution)
}

$repositoryWslOutput = @(& wsl.exe @distroArguments -e /usr/bin/wslpath -a -u ([string]$repository))
$repositoryWslExitCode = $LASTEXITCODE
$repositoryWslRaw = $repositoryWslOutput | Select-Object -First 1
Assert-ExitCode -ExitCode $repositoryWslExitCode -Operation "WSL repository path conversion"
if ([string]::IsNullOrWhiteSpace([string]$repositoryWslRaw)) {
    throw "WSL repository path conversion returned an empty path."
}
$repositoryWsl = ([string]$repositoryWslRaw).Trim()

function Invoke-MixtarWsl {
    param(
        [Parameter(Mandatory)]
        [string[]]$Command,
        [Parameter(Mandatory)]
        [string]$Operation
    )
    & wsl.exe @script:distroArguments --cd $script:repositoryWsl -- @Command
    $exitCode = $LASTEXITCODE
    Assert-ExitCode -ExitCode $exitCode -Operation $Operation
}

$mddmCommand = @("python3", "Product/build_mddm.py")
if ($Jobs -gt 0) {
    $mddmCommand += @("--jobs", [string]$Jobs)
}
Invoke-MixtarWsl -Command $mddmCommand -Operation "MDDM/MWM production build"

Invoke-MixtarWsl -Command @("fakeroot", "python3", "Product/assemble_graphical_root.py") -Operation "MixtarRVS GraphicalRoot assembly"

if ($Image) {
    $imageCommand = @(
        "-3",
        "Product/build_core_image.py",
        "--config",
        "out/Product/Graphical.config"
    )
    if (-not [string]::IsNullOrWhiteSpace($WslDistribution)) {
        $imageCommand += @("--wsl-distribution", $WslDistribution)
    }
    & py @imageCommand
    $imageExitCode = $LASTEXITCODE
    Assert-ExitCode -ExitCode $imageExitCode -Operation "MixtarRVS graphical EFI/ZFS image build"
}

Write-Output (Join-Path $repository "Output/P4/MixtarRVS-1.1-Graphical-x86_64.root.tar")
if ($Image) {
    Write-Output (Join-Path $repository "Output/P4/Image/MixtarRVS-1.1-Graphical-x86_64.vhdx")
}