#!/usr/bin/env python3
"""Build the MixtarRVS graphical product overlay from one locked contract."""

from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import re
import subprocess
import sys
import tomllib


REPOSITORY = Path(__file__).resolve().parents[1]
SHA256 = re.compile(r"^[0-9a-f]{64}$")


class GraphicsBuildError(RuntimeError):
    pass


def repository_path(value: str) -> Path:
    candidate = Path(value)
    if not candidate.is_absolute():
        candidate = REPOSITORY / candidate
    path = candidate.absolute()
    try:
        relative = path.relative_to(REPOSITORY)
    except ValueError as error:
        raise GraphicsBuildError(f"Path escapes the repository: {value}") from error
    allowed_output = (REPOSITORY / "Output").absolute()
    current = REPOSITORY
    for part in relative.parts:
        current /= part
        is_junction = getattr(current, "is_junction", None)
        is_reparse = current.is_symlink() or (
            is_junction is not None and is_junction()
        )
        if not is_reparse or current == allowed_output:
            continue
        target = current.resolve()
        try:
            target.relative_to(REPOSITORY)
        except ValueError as error:
            raise GraphicsBuildError(
                f"Path crosses an external reparse point: {value}"
            ) from error
    return path


def load_toml(path: Path) -> dict[str, object]:
    if not path.is_file():
        raise GraphicsBuildError(f"Required config does not exist: {path}")
    with path.open("rb") as stream:
        document = tomllib.load(stream)
    if document.get("schema") != 1:
        raise GraphicsBuildError(f"Unsupported config schema: {path}")
    return document


def table(document: dict[str, object], name: str) -> dict[str, object]:
    value = document.get(name)
    if not isinstance(value, dict):
        raise GraphicsBuildError(f"Missing [{name}] table")
    return value


def string_value(values: dict[str, object], name: str) -> str:
    value = values.get(name)
    if not isinstance(value, str) or not value:
        raise GraphicsBuildError(f"Missing string value: {name}")
    return value


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def validate_lock(lock_path: Path, lock: dict[str, object]) -> None:
    release = table(lock, "release")
    policy = table(lock, "policy")
    managed = table(lock, "managed")
    if string_value(release, "name") != "MixtarRVS":
        raise GraphicsBuildError("Graphics lock has the wrong release identity")
    if string_value(release, "architecture") != "x86_64":
        raise GraphicsBuildError("Graphics lock must target x86_64")
    if policy.get("x11") is not False or policy.get("xwayland") is not False:
        raise GraphicsBuildError("Graphics lock must remain Wayland-only")
    if policy.get("fhs_runtime") is not False:
        raise GraphicsBuildError("Graphics lock must not expose an FHS runtime")
    if string_value(managed, "avalonia") != "12.1.0":
        raise GraphicsBuildError("P4 requires Avalonia 12.1.0")
    if string_value(managed, "runtime_identifier") != "linux-x64":
        raise GraphicsBuildError("P4 requires the linux-x64 Native AOT runtime")

    sources = lock.get("sources")
    if not isinstance(sources, list) or not sources:
        raise GraphicsBuildError("Graphics lock has no sources")
    identifiers: set[str] = set()
    for source in sources:
        if not isinstance(source, dict):
            raise GraphicsBuildError("Invalid graphics source entry")
        identifier = string_value(source, "id")
        if identifier in identifiers:
            raise GraphicsBuildError(f"Duplicate graphics source: {identifier}")
        identifiers.add(identifier)
        if not string_value(source, "url").startswith("https://"):
            raise GraphicsBuildError(f"Source URL is not HTTPS: {identifier}")
        if not SHA256.fullmatch(string_value(source, "sha256")):
            raise GraphicsBuildError(f"Invalid source SHA-256: {identifier}")

    expected_sources = {
        "expat", "libffi", "wayland", "wayland-protocols", "freetype",
        "harfbuzz", "fontconfig", "libdrm", "mesa", "noto-sans",
        "noto-sans-mono",
    }
    if identifiers != expected_sources:
        missing = ", ".join(sorted(expected_sources - identifiers))
        extra = ", ".join(sorted(identifiers - expected_sources))
        raise GraphicsBuildError(
            f"Graphics source set differs from contract; missing={missing}; extra={extra}"
        )

    inputs = lock.get("inputs")
    if not isinstance(inputs, list) or not inputs:
        raise GraphicsBuildError("Graphics lock has no local inputs")
    for entry in inputs:
        if not isinstance(entry, dict):
            raise GraphicsBuildError("Invalid graphics input entry")
        relative = string_value(entry, "path")
        expected = string_value(entry, "sha256")
        if not SHA256.fullmatch(expected):
            raise GraphicsBuildError(f"Invalid input SHA-256: {relative}")
        path = repository_path(relative)
        if not path.is_file():
            raise GraphicsBuildError(f"Locked input is missing: {relative}")
        actual = digest(path)
        if actual != expected:
            raise GraphicsBuildError(
                f"Locked input changed: {relative}: expected {expected}, found {actual}"
            )

    if not lock_path.is_file():
        raise GraphicsBuildError("Graphics lock disappeared during validation")


def wsl_path(distribution: str, path: Path) -> str:
    result = subprocess.run(
        ["wsl.exe", "-d", distribution, "-e", "wslpath", "-a", "-u", str(path)],
        check=True,
        capture_output=True,
        text=True,
    )
    translated = result.stdout.strip()
    if not translated.startswith("/"):
        raise GraphicsBuildError(f"WSL returned an invalid path: {translated}")
    return translated


def linux_command(
    distribution: str | None,
    arguments: list[str],
    environment: dict[str, str] | None = None,
) -> None:
    environment = environment or {}
    if os.name == "nt":
        if not distribution:
            raise GraphicsBuildError("A WSL distribution is required on Windows")
        linux_repository = wsl_path(distribution, REPOSITORY)
        command = [
            "wsl.exe", "-d", distribution, "--cd", linux_repository,
            "-e", "/usr/bin/env",
            *[f"{key}={value}" for key, value in sorted(environment.items())],
            *arguments,
        ]
        subprocess.run(command, cwd=REPOSITORY, check=True)
    else:
        subprocess.run(
            arguments,
            cwd=REPOSITORY,
            check=True,
            env={**os.environ, **environment},
        )


def publish_workbench(
    document: dict[str, object], distribution: str | None
) -> None:
    workbench = table(document, "workbench")
    sdk = table(document, "sdk")
    arguments = [
        "/usr/bin/bash", "Product/publish-workbench.sh",
        string_value(workbench, "project"),
        string_value(workbench, "runtime"),
        string_value(workbench, "configuration"),
        string_value(workbench, "publish_directory"),
        string_value(sdk, "channel"),
    ]
    linux_command(distribution, arguments)


def build_stack(
    document: dict[str, object],
    lock_path: Path,
    lock: dict[str, object],
    distribution: str | None,
    jobs: int,
) -> None:
    stack = table(document, "stack")
    release = table(lock, "release")
    build_directory = repository_path(string_value(stack, "build_directory"))
    if os.name == "nt":
        if not distribution:
            raise GraphicsBuildError("A WSL distribution is required on Windows")
        repository_value = wsl_path(distribution, REPOSITORY)
        output_value = wsl_path(distribution, build_directory)
    else:
        repository_value = str(REPOSITORY)
        output_value = str(build_directory)

    epoch = release.get("source_date_epoch")
    if not isinstance(epoch, int) or isinstance(epoch, bool):
        raise GraphicsBuildError("Invalid release source_date_epoch")
    environment = {
        "MIXTAR_REPOSITORY": repository_value,
        "MIXTAR_OUTPUT": output_value,
        "MIXTAR_STACK_KEY": digest(lock_path)[:16],
        "MIXTAR_SOURCE_DATE_EPOCH": str(epoch),
        "MIXTAR_JOBS": str(jobs),
    }
    sources = lock.get("sources")
    assert isinstance(sources, list)
    for source in sources:
        assert isinstance(source, dict)
        key = string_value(source, "id").upper().replace("-", "_")
        for field in ("version", "archive", "url", "sha256"):
            environment[f"MIXTAR_{key}_{field.upper()}"] = string_value(source, field)
        optional = [field for field in ("patch", "patch_sha256") if field in source]
        if len(optional) == 1:
            raise GraphicsBuildError(
                f"Source {source.get('id')!r} needs both patch and patch_sha256"
            )
        for field in optional:
            environment[f"MIXTAR_{key}_{field.upper()}"] = string_value(source, field)

    linux_command(
        distribution,
        ["/usr/bin/bash", string_value(stack, "builder")],
        environment,
    )


def stage_overlay(config_path: Path, distribution: str | None) -> None:
    if os.name == "nt":
        if not distribution:
            raise GraphicsBuildError("A WSL distribution is required on Windows")
        config_value = wsl_path(distribution, config_path)
    else:
        config_value = str(config_path)
    linux_command(
        distribution,
        [
            "/usr/bin/fakeroot", "python3", "Product/stage_graphics.py",
            "--config", config_value,
        ],
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", default="Product/Graphics.config")
    parser.add_argument("--wsl-distribution")
    parser.add_argument("--jobs", type=int, default=0)
    options = parser.parse_args()

    try:
        config_path = repository_path(options.config)
        document = load_toml(config_path)
        base = table(document, "base")
        lock_path = repository_path(string_value(base, "release_lock"))
        lock = load_toml(lock_path)
        validate_lock(lock_path, lock)
        jobs = options.jobs or max(1, os.cpu_count() or 1)
        if jobs < 1:
            raise GraphicsBuildError("Job count must be positive")
        publish_workbench(document, options.wsl_distribution)
        build_stack(document, lock_path, lock, options.wsl_distribution, jobs)
        stage_overlay(config_path, options.wsl_distribution)
    except (
        GraphicsBuildError,
        OSError,
        subprocess.CalledProcessError,
        tomllib.TOMLDecodeError,
    ) as error:
        print(f"MixtarRVS graphics build failed: {error}", file=sys.stderr)
        return 1

    output = table(document, "output")
    print(f"MixtarRVS graphics root: {string_value(output, 'root_directory')}")
    print(f"MixtarRVS graphics manifest: {string_value(output, 'manifest')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
