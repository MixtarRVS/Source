#!/usr/bin/env python3
"""Run the existing console release test against the MixtarRVS Core image."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tomllib


REPOSITORY = Path(__file__).resolve().parents[1]
P4_ROOT = (REPOSITORY / "Output" / "P4").resolve()


class CoreTestError(RuntimeError):
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
        raise CoreTestError(f"Missing [{name}] table")
    return value


def string_value(values: dict[str, object], name: str) -> str:
    value = values.get(name)
    if not isinstance(value, str) or not value:
        raise CoreTestError(f"Missing string value: {name}")
    return value


def physical_file(path: Path, description: str) -> Path:
    if path.is_symlink() or not path.is_file():
        raise CoreTestError(f"{description} is not a physical file: {path}")
    return path.resolve(strict=True)


def report_path(path: Path) -> str:
    resolved = path.resolve(strict=True)
    for root, prefix in (
        (REPOSITORY, Path()),
        (P4_ROOT, Path("Output") / "P4"),
    ):
        try:
            relative = resolved.relative_to(root)
        except ValueError:
            continue
        return (prefix / relative).as_posix()
    raise CoreTestError(f"Report path escapes the repository and Output/P4: {path}")


def repository_file(value: str, description: str) -> Path:
    configured = Path(value)
    if not configured.is_absolute() and ".." in configured.parts:
        raise CoreTestError(f"Invalid repository path for {description}")
    raw_path = configured if configured.is_absolute() else REPOSITORY / configured
    path = physical_file(raw_path, description)
    for allowed_root in (REPOSITORY, P4_ROOT):
        try:
            path.relative_to(allowed_root)
            return path
        except ValueError:
            continue
    raise CoreTestError(f"{description} escapes the repository and Output/P4")


def p4_path(value: str) -> Path:
    path = (REPOSITORY / value).resolve()
    try:
        path.relative_to(P4_ROOT)
    except ValueError as error:
        raise CoreTestError(f"Test artifact must be below Output/P4: {value}") from error
    path.parent.mkdir(parents=True, exist_ok=True)
    return path


def run_json(command: list[str], description: str) -> dict[str, object]:
    result = subprocess.run(
        command,
        cwd=REPOSITORY,
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode:
        detail = result.stderr.strip() or result.stdout.strip()
        raise CoreTestError(f"{description} failed: {detail}")
    try:
        value = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise CoreTestError(f"{description} did not return JSON") from error
    if not isinstance(value, dict) or value.get("passed") is not True:
        raise CoreTestError(f"{description} did not pass")
    return value


def write_json_atomic(path: Path, value: dict[str, object]) -> None:
    temporary = path.with_name(path.name + ".tmp")
    temporary.unlink(missing_ok=True)
    temporary.write_text(
        json.dumps(value, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    os.replace(temporary, path)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", default="Product/Core.config")
    parser.add_argument("--qemu")
    parser.add_argument("--firmware", required=True)
    parser.add_argument("--firmware-vars", required=True)
    parser.add_argument("--accelerator")
    parser.add_argument("--memory", type=int)
    parser.add_argument("--cpus", type=int)
    parser.add_argument("--boot-timeout", type=int)
    parser.add_argument("--prompt-timeout", type=int)
    parser.add_argument("--shutdown-timeout", type=int)
    parser.add_argument("--qemu-arg", action="append", default=[])
    options = parser.parse_args()

    try:
        config_path = repository_file(options.config, "Product contract")
        with config_path.open("rb") as stream:
            document = tomllib.load(stream)
        if document.get("schema") != 1:
            raise CoreTestError("Unsupported Product/Core.config schema")

        product = table(document, "product")
        image = table(document, "image")
        test = table(document, "test")
        image_root = (REPOSITORY / string_value(image, "output_directory")).resolve()
        try:
            image_root.relative_to(P4_ROOT)
        except ValueError as error:
            raise CoreTestError("Image directory escapes Output/P4") from error
        stem = "-".join(
            (
                string_value(product, "name"),
                string_value(product, "version"),
                string_value(product, "architecture"),
            )
        )
        disk = physical_file(image_root / f"{stem}.disk.img", "Core GPT disk")
        firmware = physical_file(Path(options.firmware), "UEFI firmware")
        firmware_vars = physical_file(
            Path(options.firmware_vars), "UEFI variable store"
        )
        harness = repository_file(
            string_value(test, "console_harness"), "Console harness"
        )
        console_report_path = p4_path(string_value(test, "console_report"))
        release_report_path = p4_path(string_value(test, "release_report"))
        work_directory = (REPOSITORY / string_value(test, "work_directory")).resolve()
        try:
            work_directory.relative_to(P4_ROOT)
        except ValueError as error:
            raise CoreTestError("Test work directory escapes Output/P4") from error
        work_directory.mkdir(parents=True, exist_ok=True)

        validation = run_json(
            [
                sys.executable,
                "Product/validate_core.py",
                "--config",
                str(config_path),
                "--require-image",
            ],
            "Core artifact validation",
        )

        console_command = [
            sys.executable,
            str(harness),
            "--firmware",
            str(firmware),
            "--firmware-vars",
            str(firmware_vars),
            "--disk",
            str(disk),
            "--work-directory",
            str(work_directory),
            "--report",
            str(console_report_path),
        ]
        for flag, value in (
            ("--qemu", options.qemu),
            ("--accelerator", options.accelerator),
            ("--memory", options.memory),
            ("--cpus", options.cpus),
            ("--boot-timeout", options.boot_timeout),
            ("--prompt-timeout", options.prompt_timeout),
            ("--shutdown-timeout", options.shutdown_timeout),
        ):
            if value is not None:
                console_command.extend((flag, str(value)))
        for value in options.qemu_arg:
            console_command.append(f"--qemu-arg={value}")
        result = subprocess.run(
            console_command,
            cwd=REPOSITORY,
            check=False,
        )
        if result.returncode:
            raise CoreTestError(
                f"Console release harness failed with exit code {result.returncode}"
            )
        console_report = json.loads(
            physical_file(
                console_report_path, "Console test report"
            ).read_text(encoding="utf-8")
        )
        if not isinstance(console_report, dict) or console_report.get("passed") is not True:
            raise CoreTestError("Console release report did not pass")

        log_values = console_report.get("logs")
        if (
            console_report.get("boots") != 2
            or not isinstance(log_values, list)
            or len(log_values) != 2
        ):
            raise CoreTestError("Console release report does not contain two boot logs")
        required_runtime_markers = (
            "Mixtar Executor contract 1 / .NET 10 Native AOT",
            "APX valid:",
            "MixtarRVS: Executor zsh launch ready",
            "MixtarRVS: product runtime ready",
        )
        forbidden_runtime_markers = (
            "syntax error:",
            "unexpected end of file",
            "Unhandled exception.",
            "Aborted",
            "segfault at",
        )
        verified_logs: list[str] = []
        for index, value in enumerate(log_values, start=1):
            if not isinstance(value, str) or not value:
                raise CoreTestError(f"Boot {index} log path is invalid")
            candidate = Path(value)
            if not candidate.is_absolute():
                candidate = REPOSITORY / candidate
            log_path = physical_file(candidate, f"Boot {index} console log")
            try:
                log_path.relative_to(P4_ROOT)
            except ValueError as error:
                raise CoreTestError(f"Boot {index} log escapes Output/P4") from error
            log_text = log_path.read_text(encoding="utf-8", errors="replace")
            missing_markers = [
                marker for marker in required_runtime_markers if marker not in log_text
            ]
            if missing_markers:
                raise CoreTestError(
                    f"Boot {index} missed runtime markers: {', '.join(missing_markers)}"
                )
            failures = [
                marker for marker in forbidden_runtime_markers if marker in log_text
            ]
            if failures:
                raise CoreTestError(
                    f"Boot {index} contains runtime failures: {', '.join(failures)}"
                )
            verified_logs.append(report_path(log_path))
        runtime_evidence: dict[str, object] = {
            "boots_verified": len(verified_logs),
            "required_markers": list(required_runtime_markers),
            "forbidden_markers_absent": True,
            "logs": verified_logs,
        }

        report: dict[str, object] = {
            "schema": "mixtar.core-release-test.v1",
            "passed": True,
            "product": {
                "name": product.get("name"),
                "version": product.get("version"),
                "architecture": product.get("architecture"),
            },
            "disk": {
                "path": report_path(disk),
                "sha256": sha256(disk),
            },
            "core_validation": validation,
            "runtime": runtime_evidence,
            "console_test": {
                "path": report_path(console_report_path),
                "sha256": sha256(console_report_path),
            },
        }
        write_json_atomic(release_report_path, report)
    except (
        CoreTestError,
        json.JSONDecodeError,
        OSError,
        tomllib.TOMLDecodeError,
    ) as error:
        print(f"MixtarRVS Core release test failed: {error}", file=sys.stderr)
        return 1

    print(json.dumps(report, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
