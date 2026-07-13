BEGIN IMMEDIATE;

INSERT INTO setting(key, value) VALUES
    ('schema.name', 'MixtarRVS.Updates.config'),
    ('schema.version', '1'),
    ('system.release.current', '0.8'),
    ('system.release.target', '0.9'),
    ('policy.package_repository', 'none'),
    ('policy.update_api', 'none'),
    ('policy.website', 'https://mixtarrvs.com/'),
    ('policy.fail_closed', 'true'),
    ('source.download.connect_timeout_seconds', '10'),
    ('source.discovery.max_time_seconds', '30'),
    ('source.download.max_time_seconds', '1800'),
    ('source.download.retry_count', '5'),
    ('source.download.retry_delay_seconds', '2'),
    ('tool.fetch', 'curl'),
    ('tool.mkdir', 'mkdir'),
    ('tool.sha256', 'sha256sum'),
    ('tool.gpgv', 'gpgv');

INSERT INTO trust_anchor(id, owner, kind, fingerprint, material_uri, material_sha256, enabled) VALUES
    ('zsh-release', 'Z shell maintainers', 'openpgp',
     '7CA7ECAAF06216B90F894146ACF8146CAE8CBBC4',
     'https://www.zsh.org/pub/zsh-keyring.asc',
     'b6333e75a019034d2869333adb56387a56bbec8ffb2056f7f3b721b2fc7acc2e', 1),
    ('kernel-release', 'Linux kernel stable maintainers', 'openpgp',
     '647F28654894E3BD457199BE38DBBDC86092693E', '', '', 1),
    ('openbsd-anoncvs', 'OpenBSD Project AnonCVS', 'ssh-host-key',
     'SHA256:oaJ7VEyjt2EHMeixzKn9zJGiV5YlWHIUls070tKdBzI', '', '', 1),
    ('ncurses-release', 'Thomas E. Dickey ncurses releases', 'openpgp',
     '19882D92DDA4C400C22C0D56CC2AF4472167BE03',
     'https://invisible-island.net/public/dickey%40invisible-island.net-rsa3072.asc',
     'eec7eccb51a27ae633784d1b1ef42eb775130c782ea51a6c47fa7a901484d6db', 1),
    ('grml-manual', 'Grml Project', 'manual',
     'MANUAL-PIN-REQUIRED', '', '', 1),
    ('mixtarrvs-release', 'MixtarRVS Project', 'openpgp',
     'BCD07502474A4D979CF6FAFCC39AB35C75AFAFCF',
     'https://raw.githubusercontent.com/MixtarRVS/Source/main/System/Updates/Trust/MixtarRVS-release-key.asc',
     '901f37b3cede9b214d21a556a0b414b2b4e6c829d866d02bc07b39755b779a9c', 1);

INSERT INTO component(id, display_name, installed_version, channel, recipe,
                      install_target, boot_target, enabled, auto_install) VALUES
    ('zsh', 'ZSH', '5.9.2', 'stable', 'zsh-native-musl',
     '/System/Shells/zsh.apx', '', 1, 0),
    ('ncurses', 'ncurses terminal library', '6.6', 'stable',
     'ncurses-static-musl', '/System/Shells/zsh.apx/Resources/Terminfo', '', 1, 0),
    ('grml-zsh-config', 'Grml ZSH configuration', 'unversioned', 'stable',
     'grml-zsh-config', '/System/Shells/zsh.apx/Resources/Grml', '', 1, 0),
    ('openbsd-userland', 'OpenBSD-first Mixtar userland',
     '5767a144992f2faf8b1ef2b3d1889cb67bc98531', 'stable',
     'openbsd-ailang-bridge', '/System/Userland', '', 1, 0),
    ('linux-rt', 'Linux PREEMPT_RT kernel', '7.1.2', 'stable-rt',
     'linux-preempt-rt', '/System/Kernel/Linux/RT/{version}',
     '/System/EFI/MixtarRVS/{system_release}.efi', 1, 0),
    ('mixtarrvs', 'MixtarRVS core', '0.8', 'stable', 'mixtarrvs-native',
     '/System', '/System/EFI/MixtarRVS/{version}.efi', 1, 0);

INSERT INTO component_source(component_id, role, discovery_kind, discovery_uri,
                             artifact_uri_template, signature_uri_template,
                             verification_kind, trust_anchor_id, required) VALUES
    ('zsh', 'release-index', 'html-zsh-release', 'https://www.zsh.org/pub/',
     'https://www.zsh.org/pub/zsh-{version}.tar.xz',
     'https://www.zsh.org/pub/zsh-{version}.tar.xz.asc',
     'openpgp-detached', 'zsh-release', 1),
    ('ncurses', 'release-index', 'html-ncurses-release',
     'https://invisible-island.net/archives/ncurses/',
     'https://invisible-island.net/archives/ncurses/ncurses-{version}.tar.gz',
     'https://invisible-island.net/archives/ncurses/ncurses-{version}.tar.gz.asc',
     'openpgp-detached', 'ncurses-release', 1),
    ('grml-zsh-config', 'configuration', 'https-etag',
     'https://grml.org/console/zshrc', 'https://grml.org/console/zshrc', '',
     'manual-pinned-hash', 'grml-manual', 1),
    ('openbsd-userland', 'source', 'anoncvs',
     'anoncvs@anoncvs.spacehopper.org:/cvs', 'src', '',
     'ssh-host-key', 'openbsd-anoncvs', 1),
    ('linux-rt', 'kernel-source', 'kernel-index',
     'https://www.kernel.org/pub/linux/kernel/v7.x/',
     'https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-{version}.tar.xz',
     'https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-{version}.tar.sign',
     'openpgp-detached-stream', 'kernel-release', 1),
    ('linux-rt', 'rt-patch', 'kernel-rt-index',
     'https://www.kernel.org/pub/linux/kernel/projects/rt/', '', '',
     'openpgp-detached-stream', 'kernel-release', 1);

INSERT INTO component_dependency(component_id, dependency_id) VALUES
    ('zsh', 'ncurses'),
    ('grml-zsh-config', 'zsh');

COMMIT;


-- GNU Make is required by Linux Kbuild.  It is deliberately exposed only as
-- gmake inside the isolated source-build environment and is not a MixtarRVS
-- native command named "make".
BEGIN IMMEDIATE;

INSERT OR REPLACE INTO trust_anchor (
    id, owner, kind, fingerprint, material_uri, material_sha256, enabled
) VALUES (
    'gnu-make-release',
    'GNU Make maintainer Paul D. Smith',
    'openpgp',
    'B2508A90102F8AE3B12A0090DEACCAAEDB78137A',
    'https://ftp.gnu.org/gnu/gnu-keyring.gpg',
    '5de4e5fc372d8c32fd6cf154f4250c4d882d1cd4f765fe4f1bc2602bc8bf1510',
    1
);

INSERT OR REPLACE INTO component (
    id, display_name, installed_version, channel, recipe,
    install_target, boot_target, enabled, auto_install
) VALUES (
    'gmake-build',
    'GNU Make isolated build tool',
    '4.4.1',
    'stable',
    'gmake-static-musl',
    '/System/Compilers/GNU/4.4.1',
    '',
    1,
    0
);

INSERT OR REPLACE INTO component_source (
    component_id, role, discovery_kind, discovery_uri,
    artifact_uri_template, signature_uri_template,
    verification_kind, trust_anchor_id, required
) VALUES (
    'gmake-build',
    'release-index',
    'html-gnu-release',
    'https://ftp.gnu.org/gnu/make/',
    'https://ftp.gnu.org/gnu/make/make-{version}.tar.gz',
    'https://ftp.gnu.org/gnu/make/make-{version}.tar.gz.sig',
    'openpgp-detached',
    'gnu-make-release',
    1
);

INSERT OR REPLACE INTO setting (key, value)
VALUES ('tool.make', '/System/Compilers/GNU/4.4.1/bin/gmake');

INSERT OR REPLACE INTO setting (key, value)
VALUES ('policy.tool.gmake', 'isolated-build-only');

INSERT OR REPLACE INTO setting (key, value)
VALUES ('component.gmake-build.compiler', '/System/Compilers/Zig/0.16.0/zig');

INSERT OR REPLACE INTO setting (key, value)
VALUES ('build.sandbox.compat_shell', '/System/Shells/zsh.apx/Program/zsh');

COMMIT;

-- XZ is part of the isolated source-build closure.  The native command and
-- liblzma are built from a signed upstream release without importing a distro
-- package or making XZ part of the MixtarRVS identity.
BEGIN IMMEDIATE;

INSERT OR REPLACE INTO trust_anchor (
    id, owner, kind, fingerprint, material_uri, material_sha256, enabled
) VALUES (
    'xz-release',
    'XZ Utils maintainer Lasse Collin',
    'openpgp',
    '3690C240CE51B4670D30AD1C38EE757D69184620',
    'https://tukaani.org/misc/lasse_collin_pubkey.txt',
    '7b44485541eefe7cecb8bcf30682904bb6c3d70aae21bbfffc5fca742cb6f56f',
    1
);

INSERT OR REPLACE INTO component (
    id, display_name, installed_version, channel, recipe,
    install_target, boot_target, enabled, auto_install
) VALUES (
    'xz-build',
    'XZ source archive tool',
    '5.8.3',
    'stable',
    'xz-static-musl',
    '/System/Compilers/XZ/5.8.3',
    '',
    1,
    0
);

INSERT OR REPLACE INTO component_source (
    component_id, role, discovery_kind, discovery_uri,
    artifact_uri_template, signature_uri_template,
    verification_kind, trust_anchor_id, required
) VALUES (
    'xz-build',
    'release-index',
    'html-xz-release',
    'https://tukaani.org/xz/',
    'https://github.com/tukaani-project/xz/releases/download/v{version}/xz-{version}.tar.gz',
    'https://github.com/tukaani-project/xz/releases/download/v{version}/xz-{version}.tar.gz.sig',
    'openpgp-detached',
    'xz-release',
    1
);

INSERT OR REPLACE INTO setting (key, value)
VALUES ('tool.xz', '/System/Compilers/XZ/5.8.3/bin/xz');

INSERT OR REPLACE INTO setting (key, value)
VALUES ('library.xz', '/System/Libraries/XZ/5.8.3');

INSERT OR REPLACE INTO setting (key, value)
VALUES ('component.xz-build.compiler', '/System/Compilers/Zig/0.16.0/zig');

INSERT OR REPLACE INTO setting (key, value)
VALUES ('component.xz-build.make', 'gmake-build');

COMMIT;

-- zlib is retained only as a static dependency of source-build tools such as
-- bsdtar.  No gzip-compatible command is added to the native command surface.
BEGIN IMMEDIATE;

INSERT OR REPLACE INTO trust_anchor (
    id, owner, kind, fingerprint, material_uri, material_sha256, enabled
) VALUES (
    'zlib-release',
    'zlib maintainer Mark Adler',
    'openpgp',
    '5ED46A6721D365587791E2AA783FCD8E58BCAFBA',
    'https://madler.net/madler/pgp.html',
    '27f818fd93326e4531c6b094f0edc4c331a1c77ec6449675a3929ae3274d85ac',
    1
);

INSERT OR REPLACE INTO component (
    id, display_name, installed_version, channel, recipe,
    install_target, boot_target, enabled, auto_install
) VALUES (
    'zlib-build',
    'zlib static build library',
    '1.3.2',
    'stable',
    'zlib-static-musl',
    '/System/Libraries/Zlib/1.3.2',
    '',
    1,
    0
);

INSERT OR REPLACE INTO component_source (
    component_id, role, discovery_kind, discovery_uri,
    artifact_uri_template, signature_uri_template,
    verification_kind, trust_anchor_id, required
) VALUES (
    'zlib-build',
    'release-index',
    'html-zlib-release',
    'https://zlib.net/',
    'https://zlib.net/zlib-{version}.tar.gz',
    'https://zlib.net/zlib-{version}.tar.gz.asc',
    'openpgp-detached-and-published-sha256',
    'zlib-release',
    1
);

INSERT OR REPLACE INTO setting (key, value)
VALUES ('library.zlib', '/System/Libraries/Zlib/1.3.2');

INSERT OR REPLACE INTO setting (key, value)
VALUES ('component.zlib-build.compiler', '/System/Compilers/Zig/0.16.0/zig');

INSERT OR REPLACE INTO setting (key, value)
VALUES ('component.zlib-build.make', 'gmake-build');

COMMIT;

-- bsdtar provides the updater's archive boundary.  It is built with only the
-- already verified static zlib and liblzma dependencies.
BEGIN IMMEDIATE;

INSERT OR REPLACE INTO trust_anchor (
    id, owner, kind, fingerprint, material_uri, material_sha256, enabled
) VALUES (
    'libarchive-release',
    'libarchive release signing key',
    'openpgp',
    '659C84C0E23EA1FA97E0B58CC040B508D63D2B36',
    'https://keys.openpgp.org/vks/v1/by-fingerprint/659C84C0E23EA1FA97E0B58CC040B508D63D2B36',
    'b2c91d075f112508442384dd1649735a84e81aea7ce1593d49a8f658ab66779f',
    1
);

INSERT OR REPLACE INTO component (
    id, display_name, installed_version, channel, recipe,
    install_target, boot_target, enabled, auto_install
) VALUES (
    'archive-build',
    'BSD archive extraction tool',
    '3.8.8',
    'stable',
    'libarchive-bsdtar-static-musl',
    '/System/Compilers/BSDTar/3.8.8',
    '',
    1,
    0
);

INSERT OR REPLACE INTO component_source (
    component_id, role, discovery_kind, discovery_uri,
    artifact_uri_template, signature_uri_template,
    verification_kind, trust_anchor_id, required
) VALUES (
    'archive-build',
    'release-index',
    'html-libarchive-release',
    'https://www.libarchive.org/',
    'https://github.com/libarchive/libarchive/releases/download/v{version}/libarchive-{version}.tar.gz',
    'https://github.com/libarchive/libarchive/releases/download/v{version}/libarchive-{version}.tar.gz.asc',
    'openpgp-detached',
    'libarchive-release',
    1
);

INSERT OR REPLACE INTO setting (key, value)
VALUES ('tool.archive', '/System/Compilers/BSDTar/3.8.8/bin/bsdtar');

INSERT OR REPLACE INTO setting (key, value)
VALUES ('component.archive-build.compiler', '/System/Compilers/Zig/0.16.0/zig');

INSERT OR REPLACE INTO setting (key, value)
VALUES ('component.archive-build.make', 'gmake-build');

INSERT OR REPLACE INTO setting (key, value)
VALUES ('component.archive-build.dependencies', 'zlib-build,xz-build');

COMMIT;

-- LibreSSL supplies the source-native TLS boundary used by the downloader.
-- Only static libraries and headers are promoted; openssl(1) and nc(1) are
-- intentionally not added to the native command surface.
BEGIN IMMEDIATE;

INSERT OR REPLACE INTO trust_anchor (
    id, owner, kind, fingerprint, material_uri, material_sha256, enabled
) VALUES (
    'libressl-release',
    'LibreSSL portable release key',
    'openpgp',
    'A1EB079B8D3EB92B4EBD3139663AF51BD5E4D8D5',
    'https://ftp.openbsd.org/pub/OpenBSD/LibreSSL/libressl.asc',
    '1e282b5938b09c52cb0ba81d964f6ad26fc644ebabb18157b641dcb6384dcf1b',
    1
);

INSERT OR REPLACE INTO component (
    id, display_name, installed_version, channel, recipe,
    install_target, boot_target, enabled, auto_install
) VALUES (
    'libressl-build',
    'LibreSSL static TLS libraries',
    '4.3.2',
    'stable',
    'libressl-static-musl',
    '/System/Libraries/LibreSSL/4.3.2',
    '',
    1,
    0
);

INSERT OR REPLACE INTO component_source (
    component_id, role, discovery_kind, discovery_uri,
    artifact_uri_template, signature_uri_template,
    verification_kind, trust_anchor_id, required
) VALUES (
    'libressl-build',
    'release-index',
    'html-libressl-release',
    'https://www.libressl.org/releases.html',
    'https://ftp.openbsd.org/pub/OpenBSD/LibreSSL/libressl-{version}.tar.gz',
    'https://ftp.openbsd.org/pub/OpenBSD/LibreSSL/libressl-{version}.tar.gz.asc',
    'openpgp-detached',
    'libressl-release',
    1
);

INSERT OR REPLACE INTO setting (key, value)
VALUES ('library.libressl', '/System/Libraries/LibreSSL/4.3.2');

INSERT OR REPLACE INTO setting (key, value)
VALUES ('component.libressl-build.compiler', '/System/Compilers/Zig/0.16.0/zig');

INSERT OR REPLACE INTO setting (key, value)
VALUES ('component.libressl-build.make', 'gmake-build');

COMMIT;

-- The CA bundle is immutable until its new hash is reviewed and pinned.  The
-- sidecar hash is discovery evidence, not authority to trust an arbitrary new
-- root set automatically.
BEGIN IMMEDIATE;

INSERT OR REPLACE INTO trust_anchor (
    id, owner, kind, fingerprint, material_uri, material_sha256, enabled
) VALUES (
    'curl-ca-bundle',
    'curl Mozilla CA extraction',
    'manual',
    'SHA256:86a1f3366afac7c6f8ae9f3c779ac221129328c43f0ab2b8817eb2f362a5025c',
    'https://curl.se/ca/cacert.pem.sha256',
    '4691419828721dd35ec09e254d280acf8a5cae424fae2e9aeae49804ee03c53d',
    1
);

INSERT OR REPLACE INTO component (
    id, display_name, installed_version, channel, recipe,
    install_target, boot_target, enabled, auto_install
) VALUES (
    'ca-bundle',
    'TLS certificate authority bundle',
    '2026-05-14',
    'stable',
    'pinned-data',
    '/System/Configuration/TLS/cacert.pem',
    '',
    1,
    0
);

INSERT OR REPLACE INTO component_source (
    component_id, role, discovery_kind, discovery_uri,
    artifact_uri_template, signature_uri_template,
    verification_kind, trust_anchor_id, required
) VALUES (
    'ca-bundle',
    'published-bundle',
    'html-curl-ca-bundle',
    'https://curl.se/docs/caextract.html',
    'https://curl.se/ca/cacert.pem',
    'https://curl.se/ca/cacert.pem.sha256',
    'sha256-pinned-manual-approval',
    'curl-ca-bundle',
    1
);

INSERT OR REPLACE INTO trust_anchor (
    id, owner, kind, fingerprint, material_uri, material_sha256, enabled
) VALUES (
    'curl-release',
    'curl maintainer Daniel Stenberg',
    'openpgp',
    '27EDEAF22F3ABCEB50DB9A125CC908FDB71E12C2',
    'https://keys.openpgp.org/vks/v1/by-fingerprint/27EDEAF22F3ABCEB50DB9A125CC908FDB71E12C2',
    '55b605e2e455e1214781c14932696116b792adf334a400dda9ef2a6f06852b32',
    1
);

INSERT OR REPLACE INTO component (
    id, display_name, installed_version, channel, recipe,
    install_target, boot_target, enabled, auto_install
) VALUES (
    'curl-downloader',
    'Parallel HTTPS source downloader',
    '8.21.0',
    'stable',
    'curl-static-libressl-musl',
    '/System/Userland/curl',
    '',
    1,
    0
);

INSERT OR REPLACE INTO component_source (
    component_id, role, discovery_kind, discovery_uri,
    artifact_uri_template, signature_uri_template,
    verification_kind, trust_anchor_id, required
) VALUES (
    'curl-downloader',
    'release-index',
    'html-curl-release',
    'https://curl.se/download.html',
    'https://curl.se/download/curl-{version}.tar.xz',
    'https://curl.se/download/curl-{version}.tar.xz.asc',
    'openpgp-detached',
    'curl-release',
    1
);

INSERT OR REPLACE INTO setting (key, value)
VALUES ('tool.fetch', '/System/Userland/curl');

INSERT OR REPLACE INTO setting (key, value)
VALUES ('tool.fetch.parallel', 'true');

INSERT OR REPLACE INTO setting (key, value)
VALUES ('tls.ca_bundle', '/System/Configuration/TLS/cacert.pem');

INSERT OR REPLACE INTO setting (key, value)
VALUES ('component.curl-downloader.dependencies', 'libressl-build,zlib-build,ca-bundle');

COMMIT;

BEGIN IMMEDIATE;

INSERT OR REPLACE INTO setting(key, value) VALUES
    ('kernel.download.connect_timeout_seconds', '10'),
    ('kernel.download.max_time_seconds', '1800'),
    ('kernel.version.policy', 'pinned-in-tree'),
    ('kernel.version.pinned', '7.1.2'),
    ('kernel.rt.version.pinned', 'in-tree'),
    ('kernel.archive.index_uri', 'https://www.kernel.org/pub/linux/kernel/v7.x/'),
    ('kernel.build.allowed_stage_root', '/Temporary/Updates'),
    ('kernel.build.allowed_work_root', '/Temporary/Updates'),
    ('kernel.build.jobs', 'auto'),
    ('kernel.build.stage_root', '/Temporary/Updates/stage/0.9-candidate'),
    ('kernel.build.work_root', '/Temporary/Updates/kernel/build'),
    ('kernel.cmdline', 'quiet loglevel=3 console=tty0 console=ttyS0,115200 rdinit=/System/Init/MixtarRVS devtmpfs.mount=0'),
    ('kernel.config.fragment', '/System/Configuration/Kernel/RT.config'),
    ('kernel.firmware.embedded', 'iwlwifi-8265-36.ucode regulatory.db regulatory.db.p7s'),
    ('kernel.firmware.root', '/System/Kernel/Firmware'),
    ('kernel.initramfs.path', '/System/Runtime/Build/MixtarRVS-initramfs.cpio'),
    ('tool.chmod', '/System/Userland/chmod'),
    ('tool.cp', '/System/Userland/cp'),
    ('tool.dd', '/System/Userland/dd'),
    ('tool.find', '/System/Userland/find'),
    ('tool.make', '/System/Compilers/GNU/4.4.1/bin/gmake'),
    ('tool.mkdir', '/System/Userland/mkdir'),
    ('tool.nproc', '/System/Userland/nproc'),
    ('tool.rm', '/System/Userland/rm'),
    ('tool.patch', '/System/Userland/patch'),
    ('tool.tar', '/System/Userland/tar'),
    ('tool.test', '/System/Userland/test'),
    ('tool.xz', '/System/Compilers/XZ/5.8.3/bin/xz');

COMMIT;

BEGIN;

UPDATE setting SET value = '2' WHERE key = 'schema.version';

UPDATE trust_anchor
SET material_uri = 'wkd:gregkh@kernel.org,wkd:bigeasy@linutronix.de'
WHERE id = 'kernel-release';

UPDATE component_source
SET discovery_kind = 'kernel-org-releases-json',
    discovery_uri = 'https://www.kernel.org/releases.json'
WHERE component_id = 'linux-rt' AND role = 'kernel-source';

INSERT INTO kernel_required_symbol(component_id, symbol, role, required) VALUES
    ('linux-rt', 'PREEMPT_RT', 'realtime', 1),
    ('linux-rt', 'EFI', 'boot', 1),
    ('linux-rt', 'EFIVAR_FS', 'boot', 1),
    ('linux-rt', 'NVME_CORE', 'storage', 1),
    ('linux-rt', 'BLK_DEV_NVME', 'storage', 1),
    ('linux-rt', 'EXT4_FS', 'filesystem', 1),
    ('linux-rt', 'IWLWIFI', 'network', 1),
    ('linux-rt', 'IWLMVM', 'network', 1),
    ('linux-rt', 'E1000E', 'network', 1),
    ('linux-rt', 'DRM_I915', 'display', 0),
    ('linux-rt', 'DRM_SIMPLEDRM', 'display', 1),
    ('linux-rt', 'INPUT_EVDEV', 'input', 1),
    ('linux-rt', 'SERIO_I8042', 'input', 1),
    ('linux-rt', 'SERIO_LIBPS2', 'input', 1),
    ('linux-rt', 'MOUSE_PS2', 'input', 1),
    ('linux-rt', 'USB_XHCI_HCD', 'input', 1);

COMMIT;

BEGIN;

INSERT INTO setting(key, value) VALUES
    ('tool.signify', '/System/Userland/signify'),
    ('tool.cat', '/System/Userland/cat');

INSERT INTO trust_anchor(
    id,
    owner,
    kind,
    fingerprint,
    material_uri,
    material_sha256,
    enabled
) VALUES (
    'openbsd-79-base',
    'OpenBSD Project 7.9 base signing key',
    'signify-ed25519',
    'openbsd-79-base',
    'https://ftp.openbsd.org/pub/OpenBSD/7.9/openbsd-79-base.pub',
    'b7ee8e7981549a1f707a4ed05115a99959a5f9e34b9bed9f9a098be17dd7e4b1',
    1
);

UPDATE component
SET recipe = 'openbsd-release-ailang-bridge',
    install_target = '/System/Userland'
WHERE id = 'openbsd-userland';

UPDATE component_source
SET role = 'release-source',
    discovery_kind = 'html-openbsd-release',
    discovery_uri = 'https://cdn.openbsd.org/pub/OpenBSD/',
    artifact_uri_template = 'https://ftp.openbsd.org/pub/OpenBSD/{version}/src.tar.gz',
    signature_uri_template = 'https://ftp.openbsd.org/pub/OpenBSD/{version}/SHA256.sig',
    verification_kind = 'signify-manifest',
    trust_anchor_id = 'openbsd-79-base',
    required = 1
WHERE component_id = 'openbsd-userland';

COMMIT;

BEGIN;

INSERT INTO trust_anchor(
    id,
    owner,
    kind,
    fingerprint,
    material_uri,
    material_sha256,
    enabled
) VALUES (
    'grml-release',
    'Grml grml-etc-core source release signer',
    'openpgp',
    '7D1ACFFAD9E0806C9C4CD3925C13D6DB93052E03',
    '',
    '',
    1
);

UPDATE component
SET recipe = 'grml-verified-source',
    install_target = '/System/Shells/zsh.apx/Resources/Grml'
WHERE id = 'grml-zsh-config';

UPDATE component_source
SET role = 'source-release',
    discovery_kind = 'html-grml-source-release',
    discovery_uri = 'https://deb.grml.org/pool/main/g/grml-etc-core/',
    artifact_uri_template = 'https://deb.grml.org/pool/main/g/grml-etc-core/{source}',
    signature_uri_template = 'https://deb.grml.org/pool/main/g/grml-etc-core/{dsc}',
    verification_kind = 'openpgp-clearsigned-manifest',
    trust_anchor_id = 'grml-release',
    required = 1
WHERE component_id = 'grml-zsh-config';

DELETE FROM component_source
WHERE component_id='grml-zsh-config' AND role IN ('source-index','source-archive');

UPDATE trust_anchor
SET local_path='/System/Configuration/Updates/Trust/Grml-release-keyring.gpg',
    local_sha256='df047647e6371dec36799e2e74da4ca3d8afe0d23b7532186b2e4098fccafd75'
WHERE id='grml-release';

INSERT OR REPLACE INTO trust_signer(trust_anchor_id, fingerprint, enabled) VALUES
    ('grml-release', '7D1ACFFAD9E0806C9C4CD3925C13D6DB93052E03', 1);

COMMIT;
-- SQLite is a source-built Mixtar runtime dependency. sqlite.org does not
-- publish a detached signature for this archive, so the exact official SHA3
-- digest is the trust anchor and automatic installation remains disabled.
INSERT OR REPLACE INTO trust_anchor (
    id, owner, kind, fingerprint, material_uri, material_sha256, enabled
) VALUES (
    'sqlite-org-3.53.3-sha3',
    'SQLite Consortium',
    'manual',
    '98f2b3f3c11be6a03ea32346937b032c2472ebbd7a716bed36ca2f5693e7ce8b',
    'https://www.sqlite.org/2026/sqlite-autoconf-3530300.tar.gz',
    '',
    1
);

INSERT OR REPLACE INTO component (
    id, display_name, installed_version, channel, recipe,
    install_target, boot_target, enabled, auto_install
) VALUES (
    'sqlite-runtime',
    'SQLite runtime',
    '3.53.3',
    'source-pinned',
    'musl-static',
    '/System/Libraries/SQLite/3.53.3',
    '',
    1,
    0
);

INSERT OR REPLACE INTO component_source (
    component_id, role, discovery_kind, discovery_uri,
    artifact_uri_template, signature_uri_template,
    verification_kind, trust_anchor_id, required
) VALUES (
    'sqlite-runtime',
    'source',
    'fixed',
    'https://www.sqlite.org/download.html',
    'https://www.sqlite.org/2026/sqlite-autoconf-3530300.tar.gz',
    '',
    'sha3-256-pinned',
    'sqlite-org-3.53.3-sha3',
    1
);
-- Source-native compiler bootstrap. The first installation is deliberately
-- manual; once minisign is present, all three upstreams are signature-gated.
INSERT OR REPLACE INTO trust_anchor (
    id, owner, kind, fingerprint, material_uri, material_sha256, enabled
) VALUES
    (
        'frank-denis-minisign-release',
        'Frank Denis',
        'signify-ed25519',
        'RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3',
        'https://download.libsodium.org/libsodium/releases/README.html',
        '',
        1
    ),
    (
        'zig-release-minisign',
        'Zig Software Foundation',
        'signify-ed25519',
        'RWSGOq2NVecA2UPNdBUZykf1CCb147pkmdtYxgb3Ti+JO/wCYvhbAb/U',
        'https://ziglang.org/download/',
        '',
        1
    );

INSERT OR REPLACE INTO component (
    id, display_name, installed_version, channel, recipe,
    install_target, boot_target, enabled, auto_install
) VALUES
    (
        'zig-bootstrap',
        'Zig C/C++ bootstrap toolchain',
        '0.16.0',
        'stable',
        'install-zig-bootstrap',
        '/System/Compilers/Zig/0.16.0',
        '',
        1,
        0
    ),
    (
        'libsodium-build',
        'libsodium build dependency',
        '1.0.22',
        'stable',
        'build-libsodium-musl',
        '/System/Libraries/libsodium/1.0.22',
        '',
        1,
        0
    ),
    (
        'minisign-verifier',
        'Minisign source verifier',
        '0.12',
        'stable',
        'build-minisign-musl',
        '/System/Compilers/minisign/0.12',
        '',
        1,
        0
    );

INSERT OR REPLACE INTO component_source (
    component_id, role, discovery_kind, discovery_uri,
    artifact_uri_template, signature_uri_template,
    verification_kind, trust_anchor_id, required
) VALUES
    (
        'zig-bootstrap',
        'bootstrap-binary',
        'official-json',
        'https://ziglang.org/download/index.json',
        'https://ziglang.org/download/{version}/zig-x86_64-linux-{version}.tar.xz',
        'https://ziglang.org/download/{version}/zig-x86_64-linux-{version}.tar.xz.minisig',
        'minisign',
        'zig-release-minisign',
        1
    ),
    (
        'libsodium-build',
        'source',
        'github-release',
        'https://api.github.com/repos/jedisct1/libsodium/releases/latest',
        'https://github.com/jedisct1/libsodium/releases/download/{version}-RELEASE/libsodium-{version}.tar.gz',
        'https://github.com/jedisct1/libsodium/releases/download/{version}-RELEASE/libsodium-{version}.tar.gz.minisig',
        'minisign',
        'frank-denis-minisign-release',
        1
    ),
    (
        'minisign-verifier',
        'source',
        'github-release',
        'https://api.github.com/repos/jedisct1/minisign/releases/latest',
        'https://github.com/jedisct1/minisign/releases/download/{version}/minisign-{version}.tar.gz',
        'https://github.com/jedisct1/minisign/releases/download/{version}/minisign-{version}.tar.gz.minisig',
        'minisign',
        'frank-denis-minisign-release',
        1
    );

INSERT OR REPLACE INTO component_dependency (component_id, dependency_id) VALUES
    ('libsodium-build', 'zig-bootstrap'),
    ('minisign-verifier', 'zig-bootstrap'),
    ('minisign-verifier', 'libsodium-build');

INSERT OR REPLACE INTO setting (key, value) VALUES
    ('tool.zig', '/System/Compilers/Zig/0.16.0/zig'),
    ('tool.minisign', '/System/Compilers/minisign/0.12/minisign'),
    ('tool.sha256', '/System/Userland/mixtar-sha256'),
    ('tool.zig.library_root', '/System/Compilers/Zig/0.16.0'),
    ('build.toolchain.executable', '/System/Compilers/Zig/0.16.0/zig'),
    ('build.toolchain.cc', '/System/Compilers/Zig/0.16.0/zig cc -target x86_64-linux-musl'),
    ('build.toolchain.ar', '/System/Compilers/Zig/0.16.0/zig ar'),
    ('build.toolchain.ranlib', '/System/Compilers/Zig/0.16.0/zig ranlib'),
    ('build.toolchain.ld', '/System/Compilers/Zig/0.16.0/zig ld.lld'),
    ('build.toolchain.cache_environment', 'ZIG_GLOBAL_CACHE_DIR'),
    ('policy.build_namespace', 'isolated-posix'),
    ('tool.build_executor', '/System/Userland/mixtar-build-executor'),
    ('build.sandbox.allowed_root', '/Temporary/Updates'),
    ('build.sandbox.root', '/Temporary/Updates/Sandbox'),
    ('build.sandbox.work', '/Temporary/Updates/Work'),
    ('build.sandbox.system_source', '/System'),
    ('build.sandbox.devices_source', '/System/Runtime/Devices'),
    ('build.sandbox.tmpfs_options', 'mode=0755,size=768M'),
    ('build.sandbox.uid', '65534'),
    ('build.sandbox.gid', '65534'),
    ('build.sandbox.user', 'Builder'),
    ('build.sandbox.home', '/Temporary/Updates/Work'),
    ('build.sandbox.path', '/bin:/System/Userland:/System/Shells/zsh.apx/Program'),
    ('build.sandbox.locale', 'C.UTF-8'),
    ('build.sandbox.cache', '/Temporary/Updates/Work/.compiler-cache'),
    ('component.zsh.build_recipe', '/System/Configuration/Updates/Recipes/build_zsh_musl.sh');

BEGIN IMMEDIATE;

UPDATE setting SET value='3' WHERE key='schema.version';

INSERT OR REPLACE INTO setting (key, value) VALUES
    ('tool.gpgv', '/System/Userland/gpgv'),
    ('tool.signature_verifier', '/System/Userland/updates-signature-verify'),
    ('verification.openpgp.homedir', '/Temporary/Work/VerificationHome'),
    ('trust.gnupg.keyring.path', '/System/Configuration/Updates/Trust/GnuPG-release-keyring.gpg'),
    ('trust.gnupg.keyring.sha256', 'ee5967ec1c0b7bce5a39b2274e2c10eda78ce8700b10c9a293086ef10755640b');

INSERT OR REPLACE INTO trust_anchor (
    id, owner, kind, fingerprint, material_uri, material_sha256,
    local_path, local_sha256, enabled
) VALUES (
    'gnupg-release',
    'GnuPG Project',
    'openpgp',
    '6DAA6E64A76D2840571B4902528897B826403ADA',
    'https://gnupg.org/signature_key.asc',
    'c74efc240181ccbf81856e35268c64083a3c9a9f7a2437823648049d0b11545a',
    '/System/Configuration/Updates/Trust/GnuPG-release-keyring.gpg',
    'ee5967ec1c0b7bce5a39b2274e2c10eda78ce8700b10c9a293086ef10755640b',
    1
);

INSERT OR REPLACE INTO trust_signer (trust_anchor_id, fingerprint, enabled) VALUES
    ('gnupg-release', '6DAA6E64A76D2840571B4902528897B826403ADA', 1),
    ('gnupg-release', 'AC8E115BF73E2D8D47FA9908E98E9B2D19C6C8BD', 1);

INSERT OR REPLACE INTO component (
    id, display_name, installed_version, channel, recipe,
    install_target, boot_target, enabled, auto_install
) VALUES
    ('libgpg-error-build', 'libgpg-error build dependency', '1.61', 'stable',
     'build-libgpg-error-musl', '/System/Libraries/LibgpgError/1.61', '', 1, 0),
    ('libgcrypt-build', 'libgcrypt build dependency', '1.12.2', 'stable',
     'build-libgcrypt-musl', '/System/Libraries/Libgcrypt/1.12.2', '', 1, 0),
    ('npth-build', 'NPth build dependency', '1.8', 'stable',
     'build-npth-musl', '/System/Libraries/Npth/1.8', '', 1, 0),
    ('libassuan-build', 'libassuan build dependency', '3.0.2', 'stable',
     'build-libassuan-musl', '/System/Libraries/Libassuan/3.0.2', '', 1, 0),
    ('libksba-build', 'libksba build dependency', '1.8.0', 'stable',
     'build-libksba-musl', '/System/Libraries/Libksba/1.8.0', '', 1, 0),
    ('gpgv-verifier', 'GnuPG signature verifier', '2.5.21', 'stable',
     'build-gpgv-musl', '/System/Userland/gpgv', '', 1, 0);

INSERT OR REPLACE INTO component_source (
    component_id, role, discovery_kind, discovery_uri,
    artifact_uri_template, signature_uri_template,
    verification_kind, trust_anchor_id, required
) VALUES
    ('libgpg-error-build', 'source', 'html-gnu-release',
     'https://gnupg.org/ftp/gcrypt/libgpg-error/',
     'https://gnupg.org/ftp/gcrypt/libgpg-error/libgpg-error-{version}.tar.bz2',
     'https://gnupg.org/ftp/gcrypt/libgpg-error/libgpg-error-{version}.tar.bz2.sig',
     'openpgp-detached-fingerprint', 'gnupg-release', 1),
    ('libgcrypt-build', 'source', 'html-gnu-release',
     'https://gnupg.org/ftp/gcrypt/libgcrypt/',
     'https://gnupg.org/ftp/gcrypt/libgcrypt/libgcrypt-{version}.tar.bz2',
     'https://gnupg.org/ftp/gcrypt/libgcrypt/libgcrypt-{version}.tar.bz2.sig',
     'openpgp-detached-fingerprint', 'gnupg-release', 1),
    ('npth-build', 'source', 'html-gnu-release',
     'https://gnupg.org/ftp/gcrypt/npth/',
     'https://gnupg.org/ftp/gcrypt/npth/npth-{version}.tar.bz2',
     'https://gnupg.org/ftp/gcrypt/npth/npth-{version}.tar.bz2.sig',
     'openpgp-detached-fingerprint', 'gnupg-release', 1),
    ('libassuan-build', 'source', 'html-gnu-release',
     'https://gnupg.org/ftp/gcrypt/libassuan/',
     'https://gnupg.org/ftp/gcrypt/libassuan/libassuan-{version}.tar.bz2',
     'https://gnupg.org/ftp/gcrypt/libassuan/libassuan-{version}.tar.bz2.sig',
     'openpgp-detached-fingerprint', 'gnupg-release', 1),
    ('libksba-build', 'source', 'html-gnu-release',
     'https://gnupg.org/ftp/gcrypt/libksba/',
     'https://gnupg.org/ftp/gcrypt/libksba/libksba-{version}.tar.bz2',
     'https://gnupg.org/ftp/gcrypt/libksba/libksba-{version}.tar.bz2.sig',
     'openpgp-detached-fingerprint', 'gnupg-release', 1),
    ('gpgv-verifier', 'source', 'html-gnu-release',
     'https://gnupg.org/ftp/gcrypt/gnupg/',
     'https://gnupg.org/ftp/gcrypt/gnupg/gnupg-{version}.tar.bz2',
     'https://gnupg.org/ftp/gcrypt/gnupg/gnupg-{version}.tar.bz2.sig',
     'openpgp-detached-fingerprint', 'gnupg-release', 1);

INSERT OR REPLACE INTO component_dependency (component_id, dependency_id) VALUES
    ('libgpg-error-build', 'zig-bootstrap'),
    ('libgpg-error-build', 'gmake-build'),
    ('libgcrypt-build', 'zig-bootstrap'),
    ('libgcrypt-build', 'gmake-build'),
    ('libgcrypt-build', 'libgpg-error-build'),
    ('npth-build', 'zig-bootstrap'),
    ('npth-build', 'gmake-build'),
    ('libassuan-build', 'zig-bootstrap'),
    ('libassuan-build', 'gmake-build'),
    ('libassuan-build', 'libgpg-error-build'),
    ('libksba-build', 'zig-bootstrap'),
    ('libksba-build', 'gmake-build'),
    ('libksba-build', 'libgpg-error-build'),
    ('gpgv-verifier', 'zig-bootstrap'),
    ('gpgv-verifier', 'gmake-build'),
    ('gpgv-verifier', 'zlib-build'),
    ('gpgv-verifier', 'libgpg-error-build'),
    ('gpgv-verifier', 'libgcrypt-build'),
    ('gpgv-verifier', 'npth-build'),
    ('gpgv-verifier', 'libassuan-build'),
    ('gpgv-verifier', 'libksba-build');

UPDATE trust_anchor
SET local_path='/System/Configuration/Updates/Trust/ZSH-release-keyring.gpg',
    local_sha256='c87ab684cb36ddeb217fbffbf578dac196b389b67e1a9bc1144f8fd5c60239d3'
WHERE id='zsh-release';

UPDATE trust_anchor
SET local_path='/System/Configuration/Updates/Trust/NCURSES-release-keyring.gpg',
    local_sha256='a9183c0bc9fd26d27ffd523c59bb992c8e5122e31073bff19f13d1bd717fa6c9'
WHERE id='ncurses-release';

INSERT OR REPLACE INTO trust_signer (trust_anchor_id, fingerprint, enabled) VALUES
    ('zsh-release', '7CA7ECAAF06216B90F894146ACF8146CAE8CBBC4', 1),
    ('zsh-release', 'CDC492FEB11A7C11C7B579760EEB44FD2036EA80', 1),
    ('zsh-release', 'E96646BE08C0AF0AA0F90788A5FEEE3AC7937444', 1),
    ('zsh-release', '0559EA9B4CB1B8EFD8C0E8B807A5FDB6BF284327', 1),
    ('zsh-release', '6EB60B637CE5ACBF2449A2DADB27E997429AF20C', 1),
    ('zsh-release', '29000BA887A93190F72B6D00FB52E368B70B2559', 1),
    ('zsh-release', 'EA254BB7FB1190BC175B887FC43563CD83FA9B0E', 1),
    ('zsh-release', '0AA945AD2FD8CF3BDD0916EE2389993190DDB2CE', 1),
    ('zsh-release', 'A19EF0E8D733A424FB22424F237EEB04D642551F', 1),
    ('zsh-release', 'F7B2754C7DE2830914661F0EA71D9A9D4BDB27B3', 1),
    ('zsh-release', '19F07B95FE3D7417672D8D3179A6EADC4C58D718', 1),
    ('ncurses-release', '19882D92DDA4C400C22C0D56CC2AF4472167BE03', 1),
    ('ncurses-release', '711EBE244DE66E56020CCB474C5C495AB79670BF', 1);

UPDATE trust_anchor
SET owner='Linux kernel and PREEMPT_RT release maintainers',
    local_path='/System/Configuration/Updates/Trust/Kernel-release-keyring.gpg',
    local_sha256='e344d360f70d46001069e08eabe158fccb61b6ac3b931ca76b61709def2696eb'
WHERE id='kernel-release';

INSERT OR REPLACE INTO trust_signer (trust_anchor_id, fingerprint, enabled) VALUES
    ('kernel-release', '647F28654894E3BD457199BE38DBBDC86092693E', 1),
    ('kernel-release', '64254695FFF0AA4466CC19E67B96E8162A8CF5D1', 1);

COMMIT;

-- Native DNS for the source updater.  c-ares is a library dependency only;
-- curl remains the actual downloader and receives DNS policy from SQLite.
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

INSERT OR REPLACE INTO component (
    id, display_name, installed_version, channel, recipe,
    install_target, boot_target, enabled, auto_install
) VALUES (
    'cares-build', 'c-ares native DNS library', '1.34.8', 'stable',
    'cares-static-musl', '/System/Libraries/CAres/1.34.8', '', 1, 0
);

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

-- Canonical official source location and detached-signing trust.
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
-- The detached-signature verifier consumes a local, pinned keyring.  The
-- release page remains discovery-only and is never a trust source.
UPDATE trust_anchor
SET local_path = '/System/Configuration/Updates/Trust/MixtarRVS-release-keyring.gpg',
    local_sha256 = '3d3af3e0d56b4e662159dfbf32ea6424fb881e9e9fc66750a4a23c37672e33a2'
WHERE id = 'mixtarrvs-release';

INSERT OR REPLACE INTO trust_signer(trust_anchor_id, fingerprint, enabled)
VALUES (
    'mixtarrvs-release',
    'BCD07502474A4D979CF6FAFCC39AB35C75AFAFCF',
    1
);
