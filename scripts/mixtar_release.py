#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import tomllib
from pathlib import Path
from typing import Any

REPOSITORY = Path(__file__).resolve().parent.parent
DEFAULT_LOCK = REPOSITORY / "Release" / "M1.lock.config"
SHA256 = re.compile(r"^[0-9a-f]{64}$")
COMMIT = re.compile(r"^[0-9a-f]{40}$")
IDENTIFIER = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._+-]*$")


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def table(document: dict[str, Any], name: str) -> dict[str, Any]:
    value = document.get(name)
    if not isinstance(value, dict):
        raise ValueError(f"missing table: {name}")
    return value


def validate(document: dict[str, Any], verify_files: bool = True) -> None:
    if document.get("schema") != 1:
        raise ValueError("release lock schema must be 1")
    release = table(document, "release")
    if release.get("name") != "MixtarRVS" or release.get("version") != "M1":
        raise ValueError("release identity must be MixtarRVS M1")
    if release.get("architecture") != "x86_64":
        raise ValueError("only x86_64 is supported by M1")
    for key in ("primary_slot", "update_slot"):
        if not IDENTIFIER.fullmatch(str(release.get(key, ""))):
            raise ValueError(f"invalid release.{key}")
    if release["primary_slot"] == release["update_slot"]:
        raise ValueError("release slots must be distinct")

    policy = table(document, "policy")
    if policy.get("update_anchor") != "openzfs":
        raise ValueError("M1 updates must be anchored to OpenZFS")
    if policy.get("linux_lts") is not False or policy.get("release_candidates") is not False:
        raise ValueError("M1 must not use LTS or release-candidate kernel policy")

    for name in ("linux", "openzfs", "openssl"):
        component = table(document, name)
        if not IDENTIFIER.fullmatch(str(component.get("version", ""))):
            raise ValueError(f"invalid {name}.version")
        if "-rc" in str(component["version"]):
            raise ValueError(f"{name} release candidates are forbidden")
        if not str(component.get("url", "")).startswith("https://"):
            raise ValueError(f"{name}.url must use HTTPS")
        if not SHA256.fullmatch(str(component.get("sha256", ""))):
            raise ValueError(f"invalid {name}.sha256")
    openzfs = table(document, "openzfs")
    openzfs_patch = openzfs.get("patch")
    if not isinstance(openzfs_patch, str) or not openzfs_patch or "\\" in openzfs_patch:
        raise ValueError("invalid openzfs.patch")
    if openzfs_patch.startswith("/") or any(
        part in ("", ".", "..") for part in openzfs_patch.split("/")
    ):
        raise ValueError("openzfs.patch must be repository-relative POSIX")
    if not SHA256.fullmatch(str(openzfs.get("patch_sha256", ""))):
        raise ValueError("invalid openzfs.patch_sha256")

    for name in ("openrc", "busybox"):
        component = table(document, name)
        if not str(component.get("repository", "")).startswith("https://"):
            raise ValueError(f"{name}.repository must use HTTPS")
        if not COMMIT.fullmatch(str(component.get("commit", ""))):
            raise ValueError(f"invalid {name}.commit")
    table(document, "zsh")
    table(document, "grml")
    table(document, "signing")

    inputs = document.get("inputs")
    if not isinstance(inputs, list) or not inputs:
        raise ValueError("release lock has no local inputs")
    seen: set[str] = set()
    for entry in inputs:
        if not isinstance(entry, dict):
            raise ValueError("release input must be a table")
        relative = entry.get("path")
        expected = entry.get("sha256")
        if not isinstance(relative, str) or not relative or "\\" in relative:
            raise ValueError("release input path must be repository-relative POSIX")
        if relative.startswith("/") or any(part in ("", ".", "..") for part in relative.split("/")):
            raise ValueError(f"unsafe release input path: {relative!r}")
        if relative in seen:
            raise ValueError(f"duplicate release input: {relative}")
        if not SHA256.fullmatch(str(expected)):
            raise ValueError(f"invalid input SHA-256: {relative}")
        seen.add(relative)
        if verify_files:
            path = (REPOSITORY / relative).resolve()
            try:
                path.relative_to(REPOSITORY)
            except ValueError as error:
                raise ValueError(f"release input escapes repository: {relative}") from error
            if not path.is_file():
                raise ValueError(f"release input is missing: {relative}")
            actual = digest(path)
            if actual != expected:
                raise ValueError(f"release input changed: {relative}: {actual}")


def load(path: Path = DEFAULT_LOCK, verify_files: bool = True) -> dict[str, Any]:
    with path.open("rb") as stream:
        document = tomllib.load(stream)
    validate(document, verify_files=verify_files)
    return document


def get(document: dict[str, Any], dotted: str) -> Any:
    value: Any = document
    for part in dotted.split("."):
        if not isinstance(value, dict) or part not in value:
            raise KeyError(dotted)
        value = value[part]
    return value


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate and read a pinned Mixtar release")
    parser.add_argument("command", choices=("validate", "json", "get", "inputs"))
    parser.add_argument("key", nargs="?")
    parser.add_argument("--lock", type=Path, default=DEFAULT_LOCK)
    parser.add_argument("--no-files", action="store_true")
    arguments = parser.parse_args()
    try:
        document = load(arguments.lock.resolve(), verify_files=not arguments.no_files)
        if arguments.command == "validate":
            print(arguments.lock.resolve())
        elif arguments.command == "json":
            json.dump(document, sys.stdout, sort_keys=True, separators=(",", ":"))
            print()
        elif arguments.command == "inputs":
            for item in document["inputs"]:
                print(f"{item['sha256']}  {item['path']}")
        else:
            if not arguments.key:
                parser.error("get requires a dotted key")
            value = get(document, arguments.key)
            if isinstance(value, (dict, list, bool)):
                print(json.dumps(value, sort_keys=True, separators=(",", ":")))
            else:
                print(value)
    except (OSError, ValueError, KeyError, tomllib.TOMLDecodeError) as error:
        print(f"Mixtar release lock: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
