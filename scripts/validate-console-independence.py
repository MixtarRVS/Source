#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
import tarfile
import tomllib
from pathlib import Path
from typing import Any

REPOSITORY = Path(__file__).resolve().parent.parent
FORBIDDEN_PATH_TERMS = (
    "avalonia",
    "dotnet",
    "mddm",
    "mwm",
    "wayland",
    "xwayland",
)
REQUIRED_CONSOLE_PATHS = {
    "System/Configuration/Layout.config",
    "System/Core/BusyBox/busybox",
    "System/Init/MixtarRVS",
    "System/Terminal/ZSH/zsh",
}
OPENRC_PREFIX = "System/Configuration/OpenRC/init.d/"


def normalized_tar_path(value: str) -> str:
    result = value.replace("\\", "/")
    while result.startswith("./"):
        result = result[2:]
    return result.strip("/")


def load_toml(path: Path) -> dict[str, Any]:
    with path.open("rb") as stream:
        return tomllib.load(stream)


def repository_artifact(relative: str) -> Path:
    declared = Path(relative)
    if declared.is_absolute():
        raise RuntimeError(f"artifact path must be repository-relative: {relative}")
    logical = (REPOSITORY / declared).absolute()
    physical = logical.resolve()
    output = (REPOSITORY / "Output").resolve()
    if not (physical.is_relative_to(REPOSITORY) or physical.is_relative_to(output)):
        raise RuntimeError(f"artifact escapes repository outputs: {relative}")
    if not logical.is_file():
        raise RuntimeError(f"artifact is missing: {relative}")
    return logical


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Prove that the Mixtar console release is independent of P4 graphics."
    )
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--profile", type=Path, required=True)
    parser.add_argument("--budget", type=Path, required=True)
    parser.add_argument("--runtime-report", type=Path)
    parser.add_argument("--allow-missing-runtime", action="store_true")
    parser.add_argument("--report", type=Path, required=True)
    arguments = parser.parse_args()

    checks: dict[str, bool] = {}
    details: dict[str, Any] = {}
    error: str | None = None
    try:
        profile = load_toml(arguments.profile.resolve())
        product = profile.get("product", {})
        checks["console_profile"] = (
            product.get("mode") == "console"
            and product.get("graphical") is False
            and product.get("graphical_overlay") != profile.get("layout", {}).get("source")
        )

        budget = load_toml(arguments.budget.resolve())
        regression = budget.get("console_regression", {})
        checks["console_budget_contract"] = all(
            regression.get(name) is True
            for name in (
                "boots_without_graphical_stack",
                "boots_when_mwm_fails",
                "boots_when_avalonia_is_missing",
                "requires_independent_console_image_gate",
            )
        )

        manifest = json.loads(arguments.manifest.read_text(encoding="utf-8"))
        root_record = manifest.get("artifacts", {}).get("root_archive", {})
        root_archive = repository_artifact(root_record["path"])
        names: set[str] = set()
        graphical_paths: list[str] = []
        graphical_services: list[str] = []
        service_count = 0
        with tarfile.open(root_archive, "r:*") as archive:
            for member in archive:
                name = normalized_tar_path(member.name)
                if not name:
                    continue
                names.add(name)
                lower_name = name.casefold()
                if any(term in lower_name for term in FORBIDDEN_PATH_TERMS):
                    graphical_paths.append(name)
                if member.isfile() and name.startswith(OPENRC_PREFIX):
                    service_count += 1
                    stream = archive.extractfile(member)
                    if stream is not None:
                        text = stream.read(1024 * 1024).decode("utf-8", errors="replace").casefold()
                        if any(term in text for term in FORBIDDEN_PATH_TERMS):
                            graphical_services.append(name)

        missing = sorted(REQUIRED_CONSOLE_PATHS - names)
        checks["required_console_closure"] = not missing and service_count > 0
        checks["no_graphical_payload"] = not graphical_paths
        checks["openrc_has_no_graphical_dependency"] = not graphical_services
        details["missing_console_paths"] = missing
        details["graphical_paths"] = sorted(graphical_paths)
        details["graphical_services"] = sorted(graphical_services)
        details["openrc_service_count"] = service_count
        details["root_archive"] = root_record["path"]

        runtime_present = arguments.runtime_report is not None
        runtime_ok = False
        if runtime_present:
            runtime = json.loads(arguments.runtime_report.read_text(encoding="utf-8"))
            markers = runtime.get("markers", {})
            runtime_ok = (
                runtime.get("schema") == "mixtar.p2-qemu.v1"
                and runtime.get("passed") is True
                and runtime.get("boots") == 2
                and all(value is True for value in markers.values())
            )
        checks["runtime_console_evidence"] = runtime_ok or arguments.allow_missing_runtime
        details["runtime_evidence_present"] = runtime_present
        details["runtime_evidence_accepted"] = runtime_ok
        details["runtime_evidence_waived"] = bool(
            arguments.allow_missing_runtime and not runtime_ok
        )

        if not all(checks.values()):
            raise RuntimeError("one or more console independence checks failed")
        passed = True
    except (OSError, ValueError, KeyError, RuntimeError, tarfile.TarError) as failure:
        passed = False
        error = str(failure)

    report: dict[str, Any] = {
        "schema": "mixtar.p4-console-independence.v1",
        "passed": passed,
        "checks": checks,
        "details": details,
    }
    if error is not None:
        report["error"] = error
    arguments.report.parent.mkdir(parents=True, exist_ok=True)
    arguments.report.write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    if not passed:
        print(json.dumps(report, indent=2, sort_keys=True))
        return 1
    print("MIXTAR_P4_CONSOLE_INDEPENDENT")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
