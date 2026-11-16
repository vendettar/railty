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
    for field, value in (("version", version), ("sha256", sha256), ("url", url)):
        text = replace_field(text, field, value, cask)
    cask.write_text(text, encoding="utf-8")
    print(f"updated {cask}: version={version} sha256={sha256}")


if __name__ == "__main__":
    main()
