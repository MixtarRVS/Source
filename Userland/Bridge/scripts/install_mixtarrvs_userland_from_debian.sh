#!/bin/sh
set -eu

MIXTAR_ROOT=${MIXTAR_ROOT:-/dev/nvme0n1p3}
MOUNTPOINT=${MIXTAR_MOUNTPOINT:-/mnt/mixtar-userland}
PACKAGE=${MIXTAR_PACKAGE:-/tmp/mixtarrvs-musl-src.tar.gz}
BUILD_DIR=${MIXTAR_BUILD_DIR:-/tmp/mixtarrvs-musl-build}
TARGET=/System/Tools/MixtarRVS

require_debian() {
    kernel=$(uname -r 2>/dev/null || true)
    case "$kernel" in
        7.0.0-rc3-mixtarrvs)
            return 0
            ;;
        *)
            echo "refusing: expected Debian fallback kernel, got $kernel" >&2
            return 1
            ;;
    esac
}

require_root() {
    if [ "$(id -u)" != "0" ]; then
        echo "root required" >&2
        return 1
    fi
}

mount_mixtar() {
    mkdir -p "$MOUNTPOINT"
    if ! mountpoint -q "$MOUNTPOINT"; then
        mount "$MIXTAR_ROOT" "$MOUNTPOINT"
    fi
}

bind_mount_runtime() {
    for d in dev proc sys run; do
        mkdir -p "$MOUNTPOINT/$d"
        if ! mountpoint -q "$MOUNTPOINT/$d"; then
            mount --bind "/$d" "$MOUNTPOINT/$d"
        fi
    done
}

cleanup() {
    for d in run sys proc dev; do
        if mountpoint -q "$MOUNTPOINT/$d"; then
            umount "$MOUNTPOINT/$d" || true
        fi
    done
    if mountpoint -q "$MOUNTPOINT"; then
        umount "$MOUNTPOINT" || true
    fi
}

install_profile() {
    cat > "$MOUNTPOINT/etc/profile.d/mixtarrvs-userland.sh" <<'PROFILE'
# MixtarRVS userland identity.
# Boot-critical /bin and /sbin remain compatibility/bootstrap paths.
if [ -d /System/Tools/MixtarRVS/bin ]; then
    PATH="/System/Tools/MixtarRVS/bin:$PATH"
    export PATH
fi
PROFILE
}

run_chroot_build() {
    cp "$PACKAGE" "$MOUNTPOINT/tmp/mixtarrvs-musl-src.tar.gz"
    chroot "$MOUNTPOINT" /bin/sh -c "
set -eu
apk add --no-cache build-base linux-headers musl-fts-dev zlib-dev libbsd-dev flex bison ncurses-dev perl gawk
rm -rf '$BUILD_DIR'
mkdir -p '$BUILD_DIR'
tar -xzf /tmp/mixtarrvs-musl-src.tar.gz -C '$BUILD_DIR'
cd '$BUILD_DIR'
sh out/mixtarrvs-musl/build-mixtarrvs-musl.sh
install -d -m 0755 '$TARGET/bin' '$TARGET/libexec' /System/Config/MixtarRVS
find '$TARGET/bin' -maxdepth 1 -name Current -exec rm -f {} +
cp out/mixtarrvs-musl-target/bin/* '$TARGET/bin/'
if [ -d out/mixtarrvs-musl-target/libexec ]; then
    cp out/mixtarrvs-musl-target/libexec/* '$TARGET/libexec/' 2>/dev/null || true
fi
find '$TARGET/bin' -maxdepth 1 -type f -exec chmod 0755 {} +
find '$TARGET/libexec' -maxdepth 1 -type f -exec chmod 0755 {} + 2>/dev/null || true
ln -sfn MixtarRVS /System/Tools/Current
cp out/mixtarrvs-musl-target/TOOLS /System/Config/MixtarRVS/userland-source-tools.txt
"
}

write_manifest() {
    count=$(find "$MOUNTPOINT$TARGET/bin" -maxdepth 1 -type f | wc -l | tr -d ' ')
    cat > "$MOUNTPOINT/System/Config/MixtarRVS/userland-source-only.manifest" <<EOF
MixtarRVS source-only userland
installed_from=Debian chroot
target=$TARGET/bin
tool_count=$count
placeholders=0
boot_policy=/bin and /sbin remain compatibility/bootstrap paths
EOF
}

main() {
    require_root
    require_debian
    if [ ! -r "$PACKAGE" ]; then
        echo "missing package: $PACKAGE" >&2
        return 1
    fi
    trap cleanup EXIT
    mount_mixtar
    bind_mount_runtime
    install_profile
    run_chroot_build
    write_manifest
    sync
    echo "MixtarRVS userland installed from source-only musl build"
}

main "$@"
