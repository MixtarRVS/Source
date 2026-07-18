#!/usr/bin/env python3
"""Build the MixtarRVS 1.0 Core product overlay from one product contract."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import subprocess
import sys
import tomllib


REPOSITORY = Path(__file__).resolve().parents[1]


class CoreBuildError(RuntimeError):
    pass


def repository_path(value: str) -> Path:
    candidate = Path(value)
    if not candidate.is_absolute():
        candidate = REPOSITORY / candidate
    path = candidate.absolute()
    try:
        relative = path.relative_to(REPOSITORY)
    except ValueError as error:
        raise CoreBuildError(f"Path escapes the repository: {value}") from error

    allowed_output = (REPOSITORY / "Output").absolute()
    current = REPOSITORY
    for part in relative.parts:
        current /= part
        is_junction = getattr(current, "is_junction", None)
        is_reparse = current.is_symlink() or (is_junction is not None and is_junction())
        if not is_reparse or current == allowed_output:
            continue
        target = current.resolve()
        try:
            target.relative_to(REPOSITORY)
        except ValueError as error:
            raise CoreBuildError(f"Path crosses an external reparse point: {value}") from error
    return path
def load_contract(path: Path) -> dict[str, object]:
    if not path.is_file():
        raise CoreBuildError(f"Product contract does not exist: {path}")
    with path.open("rb") as stream:
        document = tomllib.load(stream)
    if document.get("schema") != 1:
        raise CoreBuildError("Unsupported Product/Core.config schema")
    return document


def table(document: dict[str, object], name: str) -> dict[str, object]:
    value = document.get(name)
    if not isinstance(value, dict):
        raise CoreBuildError(f"Missing [{name}] table")
    return value


def string_value(values: dict[str, object], name: str) -> str:
    value = values.get(name)
    if not isinstance(value, str) or not value:
        raise CoreBuildError(f"Missing string value: {name}")
    return value


def wsl_path(distribution: str, path: Path) -> str:
    result = subprocess.run(
        ["wsl.exe", "-d", distribution, "-e", "wslpath", "-a", "-u", str(path)],
        check=True,
        capture_output=True,
        text=True,
    )
    translated = result.stdout.strip()
    if not translated.startswith("/"):
        raise CoreBuildError(f"WSL returned an invalid repository path: {translated}")
    return translated


def publish_executor(
    document: dict[str, object], distribution: str | None
) -> None:
    sdk = table(document, "sdk")
    executor = table(document, "executor")
    arguments = [
        string_value(executor, "project"),
        string_value(executor, "runtime"),
        string_value(executor, "configuration"),
        string_value(executor, "publish_directory"),
        string_value(sdk, "channel"),
    ]

    if os.name == "nt":
        if not distribution:
            raise CoreBuildError("A WSL distribution is required on Windows")
        linux_repository = wsl_path(distribution, REPOSITORY)
        command = [
            "wsl.exe",
            "-d",
            distribution,
            "--cd",
            linux_repository,
            "--",
            "bash",
            "Product/publish-executor.sh",
            *arguments,
        ]
    else:
        command = ["bash", "Product/publish-executor.sh", *arguments]

    subprocess.run(command, cwd=REPOSITORY, check=True)


def stage_root(contract: Path, distribution: str | None) -> None:
    if os.name == "nt":
        if not distribution:
            raise CoreBuildError("A WSL distribution is required on Windows")
        linux_repository = wsl_path(distribution, REPOSITORY)
        linux_contract = wsl_path(distribution, contract)
        command = [
            "wsl.exe",
            "-d",
            distribution,
            "--cd",
            linux_repository,
            "--",
            "fakeroot",
            "python3",
            "Product/stage_core.py",
            "--config",
            linux_contract,
        ]
    else:
        command = ["fakeroot", sys.executable, "Product/stage_core.py", "--config", str(contract)]
    subprocess.run(command, cwd=REPOSITORY, check=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", default="Product/Core.config")
    parser.add_argument("--wsl-distribution")
    options = parser.parse_args()

    try:
        contract_path = repository_path(options.config)
        document = load_contract(contract_path)
        publish_executor(document, options.wsl_distribution)
        stage_root(contract_path, options.wsl_distribution)
    except (CoreBuildError, OSError, subprocess.CalledProcessError) as error:
        print(f"MixtarRVS Core build failed: {error}", file=sys.stderr)
        return 1

    output = table(document, "output")
    print(f"MixtarRVS Core root: {string_value(output, 'root_archive')}")
    print(f"MixtarRVS Core manifest: {string_value(output, 'manifest')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
