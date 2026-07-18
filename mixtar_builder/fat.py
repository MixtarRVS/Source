from __future__ import annotations

import hashlib
import math
import re
import struct
from pathlib import Path
from pathlib import PurePosixPath
from typing import Any

SECTOR_SIZE = 512
RESERVED_SECTORS = 32
FAT_COUNT = 2
ROOT_CLUSTER = 2
END_OF_CHAIN = 0x0FFFFFFF


def _fat_geometry(size_bytes: int) -> tuple[int, int]:
    total_sectors = size_bytes // SECTOR_SIZE
    sectors_per_fat = 1
    while True:
        data_sectors = total_sectors - RESERVED_SECTORS - FAT_COUNT * sectors_per_fat
        cluster_count = data_sectors
        required = math.ceil((cluster_count + 2) * 4 / SECTOR_SIZE)
        if required <= sectors_per_fat:
            break
        sectors_per_fat = required
    if cluster_count < 65525:
        raise ValueError("FAT32 image is too small; at least 34 MiB is required")
    return total_sectors, sectors_per_fat


def _boot_sector(total_sectors: int, sectors_per_fat: int, label: str) -> bytes:
    sector = bytearray(SECTOR_SIZE)
    sector[0:3] = b"\xeb\x58\x90"
    sector[3:11] = b"MIXTAR  "
    struct.pack_into("<H", sector, 11, SECTOR_SIZE)
    sector[13] = 1
    struct.pack_into("<H", sector, 14, RESERVED_SECTORS)
    sector[16] = FAT_COUNT
    sector[21] = 0xF8
    struct.pack_into("<H", sector, 24, 63)
    struct.pack_into("<H", sector, 26, 255)
    struct.pack_into("<I", sector, 32, total_sectors)
    struct.pack_into("<I", sector, 36, sectors_per_fat)
    struct.pack_into("<I", sector, 44, ROOT_CLUSTER)
    struct.pack_into("<H", sector, 48, 1)
    struct.pack_into("<H", sector, 50, 6)
    sector[64] = 0x80
    sector[66] = 0x29
    struct.pack_into("<I", sector, 67, 0x4D585452)
    sector[71:82] = label.ljust(11).encode("ascii")
    sector[82:90] = b"FAT32   "
    sector[510:512] = b"\x55\xaa"
    return bytes(sector)


def _fsinfo(free_clusters: int, next_cluster: int) -> bytes:
    sector = bytearray(SECTOR_SIZE)
    struct.pack_into("<I", sector, 0, 0x41615252)
    struct.pack_into("<I", sector, 484, 0x61417272)
    struct.pack_into("<I", sector, 488, free_clusters)
    struct.pack_into("<I", sector, 492, next_cluster)
    struct.pack_into("<I", sector, 508, 0xAA550000)
    return bytes(sector)


def _short_name(name: str, index: int) -> bytes:
    path = Path(name)
    stem = re.sub(r"[^A-Z0-9]", "", path.stem.upper())
    suffix = re.sub(r"[^A-Z0-9]", "", path.suffix.lstrip(".").upper())
    if (
        1 <= len(stem) <= 8
        and len(suffix) <= 3
        and name.upper() == stem + (f".{suffix}" if suffix else "")
    ):
        return stem.ljust(8).encode("ascii") + suffix.ljust(3).encode("ascii")
    alias = f"{stem[:6]}~{index}"[:8]
    return alias.ljust(8).encode("ascii") + suffix[:3].ljust(3).encode("ascii")


def _needs_lfn(name: str, short_name: bytes) -> bool:
    stem = short_name[:8].decode("ascii").rstrip()
    suffix = short_name[8:11].decode("ascii").rstrip()
    rendered = stem + (f".{suffix}" if suffix else "")
    return name != rendered


def _lfn_checksum(short_name: bytes) -> int:
    checksum = 0
    for value in short_name:
        checksum = ((checksum & 1) << 7) + (checksum >> 1) + value
        checksum &= 0xFF
    return checksum


def _lfn_entries(name: str, short_name: bytes) -> list[bytes]:
    units = list(
        struct.unpack(f"<{len(name.encode('utf-16le')) // 2}H", name.encode("utf-16le"))
    )
    units.append(0)
    while len(units) % 13:
        units.append(0xFFFF)
    chunks = [units[index : index + 13] for index in range(0, len(units), 13)]
    entries = []
    checksum = _lfn_checksum(short_name)
    for sequence in range(len(chunks), 0, -1):
        chunk = chunks[sequence - 1]
        entry = bytearray(32)
        sequence_field = sequence | (0x40 if sequence == len(chunks) else 0)
        struct.pack_into("B", entry, 0, sequence_field)
        entry[1:11] = struct.pack("<5H", *chunk[:5])
        entry[11] = 0x0F
        entry[13] = checksum
        entry[14:26] = struct.pack("<6H", *chunk[5:11])
        entry[28:32] = struct.pack("<2H", *chunk[11:13])
        entries.append(bytes(entry))
    return entries


def _directory_entry(
    short_name: bytes, first_cluster: int, size: int, attributes: int = 0x20
) -> bytes:
    entry = bytearray(32)
    entry[0:11] = short_name
    entry[11] = attributes
    struct.pack_into("<H", entry, 14, 0)
    struct.pack_into("<H", entry, 16, 0x21)
    struct.pack_into("<H", entry, 18, 0x21)
    struct.pack_into("<H", entry, 22, 0)
    struct.pack_into("<H", entry, 24, 0x21)
    struct.pack_into("<H", entry, 20, first_cluster >> 16)
    struct.pack_into("<H", entry, 26, first_cluster & 0xFFFF)
    struct.pack_into("<I", entry, 28, size)
    return bytes(entry)


def _safe_path(value: str) -> PurePosixPath:
    path = PurePosixPath(value)
    if path.is_absolute() or not path.parts or ".." in path.parts:
        raise ValueError(f"invalid FAT path: {value!r}")
    return path


def _entry_size(name: str, index: int) -> int:
    short = _short_name(name, index)
    return 32 * (1 + (len(_lfn_entries(name, short)) if _needs_lfn(name, short) else 0))


def _chain(next_cluster: int, byte_count: int) -> tuple[list[int], int]:
    count = max(1, math.ceil(byte_count / SECTOR_SIZE))
    clusters = list(range(next_cluster, next_cluster + count))
    return clusters, next_cluster + count


def _dot_name(parent: bool) -> bytes:
    value = b".." if parent else b"."
    return value.ljust(11, b" ")


def write_fat32(
    root: Path,
    volume: dict[str, Any],
    destination: Path,
    size_mib: int,
    label: str,
) -> dict[str, Any]:
    if not re.fullmatch(r"[A-Z0-9 ]{1,11}", label):
        raise ValueError("FAT32 label must contain 1-11 uppercase ASCII characters")
    size_bytes = size_mib * 1024 * 1024
    total_sectors, sectors_per_fat = _fat_geometry(size_bytes)
    image = bytearray(size_bytes)
    boot = _boot_sector(total_sectors, sectors_per_fat, label)
    image[0:SECTOR_SIZE] = boot
    image[6 * SECTOR_SIZE : 7 * SECTOR_SIZE] = boot

    directories = {PurePosixPath(".")}
    for value in volume["directories"]:
        path = _safe_path(value)
        directories.add(path)
        directories.update(path.parents)
    file_items: dict[PurePosixPath, dict[str, Any]] = {}
    for item in volume["files"]:
        path = _safe_path(item["path"])
        if path in file_items or path in directories:
            raise ValueError(f"duplicate FAT path: {path.as_posix()}")
        file_items[path] = item
        directories.add(path.parent)
        directories.update(path.parent.parents)

    children: dict[PurePosixPath, list[tuple[str, bool, PurePosixPath]]] = {
        path: [] for path in directories
    }
    for directory in sorted(
        (path for path in directories if path != PurePosixPath(".")),
        key=lambda path: (len(path.parts), path.as_posix()),
    ):
        children[directory.parent].append((directory.name, True, directory))
    for path in sorted(file_items, key=lambda item: item.as_posix()):
        children[path.parent].append((path.name, False, path))
    for values in children.values():
        values.sort(key=lambda value: (value[0].upper(), value[0]))

    directory_chains: dict[PurePosixPath, list[int]] = {}
    next_cluster = ROOT_CLUSTER
    ordered_directories = sorted(
        directories,
        key=lambda path: (0 if path == PurePosixPath(".") else len(path.parts), path.as_posix()),
    )
    for directory in ordered_directories:
        entry_bytes = (32 if directory == PurePosixPath(".") else 64) + 32
        entry_bytes += sum(
            _entry_size(name, index)
            for index, (name, _, _) in enumerate(children[directory], start=1)
        )
        directory_chains[directory], next_cluster = _chain(next_cluster, entry_bytes)

    allocated_files: dict[PurePosixPath, tuple[bytes, list[int]]] = {}
    for path, item in sorted(file_items.items(), key=lambda value: value[0].as_posix()):
        data = (root / Path(*path.parts)).read_bytes()
        clusters, next_cluster = _chain(next_cluster, len(data))
        allocated_files[path] = (data, clusters)

    data_sector = RESERVED_SECTORS + FAT_COUNT * sectors_per_fat
    cluster_count = total_sectors - data_sector
    if next_cluster - ROOT_CLUSTER > cluster_count:
        raise ValueError("FAT32 image does not have enough data clusters")
    free_clusters = cluster_count - (next_cluster - ROOT_CLUSTER)
    info = _fsinfo(free_clusters, next_cluster)
    image[SECTOR_SIZE : 2 * SECTOR_SIZE] = info
    image[7 * SECTOR_SIZE : 8 * SECTOR_SIZE] = info

    fat = bytearray(sectors_per_fat * SECTOR_SIZE)
    struct.pack_into("<I", fat, 0, 0x0FFFFFF8)
    struct.pack_into("<I", fat, 4, END_OF_CHAIN)
    struct.pack_into("<I", fat, ROOT_CLUSTER * 4, END_OF_CHAIN)
    all_chains = [*directory_chains.values()]
    all_chains.extend(clusters for _, clusters in allocated_files.values())
    for clusters in all_chains:
        for current, following in zip(clusters, clusters[1:], strict=False):
            struct.pack_into("<I", fat, current * 4, following)
        struct.pack_into("<I", fat, clusters[-1] * 4, END_OF_CHAIN)
    fat_offset = RESERVED_SECTORS * SECTOR_SIZE
    for index in range(FAT_COUNT):
        start = fat_offset + index * len(fat)
        image[start : start + len(fat)] = fat

    def write_chain(clusters: list[int], data: bytes) -> None:
        for index, cluster in enumerate(clusters):
            source_offset = index * SECTOR_SIZE
            destination_offset = (
                data_sector + cluster - ROOT_CLUSTER
            ) * SECTOR_SIZE
            image[destination_offset : destination_offset + SECTOR_SIZE] = data[
                source_offset : source_offset + SECTOR_SIZE
            ].ljust(SECTOR_SIZE, b"\0")

    for directory in ordered_directories:
        entries = bytearray()
        if directory == PurePosixPath("."):
            entries.extend(
                _directory_entry(
                    label.ljust(11).encode("ascii"), 0, 0, 0x08
                )
            )
        else:
            entries.extend(
                _directory_entry(
                    _dot_name(False), directory_chains[directory][0], 0, 0x10
                )
            )
            parent = directory.parent
            entries.extend(
                _directory_entry(
                    _dot_name(True), directory_chains[parent][0], 0, 0x10
                )
            )
        for index, (name, is_directory, path) in enumerate(
            children[directory], start=1
        ):
            short = _short_name(name, index)
            if _needs_lfn(name, short):
                entries.extend(b"".join(_lfn_entries(name, short)))
            if is_directory:
                first_cluster = directory_chains[path][0]
                size = 0
                attributes = 0x10
            else:
                data, clusters = allocated_files[path]
                first_cluster = clusters[0]
                size = len(data)
                attributes = 0x20
            entries.extend(
                _directory_entry(short, first_cluster, size, attributes)
            )
        entries.extend(b"\0" * 32)
        write_chain(directory_chains[directory], bytes(entries))

    for data, clusters in allocated_files.values():
        write_chain(clusters, data)
    destination.write_bytes(image)
    digest = hashlib.sha256(image).hexdigest()
    return {
        "path": destination.name,
        "format": "fat32",
        "size": len(image),
        "sha256": digest,
        "label": label.rstrip(),
    }
