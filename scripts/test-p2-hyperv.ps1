[CmdletBinding()]
param(
    [string]$ManifestPath,
    [string]$SwitchName,
    [ValidateRange(60, 900)]
    [int]$TimeoutSeconds = 300,
    [switch]$KeepVM,
    [switch]$ElevatedChild
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$Repository = Split-Path -Parent $PSScriptRoot
$OutputDirectory = Join-Path $Repository 'Output\P1'
$Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$PlatformMarker = 'MixtarRVS: P2 platform services ready'
$ShutdownMarker = 'PID1: Received "poweroff"'
$BootOneMarker = 'MIXTAR_P2_HYPERV_BOOT1_OK'
$BootTwoMarker = 'MIXTAR_P2_HYPERV_BOOT2_OK'
$HistoryMarker = 'MIXTAR_P2_HYPERV_HISTORY'
$NetworkDiagnosticEndMarker = 'MIXTAR_P2_HYPERV_NET_DIAG_END'

if ($ManifestPath) {
    if (-not [System.IO.Path]::IsPathRooted($ManifestPath)) {
        $ManifestPath = Join-Path (Get-Location) $ManifestPath
    }
    $ManifestPath = [System.IO.Path]::GetFullPath($ManifestPath)
}

function ConvertTo-PowerShellLiteral {
    param([Parameter(Mandatory)] [string]$Value)
    return "'" + $Value.Replace("'", "''") + "'"
}

$Identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$Principal = [System.Security.Principal.WindowsPrincipal]::new($Identity)
$IsAdministrator = $Principal.IsInRole(
    [System.Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $IsAdministrator) {
    if ($ElevatedChild) {
        throw 'Hyper-V acceptance could not obtain an administrator token.'
    }

    [System.IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null
    $ElevationLog = Join-Path $OutputDirectory 'HyperV-p2-elevated.log'
    Remove-Item -LiteralPath $ElevationLog -Force -ErrorAction SilentlyContinue
    $Invocation = '& ' + (ConvertTo-PowerShellLiteral $PSCommandPath) +
        ' -ElevatedChild -TimeoutSeconds ' + $TimeoutSeconds
    if ($ManifestPath) {
        $Invocation += ' -ManifestPath ' + (ConvertTo-PowerShellLiteral $ManifestPath)
    }
    if ($SwitchName) {
        $Invocation += ' -SwitchName ' + (ConvertTo-PowerShellLiteral $SwitchName)
    }
    if ($KeepVM) {
        $Invocation += ' -KeepVM'
    }
    $LogLiteral = ConvertTo-PowerShellLiteral $ElevationLog
    $Invocation = 'try { ' + $Invocation + ' *> ' + $LogLiteral +
        '; if (-not $?) { exit 1 } } catch { $_ | Out-String | ' +
        'Add-Content -LiteralPath ' + $LogLiteral + '; exit 1 }; exit 0'
    $EncodedInvocation = [Convert]::ToBase64String(
        [System.Text.Encoding]::Unicode.GetBytes($Invocation)
    )
    $PowerShellPath = (Get-Process -Id $PID).Path
    $ElevatedProcess = Start-Process -FilePath $PowerShellPath -Verb RunAs `
        -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass',
            '-EncodedCommand', $EncodedInvocation
        ) -WindowStyle Hidden -Wait -PassThru
    if (Test-Path -LiteralPath $ElevationLog -PathType Leaf) {
        Get-Content -LiteralPath $ElevationLog
    }
    if ($ElevatedProcess.ExitCode -ne 0) {
        throw "Elevated Hyper-V P2 acceptance failed with exit code $($ElevatedProcess.ExitCode)."
    }
    return
}

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
    throw "P2 VHDX is missing: $VhdxPath"
}

Import-Module Hyper-V -ErrorAction Stop
$null = Hyper-V\Get-VMHost -ErrorAction Stop
$Switches = @(Hyper-V\Get-VMSwitch)
if ($SwitchName) {
    $SelectedSwitch = $Switches | Where-Object Name -eq $SwitchName | Select-Object -First 1
    if (-not $SelectedSwitch) {
        throw "Hyper-V switch does not exist: $SwitchName"
    }
}
else {
    $SelectedSwitch = $Switches | Where-Object Name -eq 'Default Switch' | Select-Object -First 1
    if (-not $SelectedSwitch) {
        $SelectedSwitch = $Switches | Where-Object SwitchType -eq 'External' | Select-Object -First 1
    }
    if (-not $SelectedSwitch) {
        $SelectedSwitch = $Switches | Where-Object SwitchType -eq 'Internal' | Select-Object -First 1
    }
    if (-not $SelectedSwitch) {
        throw 'P2 Hyper-V acceptance requires a DHCP-capable virtual switch.'
    }
}

function New-SerialPipe {
    param([Parameter(Mandatory)] [string]$Name)
    $Security = New-Object System.IO.Pipes.PipeSecurity
    $Everyone = New-Object System.Security.Principal.SecurityIdentifier(
        [System.Security.Principal.WellKnownSidType]::WorldSid,
        $null
    )
    $Rule = New-Object System.IO.Pipes.PipeAccessRule(
        $Everyone,
        [System.IO.Pipes.PipeAccessRights]::ReadWrite,
        [System.Security.AccessControl.AccessControlType]::Allow
    )
    $Security.AddAccessRule($Rule)
    return New-Object System.IO.Pipes.NamedPipeServerStream(
        $Name,
        [System.IO.Pipes.PipeDirection]::InOut,
        1,
        [System.IO.Pipes.PipeTransmissionMode]::Byte,
        [System.IO.Pipes.PipeOptions]::Asynchronous,
        4096,
        4096,
        $Security
    )
}

function Send-SerialLine {
    param(
        [Parameter(Mandatory)] [System.IO.Pipes.NamedPipeServerStream]$Pipe,
        [Parameter(Mandatory)] [string]$Value
    )
    $Bytes = [System.Text.Encoding]::ASCII.GetBytes($Value + "`r")
    $Pipe.Write($Bytes, 0, $Bytes.Length)
    $Pipe.Flush()
}

function Invoke-SerialBoot {
    param(
        [Parameter(Mandatory)] [string]$Phase,
        [Parameter(Mandatory)] [object[]]$Steps,
        [Parameter(Mandatory)] [string]$SuccessMarker,
        [Parameter(Mandatory)] [string]$LogPath
    )
    $Pipe = New-SerialPipe -Name $PipeName
    $Captured = New-Object System.Collections.Generic.List[byte]
    $Text = New-Object System.Text.StringBuilder
    $StepIndex = 0
    $TimedOut = $false
    $HostAdapterDuringBoot = $null
    try {
        $ConnectTask = $Pipe.WaitForConnectionAsync()
        Hyper-V\Start-VM -Name $VMName
        $HostAdapterDuringBoot = Hyper-V\Get-VMNetworkAdapter -VMName $VMName |
            Select-Object -First 1
        if (-not $ConnectTask.Wait(15000)) {
            throw "Hyper-V did not connect COM1 during $Phase."
        }
        $Buffer = New-Object byte[] 4096
        $ReadTask = $Pipe.ReadAsync($Buffer, 0, $Buffer.Length)
        $Deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
        while ([DateTime]::UtcNow -lt $Deadline) {
            if ($ReadTask.Wait(50)) {
                $ReadCount = $ReadTask.Result
                if ($ReadCount -eq 0) {
                    break
                }
                for ($Index = 0; $Index -lt $ReadCount; $Index++) {
                    $Captured.Add($Buffer[$Index])
                }
                $null = $Text.Append(
                    [System.Text.Encoding]::ASCII.GetString($Buffer, 0, $ReadCount)
                )
                $Buffer = New-Object byte[] 4096
                $ReadTask = $Pipe.ReadAsync($Buffer, 0, $Buffer.Length)
            }
            $SerialText = $Text.ToString()
            if ($StepIndex -lt $Steps.Count) {
                $Step = $Steps[$StepIndex]
                $Matched = $false
                foreach ($Needle in $Step.Need) {
                    if ($SerialText.Contains([string]$Needle)) {
                        $Matched = $true
                        break
                    }
                }
                if ($Matched) {
                    Send-SerialLine -Pipe $Pipe -Value ([string]$Step.Send)
                    $StepIndex++
                }
            }
            $VMState = (Hyper-V\Get-VM -Name $VMName).State
            if ($VMState -eq 'Off') {
                break
            }
        }
        if ([DateTime]::UtcNow -ge $Deadline) {
            $TimedOut = $true
        }
    }
    finally {
        $Pipe.Dispose()
        [System.IO.File]::WriteAllBytes($LogPath, $Captured.ToArray())
    }

    $SerialText = $Text.ToString()
    $OffDeadline = [DateTime]::UtcNow.AddSeconds(20)
    do {
        $VMState = (Hyper-V\Get-VM -Name $VMName).State
        if ($VMState -eq 'Off') { break }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $OffDeadline)

    $HostNetwork = $null
    if ($HostAdapterDuringBoot) {
        $HostNetwork = [ordered]@{
            name = [string]$HostAdapterDuringBoot.Name
            switch_name = [string]$HostAdapterDuringBoot.SwitchName
            status = [string]($HostAdapterDuringBoot.Status -join ',')
            connected = [bool]$HostAdapterDuringBoot.Connected
            mac_address = [string]$HostAdapterDuringBoot.MacAddress
            ip_addresses = @($HostAdapterDuringBoot.IPAddresses)
        }
    }

    $Markers = [ordered]@{
        platform_services = $SerialText.Contains($PlatformMarker)
        time = $SerialText.Contains('MixtarRVS: system clock ready')
        logging = $SerialText.Contains('MixtarRVS: persistent logging ready')
        devices = $SerialText.Contains('MixtarRVS: device manager ready')
        volumes = $SerialText.Contains('MixtarRVS: volume scan ready')
        openzfs_tuning = $SerialText.Contains('MixtarRVS: OpenZFS tuned')
        network_dns = $SerialText.Contains('MixtarRVS: network and DNS ready')
        success = $SerialText.Contains($SuccessMarker)
        controlled_shutdown = $SerialText.Contains($ShutdownMarker)
        all_steps_sent = $StepIndex -eq $Steps.Count
        vm_off = $VMState -eq 'Off'
    }
    return [ordered]@{
        phase = $Phase
        passed = -not ($Markers.Values -contains $false) -and -not $TimedOut
        timed_out = $TimedOut
        markers = $Markers
        host_network = $HostNetwork
        log = $LogPath.Substring($Repository.Length + 1).Replace('\', '/')
    }
}

$Suffix = ([guid]::NewGuid().ToString('N')).Substring(0, 10)
$VMName = "MixtarRVS-P2-Acceptance-$Suffix"
$PipeName = "mixtar-p2-$Suffix"
$PipePath = "\\.\pipe\$PipeName"
$TempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$WorkRoot = [System.IO.Path]::GetFullPath((Join-Path $TempRoot "MixtarRVS-P2-$Suffix"))
if (-not $WorkRoot.StartsWith($TempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Unsafe Hyper-V work directory: $WorkRoot"
}
$TestDisk = Join-Path $WorkRoot 'MixtarRVS-test.vhdx'
$BootOneLog = Join-Path $OutputDirectory 'HyperV-p2-boot1.log'
$BootTwoLog = Join-Path $OutputDirectory 'HyperV-p2-boot2.log'
$ReportPath = Join-Path $OutputDirectory 'HyperV-p2.json'
$VMCreated = $false
$Passed = $false
$Password = 'Mx' + ([guid]::NewGuid().ToString('N')).Substring(0, 24) + '9a'

$BootOneCommand = @(
    'bb=/System/Core/BusyBox/busybox; p2_ok=1;'
    '$bb grep -q ''ready = true'' /System/State/Platform/P2.config || p2_ok=0;'
    '$bb grep -q ''ready = true'' /System/State/Volumes/Status.config || p2_ok=0;'
    '$bb grep -q ''dns = "ready"'' /System/State/Network/Primary.config || p2_ok=0;'
    '$bb grep -q ''applied = true'' /System/State/OpenZFS/Tuning.config || p2_ok=0;'
    ('print -s -- ' + $HistoryMarker + '; fc -W "$HISTFILE";')
    'p2_marker=MIXTAR_P2_HYPERV_BOOT1_;'
    'if (( p2_ok )); then print -r -- "${p2_marker}OK"; else print -r -- "${p2_marker}FAILED"; fi;'
    '$bb sleep 5; /System/Init/openrc-shutdown -p now'
) -join ' '
$BootTwoCommand = @(
    'bb=/System/Core/BusyBox/busybox; p2_ok=1;'
    ('$bb grep -q ' + $HistoryMarker + ' "$HISTFILE" || p2_ok=0;')
    '$bb grep -q ''^shutdown_epoch = [1-9]'' /System/State/Time/Clock.config || p2_ok=0;'
    '$bb grep -q ''dns = "ready"'' /System/State/Network/Primary.config || p2_ok=0;'
    'p2_marker=MIXTAR_P2_HYPERV_BOOT2_;'
    'if (( p2_ok )); then print -r -- "${p2_marker}OK"; else print -r -- "${p2_marker}FAILED"; fi;'
    '$bb sleep 5; /System/Init/openrc-shutdown -p now'
) -join ' '
$BootOneDiagnosticCommand = @(
    'bb=/System/Core/BusyBox/busybox;'
    'print -r -- MIXTAR_P2_HYPERV_NET_DIAG_BEGIN;'
    '$bb cat /System/Hardware/class/net/eth0/carrier 2>/System/Devices/null;'
    '$bb cat /System/Hardware/class/net/eth0/operstate 2>/System/Devices/null;'
    '$bb ip address show dev eth0;'
    '$bb cat /System/Runtime/Network/eth0.udhcpc.log 2>/System/Devices/null;'
    '$bb cat /System/State/Network/Primary.config 2>/System/Devices/null;'
    ('print -r -- ' + $NetworkDiagnosticEndMarker)
) -join ' '
$BootOneSteps = @(
    [ordered]@{ Need = @('New password:', 'Enter new password:'); Send = $Password },
    [ordered]@{ Need = @('Retype password:', 'Retype new password:'); Send = $Password },
    [ordered]@{ Need = @('login:'); Send = 'Administrator' },
    [ordered]@{ Need = @('Password:'); Send = $Password },
    [ordered]@{ Need = @('root@MixtarRVS'); Send = $BootOneDiagnosticCommand },
    [ordered]@{ Need = @($NetworkDiagnosticEndMarker); Send = $BootOneCommand }
)
$BootTwoSteps = @(
    [ordered]@{ Need = @('login:'); Send = 'Superuser' },
    [ordered]@{ Need = @('Password:'); Send = $Password },
    [ordered]@{ Need = @('root@MixtarRVS'); Send = $BootTwoCommand }
)

[System.IO.Directory]::CreateDirectory($WorkRoot) | Out-Null
Remove-Item -LiteralPath $BootOneLog, $BootTwoLog, $ReportPath -Force -ErrorAction SilentlyContinue
try {
    Hyper-V\New-VHD -Path $TestDisk -ParentPath $VhdxPath -Differencing | Out-Null
    $VM = Hyper-V\New-VM -Name $VMName -Generation 2 `
        -MemoryStartupBytes 2GB -Path $WorkRoot -NoVHD
    $VMCreated = $true
    Hyper-V\Set-VM -VM $VM -AutomaticCheckpointsEnabled $false `
        -AutomaticStartAction Nothing -AutomaticStopAction TurnOff
    Hyper-V\Set-VMProcessor -VM $VM -Count 2
    Hyper-V\Set-VMMemory -VM $VM -DynamicMemoryEnabled $false
    $Disk = Hyper-V\Add-VMHardDiskDrive -VM $VM -ControllerType SCSI `
        -ControllerNumber 0 -ControllerLocation 0 -Path $TestDisk -Passthru
    $NetworkAdapter = Hyper-V\Get-VMNetworkAdapter -VM $VM | Select-Object -First 1
    if ($NetworkAdapter) {
        Hyper-V\Connect-VMNetworkAdapter -VMNetworkAdapter $NetworkAdapter `
            -SwitchName $SelectedSwitch.Name
    }
    else {
        Hyper-V\Add-VMNetworkAdapter -VM $VM -SwitchName $SelectedSwitch.Name | Out-Null
    }
    Hyper-V\Set-VMFirmware -VM $VM -EnableSecureBoot Off `
        -ConsoleMode COM1 -FirstBootDevice $Disk
    Hyper-V\Set-VMComPort -VM $VM -Number 1 -Path $PipePath -DebuggerMode On

    $BootOne = Invoke-SerialBoot -Phase boot1 -Steps $BootOneSteps `
        -SuccessMarker $BootOneMarker -LogPath $BootOneLog
    if ($BootOne.passed) {
        $BootTwo = Invoke-SerialBoot -Phase boot2 -Steps $BootTwoSteps `
            -SuccessMarker $BootTwoMarker -LogPath $BootTwoLog
    }
    else {
        $BootTwo = [ordered]@{ phase = 'boot2'; passed = $false; skipped = $true }
    }

    $Report = [ordered]@{
        schema = 'mixtar.p2-hyperv-generation2.v1'
        passed = $BootOne.passed -and $BootTwo.passed
        source_vhdx = $Manifest.artifacts.vhdx.path
        hypervisor = [ordered]@{
            generation = 2
            secure_boot = $false
            console = 'COM1'
            processors = 2
            switch = $SelectedSwitch.Name
        }
        phases = [ordered]@{ boot1 = $BootOne; boot2 = $BootTwo }
    }
    [System.IO.File]::WriteAllText(
        $ReportPath,
        (($Report | ConvertTo-Json -Depth 16) + [Environment]::NewLine),
        $Utf8NoBom
    )
    if (-not $Report.passed) {
        throw "Hyper-V P2 acceptance failed; see $ReportPath"
    }
    $Passed = $true
}
finally {
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
        $Resolved = [System.IO.Path]::GetFullPath($WorkRoot)
        if ($Resolved.StartsWith($TempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $Resolved -Recurse -Force
        }
    }
}

if ($Passed) {
    Write-Output 'HYPERV_P2_OK'
    Write-Output $ReportPath
}