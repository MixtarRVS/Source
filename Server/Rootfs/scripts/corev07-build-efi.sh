#!/usr/bin/env bash
set -euo pipefail

VERSION="0.8"
KERNEL_VERSION="7.1.2"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"

case "$repo_root" in
  /mnt/*)
    default_kernel_workspace="${HOME:-/tmp}/.cache/mixtarrvs-corev07/kernel"
    ;;
  *)
    default_kernel_workspace="$repo_root/Server/Kernel/Generated"
    ;;
esac

stage_root_script="$repo_root/Server/Rootfs/scripts/corev07-stage-root.sh"
kernel_workspace="${MIXTARRVS_COREV07_KERNEL_WORKSPACE:-$default_kernel_workspace}"
kernel_src="${KERNEL_SRC:-$kernel_workspace/src/linux-$KERNEL_VERSION}"
build_dir="${KERNEL_BUILD_DIR:-$kernel_workspace/build/linux-$KERNEL_VERSION-mixtar-rt}"
boot_dir="$repo_root/Server/Kernel/Generated/boot"
fragment="$repo_root/Server/Kernel/configs/mixtar-corev07-rt.fragment"
firmware_dir="$repo_root/Server/Kernel/Generated/firmware"
iwlwifi_firmware_name="iwlwifi-8265-36.ucode"
regulatory_db_name="regulatory.db"
regulatory_db_signature_name="regulatory.db.p7s"
embedded_firmware_names="$iwlwifi_firmware_name $regulatory_db_name $regulatory_db_signature_name"
stage_root="$repo_root/Server/Rootfs/Generated/corev07-root"
work_dir="$repo_root/Server/Rootfs/Generated/corev07-efi-build"
source_dir="$kernel_workspace/sources"
snapshot_url="https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/snapshot/linux-$KERNEL_VERSION.tar.gz"
snapshot_archive="$source_dir/linux-$KERNEL_VERSION.snapshot.tar.gz"
repo_snapshot_archive="$repo_root/Server/Kernel/Generated/sources/linux-$KERNEL_VERSION.snapshot.tar.gz"
initramfs_cpio="$work_dir/corev07-initramfs.cpio"
efi_artifact="$work_dir/MixtarRVS-$VERSION.efi"
provenance_file="$efi_artifact.provenance"
cmdline_file="$work_dir/corev07.cmdline"
base_cmdline="quiet loglevel=3 console=tty0 console=ttyS0,115200 fbcon=map:0 fbcon=nodefer rdinit=/System/Init/MixtarRVS init=/System/Init/MixtarRVS devtmpfs.mount=0"
cmdline_extra="${COREV07_CMDLINE_EXTRA:-}"
if [[ "${COREV07_AUTORETURN:-0}" == "1" ]]; then
  cmdline_extra="${cmdline_extra:+$cmdline_extra }mixtar.autoreturn=1 mixtar.persist_logs=1 panic=300"
fi
full_cmdline="$base_cmdline${cmdline_extra:+ $cmdline_extra}"

usage() {
  cat <<EOF
usage: corev07-build-efi.sh [plan|fetch|prepare|build|stage|verify|import PATH|all]

Builds the CoreV07 single EFI artifact locally:
  /System/EFI/MixtarRVS/$VERSION.efi

It writes only under:
  case-sensitive kernel workspace
  Server/Rootfs/Generated
  Server/Kernel/Generated/boot

It does not modify Debian, ESP, EFI variables, GRUB, boot order, or a live root.
EOF
}

fail() {
  echo "corev07-build-efi: error: $*" >&2
  exit 1
}

note() {
  echo "corev07-build-efi: $*"
}

ensure_case_sensitive_kernel_tree() {
  upper="$kernel_src/net/netfilter/xt_TCPMSS.c"
  lower="$kernel_src/net/netfilter/xt_tcpmss.c"
  [[ -f "$upper" ]] || fail "kernel tree missing case-sensitive file: $upper"
  [[ -f "$lower" ]] || fail "kernel tree missing case-sensitive file: $lower"
  upper_inode="$(stat -c '%d:%i' "$upper")"
  lower_inode="$(stat -c '%d:%i' "$lower")"
  [[ "$upper_inode" != "$lower_inode" ]] || fail "kernel source is on a case-insensitive filesystem; set MIXTARRVS_COREV07_KERNEL_WORKSPACE to a WSL/ext4 path"
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || fail "missing tool: $1"
}

plan() {
  cat <<EOF
CoreV07 EFI build plan:
  version:       $VERSION
  kernel:        Linux RT $KERNEL_VERSION
  source:        $kernel_src
  build:         $build_dir
  workspace:     $kernel_workspace
  firmware dir:  $firmware_dir
  firmware:      $embedded_firmware_names
  staged root:   $stage_root
  initramfs:     $initramfs_cpio
  artifact:      $efi_artifact
  final root:    /System/EFI/MixtarRVS/$VERSION.efi
  cmdline:       $full_cmdline

No Debian mutation:
  no apt
  no grub update
  no EFI variable writes
  no /boot/efi writes
  no live / writes
EOF
}

fetch_kernel() {
  require_tool curl
  require_tool tar
  if [[ -f "$kernel_src/Makefile" ]]; then
    ensure_case_sensitive_kernel_tree
    note "kernel source already present: $kernel_src"
    return 0
  fi
  if [[ -e "$kernel_src" ]]; then
    fail "kernel source path exists but has no Makefile: $kernel_src"
  fi

  mkdir -p "$(dirname "$kernel_src")" "$source_dir"
  tmp_src="$kernel_src.tmp-fetch"
  tmp_archive="$snapshot_archive.tmp"
  rm -rf "$tmp_src"

  if [[ ! -s "$snapshot_archive" && -s "$repo_snapshot_archive" ]]; then
    cp "$repo_snapshot_archive" "$snapshot_archive"
    note "copied existing snapshot from repo Generated to kernel workspace"
  fi

  if [[ ! -s "$snapshot_archive" ]]; then
    rm -f "$tmp_archive"
    note "downloading Linux stable snapshot v$KERNEL_VERSION"
    curl -L --fail --retry 3 --output "$tmp_archive" "$snapshot_url"
    mv "$tmp_archive" "$snapshot_archive"
  else
    note "snapshot already present: $snapshot_archive"
  fi

  mkdir -p "$tmp_src"
  tar -xzf "$snapshot_archive" -C "$tmp_src" --strip-components=1
  [[ -f "$tmp_src/Makefile" ]] || fail "snapshot did not extract to a Linux source tree"
  mv "$tmp_src" "$kernel_src"
  ensure_case_sensitive_kernel_tree
  note "kernel source ready: $kernel_src"
}

stage_root_if_needed() {
  note "staging CoreV07 root before initramfs"
  MIXTARRVS_COREV07_KERNEL_WORKSPACE="$kernel_workspace" \
  KERNEL_BUILD_DIR="$build_dir" \
    bash "$stage_root_script" stage
}

write_cmdline() {
  mkdir -p "$work_dir"
  cat > "$cmdline_file" <<EOF
$full_cmdline
EOF
}

build_initramfs_cpio() {
  require_tool find
  mkdir -p "$work_dir"
  [[ -d "$stage_root" ]] || fail "missing staged root: $stage_root"
  python3 - "$stage_root" "$initramfs_cpio" <<'PY'
import os
import pathlib
import stat
import sys
import time

root = pathlib.Path(sys.argv[1])
archive = pathlib.Path(sys.argv[2])
now = int(time.time())
ino = 1
entry_modes = {}

def align4_size(size: int) -> int:
    return (4 - (size % 4)) % 4

def header(name: str, mode: int, nlink: int, size: int, mtime: int, rmaj: int = 0, rmin: int = 0) -> bytes:
    global ino
    fields = [
        ino,
        mode,
        0,
        0,
        nlink,
        mtime,
        size,
        0,
        0,
        rmaj,
        rmin,
        len(name.encode("utf-8")) + 1,
        0,
    ]
    ino += 1
    raw = "070701" + "".join(f"{value:08x}" for value in fields)
    return raw.encode("ascii")

def write_entry(f, name: str, mode: int, nlink: int, data: bytes = b"", mtime: int = now, rmaj: int = 0, rmin: int = 0) -> None:
    entry_modes[name] = mode
    encoded_name = name.encode("utf-8") + b"\0"
    f.write(header(name, mode, nlink, len(data), mtime, rmaj, rmin))
    f.write(encoded_name)
    f.write(b"\0" * align4_size(110 + len(encoded_name)))
    f.write(data)
    f.write(b"\0" * align4_size(len(data)))

def relative_name(path: pathlib.Path) -> str:
    return path.relative_to(root).as_posix()

def directory_mode(name: str) -> int:
    if name == "Temporary":
        return stat.S_IFDIR | 0o1777
    parts = pathlib.PurePosixPath(name).parts
    if len(parts) == 2 and parts[0] == "Users":
        return stat.S_IFDIR | 0o700
    return stat.S_IFDIR | 0o755

def regular_mode(name: str, data: bytes) -> int:
    normalized = f"/{name}"
    if "/System/Configuration/SSH/HostKeys/" in normalized and not name.endswith(".pub"):
        return stat.S_IFREG | 0o600
    if data.startswith(b"\x7fELF") or data.startswith(b"#!"):
        return stat.S_IFREG | 0o755
    return stat.S_IFREG | 0o644

with archive.open("wb") as f:
    for current, dirs, files in os.walk(root, topdown=True, followlinks=False):
        current_path = pathlib.Path(current)
        dirs.sort()
        files.sort()
        if current_path == root:
            dirs[:] = [dirname for dirname in dirs if dirname != "System"]
            system_path = root / "System"
            if system_path.is_dir():
                write_entry(f, "System", stat.S_IFDIR | 0o755, 2, b"", int(os.lstat(system_path).st_mtime))
                for system_current, system_dirs, system_files in os.walk(system_path, topdown=True, followlinks=False):
                    system_current_path = pathlib.Path(system_current)
                    system_dirs.sort()
                    system_files.sort()
                    if system_current_path == system_path:
                        system_dirs[:] = [dirname for dirname in system_dirs if dirname != "EFI"]
                    kept_system_dirs = []
                    for dirname in system_dirs:
                        path = system_current_path / dirname
                        st = os.lstat(path)
                        name = relative_name(path)
                        if stat.S_ISLNK(st.st_mode):
                            target = os.readlink(path).encode("utf-8")
                            write_entry(f, name, stat.S_IFLNK | 0o777, 1, target, int(st.st_mtime))
                        else:
                            write_entry(f, name, directory_mode(name), 2, b"", int(st.st_mtime))
                            kept_system_dirs.append(dirname)
                    system_dirs[:] = kept_system_dirs
                    for filename in system_files:
                        path = system_current_path / filename
                        st = os.lstat(path)
                        name = relative_name(path)
                        if stat.S_ISLNK(st.st_mode):
                            target = os.readlink(path).encode("utf-8")
                            write_entry(f, name, stat.S_IFLNK | 0o777, 1, target, int(st.st_mtime))
                        elif stat.S_ISREG(st.st_mode):
                            data = path.read_bytes()
                            write_entry(f, name, regular_mode(name, data), 1, data, int(st.st_mtime))
        kept_dirs = []
        for dirname in dirs:
            path = current_path / dirname
            st = os.lstat(path)
            name = relative_name(path)
            if stat.S_ISLNK(st.st_mode):
                target = os.readlink(path).encode("utf-8")
                write_entry(f, name, stat.S_IFLNK | 0o777, 1, target, int(st.st_mtime))
            else:
                write_entry(f, name, directory_mode(name), 2, b"", int(st.st_mtime))
                kept_dirs.append(dirname)
        dirs[:] = kept_dirs
        for filename in files:
            path = current_path / filename
            st = os.lstat(path)
            name = relative_name(path)
            if stat.S_ISLNK(st.st_mode):
                target = os.readlink(path).encode("utf-8")
                write_entry(f, name, stat.S_IFLNK | 0o777, 1, target, int(st.st_mtime))
            elif stat.S_ISREG(st.st_mode):
                data = path.read_bytes()
                write_entry(f, name, regular_mode(name, data), 1, data, int(st.st_mtime))
    write_entry(f, "System/Devices/console", stat.S_IFCHR | 0o600, 1, rmaj=5, rmin=1)
    write_entry(f, "System/Devices/null", stat.S_IFCHR | 0o666, 1, rmaj=1, rmin=3)
    write_entry(f, "TRAILER!!!", 0, 1)

required_modes = {
    "Applications": stat.S_IFDIR | 0o755,
    "System": stat.S_IFDIR | 0o755,
    "System/Configuration": stat.S_IFDIR | 0o755,
    "System/Configuration/MixtarRVS.config": stat.S_IFREG | 0o644,
    "System/Logs": stat.S_IFDIR | 0o755,
    "System/Userland/reboot": stat.S_IFREG | 0o755,
    "System/Userland/poweroff": stat.S_IFREG | 0o755,
    "Temporary": stat.S_IFDIR | 0o1777,
    "Users": stat.S_IFDIR | 0o755,
    "Volumes": stat.S_IFDIR | 0o755,
}
for name, expected_mode in required_modes.items():
    actual_mode = entry_modes.get(name)
    if actual_mode != expected_mode:
        raise SystemExit(
            f"initramfs permission policy failed for {name}: "
            f"expected {expected_mode:o}, got {actual_mode if actual_mode is None else format(actual_mode, 'o')}"
        )
for name, mode in entry_modes.items():
    if stat.S_ISREG(mode) and mode & 0o6000:
        raise SystemExit(f"initramfs permission policy failed: privileged mode on {name}")
    if stat.S_ISREG(mode) and mode & 0o022:
        raise SystemExit(f"initramfs permission policy found writable regular file: {name} mode={mode:o}")
PY
  note "wrote $initramfs_cpio"
}

prepare_config() {
  require_tool make
  [[ -f "$kernel_src/Makefile" ]] || fail "missing kernel source: $kernel_src"
  [[ -f "$fragment" ]] || fail "missing config fragment: $fragment"
  for firmware_name in $embedded_firmware_names; do
    firmware_file="$firmware_dir/$firmware_name"
    [[ -s "$firmware_file" ]] || fail "missing embedded firmware/regdb artifact: $firmware_file"
  done
  ensure_case_sensitive_kernel_tree

  mkdir -p "$build_dir"
  make -C "$kernel_src" O="$build_dir" x86_64_defconfig
  "$kernel_src/scripts/kconfig/merge_config.sh" -m -O "$build_dir" "$build_dir/.config" "$fragment"

  "$kernel_src/scripts/config" --file "$build_dir/.config" \
    --set-str INITRAMFS_SOURCE "$initramfs_cpio" \
    --set-str CMDLINE "$full_cmdline" \
    --set-str EXTRA_FIRMWARE "$embedded_firmware_names" \
    --set-str EXTRA_FIRMWARE_DIR "$firmware_dir" \
    --enable CMDLINE_BOOL \
    --enable CMDLINE_OVERRIDE \
    --enable FW_LOADER

  make -C "$kernel_src" O="$build_dir" olddefconfig
  note "prepared $build_dir/.config"
}

build_kernel_efi() {
  require_tool make
  jobs="${JOBS:-$(nproc)}"
  make -C "$kernel_src" O="$build_dir" -j"$jobs" bzImage

  image="$build_dir/arch/x86/boot/bzImage"
  [[ -s "$image" ]] || fail "missing built bzImage: $image"

  mkdir -p "$boot_dir" "$work_dir"
  cp "$image" "$boot_dir/bzImage-$KERNEL_VERSION-mixtar-rt"
  cp "$image" "$efi_artifact"
  chmod 0644 "$efi_artifact"
  note "wrote $efi_artifact"
  write_build_provenance
}

write_build_provenance() {
  require_tool sha256sum
  [[ -s "$efi_artifact" ]] || fail "cannot write provenance without EFI artifact: $efi_artifact"
  [[ -s "$initramfs_cpio" ]] || fail "cannot write provenance without initramfs: $initramfs_cpio"
  [[ -s "$cmdline_file" ]] || fail "cannot write provenance without cmdline: $cmdline_file"
  [[ -s "$build_dir/.config" ]] || fail "cannot write provenance without kernel config: $build_dir/.config"

  efi_hash="$(sha256sum "$efi_artifact" | awk '{print $1}')"
  initramfs_hash="$(sha256sum "$initramfs_cpio" | awk '{print $1}')"
  cmdline_hash="$(sha256sum "$cmdline_file" | awk '{print $1}')"
  kernel_config_hash="$(sha256sum "$build_dir/.config" | awk '{print $1}')"
  built_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  cat > "$provenance_file" <<EOF
format=MixtarRVS-EFI-Provenance-v1
core=CoreV07
release=$VERSION
source_mode=build
builder=corev07-build-efi.sh
kernel_family=Linux
kernel_profile=RT
kernel_version=$KERNEL_VERSION
efi_sha256=$efi_hash
initramfs_sha256=$initramfs_hash
cmdline_sha256=$cmdline_hash
kernel_config_sha256=$kernel_config_hash
cmdline=$full_cmdline
built_at_utc=$built_at
EOF
  chmod 0644 "$provenance_file"
  note "wrote $provenance_file"
}
stage_efi() {
  [[ -s "$efi_artifact" ]] || fail "missing EFI artifact: $efi_artifact"
  bash "$stage_root_script" stage --efi-source "$efi_artifact"
}

verify_efi() {
  [[ -s "$efi_artifact" ]] || fail "missing EFI artifact: $efi_artifact"
  magic="$(dd if="$efi_artifact" bs=2 count=1 2>/dev/null || true)"
  [[ "$magic" == "MZ" ]] || fail "EFI artifact does not start with MZ PE header"
  bash "$stage_root_script" verify
}

import_efi() {
  src=${1:-}
  [[ -n "$src" ]] || fail "import requires a source EFI path"
  [[ -s "$src" ]] || fail "source EFI missing or empty: $src"
  magic="$(dd if="$src" bs=2 count=1 2>/dev/null || true)"
  [[ "$magic" == "MZ" ]] || fail "source EFI does not start with MZ PE header"

  mkdir -p "$work_dir"
  cp "$src" "$efi_artifact"
  chmod 0644 "$efi_artifact"
  note "imported $src -> $efi_artifact"
  stage_efi
  verify_efi
}

prepare() {
  stage_root_if_needed
  write_cmdline
  prepare_config
  stage_root_if_needed
  build_initramfs_cpio
}

case "${1:-plan}" in
  plan)
    plan
    ;;
  fetch)
    fetch_kernel
    ;;
  prepare)
    prepare
    ;;
  build)
    prepare
    build_kernel_efi
    ;;
  stage)
    stage_efi
    ;;
  verify)
    verify_efi
    ;;
  import)
    import_efi "${2:-}"
    ;;
  all)
    plan
    fetch_kernel
    prepare
    build_kernel_efi
    stage_efi
    verify_efi
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
