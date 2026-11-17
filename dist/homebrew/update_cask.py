#!/usr/bin/env python3
"""Update a Homebrew Cask with a newly published Railty release."""
from __future__ import annotations

import pathlib
import re
import sys


def replace_field(text: str, field: str, value: str, path: pathlib.Path) -> str:
    pattern = re.compile(rf'(?m)^(\s*{re.escape(field)}\s+)"[^"]*"(,?)\s*$')
    updated, count = pattern.subn(
        lambda m: f'{m.group(1)}"{value}"{m.group(2)}', text, count=1
    )
    if count != 1:
        raise SystemExit(f"error: expected exactly one {field} field in {path}")
    return updated


def read_field(text: str, field: str, path: pathlib.Path) -> str:
    match = re.search(rf'(?m)^\s*{re.escape(field)}\s+"([^"]+)"', text)
    if not match:
        raise SystemExit(f"error: expected exactly one {field} field in {path}")
    return match.group(1)


def version_key(value: str) -> tuple[int, int, int]:
    stripped = value.lstrip("v")
    parts = stripped.split(".")
    if len(parts) != 3 or not all(p.isdigit() for p in parts):
        raise SystemExit(f"error: cannot compare version {value!r}")
    return int(parts[0]), int(parts[1]), int(parts[2])


def main() -> None:
    if len(sys.argv) != 5:
        raise SystemExit(
            "usage: update_cask.py <cask.rb> <version> <sha256> <url>"
        )
    cask = pathlib.Path(sys.argv[1])
    version, sha256, url = sys.argv[2:]

    if not re.fullmatch(r"[0-9a-f]{64}", sha256):
        raise SystemExit("error: sha256 must be 64 lowercase hexadecimal characters")
    if not re.fullmatch(r"v?\d+\.\d+\.\d+", version):
        raise SystemExit("error: version must look like 0.1.0 or v0.1.0")
    version = version.lstrip("v")

    text = cask.read_text(encoding="utf-8")
    current_version = read_field(text, "version", cask)
    current_sha256 = read_field(text, "sha256", cask)

    # A delayed older release must never overwrite a newer Cask (GitHub Actions
    # concurrency is not FIFO, so this is the real ordering guard).
    if version_key(current_version) > version_key(version):
        raise SystemExit(
            f"error: refusing version regression: tap is {current_version}, "
            f"requested {version}"
        )

    # Same version means the same immutable Release asset. Only accept it if
    # the SHA-256 matches; otherwise fail rather than repoint a published Cask.
    if current_version == version:
        if current_sha256 == sha256:
            print(
                f"no update needed: {cask} already at {version} ({sha256})"
            )
            return
        raise SystemExit(
            f"error: version {version} already published with sha256 "
            f"{current_sha256}, refusing to replace it with {sha256}"
        )

    for field, value in (("version", version), ("sha256", sha256), ("url", url)):
        text = replace_field(text, field, value, cask)
    cask.write_text(text, encoding="utf-8")
    print(f"updated {cask}: version={version} sha256={sha256}")


if __name__ == "__main__":
    main()
