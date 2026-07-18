#!/usr/bin/env python3
"""Validate the staged MixtarRVS Core identity and optional boot image."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import shutil
import sys
import tarfile
import tempfile
import tomllib


REPOSITORY = Path(__file__).resolve().parents[1]
OUTPUT_ROOT = (REPOSITORY / "Output").resolve()


class ValidationError(RuntimeError):
    pass


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def table(document: dict[str, object], name: str) -> dict[str, object]:
    value = document.get(name)
    if not isinstance(value, dict):
        raise ValidationError(f"Missing [{name}] table")
    return value


def string_value(values: dict[str, object], name: str) -> str:
    value = values.get(name)
    if not isinstance(value, str) or not value:
        raise ValidationError(f"Missing string value: {name}")
    return value


def list_value(values: dict[str, object], name: str) -> list[object]:
    value = values.get(name)
    if not isinstance(value, list):
        raise ValidationError(f"Missing list value: {name}")
    return value


def physical_file(path: Path, description: str) -> Path:
    if path.is_symlink() or not path.is_file():
        raise ValidationError(f"{description} is not a physical file: {path}")
    return path.resolve(strict=True)


def repository_file(value: str, description: str) -> Path:
    configured = Path(value)
    if not configured.is_absolute() and ".." in configured.parts:
        raise ValidationError(f"Invalid repository path for {description}")
    raw_path = configured if configured.is_absolute() else REPOSITORY / configured
    path = physical_file(raw_path, description)
    for allowed_root in (REPOSITORY, OUTPUT_ROOT):
        try:
            path.relative_to(allowed_root)
            return path
        except ValueError:
            continue
    raise ValidationError(f"{description} escapes the repository and Output/")


def output_directory(value: str) -> Path:
    raw_path = REPOSITORY / value
    if raw_path.is_symlink() or not raw_path.is_dir():
        raise ValidationError(f"Staged root does not exist: {value}")
    path = raw_path.resolve(strict=True)
    try:
        path.relative_to(OUTPUT_ROOT)
    except ValueError as error:
        raise ValidationError("Staged root escapes Output/") from error
    return path


def logical_path(root: Path, value: str) -> Path:
    logical = PurePosixPath(value.lstrip("/"))
    if not logical.parts or any(part in {"", ".", ".."} for part in logical.parts):
        raise ValidationError(f"Invalid Mixtar path: {value}")
    return root.joinpath(*logical.parts)


def load_toml(path: Path, description: str) -> dict[str, object]:
    physical_file(path, description)
    with path.open("rb") as stream:
        document = tomllib.load(stream)
    if document.get("schema") != 1:
        raise ValidationError(f"{description} has an unsupported schema")
    return document


def equal(actual: object, expected: object, description: str) -> None:
    if actual != expected:
        raise ValidationError(
            f"{description} mismatch: expected {expected!r}, got {actual!r}"
        )


def validate_elf(path: Path) -> None:
    physical_file(path, "Executor")
    with path.open("rb") as stream:
        header = stream.read(20)
    if len(header) != 20 or header[:4] != b"\x7fELF":
        raise ValidationError("Executor is not ELF")
    if header[4] != 2 or header[5] != 1:
        raise ValidationError("Executor is not little-endian ELF64")
    if int.from_bytes(header[16:18], "little") not in {2, 3}:
        raise ValidationError("Executor is not ET_EXEC or ET_DYN")
    if int.from_bytes(header[18:20], "little") != 62:
        raise ValidationError("Executor does not target x86_64")


def extract_validation_root(archive_path: Path, destination: Path) -> None:
    with tarfile.open(archive_path, "r:") as archive:
        for member in archive:
            logical = PurePosixPath(member.name)
            if (
                logical.is_absolute()
                or not logical.parts
                or any(part in {"", ".."} for part in logical.parts)
            ):
                raise ValidationError(
                    f"Core archive contains an unsafe path: {member.name}"
                )
            target = destination.joinpath(*logical.parts)
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True)
                continue
            if member.isfile():
                target.parent.mkdir(parents=True, exist_ok=True)
                source = archive.extractfile(member)
                if source is None:
                    raise ValidationError(
                        f"Core archive file has no payload: {member.name}"
                    )
                with source, target.open("wb") as output:
                    shutil.copyfileobj(source, output)
                target.chmod(member.mode & 0o777)
                continue
            if member.islnk():
                raise ValidationError(
                    f"Core archive contains a forbidden hardlink: {member.name}"
                )
            if member.issym() or member.isdev() or member.isfifo():
                continue
            raise ValidationError(
                f"Core archive contains an unsupported entry: {member.name}"
            )

def validate_root(document: dict[str, object]) -> dict[str, str]:
    product = table(document, "product")
    executor = table(document, "executor")
    zsh = table(document, "zsh")
    runtime = table(document, "runtime")
    output = table(document, "output")
    contracts = table(document, "contracts")

    root_archive = repository_file(
        string_value(output, "root_archive"), "Core root archive"
    )
    temporary_root = None
    if bool(output.get("materialize_root", True)):
        root = output_directory(string_value(output, "root_directory"))
        root_description = str(root)
    else:
        temporary_root = tempfile.TemporaryDirectory(
            prefix=".mixtar-core-validation-"
        )
        root = Path(temporary_root.name)
        extract_validation_root(root_archive, root)
        root_description = f"archive:{root_archive}"
    identity_path = logical_path(root, string_value(contracts, "identity"))
    identity = load_toml(identity_path, "Product identity")
    identity_product = table(identity, "product")
    for key in (
        "id",
        "name",
        "version",
        "architecture",
        "base_release",
        "interface",
        "language",
    ):
        equal(identity_product.get(key), product.get(key), f"Identity {key}")

    executor_path = logical_path(root, string_value(executor, "install_path"))
    validate_elf(executor_path)
    executor_config = logical_path(
        root, string_value(contracts, "executor_configuration")
    )
    load_toml(executor_config, "Executor configuration")

    policy_path = logical_path(
        root, string_value(contracts, "zsh_policy")
    )
    policy = load_toml(policy_path, "zsh capability policy")
    policy_application = table(policy, "application")
    equal(
        policy_application.get("id"),
        "org.mixtar.Terminal.ZSH",
        "zsh policy application id",
    )

    bundle = logical_path(root, string_value(zsh, "bundle"))
    if bundle.is_symlink() or not bundle.is_dir():
        raise ValidationError("zsh.apx is not a physical directory")
    program = physical_file(bundle / "Program" / "zsh", "zsh APX program")
    descriptor = load_toml(bundle / "zsh.config", "zsh APX descriptor")
    application = table(descriptor, "application")
    equal(application.get("id"), "org.mixtar.Terminal.ZSH", "zsh APX id")
    release = load_toml(
        repository_file(
            string_value(table(document, "base"), "release_lock"),
            "Release lock",
        ),
        "Release lock",
    )
    equal(
        application.get("version"),
        table(release, "zsh").get("version"),
        "zsh APX version",
    )
    entry = table(table(descriptor, "entry"), "terminal")
    equal(entry.get("kind"), "native", "zsh terminal entry kind")
    equal(entry.get("path"), "Program/zsh", "zsh terminal entry path")
    capabilities = table(descriptor, "capabilities")
    equal(list_value(capabilities, "required"), [], "zsh required capabilities")
    equal(list_value(capabilities, "optional"), [], "zsh optional capabilities")

    service = physical_file(
        logical_path(root, string_value(runtime, "service")),
        "Product runtime service",
    )
    runlevel = physical_file(
        logical_path(root, string_value(runtime, "runlevel")),
        "Product runtime runlevel entry",
    )
    equal(sha256(runlevel), sha256(service), "Runtime service copy")

    core_manifest = load_toml(

        repository_file(string_value(output, "manifest"), "Core manifest"),
        "Core manifest",
    )
    manifest_product = table(core_manifest, "product")
    equal(manifest_product.get("id"), product.get("id"), "Manifest product id")
    equal(
        manifest_product.get("version"),
        product.get("version"),
        "Manifest product version",
    )
    artifacts = table(core_manifest, "artifacts")
    root_artifact = table(artifacts, "root")
    equal(
        root_artifact.get("archive_sha256"),
        sha256(root_archive),
        "Core root archive hash",
    )
    equal(
        table(table(core_manifest, "components"), "executor").get("sha256"),
        sha256(executor_path),
        "Executor hash",
    )
    equal(
        table(table(core_manifest, "components"), "zsh").get("sha256"),
        sha256(program),
        "zsh hash",
    )
    evidence = {
        "root": root_description,
        "root_archive": str(root_archive),
        "root_sha256": sha256(root_archive),
        "executor_sha256": sha256(executor_path),
    }
    if temporary_root is not None:
        temporary_root.cleanup()
    return evidence


def validate_image(
    document: dict[str, object],
    root_evidence: dict[str, str],
) -> dict[str, str]:
    product = table(document, "product")
    image = table(document, "image")
    image_root = output_directory(string_value(image, "output_directory"))
    stem = "-".join(
        (
            string_value(product, "name"),
            string_value(product, "version"),
            string_value(product, "architecture"),
        )
    )
    manifest_path = physical_file(
        image_root / f"{stem}.manifest.json",
        "Image manifest",
    )
    signature = physical_file(
        image_root / f"{stem}.manifest.sig",
        "Image manifest signature",
    )
    with manifest_path.open("r", encoding="utf-8") as stream:
        manifest = json.load(stream)

    system = manifest.get("system")
    target = manifest.get("target")
    boot = manifest.get("boot")
    artifacts = manifest.get("artifacts")
    if not isinstance(system, dict) or not isinstance(target, dict):
        raise ValidationError("Image manifest identity is missing")
    if not isinstance(boot, dict) or not isinstance(artifacts, dict):
        raise ValidationError("Image manifest boot artifacts are missing")
    equal(system.get("name"), product.get("name"), "Image system name")
    equal(system.get("version"), product.get("version"), "Image system version")
    equal(
        target.get("architecture"),
        product.get("architecture"),
        "Image architecture",
    )
    equal(target.get("firmware"), "UEFI", "Image firmware")
    equal(
        boot.get("firmware_path"),
        "\\EFI\\BOOT\\BOOTX64.EFI",
        "Image firmware path",
    )
    equal(boot.get("secure_boot_signed"), True, "Secure Boot signature state")

    root_artifact = artifacts.get("root_archive")
    disk_artifact = artifacts.get("disk")
    vhdx_artifact = artifacts.get("vhdx")
    if not all(
        isinstance(value, dict)
        for value in (root_artifact, disk_artifact, vhdx_artifact)
    ):
        raise ValidationError("Image manifest lacks root, disk, or VHDX")
    equal(
        root_artifact.get("sha256"),
        root_evidence["root_sha256"],
        "Image root hash",
    )
    for artifact_name, artifact_value in (
        ("Image root archive", root_artifact),
        ("GPT disk", disk_artifact),
        ("Hyper-V VHDX", vhdx_artifact),
    ):
        artifact_path = repository_file(
            string_value(artifact_value, "path"),
            artifact_name,
        )
        try:
            artifact_path.relative_to(image_root)
        except ValueError as error:
            raise ValidationError(
                f"{artifact_name} is outside the P4 image directory"
            ) from error

    provision = manifest.get("zfs_provision")
    if not isinstance(provision, dict):
        raise ValidationError("Image lacks the ZFS provisioning report")
    equal(provision.get("passed"), True, "ZFS provisioning result")
    return {
        "manifest": str(manifest_path),
        "manifest_sha256": sha256(manifest_path),
        "signature": str(signature),
        "disk": str(REPOSITORY / string_value(disk_artifact, "path")),
        "vhdx": str(REPOSITORY / string_value(vhdx_artifact, "path")),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", default="Product/Core.config")
    parser.add_argument("--require-image", action="store_true")
    options = parser.parse_args()
    try:
        config = load_toml(
            repository_file(options.config, "Product contract"),
            "Product contract",
        )
        root = validate_root(config)
        report: dict[str, object] = {
            "schema": "mixtar.core-validation.v1",
            "passed": True,
            "root": root,
        }
        if options.require_image:
            report["image"] = validate_image(config, root)
    except (
        json.JSONDecodeError,
        OSError,
        ValidationError,
        tomllib.TOMLDecodeError,
    ) as error:
        print(f"MixtarRVS Core validation failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
