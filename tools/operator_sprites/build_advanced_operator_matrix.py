#!/usr/bin/env python3
"""Build and validate every available advanced-operator carrier in canonical order."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

CLASS_ORDER = (
    "gunner", "mage_apprentice", "swordmaster",
)
GENDER_ORDER = ("female", "male")
ACTION_ORDER = ("idle", "attack")
DIRECTION_ORDER = ("ne",)
CHROMA = {
	"gunner": "#FF00FF",
	"mage_apprentice": "#00FF00",
	"swordmaster": "#00FF00",
}


def run(command: list[str]) -> None:
    subprocess.run(command, check=True)


def build_matrix(repository: Path, source_root: Path, class_filter: set[str]) -> dict[str, object]:
    builder = repository / "tools/operator_sprites/build_advanced_operator_sprites.py"
    validator = repository / "tools/operator_sprites/validate_advanced_operator_sprites.py"
    built: list[str] = []
    for class_id in CLASS_ORDER:
        if class_filter and class_id not in class_filter:
            continue
        for gender in GENDER_ORDER:
            for action in ACTION_ORDER:
                for direction in DIRECTION_ORDER:
                    carrier = source_root / "carriers" / class_id / gender / f"{action}_{direction}.mp4"
                    if not carrier.is_file():
                        raise FileNotFoundError(f"missing canonical carrier: {carrier}")
                    command = [
                        sys.executable, str(builder), "--carrier", str(carrier),
                        "--class-id", class_id, "--gender", gender, "--action", action,
                        "--direction", direction, "--chroma", CHROMA[class_id],
                        "--runtime-root", str(repository), "--source-root", str(source_root),
                        "--key-interior",
                    ]
                    if action == "attack":
                        command += ["--window-start", "0.0", "--window-end", "3.95"]
                    print(f"BUILD {class_id}/{gender}/{action}_{direction}", flush=True)
                    run(command)
                    mirror_direction = "nw"
                    atlas_dir = repository / "assets/sprites/operators/animated" / class_id / gender
                    record = (
                        source_root / "runtime-previews" / class_id / gender
                        / f"{action}_{direction}.validation.json"
                    )
                    run([
                        sys.executable, str(validator),
                        "--atlas", str(atlas_dir / f"{action}_{direction}.webp"),
                        "--mirror", str(atlas_dir / f"{action}_{mirror_direction}.webp"),
                        "--action", action, "--carrier", str(carrier),
                        "--validation-json", str(record),
                    ])
                    built.append(f"{class_id}/{gender}/{action}_{direction}")
    return {"built_count": len(built), "built": built}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", type=Path, required=True)
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--class-id", action="append", choices=CLASS_ORDER, default=[])
    args = parser.parse_args()
    result = build_matrix(args.repository.resolve(), args.source_root.resolve(), set(args.class_id))
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
