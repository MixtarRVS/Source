#!/usr/bin/env python3
"""Build the signed EFI/ZFS image with the staged MixtarRVS Core root."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import subprocess
import sys
import tomllib


REPOSITORY = Path(__file__).resolve().parents[1]
OUTPUT_ROOT = (REPOSITORY / "Output").resolve()
P4_OUTPUT_ROOT = (OUTPUT_ROOT / "P4").resolve()


class CoreImageError(RuntimeError):
    pass


def table(document: dict[str, object], name: str) -> dict[str, object]:
    value = document.get(name)
    if not isinstance(value, dict):
        raise CoreImageError(f"Missing [{name}] table")
    return value


def string_value(values: dict[str, object], name: str) -> str:
    value = values.get(name)
    if not isinstance(value, str) or not value:
        raise CoreImageError(f"Missing string value: {name}")
    return value


def string_list(values: dict[str, object], name: str) -> list[str]:
    value = values.get(name)
    if not isinstance(value, list) or any(
        not isinstance(item, str) or not item for item in value
    ):
        raise CoreImageError(f"Missing string list: {name}")
    return value


def boolean_value(values: dict[str, object], name: str) -> bool:
    value = values.get(name)
    if not isinstance(value, bool):
        raise CoreImageError(f"Missing boolean value: {name}")
    return value


def physical_repository_file(value: str, description: str) -> Path:
    configured = Path(value)
    if not configured.is_absolute() and ".." in configured.parts:
        raise CoreImageError(f"Invalid repository path for {description}: {value}")
    raw_path = configured if configured.is_absolute() else REPOSITORY / configured
    if raw_path.is_symlink() or not raw_path.is_file():
        raise CoreImageError(f"{description} is not a physical file: {value}")
    path = raw_path.resolve(strict=True)
    for allowed_root in (REPOSITORY, OUTPUT_ROOT):
        try:
            path.relative_to(allowed_root)
            return path
        except ValueError:
            continue
    raise CoreImageError(
        f"{description} escapes the repository and Output/: {value}"
    )


def product_output(value: str) -> Path:
    raw_path = REPOSITORY / value
    if raw_path.is_symlink():
        raise CoreImageError(f"Image output cannot be a symbolic link: {value}")
    path = raw_path.resolve()
    try:
        path.relative_to(P4_OUTPUT_ROOT)
    except ValueError as error:
        raise CoreImageError(f"Image output must be below Output/P4: {value}") from error
    path.mkdir(parents=True, exist_ok=True)
    return path


def add_wslenv(current: str, name: str, path_value: bool = False) -> str:
    entry = name + ("/p" if path_value else "")
    entries = [item for item in current.split(":") if item]
    names = {item.split("/", 1)[0] for item in entries}
    if name not in names:
        entries.append(entry)
    return ":".join(entries)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", default="Product/Core.config")
    parser.add_argument("--wsl-distribution")
    options = parser.parse_args()

    try:
        config_path = physical_repository_file(
            options.config, "Product contract"
        )
        with config_path.open("rb") as stream:
            document = tomllib.load(stream)
        if document.get("schema") != 1:
            raise CoreImageError("Unsupported Product/Core.config schema")

        product = table(document, "product")
        output = table(document, "output")
        image = table(document, "image")
        root_archive = physical_repository_file(
            string_value(output, "root_archive"), "Core root archive"
        )
        image_output = product_output(string_value(image, "output_directory"))
        entrypoint = physical_repository_file(
            string_value(image, "entrypoint"), "Image entrypoint"
        )
        entrypoint_arguments = string_list(image, "entrypoint_arguments")

        environment = os.environ.copy()
        root_variable = string_value(image, "prebuilt_root_environment")
        output_variable = string_value(image, "output_environment")
        version_variable = string_value(image, "product_version_environment")
        reuse_variable = string_value(image, "reuse_base_boot_environment")
        environment[root_variable] = str(root_archive)
        environment[output_variable] = str(image_output)
        environment[version_variable] = string_value(product, "version")
        environment[reuse_variable] = (
            "1" if boolean_value(image, "reuse_base_boot") else "0"
        )
        wslenv = environment.get("WSLENV", "")
        wslenv = add_wslenv(wslenv, root_variable, True)
        wslenv = add_wslenv(wslenv, output_variable, True)
        wslenv = add_wslenv(wslenv, version_variable)
        wslenv = add_wslenv(wslenv, reuse_variable)
        environment["WSLENV"] = wslenv
        if options.wsl_distribution:
            environment["MIXTAR_WSL_DISTRIBUTION"] = options.wsl_distribution

        shell = "powershell.exe" if os.name == "nt" else "pwsh"
        subprocess.run(
            [
                shell,
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(entrypoint),
                *entrypoint_arguments,
            ],
            cwd=REPOSITORY,
            env=environment,
            check=True,
        )
    except (
        CoreImageError,
        OSError,
        subprocess.CalledProcessError,
        tomllib.TOMLDecodeError,
    ) as error:
        print(f"MixtarRVS Core image build failed: {error}", file=sys.stderr)
        return 1

    print(f"MixtarRVS Core image directory: {image_output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
