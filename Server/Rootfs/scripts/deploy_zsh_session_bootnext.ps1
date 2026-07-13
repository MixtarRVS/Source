param(
    [string]$Target = "vxz@192.168.99.110",
    [string]$Image = "Server/Rootfs/Generated/mixtar-ail-native-initramfs.cpio.gz"
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "../../..")
$imagePath = Resolve-Path (Join-Path $repoRoot $Image)
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$initrd = "initrd-mixtarrvs-zsh-session-$stamp.img"
$label = "MixtarRVS-ZSH-Session-$stamp"
$remoteDeploy = "/tmp/deploy-mixtarrvs-zsh-session.sh"

$deployTemplate = @'
#!/usr/bin/env bash
set -euo pipefail
initrd="__INITRD__"
label="__LABEL__"
src="/tmp/$initrd"
dst="/boot/efi/EFI/mixtarrvs-rt/$initrd"
cmdline="initrd=\\EFI\\mixtarrvs-rt\\$initrd root=UUID=146d4ab3-3e58-4317-8799-da2f451b9a6c rootfstype=ext4 rootflags=ro modules=nvme,ext4,jbd2,mbcache rootwait ro quiet loglevel=3 threadirqs mixtar.profile=rt-7.1.2-mixtar-rt devtmpfs.mount=0 rdinit=/System/Init/MixtarRVS"

sudo -n test -d /boot/efi/EFI/mixtarrvs-rt
sudo -n test -f /boot/efi/EFI/mixtarrvs-rt/vmlinuz.efi
old_order="$(sudo -n efibootmgr | awk -F': ' '/^BootOrder:/ { print $2; exit }')"
sudo -n install -m 0644 "$src" "$dst"
sudo -n efibootmgr -c -d /dev/nvme0n1 -p 1 -L "$label" -l '\EFI\mixtarrvs-rt\vmlinuz.efi' -u "$cmdline" >/tmp/mixtarrvs-zsh-session-efibootmgr.out
entry="$(sudo -n efibootmgr | awk -v label="$label" '$0 ~ label {gsub(/^Boot/, "", $1); gsub(/\*/, "", $1); print $1; exit}')"
if [[ -z "$entry" ]]; then
  cat /tmp/mixtarrvs-zsh-session-efibootmgr.out >&2
  echo "deploy: failed to locate created boot entry" >&2
  exit 1
fi
sudo -n efibootmgr -n "$entry"
if [[ -n "$old_order" ]]; then
  restored_order="$old_order"
  case ",$old_order," in
    *",$entry,"*) ;;
    *)
      first="${old_order%%,*}"
      rest="${old_order#*,}"
      if [[ "$rest" == "$old_order" ]]; then
        restored_order="$old_order,$entry"
      else
        restored_order="$first,$entry,$rest"
      fi
      ;;
  esac
  sudo -n efibootmgr -o "$restored_order" >/dev/null
  sudo -n efibootmgr -n "$entry" >/dev/null
fi
echo "deploy: initrd=$dst"
echo "deploy: label=$label"
echo "deploy: bootnext=$entry"
sudo -n efibootmgr | sed -n '1,12p'
'@

$deployScript = $deployTemplate.Replace("__INITRD__", $initrd).Replace("__LABEL__", $label)

$localDeploy = Join-Path $repoRoot "Server/Rootfs/Generated/deploy-mixtarrvs-zsh-session-latest.sh"
[System.IO.File]::WriteAllText($localDeploy, ($deployScript -replace "`r`n", "`n"), [System.Text.UTF8Encoding]::new($false))

ssh -o BatchMode=yes -o ConnectTimeout=5 $Target "hostname; uname -a; sudo -n true"
scp -q -o BatchMode=yes -o ConnectTimeout=5 $imagePath "${Target}:/tmp/$initrd"
scp -q -o BatchMode=yes -o ConnectTimeout=5 $localDeploy "${Target}:$remoteDeploy"
ssh -o BatchMode=yes -o ConnectTimeout=5 $Target "bash $remoteDeploy"
