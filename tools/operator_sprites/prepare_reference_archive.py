#!/usr/bin/env python3
"""Prepare immutable per-gender reference derivatives from paired GPT Image 2 boards."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image

CLASSES = (
    "gunner",
    "mage_apprentice",
    "swordmaster",
)
GENDERS = ("male", "female")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def subject_crop(image: Image.Image, margin: int = 48) -> Image.Image:
    """Crop a white-backed design half around all authored non-white pixels."""
    rgb = image.convert("RGB")
    mask = Image.new("L", rgb.size, 0)
    source = rgb.load()
    target = mask.load()
    for y in range(rgb.height):
        for x in range(rgb.width):
            red, green, blue = source[x, y]
            if min(red, green, blue) < 244 or max(red, green, blue) - min(red, green, blue) > 8:
                target[x, y] = 255
    bbox = mask.getbbox()
    if bbox is None:
        raise ValueError("reference half contains no subject pixels")
    left, top, right, bottom = bbox
    left = max(0, left - margin)
    top = max(0, top - margin)
    right = min(image.width, right + margin)
    bottom = min(image.height, bottom + margin)
    return image.crop((left, top, right, bottom))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--preview-root", type=Path, required=True)
    args = parser.parse_args()

    rows: list[dict[str, object]] = []
    args.preview_root.mkdir(parents=True, exist_ok=True)
    for class_id in CLASSES:
        paired_path = args.source_root / class_id / "paired" / "design_reference.png"
        with Image.open(paired_path) as opened:
            paired = opened.convert("RGB")
        width, height = paired.size
        if (width, height) != (2560, 1440):
            raise ValueError(f"{paired_path}: expected 2560x1440, got {width}x{height}")
        halves = {
            "male": paired.crop((0, 0, width // 2, height)),
            "female": paired.crop((width // 2, 0, width, height)),
        }
        for gender, design in halves.items():
            target_dir = args.source_root / class_id / gender
            target_dir.mkdir(parents=True, exist_ok=True)
            design_path = target_dir / "design_reference.png"
            design.save(design_path, format="PNG", optimize=False)
            chibi = subject_crop(design)
            chibi_path = target_dir / "chibi_reference.png"
            chibi.save(chibi_path, format="PNG", optimize=False)
            rows.append(
                {
                    "id": f"reference:{class_id}:{gender}",
                    "class_id": class_id,
                    "gender": gender,
                    "model": "gpt-image-2",
                    "source": str(paired_path),
                    "source_sha256": sha256(paired_path),
                    "design_reference": str(design_path),
                    "design_reference_sha256": sha256(design_path),
                    "chibi_reference": str(chibi_path),
                    "chibi_reference_sha256": sha256(chibi_path),
                    "approved": True,
                }
            )
        preview = paired.copy()
        preview.thumbnail((1280, 720), Image.Resampling.LANCZOS)
        preview_path = args.preview_root / f"{class_id}.webp"
        preview.save(preview_path, format="WEBP", quality=90, method=6)

    manifest_path = args.source_root.parent / "source_manifest.json"
    payload = {
        "schema_version": 1,
        "reference_count": len(rows),
        "references": rows,
        "keyframes": [],
        "carriers": [],
        "runtime_sequences": [],
    }
    manifest_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"prepared {len(rows)} per-gender references")
    print(manifest_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
