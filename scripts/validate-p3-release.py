#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
import tarfile
from pathlib import Path
from typing import Any

REPOSITORY = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPOSITORY / "scripts"))
from mixtar_release import load as load_release

FORBIDDEN_ROOTS = {"proc", "sys", "dev", "run", "usr", "etc", "lib", "var"}
HOST_PATH = re.compile(r"(?:[A-Za-z]:\\\\Users\\\\|/mnt/[A-Za-z]/Users/|/home/[A-Za-z0-9._-]+/)")
MODULE_MAGIC = b"~Module signature appended~\n"


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def artifact_records(value: Any):
    if isinstance(value, dict):
        if isinstance(value.get("path"), str) and isinstance(value.get("sha256"), str):
            yield value
        for child in value.values():
            yield from artifact_records(child)
    elif isinstance(value, list):
        for child in value:
            yield from artifact_records(child)


def checked_path(relative: str) -> Path:
    declared = Path(relative)
    if declared.is_absolute():
        raise RuntimeError(f"artifact path must be repository-relative: {relative}")
    logical = (REPOSITORY / declared).absolute()
    physical = logical.resolve()
    output_root = (REPOSITORY / "Output").resolve()
    if not (physical.is_relative_to(REPOSITORY) or physical.is_relative_to(output_root)):
        raise RuntimeError(f"artifact escapes repository output roots: {relative}")
    return logical


def wsl_path(path: Path) -> str:
    absolute = path.absolute()
    drive = absolute.drive
    if len(drive) != 2 or drive[1] != ":":
        raise RuntimeError(f"cannot map path into WSL: {absolute}")
    return f"/mnt/{drive[0].lower()}/{absolute.as_posix()[3:]}"


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate the published Mixtar M1 release")
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--signature", type=Path, required=True)
    parser.add_argument("--public-key", type=Path, required=True)
    parser.add_argument("--certificate", type=Path, required=True)
    parser.add_argument("--lock", type=Path, default=REPOSITORY / "Release" / "M1.lock.config")
    parser.add_argument("--wsl-distro", default="Debian")
    parser.add_argument("--report", type=Path, required=True)
    arguments = parser.parse_args()
    checks: dict[str, bool] = {}
    details: dict[str, Any] = {}
    try:
        lock = load_release(arguments.lock.resolve())
        checks["release_lock"] = lock["release"]["version"] == "M1"
        manifest = json.loads(arguments.manifest.read_text(encoding="utf-8"))
        checks["manifest_schema"] = manifest.get("schema") == "mixtar.m1-image.v1"
        checks["openzfs_runtime_patch"] = (
            manifest.get("openzfs", {}).get("mixtar_patch_sha256")
            == lock["openzfs"]["patch_sha256"]
            and manifest.get("openzfs", {}).get("device_namespace")
            == "/System/Devices"
            and manifest.get("openzfs", {}).get("hardware_namespace")
            == "/System/Hardware"
            and manifest.get("openzfs", {}).get("process_namespace")
            == "/System/Processes"
            and manifest.get("openzfs", {}).get("hostid_path")
            == "/System/Configuration/OpenZFS/hostid"
        )
        records = list(artifact_records(manifest.get("artifacts", {})))
        verified = 0
        for item in records:
            path = checked_path(item["path"])
            if not path.is_file() or digest(path) != item["sha256"]:
                raise RuntimeError(f"artifact hash mismatch: {item['path']}")
            verified += 1
        checks["artifact_hashes"] = verified >= 10
        details["verified_artifacts"] = verified
        text = arguments.manifest.read_text(encoding="utf-8")
        checks["no_host_paths"] = HOST_PATH.search(text) is None
        if not checks["no_host_paths"]:
            raise RuntimeError("release manifest contains a host-specific path")
        root_item = manifest["artifacts"]["root_archive"]
        root_archive = checked_path(root_item["path"])
        exposed: set[str] = set()
        module_count = 0
        signed_count = 0
        sdk_symvers = False
        with tarfile.open(root_archive, "r:*") as archive:
            for member in archive:
                normalized = member.name.lstrip("./")
                if normalized:
                    exposed.add(normalized.split("/", 1)[0])
                if normalized.endswith("/Development/Module.symvers"):
                    sdk_symvers = member.size > 0
                if member.isfile() and normalized.endswith(".ko"):
                    module_count += 1
                    stream = archive.extractfile(member)
                    if stream is not None and stream.read().endswith(MODULE_MAGIC):
                        signed_count += 1
        checks["no_public_fhs"] = not bool(exposed & FORBIDDEN_ROOTS)
        checks["module_sdk"] = sdk_symvers
        checks["all_modules_signed"] = module_count > 0 and signed_count == module_count
        details["module_count"] = module_count
        details["signed_module_count"] = signed_count
        verify = subprocess.run([
            "wsl.exe", "-d", arguments.wsl_distro, "--", "/usr/bin/openssl", "dgst",
            "-sha256", "-verify", wsl_path(arguments.public_key),
            "-signature", wsl_path(arguments.signature),
            wsl_path(arguments.manifest),
        ], check=False, capture_output=True, text=True, timeout=60)
        checks["manifest_signature"] = verify.returncode == 0
        for name in ("efi_a", "efi_b", "recovery_efi"):
            efi = checked_path(manifest["artifacts"][name]["path"])
            result = subprocess.run([
                "wsl.exe", "-d", arguments.wsl_distro, "--", "/usr/bin/sbverify", "--cert",
                wsl_path(arguments.certificate),
                wsl_path(efi),
            ], check=False, capture_output=True, text=True, timeout=60)
            checks[f"secure_boot_{name}"] = result.returncode == 0
        checks["immutable_root"] = manifest["artifacts"]["root"].get("readonly") is True
        checks["rollback_contract"] = manifest["update"].get("previous_release_preserved") is True
        if not all(checks.values()):
            raise RuntimeError("one or more P3 release checks failed")
        passed = True
        error = None
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.SubprocessError) as failure:
        passed = False
        error = str(failure)
    report = {
        "schema": "mixtar.m1-release-validation.v1",
        "passed": passed,
        "checks": checks,
        "details": details,
    }
    if error:
        report["error"] = error
    arguments.report.parent.mkdir(parents=True, exist_ok=True)
    arguments.report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    if not passed:
        print(json.dumps(report, indent=2, sort_keys=True))
        return 1
    print("MIXTAR_M1_RELEASE_VALID")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
