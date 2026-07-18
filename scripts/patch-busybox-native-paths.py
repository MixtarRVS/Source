#!/usr/bin/env python3
from __future__ import annotations

import re
import sys
from pathlib import Path

PATH_REPLACEMENTS = {
    b"/etc/passwd": b"/System/State/Accounts/passwd",
    b"/etc/shadow": b"/System/State/Accounts/shadow",
    b"/etc/group": b"/System/State/Accounts/group",
    b"/etc/gshadow": b"/System/State/Accounts/gshadow",
    b"/etc/shells": b"/System/Configuration/Accounts/shells",
    b"/etc/securetty": b"/System/Configuration/Accounts/securetty",
    b"/etc/nologin": b"/System/State/Accounts/nologin",
    b"/etc/issue": b"/System/Configuration/Terminal/issue",
    b"/etc/motd": b"/System/Configuration/Terminal/motd",
    b"/etc/mdev.conf": b"/System/Configuration/Devices/mdev.config",
    b"/etc/resolv.conf": b"/System/Runtime/Network/resolv.conf",
    b"/var/run/utmp": b"/System/Runtime/Accounts/utmp",
    b"/run/utmp": b"/System/Runtime/Accounts/utmp",
    b"/var/log/wtmp": b"/System/Logs/Accounts/wtmp",
    b"/var/log/lastlog": b"/System/Logs/Accounts/lastlog",
    b'"/dev"': b'"/System/Devices"',
    b"/dev/": b"/System/Devices/",
}

MDEV_SYSFS_ATTRIBUTE_RESTORATIONS = {
    b'strcpy(path_end, "/System/Devices");': b'strcpy(path_end, "/dev");',
    b'strcmp(fileName + len, "/System/Devices")': b'strcmp(fileName + len, "/dev")',
}

CONFIG_VALUES = {
    "CONFIG_GETTY": "y",
    "CONFIG_LOGIN": "y",
    "CONFIG_PASSWD": "y",
    "CONFIG_CRYPTPW": "y",
    "CONFIG_FEATURE_SHADOWPASSWDS": "y",
    "CONFIG_FEATURE_SECURETTY": "y",
    "CONFIG_USE_BB_PWD_GRP": "y",
    "CONFIG_USE_BB_SHADOW": "y",
    "CONFIG_USE_BB_CRYPT": "y",
    "CONFIG_USE_BB_CRYPT_SHA": "y",
    "CONFIG_FEATURE_DEFAULT_PASSWD_ALGO": '"sha512"',
}


def source_candidates(root: Path) -> list[Path]:
    candidates = [root]
    if root.is_dir():
        candidates.extend(root.glob("busybox-*"))
        candidates.extend(root.glob("*/busybox-*"))
    return candidates


def find_source(arguments: list[str]) -> Path:
    seen: set[Path] = set()
    for raw in arguments:
        if not raw:
            continue
        root = Path(raw).expanduser().resolve()
        for candidate in source_candidates(root):
            if candidate in seen:
                continue
            seen.add(candidate)
            if (candidate / "include/libbb.h").is_file() and (candidate / "libbb").is_dir():
                return candidate
    raise SystemExit("cannot locate extracted BusyBox source tree")


def patch_paths(source: Path) -> int:
    changed = 0
    observed = {old: 0 for old in PATH_REPLACEMENTS}
    suffixes = {".c", ".h", ".S"}

    for path in source.rglob("*"):
        if not path.is_file() or path.suffix not in suffixes:
            continue
        data = path.read_bytes()
        updated = data
        for old, new in PATH_REPLACEMENTS.items():
            occurrences = updated.count(old)
            if occurrences:
                observed[old] += occurrences
                updated = updated.replace(old, new)
            elif new in updated:
                observed[old] += updated.count(new)
        if path == source / "util-linux/mdev.c":
            for overpatched, sysfs_attribute in MDEV_SYSFS_ATTRIBUTE_RESTORATIONS.items():
                if overpatched not in updated and sysfs_attribute not in updated:
                    raise SystemExit("BusyBox mdev sysfs attribute marker not found")
                updated = updated.replace(overpatched, sysfs_attribute)
        if updated != data:
            path.write_bytes(updated)
            changed += 1

    for required in (b"/etc/passwd", b"/etc/shadow", b'"/dev"', b"/dev/"):
        if observed[required] == 0:
            raise SystemExit(f"BusyBox path marker not found: {required.decode()}")

    ttyname_path = source / "libbb/xfuncs_printf.c"
    ttyname_source = ttyname_path.read_bytes()
    ttyname_old = (
        b"char* FAST_FUNC xmalloc_ttyname(int fd)\n"
        b"{\n"
        b"\tchar buf[128];\n"
        b"\tint r = ttyname_r(fd, buf, sizeof(buf) - 1);\n"
        b"\tif (r)\n"
        b"\t\treturn NULL;\n"
        b"\treturn xstrdup(buf);\n"
        b"}\n"
    )
    ttyname_new = (
        b"char* FAST_FUNC xmalloc_ttyname(int fd)\n"
        b"{\n"
        b"\tchar buf[128];\n"
        b"\tint r = ttyname_r(fd, buf, sizeof(buf) - 1);\n"
        b"\tif (r) {\n"
        b"\t\tsnprintf(buf, sizeof(buf), \"/System/Processes/self/fd/%d\", fd);\n"
        b"\t\treturn xmalloc_readlink(buf);\n"
        b"\t}\n"
        b"\treturn xstrdup(buf);\n"
        b"}\n"
    )
    if ttyname_old in ttyname_source:
        if ttyname_source.count(ttyname_old) != 1:
            raise SystemExit("BusyBox ttyname implementation is ambiguous")
        ttyname_path.write_bytes(ttyname_source.replace(ttyname_old, ttyname_new))
        changed += 1
    elif ttyname_new not in ttyname_source:
        raise SystemExit("BusyBox ttyname implementation changed upstream")

    return changed


def find_config(arguments: list[str]) -> Path:
    for raw in arguments:
        if not raw:
            continue
        candidate = Path(raw).expanduser().resolve()
        if candidate.is_file() and candidate.name == ".config":
            return candidate
        config = candidate / ".config"
        if config.is_file():
            return config
    raise SystemExit("cannot locate generated BusyBox .config")


def patch_config(config_path: Path) -> None:
    content = config_path.read_text(encoding="utf-8")
    for symbol, value in CONFIG_VALUES.items():
        assignment = f"{symbol}={value}"
        enabled = re.compile(rf"^{re.escape(symbol)}=.*$", re.MULTILINE)
        disabled = re.compile(rf"^# {re.escape(symbol)} is not set$", re.MULTILINE)
        if enabled.search(content):
            content = enabled.sub(assignment, content, count=1)
        elif disabled.search(content):
            content = disabled.sub(assignment, content, count=1)
        else:
            content = content.rstrip() + "\n" + assignment + "\n"

    config_path.write_text(content, encoding="utf-8")


def main() -> int:
    source = find_source(sys.argv[1:])
    config = find_config(sys.argv[1:])
    changed = patch_paths(source)
    patch_config(config)
    print(f"Mixtar BusyBox native paths: {source} ({changed} files changed)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
