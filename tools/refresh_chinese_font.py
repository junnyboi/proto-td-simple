#!/usr/bin/env python3
"""Install a complete Noto Sans CJK SC face and verify shipped Chinese coverage.

Usage:
  python3 tools/refresh_chinese_font.py \
    --source /path/to/NotoSansCJKsc-Regular.otf
"""
from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path

from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "localization/zh-CN.json"
TARGET = ROOT / "assets/fonts/GameTemplateTDSansSC.otf"


def renderable_codepoints() -> set[int]:
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    values = catalog["entries"].values()
    return {ord(char) for value in values for char in value if char.isprintable()}


def cmap(path: Path) -> set[int]:
    font = TTFont(path, lazy=True)
    try:
        return set(font.getBestCmap())
    finally:
        font.close()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, type=Path)
    args = parser.parse_args()
    source = args.source.resolve()
    if not source.is_file():
        parser.error(f"font source not found: {source}")
    source_cmap = cmap(source)
    required = renderable_codepoints()
    missing = sorted(required - source_cmap)
    if missing:
        for codepoint in missing:
            print(f"missing source glyph U+{codepoint:04X} {chr(codepoint)!r}", file=sys.stderr)
        return 1
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, TARGET)
    installed_cmap = cmap(TARGET)
    installed_missing = sorted(required - installed_cmap)
    if installed_missing:
        print("installed font failed post-copy coverage verification", file=sys.stderr)
        return 1
    print(
        f"CHINESE_FONT_READY target={TARGET} bytes={TARGET.stat().st_size} "
        f"catalog_codepoints={len(required)} covered={len(required)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
