[CmdletBinding()]
param(
    [string]$ManifestPath,
    [ValidateRange(30, 600)]
    [int]$TimeoutSeconds = 120,
    [switch]$KeepVM
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$Repository = Split-Path -Parent $PSScriptRoot
$OutputDirectory = Join-Path $Repository 'Output\P1'
$Utf8NoBom = [System.Text.UTF8Encoding]::new($false)

if (-not $ManifestPath) {
    $Candidates = @(Get-ChildItem -LiteralPath $OutputDirectory `
        -Filter '*.manifest.json' -File)
    if ($Candidates.Count -ne 1) {
        throw "Expected exactly one P1 manifest, found $($Candidates.Count)."
    }
    $ManifestPath = $Candidates[0].FullName
}
if (-not [System.IO.Path]::IsPathRooted($ManifestPath)) {
    $ManifestPath = Join-Path (Get-Location) $ManifestPath
}
$ManifestPath = [System.IO.Path]::GetFullPath($ManifestPath)
$Manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
$VhdxPath = $Manifest.artifacts.vhdx.path
if (-not [System.IO.Path]::IsPathRooted($VhdxPath)) {
    $VhdxPath = Join-Path $Repository $VhdxPath
}
$VhdxPath = [System.IO.Path]::GetFullPath($VhdxPath)
if (-not (Test-Path -LiteralPath $VhdxPath -PathType Leaf)) {
    throw "P1 VHDX is missing: $VhdxPath"
}

Import-Module Hyper-V -ErrorAction Stop
try {
    $null = Hyper-V\Get-VMHost -ErrorAction Stop
}
catch {
    throw "Hyper-V access is required. Run this script from an elevated PowerShell: $($_.Exception.Message)"
}

$Suffix = ([guid]::NewGuid().ToString('N')).Substring(0, 10)
$VMName = "MixtarRVS-P1-Acceptance-$Suffix"
$PipeName = "mixtar-p1-$Suffix"
$PipePath = "\\.\pipe\$PipeName"
$TempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$WorkRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $TempRoot "MixtarRVS-P1-$Suffix")
)
if (-not $WorkRoot.StartsWith(
    $TempRoot,
    [System.StringComparison]::OrdinalIgnoreCase
)) {
    throw "Unsafe Hyper-V work directory: $WorkRoot"
}
$TestDisk = Join-Path $WorkRoot 'MixtarRVS-test.vhdx'
$LogPath = Join-Path $OutputDirectory 'HyperV-p1.log'
$ReportPath = Join-Path $OutputDirectory 'HyperV-p1.json'
$PipeServer = $null
$VMCreated = $false
$Passed = $false

Remove-Item -LiteralPath $LogPath, $ReportPath -Force `
    -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $WorkRoot -Force | Out-Null
try {
    Hyper-V\New-VHD -Path $TestDisk -ParentPath $VhdxPath `
        -Differencing | Out-Null
    $VM = Hyper-V\New-VM -Name $VMName -Generation 2 `
        -MemoryStartupBytes 1GB -Path $WorkRoot -NoVHD
    $VMCreated = $true
    Hyper-V\Set-VM -VM $VM -AutomaticCheckpointsEnabled $false `
        -AutomaticStartAction Nothing -AutomaticStopAction TurnOff
    Hyper-V\Set-VMProcessor -VM $VM -Count 2
    Hyper-V\Set-VMMemory -VM $VM -DynamicMemoryEnabled $false
    $Disk = Hyper-V\Add-VMHardDiskDrive -VM $VM -ControllerType SCSI `
        -ControllerNumber 0 -ControllerLocation 0 -Path $TestDisk -Passthru
    Hyper-V\Set-VMFirmware -VM $VM -EnableSecureBoot Off `
        -ConsoleMode COM1 -FirstBootDevice $Disk
    Hyper-V\Set-VMComPort -VM $VM -Number 1 -Path $PipePath `
        -DebuggerMode On

    $PipeSecurity = New-Object System.IO.Pipes.PipeSecurity
    $Everyone = New-Object System.Security.Principal.SecurityIdentifier(
        [System.Security.Principal.WellKnownSidType]::WorldSid,
        $null
    )
    $PipeRule = New-Object System.IO.Pipes.PipeAccessRule(
        $Everyone,
        [System.IO.Pipes.PipeAccessRights]::ReadWrite,
        [System.Security.AccessControl.AccessControlType]::Allow
    )
    $PipeSecurity.AddAccessRule($PipeRule)
    $PipeServer = New-Object System.IO.Pipes.NamedPipeServerStream(
        $PipeName,
        [System.IO.Pipes.PipeDirection]::InOut,
        1,
        [System.IO.Pipes.PipeTransmissionMode]::Byte,
        [System.IO.Pipes.PipeOptions]::Asynchronous,
        4096,
        4096,
        $PipeSecurity
    )
    $ConnectTask = $PipeServer.WaitForConnectionAsync()
    Hyper-V\Start-VM -VM $VM
    if (-not $ConnectTask.Wait(15000)) {
        throw "Hyper-V did not connect COM1 to its named pipe."
    }

    $Captured = New-Object System.Collections.Generic.List[byte]
    $Text = New-Object System.Text.StringBuilder
    $Buffer = New-Object byte[] 1
    $ReadTask = $PipeServer.ReadAsync($Buffer, 0, 1)
    $CommandSent = $false
    $ShutdownSent = $false
    $PromptMarker = 'MixtarRVS# '
    $ResultMarker = 'MIXTAR_P1_CONSOLE_OK'
    $ShutdownMarker = 'PID1: Received "poweroff"'
    $SerialDeadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)

    while ([DateTime]::UtcNow -lt $SerialDeadline) {
        if ($ReadTask.Wait(50)) {
            $ReadCount = $ReadTask.Result
            if ($ReadCount -eq 0) {
                break
            }
            $Byte = $Buffer[0]
            $Captured.Add($Byte)
            $null = $Text.Append([char]$Byte)
            $Buffer = New-Object byte[] 1
            $ReadTask = $PipeServer.ReadAsync($Buffer, 0, 1)
        }
        $SerialText = $Text.ToString()
        if (-not $CommandSent -and $SerialText.Contains($PromptMarker)) {
            $Command = [System.Text.Encoding]::ASCII.GetBytes(
                "printf 'MIXTAR_P1_%s\n' CONSOLE_OK`r`n"
            )
            foreach ($ByteToWrite in $Command) {
                $PipeServer.WriteByte($ByteToWrite)
                $PipeServer.Flush()
                Start-Sleep -Milliseconds 10
            }
            $CommandSent = $true
        }
        elseif ($CommandSent -and -not $ShutdownSent -and
            $SerialText.Contains($ResultMarker)) {
            $Shutdown = [System.Text.Encoding]::ASCII.GetBytes(
                "/System/Init/openrc-shutdown -p now`r`n"
            )
            foreach ($ByteToWrite in $Shutdown) {
                $PipeServer.WriteByte($ByteToWrite)
                $PipeServer.Flush()
                Start-Sleep -Milliseconds 10
            }
            $ShutdownSent = $true
        }
        elseif ($ShutdownSent -and $SerialText.Contains($ShutdownMarker)) {
            break
        }
    }
    $SerialText = $Text.ToString()
    [System.IO.File]::WriteAllBytes($LogPath, $Captured.ToArray())

    $Markers = [ordered]@{
        firmware_fallback_loaded = $SerialText.Contains('Linux version')
        zfs_root_mounted = $SerialText.Contains('MixtarRVS: ZFS root mounted')
        zfs_root_ready = $SerialText.Contains('MixtarRVS: ZFS root ready')
        root_mounted = $SerialText.Contains('OpenRC init version')
        openrc_zsh_ready = (
            $SerialText.Contains('MixtarRVS: zsh ') -and
            $SerialText.Contains(' ready')
        )
        console_ready = $SerialText.Contains($PromptMarker)
        console_prompt = $SerialText.Contains($PromptMarker)
        console_command = $SerialText.Contains($ResultMarker)
        shutdown_requested = $SerialText.Contains($ShutdownMarker)
    }
    $OffDeadline = [DateTime]::UtcNow.AddSeconds(15)
    do {
        $VMState = (Hyper-V\Get-VM -Name $VMName).State
        if ($VMState -eq 'Off') {
            break
        }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $OffDeadline)
    $VMOff = $VMState -eq 'Off'
    $Markers['vm_off'] = $VMOff
    $Report = [ordered]@{
        schema = 'mixtar.p1-hyperv-generation2.v1'
        passed = -not ($Markers.Values -contains $false)
        timed_out = [DateTime]::UtcNow -ge $SerialDeadline
        markers = $Markers
        raw_log = 'Output/P1/HyperV-p1.log'
        hypervisor = [ordered]@{
            generation = 2
            secure_boot = $false
            console = 'COM1'
        }
        source_vhdx = $Manifest.artifacts.vhdx.path
    }
    [System.IO.File]::WriteAllText(
        $ReportPath,
        (($Report | ConvertTo-Json -Depth 12) + [Environment]::NewLine),
        $Utf8NoBom
    )
    if (-not $Report.passed) {
        throw "Hyper-V Generation 2 acceptance failed; see $ReportPath"
    }
    $Passed = $true
}
finally {
    if ($PipeServer) {
        $PipeServer.Dispose()
    }
    if ($VMCreated -and -not $KeepVM) {
        try {
            $ExistingVM = Hyper-V\Get-VM -Name $VMName -ErrorAction SilentlyContinue
            if ($ExistingVM) {
                if ($ExistingVM.State -ne 'Off') {
                    Hyper-V\Stop-VM -VM $ExistingVM -TurnOff -Force
                }
                Hyper-V\Remove-VM -VM $ExistingVM -Force
            }
        }
        catch {
            Write-Warning "Failed to remove temporary VM ${VMName}: $($_.Exception.Message)"
        }
    }
    if (-not $KeepVM -and (Test-Path -LiteralPath $WorkRoot)) {
        $ResolvedWorkRoot = [System.IO.Path]::GetFullPath($WorkRoot)
        if ($ResolvedWorkRoot.StartsWith(
            $TempRoot,
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
            Remove-Item -LiteralPath $ResolvedWorkRoot -Recurse -Force
        }
        else {
            Write-Warning "Refusing to remove unsafe work directory: $ResolvedWorkRoot"
        }
    }
}

if ($Passed) {
    Write-Output "HYPERV_P1_OK"
    Write-Output $ReportPath
}
