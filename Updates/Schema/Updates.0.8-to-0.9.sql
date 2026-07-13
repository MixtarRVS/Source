-- MixtarRVS Updates.config migration: 0.8 -> 0.9
--
-- This migration is intentionally idempotent.  It installs native DNS and
-- downloader policy only.  Build evidence is recorded by the image integrator
-- after the signed sources and resulting binaries have passed their gates.

BEGIN IMMEDIATE;

INSERT OR REPLACE INTO setting (key, value) VALUES
    ('networking.dns.servers', '1.1.1.1,1.0.0.1'),
    ('tool.signature.verify', '/System/Userland/updates-signature-verify'),
    ('component.cares-build.build_recipe', '/System/Configuration/Updates/Recipes/build_cares_musl.sh'),
    ('component.curl-downloader.build_recipe', '/System/Configuration/Updates/Recipes/build_curl_musl.sh'),
    ('component.curl-downloader.dependencies', 'libressl-build,zlib-build,cares-build,ca-bundle');

INSERT OR REPLACE INTO trust_anchor (
    id, owner, kind, fingerprint, material_uri, material_sha256,
    local_path, local_sha256, enabled
) VALUES (
    'cares-release',
    'c-ares release maintainers',
    'openpgp',
    'DA7D64E4C82C6294CB73A20E22E3D13B5411B7CA',
    'https://keys.openpgp.org/vks/v1/by-fingerprint/DA7D64E4C82C6294CB73A20E22E3D13B5411B7CA',
    '',
    '/System/Configuration/Updates/Trust/CAres-Curl-release-keyring.gpg',
    '59f43f4d13e74dc4fb9196226c9578a73a88f1987bde6002c109529e41fe2250',
    1
);

UPDATE trust_anchor
SET local_path='/System/Configuration/Updates/Trust/CAres-Curl-release-keyring.gpg',
    local_sha256='59f43f4d13e74dc4fb9196226c9578a73a88f1987bde6002c109529e41fe2250'
WHERE id='curl-release';

INSERT OR REPLACE INTO trust_signer (trust_anchor_id, fingerprint, enabled) VALUES
    ('cares-release', 'DA7D64E4C82C6294CB73A20E22E3D13B5411B7CA', 1),
    ('cares-release', '75EB6CA0E63E90C4FF2C868FC1D15611B2E4720B', 1),
    ('curl-release', '27EDEAF22F3ABCEB50DB9A125CC908FDB71E12C2', 1);

INSERT INTO component (
    id, display_name, installed_version, channel, recipe,
    install_target, boot_target, enabled, auto_install
) VALUES (
    'cares-build', 'c-ares native DNS library', '1.34.8', 'stable',
    'cares-static-musl', '/System/Libraries/CAres/1.34.8', '', 1, 0
)
ON CONFLICT(id) DO UPDATE SET
    display_name=excluded.display_name,
    installed_version=excluded.installed_version,
    channel=excluded.channel,
    recipe=excluded.recipe,
    install_target=excluded.install_target,
    boot_target=excluded.boot_target,
    enabled=excluded.enabled,
    auto_install=excluded.auto_install;

INSERT OR REPLACE INTO trust_anchor(
    id, owner, kind, fingerprint, material_uri, material_sha256, enabled
) VALUES (
    'mixtarrvs-release', 'MixtarRVS Project', 'openpgp',
    'BCD07502474A4D979CF6FAFCC39AB35C75AFAFCF',
    'https://raw.githubusercontent.com/MixtarRVS/Source/main/System/Updates/Trust/MixtarRVS-release-key.asc',
    '901f37b3cede9b214d21a556a0b414b2b4e6c829d866d02bc07b39755b779a9c', 1
);

DELETE FROM trust_anchor WHERE id='mixtarrvs-unpublished';
UPDATE component SET enabled=1 WHERE id='mixtarrvs';

INSERT OR REPLACE INTO component_source (
    component_id, role, discovery_kind, discovery_uri,
    artifact_uri_template, signature_uri_template,
    verification_kind, trust_anchor_id, required
) VALUES (
    'cares-build', 'release-index', 'html-cares-release',
    'https://c-ares.org/',
    'https://github.com/c-ares/c-ares/releases/download/v{version}/c-ares-{version}.tar.gz',
    'https://github.com/c-ares/c-ares/releases/download/v{version}/c-ares-{version}.tar.gz.asc',
    'openpgp-detached', 'cares-release', 1
);

INSERT OR REPLACE INTO component_dependency (component_id, dependency_id) VALUES
    ('cares-build', 'zig-bootstrap'),
    ('cares-build', 'gmake-build'),
    ('curl-downloader', 'cares-build'),
    ('curl-downloader', 'libressl-build'),
    ('curl-downloader', 'zlib-build'),
    ('curl-downloader', 'ca-bundle');

UPDATE component
SET recipe='curl-static-cares-libressl-musl'
WHERE id='curl-downloader';

-- The official MixtarRVS source location is fixed even before the first
-- public release exists.  The component and its trust anchor deliberately
-- remain disabled until a real detached-signing key and release are
-- published.  This makes discovery fail closed without inventing trust data.
INSERT OR REPLACE INTO component_source (
    component_id, role, discovery_kind, discovery_uri,
    artifact_uri_template, signature_uri_template,
    verification_kind, trust_anchor_id, required
) VALUES (
    'mixtarrvs', 'official-release', 'html-github-release',
    'https://github.com/MixtarRVS/Source/releases',
    'https://github.com/MixtarRVS/Source/releases/download/v{version}/MixtarRVS-{version}-source.tar.xz',
    'https://github.com/MixtarRVS/Source/releases/download/v{version}/MixtarRVS-{version}-source.tar.xz.asc',
    'openpgp-detached', 'mixtarrvs-release', 1
);

COMMIT;
-- Pin the local MixtarRVS release keyring used by fail-closed verification.
UPDATE trust_anchor
SET local_path = '/System/Configuration/Updates/Trust/MixtarRVS-release-keyring.gpg',
    local_sha256 = '3d3af3e0d56b4e662159dfbf32ea6424fb881e9e9fc66750a4a23c37672e33a2',
    material_uri = 'https://raw.githubusercontent.com/MixtarRVS/Source/main/System/Updates/Trust/MixtarRVS-release-key.asc'
WHERE id = 'mixtarrvs-release';

UPDATE setting SET value = 'pinned-in-tree'
WHERE key = 'kernel.version.policy';

UPDATE setting SET value = '7.1.2'
WHERE key = 'kernel.version.pinned';

UPDATE setting SET value = 'in-tree'
WHERE key = 'kernel.rt.version.pinned';

UPDATE setting
SET value = 'quiet loglevel=3 console=tty0 console=ttyS0,115200 rdinit=/System/Init/MixtarRVS devtmpfs.mount=0'
WHERE key = 'kernel.cmdline';

INSERT OR REPLACE INTO trust_signer(trust_anchor_id, fingerprint, enabled)
VALUES (
    'mixtarrvs-release',
    'BCD07502474A4D979CF6FAFCC39AB35C75AFAFCF',
    1
);
