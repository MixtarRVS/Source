[CmdletBinding()]
param(
    [string]$WslDistro = "",
    [string]$KernelVersion = "",
    [ValidateRange(0, 256)]
    [int]$Jobs = 0,
    [string]$CacheNamespace = "",
    [string]$HostCacheBase = "",
    [string]$ReleaseLock = "Release/M1.lock.config",
    [string]$SigningKey = "",
    [string]$SigningCertificate = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Invoke-Checked {
    param(
        [Parameter(Mandatory)]
        [string]$Label,
        [Parameter(Mandatory)]
        [string]$FilePath,
        [string[]]$ArgumentList = @()
    )

    Write-Host "==> $Label"
    & $FilePath @ArgumentList
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "$Label failed with exit code $exitCode."
    }
}

function Get-FileRecord {
    param(
        [Parameter(Mandatory)]
        [string]$RelativePath
    )

    $normalizedPath = $RelativePath.Replace("\", "/")
    $fullPath = Join-Path $repoRoot $RelativePath
    $item = Get-Item -LiteralPath $fullPath
    return [ordered]@{
        path = $normalizedPath
        size = $item.Length
        sha256 = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

function Get-WslSha256 {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $output = & wsl.exe -d $WslDistro -e sha256sum $Path
    if ($LASTEXITCODE -ne 0) {
        throw "Could not hash WSL file: $Path"
    }
    $line = (@($output) -join "`n").Trim()
    if ($line -notmatch '^([0-9a-fA-F]{64})\s') {
        throw "Unexpected sha256sum output for $Path"
    }
    return $Matches[1].ToLowerInvariant()
}

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
Push-Location -LiteralPath $repoRoot
try {
    Write-Host "==> Load Layout.config"
    $configOutput = @(& py.exe -3 "Scripts/mixtar_config.py" json)
    if ($LASTEXITCODE -ne 0) {
        throw "Could not load Layout.config."
    }
    try {
        $mixtarConfig = (@($configOutput) -join "`n") | ConvertFrom-Json
    }
    catch {
        throw "Layout.config reader returned invalid JSON: $($_.Exception.Message)"
    }
    Write-Host "==> Load pinned release lock"
    $releaseOutput = @(& py.exe -3 "Scripts/mixtar_release.py" json --lock $ReleaseLock)
    if ($LASTEXITCODE -ne 0) {
        throw "Could not load the pinned release lock."
    }
    try {
        $releaseConfig = (@($releaseOutput) -join "`n") | ConvertFrom-Json
    }
    catch {
        throw "Release lock reader returned invalid JSON: $($_.Exception.Message)"
    }
    if ([string]::IsNullOrWhiteSpace($WslDistro)) {
        $WslDistro = $mixtarConfig.build.wsl_distro
    }
    if ([string]::IsNullOrWhiteSpace($KernelVersion)) {
        $KernelVersion = $releaseConfig.linux.version
    }
    if ($Jobs -eq 0) {
        if ($mixtarConfig.build.jobs -eq "auto") {
            $jobsOutput = @(& wsl.exe -d $WslDistro -e nproc)
            if ($LASTEXITCODE -ne 0) {
                throw "Could not resolve automatic WSL build parallelism."
            }
            $jobsText = (@($jobsOutput) -join "`n").Trim()
            $resolvedJobs = 0
            if (-not [int]::TryParse($jobsText, [ref]$resolvedJobs) -or $resolvedJobs -lt 1) {
                throw "Unexpected nproc output: $jobsText"
            }
            $Jobs = $resolvedJobs
        }
        else {
            $Jobs = [int]$mixtarConfig.build.jobs
        }
    }

    $wslRepoInput = $repoRoot.Replace('\', '/')
    $wslRepoOutput = & wsl.exe -d $WslDistro -e wslpath -a -u $wslRepoInput
    if ($LASTEXITCODE -ne 0) {
        throw "Could not resolve the repository path in WSL."
    }
    $wslRepo = (@($wslRepoOutput) -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($wslRepo)) {
        throw "WSL returned an empty repository path."
    }

    $wslHomeOutput = & wsl.exe -d $WslDistro -- bash -lc 'printf "%s" "$HOME"'
    if ($LASTEXITCODE -ne 0) {
        throw "Could not resolve the WSL user home directory."
    }
    $wslHome = (@($wslHomeOutput) -join "`n").Trim()
    if ($wslHome -notmatch '^/[A-Za-z0-9._/-]+$') {
        throw "Unexpected WSL home directory: $wslHome"
    }
    if (-not [string]::IsNullOrWhiteSpace($CacheNamespace) -and
        $CacheNamespace -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
        throw "Unexpected cache namespace: $CacheNamespace"
    }
    $wslCacheHome = "$wslHome/$($mixtarConfig.build.cache_directory)"
    if ([string]::IsNullOrWhiteSpace($HostCacheBase)) {
        $hostCacheRoot = [IO.Path]::GetFullPath(
            (Join-Path $repoRoot $mixtarConfig.build.host_cache)
        )
        $repoPrefix = $repoRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
        if (-not $hostCacheRoot.StartsWith(
            $repoPrefix,
            [StringComparison]::OrdinalIgnoreCase
        )) {
            throw "Configured host cache must remain inside the repository."
        }
    }
    else {
        $hostCacheRoot = [IO.Path]::GetFullPath($HostCacheBase)
        if ($hostCacheRoot -eq [IO.Path]::GetPathRoot($hostCacheRoot)) {
            throw "Host cache base cannot be a filesystem root."
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($CacheNamespace)) {
        $wslCacheHome = "$wslCacheHome/$CacheNamespace"
        $hostCacheRoot = Join-Path $hostCacheRoot $CacheNamespace
    }
    $wslCacheRoot = "$wslCacheHome/mixtar"
    $hostKernelCache = Join-Path $hostCacheRoot "Kernel"

    $p0Directory = Join-Path $repoRoot $mixtarConfig.build.p0_output
    New-Item -ItemType Directory -Force -Path $p0Directory | Out-Null
    Invoke-Checked -Label "Validate P0 source contract" -FilePath "py.exe" -ArgumentList @(
        "-3",
        "Scripts/validate-p0-contract.py",
        "--report", (Join-Path $p0Directory "Contract.json")
    )

    $kernelArguments = @(
        "-3",
        "-m", "mixtar_builder.kernel_cli",
        "--cache", $hostKernelCache,
        "--wsl-distro", $WslDistro,
        "--version", $KernelVersion,
        "--archive-url", $releaseConfig.linux.url,
        "--archive-sha256", $releaseConfig.linux.sha256,
        "--patch", $releaseConfig.linux.patch,
        "build",
        "--wsl-cache-home", $wslCacheHome,
        "--source-date-epoch", $mixtarConfig.boot.source_date_epoch.ToString(),
        "--jobs", $Jobs.ToString()
    )
    if (-not [string]::IsNullOrWhiteSpace($SigningKey) -or -not [string]::IsNullOrWhiteSpace($SigningCertificate)) {
        if ([string]::IsNullOrWhiteSpace($SigningKey) -or [string]::IsNullOrWhiteSpace($SigningCertificate)) {
            throw "SigningKey and SigningCertificate must be supplied together."
        }
        $kernelArguments += @(
            "--module-signing-key", $SigningKey,
            "--module-signing-certificate", $SigningCertificate
        )
    }
    if ($mixtarConfig.build.compiler_cache) {
        $kernelArguments += @(
            "--compiler-cache",
            "--compiler-cache-size", $mixtarConfig.build.compiler_cache_size
        )
    }
    Write-Host "==> Build Linux kernel"
    $kernelOutput = @(& py.exe @kernelArguments)
    $kernelExitCode = $LASTEXITCODE
    $kernelOutput | ForEach-Object { Write-Host $_ }
    if ($kernelExitCode -ne 0) {
        throw "Build Linux kernel failed with exit code $kernelExitCode."
    }
    $kernelResultText = (@($kernelOutput) -join "`n").Trim()
    try {
        $kernelResult = $kernelResultText | ConvertFrom-Json
    }
    catch {
        throw "kernel_cli returned invalid JSON: $($_.Exception.Message)"
    }
    if ([string]::IsNullOrWhiteSpace($kernelResult.manifest) -or
        [string]::IsNullOrWhiteSpace($kernelResult.executable)) {
        throw "kernel_cli did not return manifest and executable paths."
    }
    $kernelManifestPath = $kernelResult.manifest
    $kernelExecutablePath = $kernelResult.executable

    $openrcBuildCommand = "env XDG_CACHE_HOME='$wslCacheHome' SOURCE_DATE_EPOCH='$($mixtarConfig.boot.source_date_epoch)' MIXTAR_OPENRC_REPOSITORY='$($releaseConfig.openrc.repository)' MIXTAR_OPENRC_COMMIT='$($releaseConfig.openrc.commit)' MIXTAR_JOBS='$Jobs' bash Scripts/build-openrc-mixtar.sh"
    $busyboxBuildCommand = "env XDG_CACHE_HOME='$wslCacheHome' SOURCE_DATE_EPOCH='$($mixtarConfig.boot.source_date_epoch)' MIXTAR_BUSYBOX_REPOSITORY='$($releaseConfig.busybox.repository)' MIXTAR_BUSYBOX_COMMIT='$($releaseConfig.busybox.commit)' MIXTAR_JOBS='$Jobs' bash Scripts/build-busybox-mixtar.sh"
    Invoke-Checked -Label "Build OpenRC and BusyBox" -FilePath "wsl.exe" -ArgumentList @(
        "-d", $WslDistro,
        "--cd", $wslRepo,
        "bash", "-lc",
        "$openrcBuildCommand && $busyboxBuildCommand"
    )

    $wslBusyBox = "$wslCacheRoot/busybox/stage/System/Core/BusyBox/busybox"
    $busyboxAppletOutput = @(& wsl.exe -d $WslDistro -e $wslBusyBox --list)
    if ($LASTEXITCODE -ne 0) {
        throw "Could not read the staged BusyBox applet list."
    }
    $busyboxApplets = @($busyboxAppletOutput | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_ } | Sort-Object)
    $expectedBusyboxApplets = @($mixtarConfig.components.busybox.expected_applets | ForEach-Object { $_.ToString() } | Sort-Object)
    $busyboxDifference = @(Compare-Object -ReferenceObject $expectedBusyboxApplets -DifferenceObject $busyboxApplets)
    if ($busyboxDifference.Count -ne 0) {
        throw "Staged BusyBox applets differ from Layout.config: $($busyboxDifference | Out-String)"
    }

    $initramfsCommand = "env XDG_CACHE_HOME='$wslCacheHome' SOURCE_DATE_EPOCH='$($mixtarConfig.boot.source_date_epoch)' MIXTAR_TEST_COMMAND_LINE_KEY='$($mixtarConfig.test.command_line_key)' MIXTAR_TEST_POWEROFF_MODE='$($mixtarConfig.test.poweroff_mode)' MIXTAR_TEST_REBOOT_MODE='$($mixtarConfig.test.reboot_mode)' bash Scripts/build-openrc-firstboot.sh"
    Invoke-Checked -Label "Build first-boot initramfs" -FilePath "wsl.exe" -ArgumentList @(
        "-d", $WslDistro,
        "-u", "root",
        "--cd", $wslRepo,
        "bash", "-lc", $initramfsCommand
    )

    $wslInitramfs = "$wslCacheRoot/firstboot/MixtarRVS-firstboot.cpio.gz"
    $wslOutputInitramfs = "$($wslRepo)/Output/P0/MixtarRVS-firstboot.cpio.gz"
    Invoke-Checked -Label "Publish first-boot initramfs" -FilePath "wsl.exe" -ArgumentList @(
        "-d", $WslDistro,
        "-u", "root",
        "-e", "install", "-D", "-m", "0644",
        $wslInitramfs,
        $wslOutputInitramfs
    )

    $kernelManifest = Get-Content -Raw -LiteralPath (Join-Path $repoRoot $kernelManifestPath) | ConvertFrom-Json
    $patchRecords = @(
        Get-ChildItem -LiteralPath (Join-Path $repoRoot "Patches") -Recurse -File -Filter "*.patch" |
            Sort-Object FullName |
            ForEach-Object {
                $relativePath = $_.FullName.Substring($repoRoot.Length + 1)
                Get-FileRecord -RelativePath $relativePath
            }
    )
    $inputRecords = @(
        "Kernel/x86_64-mixtar.config",
        "mixtar_builder/kernel_cli.py",
        "mixtar_builder/kernel_source.py",
        "mixtar_builder/kernel_build.py",
        "Scripts/build-firstboot.ps1",
        "Scripts/build-openrc-mixtar.sh",
        "Scripts/build-busybox-mixtar.sh",
        "Scripts/build-openrc-firstboot.sh",
        "Scripts/boot-openrc-firstboot.sh",
        "Scripts/mixtar_config.py",
        "Scripts/validate-p0-contract.py",
        "Root/System/Configuration/Layout.config",
        "Root/System/Core/Platform/initialize",
        "Root/System/Terminal/ZSH/zsh"
    ) | ForEach-Object { Get-FileRecord -RelativePath $_ }

    $buildManifest = [ordered]@{
        schema = "mixtar.p0-build-manifest.v1"
        target = [ordered]@{
            architecture = $mixtarConfig.identity.architecture
            boot_mode = "direct-kernel-initramfs"
        }
        sources = [ordered]@{
            linux = $kernelManifest
            openrc = [ordered]@{
                version = $releaseConfig.openrc.version
                url = $releaseConfig.openrc.repository
                commit = $releaseConfig.openrc.commit
            }
            busybox = [ordered]@{
                version = $releaseConfig.busybox.version
                repository = $releaseConfig.busybox.repository
                commit = $releaseConfig.busybox.commit
            }
            zsh = [ordered]@{
                version = $releaseConfig.zsh.version
                origin = $releaseConfig.zsh.origin
            }
        }
        inputs = [ordered]@{
            files = @($inputRecords)
            patches = @($patchRecords)
        }
        embedded = [ordered]@{
            openrc_pid1_sha256 = Get-WslSha256 -Path "$wslCacheRoot/openrc/stage/System/Init/MixtarRVS"
            busybox_sh_sha256 = Get-WslSha256 -Path "$wslCacheRoot/busybox/stage/System/Terminal/POSIX/sh"
            busybox_applets = @($busyboxApplets)
            zsh_sha256 = (Get-FileRecord -RelativePath "Root/System/Terminal/ZSH/zsh").sha256
        }
        artifacts = [ordered]@{
            contract = Get-FileRecord -RelativePath "Output/P0/Contract.json"
            kernel = Get-FileRecord -RelativePath $kernelExecutablePath
            initramfs = Get-FileRecord -RelativePath "Output/P0/MixtarRVS-firstboot.cpio.gz"
        }
    }
    $utf8 = [Text.UTF8Encoding]::new($false)
    $buildManifestFile = Join-Path $p0Directory "Build.json"
    $buildManifestJson = $buildManifest | ConvertTo-Json -Depth 12
    [IO.File]::WriteAllText($buildManifestFile, $buildManifestJson + "`n", $utf8)

    $wslKernel = "$($wslRepo)/$($kernelExecutablePath.Replace('\', '/'))"

    function Invoke-QemuAcceptance {
        param(
            [Parameter(Mandatory)]
            [string]$Mode,
            [Parameter(Mandatory)]
            [string]$Pid1Action,
            [Parameter(Mandatory)]
            [string]$ReportStem,
            [Parameter(Mandatory)]
            [string]$ActionMarker,
            [Parameter(Mandatory)]
            [string]$KernelMarker,
            [Parameter(Mandatory)]
            [string]$SuccessMarker
        )

        Write-Host "==> Verify $Mode in QEMU"
        $wslLogName = if ($Mode -eq "poweroff") { "Qemu-firstboot.log" } else { "Qemu-reboot.log" }
        $wslLog = "$($wslRepo)/Output/P0/$wslLogName"
        $qemuArguments = @(
            "-d", $WslDistro,
            "--cd", $wslRepo,
            "env",
            "MIXTAR_QEMU_MEMORY_MIB=$($mixtarConfig.boot.qemu_memory_mib)",
            "MIXTAR_QEMU_TIMEOUT_SECONDS=$($mixtarConfig.boot.qemu_timeout_seconds)",
            "MIXTAR_CONSOLE=$($mixtarConfig.boot.console)",
            "MIXTAR_PID1=$($mixtarConfig.boot.pid1)",
            "MIXTAR_TEST_COMMAND_LINE_KEY=$($mixtarConfig.test.command_line_key)",
            "MIXTAR_TEST_POWEROFF_MODE=$($mixtarConfig.test.poweroff_mode)",
            "MIXTAR_TEST_REBOOT_MODE=$($mixtarConfig.test.reboot_mode)",
            "bash", "Scripts/boot-openrc-firstboot.sh",
            $Mode,
            $wslKernel,
            $wslInitramfs,
            $wslLog
        )
        $qemuStopwatch = [Diagnostics.Stopwatch]::StartNew()
        $qemuOutput = @(& wsl.exe @qemuArguments 2>&1)
        $qemuExitCode = $LASTEXITCODE
        $qemuStopwatch.Stop()
        $qemuLines = @($qemuOutput | ForEach-Object { $_.ToString() })
        $qemuLines | ForEach-Object { Write-Host $_ }
        $qemuLogText = ($qemuLines -join "`n") + "`n"
        $qemuLogFile = Join-Path $p0Directory "$ReportStem.log"
        [IO.File]::WriteAllText($qemuLogFile, $qemuLogText, $utf8)

        $pid1Marker = "PID1: Received `"$Pid1Action`" from FIFO"
        $markers = [ordered]@{
            platform_namespace_ready = $qemuLogText.Contains("MixtarRVS: platform namespace ready")
            zsh_ready = $qemuLogText.Contains("MixtarRVS: zsh $($releaseConfig.zsh.version) ready")
            controlled_action = $qemuLogText.Contains($ActionMarker)
            pid1_accepted = $qemuLogText.Contains($pid1Marker)
            kernel_completed = $qemuLogText.Contains($KernelMarker)
            acceptance_marker = $qemuLogText.Contains($SuccessMarker)
        }
        $allMarkersPresent = -not ($markers.Values -contains $false)
        $qemuPassed = ($qemuExitCode -eq 0) -and $allMarkersPresent
        $qemuReport = [ordered]@{
            schema = "mixtar.qemu-shutdown-report.v1"
            mode = $Mode
            completed_at_utc = [DateTime]::UtcNow.ToString("o")
            passed = $qemuPassed
            exit_code = $qemuExitCode
            duration_milliseconds = $qemuStopwatch.ElapsedMilliseconds
            build_manifest_sha256 = (Get-FileHash -LiteralPath $buildManifestFile -Algorithm SHA256).Hash.ToLowerInvariant()
            markers = $markers
            raw_log = "Output/P0/$ReportStem.log"
        }
        $qemuReportFile = Join-Path $p0Directory "$ReportStem.json"
        [IO.File]::WriteAllText($qemuReportFile, ($qemuReport | ConvertTo-Json -Depth 6) + "`n", $utf8)
        if (-not $qemuPassed) {
            throw "QEMU $Mode verification failed with exit code $qemuExitCode."
        }
    }

    Invoke-QemuAcceptance -Mode $mixtarConfig.test.poweroff_mode -Pid1Action "poweroff" -ReportStem "Qemu-firstboot" -ActionMarker "MixtarRVS: requesting controlled poweroff" -KernelMarker "reboot: Power down" -SuccessMarker "FIRST_BOOT_OK"
    Invoke-QemuAcceptance -Mode $mixtarConfig.test.reboot_mode -Pid1Action "reboot" -ReportStem "Qemu-reboot" -ActionMarker "MixtarRVS: requesting controlled reboot" -KernelMarker "reboot: Restarting system" -SuccessMarker "REBOOT_OK"

    Write-Host "FIRST_BOOT_PIPELINE_OK"
}
finally {
    Pop-Location
}
