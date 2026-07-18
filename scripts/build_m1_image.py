from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import tomllib
from pathlib import Path
from typing import Any, Callable, TypeVar

REPOSITORY = Path(__file__).resolve().parent.parent
OUTPUT_ROOT = (REPOSITORY / "Output").resolve()
sys.path.insert(0, str(REPOSITORY))
sys.path.insert(0, str(REPOSITORY / "scripts"))

from mixtar_builder.fat import write_fat32
from mixtar_builder.gpt import write_gpt_disk
from mixtar_builder.kernel_build import build_linux_kernel
from mixtar_builder.kernel_source import prepare_kernel_source
from mixtar_builder.wsl import linux_path
from mixtar_release import load as load_release

T = TypeVar("T")


class M1Error(RuntimeError):
    pass


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def repository_artifact_path(path: Path) -> str:
    resolved = path.resolve(strict=True)
    for root, prefix in (
        (REPOSITORY, Path()),
        (OUTPUT_ROOT, Path("Output")),
    ):
        try:
            relative = resolved.relative_to(root)
        except ValueError:
            continue
        return (prefix / relative).as_posix()
    raise M1Error(f"artifact is outside the repository and Output/: {path}")


def artifact(path: Path, kind: str) -> dict[str, Any]:
    return {
        "format": kind,
        "path": repository_artifact_path(path),
        "sha256": sha256(path),
        "size": path.stat().st_size,
    }


def run(command: list[str], timeout: int = 600) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        command, cwd=REPOSITORY, check=False, capture_output=True, text=True,
        timeout=timeout,
    )
    if result.returncode:
        detail = result.stderr.strip() or result.stdout.strip()
        raise M1Error(f"command failed ({command[0]}): {detail}")
    return result


def timed(timings: dict[str, float], name: str, operation: Callable[[], T]) -> T:
    started = time.monotonic()
    try:
        return operation()
    finally:
        timings[name] = round(time.monotonic() - started, 6)


def load_toml(path: Path) -> dict[str, Any]:
    with path.open("rb") as stream:
        return tomllib.load(stream)


def tool(name: str) -> Path:
    found = shutil.which(name)
    if found:
        return Path(found)
    candidate = Path(os.environ.get("ProgramFiles", r"C:\Program Files")) / "qemu" / name
    if candidate.is_file():
        return candidate
    raise M1Error(f"required tool is missing: {name}")


def wsl_cache_home(distribution: str, namespace: str) -> str:
    result = run([
        "wsl.exe", "-d", distribution, "--", "/bin/sh", "-lc",
        'printf %s "${XDG_CACHE_HOME:-$HOME/.cache}"',
    ], timeout=30)
    value = result.stdout.strip()
    if not value.startswith("/") or value == "/":
        raise M1Error(f"unsafe WSL cache home: {value!r}")
    return f"{value.rstrip('/')}/{namespace}" if namespace else value


def build_openzfs(
    layout: dict[str, Any], lock: dict[str, Any], cache_home: str,
    release: str, output: Path, jobs: int, key: Path, certificate: Path,
) -> tuple[Path, Path, dict[str, Any]]:
    item = lock["openzfs"]
    native = f"{cache_home.rstrip('/')}/mixtar/kernel"
    run([
        "wsl.exe", "-d", layout["build"]["wsl_distro"], "--", "/bin/bash",
        linux_path(REPOSITORY / "scripts" / "build-openzfs-mixtar.sh"),
        item["version"], item["url"], item["sha256"],
        f"{native}/sources/current-x86_64", f"{native}/builds/current-x86_64",
        release, linux_path(output), str(layout["boot"]["source_date_epoch"]),
        str(jobs), linux_path(key), linux_path(certificate),
        linux_path(REPOSITORY / item["patch"]), item["patch_sha256"],
    ], timeout=3600)
    manifest = output / "Build.json"
    if not manifest.is_file():
        raise M1Error("OpenZFS build manifest is missing")
    return output / "Root", output / "Modules", json.loads(manifest.read_text(encoding="utf-8"))


def build_openssl(
    layout: dict[str, Any], lock: dict[str, Any], cache_home: str,
    output: Path, jobs: int,
) -> tuple[Path, dict[str, Any]]:
    item = lock["openssl"]
    run([
        "wsl.exe", "-d", layout["build"]["wsl_distro"], "--", "/usr/bin/env",
        f"XDG_CACHE_HOME={cache_home}", "/bin/bash",
        linux_path(REPOSITORY / "scripts" / "build-openssl-mixtar.sh"),
        item["version"], item["url"], item["sha256"], linux_path(output),
        str(layout["boot"]["source_date_epoch"]), str(jobs),
    ], timeout=3600)
    manifest = output / "Build.json"
    if not manifest.is_file():
        raise M1Error("OpenSSL build manifest is missing")
    return output / "Root", json.loads(manifest.read_text(encoding="utf-8"))


def build_initramfs(
    layout: dict[str, Any], runtime: str, zfs_root: Path, zfs_modules: Path,
    release: str, output: Path, volume: dict[str, Any], slot: str,
) -> None:
    run([
        "wsl.exe", "-d", layout["build"]["wsl_distro"], "-u", "root", "--",
        "/bin/bash", linux_path(REPOSITORY / "scripts" / "build-zfs-initramfs.sh"),
        runtime, linux_path(zfs_root), linux_path(zfs_modules), release,
        linux_path(output), str(layout["boot"]["source_date_epoch"]), volume["pool"],
        f"{volume['pool']}/ROOT/{slot}", str(volume["ashift"]),
        volume["compression"], slot,
    ], timeout=600)


def build_recovery(
    layout: dict[str, Any], runtime: str, zfs_root: Path, zfs_modules: Path,
    release: str, output: Path, pool: str,
) -> None:
    run([
        "wsl.exe", "-d", layout["build"]["wsl_distro"], "-u", "root", "--",
        "/bin/bash", linux_path(REPOSITORY / "scripts" / "build-zfs-recovery-initramfs.sh"),
        runtime, linux_path(zfs_root), linux_path(zfs_modules), release,
        linux_path(output), str(layout["boot"]["source_date_epoch"]), pool,
        f"{pool}/STATE/system",
    ], timeout=600)


def product_root_source() -> Path | None:
    value = os.environ.get("MIXTAR_PREBUILT_ROOT_ARCHIVE")
    if not value:
        return None
    source_input = Path(value).expanduser()
    if source_input.is_symlink() or not source_input.is_file():
        raise M1Error(
            "MIXTAR_PREBUILT_ROOT_ARCHIVE must name a physical root archive"
        )
    source = source_input.resolve(strict=True)
    if not source.is_file():
        raise M1Error(
            "MIXTAR_PREBUILT_ROOT_ARCHIVE does not resolve to a regular file"
        )
    return source


def copy_product_root(source: Path, output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_name(output.name + ".product.tmp")
    temporary.unlink(missing_ok=True)
    try:
        shutil.copyfile(source, temporary)
        os.replace(temporary, output)
    finally:
        temporary.unlink(missing_ok=True)


def build_root(
    layout: dict[str, Any], runtime: str, modules: Path, zfs_root: Path,
    zfs_modules: Path, openssl_root: Path, public_key: Path, release: str,
    slot: str, output: Path,
) -> None:
    # Product builds may provide an already staged root while the default M1
    # path remains fully self-contained and unchanged.
    prebuilt_root = product_root_source()
    if prebuilt_root is not None:
        copy_product_root(prebuilt_root, output)
        return
    services = REPOSITORY / "Root" / "System" / "Configuration" / "OpenRC" / "init.d"
    run([
        "wsl.exe", "-d", layout["build"]["wsl_distro"], "-u", "root", "--",
        "/bin/bash", linux_path(REPOSITORY / "scripts" / "build-p1-root.sh"),
        runtime, linux_path(modules), linux_path(zfs_root), linux_path(zfs_modules),
        release, linux_path(services), linux_path(output),
        str(layout["boot"]["source_date_epoch"]), linux_path(openssl_root),
        linux_path(public_key), "M1", slot,
    ], timeout=600)


def sign_efi(distribution: str, source: Path, output: Path, key: Path, certificate: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    token = hashlib.sha256(str(output).encode("utf-8")).hexdigest()[:16]
    temporary = f"/tmp/mixtar-signed-{token}.efi"
    run(["wsl.exe", "-d", distribution, "--", "/bin/rm", "-f", temporary], timeout=30)
    try:
        run([
            "wsl.exe", "-d", distribution, "--", "/usr/bin/sbsign", "--key",
            linux_path(key), "--cert", linux_path(certificate), "--output",
            temporary, linux_path(source),
        ], timeout=180)
        run([
            "wsl.exe", "-d", distribution, "--", "/usr/bin/sbverify", "--cert",
            linux_path(certificate), temporary,
        ], timeout=60)
        run([
            "wsl.exe", "-d", distribution, "--", "/usr/bin/install", "-m", "0644",
            temporary, linux_path(output),
        ], timeout=180)
        run([
            "wsl.exe", "-d", distribution, "--", "/usr/bin/sbverify", "--cert",
            linux_path(certificate), linux_path(output),
        ], timeout=60)
    finally:
        subprocess.run(
            ["wsl.exe", "-d", distribution, "--", "/bin/rm", "-f", temporary],
            cwd=REPOSITORY, check=False, capture_output=True, timeout=30,
        )


def sign_file(
    distribution: str, source: Path, signature: Path, key: Path, public_key: Path,
) -> None:
    signature.parent.mkdir(parents=True, exist_ok=True)
    run([
        "wsl.exe", "-d", distribution, "--", "/usr/bin/openssl", "dgst",
        "-sha256", "-sign", linux_path(key), "-out", linux_path(signature),
        linux_path(source),
    ], timeout=60)
    run([
        "wsl.exe", "-d", distribution, "--", "/usr/bin/openssl", "dgst",
        "-sha256", "-verify", linux_path(public_key), "-signature",
        linux_path(signature), linux_path(source),
    ], timeout=60)


def fat_volume(
    files: dict[str, Path], output: Path, label: str, minimum_mib: int = 64,
) -> dict[str, Any]:
    total = sum(path.stat().st_size for path in files.values())
    size_mib = max(minimum_mib, (total + 1024 * 1024 - 1) // (1024 * 1024) + 24)
    with tempfile.TemporaryDirectory(prefix="mixtar-m1-fat-") as temporary:
        root = Path(temporary)
        directories: set[str] = set()
        records: list[dict[str, Any]] = []
        for relative, source in files.items():
            target = root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
            parent = target.parent
            while parent != root:
                directories.add(parent.relative_to(root).as_posix())
                parent = parent.parent
            records.append({"path": relative, "mode": "0644", "uid": 0, "gid": 0})
        return write_fat32(
            root, {"directories": sorted(directories), "files": records},
            output, size_mib, label,
        )


def update_bundles(
    distribution: str, root_archive: Path, efi: Path, output: Path,
    key: Path, public_key: Path, slot: str, name: str, version: str,
) -> tuple[dict[str, Any], dict[str, Any]]:
    with tempfile.TemporaryDirectory(prefix="mixtar-m1-update-") as temporary:
        work = Path(temporary)
        manifest = work / "Update.config"
        signature = work / "Update.sig"
        manifest.write_bytes(
            "\n".join((
                'schema = "mixtar.update.v1"',
                f'release = "{version}"',
                f'slot = "{slot}"',
                f'dataset = "mixtar/ROOT/{slot}"',
                f'root_sha256 = "{sha256(root_archive)}"',
                f'efi_sha256 = "{sha256(efi)}"',
                "",
            )).encode("ascii")
        )
        sign_file(distribution, manifest, signature, key, public_key)
        update_name = (
            f"{name}-{slot}"
            if slot.startswith(f"{version}-")
            else f"{name}-{version}-{slot}"
        )
        valid_path = output / f"{update_name}.update.fat"
        valid = fat_volume({
            "Update.config": manifest, "Update.sig": signature,
            "root.tar": root_archive, "BOOTX64.EFI": efi,
        }, valid_path, "MIXTARUPD")
        corrupted_root = work / "root.corrupt.tar"
        shutil.copyfile(root_archive, corrupted_root)
        with corrupted_root.open("ab") as stream:
            stream.write(b"MIXTAR-CORRUPTED-UPDATE")
        corrupt_path = output / f"{update_name}.corrupt-update.fat"
        corrupt = fat_volume({
            "Update.config": manifest, "Update.sig": signature,
            "root.tar": corrupted_root, "BOOTX64.EFI": efi,
        }, corrupt_path, "MIXTARUPD")
    return (
        {**valid, "path": repository_artifact_path(valid_path)},
        {**corrupt, "path": repository_artifact_path(corrupt_path)},
    )


def provision_zfs(
    kernel: Path, disk: Path, payload: Path, output: Path,
    memory_mib: int, timeout_seconds: int,
) -> dict[str, Any]:
    log = output / "Qemu-zfs-provision.log"
    command = [
        str(tool("qemu-system-x86_64.exe")), "-machine", "q35,accel=tcg",
        "-cpu", "max", "-smp", "2", "-m", str(memory_mib),
        "-kernel", str(kernel), "-append",
        "console=ttyS0,115200n8 mixtar.zfs.provision=1",
        "-drive", f"if=virtio,format=raw,file={disk}",
        "-drive", f"if=virtio,format=raw,readonly=on,file={payload}",
        "-display", "none", "-serial", "stdio", "-monitor", "none", "-no-reboot",
    ]
    started = time.monotonic()
    try:
        result = subprocess.run(
            command, cwd=REPOSITORY, check=False, capture_output=True,
            timeout=timeout_seconds,
        )
    except subprocess.TimeoutExpired as error:
        data = (error.stdout or b"") + (error.stderr or b"")
        log.write_bytes(data)
        raise M1Error(f"ZFS provisioning timed out; console: {log}") from error
    data = result.stdout + result.stderr
    log.write_bytes(data)
    markers = {
        "snapshot_rollback": b"MixtarRVS: ZFS snapshot rollback ok" in data,
        "scrub": b"MixtarRVS: ZFS scrub ok" in data,
        "provision_complete": b"MixtarRVS: ZFS provision complete" in data,
    }
    report = {
        "schema": "mixtar.m1-zfs-provision.v1",
        "passed": result.returncode == 0 and all(markers.values()),
        "exit_code": result.returncode,
        "duration_seconds": round(time.monotonic() - started, 3),
        "markers": markers,
        "raw_log": repository_artifact_path(log),
    }
    (output / "Qemu-zfs-provision.json").write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    if not report["passed"]:
        raise M1Error("QEMU ZFS provisioning failed")
    return report


def convert_vhdx(disk: Path, output: Path) -> None:
    output.unlink(missing_ok=True)
    run([
        str(tool("qemu-img.exe")), "convert", "-f", "raw", "-S", "0",
        "-O", "vhdx", "-o", "subformat=dynamic", str(disk), str(output),
    ], timeout=300)
    materialized = output.with_name(output.name + ".materialized")
    materialized.unlink(missing_ok=True)
    try:
        with output.open("rb") as source, materialized.open("xb") as target:
            shutil.copyfileobj(source, target, length=1024 * 1024)
        os.replace(materialized, output)
    finally:
        materialized.unlink(missing_ok=True)


def build_product_image_from_base(
    profile: dict[str, Any],
    layout: dict[str, Any],
    lock: dict[str, Any],
    lock_path: Path,
    distribution: str,
    key: Path,
    certificate: Path,
    public_key: Path,
    output: Path,
    name: str,
    version: str,
    architecture: str,
    stem: str,
    volume: dict[str, Any],
    efi_volume: dict[str, Any],
    slot_a: str,
    slot_b: str,
    root_archive: Path,
    payload: Path,
    efi_a: Path,
    efi_b: Path,
    recovery_efi: Path,
    esp: Path,
    blank: Path,
    disk: Path,
    vhdx: Path,
    timings: dict[str, float],
) -> dict[str, Any]:
    base_version = lock["release"]["version"]
    base_stem = f"{name}-{base_version}-{architecture}"
    base_output = REPOSITORY / profile["output"]["directory"] / "P1"
    base_manifest_path = base_output / f"{base_stem}.manifest.json"
    base_signature = base_output / f"{base_stem}.manifest.sig"
    for path, description in (
        (base_manifest_path, "base P1 manifest"),
        (base_signature, "base P1 manifest signature"),
    ):
        if path.is_symlink() or not path.is_file():
            raise M1Error(f"{description} is missing or not physical: {path}")

    timed(
        timings,
        "verify_base_manifest",
        lambda: run([
            "wsl.exe", "-d", distribution, "--", "/usr/bin/openssl", "dgst",
            "-sha256", "-verify", linux_path(public_key), "-signature",
            linux_path(base_signature), linux_path(base_manifest_path),
        ], timeout=60),
    )
    base_manifest = json.loads(base_manifest_path.read_text(encoding="utf-8"))
    if base_manifest.get("schema") != "mixtar.m1-image.v1":
        raise M1Error("base P1 manifest schema is unsupported")
    if base_manifest.get("system") != {"name": name, "version": base_version}:
        raise M1Error("base P1 manifest identity does not match the release lock")
    base_artifacts = base_manifest.get("artifacts")
    if not isinstance(base_artifacts, dict):
        raise M1Error("base P1 manifest has no artifacts")

    def copy_base_artifact(key_name: str, target: Path) -> Path:
        record = base_artifacts.get(key_name)
        if not isinstance(record, dict):
            raise M1Error(f"base P1 manifest lacks {key_name}")
        relative = record.get("path")
        expected_hash = record.get("sha256")
        if not isinstance(relative, str) or not isinstance(expected_hash, str):
            raise M1Error(f"base P1 {key_name} record is incomplete")
        source_input = REPOSITORY / relative
        if source_input.is_symlink() or not source_input.is_file():
            raise M1Error(f"base P1 {key_name} is missing or not physical")
        source = source_input.resolve(strict=True)
        try:
            source.relative_to(base_output.resolve())
        except ValueError as error:
            raise M1Error(f"base P1 {key_name} escapes Output/P1") from error
        if sha256(source) != expected_hash:
            raise M1Error(f"base P1 {key_name} hash mismatch")
        target.parent.mkdir(parents=True, exist_ok=True)
        temporary = target.with_name(target.name + ".base.tmp")
        temporary.unlink(missing_ok=True)
        try:
            shutil.copyfile(source, temporary)
            os.replace(temporary, target)
        finally:
            temporary.unlink(missing_ok=True)
        if sha256(target) != expected_hash:
            raise M1Error(f"copied P1 {key_name} hash mismatch")
        return target

    timed(timings, "reuse_efi_a", lambda: copy_base_artifact("efi_a", efi_a))
    timed(timings, "reuse_efi_b", lambda: copy_base_artifact("efi_b", efi_b))
    timed(
        timings,
        "reuse_recovery_efi",
        lambda: copy_base_artifact("recovery_efi", recovery_efi),
    )

    def verify_reused_efi(path: Path) -> None:
        run([
            "wsl.exe", "-d", distribution, "--", "/usr/bin/sbverify", "--cert",
            linux_path(certificate), linux_path(path),
        ], timeout=60)

    timed(timings, "verify_efi_a", lambda: verify_reused_efi(efi_a))
    timed(timings, "verify_efi_b", lambda: verify_reused_efi(efi_b))
    timed(
        timings,
        "verify_recovery_efi",
        lambda: verify_reused_efi(recovery_efi),
    )

    root_source = product_root_source()
    if root_source is None:
        raise M1Error("fast product image requires MIXTAR_PREBUILT_ROOT_ARCHIVE")
    timed(
        timings,
        "root_archive",
        lambda: copy_product_root(root_source, root_archive),
    )
    payload_result = timed(
        timings,
        "payload",
        lambda: fat_volume({"root.tar": root_archive}, payload, "MIXTARDATA"),
    )
    with blank.open("wb") as stream:
        stream.truncate(int(volume["size_mib"]) * 1024 * 1024)

    esp_files = {
        "EFI/BOOT/BOOTX64.EFI": efi_a,
        "EFI/Mixtar/Recovery.EFI": recovery_efi,
        "EFI/Mixtar/M1.pem": certificate,
    }
    update_headroom = 2 * max(efi_a.stat().st_size, efi_b.stat().st_size)
    transactional_bytes = (
        sum(path.stat().st_size for path in esp_files.values())
        + update_headroom
    )
    transactional_mib = (
        (transactional_bytes + 1024 * 1024 - 1) // (1024 * 1024)
        + 24
    )
    esp_size_mib = max(int(efi_volume["size_mib"]), transactional_mib)
    esp_result = timed(
        timings,
        "esp",
        lambda: fat_volume(
            esp_files,
            esp,
            efi_volume["label"],
            esp_size_mib,
        ),
    )
    disk_result = timed(
        timings,
        "gpt",
        lambda: write_gpt_disk(
            esp,
            blank,
            disk,
            f"{name}:{version}:core",
            volume["label"],
            volume["typecode"],
            False,
        ),
    )
    provision = timed(
        timings,
        "zfs_provision",
        lambda: provision_zfs(
            efi_a,
            disk,
            payload,
            output,
            int(layout["boot"]["qemu_memory_mib"]),
            int(layout["boot"]["qemu_timeout_seconds"]) + 180,
        ),
    )
    valid_update, corrupt_update = timed(
        timings,
        "update_bundles",
        lambda: update_bundles(
            distribution,
            root_archive,
            efi_b,
            output,
            key,
            public_key,
            slot_b,
            name,
            version,
        ),
    )
    timed(timings, "vhdx", lambda: convert_vhdx(disk, vhdx))

    kernel = base_manifest.get("kernel")
    openzfs = base_manifest.get("openzfs")
    openssl = base_manifest.get("openssl")
    if not all(isinstance(value, dict) for value in (kernel, openzfs, openssl)):
        raise M1Error("base P1 manifest lacks kernel, OpenZFS, or OpenSSL data")
    manifest: dict[str, Any] = {
        "schema": "mixtar.core-image.v1",
        "system": {"name": name, "version": version},
        "target": {"architecture": architecture, "firmware": "UEFI"},
        "base_release": {
            "version": base_version,
            "manifest": repository_artifact_path(base_manifest_path),
            "manifest_sha256": sha256(base_manifest_path),
            "manifest_signature": repository_artifact_path(base_signature),
        },
        "release_lock": {
            "path": repository_artifact_path(lock_path),
            "sha256": sha256(lock_path),
        },
        "boot": {
            "firmware_path": "\\EFI\\BOOT\\BOOTX64.EFI",
            "logical_path": profile["boot"]["efi"],
            "active_slot": slot_a,
            "recovery_path": "/System/EFI/Mixtar/Recovery.EFI",
            "secure_boot_signed": True,
            "transactional_esp_mib": esp_size_mib,
            "previous_firmware_created_on_update": True,
            "reused_from_base_release": True,
        },
        "kernel": kernel,
        "openzfs": openzfs,
        "openssl": openssl,
        "update": {
            "schema": "mixtar.update.v1",
            "primary_slot": slot_a,
            "candidate_slot": slot_b,
            "previous_release_preserved": True,
            "transaction_state": layout["update"]["transaction_state"],
        },
        "artifacts": {
            "esp": {**esp_result, "path": repository_artifact_path(esp)},
            "efi_a": artifact(efi_a, "pe-coff-efi"),
            "efi_b": artifact(efi_b, "pe-coff-efi"),
            "recovery_efi": artifact(recovery_efi, "pe-coff-efi"),
            "root_archive": artifact(root_archive, "tar"),
            "payload": {
                **payload_result,
                "path": repository_artifact_path(payload),
            },
            "root": {
                "format": "openzfs",
                "pool": volume["pool"],
                "dataset": f"{volume['pool']}/ROOT/{slot_a}",
                "readonly": True,
            },
            "disk": {
                **disk_result,
                **artifact(
                    disk,
                    str(disk_result.get("format", "gpt-raw")),
                ),
            },
            "vhdx": artifact(vhdx, "vhdx-dynamic"),
            "update": valid_update,
            "corrupt_update": corrupt_update,
        },
        "zfs_provision": provision,
        "timings_seconds": timings,
    }
    manifest_path = output / f"{stem}.manifest.json"
    manifest_path.write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    signature = output / f"{stem}.manifest.sig"
    timed(
        timings,
        "manifest_signature",
        lambda: sign_file(
            distribution,
            manifest_path,
            signature,
            key,
            public_key,
        ),
    )
    return {
        "manifest": str(manifest_path),
        "manifest_signature": str(signature),
        "disk": str(disk),
        "vhdx": str(vhdx),
        "efi_a": str(efi_a),
        "efi_b": str(efi_b),
        "recovery_efi": str(recovery_efi),
        "update": str(REPOSITORY / valid_update["path"]),
        "corrupt_update": str(REPOSITORY / corrupt_update["path"]),
    }


def build(
    profile_path: Path, lock_path: Path, key: Path, certificate: Path,
    public_key: Path, cache_namespace: str,
) -> dict[str, Any]:
    timings: dict[str, float] = {}
    profile = load_toml(profile_path)
    layout = load_toml(REPOSITORY / "Root" / "System" / "Configuration" / "Layout.config")
    lock = load_release(lock_path)
    for path in (key, certificate, public_key):
        if not path.is_file():
            raise M1Error(f"signing input is missing: {path}")
    p0_path = REPOSITORY / layout["build"]["p0_output"] / "Build.json"
    if not p0_path.is_file():
        raise M1Error("P0 build manifest is missing")
    p0 = json.loads(p0_path.read_text(encoding="utf-8"))
    release = p0["sources"]["linux"]["release"]
    if release != lock["linux"]["version"] or "-rc" in release:
        raise M1Error("P0 kernel does not match the M1 release lock")
    distribution = layout["build"]["wsl_distro"]
    cache_home = wsl_cache_home(distribution, cache_namespace)
    runtime = f"{cache_home.rstrip('/')}/mixtar/firstboot/root"
    jobs_value = layout["build"]["jobs"]
    jobs = (os.cpu_count() or 1) if jobs_value == "auto" else int(jobs_value)
    default_output = REPOSITORY / profile["output"]["directory"] / "P1"
    product_output_value = os.environ.get("MIXTAR_IMAGE_OUTPUT_DIRECTORY")
    if product_output_value:
        product_output_input = Path(product_output_value).expanduser()
        if product_output_input.is_symlink():
            raise M1Error(
                "MIXTAR_IMAGE_OUTPUT_DIRECTORY cannot be a symbolic link"
            )
        output = product_output_input.resolve()
        product_output_root = (REPOSITORY / "Output" / "P4").resolve()
        try:
            output.relative_to(product_output_root)
        except ValueError as error:
            raise M1Error(
                "MIXTAR_IMAGE_OUTPUT_DIRECTORY must be below Output/P4"
            ) from error
    else:
        output = default_output
    output.mkdir(parents=True, exist_ok=True)
    name = profile["system"]["name"]
    version = os.environ.get(
        "MIXTAR_PRODUCT_VERSION",
        lock["release"]["version"],
    )
    if not version or any(
        not (character.isalnum() or character in ".-_")
        for character in version
    ):
        raise M1Error("MIXTAR_PRODUCT_VERSION is not a safe release identifier")
    architecture = profile["target"]["architecture"]
    stem = f"{name}-{version}-{architecture}"
    volume = profile["volumes"]["root"]
    efi_volume = profile["volumes"]["efi"]
    slot_a = lock["release"]["primary_slot"]
    slot_b = lock["release"]["update_slot"]
    root_archive = output / f"{stem}.root.tar"
    payload = output / f"{stem}.payload.fat"
    initramfs_a = output / f"{stem}.{slot_a}.initramfs.cpio"
    initramfs_b = output / f"{stem}.{slot_b}.initramfs.cpio"
    recovery_initramfs = output / f"{stem}.recovery.initramfs.cpio"
    efi_a = output / f"{stem}.{slot_a}.EFI"
    efi_b = output / f"{stem}.{slot_b}.EFI"
    recovery_efi = output / f"{stem}.Recovery.EFI"
    esp = output / f"{stem}.esp.fat"
    blank = output / f"{stem}.root.zfs.blank"
    disk = output / f"{stem}.disk.img"
    vhdx = output / f"{stem}.vhdx"
    if os.environ.get("MIXTAR_REUSE_BASE_BOOT") == "1":
        return build_product_image_from_base(
            profile,
            layout,
            lock,
            lock_path,
            distribution,
            key,
            certificate,
            public_key,
            output,
            name,
            version,
            architecture,
            stem,
            volume,
            efi_volume,
            slot_a,
            slot_b,
            root_archive,
            payload,
            efi_a,
            efi_b,
            recovery_efi,
            esp,
            blank,
            disk,
            vhdx,
            timings,
        )


    zfs_root, zfs_modules, zfs_manifest = timed(
        timings, "openzfs",
        lambda: build_openzfs(
            layout, lock, cache_home, release, output / "OpenZFS", jobs,
            key, certificate,
        ),
    )
    openssl_root, openssl_manifest = timed(
        timings, "openssl",
        lambda: build_openssl(
            layout, lock, cache_home, output / "OpenSSL", jobs,
        ),
    )
    timed(
        timings, "initramfs_a",
        lambda: build_initramfs(
            layout, runtime, zfs_root, zfs_modules, release,
            initramfs_a, volume, slot_a,
        ),
    )
    host_cache = REPOSITORY / layout["build"]["host_cache"]
    if cache_namespace:
        host_cache /= cache_namespace
    source = timed(
        timings, "linux_source",
        lambda: prepare_kernel_source(
            host_cache / "Kernel", distribution=distribution, version=release,
            patches=(REPOSITORY / lock["linux"]["patch"],),
            archive_url=lock["linux"]["url"],
            archive_sha256=lock["linux"]["sha256"],
        ),
    )
    kernel_arguments = {
        "native_cache_home": cache_home,
        "distribution": distribution,
        "source_date_epoch": layout["boot"]["source_date_epoch"],
        "jobs": jobs,
        "compiler_cache": bool(layout["build"]["compiler_cache"]),
        "compiler_cache_size": layout["build"]["compiler_cache_size"],
        "module_signing_key": key,
        "module_signing_certificate": certificate,
    }
    kernel_a = timed(
        timings, "kernel_a",
        lambda: build_linux_kernel(
            source, REPOSITORY / "Kernel" / "x86_64-mixtar.config",
            output / "Kernel-A", embedded_initramfs=initramfs_a,
            **kernel_arguments,
        ),
    )
    timed(
        timings, "sign_efi_a",
        lambda: sign_efi(distribution, kernel_a.executable, efi_a, key, certificate),
    )
    timed(
        timings, "root_archive",
        lambda: build_root(
            layout, runtime, kernel_a.modules, zfs_root, zfs_modules,
            openssl_root, public_key, release, slot_a, root_archive,
        ),
    )
    timed(
        timings, "initramfs_b",
        lambda: build_initramfs(
            layout, runtime, zfs_root, zfs_modules, release,
            initramfs_b, volume, slot_b,
        ),
    )
    kernel_b = timed(
        timings, "kernel_b",
        lambda: build_linux_kernel(
            source, REPOSITORY / "Kernel" / "x86_64-mixtar.config",
            output / "Kernel-B", embedded_initramfs=initramfs_b,
            **kernel_arguments,
        ),
    )
    timed(
        timings, "sign_efi_b",
        lambda: sign_efi(distribution, kernel_b.executable, efi_b, key, certificate),
    )
    timed(
        timings, "recovery_initramfs",
        lambda: build_recovery(
            layout, runtime, zfs_root, zfs_modules, release,
            recovery_initramfs, volume["pool"],
        ),
    )
    recovery_kernel = timed(
        timings, "recovery_kernel",
        lambda: build_linux_kernel(
            source, REPOSITORY / "Kernel" / "x86_64-mixtar.config",
            output / "Kernel-Recovery", embedded_initramfs=recovery_initramfs,
            **kernel_arguments,
        ),
    )
    timed(
        timings, "sign_recovery_efi",
        lambda: sign_efi(
            distribution, recovery_kernel.executable, recovery_efi,
            key, certificate,
        ),
    )
    payload_result = timed(
        timings, "payload",
        lambda: fat_volume({"root.tar": root_archive}, payload, "MIXTARDATA"),
    )
    with blank.open("wb") as stream:
        stream.truncate(int(volume["size_mib"]) * 1024 * 1024)
    esp_files = {
        "EFI/BOOT/BOOTX64.EFI": efi_a,
        "EFI/Mixtar/Recovery.EFI": recovery_efi,
        "EFI/Mixtar/M1.pem": certificate,
    }
    update_headroom = 2 * max(efi_a.stat().st_size, efi_b.stat().st_size)
    transactional_bytes = sum(path.stat().st_size for path in esp_files.values()) + update_headroom
    transactional_mib = (transactional_bytes + 1024 * 1024 - 1) // (1024 * 1024) + 24
    esp_size_mib = max(int(efi_volume["size_mib"]), transactional_mib)
    esp_result = timed(
        timings, "esp",
        lambda: fat_volume(
            esp_files, esp, efi_volume["label"], esp_size_mib,
        ),
    )
    disk_result = timed(
        timings, "gpt",
        lambda: write_gpt_disk(
            esp, blank, disk, f"{name}:{version}:m1", volume["label"],
            volume["typecode"], False,
        ),
    )
    provision = timed(
        timings, "zfs_provision",
        lambda: provision_zfs(
            efi_a, disk, payload, output,
            int(layout["boot"]["qemu_memory_mib"]),
            int(layout["boot"]["qemu_timeout_seconds"]) + 180,
        ),
    )
    valid_update, corrupt_update = timed(
        timings, "update_bundles",
        lambda: update_bundles(
            distribution, root_archive, efi_b, output,
            key, public_key, slot_b, name, version,
        ),
    )
    timed(timings, "vhdx", lambda: convert_vhdx(disk, vhdx))
    manifest: dict[str, Any] = {
        "schema": "mixtar.m1-image.v1",
        "system": {"name": name, "version": version},
        "target": {"architecture": architecture, "firmware": "UEFI"},
        "release_lock": {
            "path": repository_artifact_path(lock_path),
            "sha256": sha256(lock_path),
        },
        "boot": {
            "firmware_path": "\\EFI\\BOOT\\BOOTX64.EFI",
            "logical_path": profile["boot"]["efi"],
            "active_slot": slot_a,
            "recovery_path": "/System/EFI/Mixtar/Recovery.EFI",
            "secure_boot_signed": True,
            "transactional_esp_mib": esp_size_mib,
            "previous_firmware_created_on_update": True,
        },
        "kernel": {
            "release": release,
            "sha256": sha256(efi_a),
            "module_count": len(list(kernel_a.modules.rglob("*.ko"))),
            "module_root": f"/System/Kernel/Linux/{release}",
            "module_sdk": f"/System/Kernel/Linux/{release}/Development",
            "module_symvers_sha256": sha256(kernel_a.module_symvers),
            "modules_signed": True,
        },
        "openzfs": {
            **zfs_manifest,
            "pool": volume["pool"],
            "root_dataset": f"{volume['pool']}/ROOT/{slot_a}",
            "ashift": volume["ashift"],
            "compression": volume["compression"],
        },
        "openssl": openssl_manifest,
        "update": {
            "schema": "mixtar.update.v1",
            "primary_slot": slot_a,
            "candidate_slot": slot_b,
            "previous_release_preserved": True,
            "transaction_state": layout["update"]["transaction_state"],
        },
        "artifacts": {
            "esp": {**esp_result, "path": repository_artifact_path(esp)},
            "efi_a": artifact(efi_a, "pe-coff-efi"),
            "efi_b": artifact(efi_b, "pe-coff-efi"),
            "recovery_efi": artifact(recovery_efi, "pe-coff-efi"),
            "root_archive": artifact(root_archive, "tar"),
            "payload": {**payload_result, "path": repository_artifact_path(payload)},
            "root": {
                "format": "openzfs", "pool": volume["pool"],
                "dataset": f"{volume['pool']}/ROOT/{slot_a}", "readonly": True,
            },
            "disk": {**disk_result, **artifact(disk, str(disk_result.get("format", "gpt-raw")))},
            "vhdx": artifact(vhdx, "vhdx-dynamic"),
            "update": valid_update,
            "corrupt_update": corrupt_update,
        },
        "zfs_provision": provision,
        "timings_seconds": timings,
    }
    manifest_path = output / f"{stem}.manifest.json"
    manifest_path.write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    signature = output / f"{stem}.manifest.sig"
    timed(
        timings, "manifest_signature",
        lambda: sign_file(distribution, manifest_path, signature, key, public_key),
    )
    return {
        "manifest": str(manifest_path),
        "manifest_signature": str(signature),
        "disk": str(disk),
        "vhdx": str(vhdx),
        "efi_a": str(efi_a),
        "efi_b": str(efi_b),
        "recovery_efi": str(recovery_efi),
        "update": str(REPOSITORY / valid_update["path"]),
        "corrupt_update": str(REPOSITORY / corrupt_update["path"]),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Build the signed Mixtar M1 image")
    parser.add_argument("--profile", type=Path, default=Path("Profiles/qemu-x86_64.toml"))
    parser.add_argument("--release-lock", type=Path, default=Path("Release/M1.lock.config"))
    parser.add_argument("--signing-key", type=Path, required=True)
    parser.add_argument("--signing-certificate", type=Path, required=True)
    parser.add_argument("--public-key", type=Path, required=True)
    parser.add_argument("--cache-namespace", default="")
    arguments = parser.parse_args()
    try:
        result = build(
            (REPOSITORY / arguments.profile).resolve(),
            (REPOSITORY / arguments.release_lock).resolve(),
            arguments.signing_key.resolve(),
            arguments.signing_certificate.resolve(),
            arguments.public_key.resolve(),
            arguments.cache_namespace,
        )
    except (KeyError, OSError, RuntimeError, ValueError, subprocess.SubprocessError) as error:
        print(f"mixtar-m1: error: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
