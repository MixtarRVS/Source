# Mixtar pre-v0 first boot (ThinkPad T480) practical runbook

Cel: uruchomic bootowalny Mixtar na osobnej partycji, bez automatycznego formatowania, z jednoznacznym potwierdzeniem zgody.

## Zalecenia

- Host buildowy: Linux z dostepem SSH do ThinkPada `vxz@192.168.99.110`
- Kernel: Linux na ThinkPadzie (np. `7.0.0-rc3-mixtarrvs`)
- Substrat: Alpine (`alpine-minirootfs`) + `musl` + `apk`
- Init: `openrc`
- Shell uzytkownika: `zsh`
- Builder: `mixtar-rebuild.sh` (bez Nixa)
- Instalacja na partycji wykonuje sie wyraznie po dodatkowej zgodzie operatora.

## 1) Aktualny manifest

Manifest:
- `Server/Rootfs/manifests/t480-pre-v0.mixtar.conf`

Domyslna konfiguracja zawiera teraz stale sciezki:
- `MIXTAR_BUILD_DIR="/home/vxz/mixtar-lab/builds/0002-alpine-openrc-zsh"`
- `MIXTAR_IMAGE_PATH="/home/vxz/mixtar-lab/images/mixtar-pre-v0-rootfs.ext4"`

## 2) Narzedzia

- `Server/Rootfs/tools/mixtar-safe-prep.sh` -- non-destructive
  - buduje rootfs
  - tworzy obraz ext4
  - sprawdza obraz
  - uruchamia preinstall-gate
  - nie formatuje partycji i nie pisze GRUB-a
- `Server/Rootfs/tools/mixtar-physical-install.sh` -- destrukcyjny
  - wymaga `--erase-device --write-grub`
  - wymaga dokladnego wpisania frazy:
    - `FORMAT <target_device> AS <root_label>`

## 3) Najszybsza sciezka uruchomienia

Najpierw tylko bezpieczny etap:

```sh
./Server/Installer/imported/Mixtar-OS-Setup/artifacts/mixtar-installer/scripts/first-boot-mixtar-t480.sh --safe-only
```

Po pomyslnym zakonczeniu:

```sh
./Server/Installer/imported/Mixtar-OS-Setup/artifacts/mixtar-installer/scripts/first-boot-mixtar-t480.sh --install-only
```

`--install-only` zatrzyma sie i poprosi o wpisanie frazy recznie (mozna tez podac `--phrase`).

Szybki wariant końcowy (safe + preinstall-gate + instalacja w jednej sesji):

```sh
./Server/Installer/imported/Mixtar-OS-Setup/artifacts/mixtar-installer/scripts/first-boot-mixtar-t480.sh \
  --host=192.168.99.110 --user=vxz \
  --manifest=Server/Rootfs/manifests/t480-pre-v0.mixtar.conf \
  --sequence --with-preinstall-gate --install-now \
  --phrase="FORMAT /dev/nvme0n1p3 AS MIXTARROOT"
```

Jesli chcesz wykonać to jeszcze bardziej przewidywalnie (safe, potem ręczna zgoda):

```sh
export MIXTAR_MANIFEST=./Server/Rootfs/manifests/t480-pre-v0.mixtar.conf
export MIXTAR_HOST=192.168.99.110
export MIXTAR_USER=vxz

./Server/Installer/imported/Mixtar-OS-Setup/artifacts/mixtar-installer/scripts/first-boot-mixtar-t480.sh --safe-only --host=$MIXTAR_HOST --user=$MIXTAR_USER --manifest=$MIXTAR_MANIFEST
./Server/Rootfs/tools/mixtar-rebuild.sh preinstall-gate "$MIXTAR_MANIFEST"
./Server/Rootfs/tools/mixtar-physical-install.sh install "$MIXTAR_MANIFEST" --erase-device --write-grub
# podczas prompta wpisz dokładnie:
# FORMAT /dev/nvme0n1p3 AS MIXTARROOT
```

Po reboocie sprawdź od razu:

```sh
sh ./Server/Rootfs/tools/mixtar-postboot-watch.sh --host=192.168.99.110 --user=vxz
mixtar-firstboot-verify && mixtar-generation-report && mixtar-postboot-report
cat /System/Logs/firstboot-evidence.txt
grep -n "/System/Shells/zsh" /etc/shells
rc-status
ls -la /System /Applications /Programs /Users /Compatibility
```

Przydatny wariant z jednoznacznym manifestem i hostem:

```sh
./Server/Installer/imported/Mixtar-OS-Setup/artifacts/mixtar-installer/scripts/first-boot-mixtar-t480.sh \
  --host=192.168.99.110 --user=vxz \
  --manifest=Server/Rootfs/manifests/t480-pre-v0.mixtar.conf \
  --safe-only
```

## 3b) Gotowy, jednozapisowy flow lokalny (kopiuj i wykonaj)

Jeśli chcesz zrobić to bezpośrednio i bez zgadywania komend:

```sh
export MIXTAR_MANIFEST=Server/Rootfs/manifests/t480-pre-v0.mixtar.conf
export MIXTAR_HOST=192.168.99.110
export MIXTAR_USER=vxz

./Server/Installer/imported/Mixtar-OS-Setup/artifacts/mixtar-installer/scripts/first-boot-mixtar-t480.sh \
  --host="$MIXTAR_HOST" \
  --user="$MIXTAR_USER" \
  --manifest="$MIXTAR_MANIFEST" \
  --safe-only
```

Po pozytywnych raportach:

```sh
./Server/Installer/imported/Mixtar-OS-Setup/artifacts/mixtar-installer/scripts/first-boot-mixtar-t480.sh \
  --host="$MIXTAR_HOST" \
  --user="$MIXTAR_USER" \
  --manifest="$MIXTAR_MANIFEST" \
  --install-only \
  --phrase="FORMAT /dev/nvme0n1p3 AS MIXTARROOT"
```

Polecenie `--install-only` jest destrukcyjne i zatrzyma się na frazie, więc nadal nie ma ryzyka niejawnego formatu.

### 3c) Jeszcze krócej (lokalny orchestrator)

W katalogu `Server/Rootfs/tools` dostępny jest helper:

```sh
sh ./Server/Rootfs/tools/mixtar-t480-firstboot.sh login-plan

sh ./Server/Rootfs/tools/mixtar-t480-firstboot.sh setup-login \
  --first-user=vxz --manifest=Server/Rootfs/manifests/t480-pre-v0.mixtar.conf

sh ./Server/Rootfs/tools/mixtar-t480-firstboot.sh safe \
  --host=192.168.99.110 --user=vxz --manifest=Server/Rootfs/manifests/t480-pre-v0.mixtar.conf

# Gdy chcesz przejść dalej:
sh ./Server/Rootfs/tools/mixtar-t480-firstboot.sh full \
  --phrase="FORMAT /dev/nvme0n1p3 AS MIXTARROOT" \
  --host=192.168.99.110 --user=vxz --manifest=Server/Rootfs/manifests/t480-pre-v0.mixtar.conf
```

`setup-login` pyta o hasło i zapisuje w manifeście tylko hash SHA-512 crypt. `safe` wykonuje bezpieczny przebieg z `preinstall-gate`. `full` najpierw sprawdza normalny login; jeśli `MIXTAR_FIRST_PASSWORD_HASH` nie jest ustawiony, zatrzyma się przed build/install. Awaryjnie można dodać `--allow-rescue-login`, ale wtedy świadomie bootujesz system dostępny głównie przez wpis rescue.

## 4) Co weryfikuje preinstall-gate

1. `preflight` (rootfs + target path)
2. `image-verify` (spojnosc obrazu)
3. `qemu` smoke (rescue i init)
4. `install` plan
5. `grub` plan

Przed `preinstall-gate` (lub zamiast niego), przydatne są także komendy:

```sh
export MIXTAR_MANIFEST=./Server/Rootfs/manifests/t480-pre-v0.mixtar.conf
./Server/Rootfs/tools/mixtar-rebuild.sh preinstall-gate "$MIXTAR_MANIFEST"
```

```sh
./Server/Rootfs/tools/mixtar-rebuild.sh qemu-plan "$MIXTAR_MANIFEST"
./Server/Rootfs/tools/mixtar-rebuild.sh qemu-rescue-smoke "$MIXTAR_MANIFEST"
./Server/Rootfs/tools/mixtar-rebuild.sh qemu-init-smoke "$MIXTAR_MANIFEST"
```

Dopiero po tym uruchamiasz krok destrukcyjny.

## 5) Po reboot

- Wybierz wpis `MixtarRVS pre-v0 Alpine/OpenRC/zsh` w GRUB.
- Rollback pozostaje dostepny jako wpisy starego systemu.
- Z maszyny kontrolnej uruchom:
  - `sh ./Server/Rootfs/tools/mixtar-postboot-watch.sh --host=192.168.99.110 --user=vxz`
  - wynik docelowy: `POSTBOOT_WATCH=ok`
- Jesli widzisz jedynie rescue shell:
  - sprawdz logi firstboot:
    - `/System/Logs/firstboot-evidence.txt`
  - Po poprawnym starcie wykonaj od razu:
    - `/System/Tools/mixtar-firstboot-verify`
    - `/System/Tools/mixtar-generation-report`
    - `/System/Tools/mixtar-postboot-report`
    - `cat /System/Logs/firstboot-evidence.txt`
    - `cat /System/Logs/firstboot-report.service.log`
- Kolejny krok to test logowania przez zwyklego usera:
  - `System/Shells/zsh` jako shell
  - normalny login wymaga ustawienia hash (`MIXTAR_FIRST_PASSWORD_HASH`).
