param(
    [string]$Target = "vxz@192.168.99.110",
    [string]$Image = "Server/Rootfs/Generated/mixtar-ail-native-initramfs.cpio.gz",
    [switch]$Reboot
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "../../..")
$imagePath = Resolve-Path (Join-Path $repoRoot $Image)
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$initrd = "initrd-mixtarrvs-networking-ssh-$stamp.img"
$label = "MixtarRVS-Networking-SSH-$stamp"
$remoteDeploy = "/tmp/deploy-mixtarrvs-networking-ssh.sh"
$remoteReboot = if ($Reboot) { "1" } else { "0" }

$deployTemplate = @'
#!/usr/bin/env bash
set -euo pipefail
initrd="__INITRD__"
label="__LABEL__"
do_reboot="__REBOOT__"
src="/tmp/$initrd"
dst="/boot/efi/EFI/mixtarrvs-rt/$initrd"
cmdline="initrd=\\EFI\\mixtarrvs-rt\\$initrd root=UUID=146d4ab3-3e58-4317-8799-da2f451b9a6c rootfstype=ext4 rootflags=ro modules=nvme,ext4,jbd2,mbcache rootwait ro quiet loglevel=3 threadirqs mixtar.profile=rt-7.1.2-mixtar-rt devtmpfs.mount=0 firmware_class.path=/System/Kernel/Linux/Firmware rdinit=/System/Init/MixtarRVS"

sudo -n test -d /boot/efi/EFI/mixtarrvs-rt
sudo -n test -f /boot/efi/EFI/mixtarrvs-rt/vmlinuz.efi
sudo -n test -s "$src"

old_order="$(sudo -n efibootmgr | awk -F': ' '/^BootOrder:/ { print $2; exit }')"
default_route="$(ip route show default 2>/dev/null || true)"

sudo -n install -m 0644 "$src" "$dst"
sudo -n efibootmgr -c -d /dev/nvme0n1 -p 1 -L "$label" -l '\EFI\mixtarrvs-rt\vmlinuz.efi' -u "$cmdline" >/tmp/mixtarrvs-networking-ssh-efibootmgr.out
entry="$(sudo -n efibootmgr | awk -v label="$label" '$0 ~ label {gsub(/^Boot/, "", $1); gsub(/\*/, "", $1); print $1; exit}')"
if [[ -z "$entry" ]]; then
  cat /tmp/mixtarrvs-networking-ssh-efibootmgr.out >&2
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
echo "deploy: previous_boot_order=$old_order"
echo "deploy: current_default_route=$default_route"
if echo "$default_route" | grep -q ' dev wlan'; then
  echo "deploy: warning: current SSH route uses Wi-Fi; native Mixtar networking SSH image currently proves QEMU/Ethernet, not Wi-Fi/iwd autoconnect"
fi
sudo -n efibootmgr | sed -n '1,12p'

if [[ "$do_reboot" == "1" ]]; then
  echo "deploy: rebooting to BootNext entry"
  sudo -n reboot
else
  echo "deploy: reboot not requested; run this script with -Reboot when ready"
fi
'@

$deployScript = $deployTemplate.
    Replace("__INITRD__", $initrd).
    Replace("__LABEL__", $label).
    Replace("__REBOOT__", $remoteReboot)

$localDeploy = Join-Path $repoRoot "Server/Rootfs/Generated/deploy-mixtarrvs-networking-ssh-latest.sh"
[System.IO.File]::WriteAllText($localDeploy, ($deployScript -replace "`r`n", "`n"), [System.Text.UTF8Encoding]::new($false))

ssh -o BatchMode=yes -o ConnectTimeout=5 $Target "hostname; uname -a; sudo -n true; ip route show default || true"
scp -q -o BatchMode=yes -o ConnectTimeout=5 $imagePath "${Target}:/tmp/$initrd"
scp -q -o BatchMode=yes -o ConnectTimeout=5 $localDeploy "${Target}:$remoteDeploy"
ssh -o BatchMode=yes -o ConnectTimeout=5 $Target "bash $remoteDeploy"
