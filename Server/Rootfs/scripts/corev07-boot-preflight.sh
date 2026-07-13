#!/bin/sh
set -eu

VERSION="0.8"
KERNEL_VERSION="7.1.2"

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../../.." && pwd)
rootfs_dir="$repo_root/Server/Rootfs"
generated_dir="$rootfs_dir/Generated"
stage_root="$generated_dir/corev07-root"
efi_stage="$generated_dir/corev07-efi"
case "$repo_root" in
    /mnt/*)
        default_kernel_workspace="${HOME:-/tmp}/.cache/mixtarrvs-corev07/kernel"
        ;;
    *)
        default_kernel_workspace="$repo_root/Server/Kernel/Generated"
        ;;
esac
kernel_workspace="${MIXTARRVS_COREV07_KERNEL_WORKSPACE:-$default_kernel_workspace}"
kernel_build_dir="${KERNEL_BUILD_DIR:-$kernel_workspace/build/linux-$KERNEL_VERSION-mixtar-rt}"
firmware_dir="$repo_root/Server/Kernel/Generated/firmware"
iwlwifi_firmware_name="iwlwifi-8265-36.ucode"
regulatory_db_name="regulatory.db"
regulatory_db_signature_name="regulatory.db.p7s"
embedded_firmware_names="$iwlwifi_firmware_name $regulatory_db_name $regulatory_db_signature_name"

failures=0

usage() {
    cat <<EOF
usage: corev07-boot-preflight.sh [--root PATH] [--efi-stage PATH]

Performs a local bootability preflight for CoreV07 staging.
It does not deploy, boot, reboot, write EFI variables, mount ESP, or mutate Debian.
EOF
}

ok() {
    printf '%s\n' "OK: $*"
}

fail_check() {
    failures=$((failures + 1))
    printf '%s\n' "FAIL: $*"
}

require_cmd() {
    name=$1
    if command -v "$name" >/dev/null 2>&1; then
        ok "tool available: $name"
    else
        fail_check "required preflight tool missing: $name"
    fi
}

check_file() {
    path=$1
    label=$2
    if [ -s "$stage_root$path" ]; then
        ok "$label exists: $path"
    else
        fail_check "$label missing or empty: $path"
    fi
}

check_executable() {
    path=$1
    label=$2
    if [ -x "$stage_root$path" ]; then
        ok "$label executable: $path"
    elif [ -f "$stage_root$path" ]; then
        fail_check "$label exists but is not executable: $path"
    else
        fail_check "$label missing: $path"
    fi
}

check_dir() {
    path=$1
    label=$2
    if [ -d "$stage_root$path" ]; then
        ok "$label directory: $path"
    else
        fail_check "$label missing: $path"
    fi
}

check_absent() {
    path=$1
    label=$2
    if [ -e "$stage_root$path" ] || [ -L "$stage_root$path" ]; then
        fail_check "$label must not exist: $path"
    else
        ok "$label absent: $path"
    fi
}

check_efi_pair() {
    root_efi="$stage_root/System/EFI/MixtarRVS/$VERSION.efi"
    mirror_efi="$efi_stage/EFI/MixtarRVS/$VERSION.efi"

    if [ ! -s "$root_efi" ]; then
        fail_check "root EFI missing: /System/EFI/MixtarRVS/$VERSION.efi"
        return
    fi
    if [ ! -s "$mirror_efi" ]; then
        fail_check "EFI mirror missing: EFI/MixtarRVS/$VERSION.efi"
        return
    fi

    root_hash=$(sha256sum "$root_efi" | awk '{print $1}')
    mirror_hash=$(sha256sum "$mirror_efi" | awk '{print $1}')
    if [ "$root_hash" = "$mirror_hash" ]; then
        ok "EFI mirror matches staged root artifact"
    else
        fail_check "EFI mirror differs from staged root artifact"
    fi
}

check_efi_provenance() {
    efi="$stage_root/System/EFI/MixtarRVS/$VERSION.efi"
    provenance="$efi.provenance"
    if [ ! -s "$provenance" ]; then
        fail_check "EFI provenance missing: /System/EFI/MixtarRVS/$VERSION.efi.provenance"
        return
    fi
    expected_hash=$(sha256sum "$efi" | awk '{print $1}')
    actual_hash=$(awk -F= '$1 == "efi_sha256" { print $2; exit }' "$provenance")
    if [ "$actual_hash" = "$expected_hash" ]; then
        ok "EFI provenance hash matches official EFI"
    else
        fail_check "EFI provenance hash mismatch"
    fi
    for required in \
        "format=MixtarRVS-EFI-Provenance-v1" \
        "core=CoreV07" \
        "release=$VERSION" \
        "source_mode=build" \
        "builder=corev07-build-efi.sh" \
        "kernel_version=$KERNEL_VERSION"; do
        if grep -Fqx "$required" "$provenance"; then
            ok "EFI provenance declares $required"
        else
            fail_check "EFI provenance missing $required"
        fi
    done
}
check_efi_format() {
    efi="$stage_root/System/EFI/MixtarRVS/$VERSION.efi"
    [ -s "$efi" ] || return

    magic=$(dd if="$efi" bs=2 count=1 2>/dev/null || true)
    if [ "$magic" = "MZ" ]; then
        ok "EFI has PE/MZ header"
    else
        fail_check "EFI lacks PE/MZ header"
    fi

    if objdump -f "$efi" 2>/dev/null | grep -F "pei-x86-64" >/dev/null 2>&1; then
        ok "EFI object format is pei-x86-64"
    else
        fail_check "EFI object format is not pei-x86-64"
    fi

    sections=$(objdump -h "$efi" 2>/dev/null || true)
    if printf '%s\n' "$sections" | grep -F ".linux" >/dev/null 2>&1 &&
       printf '%s\n' "$sections" | grep -F ".initrd" >/dev/null 2>&1 &&
       printf '%s\n' "$sections" | grep -F ".cmdline" >/dev/null 2>&1; then
        ok "EFI layout is UKI-style"
    elif printf '%s\n' "$sections" | grep -F ".setup" >/dev/null 2>&1 &&
         printf '%s\n' "$sections" | grep -F ".text" >/dev/null 2>&1 &&
         printf '%s\n' "$sections" | grep -F ".data" >/dev/null 2>&1; then
        ok "EFI layout is Linux EFI-stub style"
    else
        fail_check "EFI has neither UKI nor Linux EFI-stub section layout"
    fi
}

check_efi_cmdline() {
    efi="$stage_root/System/EFI/MixtarRVS/$VERSION.efi"
    [ -s "$efi" ] || return
    require_autoreturn="${COREV07_REQUIRE_AUTORETURN:-0}"

    cmdline=$(strings -a "$efi" | grep -F "rdinit=/System/Init/MixtarRVS" | head -1 || true)
    if [ -n "$cmdline" ]; then
        ok "EFI embeds Mixtar rdinit cmdline"
    else
        fail_check "EFI does not embed rdinit=/System/Init/MixtarRVS"
    fi

    case "$cmdline" in
        *"init=/System/Init/MixtarRVS"*) ok "EFI cmdline embeds init=/System/Init/MixtarRVS" ;;
        *) fail_check "EFI cmdline lacks init=/System/Init/MixtarRVS" ;;
    esac
    case "$cmdline" in
        *"devtmpfs.mount=0"*) ok "EFI cmdline disables /dev devtmpfs automount" ;;
        *) fail_check "EFI cmdline lacks devtmpfs.mount=0" ;;
    esac
    case "$cmdline" in
        *"root="*) fail_check "EFI cmdline must not hardcode root= for CoreV07 clean initramfs" ;;
        *) ok "EFI cmdline has no root= dependency" ;;
    esac
    case "$cmdline" in
        *"mixtar.autoreturn=1"*) ok "EFI cmdline enables Mixtar autoreturn" ;;
        *)
            if [ "$require_autoreturn" = "1" ]; then
                fail_check "EFI cmdline lacks mixtar.autoreturn=1 required for one-shot laptop boot"
            else
                ok "EFI cmdline autoreturn not required for normal artifact"
            fi
            ;;
    esac
    case "$cmdline" in
        *"mixtar.persist_logs=1"*) ok "EFI cmdline enables Mixtar persistent boottrace" ;;
        *)
            if [ "$require_autoreturn" = "1" ]; then
                fail_check "EFI cmdline lacks mixtar.persist_logs=1 required for one-shot laptop diagnostics"
            else
                ok "EFI cmdline persistent boottrace not required for normal artifact"
            fi
            ;;
    esac
    case "$cmdline" in
        *"panic=300"*) ok "EFI cmdline enables kernel panic watchdog" ;;
        *)
            if [ "$require_autoreturn" = "1" ]; then
                fail_check "EFI cmdline lacks panic=300 required for one-shot laptop boot"
            else
                ok "EFI cmdline panic watchdog not required for normal artifact"
            fi
            ;;
    esac

    if strings -a "$efi" | grep -F "$KERNEL_VERSION" >/dev/null 2>&1 &&
       strings -a "$efi" | grep -F "PREEMPT_RT" >/dev/null 2>&1; then
        ok "EFI embeds Linux $KERNEL_VERSION PREEMPT_RT identity"
    else
        fail_check "EFI does not prove Linux $KERNEL_VERSION PREEMPT_RT identity"
    fi

    if strings -a "$efi" | grep -F "Linux initrd" >/dev/null 2>&1; then
        ok "EFI indicates embedded Linux initrd"
    else
        fail_check "EFI does not indicate embedded Linux initrd"
    fi

    check_embedded_wifi_firmware
}

check_embedded_wifi_firmware() {
    config_file="$kernel_build_dir/.config"

    for firmware_name in $embedded_firmware_names; do
        firmware_file="$firmware_dir/$firmware_name"
        if [ -s "$firmware_file" ]; then
            ok "embedded firmware source exists: $firmware_file"
        else
            fail_check "embedded firmware source missing: $firmware_file"
        fi
    done

    config_firmware_line=$(grep -F "CONFIG_EXTRA_FIRMWARE=" "$config_file" 2>/dev/null || true)
    if [ -s "$config_file" ] && grep -F "CONFIG_FW_LOADER=y" "$config_file" >/dev/null 2>&1; then
        ok "kernel config enables firmware loader"
    else
        fail_check "kernel config does not enable firmware loader"
    fi
    if [ -s "$config_file" ] &&
       grep -F "CONFIG_CFG80211_CERTIFICATION_ONUS=y" "$config_file" >/dev/null 2>&1 &&
       grep -F "# CONFIG_CFG80211_REQUIRE_SIGNED_REGDB is not set" "$config_file" >/dev/null 2>&1; then
        ok "kernel config accepts embedded unsigned recovery regulatory.db"
    else
        fail_check "kernel config still requires signed regulatory.db"
    fi
    for firmware_name in $embedded_firmware_names; do
        case "$config_firmware_line" in
            *"$firmware_name"*) ok "kernel config embeds $firmware_name" ;;
            *) fail_check "kernel config does not embed $firmware_name" ;;
        esac
    done

    for firmware_name in $embedded_firmware_names; do
        firmware_object="$kernel_build_dir/drivers/base/firmware_loader/builtin/$firmware_name.gen.o"
        if [ -s "$firmware_object" ]; then
            ok "kernel build contains embedded firmware object: $firmware_name"
        else
            fail_check "kernel build missing embedded firmware object: $firmware_object"
        fi
    done
}

check_no_interpreter() {
    rel=$1
    label=$2
    full="$stage_root$rel"
    [ -f "$full" ] || return
    if readelf -l "$full" 2>/dev/null | grep -F "Requesting program interpreter" >/dev/null 2>&1; then
        fail_check "$label must be static/no-interpreter: $rel"
    else
        ok "$label has no dynamic interpreter: $rel"
    fi
}

check_pid1_binary_policy() {
    pid1="$stage_root/System/Init/MixtarRVS"
    [ -f "$pid1" ] || return

    pid1_strings=$(strings -a "$pid1")

    if printf '%s\n' "$pid1_strings" | grep -F "PATH=/System/Tools" >/dev/null 2>&1; then
        fail_check "PID1 still exports old /System/Tools PATH"
    else
        ok "PID1 does not export old /System/Tools PATH"
    fi

    if printf '%s\n' "$pid1_strings" | grep -F "/System/Tools/" >/dev/null 2>&1; then
        fail_check "PID1 still contains old /System/Tools command prefix"
    else
        ok "PID1 does not contain old /System/Tools command prefix"
    fi

    if printf '%s\n' "$pid1_strings" | grep -F "PATH=/System/Userland" >/dev/null 2>&1; then
        ok "PID1 exports /System/Userland PATH"
    else
        fail_check "PID1 does not export /System/Userland PATH"
    fi

    if printf '%s\n' "$pid1_strings" | grep -F "/System/Userland/" >/dev/null 2>&1; then
        ok "PID1 contains /System/Userland command prefix"
    else
        fail_check "PID1 does not contain /System/Userland command prefix"
    fi

    if printf '%s\n' "$pid1_strings" | grep -F "mixtar.autoreturn=1" >/dev/null 2>&1; then
        ok "PID1 contains autoreturn trigger support"
    else
        fail_check "PID1 does not contain autoreturn trigger support"
    fi
}

check_interpreter() {
    rel=$1
    label=$2
    full="$stage_root$rel"
    [ -f "$full" ] || return
    if readelf -l "$full" 2>/dev/null | grep -F "Requesting program interpreter: /System/Shells/Runtime/ld-linux-x86-64.so.2" >/dev/null 2>&1; then
        ok "$label uses CoreV07 loader: $rel"
    else
        fail_check "$label does not use /System/Shells/Runtime/ld-linux-x86-64.so.2: $rel"
    fi
}

check_needed_libs() {
    rel=$1
    label=$2
    full="$stage_root$rel"
    [ -f "$full" ] || return
    needed=$(readelf -d "$full" 2>/dev/null | sed -n 's/.*Shared library: \[\([^]]*\)\].*/\1/p')
    if [ -z "$needed" ]; then
        ok "$label has no shared library requirements: $rel"
        return
    fi
    for lib in $needed; do
        if [ -e "$stage_root/System/Shells/Runtime/$lib" ] ||
           [ -e "$stage_root/System/Libraries/$lib" ] ||
           [ -e "$stage_root/System/Networking/Core/Runtime/$lib" ] ||
           [ -e "$stage_root/System/Networking/WiFi/Runtime/$lib" ] ||
           [ -e "$stage_root/System/Networking/SSH/Runtime/$lib" ]; then
            ok "$label dependency resolved: $lib"
        else
            fail_check "$label missing dependency: $lib"
        fi
    done
}

check_all_elf_runtime_closure() {
    inventory="$generated_dir/corev08-elf-runtime-inventory.txt"
    find "$stage_root" -type f -print > "$inventory"
    elf_count=0
    missing_count=0
    while IFS= read -r full; do
        if ! readelf -h "$full" >/dev/null 2>&1; then
            continue
        fi
        elf_count=$((elf_count + 1))
        rel=${full#"$stage_root"}
        runtime_root="$stage_root"
        case "$rel" in
            */Root/*)
                private_prefix=${rel%%/Root/*}
                runtime_root="$stage_root$private_prefix/Root"
                ;;
        esac

        soname=$(readelf -d "$full" 2>/dev/null | sed -n 's/.*Library soname: \[\([^]]*\)\].*/\1/p' | head -n 1)
        if [ -z "$soname" ]; then
            interpreter=$(readelf -l "$full" 2>/dev/null | sed -n 's/.*Requesting program interpreter: \([^]]*\)].*/\1/p' | head -n 1)
            if [ -n "$interpreter" ] &&
               [ ! -e "$runtime_root$interpreter" ] &&
               [ ! -e "$stage_root$interpreter" ]; then
                fail_check "ELF runtime closure missing interpreter $interpreter for $rel"
                missing_count=$((missing_count + 1))
            fi
        fi

        needed=$(readelf -d "$full" 2>/dev/null | sed -n 's/.*Shared library: \[\([^]]*\)\].*/\1/p')
        for lib in $needed; do
            resolved=0
            if [ -e "$(dirname "$full")/$lib" ]; then
                resolved=1
            elif [ "$runtime_root" != "$stage_root" ]; then
                if find "$runtime_root" \( -type f -o -type l \) -name "$lib" -print -quit 2>/dev/null | grep -q .; then
                    resolved=1
                fi
            elif [ -e "$stage_root/System/Shells/Runtime/$lib" ] ||
                 [ -e "$stage_root/System/Libraries/$lib" ] ||
                 [ -e "$stage_root/System/Networking/Core/Runtime/$lib" ] ||
                 [ -e "$stage_root/System/Networking/WiFi/Runtime/$lib" ] ||
                 [ -e "$stage_root/System/Networking/SSH/Runtime/$lib" ]; then
                resolved=1
            fi
            if [ "$resolved" -ne 1 ]; then
                fail_check "ELF runtime closure missing $lib for $rel"
                missing_count=$((missing_count + 1))
            fi
        done
    done < "$inventory"

    if [ "$elf_count" -eq 0 ]; then
        fail_check "ELF runtime closure inventory is empty"
    elif [ "$missing_count" -eq 0 ]; then
        ok "all-ELF runtime closure is self-contained ($elf_count ELF objects)"
    fi
}

check_text_contains() {
    path=$1
    text=$2
    label=$3
    if [ -f "$stage_root$path" ] && grep -F "$text" "$stage_root$path" >/dev/null 2>&1; then
        ok "$label"
    else
        fail_check "$label missing"
    fi
}

check_text_absent() {
    path=$1
    text=$2
    label=$3
    if [ -f "$stage_root$path" ] && grep -F "$text" "$stage_root$path" >/dev/null 2>&1; then
        fail_check "$label forbidden pattern present"
    else
        ok "$label"
    fi
}

check_binary_strings_contains() {
    path=$1
    text=$2
    label=$3
    if [ -f "$stage_root$path" ] && strings -a "$stage_root$path" | grep -F "$text" >/dev/null 2>&1; then
        ok "$label"
    else
        fail_check "$label missing"
    fi
}

check_binary_strings_absent() {
    path=$1
    text=$2
    label=$3
    if [ -f "$stage_root$path" ] && strings -a "$stage_root$path" | grep -F "$text" >/dev/null 2>&1; then
        fail_check "$label forbidden pattern present"
    else
        ok "$label"
    fi
}

check_sqlite_meta() {
    db_rel=$1
    table_name=$2
    key=$3
    expected=$4
    label=$5
    db="$stage_root$db_rel"
    if python3 - "$db" "$table_name" "$key" "$expected" <<'PY'
import sqlite3
import sys

db_path, table_name, key, expected = sys.argv[1:5]
try:
    db = sqlite3.connect(db_path)
    row = db.execute(f"SELECT value FROM {table_name} WHERE key = ?", (key,)).fetchone()
    db.close()
except Exception:
    sys.exit(1)
if row is None or row[0] != expected:
    sys.exit(1)
PY
    then
        ok "$label $key=$expected"
    else
        fail_check "$label missing $key=$expected"
    fi
}

check_sqlite_root_dir() {
    db_rel=$1
    expected=$2
    label=$3
    db="$stage_root$db_rel"
    if python3 - "$db" "$expected" <<'PY'
import sqlite3
import sys

db_path, expected = sys.argv[1:3]
try:
    db = sqlite3.connect(db_path)
    row = db.execute("SELECT 1 FROM root_dir WHERE path = ?", (expected,)).fetchone()
    db.close()
except Exception:
    sys.exit(1)
if row is None:
    sys.exit(1)
PY
    then
        ok "$label root.dir=$expected"
    else
        fail_check "$label missing root.dir=$expected"
    fi
}

check_sqlite_user() {
    db_rel=$1
    name=$2
    expected_uid=$3
    expected_gid=$4
    expected_home=$5
    label=$6
    db="$stage_root$db_rel"
    if python3 - "$db" "$name" "$expected_uid" "$expected_gid" "$expected_home" <<'PY'
import sqlite3
import sys

db_path, name, expected_uid, expected_gid, expected_home = sys.argv[1:6]
try:
    db = sqlite3.connect(db_path)
    row = db.execute(
        "SELECT uid, gid, home FROM user WHERE name = ? COLLATE BINARY",
        (name,),
    ).fetchone()
    db.close()
except Exception:
    sys.exit(1)
if row != (int(expected_uid), int(expected_gid), expected_home):
    sys.exit(1)
PY
    then
        ok "$label name=$name uid=$expected_uid gid=$expected_gid home=$expected_home"
    else
        fail_check "$label invalid identity for $name"
    fi
}

check_userland_core() {
    for tool in echo cat pwd ls; do
        check_executable "/System/Userland/$tool" "Core userland $tool"
        check_needed_libs "/System/Userland/$tool" "Core userland $tool"
    done
}

while [ $# -gt 0 ]; do
    case "$1" in
        --root)
            [ $# -ge 2 ] || { printf '%s\n' "missing --root value" >&2; exit 2; }
            stage_root=$2
            shift 2
            ;;
        --efi-stage)
            [ $# -ge 2 ] || { printf '%s\n' "missing --efi-stage value" >&2; exit 2; }
            efi_stage=$2
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf '%s\n' "unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

printf '%s\n' "CoreV07 boot preflight"
printf '%s\n' "  root:      $stage_root"
printf '%s\n' "  efi-stage: $efi_stage"

require_cmd objdump
require_cmd readelf
require_cmd strings
require_cmd sha256sum
require_cmd python3

if [ "$failures" -ne 0 ]; then
    printf '%s\n' "CoreV07 boot preflight: $failures failure(s)"
    exit 1
fi

[ -d "$stage_root" ] || { printf '%s\n' "FAIL: staged root missing: $stage_root"; exit 1; }

check_dir "/Applications" "native root"
check_dir "/System" "native root"
check_dir "/Users" "native root"
check_dir "/Volumes" "native root"
check_dir "/Temporary" "native root"
for path in /bin /boot /dev /etc /home /lib /lib64 /proc /root /run /sbin /sys /tmp /usr /var; do
    check_absent "$path" "forbidden native root"
done

check_file "/System/EFI/MixtarRVS/$VERSION.efi" "EFI artifact"
check_file "/System/EFI/MixtarRVS/$VERSION.efi.provenance" "EFI provenance"
check_efi_pair
check_efi_provenance
check_efi_format
check_efi_cmdline
check_all_elf_runtime_closure

check_executable "/System/Init/MixtarRVS" "PID1"
check_no_interpreter "/System/Init/MixtarRVS" "PID1"
check_pid1_binary_policy
check_binary_strings_contains "/System/Init/MixtarRVS" "pid1: failed to apply system.name as kernel hostname" "PID1 applies SQLite system.name to kernel hostname"
check_binary_strings_contains "/System/Init/MixtarRVS" "session: failed to enter configured user identity" "PID1 enforces configured session UID/GID"
check_binary_strings_contains "/System/Init/MixtarRVS" "pid1: persistent Users and Configuration ready" "PID1 owns persistent data/config activation"
if grep -F 'if mi_exists(config_db) != 0 then' "$repo_root/Server/Rootfs/initramfs/mixtar_init.ail" >/dev/null 2>&1 &&
   grep -F 'if mi_exists(MI_PERSISTENCE_READY_MARKER) != 0 then' "$repo_root/Server/Rootfs/initramfs/mixtar_init.ail" >/dev/null 2>&1; then
    ok "PID1 persistence checks use positive exists semantics"
else
    fail_check "PID1 persistence checks use inverted exists semantics"
fi
check_binary_strings_contains "/System/Init/MixtarRVS" "pid1: persistence unavailable; continuing with RAM root" "PID1 persistence failure is fail-safe"
check_binary_strings_contains "/System/Init/MixtarRVS" "pid1: autoreturn reboot syscall failed; remote access remains active" "PID1 autoreturn failure preserves remote recovery"
check_binary_strings_absent "/System/Init/MixtarRVS" "/Volumes/DebianRoot" "PID1 Debian-root runtime dependency absent"
check_binary_strings_absent "/System/Init/MixtarRVS" "Debian-root boottrace" "PID1 Debian-root boottrace absent"
check_executable "/System/Shells/zsh" "ZSH"
check_interpreter "/System/Shells/zsh" "ZSH"
check_needed_libs "/System/Shells/zsh" "ZSH"
check_executable "/System/Runtime/Executor" "APX Executor"
check_interpreter "/System/Runtime/Executor" "APX Executor"
check_needed_libs "/System/Runtime/Executor" "APX Executor"
if readelf -d "$stage_root/System/Runtime/Executor" 2>/dev/null |
   grep -F '(RPATH)' | grep -F '/System/Shells/Runtime' >/dev/null 2>&1 &&
   ! readelf -d "$stage_root/System/Runtime/Executor" 2>/dev/null |
       grep -F '(RUNPATH)' >/dev/null 2>&1; then
    ok "APX Executor has inherited native runtime RPATH"
else
    fail_check "APX Executor must use inherited /System/Shells/Runtime RPATH"
fi
if "$stage_root/System/Shells/Runtime/ld-linux-x86-64.so.2" \
       --library-path "$stage_root/System/Shells/Runtime" \
       --list "$stage_root/System/Runtime/Executor" >/dev/null 2>&1; then
    ok "APX Executor transitive runtime graph resolves"
else
    fail_check "APX Executor transitive runtime graph does not resolve"
fi

check_file "/System/Shells/Runtime/ld-linux-x86-64.so.2" "dynamic loader"
check_file "/System/Shells/Terminfo/l/linux" "linux terminfo"
check_file "/System/Configuration/MixtarRVS.config" "PID1 SQLite config"
check_sqlite_root_dir "/System/Configuration/MixtarRVS.config" "/System/EFI" "PID1 SQLite config"
check_sqlite_root_dir "/System/Configuration/MixtarRVS.config" "/System/EFI/MixtarRVS" "PID1 SQLite config"
check_file "/System/Configuration/ZSH/ZSH.config" "ZSH SQLite config"
check_file "/System/Configuration/Networking/Networking.config" "CoreV07 Networking SQLite config"
check_file "/System/Configuration/Networking/WiFi.config" "CoreV07 Wi-Fi SQLite config"
check_file "/System/Configuration/Security/Policy.config" "CoreV07 security policy SQLite config"
check_file "/System/Configuration/Security/AdminSession.config" "CoreV07 administrator session SQLite config"
check_file "/System/Security/Auth.contract" "CoreV07 auth contract"
check_executable "/System/Userland/admin" "CoreV07 fail-closed admin command"
check_executable "/System/Userland/exit-admin" "CoreV07 exit-admin command"
check_file "/System/Configuration/SSH/SSH.config" "SSH SQLite config"
check_file "/System/Configuration/SSH/sshd_config" "OpenSSH config"
check_file "/System/Configuration/SSH/HostKeys/ssh_host_ed25519_key" "OpenSSH host key"
check_file "/System/Configuration/SSH/authorized_keys/vxz" "OpenSSH authorized key for vxz"
check_text_absent "/System/Configuration/SSH/sshd_config" "UsePAM" "OpenSSH config unsupported PAM option"
check_text_contains "/System/Configuration/SSH/sshd_config" "ChrootDirectory /Native" "SSH sessions use clean native root"
check_text_contains "/System/Configuration/SSH/sshd_config" "SetEnv PATH=/System/Shells:/System/Userland" "SSH sessions use native command PATH"
if [ "$(stat -c %a "$stage_root/System/Configuration/SSH/HostKeys/ssh_host_ed25519_key")" = "600" ]; then
    ok "OpenSSH host key staged mode is 0600"
elif strings -a "$stage_root/System/Networking/SSH/mixtar-sshd-service" | grep -F "/System/Configuration/SSH/HostKeys/ssh_host_ed25519_key" >/dev/null 2>&1; then
    ok "OpenSSH host key mode is enforced by SSH runtime wrapper"
else
    fail_check "OpenSSH host key mode must be 0600 or enforced by SSH runtime wrapper"
fi
check_file "/System/UI/Shell/MixtarShell.apx/MixtarShell.config" "MixtarShell APX config"
check_executable "/System/UI/Shell/MixtarShell.apx/Program/MixtarShell" "MixtarShell APX entry"

check_sqlite_meta "/System/Configuration/MixtarRVS.config" meta "stage.scope" "generated-only" "PID1 config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" meta "system.name" "MixtarRVS" "PID1 config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" meta "default.user" "vxz" "PID1 config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" meta "default.uid" "1000" "PID1 config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" meta "default.gid" "1000" "PID1 config"
check_sqlite_user "/System/Configuration/MixtarRVS.config" "vxz" "1000" "1000" "/Users/vxz" "PID1 configured user"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" meta "session.reboot.status" "200" "PID1 lifecycle protocol"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" meta "session.poweroff.status" "201" "PID1 lifecycle protocol"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" meta "lifecycle.reboot.command" "/System/Userland/reboot" "native lifecycle command"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" meta "lifecycle.poweroff.command" "/System/Userland/poweroff" "native lifecycle command"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" meta "lifecycle.control.path" "/System/Runtime/Lifecycle" "native lifecycle control"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" meta "persistence.enabled" "true" "PID1 persistence config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" meta "persistence.device" "/System/Devices/nvme0n1p3" "PID1 persistence config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" meta "persistence.fstype" "ext4" "PID1 persistence config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" meta "persistence.users.target" "/Users" "PID1 persistence config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" meta "persistence.configuration.target" "/System/Configuration" "PID1 persistence config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" meta "boot.deploy" "disabled" "PID1 config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" meta "efi.mutation" "disabled" "PID1 config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" meta "userland.path" "/System/Userland" "PID1 config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" meta "tools.mode" "admin-only" "PID1 config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" meta "drivers.mode" "store-only" "PID1 config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" meta "networking.service" "/System/Networking/start-networking" "PID1 config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" meta "networking.ping.group_range.path" "/System/Process/sys/net/ipv4/ping_group_range" "PID1 ICMP policy"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" meta "networking.ping.gid.min" "0" "PID1 ICMP policy"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" meta "networking.ping.gid.max" "1000" "PID1 ICMP policy"
if grep -F "ping_policy_rc = mi_configure_ping_group(ping_range_path, ping_gid_min, ping_gid_max)" "$repo_root/Server/Rootfs/initramfs/mixtar_init.ail" >/dev/null 2>&1; then
    ok "PID1 owns config-driven ICMP policy"
else
    fail_check "PID1 does not apply config-driven ICMP policy"
fi
check_sqlite_meta "/System/Configuration/MixtarRVS.config" meta "networking.config" "/System/Configuration/Networking/Networking.config" "PID1 config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" meta "wifi.config" "/System/Configuration/Networking/WiFi.config" "PID1 config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" meta "regulatory.db" "embedded" "PID1 config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" meta "security.path" "/System/Security" "PID1 config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" meta "security.policy" "/System/Configuration/Security/Policy.config" "PID1 config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" meta "security.runtime" "/System/Runtime/Security" "PID1 config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" meta "admin.mode" "session-token" "PID1 config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" meta "admin.command" "admin" "PID1 config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" meta "sudo.default" "false" "PID1 config"
check_sqlite_meta "/System/Configuration/Networking/Networking.config" meta "networking.mode" "recovery-corev07" "CoreV07 Networking config"
check_sqlite_meta "/System/Configuration/Networking/Networking.config" meta "networking.ui" "false" "CoreV07 Networking config"
check_sqlite_meta "/System/Configuration/Networking/Networking.config" meta "regulatory.db" "embedded" "CoreV07 Networking config"
check_sqlite_meta "/System/Configuration/Networking/WiFi.config" meta "wifi.mode" "recovery-corev07" "CoreV07 Wi-Fi config"
check_sqlite_meta "/System/Configuration/Networking/WiFi.config" meta "wifi.backend" "iwd" "CoreV07 Wi-Fi config"
check_sqlite_meta "/System/Configuration/Networking/WiFi.config" meta "wifi.regulatory_db" "embedded" "CoreV07 Wi-Fi config"
check_sqlite_meta "/System/Configuration/Security/Policy.config" setting "admin.mode" "session-token" "CoreV07 security policy"
check_sqlite_meta "/System/Configuration/Security/Policy.config" setting "admin.command" "admin" "CoreV07 security policy"
check_sqlite_meta "/System/Configuration/Security/Policy.config" setting "admin.session.title" "Administrator: Mixtar Terminal" "CoreV07 security policy"
check_sqlite_meta "/System/Configuration/Security/Policy.config" setting "sudo.default" "false" "CoreV07 security policy"
check_sqlite_meta "/System/Configuration/Security/AdminSession.config" setting "title" "Administrator: Mixtar Terminal" "CoreV07 admin session"
check_sqlite_meta "/System/Configuration/Security/AdminSession.config" setting "prompt" "unchanged" "CoreV07 admin session"
check_sqlite_meta "/System/Configuration/ZSH/ZSH.config" setting "history.file" '${HOME}/.zsh_history' "ZSH config"
check_sqlite_meta "/System/UI/Shell/MixtarShell.apx/MixtarShell.config" setting "entry.path" "Program/MixtarShell" "MixtarShell APX config"
check_sqlite_meta "/System/UI/Shell/MixtarShell.apx/MixtarShell.config" setting "runtime" "mixtar" "MixtarShell APX config"

if grep -F 'const int MI_AUTORETURN_MS = 300000' "$repo_root/Server/Rootfs/initramfs/mixtar_init_defs.ail" >/dev/null 2>&1 &&
   grep -F 'ail_sleep_ms(MI_AUTORETURN_MS)' "$repo_root/Server/Rootfs/initramfs/mixtar_init.ail" >/dev/null 2>&1; then
    ok "PID1 autoreturn watchdog is fixed at 5m"
else
    fail_check "PID1 autoreturn watchdog is not fixed at 5m"
fi
if grep -F 'const string MI_TOOL_PREFIX = "/System/Userland/"' "$repo_root/Server/Rootfs/initramfs/mixtar_init_defs.ail" >/dev/null 2>&1 &&
   grep -F 'const string MI_SESSION_ENV_PATH = "PATH=/System/Shells:/System/Userland"' "$repo_root/Server/Rootfs/initramfs/mixtar_init_defs.ail" >/dev/null 2>&1; then
    ok "PID1 uses /System/Userland for commands and session PATH"
else
    fail_check "PID1 still leaks command execution through /System/Tools"
fi

check_userland_core
check_executable "/System/Userland/ping" "native userland ping"
check_executable "/System/Userland/reboot" "native lifecycle reboot"
check_no_interpreter "/System/Userland/reboot" "native lifecycle reboot"
check_binary_strings_contains "/System/Userland/reboot" "MixtarRVS lifecycle request failed" "native lifecycle FIFO client"
check_executable "/System/Userland/poweroff" "native lifecycle poweroff"
check_no_interpreter "/System/Userland/poweroff" "native lifecycle poweroff"
check_binary_strings_contains "/System/Init/MixtarRVS" "pid1: lifecycle control ready" "PID1 lifecycle service"
check_text_absent "/Users/vxz/.zshrc" "function poweroff" "default shell no longer shadows native lifecycle commands"

check_executable "/System/Networking/start-networking" "CoreV07 recovery networking service"
check_executable "/System/Networking/Core/ip" "CoreV07 ip wrapper"
check_executable "/System/Networking/Core/ip.bin" "CoreV07 ip binary"
check_needed_libs "/System/Networking/Core/ip.bin" "CoreV07 ip binary"
check_executable "/System/Networking/WiFi/mixtar-wifi-service" "CoreV07 Wi-Fi service wrapper"
check_no_interpreter "/System/Networking/WiFi/mixtar-wifi-service" "CoreV07 Wi-Fi service wrapper"
check_executable "/System/Networking/WiFi/bin/iwd" "CoreV07 iwd daemon"
check_needed_libs "/System/Networking/WiFi/bin/iwd" "CoreV07 iwd daemon"
check_executable "/System/Networking/WiFi/bin/dbus-daemon" "CoreV07 Wi-Fi dbus daemon"
check_needed_libs "/System/Networking/WiFi/bin/dbus-daemon" "CoreV07 Wi-Fi dbus daemon"
check_file "/System/Networking/WiFi/Runtime/ld-linux-x86-64.so.2" "Wi-Fi runtime loader"
check_file "/System/Networking/WiFi/Root/etc/passwd" "Wi-Fi private passwd"
check_file "/System/Networking/WiFi/Root/etc/group" "Wi-Fi private group"
check_executable "/System/Networking/SSH/mixtar-sshd-service" "CoreV07 SSH service wrapper"
check_no_interpreter "/System/Networking/SSH/mixtar-sshd-service" "CoreV07 SSH service wrapper"
check_executable "/System/Networking/SSH/sbin/sshd" "CoreV07 OpenSSH daemon"
check_needed_libs "/System/Networking/SSH/sbin/sshd" "CoreV07 OpenSSH daemon"
check_file "/System/Networking/SSH/Runtime/ld-linux-x86-64.so.2" "OpenSSH runtime loader"
check_binary_strings_contains "/System/Networking/start-networking" "/System/Shells" "networking service uses /System/Shells"
check_binary_strings_contains "/System/Networking/start-networking" "/System/Networking/WiFi/mixtar-wifi-service" "networking service launches Wi-Fi wrapper"
check_binary_strings_contains "/System/Networking/start-networking" "/System/Networking/SSH/mixtar-sshd-service" "networking service launches SSH wrapper"
check_binary_strings_contains "/System/Networking/start-networking" "/System/Hardware/class/net" "networking service enumerates kernel network interfaces"
check_binary_strings_contains "/System/Networking/start-networking" "networking: kernel dmesg snapshot begin" "networking service logs kernel dmesg diagnostics"
check_binary_strings_contains "/System/Networking/start-networking" "networking: iface present" "networking service logs present interfaces"
check_binary_strings_absent "/System/Networking/start-networking" "192.168.99.110" "networking service avoids hardcoded recovery address"
check_binary_strings_contains "/System/Networking/start-networking" "ssh-probe detected native address" "SSH self-test discovers active IPv4"
check_binary_strings_contains "/System/Networking/start-networking" "static fallback disabled" "networking service avoids address conflicts"
check_binary_strings_contains "/System/Networking/start-networking" "CoreV07-last.log" "networking service exports boot logs to ESP"
check_binary_strings_absent "/System/Networking/start-networking" "/System/Terminal" "networking service retired terminal path"
check_binary_strings_absent "/System/Networking/start-networking" "10.0.2.15" "networking service retired QEMU-only address"
check_binary_strings_contains "/System/Networking/start-networking" "existing DHCP/global IPv4 retained" "networking service prefers existing DHCP address"


check_binary_strings_absent "/System/Networking/start-networking" "for attempt in {1..90}" "networking service retired retry spam loop"
check_text_contains "/System/Networking/Core/ip" "#!/System/Shells/zsh" "ip wrapper uses /System/Shells"
check_text_absent "/System/Networking/Core/ip" "/System/Terminal" "ip wrapper retired terminal path"
check_binary_strings_contains "/System/Networking/WiFi/mixtar-wifi-service" "/System/Networking/WiFi/Root" "Wi-Fi wrapper uses private root"
check_binary_strings_absent "/System/Networking/WiFi/mixtar-wifi-service" "/System/Terminal" "Wi-Fi wrapper retired terminal path"
check_binary_strings_contains "/System/Networking/SSH/mixtar-sshd-service" "/System/Shells" "SSH wrapper binds shell namespace"
check_binary_strings_contains "/System/Networking/SSH/mixtar-sshd-service" "/System/Networking/SSH/Root/Native/System/Logs" "SSH wrapper exposes native logs inside session root"
check_binary_strings_contains "/System/Networking/SSH/mixtar-sshd-service" "/System/Networking/SSH/Root/Native/System/Networking/Core" "SSH wrapper exposes native networking inside session root"
check_binary_strings_absent "/System/Networking/SSH/mixtar-sshd-service" "/System/Terminal" "SSH wrapper retired terminal path"
check_binary_strings_contains "/System/Networking/SSH/mixtar-sshd-service" "/run/sshd" "SSH wrapper contains private chroot /run/sshd"
check_binary_strings_contains "/System/Networking/SSH/mixtar-sshd-service" "chroot component ownership" "SSH wrapper enforces root ownership on chroot components"
check_binary_strings_contains "/System/Networking/SSH/mixtar-sshd-service" "chroot component mode" "SSH wrapper enforces safe chroot modes"

check_file "/System/Drivers/Linux/RT/$KERNEL_VERSION/Drivers.config" "driver store database"
check_file "/System/Drivers/Linux/RT/$KERNEL_VERSION/Drivers.status" "driver store status"
if grep -F "policy.no_visible_dev=true" "$stage_root/System/Drivers/Linux/RT/$KERNEL_VERSION/Drivers.status" >/dev/null 2>&1 &&
   grep -F "policy.devtmpfs_automount=disabled" "$stage_root/System/Drivers/Linux/RT/$KERNEL_VERSION/Drivers.status" >/dev/null 2>&1; then
    ok "driver policy keeps /dev out of native root"
else
    fail_check "driver policy does not prove hidden /dev/devtmpfs policy"
fi

if [ "$failures" -eq 0 ]; then
    printf '%s\n' "CoreV07 boot preflight: OK"
    exit 0
fi

printf '%s\n' "CoreV07 boot preflight: $failures failure(s)"
exit 1
