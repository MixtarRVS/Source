[CmdletBinding()]
param(
    [string]$WslDistribution = 'Debian',
    [ValidateRange(0, 512)]
    [int]$Jobs = 0,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$repoWsl = (& wsl.exe -d $WslDistribution -e wslpath -a $repo).Trim()
if ($LASTEXITCODE -ne 0 -or -not $repoWsl) {
    throw 'Could not translate the repository path for WSL.'
}

$arguments = @('-d', $WslDistribution, '--cd', $repoWsl, '-e', 'python3', 'Product/build_mwm.py')
if ($Jobs -gt 0) {
    $arguments += @('--jobs', $Jobs)
}
if ($Force) {
    $arguments += '--force'
}

& wsl.exe @arguments
if ($LASTEXITCODE -ne 0) {
    throw "MWM build failed with exit code $LASTEXITCODE."
}
