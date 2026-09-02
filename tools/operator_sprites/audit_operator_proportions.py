#!/usr/bin/env python3
"""Measure advanced-operator crown-to-ground silhouettes and validate runtime calibration.

The processor normalizes each source frame by its longest visible edge. That edge
may belong to equipment rather than the body, so this audit samples a narrow band
around the bottom-center root across neutral idle frames. The resulting median is
used by OperatorAnimationDef.normalized_subject_height_px to map every identity to
one common tactical body height without modifying source atlases.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from statistics import median
from typing import Any

from PIL import Image

CELL = 640
COLUMNS = 8
ALPHA_THRESHOLD = 16
BAND_HALF_WIDTH = 72
DIRECTIONS = ("ne",)
SAMPLE_INDICES = (0, 6, 12, 18, 23)


def atlas_cell(atlas: Image.Image, index: int) -> Image.Image:
    x = (index % COLUMNS) * CELL
    y = (index // COLUMNS) * CELL
    return atlas.crop((x, y, x + CELL, y + CELL)).convert("RGBA")


def alpha_bbox_height(frame: Image.Image) -> int:
    alpha = frame.getchannel("A").point(
        lambda value: 255 if value > ALPHA_THRESHOLD else 0
    )
    bbox = alpha.getbbox()
    if bbox is None:
        raise ValueError("empty operator frame")
    return bbox[3] - bbox[1]


def central_silhouette_height(frame: Image.Image) -> int:
    alpha = frame.getchannel("A")
    x0 = CELL // 2 - BAND_HALF_WIDTH
    x1 = CELL // 2 + BAND_HALF_WIDTH
    occupied: list[int] = []
    for y in range(CELL):
        _, row_max = alpha.crop((x0, y, x1, y + 1)).getextrema()
        if row_max > ALPHA_THRESHOLD:
            occupied.append(y)
    if not occupied:
        raise ValueError("empty central operator silhouette")
    return occupied[-1] - occupied[0] + 1


def load_config(repository: Path) -> dict[str, Any]:
    path = repository / "data/presentation/advanced_operator_proportions.json"
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("schema_version") != 1:
        raise ValueError(f"{path}: expected schema version 1")
    identities = payload.get("identities")
    if not isinstance(identities, dict) or len(identities) != 6:
        raise ValueError(f"{path}: expected exact 6-identity matrix")
    return payload


def measure_identity(repository: Path, template_id: str) -> dict[str, Any]:
    class_id, gender = template_id.rsplit("_", 1)
    central: list[int] = []
    alpha: list[int] = []
    for direction in DIRECTIONS:
        path = (
            repository
            / "assets/sprites/operators/animated"
            / class_id
            / gender
            / f"idle_{direction}.webp"
        )
        with Image.open(path) as opened:
            atlas = opened.convert("RGBA")
        for index in SAMPLE_INDICES:
            frame = atlas_cell(atlas, index)
            central.append(central_silhouette_height(frame))
            alpha.append(alpha_bbox_height(frame))
    return {
        "template_id": template_id,
        "class_id": class_id,
        "gender": gender,
        "median_central_height_px": round(float(median(central)), 1),
        "min_central_height_px": min(central),
        "max_central_height_px": max(central),
        "median_alpha_bbox_height_px": round(float(median(alpha)), 1),
        "central_to_alpha_ratio": round(float(median(central)) / float(median(alpha)), 4),
    }


def audit(repository: Path) -> dict[str, Any]:
    config = load_config(repository)
    target = int(config["target_runtime_body_height_px"])
    rows: list[dict[str, Any]] = []
    failures: list[str] = []
    for template_id, calibration in sorted(config["identities"].items()):
        if not isinstance(calibration, dict):
            failures.append(f"{template_id}: calibration must be an object")
            continue
        row = measure_identity(repository, template_id)
        configured = int(calibration.get("normalized_body_height_px", 0))
        observed = float(row["median_central_height_px"])
        projected = observed * target / configured if configured > 0 else 0.0
        row.update(
            {
                "configured_body_height_px": configured,
                "target_runtime_body_height_px": target,
                "projected_runtime_body_height_px": round(projected, 3),
                "disposition": calibration.get("disposition", ""),
            }
        )
        if configured < 480 or configured > 640:
            failures.append(f"{template_id}: configured body height must be 480..640")
        if abs(observed - configured) > 12.0:
            failures.append(
                f"{template_id}: observed {observed:.1f}px differs from configured {configured}px"
            )
        if abs(projected - target) > 2.0:
            failures.append(
                f"{template_id}: projected runtime height {projected:.2f}px is outside {target}±2px"
            )
        rows.append(row)
    return {
        "schema_version": 1,
        "method": "central 144px alpha silhouette across ten neutral idle samples",
        "identity_count": len(rows),
        "rows": rows,
        "failures": failures,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", type=Path, default=Path.cwd())
    parser.add_argument("--output", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    payload = audit(args.repository.resolve())
    text = json.dumps(payload, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text, encoding="utf-8")
    print(text, end="")
    if args.check and payload["failures"]:
        return 1
    if args.check:
        print("ADVANCED_OPERATOR_PROPORTION_AUDIT_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
