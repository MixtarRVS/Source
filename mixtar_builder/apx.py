from __future__ import annotations

import argparse
import json
import re
import sys
import tomllib
import uuid
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any, Sequence

APX_SCHEMA = 1
APPLICATION_ID = re.compile(r"^[A-Za-z0-9](?:[A-Za-z0-9._-]{1,126}[A-Za-z0-9])$")
IDENTITY = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")
KNOWN_CAPABILITIES = frozenset(
    {
        "ui.window",
        "ui.notifications",
        "network.client",
        "network.listen",
        "storage.user",
        "storage.volumes.read",
        "storage.volumes.write",
        "devices.input",
        "devices.graphics",
        "process.inspect",
        "system.status",
        "system.admin",
    }
)
ENTRY_CONTEXTS = ("graphical", "terminal")


class ApxError(RuntimeError):
    pass


@dataclass(frozen=True)
class ApxEntry:
    context: str
    relative_path: PurePosixPath
    executable: Path
    entry_type: str = "native"


@dataclass(frozen=True)
class ApxApplication:
    application_id: str
    name: str
    version: str


@dataclass(frozen=True)
class ApxBundle:
    root: Path
    config: Path
    application: ApxApplication
    entries: dict[str, ApxEntry]
    required_capabilities: tuple[str, ...]
    optional_capabilities: tuple[str, ...]

    def summary(self) -> dict[str, Any]:
        return {
            "schema": "mixtar.apx-validation.v1",
            "valid": True,
            "bundle": str(self.root),
            "config": str(self.config),
            "application": {
                "id": self.application.application_id,
                "name": self.application.name,
                "version": self.application.version,
            },
            "entries": {
                name: {
                    "type": entry.entry_type,
                    "path": entry.relative_path.as_posix(),
                    "elf": "x86_64",
                }
                for name, entry in sorted(self.entries.items())
            },
            "permissions": {
                "required": list(self.required_capabilities),
                "optional": list(self.optional_capabilities),
            },
        }


def _table(data: dict[str, Any], key: str) -> dict[str, Any]:
    value = data.get(key)
    if not isinstance(value, dict):
        raise ApxError(f"missing or invalid [{key}] table")
    return value


def _text(data: dict[str, Any], key: str, label: str) -> str:
    value = data.get(key)
    if not isinstance(value, str) or not value.strip():
        raise ApxError(f"missing or invalid text value: {label}")
    if "\x00" in value:
        raise ApxError(f"NUL is not allowed in {label}")
    return value.strip()


def _capabilities(data: dict[str, Any], key: str) -> tuple[str, ...]:
    value = data.get(key, [])
    if not isinstance(value, list) or any(not isinstance(item, str) for item in value):
        raise ApxError(f"permissions.{key} must be an array of strings")
    normalized = tuple(item.strip() for item in value)
    if any(not item for item in normalized):
        raise ApxError(f"permissions.{key} contains an empty capability")
    if len(set(normalized)) != len(normalized):
        raise ApxError(f"permissions.{key} contains a duplicate capability")
    unknown = sorted(set(normalized) - KNOWN_CAPABILITIES)
    if unknown:
        raise ApxError(f"unknown capabilities in permissions.{key}: {', '.join(unknown)}")
    return normalized


def _safe_entry_path(bundle: Path, value: str, label: str) -> tuple[PurePosixPath, Path]:
    if "\\" in value:
        raise ApxError(f"{label} must use '/' separators")
    logical = PurePosixPath(value)
    if logical.is_absolute() or not logical.parts or any(part in ("", ".", "..") for part in logical.parts):
        raise ApxError(f"{label} must be a non-empty relative path without '.' or '..'")
    cursor = bundle
    for part in logical.parts:
        cursor /= part
        if cursor.is_symlink():
            raise ApxError(f"{label} may not traverse a symbolic link: {logical.as_posix()}")
    try:
        executable = cursor.resolve(strict=True)
    except OSError as error:
        raise ApxError(f"{label} does not exist: {logical.as_posix()}") from error
    if not executable.is_relative_to(bundle) or not executable.is_file():
        raise ApxError(f"{label} escapes the bundle or is not a file")
    return logical, executable


def _validate_elf_x86_64(path: Path, label: str) -> None:
    with path.open("rb") as stream:
        header = stream.read(20)
    if len(header) < 20 or header[:4] != b"\x7fELF":
        raise ApxError(f"{label} is not an ELF executable")
    if header[4] != 2 or header[5] != 1:
        raise ApxError(f"{label} must be a little-endian ELF64 executable")
    elf_type = int.from_bytes(header[16:18], "little")
    machine = int.from_bytes(header[18:20], "little")
    if elf_type not in (2, 3) or machine != 62:
        raise ApxError(f"{label} must be an x86_64 ET_EXEC or ET_DYN ELF")


def _entry(bundle: Path, entries: dict[str, Any], context: str) -> ApxEntry | None:
    raw = entries.get(context)
    if raw is None:
        return None
    if not isinstance(raw, dict):
        raise ApxError(f"entry.{context} must be a table")
    entry_type = _text(raw, "type", f"entry.{context}.type")
    if entry_type != "native":
        raise ApxError(f"entry.{context}.type must be 'native' in APX v1")
    path_text = _text(raw, "path", f"entry.{context}.path")
    logical, executable = _safe_entry_path(bundle, path_text, f"entry.{context}.path")
    _validate_elf_x86_64(executable, f"entry.{context}.path")
    return ApxEntry(context, logical, executable, entry_type)


def load_bundle(path: Path) -> ApxBundle:
    declared = path.expanduser().absolute()
    if declared.is_symlink():
        raise ApxError("the APX bundle may not be a symbolic link")
    if not declared.is_dir() or not declared.name.endswith(".apx"):
        raise ApxError("the bundle must be a directory with the exact '.apx' suffix")
    bundle = declared.resolve(strict=True)
    base_name = bundle.name[:-4]
    if not base_name:
        raise ApxError("the APX bundle name is empty")
    config = bundle / f"{base_name}.config"
    if config.is_symlink() or not config.is_file():
        raise ApxError(f"matching configuration file is missing: {base_name}.config")
    try:
        with config.open("rb") as stream:
            data = tomllib.load(stream)
    except tomllib.TOMLDecodeError as error:
        raise ApxError(f"invalid TOML in {config.name}: {error}") from error

    schema = data.get("schema")
    if isinstance(schema, bool) or schema != APX_SCHEMA:
        raise ApxError(f"unsupported APX schema: {schema!r}")
    application_data = _table(data, "application")
    application_id = _text(application_data, "id", "application.id")
    if not APPLICATION_ID.fullmatch(application_id) or "." not in application_id:
        raise ApxError("application.id must be a dotted stable identifier")
    application = ApxApplication(
        application_id=application_id,
        name=_text(application_data, "name", "application.name"),
        version=_text(application_data, "version", "application.version"),
    )

    entry_data = _table(data, "entry")
    unknown_contexts = sorted(set(entry_data) - set(ENTRY_CONTEXTS))
    if unknown_contexts:
        raise ApxError(f"unknown APX entry contexts: {', '.join(unknown_contexts)}")
    entries = {
        context: entry
        for context in ENTRY_CONTEXTS
        if (entry := _entry(bundle, entry_data, context)) is not None
    }
    if not entries:
        raise ApxError("APX requires entry.graphical or entry.terminal")

    permission_data = data.get("permissions", {})
    if not isinstance(permission_data, dict):
        raise ApxError("[permissions] must be a table")
    required = _capabilities(permission_data, "required")
    optional = _capabilities(permission_data, "optional")
    overlap = sorted(set(required) & set(optional))
    if overlap:
        raise ApxError(f"capabilities cannot be both required and optional: {', '.join(overlap)}")

    return ApxBundle(bundle, config, application, entries, required, optional)


def create_launch_plan(
    bundle: ApxBundle,
    context: str,
    user: str,
    session: str,
    arguments: Sequence[str] = (),
    diagnostics: bool = False,
    wait: bool = False,
) -> dict[str, Any]:
    if context not in ENTRY_CONTEXTS:
        raise ApxError("launch context must be 'graphical' or 'terminal'")
    if not IDENTITY.fullmatch(user):
        raise ApxError("user name is not valid for a launch descriptor")
    if not IDENTITY.fullmatch(session):
        raise ApxError("session id is not valid for a launch descriptor")
    if any("\x00" in value for value in arguments):
        raise ApxError("application arguments may not contain NUL")
    entry = bundle.entries.get(context)
    fallback = False
    if entry is None:
        entry = next(iter(bundle.entries.values()))
        fallback = True
    launch_id = f"launch-{uuid.uuid4()}"
    return {
        "schema": "mixtar.launch.v1",
        "launch": {
            "id": launch_id,
            "context": context,
            "entry_context": entry.context,
            "fallback_entry": fallback,
            "diagnostics": diagnostics,
            "wait": wait,
        },
        "application": {
            "id": bundle.application.application_id,
            "name": bundle.application.name,
            "version": bundle.application.version,
        },
        "session": {"id": session, "user": user},
        "paths": {
            "bundle": str(bundle.root),
            "executable": str(entry.executable),
            "app_data": f"/Users/{user}/Applications/{bundle.application.application_id}",
        },
        "process": {
            "shell": False,
            "argv": [str(entry.executable), *arguments],
        },
        "permissions": {
            "required": list(bundle.required_capabilities),
            "optional": list(bundle.optional_capabilities),
        },
    }


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="mixtar-apx",
        description="Validate APX v1 bundles and produce Executor launch plans.",
    )
    commands = parser.add_subparsers(dest="command", required=True)
    validate = commands.add_parser("validate", help="Validate one APX bundle")
    validate.add_argument("bundle", type=Path)
    validate.add_argument("--json", action="store_true")
    plan = commands.add_parser("plan", help="Produce a launch plan without executing it")
    plan.add_argument("--context", choices=ENTRY_CONTEXTS, required=True)
    plan.add_argument("--user", default="Administrator")
    plan.add_argument("--session", default="console")
    plan.add_argument("--diagnostics", action="store_true")
    plan.add_argument("--wait", action="store_true")
    plan.add_argument("bundle", type=Path)
    plan.add_argument("application_arguments", nargs=argparse.REMAINDER)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    values = list(sys.argv[1:] if argv is None else argv)
    values = ["--help" if value == "/?" else value for value in values]
    args = _parser().parse_args(values)
    try:
        bundle = load_bundle(args.bundle)
        if args.command == "validate":
            report = bundle.summary()
            if args.json:
                print(json.dumps(report, indent=2, sort_keys=True))
            else:
                print(f"APX valid: {bundle.application.application_id}")
                print(f"Bundle: {bundle.root}")
                print(f"Entries: {', '.join(sorted(bundle.entries))}")
            return 0
        application_arguments = list(args.application_arguments)
        if application_arguments[:1] == ["--"]:
            application_arguments.pop(0)
        plan = create_launch_plan(
            bundle,
            context=args.context,
            user=args.user,
            session=args.session,
            arguments=application_arguments,
            diagnostics=args.diagnostics,
            wait=args.wait,
        )
        print(json.dumps(plan, indent=2, sort_keys=True))
        return 0
    except (ApxError, OSError, ValueError) as error:
        print(f"mixtar-apx: error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
