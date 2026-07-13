#!/bin/sh
set -eu

usage() {
    printf '%s\n' 'usage: corev09-verify.sh ROOT [SYSTEM_VERSION]'
    printf '%s\n' 'Read-only verifier for an offline MixtarRVS 0.9 root.'
}

root=${1:-}
system_version=${2:-0.9}

if [ -z "$root" ] || [ "$root" = "-h" ] || [ "$root" = "--help" ]; then
    usage
    [ -n "$root" ] && exit 0
    exit 64
fi

command -v realpath >/dev/null 2>&1 || { printf '%s\n' 'FAIL: realpath is required' >&2; exit 69; }
root=$(realpath "$root")
[ "$root" != "/" ] || { printf '%s\n' 'FAIL: refusing to verify host root' >&2; exit 73; }
[ -d "$root/System" ] || { printf '%s\n' "FAIL: not a Mixtar root: $root" >&2; exit 66; }

db="$root/System/Configuration/Updates.config"
failures=0

pass() { printf '%s\n' "PASS: $*"; }
fail() { failures=$((failures + 1)); printf '%s\n' "FAIL: $*" >&2; }

check_runtime_user_config() {
    runtime_db="$root/System/Configuration/MixtarRVS.config"
    command -v python3 >/dev/null 2>&1 || { fail 'python3 host verifier dependency missing'; return; }
    require_exec /System/Init/ConsoleSetup 'runtime ConsoleSetup'
    if command -v file >/dev/null 2>&1 && \
       file "$root/System/Init/ConsoleSetup" | grep -q 'statically linked'; then
        pass 'static runtime /System/Init/ConsoleSetup'
    else
        fail 'runtime ConsoleSetup is not static'
    fi
    if output=$(python3 - "$runtime_db" <<'PY'
import sqlite3
import sys

path = sys.argv[1]
try:
    connection = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    integrity = connection.execute("PRAGMA integrity_check").fetchone()[0]
    columns = {
        row[1] for row in connection.execute("PRAGMA table_info('user')")
    }
    default_user_row = connection.execute(
        "SELECT value FROM meta WHERE key='default.user'"
    ).fetchone()
    policies = dict(
        connection.execute(
            "SELECT key, value FROM meta WHERE key IN ("
            "'users.home.root','users.shell.default',"
            "'users.uid.minimum','users.gid.strategy')"
        )
    )
    boot_policy = dict(
        connection.execute(
            "SELECT key, value FROM meta WHERE key IN ("
            "'console.setup','console.keymap','locale.name',"
            "'networking.ping.group_range.path',"
            "'networking.ping.gid.min','networking.ping.gid.max')"
        )
    )
    if default_user_row is None:
        raise RuntimeError("default.user is missing")
    identity = connection.execute(
        "SELECT home, shell, uid, gid FROM user WHERE name=? COLLATE BINARY",
        (default_user_row[0],),
    ).fetchone()
    connection.close()
except Exception as error:
    print(error)
    raise SystemExit(1)

required_columns = {"name", "home", "shell", "uid", "gid"}
if integrity != "ok":
    raise SystemExit("integrity check failed")
if not required_columns.issubset(columns):
    raise SystemExit("user table lacks name/home/shell/uid/gid")
if identity is None or not identity[0] or not identity[1] or identity[2] <= 0 or identity[3] <= 0:
    raise SystemExit("default user identity is invalid")
required_policies = {
    "users.home.root",
    "users.shell.default",
    "users.uid.minimum",
    "users.gid.strategy",
}
if set(policies) != required_policies or any(not value for value in policies.values()):
    raise SystemExit("users.* policy is incomplete")
expected_boot_policy = {
    "console.setup": "/System/Init/ConsoleSetup",
    "console.keymap": "pl",
    "locale.name": "C.UTF-8",
    "networking.ping.group_range.path": "/System/Process/sys/net/ipv4/ping_group_range",
    "networking.ping.gid.min": "0",
    "networking.ping.gid.max": "1000",
}
if boot_policy != expected_boot_policy:
    raise SystemExit("console/locale/ICMP policy is incomplete")
print(f"default user {default_user_row[0]} uid={identity[2]} gid={identity[3]}")
PY
    ); then
        pass "runtime user configuration $output"
    else
        fail "runtime user configuration: $output"
    fi
}

require_file() {
    if [ -s "$root$1" ]; then pass "$2"; else fail "$2 missing: $1"; fi
}

require_exec() {
    if [ -x "$root$1" ]; then pass "$2"; else fail "$2 not executable: $1"; fi
}

require_dir() {
    if [ -d "$root$1" ]; then pass "$2"; else fail "$2 missing: $1"; fi
}

require_absent() {
    if [ -e "$root$1" ] || [ -L "$root$1" ]; then fail "$2 must be absent: $1"; else pass "$2 absent"; fi
}

db_query() {
    python3 - "$db" "$1" <<'PY'
import sqlite3
import sys

path, query = sys.argv[1:3]
try:
    connection = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    row = connection.execute(query).fetchone()
    connection.close()
except Exception as error:
    print(f"__SQL_ERROR__:{error}")
    raise SystemExit(0)
if row is not None and row[0] is not None:
    print(row[0])
PY
}

db_equal() {
    actual=$(db_query "$1")
    if [ "$actual" = "$2" ]; then pass "$3"; else fail "$3 expected='$2' actual='${actual:-missing}'"; fi
}

db_status_at_least_build() {
    component=$1
    status=$(db_query "SELECT status FROM observation WHERE component_id='$component'")
    case "$status" in
        build-passed|system-verified|staged|boot-tested|installed|artifact-gate-pass)
            pass "$component state=$status"
            ;;
        *)
            fail "$component is not build-ready: ${status:-missing}"
            ;;
    esac
}

check_root_layout() {
    for path in Applications System Temporary Users Volumes; do
        require_dir "/$path" "native root $path"
    done
    extras=$(find "$root" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort | grep -Ev '^(Applications|System|Temporary|Users|Volumes|lost\+found)$' || true)
    if [ -z "$extras" ]; then
        pass 'native root contains no foreign top-level paths'
    else
        fail "foreign root paths: $(printf '%s' "$extras" | tr '\n' ' ')"
    fi
    for path in bin boot dev etc home lib lib64 media mnt opt proc root run sbin srv sys tmp usr var Programs Compatibility; do
        require_absent "/$path" "native root /$path"
    done
}

check_native_layout() {
    for path in \
        /System/Compilers \
        /System/Configuration \
        /System/Drivers \
        /System/EFI/MixtarRVS \
        /System/Init \
        /System/Kernel/Linux/RT \
        /System/Libraries \
        /System/Logs \
        /System/Resources \
        /System/Runtime \
        /System/Shells \
        /System/Shells/zsh.apx \
        /System/Tools \
        /System/Userland; do
        require_dir "$path" "Mixtar path $path"
    done
    require_exec /System/Init/MixtarRVS 'runtime MixtarRVS PID1'
    require_file /System/Configuration/MixtarRVS.config 'runtime MixtarRVS configuration'
    require_file /System/Configuration/MixtarRVS.init 'runtime recovery configuration'
    require_exec /System/Shells/zsh.apx/Program/zsh 'native zsh.apx entrypoint'
    require_file /System/Shells/zsh.apx/zsh.config 'native zsh.apx SQLite config'
    require_file /System/Shells/zsh.apx/Resources/Grml/etc/zsh/zshrc 'verified Grml source in zsh.apx'
    require_exec /System/Runtime/Executor 'APX Executor'
    require_exec /System/Userland/curl 'native source downloader'
    require_file /System/Libraries/CAres/1.34.8/lib/libcares.a 'native c-ares static library'
    require_file /System/Libraries/CAres/1.34.8/include/ares.h 'native c-ares public header'
    require_file /System/Configuration/Updates/Trust/CAres-Curl-release-keyring.gpg 'c-ares/curl release keyring'
}

check_compiler_boundary() {
    forbidden=$(find "$root/System/Userland" "$root/System/Tools" -type f \( \
        -name cc -o -name c++ -o -name cpp -o -name gcc -o -name g++ -o \
        -name clang -o -name clang++ -o -name zig -o -name rustc -o -name cargo -o \
        -name make -o -name gmake -o -name cmake -o -name meson -o -name ninja -o \
        -name ld -o -name lld -o -name ar -o -name ranlib \) -print 2>/dev/null || true)
    if [ -z "$forbidden" ]; then
        pass 'no compiler or build tool exists in Userland/Tools'
    else
        fail "compiler/build tools outside /System/Compilers: $(printf '%s' "$forbidden" | tr '\n' ' ')"
    fi
    bad_settings=$(db_query "SELECT COUNT(*) FROM setting WHERE (key IN ('build.toolchain.executable','build.toolchain.cc','build.toolchain.ar','build.toolchain.ranlib','build.toolchain.ld','tool.zig','tool.make','tool.archive')) AND value NOT LIKE '/System/Compilers/%'")
    if [ "$bad_settings" = "0" ]; then pass 'build tool policy points only into /System/Compilers'; else fail "build tool settings outside /System/Compilers: $bad_settings"; fi
}

check_database() {
    require_file /System/Configuration/Updates.config 'Updates.config'
    command -v python3 >/dev/null 2>&1 || { fail 'python3 host verifier dependency missing'; return; }
    integrity=$(db_query 'PRAGMA integrity_check')
    if [ "$integrity" = "ok" ]; then pass 'Updates.config integrity'; else fail "Updates.config integrity: $integrity"; fi
    db_equal "SELECT value FROM setting WHERE key='schema.version'" 3 'Updates.config schema'
    db_equal "SELECT COUNT(*) FROM setting WHERE key='kernel.cmdline' AND value LIKE '%rdinit=/System/Init/MixtarBoot%' AND value NOT LIKE '%rdinit=/System/Init/MixtarRVS%'" 1 'kernel early-init policy selects MixtarBoot'
    db_equal "SELECT COUNT(*) FROM setting WHERE key='networking.dns.servers' AND length(trim(value))>0" 1 'native DNS policy is configured in SQLite'
    db_equal "SELECT COUNT(*) FROM component WHERE id='cares-build' AND install_target='/System/Libraries/CAres/1.34.8' AND enabled=1" 1 'c-ares library component policy'
    db_equal "SELECT COUNT(*) FROM component_dependency WHERE component_id='curl-downloader' AND dependency_id='cares-build'" 1 'curl depends on c-ares'
    db_equal "SELECT COUNT(*) FROM component_source WHERE required=1 AND (trust_anchor_id='' OR trust_anchor_id IS NULL)" 0 'all required sources have trust anchors'
    db_equal "SELECT COUNT(*) FROM component_source s JOIN component c ON c.id=s.component_id LEFT JOIN trust_anchor t ON t.id=s.trust_anchor_id WHERE c.enabled=1 AND s.required=1 AND (t.id IS NULL OR t.enabled!=1)" 0 'all required source trust anchors are enabled'
    db_equal "SELECT COUNT(*) FROM component_source WHERE lower(discovery_uri) LIKE '%mixtarrvs.com%' OR lower(artifact_uri_template) LIKE '%mixtarrvs.com%'" 0 'mixtarrvs.com is not an update repository'

    unpublished=$(db_query "SELECT COUNT(*) FROM trust_anchor WHERE id='mixtarrvs-unpublished' AND enabled=1")
    if [ "$unpublished" = "0" ]; then pass 'unpublished Mixtar trust placeholder remains disabled'; else fail 'unpublished Mixtar trust placeholder is enabled'; fi
    official_mixtar_source=$(db_query "SELECT COUNT(*) FROM component_source WHERE component_id='mixtarrvs' AND role='official-release' AND required=1 AND discovery_uri!='' AND artifact_uri_template!='' AND signature_uri_template!=''")
    if [ "$official_mixtar_source" = "1" ]; then pass 'official MixtarRVS source location is configured'; else fail 'official MixtarRVS source location is not configured'; fi
    official_mixtar_trust=$(db_query "SELECT COUNT(*) FROM component_source s JOIN trust_anchor t ON t.id=s.trust_anchor_id WHERE s.component_id='mixtarrvs' AND s.role='official-release' AND s.required=1 AND t.enabled=1 AND t.fingerprint!='OFFICIAL-SOURCE-NOT-YET-PUBLISHED'")
    if [ "$official_mixtar_trust" = "1" ]; then pass 'official MixtarRVS signing trust is configured'; else fail 'official MixtarRVS signing trust is not configured'; fi

    db_status_at_least_build zsh
    db_status_at_least_build grml-zsh-config
    openbsd_status=$(db_query "SELECT status FROM observation WHERE component_id='openbsd-userland'")
    case "$openbsd_status" in
        verified-source|build-passed|system-verified|staged|boot-tested|installed)
            pass "openbsd-userland state=$openbsd_status"
            ;;
        *)
            fail "openbsd-userland is not verified: ${openbsd_status:-missing}"
            ;;
    esac
    kernel_status=$(db_query "SELECT status FROM kernel_build_state WHERE component_id='linux-rt'")
    case "$kernel_status" in
        artifact-gate-pass|system-verified|staged|boot-tested|installed)
            pass "linux-rt artifact state=$kernel_status"
            ;;
        *)
            fail "linux-rt artifact gate has not passed: ${kernel_status:-missing}"
            ;;
    esac
}

check_trust_material() {
    if output=$(python3 - "$db" "$root" <<'PY'
import hashlib
import sqlite3
import sys
from pathlib import Path

database, root = sys.argv[1:3]
connection = sqlite3.connect(f"file:{database}?mode=ro", uri=True)
errors = []
checked = 0
for anchor, kind, fingerprint, material_uri, material_hash, local_path, expected in connection.execute(
    "SELECT DISTINCT t.id,t.kind,coalesce(t.fingerprint,''),coalesce(t.material_uri,''),"
    "coalesce(t.material_sha256,''),coalesce(t.local_path,''),coalesce(t.local_sha256,'') "
    "FROM trust_anchor t JOIN component_source s ON s.trust_anchor_id=t.id "
    "JOIN component c ON c.id=s.component_id "
    "WHERE t.enabled=1 AND s.required=1 AND c.enabled=1 ORDER BY t.id"
):
    if not local_path:
        inline_key = kind in {"manual", "signify-ed25519", "ssh-host-key"} and fingerprint
        pinned_remote_key = bool(fingerprint and material_uri and len(material_hash) == 64)
        if inline_key or pinned_remote_key:
            checked += 1
            continue
        errors.append(f"{anchor}: no pinned local material or inline key")
        continue
    path = Path(root + local_path)
    if not path.is_file() or len(expected) != 64:
        errors.append(f"{anchor}: missing material or SHA-256")
        continue
    actual = hashlib.sha256(path.read_bytes()).hexdigest()
    if actual != expected:
        errors.append(f"{anchor}: SHA-256 mismatch")
        continue
    checked += 1
connection.close()
if errors:
    print("; ".join(errors))
    raise SystemExit(1)
print(f"verified anchors={checked}")
PY
    ); then
        pass "trust material $output"
    else
        fail "trust material: $output"
    fi
}

check_static_runtime() {
    command -v file >/dev/null 2>&1 || { fail 'file host verifier dependency missing'; return; }
    for relative in \
        /System/Shells/zsh.apx/Program/zsh \
        /System/Userland/curl \
        /System/Userland/mixtar-build-executor \
        /System/Userland/updates \
        /System/Userland/updates-grml \
        /System/Userland/updates-kernel \
        /System/Userland/updates-kernel-source \
        /System/Userland/updates-mixtar \
        /System/Userland/updates-ncurses \
        /System/Userland/updates-openbsd \
        /System/Userland/updates-signature-verify; do
        if [ ! -x "$root$relative" ]; then
            fail "runtime executable missing: $relative"
            continue
        fi
        description=$(file "$root$relative")
        if printf '%s\n' "$description" | grep -q 'statically linked'; then pass "static runtime $relative"; else fail "runtime is not static: $relative"; fi
    done
    curl_version=$("$root/System/Userland/curl" --version 2>/dev/null | head -n 1 || true)
    if printf '%s\n' "$curl_version" | grep -q 'c-ares/1.34.8'; then pass 'curl uses native c-ares resolver'; else fail 'curl is missing native c-ares resolver'; fi
}

check_kernel_artifacts() {
    kernel_dirs=$(find "$root/System/Kernel/Linux/RT" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null || true)
    kernel_count=$(printf '%s\n' "$kernel_dirs" | sed '/^$/d' | wc -l)
    if [ "$kernel_count" != "1" ]; then
        fail "expected one versioned RT kernel, found $kernel_count"
        return
    fi
    kernel_version=$(printf '%s\n' "$kernel_dirs" | head -n 1)
    profile="/System/Kernel/Linux/RT/$kernel_version"
    config="$root$profile/config"
    require_file "$profile/config" 'RT kernel config'
    require_file "$profile/System.map" 'RT kernel System.map'
    require_file "$profile/build.provenance" 'RT kernel provenance'
    if grep -qx 'CONFIG_PREEMPT_RT=y' "$config"; then pass 'kernel has CONFIG_PREEMPT_RT=y'; else fail 'kernel is not PREEMPT_RT'; fi

    expected_cmdline=$(db_query "SELECT value FROM setting WHERE key='kernel.cmdline'")
    actual_cmdline=$(sed -n 's/^CONFIG_CMDLINE="\(.*\)"$/\1/p' "$config" | head -n 1)
    if [ -n "$expected_cmdline" ] && [ "$actual_cmdline" = "$expected_cmdline" ]; then
        pass 'kernel command line matches Updates.config policy'
    else
        fail 'kernel command line does not match Updates.config policy'
    fi

    initramfs=/System/Runtime/Build/MixtarRVS-initramfs.cpio
    require_file "$initramfs" 'Mixtar early initramfs'
    if ! command -v cpio >/dev/null 2>&1; then
        fail 'cpio host verifier dependency missing'
    elif cpio -it < "$root$initramfs" 2>/dev/null | grep -qx 'System/Init/MixtarBoot'; then
        pass 'initramfs contains configured MixtarBoot rdinit'
    else
        fail 'initramfs is missing configured MixtarBoot rdinit'
    fi

    efi="/System/EFI/MixtarRVS/$system_version.efi"
    require_file "$efi" 'versioned Mixtar EFI'
    if [ -s "$root$efi" ] && [ "$(dd if="$root$efi" bs=2 count=1 2>/dev/null || true)" = MZ ]; then pass 'Mixtar EFI has PE/MZ header'; else fail 'Mixtar EFI is not PE/MZ'; fi
    expected=$(awk -F= '$1=="efi_sha256" {print $2; exit}' "$root$profile/build.provenance" 2>/dev/null || true)
    actual=$(sha256sum "$root$efi" 2>/dev/null | awk '{print $1}')
    if [ -n "$expected" ] && [ "$expected" = "$actual" ]; then pass 'EFI provenance hash'; else fail 'EFI provenance hash mismatch'; fi
}

check_root_layout
check_runtime_user_config
check_native_layout
check_database
check_compiler_boundary
check_trust_material
check_static_runtime
check_kernel_artifacts

if [ "$failures" -eq 0 ]; then
    printf '%s\n' 'MIXTARRVS_COREV09_VERIFY=PASS'
    exit 0
fi

printf '%s\n' "MIXTARRVS_COREV09_VERIFY=FAIL failures=$failures" >&2
exit 1
