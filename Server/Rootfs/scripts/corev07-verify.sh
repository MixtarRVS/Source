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
pid1_source="$repo_root/Server/Rootfs/initramfs/mixtar_init.ail"
pid1_defs_source="$repo_root/Server/Rootfs/initramfs/mixtar_init_defs.ail"
executor_source="$repo_root/Server/Runtime/Executor/mixtar_executor.ail"
stage_source="$repo_root/Server/Rootfs/scripts/corev07-stage-root.sh"
local_gate_source="$repo_root/Server/Rootfs/scripts/corev07-local-gate.sh"
boot_preflight_source="$repo_root/Server/Rootfs/scripts/corev07-boot-preflight.sh"
build_efi_source="$repo_root/Server/Rootfs/scripts/corev07-build-efi.sh"
one_shot_script_source="$repo_root/Server/Rootfs/scripts/corev07-oneshot-deploy.sh"
contract_source="$repo_root/Server/Rootfs/COREV07_CONTRACT.md"
one_shot_source="$repo_root/Server/Rootfs/COREV07_ONESHOT_BOOT.md"
bundle_model_source="$repo_root/docs/BUNDLE_MODEL.md"
layout_policy_source="$repo_root/Server/Rootfs/LAYOUT_POLICY.md"

failures=0

usage() {
    cat <<EOF
usage: corev07-verify.sh [--root PATH] [--efi-stage PATH]

Verifies CoreV07 staging only. It does not modify Debian, ESP, EFI variables,
boot order, or a live root.
EOF
}

fail_check() {
    failures=$((failures + 1))
    printf '%s\n' "FAIL: $*"
}

pass_check() {
    printf '%s\n' "OK: $*"
}

check_dir() {
    path=$1
    label=$2
    if [ -d "$stage_root$path" ]; then
        pass_check "$label: $path"
    else
        fail_check "$label missing: $path"
    fi
}

check_file() {
    path=$1
    label=$2
    if [ -f "$stage_root$path" ]; then
        pass_check "$label: $path"
    else
        fail_check "$label missing: $path"
    fi
}

check_executable() {
    path=$1
    label=$2
    if [ -x "$stage_root$path" ]; then
        pass_check "$label executable: $path"
    elif [ -f "$stage_root$path" ]; then
        fail_check "$label exists but is not executable: $path"
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
        pass_check "$label absent: $path"
    fi
}

check_nonempty_file() {
    path=$1
    label=$2
    if [ -s "$stage_root$path" ]; then
        pass_check "$label non-empty: $path"
    elif [ -f "$stage_root$path" ]; then
        fail_check "$label exists but is empty: $path"
    else
        fail_check "$label missing: $path"
    fi
}

check_mz_file() {
    path=$1
    label=$2
    full="$stage_root$path"
    if [ ! -s "$full" ]; then
        fail_check "$label missing or empty: $path"
        return
    fi
    magic=$(dd if="$full" bs=2 count=1 2>/dev/null || true)
    if [ "$magic" = "MZ" ]; then
        pass_check "$label has EFI/PE MZ header: $path"
    else
        fail_check "$label does not have EFI/PE MZ header: $path"
    fi
}

check_sqlite_file() {
    path=$1
    label=$2
    full="$stage_root$path"
    if [ ! -s "$full" ]; then
        fail_check "$label missing or empty: $path"
        return
    fi
    magic=$(dd if="$full" bs=15 count=1 2>/dev/null || true)
    if [ "$magic" = "SQLite format 3" ]; then
        pass_check "$label has SQLite header: $path"
    else
        fail_check "$label does not have SQLite header: $path"
    fi
}

check_sqlite_setting() {
    path=$1
    key=$2
    value=$3
    label=$4
    full="$stage_root$path"
    if python3 - "$full" "$key" "$value" <<'PY'
import sqlite3
import sys

db_path, key, expected = sys.argv[1:4]
try:
    db = sqlite3.connect(db_path)
    row = db.execute("SELECT value FROM setting WHERE key = ?", (key,)).fetchone()
    db.close()
except Exception:
    sys.exit(1)
if row is None or row[0] != expected:
    sys.exit(1)
PY
    then
        pass_check "$label $key=$value"
    else
        fail_check "$label missing $key=$value"
    fi
}

check_sqlite_meta() {
    path=$1
    key=$2
    value=$3
    label=$4
    full="$stage_root$path"
    if python3 - "$full" "$key" "$value" <<'PY'
import sqlite3
import sys

db_path, key, expected = sys.argv[1:4]
try:
    db = sqlite3.connect(db_path)
    row = db.execute("SELECT value FROM meta WHERE key = ?", (key,)).fetchone()
    db.close()
except Exception:
    sys.exit(1)
if row is None or row[0] != expected:
    sys.exit(1)
PY
    then
        pass_check "$label $key=$value"
    else
        fail_check "$label missing $key=$value"
    fi
}

check_sqlite_root_dir() {
    path=$1
    expected=$2
    label=$3
    full="$stage_root$path"
    if python3 - "$full" "$expected" <<'PY'
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
        pass_check "$label root.dir=$expected"
    else
        fail_check "$label missing root.dir=$expected"
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
        pass_check "EFI provenance hash matches official EFI"
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
            pass_check "EFI provenance declares $required"
        else
            fail_check "EFI provenance missing $required"
        fi
    done
}
check_marker() {
    key=$1
    value=$2
    marker="$stage_root/System/Configuration/CoreV07.contract"
    if [ -f "$marker" ] && grep -Fqx "$key=$value" "$marker"; then
        pass_check "contract $key=$value"
    else
        fail_check "contract missing $key=$value"
    fi
}

check_pid1_source_contains() {
    text=$1
    label=$2
    if [ -f "$pid1_source" ] && grep -F -- "$text" "$pid1_source" >/dev/null 2>&1; then
        pass_check "PID1 source $label"
    else
        fail_check "PID1 source missing $label"
    fi
}

check_pid1_source_absent() {
    text=$1
    label=$2
    if [ -f "$pid1_source" ] && grep -F "$text" "$pid1_source" >/dev/null 2>&1; then
        fail_check "PID1 source forbidden pattern present: $label"
    else
        pass_check "PID1 source forbidden pattern absent: $label"
    fi
}

check_source_contains() {
    file=$1
    text=$2
    label=$3
    if [ -f "$file" ] && grep -F -- "$text" "$file" >/dev/null 2>&1; then
        pass_check "$label"
    else
        fail_check "$label missing"
    fi
}

check_source_absent() {
    file=$1
    text=$2
    label=$3
    if [ -f "$file" ] && grep -F -- "$text" "$file" >/dev/null 2>&1; then
        fail_check "$label forbidden pattern present"
    else
        pass_check "$label forbidden pattern absent"
    fi
}

check_staged_text_contains() {
    path=$1
    text=$2
    label=$3
    if [ -f "$stage_root$path" ] && grep -F -- "$text" "$stage_root$path" >/dev/null 2>&1; then
        pass_check "$label"
    else
        fail_check "$label missing"
    fi
}

check_staged_text_absent() {
    path=$1
    text=$2
    label=$3
    if [ -f "$stage_root$path" ] && grep -F -- "$text" "$stage_root$path" >/dev/null 2>&1; then
        fail_check "$label forbidden pattern present"
    else
        pass_check "$label"
    fi
}

check_staged_strings_contains() {
    path=$1
    text=$2
    label=$3
    if [ -f "$stage_root$path" ] && strings -a "$stage_root$path" | grep -F -- "$text" >/dev/null 2>&1; then
        pass_check "$label"
    else
        fail_check "$label missing"
    fi
}

check_staged_strings_absent() {
    path=$1
    text=$2
    label=$3
    if [ -f "$stage_root$path" ] && strings -a "$stage_root$path" | grep -F -- "$text" >/dev/null 2>&1; then
        fail_check "$label forbidden pattern present"
    else
        pass_check "$label"
    fi
}

check_no_compiler_binaries_in_userland() {
    check_no_compiler_binaries_in_path \
        "$stage_root/System/Userland" \
        "userland"
}

check_no_compiler_binaries_in_tools() {
    check_no_compiler_binaries_in_path \
        "$stage_root/System/Tools" \
        "administrative tools"
}

check_no_compiler_binaries_in_path() {
    target_dir=$1
    target_label=$2

    if [ ! -d "$target_dir" ]; then
        fail_check "cannot scan compiler placement: $target_dir is missing"
        return
    fi

    compiler_binaries="$(
        find "$target_dir" \( -type f -o -type l \) \
            \( -name "cc" -o -name "c++" -o -name "cpp" -o -name "gcc" -o -name "gcc-ar" -o -name "gcc-nm" -o -name "gcc-ranlib" -o -name "gcc-strip" -o \
              -name "g++" -o -name "g++-*" -o -name "clang" -o -name "clang++" -o -name "clang-ar" -o -name "clang-ranlib" -o -name "clang-strip" -o \
              -name "clang-format" -o -name "clangd" -o -name "clang-cl" -o -name "llvm-*" -o -name "lld" -o -name "ld" -o -name "ld.lld" -o \
              -name "ar" -o -name "as" -o -name "nm" -o -name "ranlib" -o -name "objcopy" -o -name "objdump" -o -name "readelf" -o \
              -name "size" -o -name "strings" -o -name "strip" -o -name "strip" -o -name "make" -o -name "gmake" -o -name "ninja" -o -name "cmake" -o \
              -name "autoconf" -o -name "automake" -o -name "libtool" -o -name "m4" -o -name "meson" -o -name "configure" -o \
              -name "nasm" -o -name "yasm" -o -name "tcc" -o -name "rustc" -o -name "go" -o -name "cargo" -o -name "zig" \) \
        2>/dev/null
    )"

    if [ -n "$compiler_binaries" ]; then
        fail_check "compiler binaries must live in /System/Compilers, found in $target_label ($target_dir):"
        while IFS= read -r item; do
            [ -n "$item" ] || continue
            fail_check "  $(printf '%s' "$item" | sed "s#^$stage_root##")"
        done <<EOF
$compiler_binaries
EOF
    else
        pass_check "no forbidden compiler binaries detected in $target_label ($target_dir)"
    fi
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

printf '%s\n' "CoreV07 verifier"
printf '%s\n' "  root:      $stage_root"
printf '%s\n' "  efi-stage: $efi_stage"

[ -d "$stage_root" ] || {
    printf '%s\n' "FAIL: staged root does not exist: $stage_root"
    exit 1
}

check_dir "/Applications" "native root"
check_dir "/System" "native root"
check_dir "/Users" "native root"
check_dir "/Volumes" "native root"
check_dir "/Temporary" "native root"

check_absent "/bin" "forbidden native root"
check_absent "/boot" "forbidden native root"
check_absent "/dev" "forbidden native root"
check_absent "/etc" "forbidden native root"
check_absent "/home" "forbidden native root"
check_absent "/lib" "forbidden native root"
check_absent "/lib64" "forbidden native root"
check_absent "/proc" "forbidden native root"
check_absent "/root" "forbidden native root"
check_absent "/run" "forbidden native root"
check_absent "/sbin" "forbidden native root"
check_absent "/sys" "forbidden native root"
check_absent "/tmp" "forbidden native root"
check_absent "/usr" "forbidden native root"
check_absent "/var" "forbidden native root"

check_dir "/System/Init" "system path"
check_dir "/System/Kernel/Linux/RT/$KERNEL_VERSION" "kernel profile"
check_dir "/System/EFI/MixtarRVS" "EFI path"
check_dir "/System/Shells" "shell path"
check_dir "/System/Shells/Runtime" "shell runtime path"
check_dir "/System/Shells/Terminfo" "shell terminfo path"
check_dir "/System/Tools" "tool path"
check_dir "/System/Compilers" "compiler toolchain path"
check_dir "/System/Userland" "base userland path"
check_no_compiler_binaries_in_userland
check_no_compiler_binaries_in_tools
check_dir "/System/Drivers" "driver path"
check_dir "/System/Drivers/Linux/RT/$KERNEL_VERSION" "driver store path"
check_dir "/System/Libraries" "library path"
check_dir "/System/Configuration" "runtime config path"
check_dir "/System/Configuration/Networking" "networking config path"
check_dir "/System/Configuration/Security" "security config path"
check_absent "/System/Config" "retired duplicate configuration path"
check_absent "/System/Applications" "retired system applications path"
check_dir "/System/Resources" "resource path"
check_dir "/System/Logs" "log path"
check_dir "/System/Networking" "networking namespace"
check_dir "/System/Networking/Core" "networking core path"
check_dir "/System/Networking/Core/Runtime" "networking core runtime path"
check_dir "/System/Networking/WiFi" "recovery Wi-Fi path"
check_dir "/System/Networking/WiFi/Runtime" "recovery Wi-Fi runtime path"
check_dir "/System/Networking/WiFi/bin" "recovery Wi-Fi bin path"
check_dir "/System/Networking/WiFi/Root" "recovery Wi-Fi private root"
check_dir "/System/Networking/SSH" "recovery SSH path"
check_dir "/System/Networking/SSH/Runtime" "recovery SSH runtime path"
check_dir "/System/Networking/SSH/bin" "recovery SSH bin path"
check_dir "/System/Networking/SSH/sbin" "recovery SSH sbin path"
check_dir "/System/Networking/SSH/libexec" "recovery SSH libexec path"
check_dir "/System/Networking/SSH/Root" "recovery SSH private root"
check_dir "/System/Devices" "runtime kernel view"
check_dir "/System/Process" "runtime kernel view"
check_dir "/System/Hardware" "runtime kernel view"
check_dir "/System/Runtime/Devices" "runtime view"
check_dir "/System/Runtime/Display" "runtime view"
check_dir "/System/Runtime/Kernel/proc" "runtime view"
check_dir "/System/Runtime/Kernel/sys" "runtime view"
check_dir "/System/Runtime/Networking" "runtime networking path"
check_dir "/System/Runtime/Networking/SSH" "runtime SSH path"
check_dir "/System/Runtime/Security" "runtime security path"
check_dir "/System/Runtime/Security/Tokens" "runtime security token path"
check_dir "/System/Runtime/Sessions" "runtime view"
check_dir "/System/Runtime/Sockets" "runtime view"
check_dir "/System/Security" "security authority path"
check_dir "/System/Security/Auth" "auth authority path"
check_dir "/System/UI" "UI namespace"
check_dir "/System/UI/Fonts" "UI namespace"
check_dir "/System/UI/Icons" "UI namespace"
check_dir "/System/UI/Sessions" "UI namespace"
check_dir "/System/UI/Shell" "UI namespace"
check_dir "/System/UI/Themes" "UI namespace"
check_dir "/System/UI/Shell/MixtarShell.apx" "system APX bundle"
check_dir "/System/UI/Shell/MixtarShell.apx/Program" "system APX bundle"
check_dir "/System/UI/Shell/MixtarShell.apx/Icon" "system APX bundle"
check_dir "/System/UI/Shell/MixtarShell.apx/Resources" "system APX bundle"
check_dir "/System/UI/Shell/MixtarShell.apx/Data" "system APX bundle"
check_absent "/Applications/MixtarShell.apx" "forbidden system UI APX under user applications"
check_absent "/System/Shells/MixtarShell.apx" "forbidden UI shell APX under system shells"
check_absent "/System/Userland/MixtarShell.apx" "forbidden APX bundle under userland commands"
check_absent "/System/Tools/MixtarShell.apx" "forbidden APX bundle under administrative tools"
check_absent "/System/Runtime/MixtarShell.apx" "forbidden APX bundle under runtime state"
check_dir "/System/Compatibility/POSIX/Linux" "compatibility root"
check_dir "/System/Compatibility/POSIX/OpenBSD" "compatibility root"
check_dir "/System/Compatibility/POSIX/FreeBSD" "compatibility root"

check_executable "/System/Init/MixtarRVS" "PID1"
check_executable "/System/Runtime/Executor" "APX runtime executor"
check_executable "/System/Networking/start-networking" "CoreV07 recovery networking service"
check_executable "/System/Networking/Core/ip" "CoreV07 ip wrapper"
check_executable "/System/Networking/Core/ip.bin" "CoreV07 ip binary"
check_executable "/System/Networking/WiFi/mixtar-wifi-service" "CoreV07 Wi-Fi service wrapper"
check_executable "/System/Networking/WiFi/bin/iwd" "CoreV07 iwd daemon"
check_executable "/System/Networking/WiFi/bin/dbus-daemon" "CoreV07 Wi-Fi dbus daemon"
check_nonempty_file "/System/Networking/WiFi/Runtime/ld-linux-x86-64.so.2" "CoreV07 Wi-Fi loader"
check_nonempty_file "/System/Networking/WiFi/Root/etc/passwd" "CoreV07 Wi-Fi private passwd"
check_nonempty_file "/System/Networking/WiFi/Root/etc/group" "CoreV07 Wi-Fi private group"
check_executable "/System/Networking/SSH/mixtar-sshd-service" "CoreV07 SSH service wrapper"
check_executable "/System/Networking/SSH/sbin/sshd" "CoreV07 OpenSSH daemon"
check_nonempty_file "/System/Networking/SSH/Runtime/ld-linux-x86-64.so.2" "CoreV07 OpenSSH loader"
check_nonempty_file "/System/Configuration/Networking/Networking.config" "CoreV07 Networking SQLite config"
check_nonempty_file "/System/Configuration/Networking/WiFi.config" "CoreV07 Wi-Fi SQLite config"
check_nonempty_file "/System/Configuration/Security/Policy.config" "CoreV07 security policy SQLite config"
check_nonempty_file "/System/Configuration/Security/AdminSession.config" "CoreV07 administrator session SQLite config"
check_nonempty_file "/System/Security/Auth.contract" "CoreV07 auth contract"
check_executable "/System/Userland/admin" "CoreV07 fail-closed admin command"
check_executable "/System/Userland/exit-admin" "CoreV07 exit-admin command"
check_nonempty_file "/System/Configuration/SSH/SSH.config" "CoreV07 SSH SQLite config"
check_nonempty_file "/System/Configuration/SSH/sshd_config" "CoreV07 OpenSSH config"
check_nonempty_file "/System/Configuration/SSH/HostKeys/ssh_host_ed25519_key" "CoreV07 OpenSSH host key"
check_nonempty_file "/System/Configuration/SSH/authorized_keys/vxz" "CoreV07 vxz authorized key"
check_staged_text_absent "/System/Configuration/SSH/sshd_config" "UsePAM" "CoreV07 OpenSSH config unsupported PAM option"
check_staged_text_contains "/System/Configuration/SSH/sshd_config" "ChrootDirectory /Native" "CoreV07 SSH sessions use clean native root"
check_staged_text_contains "/System/Configuration/SSH/sshd_config" "SetEnv PATH=/System/Shells:/System/Userland" "CoreV07 SSH sessions use native command PATH"
if [ "$(stat -c %a "$stage_root/System/Configuration/SSH/HostKeys/ssh_host_ed25519_key")" = "600" ]; then
    pass_check "CoreV07 OpenSSH host key staged mode is 0600"
elif grep -F 'ensure_mode("/System/Configuration/SSH/HostKeys/ssh_host_ed25519_key", 0600);' "$stage_source" >/dev/null 2>&1; then
    pass_check "CoreV07 OpenSSH host key mode is enforced by SSH runtime wrapper"
else
    fail_check "CoreV07 OpenSSH host key mode must be 0600 or enforced by SSH runtime wrapper"
fi
check_staged_strings_contains "/System/Networking/start-networking" "/System/Shells" "CoreV07 networking service uses /System/Shells"
check_staged_strings_contains "/System/Networking/start-networking" "/System/Networking/WiFi/mixtar-wifi-service" "CoreV07 networking service launches Wi-Fi wrapper"
check_staged_strings_contains "/System/Networking/start-networking" "/System/Networking/SSH/mixtar-sshd-service" "CoreV07 networking service launches SSH wrapper"
check_staged_strings_contains "/System/Networking/start-networking" "/System/Hardware/class/net" "CoreV07 networking service enumerates kernel network interfaces"
check_staged_strings_contains "/System/Networking/start-networking" "networking: kernel dmesg snapshot begin" "CoreV07 networking service logs kernel dmesg diagnostics"
check_staged_strings_contains "/System/Networking/start-networking" "networking: iface present" "CoreV07 networking service logs present interfaces"
check_staged_strings_absent "/System/Networking/start-networking" "192.168.99.110" "CoreV07 networking service avoids hardcoded recovery address"
check_staged_strings_contains "/System/Networking/start-networking" "ssh-probe detected native address" "CoreV07 SSH self-test discovers active IPv4"
check_staged_strings_contains "/System/Networking/start-networking" "static fallback disabled" "CoreV07 networking service avoids address conflicts"
check_staged_strings_contains "/System/Networking/start-networking" "CoreV07-last.log" "CoreV07 networking service exports boot logs to ESP"
check_source_contains "$stage_source" "CoreV07-last.log\", O_WRONLY | O_CREAT | O_TRUNC" "CoreV07 networking service truncates per-boot ESP log"
check_source_contains "$stage_source" "CoreV07-sshd.log\", O_WRONLY | O_CREAT | O_TRUNC" "CoreV07 SSH service truncates per-boot ESP log"
check_source_contains "$build_efi_source" 'regulatory_db_name="regulatory.db"' "CoreV07 EFI builder embeds regulatory.db"
check_source_contains "$build_efi_source" 'regulatory_db_signature_name="regulatory.db.p7s"' "CoreV07 EFI builder embeds regulatory.db signature"
check_source_contains "$boot_preflight_source" 'regulatory_db_name="regulatory.db"' "CoreV07 preflight checks regulatory.db"
check_source_contains "$boot_preflight_source" 'regulatory_db_signature_name="regulatory.db.p7s"' "CoreV07 preflight checks regulatory.db signature"
check_source_contains "$repo_root/Server/Kernel/configs/mixtar-corev07-rt.fragment" "CONFIG_CFG80211_CERTIFICATION_ONUS=y" "CoreV07 RT fragment owns cfg80211 regulatory policy"
check_source_contains "$repo_root/Server/Kernel/configs/mixtar-corev07-rt.fragment" "# CONFIG_CFG80211_REQUIRE_SIGNED_REGDB is not set" "CoreV07 RT fragment allows embedded recovery regulatory.db"
check_staged_strings_absent "/System/Networking/start-networking" "/System/Terminal" "CoreV07 networking service retired terminal path"
check_staged_strings_absent "/System/Networking/start-networking" "10.0.2.15" "CoreV07 networking service retired QEMU-only address"
check_staged_strings_contains "/System/Networking/start-networking" "existing DHCP/global IPv4 retained" "CoreV07 networking service prefers existing DHCP address"
check_staged_strings_absent "/System/Networking/start-networking" "for attempt in {1..90}" "CoreV07 networking service retired retry spam loop"
check_staged_text_contains "/System/Networking/Core/ip" "#!/System/Shells/zsh" "CoreV07 ip wrapper uses /System/Shells"
check_staged_text_absent "/System/Networking/Core/ip" "/System/Terminal" "CoreV07 ip wrapper retired terminal path"
check_staged_strings_contains "/System/Networking/WiFi/mixtar-wifi-service" "/System/Networking/WiFi/Root" "CoreV07 Wi-Fi wrapper uses private root"
check_staged_strings_absent "/System/Networking/WiFi/mixtar-wifi-service" "/System/Terminal" "CoreV07 Wi-Fi wrapper retired terminal path"
check_staged_strings_contains "/System/Networking/SSH/mixtar-sshd-service" "/System/Shells" "CoreV07 SSH wrapper binds shell namespace"
check_staged_strings_absent "/System/Networking/SSH/mixtar-sshd-service" "/System/Terminal" "CoreV07 SSH wrapper retired terminal path"
check_staged_strings_contains "/System/Networking/SSH/mixtar-sshd-service" "/run/sshd" "CoreV07 SSH wrapper keeps /run inside private chroot"
check_staged_strings_contains "/System/Networking/SSH/mixtar-sshd-service" "/System/Networking/SSH/Root/Native/System/Logs" "CoreV07 SSH wrapper exposes native logs only inside session root"
check_staged_strings_contains "/System/Networking/SSH/mixtar-sshd-service" "/System/Networking/SSH/Root/Native/System/Networking/Core" "CoreV07 SSH wrapper exposes native networking inside session root"
check_dir "/System/Runtime" "runtime namespace"
check_executable "/System/Shells/zsh" "default shell"
check_nonempty_file "/System/Shells/Runtime/ld-linux-x86-64.so.2" "zsh ELF loader"
check_nonempty_file "/System/Shells/Terminfo/l/linux" "zsh linux terminfo"
if command -v readelf >/dev/null 2>&1 && [ -x "$stage_root/System/Shells/zsh" ]; then
    if readelf -l "$stage_root/System/Shells/zsh" 2>/dev/null | grep -F '/System/Shells/Runtime/ld-linux-x86-64.so.2' >/dev/null 2>&1; then
        pass_check "zsh interpreter is CoreV07-native"
    else
        fail_check "zsh interpreter is not /System/Shells/Runtime/ld-linux-x86-64.so.2"
    fi
fi
check_nonempty_file "/System/EFI/MixtarRVS/$VERSION.efi" "official EFI"
check_nonempty_file "/System/EFI/MixtarRVS/$VERSION.efi.provenance" "official EFI provenance"
check_efi_provenance
if [ -s "$stage_root/System/EFI/MixtarRVS/$VERSION.efi" ]; then
    check_mz_file "/System/EFI/MixtarRVS/$VERSION.efi" "official EFI"
fi

check_pid1_source_contains "while mi_pid1_should_run() != 0 then" "has non-returning supervisor loop"
check_pid1_source_contains "mi_spawn_session" "spawns session as child"
check_pid1_source_contains "mi_reboot_now()" "has native reboot path"
check_pid1_source_contains "mi_poweroff_now()" "has native poweroff path"
check_pid1_source_contains "if mi_exists(config_db) != 0 then" "binds persistent configuration only when its database exists"
check_pid1_source_contains "if mi_exists(MI_PERSISTENCE_READY_MARKER) != 0 then" "uses positive persistence-ready marker semantics"
check_source_contains "$pid1_defs_source" "const int MI_AUTORETURN_MS = 300000" "PID1 defs have 5m autoreturn constant"
check_pid1_source_contains "ail_sleep_ms(MI_AUTORETURN_MS)" "uses autoreturn constant instead of hardcoded sleep"
check_source_contains "$pid1_defs_source" 'const string MI_TOOL_PREFIX = "/System/Userland/"' "PID1 defs use userland command prefix"
check_source_contains "$pid1_defs_source" 'const string MI_SESSION_ENV_PATH = "PATH=/System/Shells:/System/Userland"' "PID1 defs use userland session PATH"
check_pid1_source_absent "exit_group" "exit_group"
check_pid1_source_absent "exec zsh" "exec zsh as PID1"
check_source_absent "$pid1_defs_source" 'MI_TOOL_PREFIX = "/System/Tools/"' "PID1 defs old tools command prefix"
check_source_absent "$pid1_defs_source" 'MI_SESSION_ENV_PATH = "PATH=/System/Shells:/System/Tools"' "PID1 defs old tools session PATH"

check_source_contains "$executor_source" "sql_open_readonly" "Executor source opens APX config read-only"
check_source_contains "$executor_source" "app.id" "Executor source requires APX app.id metadata"
check_source_contains "$executor_source" "app.name" "Executor source requires APX app.name metadata"
check_source_contains "$executor_source" "app.version" "Executor source requires APX app.version metadata"
check_source_contains "$executor_source" "ENTRY_TYPE_NATIVE" "Executor source supports native APX entry"
check_source_contains "$executor_source" "native APX entry requires runtime=mixtar" "Executor source rejects invalid native runtime"
check_source_contains "$executor_source" "ailang APX entry requires runtime=ailang" "Executor source rejects invalid AILang runtime"
check_source_contains "$executor_source" "Program" "Executor source has Program/<bundle> entry convention"
check_source_contains "$executor_source" "PATH=/System/Userland" "Executor source APX PATH starts from userland"
check_source_absent "$executor_source" "PATH=/System/Userland:/System/Tools" "Executor source administrative tools in APX PATH"
check_source_absent "$executor_source" "/System/Tools/ailang" "Executor source hidden AILang runtime under /System/Tools"
check_source_absent "$executor_source" "/System/Drivers" "Executor source driver store in PATH"
check_source_contains "$executor_source" "MIXTAR_APX_RUNTIME" "Executor source exports APX runtime"
check_source_absent "$executor_source" "Launcher.ail" "Executor source Launcher.ail"
check_source_absent "$executor_source" "Info.xml" "Executor source Info.xml"
check_source_absent "$stage_source" 'System/Tools" "$stage_root/System/Userland' "stage source legacy Tools-to-Userland fallback"
check_source_absent "$stage_source" "/System/Config/" "stage source retired duplicate configuration subtree"
check_source_absent "$stage_source" "System/Config/" "stage source retired duplicate configuration subtree"
check_source_absent "$stage_source" "/System/Applications" "stage source retired system applications path"
check_source_absent "$stage_source" "efibootmgr" "stage source EFI variable mutation"
check_source_absent "$stage_source" "update-grub" "stage source Debian GRUB update"
check_source_absent "$stage_source" "grub-install" "stage source Debian GRUB install"
check_source_absent "$stage_source" "bootctl" "stage source systemd-boot mutation"
check_source_absent "$stage_source" "bcdedit" "stage source host boot manager mutation"
check_source_absent "$stage_source" "apt " "stage source Debian package mutation"
check_source_absent "$stage_source" "dpkg " "stage source Debian package database mutation"
check_source_absent "$stage_source" "mount /boot/efi" "stage source ESP mount mutation"
check_source_absent "$stage_source" "umount /boot/efi" "stage source ESP unmount mutation"
check_source_contains "$stage_source" "scope:      generated-only" "stage plan declares generated-only scope"
check_source_contains "$stage_source" "stage_corev07_networking" "stage source includes CoreV07 networking staging"
check_source_contains "$stage_source" "build_corev07_sshd_service" "stage source rebuilds CoreV07 SSH service wrapper"
check_source_contains "$stage_source" "secure_chroot_component(root)" "stage source secures SSH private root ownership and mode"
check_source_contains "$stage_source" "SetEnv PATH=/System/Shells:/System/Userland" "stage source normalizes SSH native command PATH"
check_source_contains "$stage_source" 'secure_chroot_component("/System/Networking/SSH/Root/Native")' "stage source secures SSH native chroot ownership and mode"
check_source_contains "$stage_source" "write_corev07_networking_service" "stage source writes CoreV07 networking service"
check_source_contains "$stage_source" "boot:       disabled" "stage plan declares boot deployment disabled"
check_source_contains "$stage_source" "efi-write:  disabled" "stage plan declares EFI writes disabled"
check_source_contains "$stage_source" "not an installer" "stage plan rejects installer role"
check_source_contains "$stage_source" "not a deployment tool" "stage plan rejects deployment role"
check_source_contains "$stage_source" 'exec "$script_dir/corev07-verify.sh" --root "$stage_root" --efi-stage "$efi_stage"' "stage verify command delegates to local verifier"
check_source_contains "$stage_source" 'require_safe_generated_path "$stage_root"' "stage validates staged root path before cleanup"
check_source_contains "$stage_source" 'require_safe_generated_path "$efi_stage"' "stage validates EFI mirror path before cleanup"
check_source_contains "$stage_source" 'rm -rf "$stage_root" "$efi_stage"' "stage cleanup is limited to staged root and EFI mirror variables"
if [ -f "$local_gate_source" ]; then
    pass_check "CoreV07 local gate exists"
else
    fail_check "CoreV07 local gate missing"
fi
if [ -f "$boot_preflight_source" ]; then
    pass_check "CoreV07 boot preflight exists"
else
    fail_check "CoreV07 boot preflight missing"
fi
check_source_contains "$local_gate_source" 'sh "$script_dir/corev07-stage-root.sh" plan "$@"' "local gate runs plan first"
check_source_contains "$local_gate_source" 'sh "$script_dir/corev07-stage-root.sh" stage "$@"' "local gate runs stage second"
check_source_contains "$local_gate_source" 'sh "$script_dir/corev07-stage-root.sh" verify "$@"' "local gate runs verify third"
check_source_contains "$local_gate_source" 'sh "$script_dir/corev07-boot-preflight.sh" "$@"' "local gate runs boot preflight fourth"
check_source_contains "$local_gate_source" "not an installer" "local gate rejects installer role"
check_source_contains "$local_gate_source" "not a deployment tool" "local gate rejects deployment role"
check_source_absent "$local_gate_source" "efibootmgr" "local gate EFI variable mutation"
check_source_absent "$local_gate_source" "update-grub" "local gate Debian GRUB update"
check_source_absent "$local_gate_source" "grub-install" "local gate Debian GRUB install"
check_source_absent "$local_gate_source" "bootctl" "local gate systemd-boot mutation"
check_source_absent "$local_gate_source" "bcdedit" "local gate host boot manager mutation"
check_source_absent "$local_gate_source" "apt " "local gate Debian package mutation"
check_source_absent "$local_gate_source" "dpkg " "local gate Debian package database mutation"
check_source_absent "$local_gate_source" "mount /boot/efi" "local gate ESP mount mutation"
check_source_absent "$local_gate_source" "umount /boot/efi" "local gate ESP unmount mutation"
check_source_absent "$local_gate_source" "reboot" "local gate reboot mutation"
check_source_contains "$boot_preflight_source" "rdinit=/System/Init/MixtarRVS" "boot preflight checks Mixtar rdinit"
check_source_contains "$boot_preflight_source" "devtmpfs.mount=0" "boot preflight checks hidden /dev automount policy"
check_source_contains "$boot_preflight_source" "Linux initrd" "boot preflight checks embedded initrd evidence"
check_source_contains "$boot_preflight_source" "check_needed_libs" "boot preflight checks dynamic library closure"
check_source_contains "$boot_preflight_source" "sha256sum" "boot preflight checks EFI mirror hash"
check_source_contains "$boot_preflight_source" "COREV07_REQUIRE_AUTORETURN" "boot preflight supports one-shot autoreturn requirement"
check_source_contains "$boot_preflight_source" "mixtar.autoreturn=1" "boot preflight checks Mixtar autoreturn cmdline"
check_source_contains "$boot_preflight_source" "mixtar.persist_logs=1" "boot preflight checks Mixtar persistent boottrace cmdline"
check_source_contains "$boot_preflight_source" "panic=300" "boot preflight checks kernel panic watchdog cmdline"
check_source_absent "$boot_preflight_source" "efibootmgr" "boot preflight EFI variable mutation"
check_source_absent "$boot_preflight_source" "update-grub" "boot preflight Debian GRUB update"
check_source_absent "$boot_preflight_source" "grub-install" "boot preflight Debian GRUB install"
check_source_absent "$boot_preflight_source" "bootctl" "boot preflight systemd-boot mutation"
check_source_absent "$boot_preflight_source" "bcdedit" "boot preflight host boot manager mutation"
check_source_absent "$boot_preflight_source" "apt " "boot preflight Debian package mutation"
check_source_absent "$boot_preflight_source" "dpkg " "boot preflight Debian package database mutation"
check_source_absent "$boot_preflight_source" "mount /boot/efi" "boot preflight ESP mount mutation"
check_source_absent "$boot_preflight_source" "umount /boot/efi" "boot preflight ESP unmount mutation"
check_source_absent "$boot_preflight_source" "systemctl reboot" "boot preflight reboot mutation"
check_source_absent "$boot_preflight_source" "/sbin/reboot" "boot preflight reboot mutation"
check_source_absent "$boot_preflight_source" " shutdown " "boot preflight shutdown mutation"
check_source_contains "$build_efi_source" "COREV07_AUTORETURN" "EFI builder supports explicit one-shot autoreturn mode"
check_source_contains "$build_efi_source" "iwlwifi-8265-36.ucode" "EFI builder embeds Intel 8265 Wi-Fi firmware"
check_source_contains "$build_efi_source" "EXTRA_FIRMWARE" "EFI builder uses kernel embedded firmware"
check_source_contains "$build_efi_source" "mixtar.autoreturn=1" "EFI builder embeds autoreturn when requested"
check_source_contains "$build_efi_source" "mixtar.persist_logs=1" "EFI builder embeds persistent boottrace when requested"
check_source_contains "$build_efi_source" "panic=300" "EFI builder embeds kernel panic watchdog when requested"
check_source_contains "$build_efi_source" 'full_cmdline="$base_cmdline' "EFI builder has single computed cmdline"
check_source_contains "$build_efi_source" '--set-str CMDLINE "$full_cmdline"' "EFI builder passes computed cmdline to kernel config"
check_source_absent "$build_efi_source" "efibootmgr" "EFI builder EFI variable mutation"
check_source_absent "$build_efi_source" "update-grub" "EFI builder Debian GRUB update"
check_source_absent "$build_efi_source" "grub-install" "EFI builder Debian GRUB install"
check_source_absent "$build_efi_source" "bootctl" "EFI builder systemd-boot mutation"
check_source_absent "$build_efi_source" "bcdedit" "EFI builder host boot manager mutation"
check_source_absent "$build_efi_source" "apt " "EFI builder Debian package mutation"
check_source_absent "$build_efi_source" "dpkg " "EFI builder Debian package database mutation"
check_source_absent "$build_efi_source" "mount /boot/efi" "EFI builder ESP mount mutation"
check_source_absent "$build_efi_source" "umount /boot/efi" "EFI builder ESP unmount mutation"
if [ -x "$one_shot_script_source" ]; then
    pass_check "one-shot deploy script exists and is executable"
else
    fail_check "one-shot deploy script missing or not executable"
fi
check_source_contains "$one_shot_script_source" "Default mode is dry-run/read-only" "one-shot script documents dry-run default"
check_source_contains "$one_shot_script_source" 'if [ "$apply" -ne 1 ]' "one-shot script requires --apply for mutation"
check_source_contains "$one_shot_script_source" 'if [ "$reboot_after" = "1" ]' "one-shot script requires --reboot for reboot"
check_source_contains "$one_shot_script_source" "BatchMode=yes" "one-shot script disables interactive SSH password prompts"
check_source_contains "$one_shot_script_source" "ConnectTimeout=8" "one-shot script uses bounded SSH timeout"
check_source_contains "$one_shot_script_source" "sudo -n" "one-shot script disables interactive sudo prompts"
check_source_contains "$one_shot_script_source" "mixtar.autoreturn=1" "one-shot script verifies autoreturn artifact"
check_source_contains "$one_shot_script_source" "mixtar.persist_logs=1" "one-shot script verifies persistent boottrace artifact"
check_source_contains "$one_shot_script_source" "panic=300" "one-shot script verifies kernel panic watchdog artifact"
check_source_contains "$one_shot_script_source" "efibootmgr -n" "one-shot script sets BootNext"
check_source_contains "$one_shot_script_source" "efibootmgr -c" "one-shot script can create missing Mixtar EFI entry"
check_source_contains "$one_shot_script_source" "old_boot_order=" "one-shot script captures original BootOrder"
check_source_contains "$one_shot_script_source" 'efibootmgr -o "$old_boot_order"' "one-shot script restores original BootOrder after entry creation"
check_source_contains "$one_shot_script_source" "--replace-entry" "one-shot script can replace broken test entry"
check_source_contains "$one_shot_script_source" 'loader="\\EFI\\MixtarRVS\\${version}.efi"' "one-shot script uses canonical EFI loader path"
check_source_absent "$one_shot_script_source" "update-grub" "one-shot script Debian GRUB update"
check_source_absent "$one_shot_script_source" "grub-install" "one-shot script Debian GRUB install"
check_source_absent "$one_shot_script_source" "apt " "one-shot script Debian package mutation"
check_source_absent "$one_shot_script_source" "dpkg " "one-shot script Debian package database mutation"
check_source_absent "$one_shot_script_source" "mkfs" "one-shot script filesystem formatting"
if [ -f "$repo_root/Server/Runtime/Executor/mixtar_executor.c" ]; then
    fail_check "retired C executor fallback must not exist"
else
    pass_check "retired C executor fallback absent"
fi

check_executable "/System/Userland/echo" "base userland echo"
check_executable "/System/Userland/cat" "base userland cat"
check_executable "/System/Userland/pwd" "base userland pwd"
check_executable "/System/Userland/ls" "base userland ls"
check_executable "/System/Userland/ping" "native userland ping"
check_sqlite_root_dir "/System/Configuration/MixtarRVS.config" "/System/EFI" "PID1 SQLite config"
check_sqlite_root_dir "/System/Configuration/MixtarRVS.config" "/System/EFI/MixtarRVS" "PID1 SQLite config"
check_absent "/System/Tools/echo" "forbidden userland command under administrative tools"
check_absent "/System/Tools/cat" "forbidden userland command under administrative tools"
check_absent "/System/Tools/pwd" "forbidden userland command under administrative tools"
check_absent "/System/Tools/ls" "forbidden userland command under administrative tools"
check_absent "/System/Tools/sh" "forbidden shell under administrative tools"
check_absent "/System/Tools/ailang" "forbidden runtime under administrative tools"
check_absent "/System/Tools/ailang-run" "forbidden runtime under administrative tools"
check_absent "/System/Tools/drivers" "forbidden driver tool under administrative tools"

check_absent "/System/EFI/MixtarRVS/Current.efi" "forbidden unversioned EFI"
check_absent "/System/EFI/MixtarRVS/Previous.efi" "forbidden rollback EFI"
check_absent "/System/Kernel/Linux/RT/$KERNEL_VERSION/vmlinuz" "forbidden split boot artifact"
check_absent "/System/Kernel/Linux/RT/$KERNEL_VERSION/initramfs" "forbidden split boot artifact"
check_absent "/System/Kernel/Linux/RT/$KERNEL_VERSION/initrd" "forbidden split boot artifact"

check_file "/System/Configuration/MixtarRVS.config.sql" "SQLite config seed"
check_file "/System/Configuration/CoreV07.contract" "CoreV07 marker"
if [ -f "$repo_root/Server/Rootfs/COREV07_CONTRACT.md" ]; then
    pass_check "CoreV07 source contract exists"
else
    fail_check "CoreV07 source contract missing"
fi
check_source_contains "$contract_source" "stage.scope = generated-only" "CoreV07 source contract declares generated-only staging"
check_source_contains "$contract_source" "boot.deploy = disabled" "CoreV07 source contract disables boot deployment"
check_source_contains "$contract_source" "efi.mutation = disabled" "CoreV07 source contract disables EFI mutation"
check_source_contains "$contract_source" "run the local CoreV07 verifier" "CoreV07 source contract requires local verifier before boot"
check_source_contains "$contract_source" "only then consider boot or deployment tests" "CoreV07 source contract keeps boot after verifier"
check_source_contains "$contract_source" "requires a separate decision" "CoreV07 source contract keeps deployment separate"
check_source_contains "$contract_source" "Server/Rootfs/scripts/corev07-local-gate.sh" "CoreV07 source contract declares local gate"
check_source_contains "$contract_source" "This local gate must remain local-only." "CoreV07 source contract keeps local gate local-only"
check_source_contains "$contract_source" "It must not be extended into installation" "CoreV07 source contract blocks local gate installation role"
check_source_contains "$contract_source" "EFI mutation, or Debian mutation" "CoreV07 source contract blocks local gate EFI and Debian mutation"
check_source_contains "$contract_source" "/System/Runtime/Executor" "CoreV07 source contract declares APX Executor path"
check_source_contains "$contract_source" "source: AILang" "CoreV07 source contract declares AILang Executor source"
check_source_contains "$contract_source" "source path: Server/Runtime/Executor/mixtar_executor.ail" "CoreV07 source contract declares AILang Executor source path"
check_source_contains "$contract_source" "mode: command-root" "CoreV07 source contract declares userland command-root mode"
check_source_contains "$contract_source" "mode: sqlite-primary" "CoreV07 source contract declares config sqlite-primary mode"
check_source_contains "$contract_source" "mode: store-only" "CoreV07 source contract declares drivers store-only mode"
check_source_contains "$contract_source" "mode: admin-only" "CoreV07 source contract declares tools admin-only mode"
check_source_contains "$one_shot_source" "COREV07_REQUIRE_AUTORETURN=1" "one-shot contract requires autoreturn preflight"
check_source_contains "$one_shot_source" "Server/Rootfs/scripts/corev07-oneshot-deploy.sh" "one-shot contract declares controlled deploy script"
check_source_contains "$one_shot_source" "ssh BatchMode=yes" "one-shot contract requires non-interactive SSH"
check_source_contains "$one_shot_source" "sudo -n" "one-shot contract requires non-interactive sudo"
check_source_contains "$one_shot_source" "BootNext only" "one-shot contract restricts boot mutation to BootNext"
check_source_contains "$one_shot_source" "mixtar.autoreturn=1" "one-shot contract requires Mixtar autoreturn"
check_source_contains "$one_shot_source" "panic=300" "one-shot contract requires kernel panic watchdog"
check_source_contains "$one_shot_script_source" "provenance" "one-shot deploy verifies EFI provenance"
check_source_contains "$one_shot_script_source" '$data_mount/System/EFI/MixtarRVS/$version.efi' "one-shot deploy installs versioned EFI into Mixtar data root"
check_source_contains "$one_shot_script_source" "persistent EFI artifact hash mismatch" "one-shot deploy verifies persistent EFI hash"
check_source_absent "$one_shot_script_source" '"/System/EFI/MixtarRVS/$version.efi" || true' "one-shot deploy never writes best-effort EFI into live host root"
check_source_contains "$one_shot_script_source" "source_mode=build" "one-shot deploy requires build provenance"
check_source_contains "$one_shot_source" "leaving BootOrder changed" "one-shot contract forbids leaving BootOrder changed"
check_source_contains "$one_shot_source" "restore the original" "one-shot contract requires BootOrder restoration"
check_source_contains "$one_shot_source" "running update-grub" "one-shot contract forbids update-grub"
check_source_contains "$one_shot_source" "running grub-install" "one-shot contract forbids grub-install"
check_source_contains "$one_shot_source" "formatting partitions" "one-shot contract forbids formatting"
check_source_contains "$bundle_model_source" "ApplicationName.apx/" "APX bundle model declares APX directory shape"
check_source_contains "$bundle_model_source" "ApplicationName.config" "APX bundle model declares SQLite config file"
check_source_contains "$bundle_model_source" "Program/ApplicationName" "APX bundle model declares Program entrypoint"
check_source_contains "$bundle_model_source" "entry.type=native" "APX bundle model declares native entry type"
check_source_contains "$bundle_model_source" "runtime=mixtar" "APX bundle model declares Mixtar runtime"
check_source_contains "$bundle_model_source" "entry.path=Program/<bundle-base-name>" "APX bundle model declares default Program entry path"
check_source_absent "$bundle_model_source" "Launcher.ail" "APX bundle model retired launcher file"
check_source_absent "$bundle_model_source" "Info.xml" "APX bundle model retired XML metadata"
check_source_contains "$layout_policy_source" "/System/Userland" "layout policy declares userland path"
check_source_contains "$layout_policy_source" "mode: command-root" "layout policy declares userland command-root mode"
check_source_contains "$layout_policy_source" "/System/Runtime/Executor" "layout policy declares APX Executor path"
check_source_contains "$layout_policy_source" "/System/Configuration" "layout policy declares config path"
check_source_contains "$layout_policy_source" "mode: sqlite-primary" "layout policy declares config sqlite-primary mode"
check_source_contains "$layout_policy_source" "/System/Drivers" "layout policy declares driver path"
check_source_contains "$layout_policy_source" "mode: store-only" "layout policy declares drivers store-only mode"
check_source_contains "$layout_policy_source" "/System/Tools" "layout policy declares tools path"
check_source_contains "$layout_policy_source" "mode: admin-only" "layout policy declares tools admin-only mode"
check_source_contains "$layout_policy_source" "not part of the default user or APX PATH" "layout policy keeps tools out of default PATH"
check_source_contains "$layout_policy_source" "/System/Security" "layout policy declares security authority path"
check_source_contains "$layout_policy_source" "mode: authority-policy" "layout policy declares security authority-policy mode"
check_source_contains "$layout_policy_source" "/System/Runtime/Security" "layout policy declares runtime security path"
check_source_contains "$layout_policy_source" "Administrator: Mixtar Terminal" "layout policy declares administrator terminal status"
check_source_contains "$layout_policy_source" "sudo.default=false" "layout policy declares sudo default policy"
check_source_contains "$layout_policy_source" "/System/UI/Shell/MixtarShell.apx" "layout policy declares system UI shell APX"
check_nonempty_file "/System/Configuration/MixtarRVS.config" "PID1 SQLite config"
check_sqlite_file "/System/Configuration/Networking/Networking.config" "CoreV07 Networking SQLite config"
check_sqlite_file "/System/Configuration/Networking/WiFi.config" "CoreV07 Wi-Fi SQLite config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" "runtime.executor" "/System/Runtime/Executor" "PID1 SQLite config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" "runtime.executor.source" "AILang" "PID1 SQLite config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" "runtime.executor.source.path" "Server/Runtime/Executor/mixtar_executor.ail" "PID1 SQLite config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" "session.reboot.status" "200" "PID1 lifecycle protocol"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" "session.poweroff.status" "201" "PID1 lifecycle protocol"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" "persistence.enabled" "true" "PID1 persistence config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" "persistence.device" "/System/Devices/nvme0n1p3" "PID1 persistence config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" "persistence.fstype" "ext4" "PID1 persistence config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" "persistence.users.source" "/Volumes/MixtarRoot/Users" "PID1 persistence config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" "persistence.users.target" "/Users" "PID1 persistence config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" "persistence.configuration.source" "/Volumes/MixtarRoot/System/Configuration" "PID1 persistence config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" "persistence.configuration.target" "/System/Configuration" "PID1 persistence config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" "applications.user" "/Applications" "PID1 SQLite config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" "applications.mode" "user-visible-only" "PID1 SQLite config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" "system.ui.shell" "/System/UI/Shell" "PID1 SQLite config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" "system.ui.shell.apx" "/System/UI/Shell/MixtarShell.apx" "PID1 SQLite config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" "stage.scope" "generated-only" "PID1 SQLite config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" "boot.deploy" "disabled" "PID1 SQLite config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" "efi.mutation" "disabled" "PID1 SQLite config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" "config.path" "/System/Configuration" "PID1 SQLite config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" "config.mode" "sqlite-primary" "PID1 SQLite config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" "userland.path" "/System/Userland" "PID1 SQLite config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" "userland.mode" "command-root" "PID1 SQLite config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" "tools.path" "/System/Tools" "PID1 SQLite config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" "tools.mode" "admin-only" "PID1 SQLite config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" "drivers.path" "/System/Drivers" "PID1 SQLite config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" "drivers.mode" "store-only" "PID1 SQLite config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" "networking.config" "/System/Configuration/Networking/Networking.config" "PID1 SQLite config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" "wifi.config" "/System/Configuration/Networking/WiFi.config" "PID1 SQLite config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" "regulatory.db" "embedded" "PID1 SQLite config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" "security.path" "/System/Security" "PID1 SQLite config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" "security.policy" "/System/Configuration/Security/Policy.config" "PID1 SQLite config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" "security.auth" "/System/Security/Auth" "PID1 SQLite config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" "security.runtime" "/System/Runtime/Security" "PID1 SQLite config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" "security.auth.socket" "/System/Runtime/Security/Auth.sock" "PID1 SQLite config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" "admin.mode" "session-token" "PID1 SQLite config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" "admin.command" "admin" "PID1 SQLite config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" "admin.session.title" "Administrator: Mixtar Terminal" "PID1 SQLite config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" "admin.session.prompt" "unchanged" "PID1 SQLite config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" "sudo.default" "false" "PID1 SQLite config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" "session.exec" "/System/Shells/zsh" "PID1 SQLite config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" "networking.service" "/System/Networking/start-networking" "PID1 SQLite config"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" "networking.ping.group_range.path" "/System/Process/sys/net/ipv4/ping_group_range" "PID1 ICMP policy"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" "networking.ping.gid.min" "0" "PID1 ICMP policy"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" "networking.ping.gid.max" "1000" "PID1 ICMP policy"
check_source_contains "$pid1_source" "mi_configure_ping_group" "PID1 owns config-driven ICMP policy"
check_source_absent "$stage_source" "configure_ping_group_range(void)" "network service does not override PID1 ICMP policy"
check_sqlite_meta "/System/Configuration/MixtarRVS.config" "compat.exec" "/System/Userland/compat-exec" "PID1 SQLite config"
check_sqlite_file "/System/Configuration/SSH/SSH.config" "CoreV07 SSH SQLite config"
check_sqlite_meta "/System/Configuration/Networking/Networking.config" "networking.mode" "recovery-corev07" "CoreV07 Networking SQLite config"
check_sqlite_meta "/System/Configuration/Networking/Networking.config" "networking.ui" "false" "CoreV07 Networking SQLite config"
check_sqlite_meta "/System/Configuration/Networking/Networking.config" "regulatory.db" "embedded" "CoreV07 Networking SQLite config"
check_sqlite_meta "/System/Configuration/Networking/WiFi.config" "wifi.mode" "recovery-corev07" "CoreV07 Wi-Fi SQLite config"
check_sqlite_meta "/System/Configuration/Networking/WiFi.config" "wifi.backend" "iwd" "CoreV07 Wi-Fi SQLite config"
check_sqlite_meta "/System/Configuration/Networking/WiFi.config" "wifi.regulatory_db" "embedded" "CoreV07 Wi-Fi SQLite config"
check_sqlite_setting "/System/Configuration/Security/Policy.config" "admin.mode" "session-token" "CoreV07 security policy"
check_sqlite_setting "/System/Configuration/Security/Policy.config" "admin.command" "admin" "CoreV07 security policy"
check_sqlite_setting "/System/Configuration/Security/Policy.config" "admin.session.title" "Administrator: Mixtar Terminal" "CoreV07 security policy"
check_sqlite_setting "/System/Configuration/Security/Policy.config" "admin.session.prompt" "unchanged" "CoreV07 security policy"
check_sqlite_setting "/System/Configuration/Security/Policy.config" "sudo.default" "false" "CoreV07 security policy"
check_sqlite_setting "/System/Configuration/Security/AdminSession.config" "title" "Administrator: Mixtar Terminal" "CoreV07 admin session"
check_sqlite_setting "/System/Configuration/Security/AdminSession.config" "prompt" "unchanged" "CoreV07 admin session"
check_sqlite_setting "/System/Configuration/Security/AdminSession.config" "user.display" "vxz" "CoreV07 admin session"
check_file "/System/Configuration/MixtarRVS.init" "PID1 text fallback config"
check_nonempty_file "/System/Configuration/ZSH/ZSH.config" "ZSH SQLite config"
check_sqlite_setting "/System/Configuration/ZSH/ZSH.config" "shell.path" "/System/Shells/zsh" "ZSH SQLite config"
check_sqlite_setting "/System/Configuration/ZSH/ZSH.config" "runtime.path" "/System/Shells/Runtime" "ZSH SQLite config"
check_sqlite_setting "/System/Configuration/ZSH/ZSH.config" "path" "/System/Shells:/System/Userland" "ZSH SQLite config"
check_nonempty_file "/System/UI/Session.config" "Session SQLite config"
check_file "/System/UI/Session.contract" "Session text contract"
check_sqlite_file "/System/UI/Shell/MixtarShell.apx/MixtarShell.config" "MixtarShell APX config"
check_sqlite_setting "/System/UI/Shell/MixtarShell.apx/MixtarShell.config" "app.id" "org.mixtar.shell.MixtarShell" "MixtarShell APX config"
check_sqlite_setting "/System/UI/Shell/MixtarShell.apx/MixtarShell.config" "app.name" "MixtarShell" "MixtarShell APX config"
check_sqlite_setting "/System/UI/Shell/MixtarShell.apx/MixtarShell.config" "app.version" "0.1" "MixtarShell APX config"
check_sqlite_setting "/System/UI/Shell/MixtarShell.apx/MixtarShell.config" "entry.type" "native" "MixtarShell APX config"
check_sqlite_setting "/System/UI/Shell/MixtarShell.apx/MixtarShell.config" "entry.path" "Program/MixtarShell" "MixtarShell APX config"
check_sqlite_setting "/System/UI/Shell/MixtarShell.apx/MixtarShell.config" "runtime" "mixtar" "MixtarShell APX config"
check_executable "/System/UI/Shell/MixtarShell.apx/Program/MixtarShell" "MixtarShell APX entry"
check_absent "/System/UI/Shell/MixtarShell.apx/Launcher.ail" "retired APX launcher"
check_absent "/System/UI/Shell/MixtarShell.apx/Info.xml" "retired APX XML metadata"
check_file "/Users/vxz/.zshrc" "default user ZSH rc"
if [ -f "$stage_root/Users/vxz/.zshenv" ]; then
    if grep -F 'TERMINFO=/System/Shells/Terminfo' "$stage_root/Users/vxz/.zshenv" >/dev/null 2>&1; then
        pass_check "default user ZSH env sets CoreV07 terminfo"
    else
        fail_check "default user ZSH env does not set CoreV07 terminfo"
    fi
    if grep -F 'PATH=/System/Shells:/System/Userland' "$stage_root/Users/vxz/.zshenv" >/dev/null 2>&1 &&
       ! grep -F '/System/Tools' "$stage_root/Users/vxz/.zshenv" >/dev/null 2>&1 &&
       ! grep -F '/System/Drivers' "$stage_root/Users/vxz/.zshenv" >/dev/null 2>&1; then
        pass_check "default user ZSH env uses command-root PATH only"
    else
        fail_check "default user ZSH env leaks admin or driver paths"
    fi
fi
check_file "/System/Kernel/Linux/RT/$KERNEL_VERSION/kernel-profile.json" "kernel profile manifest"
check_nonempty_file "/System/Drivers/Linux/RT/$KERNEL_VERSION/Drivers.config" "driver store SQLite config"
check_nonempty_file "/System/Drivers/Linux/RT/$KERNEL_VERSION/Drivers.status" "driver store status"
check_absent "/System/Drivers/drivers" "driver store executable command"

if [ -f "$stage_root/System/Configuration/MixtarRVS.init" ]; then
    if grep -F '/System/Terminal' "$stage_root/System/Configuration/MixtarRVS.init" >/dev/null 2>&1; then
        fail_check "PID1 fallback config contains retired CoreV07 paths"
    else
        pass_check "PID1 fallback config uses CoreV07 paths"
    fi
    if grep -F 'session.exec=/System/Shells/zsh' "$stage_root/System/Configuration/MixtarRVS.init" >/dev/null 2>&1; then
        pass_check "PID1 fallback config starts /System/Shells/zsh"
    else
        fail_check "PID1 fallback config does not start /System/Shells/zsh"
    fi
fi

if [ -f "$stage_root/System/Kernel/Linux/RT/$KERNEL_VERSION/kernel-profile.json" ]; then
    if grep -F '"version": "7.1.2"' "$stage_root/System/Kernel/Linux/RT/$KERNEL_VERSION/kernel-profile.json" >/dev/null 2>&1; then
        pass_check "kernel profile declares version 7.1.2"
    else
        fail_check "kernel profile does not declare version 7.1.2"
    fi
    if grep -F '"artifact": "/System/EFI/MixtarRVS/0.8.efi"' "$stage_root/System/Kernel/Linux/RT/$KERNEL_VERSION/kernel-profile.json" >/dev/null 2>&1; then
        pass_check "kernel profile declares CoreV07 EFI artifact"
    else
        fail_check "kernel profile does not declare CoreV07 EFI artifact"
    fi
fi

if [ -f "$stage_root/System/Drivers/Linux/RT/$KERNEL_VERSION/Drivers.status" ]; then
    if grep -F 'policy.no_visible_dev=true' "$stage_root/System/Drivers/Linux/RT/$KERNEL_VERSION/Drivers.status" >/dev/null 2>&1; then
        pass_check "driver store keeps /dev hidden from native root"
    else
        fail_check "driver store does not declare hidden /dev policy"
    fi
    if grep -F '[boot-required]' "$stage_root/System/Drivers/Linux/RT/$KERNEL_VERSION/Drivers.status" >/dev/null 2>&1 &&
       grep -F '[hardware-present]' "$stage_root/System/Drivers/Linux/RT/$KERNEL_VERSION/Drivers.status" >/dev/null 2>&1 &&
       grep -F '[blocked]' "$stage_root/System/Drivers/Linux/RT/$KERNEL_VERSION/Drivers.status" >/dev/null 2>&1; then
        pass_check "driver store has required categories"
    else
        fail_check "driver store missing required categories"
    fi
fi

if [ -f "$stage_root/System/UI/Session.contract" ]; then
    if grep -Fqx 'session.mode=console' "$stage_root/System/UI/Session.contract" &&
       grep -Fqx 'session.shell=/System/Shells/zsh' "$stage_root/System/UI/Session.contract" &&
       grep -Fqx 'ui.graphical.enabled=false' "$stage_root/System/UI/Session.contract" &&
       grep -Fqx 'runtime.executor=/System/Runtime/Executor' "$stage_root/System/UI/Session.contract" &&
       grep -Fqx 'apx.executor=/System/Runtime/Executor' "$stage_root/System/UI/Session.contract"; then
        pass_check "Session contract declares console-only UI base"
    else
        fail_check "Session contract does not declare expected console-only UI base"
    fi
fi

check_marker "version" "$VERSION"
check_marker "kernel_layout" "/System/Kernel/Linux/RT/$KERNEL_VERSION"
check_marker "boot_mode" "single-uki"
check_marker "boot_artifact" "/System/EFI/MixtarRVS/$VERSION.efi"
check_marker "pid1" "/System/Init/MixtarRVS"
check_marker "shell" "/System/Shells/zsh"
check_marker "executor" "/System/Runtime/Executor"
check_marker "executor_source" "AILang"
check_marker "executor_source_path" "Server/Runtime/Executor/mixtar_executor.ail"
check_marker "debian" "build-rescue-only"
check_marker "stage_scope" "generated-only"
check_marker "boot_deploy" "disabled"
check_marker "efi_mutation" "disabled"
check_marker "native_applications" "/Applications"
check_marker "native_applications_mode" "user-visible-only"
check_marker "native_config" "/System/Configuration"
check_marker "native_config_mode" "sqlite-primary"
check_marker "native_tools" "/System/Tools"
check_marker "native_tools_mode" "admin-only"
check_marker "native_userland" "/System/Userland"
check_marker "native_userland_mode" "command-root"
check_marker "native_drivers" "/System/Drivers"
check_marker "native_drivers_mode" "store-only"
check_marker "system_ui_shell" "/System/UI/Shell"
check_marker "system_ui_shell_apx" "/System/UI/Shell/MixtarShell.apx"
check_marker "security" "/System/Security"
check_marker "security_policy" "/System/Configuration/Security/Policy.config"
check_marker "security_runtime" "/System/Runtime/Security"
check_marker "admin_mode" "session-token"
check_marker "admin_command" "admin"
check_marker "sudo_default" "false"
check_marker "posix" "/System/Compatibility"

if [ -d "$efi_stage" ]; then
    if [ -s "$efi_stage/EFI/MixtarRVS/$VERSION.efi" ]; then
        pass_check "EFI stage contains EFI/MixtarRVS/$VERSION.efi"
        magic=$(dd if="$efi_stage/EFI/MixtarRVS/$VERSION.efi" bs=2 count=1 2>/dev/null || true)
        if [ "$magic" = "MZ" ]; then
            pass_check "EFI stage artifact has EFI/PE MZ header"
        else
            fail_check "EFI stage artifact does not have EFI/PE MZ header"
        fi
    else
        fail_check "EFI stage missing EFI/MixtarRVS/$VERSION.efi"
    fi
else
    fail_check "EFI stage directory missing: $efi_stage"
fi

if [ "$failures" -eq 0 ]; then
    printf '%s\n' "CoreV07 verifier: OK"
    exit 0
fi

printf '%s\n' "CoreV07 verifier: $failures failure(s)"
exit 1
