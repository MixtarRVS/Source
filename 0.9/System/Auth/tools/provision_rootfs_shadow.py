#!/usr/bin/env python3
"""Stage Mixtar's privileged account shadow file into a rootfs.

The default state is locked. A real password is enabled only when the caller
provides a precomputed crypt(3) hash or asks for an interactive local prompt.
"""

from __future__ import annotations

import argparse
import getpass
import os
import secrets
import stat
import subprocess
import sys
from pathlib import Path


LOCKED_HASH = "!"
DEFAULT_DAYS = "19700"


def die(message: str) -> None:
    print(f"provision-shadow: {message}", file=sys.stderr)
    raise SystemExit(1)


def read_hash_file(path: str) -> str:
    text = Path(path).read_text(encoding="utf-8").strip()
    if not text:
        die(f"empty hash file: {path}")
    return text


def validate_hash(value: str) -> str:
    text = value.strip()
    if text == LOCKED_HASH:
        return text
    accepted = ("$5$", "$6$", "$y$")
    if not text.startswith(accepted):
        die("password hash must be locked '!' or SHA-256/SHA-512/yescrypt crypt format")
    if ":" in text or "\n" in text:
        die("password hash contains invalid shadow-file characters")
    return text


def make_sha512_hash_from_prompt() -> str:
    first = getpass.getpass("Administrator password: ")
    second = getpass.getpass("Confirm password: ")
    if first != second:
        die("passwords do not match")
    if not first:
        die("blank password refused")

    salt = secrets.token_urlsafe(12).replace("-", ".").replace("_", ".")[:16]
    proc = subprocess.run(
        ["openssl", "passwd", "-6", "-salt", salt, "-stdin"],
        input=first.encode("utf-8"),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    first = "\0" * len(first)
    second = "\0" * len(second)
    if proc.returncode != 0:
        err = proc.stderr.decode("utf-8", errors="replace").strip()
        die(f"openssl passwd failed: {err}")
    return validate_hash(proc.stdout.decode("utf-8").strip())


def resolve_hash(args: argparse.Namespace) -> str:
    sources = [
        bool(args.locked),
        bool(args.hash),
        bool(args.hash_file),
        bool(args.hash_env),
        bool(args.prompt),
    ]
    if sum(1 for item in sources if item) != 1:
        die("choose exactly one of --locked, --hash, --hash-file, --hash-env, --prompt")
    if args.locked:
        return LOCKED_HASH
    if args.hash:
        return validate_hash(args.hash)
    if args.hash_file:
        return validate_hash(read_hash_file(args.hash_file))
    if args.hash_env:
        value = os.environ.get(args.hash_env, "")
        if not value:
            die(f"environment variable {args.hash_env} is empty")
        return validate_hash(value)
    return make_sha512_hash_from_prompt()


def write_shadow(rootfs: Path, password_hash: str) -> Path:
    config = rootfs / "System" / "Config"
    config.mkdir(parents=True, exist_ok=True)
    shadow = config / "shadow"
    content = (
        f"Administrator:{password_hash}:{DEFAULT_DAYS}:0:99999:7:::\n"
        f"Superuser:{password_hash}:{DEFAULT_DAYS}:0:99999:7:::\n"
    )
    shadow.write_text(content, encoding="utf-8")
    shadow.chmod(stat.S_IRUSR | stat.S_IWUSR)
    return shadow


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--rootfs", required=True, help="rootfs directory")
    parser.add_argument("--locked", action="store_true", help="stage locked accounts")
    parser.add_argument("--hash", help="crypt(3) password hash; avoid for shared shells")
    parser.add_argument("--hash-file", help="file containing a crypt(3) hash")
    parser.add_argument("--hash-env", help="environment variable containing a crypt(3) hash")
    parser.add_argument("--prompt", action="store_true", help="prompt and generate SHA-512 hash")
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args()

    rootfs = Path(args.rootfs)
    if not rootfs.is_dir():
        die(f"rootfs not found: {rootfs}")
    password_hash = resolve_hash(args)
    shadow = write_shadow(rootfs, password_hash)
    if not args.quiet:
        mode = "locked" if password_hash == LOCKED_HASH else "password-hash"
        print(f"provision-shadow: wrote {shadow} ({mode})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
