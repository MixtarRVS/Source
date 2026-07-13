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
    session_policy = dict(
        connection.execute(
            "SELECT key, value FROM meta WHERE key IN ("
            "'session.exec','session.shell','users.shell.default')"
        )
    )
    setting_session_policy = dict(
        connection.execute(
            "SELECT key, value FROM setting WHERE key IN ("
            "'session.exec','session.shell')"
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
expected_session_exec = "/System/Shells/zsh.apx/Program/zsh"
expected_session_policy = {
    "session.exec": expected_session_exec,
    "session.shell": expected_session_exec,
    "users.shell.default": expected_session_exec,
}
expected_setting_session_policy = {
    "session.exec": expected_session_exec,
    "session.shell": expected_session_exec,
}
if session_policy != expected_session_policy:
    raise SystemExit("meta session policy does not select the native zsh.apx entrypoint")
if setting_session_policy != expected_setting_session_policy:
    raise SystemExit("setting session policy does not select the native zsh.apx entrypoint")
if identity[1] != expected_session_exec:
    raise SystemExit("default user shell does not match the native zsh.apx entrypoint")
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

require_text() {
    if [ -f "$root$1" ] && grep -F "$2" "$root$1" >/dev/null 2>&1; then
        pass "$3"
    else
        fail "$3 missing text '$2' in $1"
    fi
}

check_zsh_configuration() {
    require_file /System/Configuration/ZSH/ZSH.config 'global ZSH SQLite configuration'
    require_file /System/Shells/zsh.apx/Resources/Configuration/.zshenv 'zsh.apx global environment'
    require_file /System/Shells/zsh.apx/Resources/Configuration/.zshrc 'zsh.apx interactive configuration'
    require_file /System/Shells/zsh.apx/Resources/Configuration/grml.zsh 'adapted Grml configuration'
    require_text /System/Shells/zsh.apx/Resources/Configuration/.zshenv \
        'export ZDOTDIR="/System/Shells/zsh.apx/Resources/Configuration"' \
        'zsh.apx exports its configuration directory'
    require_text /System/Shells/zsh.apx/Resources/Configuration/.zshenv \
        'export TMPDIR="/Temporary"' 'zsh.apx uses native temporary storage'
    require_text /System/Shells/zsh.apx/Resources/Configuration/.zshenv \
        'export TMPPREFIX="/Temporary/zsh"' 'zsh.apx here-documents use native temporary storage'
    require_text /System/Shells/zsh.apx/Resources/Configuration/.zshenv \
        'export ZSH_CACHE_DIR="/Temporary/ZSH"' 'zsh.apx cache stays outside the bundle'
    require_text /System/Shells/zsh.apx/Resources/Configuration/.zshenv \
        'export GRML_COMP_CACHE_DIR="/Temporary/ZSH"' 'Grml cache stays outside the bundle'
    require_text /System/Shells/zsh.apx/Resources/Configuration/.zshrc \
        'autoload -Uz add-zsh-hook colors compinit' 'zsh.apx enables colors and completion'
    require_text /System/Shells/zsh.apx/Resources/Configuration/.zshrc \
        'add-zsh-hook -d precmd' 'zsh.apx keeps Mixtar prompt after Grml setup'
    require_text /System/Shells/zsh.apx/Resources/Configuration/.zshrc \
        'source /System/Shells/zsh.apx/Resources/Configuration/grml.zsh' \
        'zsh.apx loads adapted Grml configuration'
    require_text /System/Shells/zsh.apx/Resources/Configuration/.zshrc \
        '%F{green}' 'zsh.apx prompt contains color policy'
    require_exec /System/Networking/start-networking 'native networking service'
    first_line=$(sed -n '1p' "$root/System/Networking/start-networking" 2>/dev/null || true)
    if [ "$first_line" = '#!/System/Shells/zsh.apx/Program/zsh' ]; then
        pass 'networking service uses native zsh.apx interpreter'
    else
        fail "networking service interpreter is invalid: ${first_line:-missing}"
    fi
    if grep -F '/System/Terminal/ZSH' "$root/System/Networking/start-networking" >/dev/null 2>&1; then
        fail 'networking service retains obsolete /System/Terminal/ZSH paths'
    else
        pass 'networking service contains no obsolete terminal paths'
    fi
    if grep -F '/dev/null' "$root/System/Networking/start-networking" >/dev/null 2>&1; then
        fail 'networking service retains foreign /dev/null path'
    else
        pass 'networking service uses native null device path'
    fi
    if command -v strings >/dev/null 2>&1 && \
       strings "$root/System/Init/MixtarRVS" | grep -Fx \
           'ZDOTDIR=/System/Shells/zsh.apx/Resources/Configuration' >/dev/null 2>&1; then
        pass 'PID1 embeds native ZDOTDIR policy'
    else
        fail 'PID1 does not embed native ZDOTDIR policy'
    fi
    if output=$(python3 - "$root" <<'PY'
import sqlite3
import sys
from pathlib import Path

root = Path(sys.argv[1])
expected = {
    "shell.path": "/System/Shells/zsh.apx/Program/zsh",
    "runtime.path": "/System/Shells/zsh.apx/Runtime",
    "path": "/System/Shells/zsh.apx/Program:/System/Userland",
    "terminfo.path": "/System/Shells/zsh.apx/Resources/Terminfo",
    "zdotdir": "/System/Shells/zsh.apx/Resources/Configuration",
    "temporary.path": "/Temporary",
    "temporary.prefix": "/Temporary/zsh",
    "cache.path": "/Temporary/ZSH",
    "grml.cache.path": "/Temporary/ZSH",
    "startup.global": "/System/Shells/zsh.apx/Resources/Configuration/.zshenv",
    "startup.interactive": "/System/Shells/zsh.apx/Resources/Configuration/.zshrc",
    "startup.grml": "/System/Shells/zsh.apx/Resources/Configuration/grml.zsh",
}
for relative in (
    "System/Configuration/ZSH/ZSH.config",
    "System/Shells/zsh.apx/zsh.config",
):
    path = root / relative
    connection = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    try:
        if connection.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
            raise RuntimeError(f"{relative}: integrity check failed")
        actual = dict(
            connection.execute(
                "SELECT key,value FROM setting WHERE key IN ("
                + ",".join("?" for _ in expected)
                + ")",
                tuple(expected),
            )
        )
    finally:
        connection.close()
    if actual != expected:
        raise RuntimeError(f"{relative}: ZSH policy mismatch: {actual}")
print("global and bundle ZSH policy agree")
PY
    ); then
        pass "ZSH SQLite policy $output"
    else
        fail "ZSH SQLite policy: $output"
    fi
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
        /System/Devices \
        /System/Drivers \
        /System/EFI/MixtarRVS \
        /System/Hardware \
        /System/Init \
        /System/Kernel/Linux/RT \
        /System/Libraries \
        /System/Logs \
        /System/Process \
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
    require_exec /System/Userland/gpgv 'native OpenPGP verifier'
    require_file /System/Configuration/TLS/cacert.pem 'pinned TLS CA bundle'
    require_file /System/Configuration/TLS/cacert.pem.sha256 'pinned TLS CA bundle sidecar'
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
    db_equal "SELECT value FROM setting WHERE key='build.sandbox.devices_source'" /System/Devices 'build sandbox uses native device path'
    db_equal "SELECT value FROM setting WHERE key='tool.sha256'" /System/Userland/mixtar-sha256 'native SHA-256 policy'
    db_equal "SELECT value FROM setting WHERE key='tool.gpgv'" /System/Userland/gpgv 'native OpenPGP verifier policy'
    sha256_tool=$(db_query "SELECT value FROM setting WHERE key='tool.sha256'")
    require_exec "$sha256_tool" 'native SHA-256 tool'
    sha256_probe=$(mktemp /tmp/mixtar-sha256-verify.XXXXXX) || {
        fail 'cannot create SHA-256 verifier input'
        sha256_probe=
    }
    if [ -n "$sha256_probe" ]; then
        printf test > "$sha256_probe"
        sha256_actual=$("$root$sha256_tool" "$sha256_probe" 2>/dev/null || true)
        rm -f -- "$sha256_probe"
        if [ "$sha256_actual" = '9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08' ]; then
            pass 'native SHA-256 known-vector gate'
        else
            fail "native SHA-256 known-vector mismatch: ${sha256_actual:-missing}"
        fi
    fi
    ca_bundle=/System/Configuration/TLS/cacert.pem
    ca_sidecar=/System/Configuration/TLS/cacert.pem.sha256
    ca_expected=$(db_query "SELECT replace(fingerprint, 'SHA256:', '') FROM trust_anchor WHERE id='curl-ca-bundle' AND enabled=1")
    ca_sidecar_expected=$(db_query "SELECT material_sha256 FROM trust_anchor WHERE id='curl-ca-bundle' AND enabled=1")
    ca_actual=$("$root$sha256_tool" "$root$ca_bundle" 2>/dev/null || true)
    ca_sidecar_actual=$("$root$sha256_tool" "$root$ca_sidecar" 2>/dev/null || true)
    ca_declared=$(tr -cs '0-9A-Fa-f' '\n' <"$root$ca_sidecar" | awk 'length($0) == 64 { print tolower($0); exit }')
    ca_certificates=$(grep -c -- 'BEGIN CERTIFICATE' "$root$ca_bundle" 2>/dev/null || true)
    if [ -n "$ca_expected" ] && [ "$ca_actual" = "$ca_expected" ]; then
        pass 'TLS CA bundle matches pinned SQLite fingerprint'
    else
        fail "TLS CA bundle hash mismatch: expected=${ca_expected:-missing} actual=${ca_actual:-missing}"
    fi
    if [ -n "$ca_sidecar_expected" ] && [ "$ca_sidecar_actual" = "$ca_sidecar_expected" ]; then
        pass 'TLS CA sidecar matches pinned SQLite material hash'
    else
        fail 'TLS CA sidecar material hash mismatch'
    fi
    if [ "$ca_declared" = "$ca_expected" ]; then
        pass 'TLS CA sidecar declares pinned bundle hash'
    else
        fail 'TLS CA sidecar does not declare pinned bundle hash'
    fi
    if [ "${ca_certificates:-0}" -gt 0 ]; then
        pass "TLS CA bundle contains certificates count=$ca_certificates"
    else
        fail 'TLS CA bundle contains no certificates'
    fi
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
    db_status_at_least_build gpgv-verifier
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
        /System/Userland/gpgv \
        /System/Userland/mixtar-sha256 \
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
check_zsh_configuration
check_database
check_compiler_boundary
check_trust_material
check_static_runtime
check_kernel_artifacts

release_version=$(db_query "SELECT value FROM setting WHERE key='system.release.current'")
if [ "$release_version" = '0.9' ]; then
    pass 'system release version 0.9'
else
    fail "system release version expected=0.9 actual=$release_version"
fi

component_version=$(db_query "SELECT installed_version FROM component WHERE id='mixtarrvs'")
if [ "$component_version" = '0.9' ]; then
    pass 'MixtarRVS core installed version 0.9'
else
    fail "MixtarRVS core installed version expected=0.9 actual=$component_version"
fi

networking_service="$root/System/Networking/start-networking"
if grep -F 'for attempt in {1..60}' "$networking_service" >/dev/null 2>&1; then
    pass 'network diagnostics cover the 5m PID1 autoreturn window'
else
    fail 'network diagnostics do not cover the 5m PID1 autoreturn window'
fi
if grep -F 'networking: autoreturn reboot' "$networking_service" >/dev/null 2>&1 ||
   grep -F '/System/Userland/reboot' "$networking_service" >/dev/null 2>&1; then
    fail 'networking service duplicates PID1 autoreturn authority'
else
    pass 'PID1 exclusively owns autoreturn reboot'
fi

networking_config="$root/System/Configuration/Networking/Networking.config"
if output=$(python3 - "$networking_config" <<'PY'
import sqlite3
import sys

connection = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
settings = dict(connection.execute(
    "SELECT key, value FROM setting WHERE key IN ("
    "'dhcp.default','wifi.wlan0.address_mode',"
    "'wifi.wlan0.static','wifi.wlan0.gateway')"
))
connection.close()
expected = {
    "dhcp.default": "1",
    "wifi.wlan0.address_mode": "dhcp",
}
if settings != expected:
    raise SystemExit(f"unexpected networking policy: {settings}")
print("wlan0=iwd-dhcp")
PY
); then
    pass "native WiFi policy $output"
else
    fail "native WiFi policy: $output"
fi
if grep -F '192.168.99.110' "$networking_service" "$networking_config" >/dev/null 2>&1; then
    fail 'obsolete physical static address remains in Mixtar networking'
else
    pass 'physical networking has no hardcoded LAN address'
fi
if grep -F 'mi_network_ready' "$networking_service" >/dev/null 2>&1 &&
   grep -F 'waiting for iwd DHCP on wlan0' "$networking_service" >/dev/null 2>&1; then
    pass 'network configuration exits on DHCP readiness'
else
    fail 'network configuration lacks DHCP readiness handling'
fi

ping_binary="$root/System/Userland/ping"
if [ "$(stat -c '%u:%g' "$ping_binary" 2>/dev/null || true)" = '0:0' ] &&
   [ "$(stat -c '%a' "$ping_binary" 2>/dev/null || true)" = '755' ]; then
    pass 'native ping ownership and mode'
else
    fail 'native ping must be root:root mode 0755'
fi
if command -v getcap >/dev/null 2>&1 &&
   getcap "$ping_binary" 2>/dev/null | grep -Eq 'cap_net_raw(\+|=)ep'; then
    pass 'native ping has only the required raw-socket capability'
else
    fail 'native ping lacks cap_net_raw=ep'
fi

sshd_service="$root/System/Networking/SSH/mixtar-sshd-service"
if strings "$sshd_service" 2>/dev/null |
   grep -F '/System/Networking/SSH/Root/dev' >/dev/null 2>&1; then
    pass 'SSH compatibility root maps native devices to private /dev'
else
    fail 'SSH compatibility root lacks private /dev mapping'
fi
if strings "$sshd_service" 2>/dev/null |
   grep -F '/System/Networking/SSH/Root/System/Shells' >/dev/null 2>&1; then
    pass 'SSH compatibility root maps native shells'
else
    fail 'SSH compatibility root lacks native shell mapping'
fi
if strings "$sshd_service" 2>/dev/null |
   grep -F '/System/Networking/SSH/Root/System/Terminal' >/dev/null 2>&1; then
    fail 'SSH compatibility root retains obsolete terminal mapping'
else
    pass 'SSH compatibility root has no obsolete terminal mapping'
fi
if strings "$sshd_service" 2>/dev/null |
   grep -F '/System/Networking/SSH/Root/System/Configuration' >/dev/null 2>&1 &&
   strings "$sshd_service" 2>/dev/null |
   grep -F '/System/Networking/SSH/Root/System/Runtime' >/dev/null 2>&1 &&
   strings "$sshd_service" 2>/dev/null |
   grep -F '/System/Networking/SSH/Root/System/Init' >/dev/null 2>&1 &&
   strings "$sshd_service" 2>/dev/null |
   grep -F '/System/Networking/SSH/Root/System/Logs' >/dev/null 2>&1; then
    pass 'SSH private root exposes native control-plane paths'
else
    fail 'SSH private root lacks native control-plane paths'
fi
if python3 - \
    "$root/System/Configuration/MixtarRVS.config" \
    "$root/System/Networking/SSH/Root/etc/passwd" \
    "$root/System/Networking/SSH/Root/etc/group" \
    "$root/System/Networking/SSH/Root/etc/shadow" \
    "$root/System/Configuration/SSH/sshd_config" <<'PY'
import pathlib
import sqlite3
import sys

config_path, passwd_path, group_path, shadow_path, sshd_path = map(
    pathlib.Path, sys.argv[1:]
)
db = sqlite3.connect(config_path)
row = db.execute("SELECT value FROM meta WHERE key='default.user'").fetchone()
db.close()
if row is None or not row[0]:
    raise SystemExit("missing default.user")
user = row[0]
shell = "/System/Shells/zsh.apx/Program/zsh"
passwd = passwd_path.read_text(encoding="utf-8").splitlines()
group = group_path.read_text(encoding="utf-8").splitlines()
shadow = shadow_path.read_text(encoding="utf-8").splitlines()
sshd = sshd_path.read_text(encoding="utf-8")
expected_user = f"{user}:x:1000:1000:{user}:/Users/{user}:{shell}"
if expected_user not in passwd:
    raise SystemExit(f"private passwd lacks configured user {user}")
if f"{user}:x:1000:" not in group:
    raise SystemExit(f"private group lacks configured user {user}")
if not any(line.startswith(f"{user}:") for line in shadow):
    raise SystemExit(f"private shadow lacks configured user {user}")
if "ChrootDirectory /Native" in sshd:
    raise SystemExit("redundant per-session /Native chroot remains enabled")
print(f"user={user}")
PY
then
    pass 'SSH private account follows MixtarRVS.config without redundant chroot'
else
    fail 'SSH private account/configuration is inconsistent'
fi

if [ "$failures" -eq 0 ]; then
    printf '%s\n' 'MIXTARRVS_COREV09_VERIFY=PASS'
    exit 0
fi

printf '%s\n' "MIXTARRVS_COREV09_VERIFY=FAIL failures=$failures" >&2
exit 1
