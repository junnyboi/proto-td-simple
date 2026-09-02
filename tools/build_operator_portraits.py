#!/usr/bin/env python3
"""Build reviewed operator portrait sources into Godot runtime assets.

The GPT Image 2 sources intentionally use a chroma-green isolation target. The
builder removes only border-connected green/background pixels, preserves the
highest-resolution source files under docs/, writes 512x512 RGBA runtime
images, refreshes legacy portrait aliases, and records deterministic hashes.
"""

from __future__ import annotations

import hashlib
import json
import shutil
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = ROOT / "docs/portraits/operator/sources"
RECRUIT_DIR = ROOT / "assets/portraits/recruits"
SPECIALIZATION_DIR = ROOT / "assets/portraits/specializations"
REPORT_PATH = ROOT / "docs/portraits/operator/ASSET_REPORT.json"
CHECKSUM_PATH = ROOT / "docs/portraits/operator/SHA256SUMS"
RUNTIME_SIZE = (512, 512)
SOURCE_SIZE = (1920, 1920)

RECRUITS = {
    "recruit_solcrest_female.png": "solcrest_female.png",
    "recruit_solcrest_male.png": "solcrest_male.png",
    "recruit_vesper_female.png": "vesper_female.png",
    "recruit_vesper_male.png": "vesper_male.png",
    "recruit_lunaris_female.png": "lunaris_female.png",
    "recruit_lunaris_male.png": "lunaris_male.png",
    "recruit_crimson_female.png": "crimson_female.png",
    "recruit_crimson_male.png": "crimson_male.png",
}

SPECIALIZATIONS = {
    f"specialization_{class_id}_{variant}.png": f"{class_id}_{variant}.png"
    for class_id in (
        "gunner",
        "mage_apprentice",
        "swordmaster",
    )
    for variant in ("female", "male")
}

LEGACY_ALIASES = {
    "caster_1.png": SPECIALIZATION_DIR / "mage_apprentice_female.png",
    "guard_1.png": SPECIALIZATION_DIR / "swordmaster_female.png",
    "sniper_1.png": SPECIALIZATION_DIR / "gunner_male.png",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def border_connected_background(rgb: np.ndarray, original_alpha: np.ndarray) -> np.ndarray:
    """Find chroma/transparent background connected to the image border."""

    r = rgb[:, :, 0].astype(np.int16)
    g = rgb[:, :, 1].astype(np.int16)
    b = rgb[:, :, 2].astype(np.int16)
    dominance = g - np.maximum(r, b)

    # A permissive candidate captures textured green and green alpha residue.
    # Border connectivity prevents interior teal/cyan costume details from being
    # removed merely because they contain green.
    candidate = (original_alpha <= 12) | ((g >= 28) & (dominance >= 12))
    height, width = candidate.shape
    connected = np.zeros((height, width), dtype=bool)
    queue: deque[tuple[int, int]] = deque()

    for x in range(width):
        if candidate[0, x]:
            queue.append((0, x))
        if candidate[height - 1, x]:
            queue.append((height - 1, x))
    for y in range(height):
        if candidate[y, 0]:
            queue.append((y, 0))
        if candidate[y, width - 1]:
            queue.append((y, width - 1))

    while queue:
        y, x = queue.popleft()
        if connected[y, x] or not candidate[y, x]:
            continue
        connected[y, x] = True
        if y > 0:
            queue.append((y - 1, x))
        if y + 1 < height:
            queue.append((y + 1, x))
        if x > 0:
            queue.append((y, x - 1))
        if x + 1 < width:
            queue.append((y, x + 1))

    return connected


def clean_source(source_path: Path) -> tuple[Image.Image, dict[str, object]]:
    source = Image.open(source_path).convert("RGBA")
    if source.size != SOURCE_SIZE:
        raise RuntimeError(f"source must be exactly {SOURCE_SIZE}: {source_path} is {source.size}")
    rgba = np.asarray(source).copy()
    rgb = rgba[:, :, :3]
    alpha = rgba[:, :, 3]
    connected = border_connected_background(rgb, alpha)

    # GPT Image 2 can leave enclosed chroma regions between hair, weapon limbs,
    # fingers, or astrolabe rings. Those regions cannot reach the border flood.
    # Remove only strongly green-dominant pixels globally; muted teal cloth and
    # cyan energy remain because blue meets or exceeds their green channel.
    r = rgb[:, :, 0].astype(np.int16)
    g = rgb[:, :, 1].astype(np.int16)
    b = rgb[:, :, 2].astype(np.int16)
    global_chroma = (
        (g >= 48)
        & ((g - r) >= 22)
        & ((g - b) >= 14)
        & (g * 100 >= r * 145)
        & (g * 100 >= b * 120)
    )
    removed = connected | global_chroma

    # Hard-clear the connected chroma/background. The source generation already
    # supplies a narrow antialiased subject edge; removing connected spill is
    # more faithful than inventing replacement pixels.
    alpha[removed] = 0

    # Remove low-alpha residue everywhere and neutralize transparent RGB so PNG
    # importers cannot reveal green fringe during filtering.
    alpha[alpha <= 12] = 0
    transparent = alpha == 0
    rgba[:, :, 3] = alpha
    rgba[transparent, :3] = 0

    cleaned = Image.fromarray(rgba, mode="RGBA")
    alpha_image = cleaned.getchannel("A")
    bounds = alpha_image.getbbox()
    if bounds is None:
        raise RuntimeError(f"source became fully transparent: {source_path}")
    x0, y0, x1, y1 = bounds
    width, height = cleaned.size
    foreground_pixels = int(np.count_nonzero(np.asarray(alpha_image) > 16))
    corner_alpha = [
        int(alpha[0, 0]),
        int(alpha[0, width - 1]),
        int(alpha[height - 1, 0]),
        int(alpha[height - 1, width - 1]),
    ]
    metadata = {
        "source_size": [width, height],
        "source_sha256": sha256(source_path),
        "alpha_bounds": [x0, y0, x1, y1],
        "alpha_coverage": foreground_pixels / float(width * height),
        "corner_alpha": corner_alpha,
        "removed_background_pixels": int(np.count_nonzero(removed)),
    }
    return cleaned, metadata


def build_one(source_name: str, output_path: Path) -> dict[str, object]:
    source_path = SOURCE_DIR / source_name
    if not source_path.is_file():
        raise FileNotFoundError(source_path)
    cleaned, metadata = clean_source(source_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    runtime = cleaned.resize(RUNTIME_SIZE, Image.Resampling.LANCZOS)
    runtime.save(output_path, format="PNG", optimize=True)
    metadata.update(
        {
            "source": str(source_path.relative_to(ROOT)),
            "runtime": str(output_path.relative_to(ROOT)),
            "runtime_size": list(runtime.size),
            "runtime_sha256": sha256(output_path),
            "runtime_corner_alpha": [
                runtime.getpixel((0, 0))[3],
                runtime.getpixel((runtime.width - 1, 0))[3],
                runtime.getpixel((0, runtime.height - 1))[3],
                runtime.getpixel((runtime.width - 1, runtime.height - 1))[3],
            ],
        }
    )
    return metadata


def main() -> None:
    expected_sources = set(RECRUITS) | set(SPECIALIZATIONS)
    actual_sources = {path.name for path in SOURCE_DIR.glob("*.png")}
    if expected_sources != actual_sources:
        missing = sorted(expected_sources - actual_sources)
        unexpected = sorted(actual_sources - expected_sources)
        raise RuntimeError(f"source matrix mismatch; missing={missing}, unexpected={unexpected}")

    records: list[dict[str, object]] = []
    for source_name, output_name in RECRUITS.items():
        records.append(build_one(source_name, RECRUIT_DIR / output_name))
    for source_name, output_name in SPECIALIZATIONS.items():
        records.append(build_one(source_name, SPECIALIZATION_DIR / output_name))

    for alias_name, target in LEGACY_ALIASES.items():
        if not target.is_file():
            raise FileNotFoundError(target)
        shutil.copyfile(target, ROOT / "assets/portraits" / alias_name)

    runtime_hashes = [str(record["runtime_sha256"]) for record in records]
    if len(runtime_hashes) != len(set(runtime_hashes)):
        raise RuntimeError("generated runtime portraits are not unique by SHA-256")
    source_hashes = [str(record["source_sha256"]) for record in records]
    if len(source_hashes) != len(set(source_hashes)):
        raise RuntimeError("generated GPT Image 2 sources are not unique by SHA-256")

    report = {
        "schema_version": 1,
        "generator": "GPT Image 2",
        "source_count": len(records),
        "recruit_count": len(RECRUITS),
        "specialization_count": len(SPECIALIZATIONS),
        "runtime_size": list(RUNTIME_SIZE),
        "source_size": list(SOURCE_SIZE),
        "legacy_alias_count": len(LEGACY_ALIASES),
        "records": records,
        "legacy_aliases": {
            alias: str(target.relative_to(ROOT)) for alias, target in LEGACY_ALIASES.items()
        },
    }
    REPORT_PATH.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    checksum_paths = sorted(
        list(SOURCE_DIR.glob("*.png"))
        + list(RECRUIT_DIR.glob("*.png"))
        + list(SPECIALIZATION_DIR.glob("*.png"))
    )
    CHECKSUM_PATH.write_text(
        "".join(f"{sha256(path)}  {path.relative_to(ROOT)}\n" for path in checksum_paths),
        encoding="utf-8",
    )
    print(
        f"built {len(records)} portraits: {len(RECRUITS)} recruits, "
        f"{len(SPECIALIZATIONS)} specializations, {len(LEGACY_ALIASES)} legacy aliases"
    )


if __name__ == "__main__":
    main()
