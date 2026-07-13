#!/bin/sh
set -eu

VERSION="0.8"

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../../.." && pwd)
artifact="$repo_root/Server/Rootfs/Generated/corev07-root/System/EFI/MixtarRVS/$VERSION.efi"
provenance="$artifact.provenance"
config_root="$repo_root/Server/Rootfs/Generated/corev07-root/System/Configuration"
config_db="$config_root/MixtarRVS.config"
config_archive="$artifact.config.tar"
target="${MIXTAR_ONESHOT_TARGET:-vxz@192.168.99.112}"
identity="${MIXTAR_SSH_IDENTITY:-}"
windows_openssh="${MIXTAR_WINDOWS_OPENSSH:-0}"
windows_ssh="/mnt/c/Windows/System32/OpenSSH/ssh.exe"
windows_scp="/mnt/c/Windows/System32/OpenSSH/scp.exe"
remote_tmp="/tmp/MixtarRVS-$VERSION.efi"
remote_config_archive="/tmp/MixtarRVS-$VERSION.config.tar"
esp_mount="/boot/efi"
esp_rel="EFI/MixtarRVS/$VERSION.efi"
entry_label="MixtarRVS-$VERSION-OneShot"
entry_disk="/dev/nvme0n1"
entry_part="1"
data_part="3"
apply=0
reboot_after=0
probe_remote=1
replace_entry=0
allow_no_autoreturn=0

usage() {
    cat <<EOF
usage: corev07-oneshot-deploy.sh [--target USER@HOST] [--artifact PATH]
                                  [--identity PATH]
                                  [--windows-openssh]
                                  [--disk DEV] [--part N] [--data-part N]
                                  [--apply] [--replace-entry] [--reboot]
                                  [--allow-no-autoreturn]
                                  [--local-only]

Default mode is dry-run/read-only:
  - validates local EFI artifact
  - optionally probes the laptop over SSH using read-only commands
  - does not copy files
  - does not write ESP
  - does not write EFI variables
  - does not reboot

Mutation requires --apply.
Reboot additionally requires --reboot.
EOF
}

fail() {
    printf '%s\n' "corev07-oneshot-deploy: error: $*" >&2
    exit 1
}

note() {
    printf '%s\n' "corev07-oneshot-deploy: $*"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --target)
            [ $# -ge 2 ] || fail "missing --target value"
            target=$2
            shift 2
            ;;
        --artifact)
            [ $# -ge 2 ] || fail "missing --artifact value"
            artifact=$2
            shift 2
            ;;
        --identity)
            [ $# -ge 2 ] || fail "missing --identity value"
            identity=$2
            shift 2
            ;;
        --windows-openssh)
            windows_openssh=1
            shift
            ;;
        --disk)
            [ $# -ge 2 ] || fail "missing --disk value"
            entry_disk=$2
            shift 2
            ;;
        --part)
            [ $# -ge 2 ] || fail "missing --part value"
            entry_part=$2
            shift 2
            ;;
        --data-part)
            [ $# -ge 2 ] || fail "missing --data-part value"
            data_part=$2
            shift 2
            ;;
        --apply)
            apply=1
            shift
            ;;
        --reboot)
            reboot_after=1
            shift
            ;;
        --replace-entry)
            replace_entry=1
            shift
            ;;
        --allow-no-autoreturn)
            allow_no_autoreturn=1
            shift
            ;;
        --local-only)
            probe_remote=0
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            fail "unknown argument: $1"
            ;;
    esac
done

[ -s "$artifact" ] || fail "missing EFI artifact: $artifact"
[ -z "$identity" ] || [ -r "$identity" ] || fail "SSH identity is not readable: $identity"
provenance="$artifact.provenance"
[ -s "$provenance" ] || fail "missing EFI provenance: $provenance"
[ -d "$config_root" ] || fail "missing generated configuration: $config_root"
[ -s "$config_db" ] || fail "missing generated configuration database: $config_db"
command -v sha256sum >/dev/null 2>&1 || fail "missing local tool: sha256sum"
command -v strings >/dev/null 2>&1 || fail "missing local tool: strings"
command -v tar >/dev/null 2>&1 || fail "missing local tool: tar"

tar -C "$config_root" -cf "$config_archive" .
[ -s "$config_archive" ] || fail "failed to create configuration archive"

artifact_hash=$(sha256sum "$artifact" | awk '{print $1}')
provenance_hash=$(sha256sum "$provenance" | awk '{print $1}')
config_db_hash=$(sha256sum "$config_db" | awk '{print $1}')
config_archive_hash=$(sha256sum "$config_archive" | awk '{print $1}')
provenance_efi_hash=$(awk -F= '$1 == "efi_sha256" { print $2; exit }' "$provenance")
[ "$provenance_efi_hash" = "$artifact_hash" ] || fail "EFI provenance hash does not match artifact"
grep -Fqx "source_mode=build" "$provenance" || fail "EFI provenance does not prove source_mode=build"
artifact_strings=$(strings -a "$artifact")

printf '%s\n' "$artifact_strings" | grep -F "rdinit=/System/Init/MixtarRVS" >/dev/null 2>&1 ||
    fail "artifact lacks rdinit=/System/Init/MixtarRVS"
printf '%s\n' "$artifact_strings" | grep -F "init=/System/Init/MixtarRVS" >/dev/null 2>&1 ||
    fail "artifact lacks init=/System/Init/MixtarRVS"
printf '%s\n' "$artifact_strings" | grep -F "devtmpfs.mount=0" >/dev/null 2>&1 ||
    fail "artifact lacks devtmpfs.mount=0"
if [ "$allow_no_autoreturn" -eq 0 ]; then
    printf '%s\n' "$artifact_strings" | grep -F "mixtar.autoreturn=1" >/dev/null 2>&1 ||
        fail "artifact lacks mixtar.autoreturn=1"
    printf '%s\n' "$artifact_strings" | grep -F "mixtar.persist_logs=1" >/dev/null 2>&1 ||
        fail "artifact lacks mixtar.persist_logs=1"
    printf '%s\n' "$artifact_strings" | grep -F "panic=300" >/dev/null 2>&1 ||
        fail "artifact lacks panic=300"
fi

note "artifact: $artifact"
note "sha256:   $artifact_hash"
note "prov:     $provenance_hash"
note "target:   $target"
note "entry:    $entry_label"
note "loader:   \\EFI\\MixtarRVS\\$VERSION.efi"
note "disk:     $entry_disk partition $entry_part"
note "data:     $entry_disk partition $data_part"
note "config:   $config_db_hash"

run_ssh() {
    if [ "$windows_openssh" = "1" ]; then
        "$windows_ssh" "$@"
    elif [ -n "$identity" ]; then
        ssh -i "$identity" "$@"
    else
        ssh "$@"
    fi
}

copy_remote() {
    local_path=$1
    remote_path=$2
    if [ "$windows_openssh" = "1" ]; then
        windows_local_path=$(wslpath -w "$local_path")
        "$windows_scp" -o BatchMode=yes -o ConnectTimeout=8 "$windows_local_path" "$remote_path"
    elif [ -n "$identity" ]; then
        scp -i "$identity" -o BatchMode=yes -o ConnectTimeout=8 "$local_path" "$remote_path"
    else
        scp -o BatchMode=yes -o ConnectTimeout=8 "$local_path" "$remote_path"
    fi
}
if [ "$allow_no_autoreturn" -eq 1 ]; then
    note "autoreturn: disabled by explicit --allow-no-autoreturn"
fi

if [ "$probe_remote" -eq 1 ]; then
    if [ "$windows_openssh" = "1" ]; then
        [ -x "$windows_ssh" ] || fail "missing Windows OpenSSH client: $windows_ssh"
    else
        command -v ssh >/dev/null 2>&1 || fail "missing local tool: ssh"
    fi
    note "probing target read-only"
    run_ssh -o BatchMode=yes -o ConnectTimeout=8 "$target" \
        'set -eu
        printf "remote.hostname=%s\n" "$(hostname 2>/dev/null || true)"
        printf "remote.uname=%s\n" "$(uname -a 2>/dev/null || true)"
        if [ -d /sys/firmware/efi/efivars ]; then echo remote.uefi=yes; else echo remote.uefi=no; fi
        if sudo -n test -d /boot/efi/EFI 2>/dev/null; then echo remote.esp_path=yes; else echo remote.esp_path=no; fi
        if command -v findmnt >/dev/null 2>&1; then
            printf "remote.esp_source=%s\n" "$(findmnt -no SOURCE /boot/efi 2>/dev/null || true)"
        fi
        if command -v efibootmgr >/dev/null 2>&1; then
            echo remote.efibootmgr=yes
            efibootmgr | sed -n "1,12p"
        else
            echo remote.efibootmgr=no
        fi'
fi

if [ "$apply" -ne 1 ]; then
    note "dry-run complete; no remote mutation performed"
    note "rerun with --apply to copy EFI and set BootNext"
    note "add --reboot only when the one-shot boot should start immediately"
    exit 0
fi

if [ "$windows_openssh" = "1" ]; then
    [ -x "$windows_scp" ] || fail "missing Windows OpenSSH scp: $windows_scp"
    command -v wslpath >/dev/null 2>&1 || fail "missing local tool: wslpath"
else
    command -v scp >/dev/null 2>&1 || fail "missing local tool: scp"
fi

note "copying artifact to remote temporary path"
copy_remote "$artifact" "$target:$remote_tmp"
copy_remote "$provenance" "$target:$remote_tmp.provenance"
copy_remote "$config_archive" "$target:$remote_config_archive"

note "installing artifact and setting BootNext on remote target"
remote_runner="sudo -n sh -s"
case "$target" in
    root|root@*)
        remote_runner="sh -s"
        ;;
esac
run_ssh -o BatchMode=yes -o ConnectTimeout=8 "$target" \
    "$remote_runner -- '$remote_tmp' '$esp_mount' '$esp_rel' '$entry_label' '$entry_disk' '$entry_part' '$artifact_hash' '$reboot_after' '$replace_entry' '$VERSION' '$provenance_hash' '$remote_config_archive' '$config_db_hash' '$data_part' '$config_archive_hash'" <<'REMOTE'
set -eu

remote_tmp=$1
esp_mount=$2
esp_rel=$3
entry_label=$4
entry_disk=$5
entry_part=$6
expected_hash=$7
reboot_after=$8
replace_entry=$9
version=${10}
expected_provenance_hash=${11}
remote_config_archive=${12}
expected_config_db_hash=${13}
data_part=${14}
expected_config_archive_hash=${15}
loader="\\EFI\\MixtarRVS\\${version}.efi"
data_device="${entry_disk}p${data_part}"
data_mount="/mnt/mixtar-oneshot-data"

fail() {
    printf '%s\n' "remote-oneshot: error: $*" >&2
    exit 1
}

[ -s "$remote_tmp" ] || fail "missing uploaded artifact: $remote_tmp"
[ -s "$remote_tmp.provenance" ] || fail "missing uploaded provenance: $remote_tmp.provenance"
[ -s "$remote_config_archive" ] || fail "missing uploaded Mixtar configuration archive"
[ -d "$esp_mount/EFI" ] || fail "ESP path missing: $esp_mount/EFI"
command -v sha256sum >/dev/null 2>&1 || fail "sha256sum missing on remote"
command -v efibootmgr >/dev/null 2>&1 || fail "efibootmgr missing on remote"
command -v blkid >/dev/null 2>&1 || fail "blkid missing on remote"
command -v findmnt >/dev/null 2>&1 || fail "findmnt missing on remote"
command -v find >/dev/null 2>&1 || fail "find missing on remote"
command -v stat >/dev/null 2>&1 || fail "stat missing on remote"
command -v tar >/dev/null 2>&1 || fail "tar missing on remote"

esp_source=""
if command -v findmnt >/dev/null 2>&1; then
    esp_source=$(findmnt -no SOURCE "$esp_mount" 2>/dev/null || true)
fi
if [ -z "$esp_source" ]; then
    esp_source=$(awk -v mountpoint="$esp_mount" '$2 == mountpoint { print $1; exit }' /proc/mounts 2>/dev/null || true)
fi
[ -n "$esp_source" ] || fail "cannot identify ESP source for $esp_mount"

resolved_esp_source=$(readlink -f "$esp_source" 2>/dev/null || printf '%s\n' "$esp_source")
resolved_expected_a=$(readlink -f "${entry_disk}p${entry_part}" 2>/dev/null || printf '%s\n' "${entry_disk}p${entry_part}")
resolved_expected_b=$(readlink -f "${entry_disk}${entry_part}" 2>/dev/null || printf '%s\n' "${entry_disk}${entry_part}")
if [ "$resolved_esp_source" != "$resolved_expected_a" ] &&
   [ "$resolved_esp_source" != "$resolved_expected_b" ]; then
    fail "ESP source $resolved_esp_source does not match requested $entry_disk partition $entry_part"
fi

actual_hash=$(sha256sum "$remote_tmp" | awk '{print $1}')
[ "$actual_hash" = "$expected_hash" ] || fail "uploaded artifact hash mismatch"
actual_provenance_hash=$(sha256sum "$remote_tmp.provenance" | awk '{print $1}')
[ "$actual_provenance_hash" = "$expected_provenance_hash" ] || fail "uploaded provenance hash mismatch"
remote_provenance_efi_hash=$(awk -F= '$1 == "efi_sha256" { print $2; exit }' "$remote_tmp.provenance")
[ "$remote_provenance_efi_hash" = "$expected_hash" ] || fail "uploaded provenance does not match artifact"
uploaded_config_archive_hash=$(sha256sum "$remote_config_archive" | awk '{print $1}')
[ "$uploaded_config_archive_hash" = "$expected_config_archive_hash" ] || fail "uploaded configuration archive hash mismatch"
if tar -tf "$remote_config_archive" | grep -Eq '(^/|(^|/)\.\.(/|$))'; then
    fail "configuration archive contains an unsafe path"
fi

resolved_data_device=$(readlink -f "$data_device" 2>/dev/null || printf '%s\n' "$data_device")
[ -b "$resolved_data_device" ] || fail "Mixtar data partition is not a block device: $resolved_data_device"
data_fstype=$(blkid -s TYPE -o value "$resolved_data_device" 2>/dev/null || true)
[ "$data_fstype" = "ext4" ] || fail "Mixtar data partition must be ext4, got: ${data_fstype:-unknown}"
mkdir -p "$data_mount"
mounted_here=0
current_data_source=$(findmnt -rn -o SOURCE --mountpoint "$data_mount" 2>/dev/null || true)
if [ -z "$current_data_source" ]; then
    mount -t ext4 "$resolved_data_device" "$data_mount"
    mounted_here=1
else
    resolved_current_source=$(readlink -f "$current_data_source" 2>/dev/null || printf '%s\n' "$current_data_source")
    [ "$resolved_current_source" = "$resolved_data_device" ] || fail "data mount is occupied by $resolved_current_source"
fi
mkdir -p "$data_mount/System/Configuration" "$data_mount/Users"
tar -C "$data_mount/System/Configuration" -xf "$remote_config_archive"
chown -R 0:0 "$data_mount/System/Configuration"
find "$data_mount/System/Configuration" -xdev -type d -exec chmod 0755 {} +
find "$data_mount/System/Configuration" -xdev -type f -exec chmod 0644 {} +
if [ -d "$data_mount/System/Configuration/SSH/HostKeys" ]; then
    chmod 0700 "$data_mount/System/Configuration/SSH/HostKeys"
    find "$data_mount/System/Configuration/SSH/HostKeys" -xdev -type f ! -name '*.pub' -exec chmod 0600 {} +
fi
config_owner=$(stat -c '%u:%g' "$data_mount/System/Configuration")
[ "$config_owner" = "0:0" ] || fail "persistent configuration owner must be root:root, got: $config_owner"
config_mode=$(stat -c '%a' "$data_mount/System/Configuration")
[ "$config_mode" = "755" ] || fail "persistent configuration directory mode must be 0755, got: $config_mode"
config_db_mode=$(stat -c '%a' "$data_mount/System/Configuration/MixtarRVS.config")
[ "$config_db_mode" = "644" ] || fail "persistent configuration database mode must be 0644, got: $config_db_mode"
unsafe_config_path=$(find "$data_mount/System/Configuration" -xdev \( -type f -o -type d \) -perm /022 -print -quit)
[ -z "$unsafe_config_path" ] || fail "persistent configuration is writable by group/others: $unsafe_config_path"
installed_config_db_hash=$(sha256sum "$data_mount/System/Configuration/MixtarRVS.config" | awk '{print $1}')
[ "$installed_config_db_hash" = "$expected_config_db_hash" ] || fail "persistent configuration database hash mismatch"
install -D -m 0644 "$remote_tmp" "$data_mount/System/EFI/MixtarRVS/$version.efi"
install -D -m 0644 "$remote_tmp.provenance" "$data_mount/System/EFI/MixtarRVS/$version.efi.provenance"
installed_data_efi_hash=$(sha256sum "$data_mount/System/EFI/MixtarRVS/$version.efi" | awk '{print $1}')
[ "$installed_data_efi_hash" = "$expected_hash" ] || fail "persistent EFI artifact hash mismatch"
installed_data_provenance_hash=$(sha256sum "$data_mount/System/EFI/MixtarRVS/$version.efi.provenance" | awk '{print $1}')
[ "$installed_data_provenance_hash" = "$expected_provenance_hash" ] || fail "persistent EFI provenance hash mismatch"
sync
if [ "$mounted_here" = "1" ]; then
    umount "$data_mount"
fi

install -D -m 0644 "$remote_tmp" "$esp_mount/$esp_rel"
install -D -m 0644 "$remote_tmp.provenance" "$esp_mount/$esp_rel.provenance"
installed_hash=$(sha256sum "$esp_mount/$esp_rel" | awk '{print $1}')
[ "$installed_hash" = "$expected_hash" ] || fail "installed ESP artifact hash mismatch"
installed_provenance_hash=$(sha256sum "$esp_mount/$esp_rel.provenance" | awk '{print $1}')
[ "$installed_provenance_hash" = "$expected_provenance_hash" ] || fail "installed ESP provenance hash mismatch"


old_boot_order=$(efibootmgr | awk -F': ' '/^BootOrder:/ { print $2; exit }')
bootnum=$(
    efibootmgr |
    awk -v label="$entry_label" '
        index($0, label) {
            gsub(/^Boot/, "", $1)
            gsub(/\*.*/, "", $1)
            print $1
            exit
        }'
)

if [ "$replace_entry" = "1" ] && [ -n "$bootnum" ]; then
    efibootmgr -b "$bootnum" -B
    bootnum=""
fi

created_entry=0
if [ -z "$bootnum" ]; then
    efibootmgr -c -d "$entry_disk" -p "$entry_part" -L "$entry_label" -l "$loader"
    created_entry=1
    bootnum=$(
        efibootmgr |
        awk -v label="$entry_label" '
            index($0, label) {
                gsub(/^Boot/, "", $1)
                gsub(/\*.*/, "", $1)
                print $1
                exit
            }'
    )
fi

[ -n "$bootnum" ] || fail "could not resolve MixtarRVS EFI boot number"
if [ "$created_entry" = "1" ] && [ -n "$old_boot_order" ]; then
    efibootmgr -o "$old_boot_order"
fi
efibootmgr -n "$bootnum"
efibootmgr | sed -n '1,12p'
sync

if [ "$reboot_after" = "1" ]; then
    reboot
fi
REMOTE

note "remote BootNext prepared"
if [ "$reboot_after" -eq 1 ]; then
    note "remote reboot requested"
else
    note "rerun with --apply --reboot to start the one-shot boot immediately"
fi
