#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from pathlib import Path

REPOSITORY = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPOSITORY))
sys.path.insert(0, str(REPOSITORY / "scripts"))
from mixtar_builder.kernel_source import _release_metadata
from mixtar_release import load


def main() -> int:
    lock = load()
    version, url, _ = _release_metadata("stable")
    print(json.dumps({
        "schema": "mixtar.release-candidate.v1",
        "current": {
            "mixtar": lock["release"]["version"],
            "linux": lock["linux"]["version"],
            "openzfs": lock["openzfs"]["version"],
        },
        "candidate": {
            "linux": version,
            "url": url,
            "eligible": False,
            "reason": "A candidate becomes eligible only after the pinned OpenZFS release supports it.",
        },
        "build_lock_changed": False,
    }, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
