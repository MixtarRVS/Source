#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
readonly ROOT_OVERLAY="$REPO_ROOT/Root"

readonly RUNTIME_ROOT="${1:?runtime root is required}"
readonly MODULES_SOURCE="${2:?module source is required}"
readonly OPENZFS_ROOT="${3:?OpenZFS root stage is required}"
readonly OPENZFS_MODULES="${4:?OpenZFS modules are required}"
readonly RELEASE="${5:?kernel release is required}"
readonly SERVICE_DIRECTORY="${6:?OpenRC service directory is required}"
readonly ROOT_ARCHIVE="${7:?root archive is required}"
readonly SOURCE_DATE_EPOCH="${8:?source date epoch is required}"
readonly OPENSSL_ROOT="${9:?OpenSSL root stage is required}"
readonly PUBLIC_KEY="${10:?release public key is required}"
readonly RELEASE_NAME="${11:?release name is required}"
readonly RELEASE_SLOT="${12:?release slot is required}"

for path in \
  "$RUNTIME_ROOT" \
  "$ROOT_OVERLAY" \
  "$MODULES_SOURCE" \
  "$OPENZFS_ROOT" \
  "$OPENZFS_MODULES" \
  "$SERVICE_DIRECTORY" \
  "$OPENSSL_ROOT"; do
  [ -d "$path" ] || {
    printf 'Missing P1 source directory: %s\n' "$path" >&2
    exit 2
  }
done
for service in mixtar-console mixtar-platform; do
  [ -f "$SERVICE_DIRECTORY/$service" ] || {
    printf 'Missing P1 OpenRC service: %s\n' "$service" >&2
    exit 2
  }
done

work="$(mktemp -d /tmp/mixtar-p1.XXXXXX)"
cleanup() {
  case "$work" in
    /tmp/mixtar-p1.*) rm -rf -- "$work" ;;
  esac
}
trap cleanup EXIT
stage="$work/Root"
mkdir -p "$stage"
cp -a "$RUNTIME_ROOT/." "$stage/"
cp -a "$ROOT_OVERLAY/." "$stage/"
cp -a "$OPENZFS_ROOT/." "$stage/"
cp -a "$OPENSSL_ROOT/." "$stage/"

init_d="$stage/System/Configuration/OpenRC/init.d"
runlevel="$stage/System/Configuration/OpenRC/runlevels/default"
mkdir -p "$init_d" "$runlevel"
for source in "$SERVICE_DIRECTORY"/mixtar-*; do
  [ -f "$source" ] || continue
  name="${source##*/}"
  install -m0755 "$source" "$init_d/$name"
  ln -sfn "../../init.d/$name" "$runlevel/$name"
done
find "$stage/System/Core/Platform" -type f -exec chmod 0755 {} +
find "$stage/System/Core/Update" -type f -exec chmod 0755 {} +

module_target="$stage/System/Kernel/Linux/$RELEASE"
mkdir -p "$module_target"
cp -a "$MODULES_SOURCE/." "$module_target/"
cp -a "$OPENZFS_MODULES/." "$module_target/"
[ -f "$module_target/Development/Module.symvers" ] || {
  printf '%s\n' 'Kernel module SDK is missing Module.symvers' >&2
  exit 1
}
mkdir -p "$stage/System/Configuration/Release"
install -m0644 "$PUBLIC_KEY" "$stage/System/Configuration/Release/M1.public.pem"
cat >"$stage/System/Configuration/Release/Active.config" <<EOF
schema = "mixtar.active-release.v1"
release = "$RELEASE_NAME"
slot = "$RELEASE_SLOT"
dataset = "mixtar/ROOT/$RELEASE_SLOT"
EOF

/usr/sbin/depmod \
  --basedir "$stage" \
  --moduledir /System/Kernel/Linux \
  "$RELEASE"
[ -s "$module_target/modules.dep" ] || {
  printf 'P1 module dependency index was not generated\n' >&2
  exit 1
}

cat >"$init_d/zfs-root-proof" <<'EOF'
#!/System/Init/openrc-run
description="Confirm that Mixtar is running from the provisioned ZFS root"

depend() {
  before zsh-proof mixtar-platform mixtar-console
}

start() {
  ebegin "Checking Mixtar OpenZFS root"
  if ! /System/Commands/grep -q ' / zfs ' /System/Processes/mounts; then
    eend 1 'Root filesystem is not ZFS'
    return 1
  fi
  printf '%s\n' 'MixtarRVS: ZFS root ready'
  eend 0
}
EOF
chmod 0755 "$init_d/zfs-root-proof"
ln -sfn ../../init.d/zfs-root-proof "$runlevel/zfs-root-proof"

chown -hR 0:0 "$stage"
find "$stage" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
rm -f -- "$ROOT_ARCHIVE"
tar \
  --sort=name \
  --mtime="@$SOURCE_DATE_EPOCH" \
  --owner=0 \
  --group=0 \
  --numeric-owner \
  --format=posix \
  --pax-option=delete=atime,delete=ctime \
  -cf "$ROOT_ARCHIVE" \
  -C "$stage" .