param(
    [string]$Target = "vxz@192.168.99.110"
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "../../..")
$stageDir = Join-Path $repoRoot "Server/Rootfs/Generated/openssh-source"
$remoteScript = "/tmp/stage-mixtar-openssh.sh"
$remoteTar = "/tmp/mixtar-openssh-source.tar.gz"
$localScript = Join-Path $repoRoot "Server/Rootfs/Generated/stage-mixtar-openssh.sh"
$localTar = Join-Path $repoRoot "Server/Rootfs/Generated/mixtar-openssh-source.tar.gz"

$script = @'
#!/usr/bin/env bash
set -eu
out="/tmp/mixtar-openssh-source"
tarball="/tmp/mixtar-openssh-source.tar.gz"
rm -rf "$out" "$tarball"
mkdir -p "$out"

copy_path() {
  p="$1"
  if [ -e "$p" ]; then
    mkdir -p "$out/$(dirname "$p")"
    cp -a "$p" "$out/$p"
  fi
}

copy_binary_closure() {
  bin="$1"
  copy_path "$bin"
  ldd "$bin" 2>/dev/null | awk '
    /^[[:space:]]*\// { print $1; next }
    /=>[[:space:]]*\// { print $3; next }
  ' | while read -r lib; do
    [ -n "$lib" ] && copy_path "$lib"
  done
}

for bin in \
  /usr/sbin/sshd \
  /usr/bin/ssh \
  /usr/bin/ssh-keygen \
  /usr/bin/ip \
  /usr/lib/openssh/sftp-server \
  /usr/lib/openssh/sshd-session \
  /usr/lib/openssh/sshd-auth \
  /usr/lib/openssh/ssh-pkcs11-helper \
  /usr/lib/openssh/ssh-sk-helper
do
  if [ -x "$bin" ]; then
    copy_binary_closure "$bin"
  fi
done

for extra in \
  /lib64/ld-linux-x86-64.so.2 \
  /usr/lib/x86_64-linux-gnu/libnss_files.so.2 \
  /usr/lib/x86_64-linux-gnu/libnss_dns.so.2 \
  /usr/lib/x86_64-linux-gnu/libresolv.so.2 \
  /etc/ssh/moduli
do
  copy_path "$extra"
done

if [ -f "$HOME/.ssh/authorized_keys" ]; then
  mkdir -p "$out/authorized_keys"
  cp "$HOME/.ssh/authorized_keys" "$out/authorized_keys/vxz"
fi

(
  cd "$out"
  tar -czf "$tarball" .
)
echo "$tarball"
'@

New-Item -ItemType Directory -Force -Path (Split-Path $localScript) | Out-Null
[System.IO.File]::WriteAllText($localScript, ($script -replace "`r`n", "`n"), [System.Text.UTF8Encoding]::new($false))

scp -q -o BatchMode=yes -o ConnectTimeout=5 $localScript "${Target}:$remoteScript"
ssh -o BatchMode=yes -o ConnectTimeout=5 $Target "bash $remoteScript"
scp -q -o BatchMode=yes -o ConnectTimeout=5 "${Target}:$remoteTar" $localTar

if (Test-Path $stageDir) {
    Remove-Item -LiteralPath $stageDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $stageDir | Out-Null
tar -xzf $localTar -C $stageDir

Get-ChildItem -Recurse -File $stageDir |
    Select-Object -First 20 FullName,Length
