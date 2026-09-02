#!/usr/bin/env python3
"""Configure high-resolution advanced operator atlases for Web-safe 2D import.

Source WebP atlases remain untouched at 640 px cells. Godot's default lossless
recompression amplified the 231 MiB source set to roughly 565 MiB of CTEX data,
which produced an 803 MiB PCK and exceeded the supported browser memory budget.
This tool selects high-quality lossy texture storage with mipmaps so runtime
presentation remains sharp at tower scale while the retained sources stay intact.
"""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
IMPORT_ROOT = ROOT / "assets" / "sprites" / "operators" / "animated"
EXPECTED_IMPORTS = 88
REPLACEMENTS = {
    "compress/mode=0": "compress/mode=1",
    "compress/lossy_quality=0.7": "compress/lossy_quality=0.92",
    "mipmaps/generate=false": "mipmaps/generate=true",
}


def main() -> None:
    paths = sorted(
        path
        for path in IMPORT_ROOT.glob("**/*.webp.import")
        if len(path.relative_to(IMPORT_ROOT).parts) == 3
    )
    if len(paths) != EXPECTED_IMPORTS:
        raise SystemExit(f"expected {EXPECTED_IMPORTS} advanced sprite imports, found {len(paths)}")

    changed = 0
    for path in paths:
        text = path.read_text(encoding="utf-8")
        original = text
        for old, new in REPLACEMENTS.items():
            if old not in text and new not in text:
                raise SystemExit(f"{path}: missing import setting {old!r}")
            text = text.replace(old, new)
        if text != original:
            path.write_text(text, encoding="utf-8")
            changed += 1

    print(f"configured={len(paths)} changed={changed} mode=lossy quality=0.92 mipmaps=true")


if __name__ == "__main__":
    main()
