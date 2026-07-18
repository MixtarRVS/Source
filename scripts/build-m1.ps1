[CmdletBinding()]
param(
    [switch]$CleanCache,
    [switch]$SkipP0,
    [switch]$SkipQemu,
    [switch]$SkipP2,
    [switch]$ProductImageOnly,
    [switch]$TestHyperV,
    [string]$SwitchName,
    [string]$ReleaseLock = "Release/M1.lock.config",
    [string]$SigningDirectory = "Output/P3/Signing",
    [string]$CacheNamespace = ""
)
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$Repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$Utf8 = [Text.UTF8Encoding]::new($false)
$Timings = [ordered]@{}

function Invoke-Stage {
    param([string]$Name, [scriptblock]$Action)
    Write-Host "==> $Name"
    $clock = [Diagnostics.Stopwatch]::StartNew()
    try { & $Action }
    finally {
        $clock.Stop()
        $Timings[$Name] = [Math]::Round($clock.Elapsed.TotalSeconds, 3)
    }
}

function Resolve-Qemu {
    $candidates = @()
    if ($env:MIXTAR_QEMU) { $candidates += $env:MIXTAR_QEMU }
    $command = Get-Command qemu-system-x86_64.exe -ErrorAction SilentlyContinue
    if ($command) { $candidates += $command.Source }
    if ($env:ProgramFiles) { $candidates += (Join-Path $env:ProgramFiles "qemu\qemu-system-x86_64.exe") }
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return [IO.Path]::GetFullPath($candidate)
        }
    }
    throw "qemu-system-x86_64.exe was not found. Set MIXTAR_QEMU."
}

function Resolve-Firmware {
    param([string]$Qemu, [string]$EnvironmentName, [string[]]$Names)
    $configured = [Environment]::GetEnvironmentVariable($EnvironmentName)
    if ($configured -and (Test-Path -LiteralPath $configured -PathType Leaf)) {
        return [IO.Path]::GetFullPath($configured)
    }
    $directory = Split-Path -Parent $Qemu
    foreach ($base in @((Join-Path $directory "share"), (Join-Path (Split-Path -Parent $directory) "share\qemu"))) {
        foreach ($name in $Names) {
            $candidate = Join-Path $base $name
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { return [IO.Path]::GetFullPath($candidate) }
        }
    }
    throw "UEFI firmware was not found. Set $EnvironmentName."
}

function WslPath {
    param([string]$Distribution, [string]$Path)
    $value = @(& wsl.exe -d $Distribution -e wslpath -a -u ([IO.Path]::GetFullPath($Path)))
    if ($LASTEXITCODE -ne 0) { throw "wslpath failed for $Path" }
    return (@($value) -join "`n").Trim()
}

function FileRecord {
    param([string]$Path)
    $full = [IO.Path]::GetFullPath($Path)
    return [ordered]@{
        path = $full.Substring($Repository.Length + 1).Replace("\", "/")
        size = (Get-Item -LiteralPath $full).Length
        sha256 = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

Push-Location $Repository
try {
    $configText = @(& py.exe -3 scripts/mixtar_config.py json)
    if ($LASTEXITCODE -ne 0) { throw "Layout.config is invalid." }
    $config = (@($configText) -join "`n") | ConvertFrom-Json
    $lockText = @(& py.exe -3 scripts/mixtar_release.py json --lock $ReleaseLock)
    if ($LASTEXITCODE -ne 0) { throw "M1 release lock is invalid." }
    $lock = (@($lockText) -join "`n") | ConvertFrom-Json
    $distribution = $config.build.wsl_distro
    $signing = [IO.Path]::GetFullPath((Join-Path $Repository $SigningDirectory))
    [IO.Directory]::CreateDirectory($signing) | Out-Null
    $key = Join-Path $signing "M1.key.pem"
    $certificate = Join-Path $signing "M1.certificate.pem"
    $publicKey = Join-Path $signing "M1.public.pem"
    $certificateDer = Join-Path $signing "M1.certificate.cer"
    $wslKey = WslPath $distribution $key
    $wslCertificate = WslPath $distribution $certificate
    $wslPublicKey = WslPath $distribution $publicKey
    $wslCertificateDer = WslPath $distribution $certificateDer
    if (-not (Test-Path -LiteralPath $key) -or -not (Test-Path -LiteralPath $certificate)) {
        Invoke-Stage "Generate persistent M1 signing identity" {
            & wsl.exe -d $distribution -- /usr/bin/openssl req -new -x509 -newkey rsa:3072 -sha256 -nodes -days 3650 `
                -subj "/CN=MixtarRVS M1 Release/" -keyout $wslKey -out $wslCertificate
            if ($LASTEXITCODE -ne 0) { throw "Could not generate M1 signing identity." }
        }
    }
    & wsl.exe -d $distribution -- /usr/bin/openssl pkey -in $wslKey -pubout -out $wslPublicKey
    if ($LASTEXITCODE -ne 0) { throw "Could not export M1 public key." }
    & wsl.exe -d $distribution -- /usr/bin/openssl x509 -in $wslCertificate -outform DER -out $wslCertificateDer
    if ($LASTEXITCODE -ne 0) { throw "Could not export M1 Secure Boot certificate." }
    & wsl.exe -d $distribution -- bash -lc 'command -v sbsign >/dev/null && command -v sbverify >/dev/null'
    if ($LASTEXITCODE -ne 0) { throw "WSL requires sbsigntool (sbsign and sbverify)." }

    if ($CleanCache -and [string]::IsNullOrWhiteSpace($CacheNamespace)) {
        $CacheNamespace = "m1-clean-$([Guid]::NewGuid().ToString('N'))"
    }
    if (-not $SkipP0) {
        Invoke-Stage "Build pinned P0 from source" {
            $arguments = @{
                ReleaseLock = $ReleaseLock
                SigningKey = $key
                SigningCertificate = $certificate
            }
            if ($cacheNamespace) { $arguments.CacheNamespace = $cacheNamespace }
            & (Join-Path $PSScriptRoot "build-firstboot.ps1") @arguments
            if ($LASTEXITCODE -ne 0) { throw "Pinned P0 build failed." }
        }
    }
    $image = Invoke-Stage "Build signed immutable M1 image" {
        $arguments = @(
            "-3.14", (Join-Path $PSScriptRoot "build_m1_image.py"),
            "--profile", "Profiles/qemu-x86_64.toml",
            "--release-lock", $ReleaseLock,
            "--signing-key", $key,
            "--signing-certificate", $certificate,
            "--public-key", $publicKey
        )
        if ($cacheNamespace) { $arguments += @("--cache-namespace", $cacheNamespace) }
        $output = @(& py.exe @arguments)
        if ($LASTEXITCODE -ne 0) { throw "M1 image build failed." }
        return ((@($output) -join "`n") | ConvertFrom-Json)
    }
    if ($ProductImageOnly) {
        $image | ConvertTo-Json -Depth 8
        return
    }

    $qemu = $null
    $code = $null
    $vars = $null
    if (-not $SkipQemu) {
        $qemu = Resolve-Qemu
        $code = Resolve-Firmware $qemu MIXTAR_UEFI_CODE @("edk2-x86_64-code.fd")
        $vars = Resolve-Firmware $qemu MIXTAR_UEFI_VARS @("edk2-i386-vars.fd", "edk2-x86_64-vars.fd")
        if (-not $SkipP2) {
            Invoke-Stage "QEMU console, network, persistence, reboot and poweroff" {
                & py.exe -3.14 scripts/test-p2-console.py --qemu $qemu --firmware $code `
                    --firmware-vars $vars --disk $image.disk --report Output/P1/Qemu-p2.json
                if ($LASTEXITCODE -ne 0) { throw "P2 QEMU acceptance failed." }
            }
        }
        Invoke-Stage "QEMU corrupted update, A/B switch and recovery rollback" {
            & py.exe -3.14 scripts/test-p3-release.py --qemu $qemu --firmware $code `
                --firmware-vars $vars --disk $image.disk --efi-a $image.efi_a `
                --recovery-efi $image.recovery_efi --update $image.update `
                --corrupt-update $image.corrupt_update --report Output/P3/Qemu-p3.json
            if ($LASTEXITCODE -ne 0) { throw "P3 update and recovery acceptance failed." }
        }
    }

    $consoleReport = Join-Path $Repository "Output\P4\Console-independence.json"
    Invoke-Stage "P4 console independence regression" {
        $arguments = @(
            "-3.14", (Join-Path $PSScriptRoot "validate-console-independence.py"),
            "--manifest", $image.manifest,
            "--profile", (Join-Path $Repository "Profiles\qemu-x86_64.toml"),
            "--budget", (Join-Path $Repository "Root\System\Configuration\Product\P4.config"),
            "--report", $consoleReport
        )
        if (-not $SkipQemu -and -not $SkipP2) {
            $arguments += @("--runtime-report", (Join-Path $Repository "Output\P1\Qemu-p2.json"))
        }
        else {
            $arguments += "--allow-missing-runtime"
        }
        & py.exe @arguments
        if ($LASTEXITCODE -ne 0) { throw "P4 console independence regression failed." }
    }
    $sdk = Join-Path $Repository "Output\P1\Kernel-A\System\Kernel\Linux\$($lock.linux.version)\Modules\Development"
    Invoke-Stage "External module SDK" {
        & scripts/test-p3-sdk.ps1 -Sdk $sdk -SigningKey $key `
            -SigningCertificate $certificate -WslDistro $distribution
    }
    Invoke-Stage "Release integrity, FHS and Secure Boot signatures" {
        & py.exe -3.14 scripts/validate-p3-release.py --manifest $image.manifest `
            --signature $image.manifest_signature --public-key $publicKey `
            --certificate $certificate --lock $ReleaseLock --wsl-distro $distribution `
            --report Output/P3/Release-validation.json
        if ($LASTEXITCODE -ne 0) { throw "M1 release validation failed." }
    }
    if ($TestHyperV) {
        Invoke-Stage "Hyper-V Generation 2 acceptance" {
            $arguments = @{ ManifestPath = $image.manifest }
            if ($SwitchName) { $arguments.SwitchName = $SwitchName }
            & scripts/test-p2-hyperv.ps1 @arguments
        }
    }
    $acceptance = [ordered]@{
        qemu_p2 = (-not $SkipQemu -and -not $SkipP2)
        console_independence = $true
        qemu_p3 = (-not $SkipQemu)
        module_sdk = $true
        integrity = $true
        hyper_v = [bool]$TestHyperV
    }
    $releaseManifest = [ordered]@{
        schema = "mixtar.m1-release.v1"
        release = $lock.release
        clean_cache = [bool]$CleanCache
        cache_namespace = $cacheNamespace
        source_lock = FileRecord (Join-Path $Repository $ReleaseLock)
        image_manifest = FileRecord $image.manifest
        image_manifest_signature = FileRecord $image.manifest_signature
        disk = FileRecord $image.disk
        vhdx = FileRecord $image.vhdx
        public_key = FileRecord $publicKey
        secure_boot_certificate = FileRecord $certificateDer
        acceptance = $acceptance
        reports = [ordered]@{
            qemu_p2 = if (Test-Path -LiteralPath "Output/P1/Qemu-p2.json") { FileRecord "Output/P1/Qemu-p2.json" } else { $null }
            console_independence = FileRecord $consoleReport
            qemu_p3 = if (Test-Path -LiteralPath "Output/P3/Qemu-p3.json") { FileRecord "Output/P3/Qemu-p3.json" } else { $null }
            module_sdk = FileRecord "Output/P3/Module-SDK.json"
            release_validation = FileRecord "Output/P3/Release-validation.json"
            hyper_v = if (Test-Path -LiteralPath "Output/P1/HyperV-p2.json") { FileRecord "Output/P1/HyperV-p2.json" } else { $null }
        }
        timings_seconds = $Timings
    }
    [IO.Directory]::CreateDirectory((Join-Path $Repository "Output\P3")) | Out-Null
    $releasePath = Join-Path $Repository "Output\P3\M1.release.json"
    [IO.File]::WriteAllText($releasePath, ($releaseManifest | ConvertTo-Json -Depth 12) + "`n", $Utf8)
    $releaseSignature = Join-Path $Repository "Output\P3\M1.release.sig"
    & wsl.exe -d $distribution -- /usr/bin/openssl dgst -sha256 -sign $wslKey `
        -out (WslPath $distribution $releaseSignature) (WslPath $distribution $releasePath)
    if ($LASTEXITCODE -ne 0) { throw "Could not sign the final M1 release manifest." }
    Write-Host "MIXTAR_M1_PIPELINE_OK"
}
finally {
    Pop-Location
}
