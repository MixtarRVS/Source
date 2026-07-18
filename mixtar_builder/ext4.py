from __future__ import annotations

import hashlib
import uuid
from pathlib import Path, PurePosixPath
from typing import Any

from .wsl import linux_path, run_wsl

UUID_NAMESPACE = uuid.UUID("87dbc1fd-bb82-46e7-84ec-70aa031193ec")
FIXED_TIME = 315532800


def _inode_metadata(path: str, mode: int, uid: int, gid: int) -> tuple[str, ...]:
    return (
        f"set_inode_field {path} mode 0{mode:o}",
        f"set_inode_field {path} uid {uid}",
        f"set_inode_field {path} gid {gid}",
        f"set_inode_field {path} atime @{FIXED_TIME}",
        f"set_inode_field {path} ctime @{FIXED_TIME}",
        f"set_inode_field {path} mtime @{FIXED_TIME}",
        f"set_inode_field {path} crtime @{FIXED_TIME}",
    )


def _debugfs_commands(volume: dict[str, Any], nodes: list[dict[str, Any]]) -> list[str]:
    commands = ["rmdir /lost+found"]
    commands.extend(_inode_metadata("/", 0o040755, 0, 0))
    for directory in volume["directories"]:
        commands.extend(_inode_metadata(f"/{directory}", 0o040755, 0, 0))
    for item in volume["files"]:
        mode = 0o100000 | int(item["mode"], 8)
        commands.extend(
            _inode_metadata(f"/{item['path']}", mode, item["uid"], item["gid"])
        )
    for node in nodes:
        if node["type"] != "character":
            raise ValueError(f"unsupported ext4 node type: {node['type']}")
        node_path = PurePosixPath(node["path"])
        parent = node_path.parent.as_posix()
        commands.extend(
            (
                f"cd {parent}",
                f"mknod {node_path.name} c {node['major']} {node['minor']}",
                "cd /",
            )
        )
        mode = 0o020000 | int(node["mode"], 8)
        commands.extend(
            _inode_metadata(node_path.as_posix(), mode, node["uid"], node["gid"])
        )
    return commands


def write_ext4(
    root: Path,
    volume: dict[str, Any],
    nodes: list[dict[str, Any]],
    destination: Path,
    size_mib: int,
    label: str,
    system_name: str,
) -> dict[str, object]:
    filesystem_uuid = uuid.uuid5(UUID_NAMESPACE, system_name)
    root_linux = linux_path(root)
    destination_linux = linux_path(destination)
    block_count = size_mib * 1024 * 1024 // 4096
    run_wsl(
        [
            "env",
            "E2FSPROGS_FAKE_TIME=315532800",
            "/sbin/mke2fs",
            "-q",
            "-t",
            "ext4",
            "-F",
            "-b",
            "4096",
            "-m",
            "0",
            "-L",
            label,
            "-U",
            str(filesystem_uuid),
            "-E",
            "lazy_itable_init=0,lazy_journal_init=0",
            "-d",
            root_linux,
            destination_linux,
            str(block_count),
        ],
        timeout=180,
    )
    command_file = destination.with_suffix(destination.suffix + ".debugfs")
    command_file.write_text(
        "\n".join(_debugfs_commands(volume, nodes)) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    try:
        run_wsl(
            [
                "/sbin/debugfs",
                "-w",
                "-f",
                linux_path(command_file),
                destination_linux,
            ],
            timeout=120,
        )
    finally:
        command_file.unlink(missing_ok=True)
    for node in nodes:
        report = run_wsl(
            ["/sbin/debugfs", "-R", f"stat {node['path']}", destination_linux]
        )
        if "Type: character special" not in report:
            raise RuntimeError(f"ext4 device verification failed: {node['path']}")
    data = destination.read_bytes()
    return {
        "path": destination.name,
        "format": "ext4",
        "size": len(data),
        "sha256": hashlib.sha256(data).hexdigest(),
        "label": label,
        "uuid": str(filesystem_uuid),
    }
