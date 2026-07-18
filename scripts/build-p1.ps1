[CmdletBinding()]
param(
    [switch]$SkipP0,
    [switch]$SkipQemu,
    [switch]$SkipP2,
    [switch]$TestHyperV,
    [string]$SwitchName,
    [switch]$CleanCache
)
$arguments = @{}
foreach ($name in "SkipP0", "SkipQemu", "SkipP2", "TestHyperV", "CleanCache") {
    if (Get-Variable -Name $name -ValueOnly) { $arguments[$name] = $true }
}
if ($SwitchName) { $arguments.SwitchName = $SwitchName }
& (Join-Path $PSScriptRoot "build-m1.ps1") @arguments
