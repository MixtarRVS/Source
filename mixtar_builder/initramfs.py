from __future__ import annotations

import gzip
import hashlib
from dataclasses import dataclass
from pathlib import Path
from typing import Any

CPIO_MAGIC = "070701"
TRAILER = "TRAILER!!!"


@dataclass(frozen=True)
class CpioEntry:
    name: str
    mode: int
    uid: int = 0
    gid: int = 0
    data: bytes = b""
    device_major: int = 0
    device_minor: int = 0


def _padding(size: int) -> bytes:
    return b"\0" * ((-size) % 4)


def _field(value: int) -> str:
    if value < 0 or value > 0xFFFFFFFF:
        raise ValueError(f"cpio field outside 32-bit range: {value}")
    return f"{value:08x}"


def _encode_entry(entry: CpioEntry, inode: int) -> bytes:
    encoded_name = entry.name.encode("utf-8") + b"\0"
    header = "".join(
        (
            CPIO_MAGIC,
            _field(inode),
            _field(entry.mode),
            _field(entry.uid),
            _field(entry.gid),
            _field(1),
            _field(0),
            _field(len(entry.data)),
            _field(0),
            _field(0),
            _field(entry.device_major),
            _field(entry.device_minor),
            _field(len(encoded_name)),
            _field(0),
        )
    ).encode("ascii")
    named = header + encoded_name
    return named + _padding(len(named)) + entry.data + _padding(len(entry.data))


def _entries(
    root: Path, volume: dict[str, Any], nodes: list[dict[str, Any]]
) -> list[CpioEntry]:
    entries = [
        CpioEntry(name=directory, mode=0o040755) for directory in volume["directories"]
    ]
    for item in volume["files"]:
        entries.append(
            CpioEntry(
                name=item["path"],
                mode=0o100000 | int(item["mode"], 8),
                uid=item["uid"],
                gid=item["gid"],
                data=(root / item["path"]).read_bytes(),
            )
        )
    for node in nodes:
        if node["type"] != "character":
            raise ValueError(f"unsupported initramfs node type: {node['type']}")
        entries.append(
            CpioEntry(
                name=node["path"].lstrip("/"),
                mode=0o020000 | int(node["mode"], 8),
                uid=node["uid"],
                gid=node["gid"],
                device_major=node["major"],
                device_minor=node["minor"],
            )
        )
    return sorted(entries, key=lambda entry: entry.name)


def write_initramfs(
    root: Path,
    volume: dict[str, Any],
    nodes: list[dict[str, Any]],
    destination: Path,
) -> dict[str, Any]:
    archive = bytearray()
    for inode, entry in enumerate(_entries(root, volume, nodes), start=1):
        archive.extend(_encode_entry(entry, inode))
    archive.extend(_encode_entry(CpioEntry(name=TRAILER, mode=0), len(archive) + 1))
    compressed = gzip.compress(bytes(archive), compresslevel=9, mtime=0)
    destination.write_bytes(compressed)
    return {
        "path": destination.name,
        "format": "cpio-newc+gzip",
        "size": len(compressed),
        "sha256": hashlib.sha256(compressed).hexdigest(),
    }
