[CmdletBinding()]
param(
    [string]$Firmware,
    [string]$FirmwareVars,

    [string]$Qemu,
    [string]$Accelerator,
    [int]$Memory,
    [int]$Cpus,
    [string[]]$QemuArgument,
    [string]$Configuration = "Product/Core.config",
    [switch]$Build
)

function Resolve-QemuExecutable {
    param([string]$Configured)
    $candidates = @($Configured, $env:MIXTAR_QEMU)
    $command = Get-Command qemu-system-x86_64.exe -ErrorAction SilentlyContinue
    if ($command) { $candidates += $command.Source }
    if ($env:ProgramFiles) {
        $candidates += (Join-Path $env:ProgramFiles "qemu\qemu-system-x86_64.exe")
    }
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return [IO.Path]::GetFullPath($candidate)
        }
    }
    throw "qemu-system-x86_64.exe was not found. Set MIXTAR_QEMU or use -Qemu."
}

function Resolve-FirmwareFile {
    param(
        [string]$Configured,
        [string]$QemuPath,
        [string]$EnvironmentName,
        [string[]]$Names
    )
    if ($Configured) {
        if (Test-Path -LiteralPath $Configured -PathType Leaf) {
            return [IO.Path]::GetFullPath($Configured)
        }
        throw "Configured firmware does not exist: $Configured"
    }
    $environmentValue = [Environment]::GetEnvironmentVariable($EnvironmentName)
    if ($environmentValue -and (Test-Path -LiteralPath $environmentValue -PathType Leaf)) {
        return [IO.Path]::GetFullPath($environmentValue)
    }
    $directory = Split-Path -Parent $QemuPath
    $bases = @(
        (Join-Path $directory "share"),
        (Join-Path (Split-Path -Parent $directory) "share\qemu")
    )
    foreach ($base in $bases) {
        foreach ($name in $Names) {
            $candidate = Join-Path $base $name
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                return [IO.Path]::GetFullPath($candidate)
            }
        }
    }
    throw "UEFI firmware was not found. Set $EnvironmentName or pass an explicit path."
}

$ErrorActionPreference = "Stop"
$Qemu = Resolve-QemuExecutable $Qemu
$Firmware = Resolve-FirmwareFile `
    $Firmware $Qemu "MIXTAR_UEFI_CODE" @("edk2-x86_64-code.fd")
$FirmwareVars = Resolve-FirmwareFile `
    $FirmwareVars $Qemu "MIXTAR_UEFI_VARS" @("edk2-i386-vars.fd", "edk2-x86_64-vars.fd")
$repository = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $repository
try {
    if ($Build) {
        & "$PSScriptRoot\build-core.ps1" `
            -Configuration $Configuration `
            -Image
        if ($LASTEXITCODE -ne 0) {
            throw "MixtarRVS Core image build failed with exit code $LASTEXITCODE."
        }
    }

    $arguments = @(
        "-3",
        "Product/test_core_release.py",
        "--config",
        $Configuration,
        "--firmware",
        $Firmware,
        "--firmware-vars",
        $FirmwareVars
    )
    if (-not [string]::IsNullOrWhiteSpace($Qemu)) {
        $arguments += @("--qemu", $Qemu)
    }
    if (-not [string]::IsNullOrWhiteSpace($Accelerator)) {
        $arguments += @("--accelerator", $Accelerator)
    }
    if ($Memory -gt 0) {
        $arguments += @("--memory", [string]$Memory)
    }
    if ($Cpus -gt 0) {
        $arguments += @("--cpus", [string]$Cpus)
    }

    foreach ($value in $QemuArgument) {
        $arguments += @("--qemu-arg", $value)
    }

    & py @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "MixtarRVS Core release test failed with exit code $LASTEXITCODE."
    }
}
finally {
    Pop-Location
}
