"""Acquisition and deterministic patching of Linux kernel sources."""

from __future__ import annotations

import hashlib
import http.client
import json
import re
import shutil
import subprocess
import tarfile
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from urllib.parse import urljoin, urlsplit

KERNEL_RELEASES_URL = "https://www.kernel.org/releases.json"
USER_AGENT = "Mixtar-Builder/0.11"


class KernelSourceError(RuntimeError):
    """Raised when kernel source preparation cannot be completed safely."""


@dataclass(frozen=True)
class PreparedKernelSource:
    version: str
    source: Path
    archive_url: str
    archive_sha256: str
    patch_sha256: tuple[str, ...]
    cache_key: str
    timings: dict[str, float]
    cached: bool


def _https_response(
    url: str,
    redirects: int = 5,
) -> tuple[http.client.HTTPSConnection, http.client.HTTPResponse]:
    parsed = urlsplit(url)
    if parsed.scheme != "https" or not parsed.hostname:
        raise KernelSourceError(f"refusing non-HTTPS kernel URL: {url}")
    connection = http.client.HTTPSConnection(parsed.hostname, parsed.port, timeout=60)
    target = parsed.path + (f"?{parsed.query}" if parsed.query else "")
    connection.request("GET", target, headers={"User-Agent": USER_AGENT})
    response = connection.getresponse()
    if response.status in {301, 302, 303, 307, 308} and redirects:
        location = response.getheader("Location")
        connection.close()
        if not location:
            raise KernelSourceError(f"kernel.org redirect has no target for {url}")
        return _https_response(urljoin(url, location), redirects - 1)
    if response.status != 200:
        connection.close()
        raise KernelSourceError(f"kernel.org returned HTTP {response.status} for {url}")
    return connection, response


def _download(url: str, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    connection, response = _https_response(url)
    try:
        with destination.open("wb") as output:
            shutil.copyfileobj(response, output)
    finally:
        connection.close()


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _release_metadata(version: str) -> tuple[str, str, str | None]:
    connection, response = _https_response(KERNEL_RELEASES_URL)
    try:
        document: dict[str, Any] = json.loads(response.read())
    finally:
        connection.close()
    releases = document.get("releases", [])
    if version in {"latest", "stable"}:
        latest_stable = document.get("latest_stable", {})
        stable_version = (
            latest_stable.get("version")
            if isinstance(latest_stable, dict)
            else None
        )
        candidates = [
            item for item in releases if item.get("version") == stable_version
        ]
        if not candidates:
            candidates = [
                item
                for item in releases
                if item.get("moniker") == "stable"
                and "-rc" not in str(item.get("version", ""))
            ]
    else:
        candidates = [item for item in releases if item.get("version") == version]
    if not candidates:
        raise KernelSourceError(f"kernel.org does not list Linux {version!r}")
    release = candidates[0]
    resolved = str(release["version"])
    archive_url = str(release["source"])
    checksum_url = None
    if urlsplit(archive_url).hostname == "cdn.kernel.org":
        checksum_url = archive_url.rsplit("/", 1)[0] + "/sha256sums.asc"
    return resolved, archive_url, checksum_url


def _official_checksum(checksum_file: Path, archive_name: str) -> str:
    pattern = re.compile(rf"^([0-9a-fA-F]{{64}})\s+\*?{re.escape(archive_name)}$")
    for line in checksum_file.read_text(
        encoding="utf-8", errors="replace"
    ).splitlines():
        match = pattern.match(line.strip())
        if match:
            return match.group(1).lower()
    raise KernelSourceError(f"official checksum for {archive_name} is missing")


def _wsl_path(path: Path) -> str:
    resolved = path.resolve()
    drive = resolved.drive.rstrip(":").lower()
    suffix = resolved.as_posix().split(":", 1)[-1]
    return f"/mnt/{drive}{suffix}"


def _apply_patches(
    source: Path, patches: tuple[Path, ...], distribution: str
) -> None:
    if not patches:
        return
    wsl = shutil.which("wsl.exe")
    if not wsl:
        raise KernelSourceError("patching kernel sources requires WSL")
    for patch in patches:
        process = subprocess.run(
            [
                wsl,
                "-d",
                distribution,
                "--cd",
                _wsl_path(source),
                "--",
                "/usr/bin/patch",
                "-p1",
                "--forward",
                "--batch",
                "-i",
                _wsl_path(patch),
            ],
            check=False,
            capture_output=True,
            text=True,
            timeout=120,
        )
        if process.returncode:
            detail = process.stderr.strip() or process.stdout.strip()
            raise KernelSourceError(f"patch {patch.name} failed: {detail}")


def prepare_kernel_source(
    cache: Path,
    *,
    distribution: str,
    version: str = "stable",
    patches: tuple[Path, ...] = (),
    archive_url: str | None = None,
    archive_sha256: str | None = None,
) -> PreparedKernelSource:
    """Download, authenticate, extract and patch a Linux source tree."""
    timings = {"metadata": 0.0, "download": 0.0, "verify": 0.0, "extract": 0.0, "patch": 0.0}
    if (archive_url is None) != (archive_sha256 is None):
        raise KernelSourceError("locked kernel URL and SHA-256 must be supplied together")
    if archive_url is None:
        started = time.monotonic()
        resolved, resolved_url, checksum_url = _release_metadata(version)
        timings["metadata"] = time.monotonic() - started
        archive_url = resolved_url
        locked_sha256 = None
    else:
        resolved = version
        checksum_url = None
        locked_sha256 = str(archive_sha256)
        if version in {"latest", "stable"} or "-rc" in version:
            raise KernelSourceError("a release build requires an exact non-RC kernel version")
        if not re.fullmatch(r"[0-9a-f]{64}", locked_sha256):
            raise KernelSourceError("locked kernel SHA-256 is invalid")
        parsed = urlsplit(archive_url)
        if parsed.scheme != "https" or not parsed.hostname:
            raise KernelSourceError("locked kernel URL must use HTTPS")

    downloads = cache / "downloads"
    archive = downloads / Path(archive_url).name
    sums = downloads / f"sha256sums-{resolved}.asc"
    local_sum = archive.with_suffix(archive.suffix + ".sha256")
    started = time.monotonic()
    if not archive.exists():
        _download(archive_url, archive)
    timings["download"] = time.monotonic() - started
    started = time.monotonic()
    actual = _sha256(archive)
    if locked_sha256 is not None:
        expected = locked_sha256
    elif checksum_url:
        if not sums.exists():
            _download(checksum_url, sums)
        expected = _official_checksum(sums, archive.name)
    elif local_sum.exists():
        expected = local_sum.read_text(encoding="ascii").strip()
    else:
        expected = actual
        local_sum.write_text(actual + "\n", encoding="ascii")
    timings["verify"] = time.monotonic() - started
    if actual != expected:
        archive.unlink(missing_ok=True)
        raise KernelSourceError(f"Linux {resolved} archive checksum mismatch")

    normalized_patches = tuple(path.resolve() for path in patches)
    patch_hashes = tuple(_sha256(path) for path in normalized_patches)
    key_material = "\n".join((resolved, actual, *patch_hashes)).encode("ascii")
    cache_key = hashlib.sha256(key_material).hexdigest()[:20]
    destination = cache / "sources" / f"linux-{resolved}-{cache_key}"
    marker = destination / ".mixtar-source.json"
    if marker.exists():
        return PreparedKernelSource(resolved, destination, archive_url, actual, patch_hashes, cache_key, timings, True)

    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="mixtar-kernel-", dir=destination.parent) as temporary:
        work = Path(temporary)
        started = time.monotonic()
        with tarfile.open(archive, "r:*") as package:
            package.extractall(work, filter="data")
        timings["extract"] = time.monotonic() - started
        roots = [entry for entry in work.iterdir() if entry.is_dir()]
        if len(roots) != 1:
            raise KernelSourceError("kernel archive has an unexpected directory layout")
        started = time.monotonic()
        _apply_patches(roots[0], normalized_patches, distribution)
        timings["patch"] = time.monotonic() - started
        marker_data = {"archive_url": archive_url, "archive_sha256": actual, "patch_sha256": patch_hashes, "version": resolved}
        (roots[0] / marker.name).write_text(json.dumps(marker_data, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        try:
            shutil.move(roots[0], destination)
        except FileExistsError:
            if not marker.exists():
                raise
    return PreparedKernelSource(resolved, destination, archive_url, actual, patch_hashes, cache_key, timings, False)
