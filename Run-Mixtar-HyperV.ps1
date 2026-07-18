[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$stage = 'initialization'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
$isAdministrator = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdministrator) {
    $powershell = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $PSCommandPath
    Start-Process -FilePath $powershell -Verb RunAs -ArgumentList $arguments
    exit
}

try {
    $stage = 'loading Hyper-V'
    Import-Module Hyper-V

    $name = 'MixtarRVS-1.1'
    $repository = Split-Path -Parent $PSCommandPath
    $vhd = Join-Path $repository 'Output\P4\Image\MixtarRVS-1.1-x86_64.vhdx'
    $vmRoot = Join-Path $repository 'Output\P4\Hyper-V'

    $stage = 'locating the Mixtar disk'
    if (-not (Test-Path -LiteralPath $vhd -PathType Leaf)) {
        throw "Mixtar VHDX was not found: $vhd"
    }
    $vhd = (Resolve-Path -LiteralPath $vhd).Path

    $stage = 'locating MixtarRVS-1.1'
    $vm = Get-VM -Name $name -ErrorAction SilentlyContinue

    if (-not $vm) {
        $stage = 'creating MixtarRVS-1.1'
        New-Item -ItemType Directory -Path $vmRoot -Force | Out-Null
        New-VM -Name $name -Generation 2 -MemoryStartupBytes 4GB -VHDPath $vhd -Path $vmRoot | Out-Null
        $vm = Get-VM -Name $name -ErrorAction Stop
    }
    else {
        $stage = 'checking the attached Mixtar disk'
        $drives = @(Get-VMHardDiskDrive -VMName $name -ErrorAction Stop)
        $matchingDrive = $drives | Where-Object {
            $_.Path -and [IO.Path]::GetFullPath($_.Path).Equals(
                [IO.Path]::GetFullPath($vhd),
                [StringComparison]::OrdinalIgnoreCase)
        } | Select-Object -First 1

        if (-not $matchingDrive) {
            if ($drives.Count -eq 0) {
                Add-VMHardDiskDrive -VMName $name -Path $vhd | Out-Null
            }
            else {
                throw "MixtarRVS-1.1 already exists but uses another disk."
            }
        }
    }

    $stage = 'configuring MixtarRVS-1.1'
    $processorCount = [Math]::Max(1, [Math]::Min(8, [Environment]::ProcessorCount))
    Set-VM -Name $name -AutomaticCheckpointsEnabled $false -CheckpointType Disabled -AutomaticStartAction Nothing -AutomaticStopAction ShutDown
    Set-VMMemory -VMName $name -DynamicMemoryEnabled $false -StartupBytes 4GB
    Set-VMProcessor -VMName $name -Count $processorCount

    $stage = 'configuring Mixtar firmware'
    $bootDisk = Get-VMHardDiskDrive -VMName $name | Select-Object -First 1
    if (-not $bootDisk) {
        throw 'The Mixtar VM has no attached disk.'
    }
    Set-VMFirmware -VMName $name -EnableSecureBoot Off -FirstBootDevice $bootDisk

    $stage = 'starting MixtarRVS-1.1'
    $vm = Get-VM -Name $name
    if ($vm.State -eq 'Off' -or $vm.State -eq 'Saved') {
        Start-VM -Name $name | Out-Null
    }

    $stage = 'opening the Hyper-V console'
    Start-Process -FilePath "$env:SystemRoot\System32\vmconnect.exe" -ArgumentList @('localhost', $name)
}
catch {
    Add-Type -AssemblyName PresentationFramework
    $details = "Stage: $stage" + [Environment]::NewLine + [Environment]::NewLine + $_.Exception.Message
    [System.Windows.MessageBox]::Show(
        $details,
        'MixtarRVS Hyper-V launcher',
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Error
    ) | Out-Null
    exit 1
}
