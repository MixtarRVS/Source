from __future__ import annotations

import hashlib
import shutil
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path

UKI_SECTIONS = (".osrel", ".cmdline", ".linux", ".initrd")


@dataclass(frozen=True)
class PeLayout:
    section_alignment: int
    next_address: int
    sections: tuple[str, ...]


def _align(value: int, alignment: int) -> int:
    return (value + alignment - 1) // alignment * alignment


def _pe_layout(path: Path) -> PeLayout:
    data = path.read_bytes()
    if len(data) < 64 or data[:2] != b"MZ":
        raise ValueError(f"not a PE/COFF file: {path}")
    pe_offset = int.from_bytes(data[0x3C:0x40], "little")
    if pe_offset + 24 > len(data) or data[pe_offset : pe_offset + 4] != b"PE\0\0":
        raise ValueError(f"invalid PE signature: {path}")
    section_count = int.from_bytes(data[pe_offset + 6 : pe_offset + 8], "little")
    optional_size = int.from_bytes(data[pe_offset + 20 : pe_offset + 22], "little")
    optional_offset = pe_offset + 24
    if optional_offset + optional_size > len(data) or optional_size < 36:
        raise ValueError(f"invalid PE optional header: {path}")
    section_alignment = int.from_bytes(
        data[optional_offset + 32 : optional_offset + 36], "little"
    )
    if section_alignment == 0:
        raise ValueError(f"invalid PE section alignment: {path}")
    table_offset = optional_offset + optional_size
    sections = []
    highest_end = 0
    for index in range(section_count):
        offset = table_offset + index * 40
        if offset + 40 > len(data):
            raise ValueError(f"truncated PE section table: {path}")
        name = data[offset : offset + 8].rstrip(b"\0").decode("ascii")
        virtual_size = int.from_bytes(data[offset + 8 : offset + 12], "little")
        virtual_address = int.from_bytes(data[offset + 12 : offset + 16], "little")
        sections.append(name)
        highest_end = max(highest_end, virtual_address + virtual_size)
    return PeLayout(
        section_alignment=section_alignment,
        next_address=_align(highest_end, section_alignment),
        sections=tuple(sections),
    )


def _section_addresses(stub: Path, inputs: list[Path]) -> list[int]:
    layout = _pe_layout(stub)
    address = layout.next_address
    addresses = []
    for source in inputs:
        addresses.append(address)
        address = _align(address + source.stat().st_size, layout.section_alignment)
    return addresses


def write_uki(
    stub: Path,
    kernel: Path,
    initramfs: Path,
    destination: Path,
    os_release: str,
    command_line: str,
) -> dict[str, object]:
    tool = shutil.which("objcopy")
    if tool is None:
        raise RuntimeError("GNU objcopy is required to build UKI")
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="mixtar-uki-") as temporary:
        work = Path(temporary)
        osrel = work / "os-release"
        cmdline = work / "cmdline"
        osrel.write_text(os_release.rstrip("\n") + "\n", encoding="utf-8")
        cmdline.write_text(command_line.strip(), encoding="utf-8")
        inputs = [osrel, cmdline, kernel, initramfs]
        addresses = _section_addresses(stub, inputs)
        command = [tool]
        for name, source, address in zip(UKI_SECTIONS, inputs, addresses, strict=True):
            command.extend(("--add-section", f"{name}={source}"))
            command.extend(("--change-section-vma", f"{name}=0x{address:x}"))
            command.extend(
                ("--set-section-flags", f"{name}=contents,alloc,load,readonly,data")
            )
        command.extend((str(stub), str(destination)))
        result = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
            timeout=120,
        )
        if result.returncode != 0:
            detail = (result.stderr or result.stdout).strip()
            raise RuntimeError(f"GNU objcopy failed to build UKI: {detail}")
    layout = _pe_layout(destination)
    missing = sorted(set(UKI_SECTIONS) - set(layout.sections))
    if missing:
        raise RuntimeError(f"UKI is missing PE sections: {', '.join(missing)}")
    data = destination.read_bytes()
    return {
        "path": destination.name,
        "format": "uki-pe-coff",
        "size": len(data),
        "sha256": hashlib.sha256(data).hexdigest(),
        "sections": list(UKI_SECTIONS),
    }
