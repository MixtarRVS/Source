#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
    echo "usage: corev09-stage-root.sh MOUNTED_TEST_ROOT" >&2
    exit 64
fi

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(realpath "$script_dir/../../..")
root=$(realpath "$1")
base_root="$repo_root/Server/Rootfs/Generated/corev07-root"
native_root="${MIXTAR_COREV09_NATIVE_ROOT:-$repo_root/Server/Rootfs/Generated/ail-native-initramfs-root}"
inputs="${MIXTAR_COREV09_INPUTS:-$repo_root/out/server/corev09-inputs}"
openbsd_userland="$inputs/OpenBSD/7.9/Userland"
updaters="$inputs/Updaters"
compilers="$inputs/Compilers"
base_libraries="$inputs/Libraries/Base"
cares="$inputs/Libraries/CAres/1.34.8"
curl="$inputs/Userland/curl"
gpgv="$inputs/Userland/gpgv"
zsh_archive="$inputs/Shells/zsh-5.9.2.apx.tar"
source_config="$inputs/Configuration/Source.config"
ca_bundle="$inputs/Configuration/TLS/cacert.pem"
ca_bundle_sha256="$inputs/Configuration/TLS/cacert.pem.sha256"

fail() {
    echo "corev09-stage: $*" >&2
    exit 70
}

[ "$root" != "/" ] || fail "refusing to stage host root"
case "$root" in
    "$repo_root"/out/server/*|/var/tmp/*|/tmp/*) ;;
    *) fail "test root is outside an approved staging location: $root" ;;
esac
[ -d "$root/System" ] || fail "target is not a Mixtar test root: $root"
[ -d "$base_root/System" ] || fail "base root is unavailable"

for required in \
    "$openbsd_userland" \
    "$updaters" \
    "$compilers" \
    "$base_libraries" \
    "$cares/lib/libcares.a" \
    "$cares/include/ares.h" \
    "$curl" \
    "$gpgv" \
    "$zsh_archive" \
    "$source_config" \
    "$ca_bundle" \
    "$ca_bundle_sha256" \
    "$updaters/mixtar-sha256" \
    "$native_root/System/Init/MixtarRVS" \
    "$native_root/System/Networking/start-networking" \
    "$native_root/System/Networking/Core/mixtar-devices" \
    "$native_root/System/Networking/WiFi/mixtar-wifi-service" \
    "$repo_root/Server/Updates/Schema/Updates.schema.sql" \
    "$repo_root/Server/Updates/Schema/Updates.seed.sql" \
    "$repo_root/Server/Updates/Trust/MixtarRVS-release-keyring.gpg"
do
    [ -e "$required" ] || fail "missing build input: $required"
done

copy_tree() {
    source_path=$1
    destination_path=$2
    [ -d "$source_path" ] || return 0
    mkdir -p "$destination_path"
    cp -a "$source_path/." "$destination_path/"
}

mkdir -p \
    "$root/Applications" \
    "$root/System" \
    "$root/System/Devices" \
    "$root/System/Hardware" \
    "$root/System/Process" \
    "$root/Temporary" \
    "$root/Users" \
    "$root/Volumes"

for system_part in Init Drivers EFI Kernel Logs Networking Resources Runtime Security Tools; do
    copy_tree "$base_root/System/$system_part" "$root/System/$system_part"
done
copy_tree "$base_root/System/Configuration" "$root/System/Configuration"
mkdir -p "$root/System/Configuration/TLS"
install -m 0644 "$ca_bundle" "$root/System/Configuration/TLS/cacert.pem"
install -m 0644 "$ca_bundle_sha256" \
    "$root/System/Configuration/TLS/cacert.pem.sha256"
copy_tree "$native_root/System/Networking" "$root/System/Networking"
install -m 0755 "$native_root/System/Init/MixtarRVS" "$root/System/Init/MixtarRVS"
install -m 0755 "$native_root/System/Networking/start-networking" \
    "$root/System/Networking/start-networking"

python3 - "$root" <<'PY'
import pathlib
import sqlite3
import sys

root = pathlib.Path(sys.argv[1])
policies = {
    root / "System/Configuration/Networking/Networking.config": {
        "dhcp.default": "1",
        "wifi.wlan0.address_mode": "dhcp",
    },
    root / "System/Configuration/Networking/WiFi.config": {
        "wifi.wlan0.address_mode": "dhcp",
    },
}
obsolete = {
    "networking.address",
    "networking.gateway",
    "wifi.address",
}
for path, settings in policies.items():
    db = sqlite3.connect(path)
    try:
        db.execute(
            "CREATE TABLE IF NOT EXISTS setting("
            "key TEXT PRIMARY KEY, value TEXT NOT NULL)"
        )
        db.executemany(
            "INSERT INTO setting(key, value) VALUES (?, ?) "
            "ON CONFLICT(key) DO UPDATE SET value=excluded.value",
            settings.items(),
        )
        has_meta = db.execute(
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name='meta'"
        ).fetchone()
        if has_meta:
            db.executemany(
                "DELETE FROM meta WHERE key=?",
                ((key,) for key in obsolete),
            )
        db.commit()
        db.execute("VACUUM")
        if db.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
            raise RuntimeError(f"invalid networking database: {path}")
    finally:
        db.close()
PY

rm -rf -- "$root/System/UI"
find "$root/Applications" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +

if [ "${MIXTAR_COREV09_REUSE_COMPILERS:-0}" = "1" ]; then
    find "$compilers" -type f -print | while IFS= read -r compiler_file; do
        compiler_relative=${compiler_file#"$compilers"/}
        [ -f "$root/System/Compilers/$compiler_relative" ] || exit 1
    done || fail "existing compiler closure is incomplete"
    for compiler_path in \
        Zig/0.16.0/zig \
        GNU/4.4.1/bin/gmake \
        BSDTar/3.8.8/bin/bsdtar \
        XZ/5.8.3/bin/xz \
        minisign/0.12/minisign
    do
        cmp "$compilers/$compiler_path" "$root/System/Compilers/$compiler_path" >/dev/null || \
            fail "existing compiler closure differs: $compiler_path"
    done
else
    rm -rf -- "$root/System/Compilers"
    copy_tree "$compilers" "$root/System/Compilers"
fi

rm -rf -- "$root/System/Libraries"
copy_tree "$base_libraries" "$root/System/Libraries"
copy_tree "$cares" "$root/System/Libraries/CAres/1.34.8"
rm -rf -- "$root/System/Libraries/Zig"

rm -rf -- "$root/System/Userland"
mkdir -p "$root/System/Userland"
copy_tree "$openbsd_userland" "$root/System/Userland"
mkdir -p "$root/System/Compilers/OpenBSD/7.9/bin"
for tool in lex m4 nm pkgconf rpcgen yacc; do
    if [ -f "$root/System/Userland/$tool" ]; then
        mv "$root/System/Userland/$tool" "$root/System/Compilers/OpenBSD/7.9/bin/$tool"
    fi
done
copy_tree "$updaters" "$root/System/Userland"
install -m 0755 "$curl" "$root/System/Userland/curl"
install -m 0755 "$gpgv" "$root/System/Userland/gpgv"

for helper in admin exit-admin network security system; do
    if [ -f "$base_root/System/Userland/$helper" ]; then
        install -m 0755 "$base_root/System/Userland/$helper" "$root/System/Userland/$helper"
    fi
done
for helper in reboot poweroff; do
    native_helper="$native_root/System/Terminal/ZSH/$helper"
    [ -x "$native_helper" ] || fail "missing native lifecycle helper: $native_helper"
    install -m 0755 "$native_helper" "$root/System/Userland/$helper"
done

command -v setcap >/dev/null 2>&1 || fail "setcap is required to stage native ping capability"
chown -R 0:0 "$root/System/Userland"
chmod -R go-w "$root/System/Userland"
[ -x "$root/System/Userland/ping" ] || fail "OpenBSD ping is missing from native userland"
chmod 0755 "$root/System/Userland/ping"
setcap cap_net_raw=ep "$root/System/Userland/ping"

rm -rf -- "$root/System/Shells"
mkdir -p "$root/System/Shells"
tar -xf "$zsh_archive" -C "$root/System/Shells"
[ -x "$root/System/Shells/zsh.apx/Program/zsh" ] || fail "zsh.apx entrypoint is missing"
[ -f "$root/System/Shells/zsh.apx/zsh.config" ] || fail "zsh.apx config is missing"
[ -f "$root/System/Shells/zsh.apx/Resources/Grml/etc/zsh/zshrc" ] || fail "Grml zshrc is missing"

for script_scope in "$root/System/Userland" "$root/System/Networking"; do
    [ -d "$script_scope" ] || continue
    grep -Ilr '^#!/System/Shells/zsh$' "$script_scope" 2>/dev/null | while IFS= read -r script; do
        sed -i '1s|^#!/System/Shells/zsh$|#!/System/Shells/zsh.apx/Program/zsh|' "$script"
    done
done

updates_dir="$root/System/Configuration/Updates"
rm -rf -- "$updates_dir"
mkdir -p "$updates_dir/Trust" "$updates_dir/Recipes" "$updates_dir/Schema"
copy_tree "$repo_root/Server/Updates/Trust" "$updates_dir/Trust"
copy_tree "$repo_root/Server/Updates/Recipes" "$updates_dir/Recipes"
copy_tree "$repo_root/Server/Updates/Schema" "$updates_dir/Schema"
install -m 0644 "$source_config" "$root/System/Configuration/Source.config"

updates_db="$root/System/Configuration/Updates.config"
updates_tmp="$updates_db.tmp.$$"
rm -f -- "$updates_tmp"
"$root/System/Userland/updates-config-builder" build \
    "$repo_root/Server/Updates/Schema/Updates.schema.sql" \
    "$repo_root/Server/Updates/Schema/Updates.seed.sql" \
    "$updates_tmp"
"$root/System/Userland/updates" audit "$updates_tmp"
mv "$updates_tmp" "$updates_db"
chmod 0644 "$updates_db"

kernel_stage=${MIXTAR_COREV09_KERNEL_STAGE:-"$repo_root/out/server/kernel-stage-0.9"}
kernel_state_db=${MIXTAR_COREV09_KERNEL_DB:-"$repo_root/out/server/Updates.config.0.9-kernel-build"}
initramfs_input=${MIXTAR_COREV09_INITRAMFS:-"$repo_root/Server/Rootfs/Generated/mixtar-boot-initramfs.cpio"}

kernel_stage=$(realpath "$kernel_stage")
kernel_state_db=$(realpath "$kernel_state_db")
initramfs_input=$(realpath "$initramfs_input")
case "$kernel_stage" in
    "$repo_root"/out/server/*) ;;
    *) fail "kernel stage must remain under out/server" ;;
esac
case "$kernel_state_db" in
    "$repo_root"/out/server/*) ;;
    *) fail "kernel state database must remain under out/server" ;;
esac
case "$initramfs_input" in
    "$repo_root"/out/server/*|"$repo_root"/Server/Rootfs/Generated/mixtar-boot-initramfs.cpio) ;;
    *) fail "initramfs input is outside approved Mixtar build locations" ;;
esac

kernel_versions=$(find "$kernel_stage/System/Kernel/Linux/RT" \
    -mindepth 1 -maxdepth 1 -type d -printf '%f\n')
kernel_count=$(printf '%s\n' "$kernel_versions" | sed '/^$/d' | wc -l)
[ "$kernel_count" -eq 1 ] || fail "kernel stage must contain exactly one RT version"
kernel_version=$(printf '%s\n' "$kernel_versions" | head -n 1)
kernel_profile_source="$kernel_stage/System/Kernel/Linux/RT/$kernel_version"

efi_files=$(find "$kernel_stage/System/EFI/MixtarRVS" \
    -mindepth 1 -maxdepth 1 -type f -name '*.efi' -printf '%f\n')
efi_count=$(printf '%s\n' "$efi_files" | sed '/^$/d' | wc -l)
[ "$efi_count" -eq 1 ] || fail "kernel stage must contain exactly one Mixtar EFI"
efi_name=$(printf '%s\n' "$efi_files" | head -n 1)
system_release=${efi_name%.efi}
efi_source="$kernel_stage/System/EFI/MixtarRVS/$efi_name"

for required in \
    "$kernel_profile_source/config" \
    "$kernel_profile_source/System.map" \
    "$kernel_profile_source/build.provenance" \
    "$efi_source" \
    "$kernel_state_db" \
    "$initramfs_input"
do
    [ -s "$required" ] || fail "missing kernel artifact: $required"
done
[ -d "$kernel_profile_source/modules" ] || fail "kernel modules are missing"
[ -z "$(find "$kernel_stage" -type l -print -quit)" ] || fail "kernel stage contains external links"

rm -rf -- "$root/System/Kernel/Linux/RT"
mkdir -p "$root/System/Kernel/Linux/RT/$kernel_version"
cp -a -- "$kernel_profile_source/." "$root/System/Kernel/Linux/RT/$kernel_version/"
rm -rf -- "$root/System/EFI/MixtarRVS"
mkdir -p "$root/System/EFI/MixtarRVS"
install -m 0644 "$efi_source" "$root/System/EFI/MixtarRVS/$efi_name"
mkdir -p "$root/System/Runtime/Build"
install -m 0644 "$initramfs_input" \
    "$root/System/Runtime/Build/MixtarRVS-initramfs.cpio"

python3 - "$root" <<'PY'
import pathlib
import shlex
import sqlite3
import sys
import time

root = pathlib.Path(sys.argv[1])
config = root / "System/Configuration/MixtarRVS.config"
db = sqlite3.connect(config)
try:
    db.execute("CREATE TABLE IF NOT EXISTS setting(key TEXT PRIMARY KEY, value TEXT NOT NULL)")
    values = {
        "session.exec": "/System/Shells/zsh.apx/Program/zsh",
        "session.shell": "/System/Shells/zsh.apx/Program/zsh",
        "updates.config": "/System/Configuration/Updates.config",
        "source.config": "/System/Configuration/Source.config",
        "system.version": "0.9",
    }
    db.executemany(
        "INSERT INTO setting(key, value) VALUES (?, ?) "
        "ON CONFLICT(key) DO UPDATE SET value=excluded.value",
        values.items(),
    )

    db.execute(
        "CREATE TABLE IF NOT EXISTS meta("
        "key TEXT PRIMARY KEY, value TEXT NOT NULL)"
    )
    default_user_row = db.execute(
        "SELECT value FROM meta WHERE key='default.user'"
    ).fetchone()
    if default_user_row is not None and default_user_row[0]:
        default_user = default_user_row[0]
    else:
        default_user_row = db.execute(
            "SELECT name FROM user WHERE uid > 0 ORDER BY uid LIMIT 1"
        ).fetchone()
        if default_user_row is None or not default_user_row[0]:
            raise SystemExit("MixtarRVS.config has no non-root default user")
        default_user = default_user_row[0]

    meta_values = {
        "default.user": default_user,
        "session.exec": "/System/Shells/zsh.apx/Program/zsh",
        "session.shell": "/System/Shells/zsh.apx/Program/zsh",
        "users.home.root": "/Users",
        "users.shell.default": "/System/Shells/zsh.apx/Program/zsh",
        "users.uid.minimum": "1000",
        "users.gid.strategy": "uid",
        "console.setup": "/System/Init/ConsoleSetup",
        "console.keymap": "pl",
        "locale.name": "C.UTF-8",
        "networking.ping.group_range.path": "/System/Process/sys/net/ipv4/ping_group_range",
        "networking.ping.gid.min": "0",
        "networking.ping.gid.max": "1000",
    }
    db.executemany(
        "INSERT INTO meta(key, value) VALUES (?, ?) "
        "ON CONFLICT(key) DO UPDATE SET value=excluded.value",
        meta_values.items(),
    )
    db.execute(
        "UPDATE user SET shell=? WHERE name=?",
        ("/System/Shells/zsh.apx/Program/zsh", default_user),
    )

    zsh_bundle = root / "System/Shells/zsh.apx"
    zsh_configuration = zsh_bundle / "Resources/Configuration"
    zsh_configuration.mkdir(parents=True, exist_ok=True)
    zsh_settings = {
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
        "history.file": "${HOME}/.zsh_history",
        "prompt": "%F{green}${USER:-User}@${MIXTAR_SYSTEM_NAME:-MixtarRVS}%f:%F{blue}%~%f> ",
        "locale": "C.UTF-8",
        "keyboard.layout": "pl",
    }
    for zsh_database in (
        root / "System/Configuration/ZSH/ZSH.config",
        zsh_bundle / "zsh.config",
    ):
        zsh_database.parent.mkdir(parents=True, exist_ok=True)
        zsh_db = sqlite3.connect(zsh_database)
        try:
            zsh_db.execute(
                "CREATE TABLE IF NOT EXISTS setting("
                "key TEXT PRIMARY KEY, value TEXT NOT NULL)"
            )
            zsh_db.executemany(
                "INSERT INTO setting(key, value) VALUES (?, ?) "
                "ON CONFLICT(key) DO UPDATE SET value=excluded.value",
                zsh_settings.items(),
            )
            zsh_db.commit()
            if zsh_db.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
                raise RuntimeError(f"invalid ZSH database: {zsh_database}")
        finally:
            zsh_db.close()

    grml_source = zsh_bundle / "Resources/Grml/etc/zsh/zshrc"
    if not grml_source.is_file():
        raise SystemExit("verified Grml zshrc is missing from zsh.apx")
    grml_text = grml_source.read_text(encoding="utf-8", errors="surrogateescape")
    for old, new in (
        ("/dev/null", "/System/Devices/null"),
        ("/usr/share/grml/zsh", "/System/Shells/zsh.apx/Resources/Grml/usr_share_grml/zsh"),
        ("/etc/grml", "/System/Shells/zsh.apx/Resources/Grml/etc/grml"),
        ("/etc/zsh", "/System/Shells/zsh.apx/Resources/Grml/etc/zsh"),
        ("/tmp/", "/Temporary/"),
    ):
        grml_text = grml_text.replace(old, new)
    (zsh_configuration / "grml.zsh").write_text(
        grml_text,
        encoding="utf-8",
        errors="surrogateescape",
    )

    zshenv_lines = (
        f'export PATH="{zsh_settings["path"]}"',
        f'export TERMINFO="{zsh_settings["terminfo.path"]}"',
        f'export ZDOTDIR="{zsh_settings["zdotdir"]}"',
        f'export TMPDIR="{zsh_settings["temporary.path"]}"',
        f'export TMPPREFIX="{zsh_settings["temporary.prefix"]}"',
        f'export ZSH_CACHE_DIR="{zsh_settings["cache.path"]}"',
        f'export ZSH_COMPDUMP="{zsh_settings["cache.path"]}/.zcompdump"',
        f'export GRML_COMP_CACHE_DIR="{zsh_settings["grml.cache.path"]}"',
        'export TERM="${TERM:-linux}"',
        'export LANG="${LANG:-C.UTF-8}"',
        'export LC_CTYPE="${LC_CTYPE:-C.UTF-8}"',
        'export MIXTAR_SYSTEM_NAME="${MIXTAR_SYSTEM_NAME:-MixtarRVS}"',
    )
    (zsh_configuration / ".zshenv").write_text(
        "\n".join(zshenv_lines) + "\n",
        encoding="utf-8",
    )
    prompt = shlex.quote(zsh_settings["prompt"])
    zshrc_lines = (
        'if [[ -n ${MIXTAR_GLOBAL_ZSHRC_LOADED:-} ]]; then return; fi',
        'typeset -g MIXTAR_GLOBAL_ZSHRC_LOADED=1',
        '[[ -d $ZSH_CACHE_DIR ]] || mkdir -p -- "$ZSH_CACHE_DIR"',
        'fpath=(/System/Shells/zsh.apx/Resources/Functions $fpath)',
        'if [[ -r /System/Shells/zsh.apx/Resources/Configuration/grml.zsh ]]; then',
        '  source /System/Shells/zsh.apx/Resources/Configuration/grml.zsh',
        'fi',
        'autoload -Uz add-zsh-hook colors compinit',
        'for mixtar_prompt_hook in prompt_grml_precmd prompt_grml-chroot_precmd prompt_grml-large_precmd; do',
        '  add-zsh-hook -d precmd "$mixtar_prompt_hook" 2>/System/Devices/null',
        'done',
        'unset mixtar_prompt_hook',
        'colors',
        'compinit -D',
        'bindkey -e',
        'KEYTIMEOUT=5',
        "bindkey '^?' backward-delete-char",
        "bindkey '^H' backward-delete-char",
        "bindkey '^[[3~' delete-char",
        "bindkey '^[[A' up-line-or-history",
        "bindkey '^[[B' down-line-or-history",
        "bindkey '^[[C' forward-char",
        "bindkey '^[[D' backward-char",
        'setopt PROMPT_SUBST AUTO_CD AUTO_LIST AUTO_MENU COMPLETE_IN_WORD',
        'setopt HIST_IGNORE_DUPS HIST_REDUCE_BLANKS INC_APPEND_HISTORY',
        'HISTFILE="${HOME}/.zsh_history"',
        'HISTSIZE=10000',
        'SAVEHIST=10000',
        f'PROMPT={prompt}',
    )
    (zsh_configuration / ".zshrc").write_text(
        "\n".join(zshrc_lines) + "\n",
        encoding="utf-8",
    )
    for generated_startup in zsh_configuration.iterdir():
        generated_startup.chmod(0o644)

    updates_db = sqlite3.connect(
        root / "System/Configuration/Updates.config"
    )
    checked_at_ms = int(time.time() * 1000)
    completed_components = (
        (
            "zsh",
            "build-passed",
            "source-built static musl APX staged and executable",
        ),
        (
            "grml-zsh-config",
            "build-passed",
            "verified Grml configuration staged inside zsh.apx",
        ),
        (
            "openbsd-userland",
            "build-passed",
            "OpenBSD-first source bridge output staged under /System/Userland",
        ),
        (
            "gpgv-verifier",
            "build-passed",
            "source-built static musl OpenPGP verifier staged under /System/Userland",
        ),
    )
    for component_id, status, detail in completed_components:
        source = updates_db.execute(
            "SELECT c.installed_version, c.install_target, s.discovery_uri, "
            "s.signature_uri_template, coalesce(t.local_path, '') "
            "FROM component c "
            "JOIN component_source s ON s.component_id=c.id "
            "LEFT JOIN trust_anchor t ON t.id=s.trust_anchor_id "
            "WHERE c.id=? ORDER BY s.required DESC, s.role LIMIT 1",
            (component_id,),
        ).fetchone()
        if source is None:
            raise SystemExit(f"Updates.config has no source for {component_id}")
        version, install_target, source_uri, signature_uri, trust_path = source
        updates_db.execute(
            "INSERT INTO observation("
            "component_id, available_version, status, source_uri, signature_uri, "
            "source_path, signature_path, trust_path, detail, checked_at_ms) "
            "VALUES (?, ?, ?, ?, ?, ?, '', ?, ?, ?) "
            "ON CONFLICT(component_id) DO UPDATE SET "
            "available_version=excluded.available_version, "
            "status=excluded.status, source_uri=excluded.source_uri, "
            "signature_uri=excluded.signature_uri, source_path=excluded.source_path, "
            "signature_path=excluded.signature_path, trust_path=excluded.trust_path, "
            "detail=excluded.detail, checked_at_ms=excluded.checked_at_ms",
            (
                component_id,
                version,
                status,
                source_uri,
                signature_uri,
                install_target,
                trust_path,
                detail,
                checked_at_ms,
            ),
        )
    updates_db.commit()
    if updates_db.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
        raise SystemExit("Updates.config integrity check failed")
    updates_db.close()

    db.commit()
    if db.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
        raise SystemExit("MixtarRVS.config integrity check failed")
finally:
    db.close()

for path in (
    root / "System/Configuration/Updates.config",
    root / "System/Configuration/Source.config",
    root / "System/Shells/zsh.apx/zsh.config",
):
    db = sqlite3.connect(path)
    try:
        if db.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
            raise SystemExit(f"SQLite integrity check failed: {path}")
    finally:
        db.close()
PY

python3 - "$updates_db" "$kernel_state_db" "$root" \
    "$kernel_version" "$system_release" <<'PY'
import hashlib
import pathlib
import sqlite3
import sys

target_path, source_path, root_path, version, release = sys.argv[1:]
root = pathlib.Path(root_path)
profile = f"/System/Kernel/Linux/RT/{version}"
efi = f"/System/EFI/MixtarRVS/{release}.efi"
runtime_work = "/Temporary/Updates/kernel/build"
runtime_source = f"{runtime_work}/src/linux-{version}"
runtime_build = f"{runtime_work}/build/linux-{version}"

source = sqlite3.connect(f"file:{source_path}?mode=ro", uri=True)
try:
    if source.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
        raise SystemExit("kernel state database integrity check failed")
    state = source.execute(
        "SELECT kernel_version, system_release, status, efi_sha256 "
        "FROM kernel_build_state WHERE component_id='linux-rt'"
    ).fetchone()
    if state is None or state[:3] != (version, release, "artifact-gate-pass"):
        raise SystemExit("kernel state database has not passed its artifact gate")
    expected_efi_hash = state[3]
finally:
    source.close()

actual_efi_hash = hashlib.sha256((root / efi.removeprefix("/")).read_bytes()).hexdigest()
if actual_efi_hash != expected_efi_hash:
    raise SystemExit("staged EFI does not match the artifact-gate database")

target = sqlite3.connect(target_path)
try:
    target.execute("ATTACH DATABASE ? AS kernel_source", (source_path,))
    for table in (
        "observation",
        "kernel_observation",
        "kernel_build_gate",
        "kernel_build_state",
        "kernel_patch_approval",
    ):
        columns = [
            row[1] for row in target.execute(f"PRAGMA main.table_info({table})")
        ]
        source_columns = [
            row[1]
            for row in target.execute(f"PRAGMA kernel_source.table_info({table})")
        ]
        if not columns or columns != source_columns:
            raise SystemExit(f"kernel state schema mismatch: {table}")
        column_list = ",".join(columns)
        target.execute(
            f"INSERT OR REPLACE INTO {table} ({column_list}) "
            f"SELECT {column_list} FROM kernel_source.{table} "
            "WHERE component_id='linux-rt'"
        )

    target.execute(
        "UPDATE observation SET status='artifact-gate-pass', source_path=?, "
        "signature_path='', trust_path=?, detail=? WHERE component_id='linux-rt'",
        (
            profile,
            "/System/Configuration/Updates/Trust/Kernel-release-keyring.gpg",
            "verified Linux source built as the installed MixtarRVS RT kernel",
        ),
    )
    target.execute(
        "UPDATE kernel_observation SET stable_source_path='', "
        "stable_signature_path='', rt_patch_path='', rt_signature_path='', "
        "trust_path=?, status='verified-source' WHERE component_id='linux-rt'",
        ("/System/Configuration/Updates/Trust/Kernel-release-keyring.gpg",),
    )
    target.execute(
        "UPDATE kernel_build_gate SET source_root=?, config_path=?, "
        "status='build-gate-pass' WHERE component_id='linux-rt'",
        (runtime_source, f"{profile}/config"),
    )
    target.execute(
        "UPDATE kernel_build_state SET work_root=?, source_root=?, build_root=?, "
        "config_fragment_path='/System/Configuration/Kernel/RT.config', "
        "initramfs_path='/System/Runtime/Build/MixtarRVS-initramfs.cpio', "
        "firmware_root='/System/Kernel/Firmware', kernel_config_path=?, "
        "staged_kernel_root=?, staged_efi_path=?, status='artifact-gate-pass' "
        "WHERE component_id='linux-rt'",
        (runtime_work, runtime_source, runtime_build, f"{profile}/config", profile, efi),
    )
    target.commit()
    if target.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
        raise SystemExit("Updates.config failed after kernel state import")
finally:
    target.close()
PY

if [ -f "$root/System/Configuration/MixtarRVS.init" ]; then
    sed -i 's#/System/Shells/zsh#/System/Shells/zsh.apx/Program/zsh#g' \
        "$root/System/Configuration/MixtarRVS.init"
fi
if [ -f "$root/System/Configuration/SSH/sshd_config" ]; then
    sed -i 's#/System/Shells/zsh#/System/Shells/zsh.apx/Program/zsh#g' \
        "$root/System/Configuration/SSH/sshd_config"
fi
if [ -f "$root/System/Networking/SSH/Root/etc/passwd" ]; then
    sed -i 's#/System/Shells/zsh#/System/Shells/zsh.apx/Program/zsh#g' \
        "$root/System/Networking/SSH/Root/etc/passwd"
fi
networking_service="$root/System/Networking/start-networking"
if [ -f "$networking_service" ]; then
    sed -i \
        -e 's#/System/Terminal/ZSH/zsh#/System/Shells/zsh.apx/Program/zsh#g' \
        -e 's#/System/Terminal/ZSH/Runtime#/System/Shells/zsh.apx/Runtime#g' \
        -e 's#/System/Terminal/ZSH#/System/Shells/zsh.apx/Program#g' \
        -e '1s|^#!/System/Shells/zsh$|#!/System/Shells/zsh.apx/Program/zsh|' \
        "$networking_service"
    chmod 0755 "$networking_service"
fi

find "$root/System/Userland" "$root/System/Tools" -type f \( \
    -name cc -o -name c++ -o -name cpp -o -name gcc -o -name g++ -o \
    -name clang -o -name clang++ -o -name zig -o -name rustc -o -name cargo -o \
    -name make -o -name gmake -o -name cmake -o -name meson -o -name ninja -o \
    -name ld -o -name lld -o -name ar -o -name ranlib \) -print | \
    grep . && fail "compiler leaked outside /System/Compilers" || true

find "$root" -xdev \( \
    -type d \( -iname mddm -o -iname mdm \) -o \
    -type f \( -iname mddm -o -iname 'mddm.*' -o -iname mdm -o -iname 'mdm.*' \) \
    \) -print | \
    grep . && fail "UI/display-manager artifact leaked into CoreV09" || true

cat >"$root/System/Configuration/CoreV09.manifest" <<EOF
version=0.9
root_model=native-mixtar
userland=OpenBSD-7.9-musl
shell=zsh-5.9.2-apx-musl
updates=AILang-musl-static
compiler_root=/System/Compilers
ui=absent
activation=disabled
EOF

echo "CORE_V09_STAGE_ROOT=$root"
echo "CORE_V09_STAGE_GATE=PASS"
