#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import sys
import tomllib
from typing import Any


REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_CONFIG = (
    REPO_ROOT
    / "Root"
    / "System"
    / "Configuration"
    / "Layout.config"
)

REQUIRED_LAYOUT = {
    "system": "/System",
    "commands": "/System/Commands",
    "core": "/System/Core",
    "init": "/System/Init",
    "libraries": "/System/Libraries",
    "configuration": "/System/Configuration",
    "state": "/System/State",
    "cache": "/System/Cache",
    "logs": "/System/Logs",
    "runtime": "/System/Runtime",
    "processes": "/System/Processes",
    "hardware": "/System/Hardware",
    "devices": "/System/Devices",
    "terminal": "/System/Terminal",
    "users": "/Users",
    "volumes": "/Volumes",
    "temporary": "/Temporary",
}

FORBIDDEN_PUBLIC_ROOTS = ("/proc", "/sys", "/dev", "/run", "/usr", "/etc", "/lib", "/var")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
COMMIT_RE = re.compile(r"^[0-9a-f]{40}$")


def load_config(path: Path) -> dict[str, Any]:
    with path.open("rb") as stream:
        config = tomllib.load(stream)
    validate_config(config)
    return config


def require_table(config: dict[str, Any], name: str) -> dict[str, Any]:
    value = config.get(name)
    if not isinstance(value, dict):
        raise ValueError(f"missing or invalid table: {name}")
    return value


def validate_config(config: dict[str, Any]) -> None:
    if config.get("schema") != 1:
        raise ValueError("Layout.config schema must be 1")

    identity = require_table(config, "identity")
    if identity.get("name") != "MixtarRVS":
        raise ValueError("identity.name must be MixtarRVS")
    if identity.get("architecture") != "x86_64":
        raise ValueError("identity.architecture must be x86_64")

    layout = require_table(config, "layout")
    for key, expected in REQUIRED_LAYOUT.items():
        if layout.get(key) != expected:
            raise ValueError(f"layout.{key} must be {expected}")
    for key, value in layout.items():
        if not isinstance(value, str) or not value.startswith("/"):
            raise ValueError(f"layout.{key} must be an absolute path")
        if value in FORBIDDEN_PUBLIC_ROOTS:
            raise ValueError(f"layout.{key} uses forbidden public root {value}")

    boot = require_table(config, "boot")
    for key in ("pid1", "system_shell", "user_shell"):
        value = boot.get(key)
        if not isinstance(value, str) or not value.startswith("/System/"):
            raise ValueError(f"boot.{key} must be below /System")
    if not isinstance(boot.get("qemu_memory_mib"), int) or boot["qemu_memory_mib"] < 64:
        raise ValueError("boot.qemu_memory_mib must be at least 64")
    if not isinstance(boot.get("qemu_timeout_seconds"), int) or boot["qemu_timeout_seconds"] < 1:
        raise ValueError("boot.qemu_timeout_seconds must be positive")
    if not isinstance(boot.get("source_date_epoch"), int) or boot["source_date_epoch"] < 0:
        raise ValueError("boot.source_date_epoch must be non-negative")
    if not isinstance(boot.get("console"), str) or not re.fullmatch(r"[A-Za-z0-9._-]+", boot["console"]):
        raise ValueError("boot.console is invalid")

    build = require_table(config, "build")
    jobs = build.get("jobs")
    if jobs != "auto" and (not isinstance(jobs, int) or jobs < 1):
        raise ValueError("build.jobs must be auto or a positive integer")
    if not isinstance(build.get("compiler_cache"), bool):
        raise ValueError("build.compiler_cache must be boolean")
    compiler_cache_size = build.get("compiler_cache_size")
    if not isinstance(compiler_cache_size, str) or not re.fullmatch(
        r"[1-9][0-9]*(?:KiB|MiB|GiB|TiB)", compiler_cache_size
    ):
        raise ValueError("build.compiler_cache_size must use a binary size suffix")
    if not isinstance(build.get("wsl_distro"), str) or not build["wsl_distro"]:
        raise ValueError("build.wsl_distro must not be empty")
    cache_directory = build.get("cache_directory")
    if not isinstance(cache_directory, str) or not re.fullmatch(r"[A-Za-z0-9._-]+", cache_directory):
        raise ValueError("build.cache_directory must be one relative directory")
    if cache_directory in (".", ".."):
        raise ValueError("build.cache_directory must not traverse")
    host_cache = build.get("host_cache")
    if not isinstance(host_cache, str) or host_cache.startswith("/"):
        raise ValueError("build.host_cache must be relative")
    if any(part in ("", ".", "..") for part in host_cache.replace("\\", "/").split("/")):
        raise ValueError("build.host_cache must not traverse")

    components = require_table(config, "components")
    linux = require_table(components, "linux")
    if linux.get("architecture") != identity["architecture"]:
        raise ValueError("Linux architecture must match identity.architecture")
    if set(linux) != {"architecture"}:
        raise ValueError("components.linux may contain capabilities, not release pins")
    openrc = require_table(components, "openrc")
    if openrc.get("role") != "pid1" or set(openrc) != {"role"}:
        raise ValueError("components.openrc must only declare its PID 1 role")
    busybox = require_table(components, "busybox")
    modules_directory = busybox.get("modules_directory")
    if not isinstance(modules_directory, str) or not re.fullmatch(
        r"/System(?:/[A-Za-z0-9._-]+)+", modules_directory
    ):
        raise ValueError("components.busybox.modules_directory must be an absolute /System path")
    depmod_file = busybox.get("depmod_file")
    if not isinstance(depmod_file, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", depmod_file):
        raise ValueError("components.busybox.depmod_file must be a plain file name")
    symbols = busybox.get("kconfig_symbols")
    if not isinstance(symbols, list) or not symbols:
        raise ValueError("components.busybox.kconfig_symbols must be a non-empty list")
    if any(not isinstance(symbol, str) or not re.fullmatch(r"CONFIG_[A-Z0-9_]+", symbol) for symbol in symbols):
        raise ValueError("BusyBox Kconfig symbols must use CONFIG_* names")
    applets = busybox.get("expected_applets")
    if not isinstance(applets, list) or not applets:
        raise ValueError("components.busybox.expected_applets must be a non-empty list")
    if any(not isinstance(applet, str) or not re.fullmatch(r"[a-z][a-z0-9_-]*", applet) for applet in applets):
        raise ValueError("BusyBox applet names are invalid")
    if len(set(symbols)) != len(symbols) or len(set(applets)) != len(applets):
        raise ValueError("BusyBox symbols and applets must not contain duplicates")
    zsh = require_table(components, "zsh")
    if zsh.get("role") != "interactive-shell" or set(zsh) != {"role"}:
        raise ValueError("components.zsh must only declare its shell role")

    security = require_table(config, "security")
    public_key = security.get("release_public_key")
    if not isinstance(public_key, str) or not public_key.startswith("/System/"):
        raise ValueError("security.release_public_key must be a native /System path")
    if security.get("module_signatures_required") is not True:
        raise ValueError("module signatures must be required")
    if security.get("secure_boot_artifacts") is not True:
        raise ValueError("Secure Boot artifacts must be enabled")

    update = require_table(config, "update")
    for key in ("dataset_parent", "esp_mount", "firmware_path", "previous_firmware_path", "recovery_firmware_path", "transaction_state"):
        value = update.get(key)
        if not isinstance(value, str) or not value:
            raise ValueError(f"update.{key} must not be empty")
    if update["dataset_parent"] != "mixtar/ROOT":
        raise ValueError("update.dataset_parent must be mixtar/ROOT")
    for key in ("esp_mount", "firmware_path", "previous_firmware_path", "recovery_firmware_path", "transaction_state"):
        if not update[key].startswith("/System/"):
            raise ValueError(f"update.{key} must use the native /System namespace")

    test = require_table(config, "test")
    command_line_key = test.get("command_line_key")
    if not isinstance(command_line_key, str) or not re.fullmatch(r"[A-Za-z][A-Za-z0-9_.-]*", command_line_key):
        raise ValueError("test.command_line_key is invalid")
    modes = (test.get("poweroff_mode"), test.get("reboot_mode"))
    if any(not isinstance(mode, str) or not re.fullmatch(r"[A-Za-z][A-Za-z0-9_.-]*", mode) for mode in modes):
        raise ValueError("test modes are invalid")
    if modes[0] == modes[1]:
        raise ValueError("test modes must be distinct")


def get_key(config: dict[str, Any], dotted_key: str) -> Any:
    value: Any = config
    for part in dotted_key.split("."):
        if not isinstance(value, dict) or part not in value:
            raise KeyError(dotted_key)
        value = value[part]
    return value


def main() -> int:
    parser = argparse.ArgumentParser(description="Read and validate Mixtar Layout.config")
    parser.add_argument("command", choices=("validate", "json", "get", "get-list"))
    parser.add_argument("key", nargs="?")
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    args = parser.parse_args()

    try:
        config = load_config(args.config.resolve())
        if args.command == "validate":
            print(args.config.resolve())
        elif args.command == "json":
            json.dump(config, sys.stdout, sort_keys=True, separators=(",", ":"))
            print()
        elif args.command == "get":
            if not args.key:
                parser.error("get requires a dotted key")
            value = get_key(config, args.key)
            if isinstance(value, (dict, list, bool)):
                print(json.dumps(value, sort_keys=True, separators=(",", ":")))
            else:
                print(value)
        else:
            if not args.key:
                parser.error("get-list requires a dotted key")
            value = get_key(config, args.key)
            if not isinstance(value, list) or any(not isinstance(item, str) for item in value):
                raise ValueError(f"{args.key} is not a list of strings")
            for item in value:
                print(item)
    except (OSError, ValueError, KeyError, tomllib.TOMLDecodeError) as error:
        print(f"Layout.config: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
