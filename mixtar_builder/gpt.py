from __future__ import annotations

import hashlib
import uuid
from pathlib import Path

from .wsl import linux_path, run_wsl

SECTOR_SIZE = 512
ESP_START_LBA = 2048
GUID_NAMESPACE = uuid.UUID("9b9ef5d8-ef3b-4cb7-a062-a1028512438b")


def _copy_partition(image: Path, partition: Path, start_lba: int) -> None:
    with image.open("r+b") as output, partition.open("rb") as source:
        output.seek(start_lba * SECTOR_SIZE)
        for block in iter(lambda: source.read(1024 * 1024), b""):
            if block.count(0) == len(block):
                output.seek(len(block), 1)
            else:
                output.write(block)


def write_gpt_disk(
    esp_image: Path,
    root_image: Path,
    destination: Path,
    system_name: str,
    root_label: str = "MIXTARROOT",
    root_typecode: str = "8300",
    copy_root: bool = True,
) -> dict[str, object]:
    if (
        esp_image.stat().st_size % SECTOR_SIZE
        or root_image.stat().st_size % SECTOR_SIZE
    ):
        raise ValueError("partition images must be aligned to 512-byte sectors")
    esp_sectors = esp_image.stat().st_size // SECTOR_SIZE
    root_sectors = root_image.stat().st_size // SECTOR_SIZE
    esp_end_lba = ESP_START_LBA + esp_sectors - 1
    root_start_lba = esp_end_lba + 1
    root_end_lba = root_start_lba + root_sectors - 1
    total_sectors = root_end_lba + 2049
    destination.parent.mkdir(parents=True, exist_ok=True)
    with destination.open("wb") as stream:
        stream.truncate(total_sectors * SECTOR_SIZE)

    disk_guid = uuid.uuid5(GUID_NAMESPACE, f"{system_name}:disk")
    esp_guid = uuid.uuid5(GUID_NAMESPACE, f"{system_name}:esp")
    root_guid = uuid.uuid5(GUID_NAMESPACE, f"{system_name}:root")
    run_wsl(
        [
            "/sbin/sgdisk",
            "--clear",
            f"--disk-guid={disk_guid}",
            f"--new=1:{ESP_START_LBA}:{esp_end_lba}",
            "--typecode=1:ef00",
            "--change-name=1:MixtarRVS EFI",
            f"--partition-guid=1:{esp_guid}",
            f"--new=2:{root_start_lba}:{root_end_lba}",
            f"--typecode=2:{root_typecode}",
            f"--change-name=2:{root_label}",
            f"--partition-guid=2:{root_guid}",
            linux_path(destination),
        ]
    )
    _copy_partition(destination, esp_image, ESP_START_LBA)
    if copy_root:
        _copy_partition(destination, root_image, root_start_lba)
    data = destination.read_bytes()
    return {
        "path": destination.name,
        "format": "gpt-disk",
        "size": len(data),
        "sha256": hashlib.sha256(data).hexdigest(),
        "disk_guid": str(disk_guid),
        "esp_partition_guid": str(esp_guid),
        "root_partition_guid": str(root_guid),
        "esp_start_lba": ESP_START_LBA,
        "esp_end_lba": esp_end_lba,
        "root_start_lba": root_start_lba,
        "root_end_lba": root_end_lba,
        "root_typecode": root_typecode,
    }
