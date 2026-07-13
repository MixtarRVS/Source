PRAGMA foreign_keys = ON;
PRAGMA journal_mode = DELETE;
PRAGMA synchronous = FULL;
BEGIN IMMEDIATE;

DROP TABLE IF EXISTS update_transaction;
DROP TABLE IF EXISTS observation;
DROP TABLE IF EXISTS component_dependency;
DROP TABLE IF EXISTS component_source;
DROP TABLE IF EXISTS component;
DROP TABLE IF EXISTS trust_signer;
DROP TABLE IF EXISTS trust_anchor;
DROP TABLE IF EXISTS setting;

CREATE TABLE setting (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
) STRICT;

CREATE TABLE trust_anchor (
    id TEXT PRIMARY KEY,
    owner TEXT NOT NULL,
    kind TEXT NOT NULL CHECK (kind IN (
        'openpgp',
        'ssh-host-key',
        'signify-ed25519',
        'manual'
    )),
    fingerprint TEXT NOT NULL,
    material_uri TEXT NOT NULL,
    material_sha256 TEXT NOT NULL,
    local_path TEXT NOT NULL DEFAULT '',
    local_sha256 TEXT NOT NULL DEFAULT '',
    enabled INTEGER NOT NULL CHECK (enabled IN (0, 1))
) STRICT;

CREATE TABLE trust_signer (
    trust_anchor_id TEXT NOT NULL REFERENCES trust_anchor(id) ON DELETE CASCADE,
    fingerprint TEXT NOT NULL,
    enabled INTEGER NOT NULL CHECK (enabled IN (0, 1)),
    PRIMARY KEY (trust_anchor_id, fingerprint)
) STRICT;

CREATE TABLE component (
    id TEXT PRIMARY KEY,
    display_name TEXT NOT NULL,
    installed_version TEXT NOT NULL,
    channel TEXT NOT NULL,
    recipe TEXT NOT NULL,
    install_target TEXT NOT NULL,
    boot_target TEXT NOT NULL,
    enabled INTEGER NOT NULL CHECK (enabled IN (0, 1)),
    auto_install INTEGER NOT NULL CHECK (auto_install IN (0, 1))
) STRICT;

CREATE TABLE component_source (
    component_id TEXT NOT NULL REFERENCES component(id) ON DELETE CASCADE,
    role TEXT NOT NULL,
    discovery_kind TEXT NOT NULL,
    discovery_uri TEXT NOT NULL,
    artifact_uri_template TEXT NOT NULL,
    signature_uri_template TEXT NOT NULL,
    verification_kind TEXT NOT NULL,
    trust_anchor_id TEXT NOT NULL REFERENCES trust_anchor(id),
    required INTEGER NOT NULL CHECK (required IN (0, 1)),
    PRIMARY KEY (component_id, role)
) STRICT;

CREATE TABLE component_dependency (
    component_id TEXT NOT NULL REFERENCES component(id) ON DELETE CASCADE,
    dependency_id TEXT NOT NULL REFERENCES component(id),
    PRIMARY KEY (component_id, dependency_id),
    CHECK (component_id <> dependency_id)
) STRICT;

CREATE TABLE observation (
    component_id TEXT PRIMARY KEY REFERENCES component(id) ON DELETE CASCADE,
    available_version TEXT NOT NULL,
    status TEXT NOT NULL,
    source_uri TEXT NOT NULL,
    signature_uri TEXT NOT NULL,
    source_path TEXT NOT NULL,
    signature_path TEXT NOT NULL,
    trust_path TEXT NOT NULL,
    detail TEXT NOT NULL,
    checked_at_ms INTEGER NOT NULL
) STRICT;

CREATE TABLE update_transaction (
    id INTEGER PRIMARY KEY,
    component_id TEXT NOT NULL REFERENCES component(id),
    version TEXT NOT NULL,
    state TEXT NOT NULL,
    source_sha256 TEXT NOT NULL,
    build_sha256 TEXT NOT NULL,
    started_at_ms INTEGER NOT NULL,
    finished_at_ms INTEGER NOT NULL,
    detail TEXT NOT NULL
) STRICT;

CREATE TABLE kernel_required_symbol (
    component_id TEXT NOT NULL REFERENCES component(id) ON DELETE CASCADE,
    symbol TEXT NOT NULL,
    role TEXT NOT NULL CHECK (role IN (
        'boot',
        'storage',
        'filesystem',
        'network',
        'display',
        'input',
        'realtime',
        'security'
    )),
    required INTEGER NOT NULL CHECK (required IN (0, 1)),
    PRIMARY KEY (component_id, symbol)
) STRICT;

CREATE TABLE kernel_patch_approval (
    component_id TEXT NOT NULL REFERENCES component(id) ON DELETE CASCADE,
    kernel_version TEXT NOT NULL,
    symbol TEXT NOT NULL,
    patch_sha256 TEXT NOT NULL,
    patch_path TEXT NOT NULL DEFAULT '',
    approved INTEGER NOT NULL CHECK (approved IN (0, 1)),
    reason TEXT NOT NULL,
    PRIMARY KEY (component_id, kernel_version, symbol, patch_sha256)
) STRICT;

CREATE TABLE IF NOT EXISTS kernel_observation (
    component_id TEXT PRIMARY KEY REFERENCES component(id),
    stable_version TEXT NOT NULL,
    stable_source_uri TEXT NOT NULL,
    stable_signature_uri TEXT NOT NULL,
    rt_version TEXT NOT NULL,
    rt_patch_uri TEXT NOT NULL,
    rt_signature_uri TEXT NOT NULL,
    stable_source_path TEXT NOT NULL DEFAULT '',
    stable_signature_path TEXT NOT NULL DEFAULT '',
    rt_patch_path TEXT NOT NULL DEFAULT '',
    rt_signature_path TEXT NOT NULL DEFAULT '',
    trust_path TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL,
    detail TEXT NOT NULL,
    checked_at_ms INTEGER NOT NULL,
    verified_at_ms INTEGER NOT NULL DEFAULT 0
) WITHOUT ROWID;

CREATE TABLE IF NOT EXISTS kernel_build_gate (
    component_id TEXT PRIMARY KEY REFERENCES component(id),
    kernel_version TEXT NOT NULL,
    source_root TEXT NOT NULL,
    config_path TEXT NOT NULL,
    required_count INTEGER NOT NULL,
    conflict_count INTEGER NOT NULL,
    approved_conflict_count INTEGER NOT NULL,
    status TEXT NOT NULL,
    detail TEXT NOT NULL,
    checked_at_ms INTEGER NOT NULL
) WITHOUT ROWID;

CREATE TABLE IF NOT EXISTS kernel_build_state (
    component_id TEXT PRIMARY KEY REFERENCES component(id),
    kernel_version TEXT NOT NULL,
    system_release TEXT NOT NULL,
    work_root TEXT NOT NULL,
    source_root TEXT NOT NULL,
    build_root TEXT NOT NULL,
    config_fragment_path TEXT NOT NULL,
    initramfs_path TEXT NOT NULL,
    firmware_root TEXT NOT NULL,
    kernel_config_path TEXT NOT NULL,
    kernel_release TEXT NOT NULL DEFAULT '',
    staged_kernel_root TEXT NOT NULL DEFAULT '',
    staged_efi_path TEXT NOT NULL DEFAULT '',
    kernel_sha256 TEXT NOT NULL DEFAULT '',
    efi_sha256 TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL,
    detail TEXT NOT NULL,
    updated_at_ms INTEGER NOT NULL
) WITHOUT ROWID;

PRAGMA user_version = 3;
COMMIT;
