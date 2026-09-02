#!/usr/bin/env python3
"""Validate advanced-operator source carriers and high-quality runtime atlases."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import subprocess
import sys
from dataclasses import dataclass
from fractions import Fraction
from pathlib import Path
from typing import Any, Sequence

from PIL import Image, ImageChops, ImageStat

CELL_SIZE = 640
COLUMNS = 8
ACTION_LAYOUT = {"idle": (24, 3), "attack": (13, 2)}
DIRECTION_MIRRORS = {"ne": "nw"}


class ValidationError(ValueError):
    """Raised when an output does not satisfy the runtime contract."""


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _run(command: Sequence[str]) -> str:
    try:
        result = subprocess.run(
            list(command), check=True, text=True, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except FileNotFoundError as exc:
        raise ValidationError(f"required executable not found: {command[0]}") from exc
    except subprocess.CalledProcessError as exc:
        raise ValidationError(f"{command[0]} failed: {exc.stderr.strip()}") from exc
    return result.stdout


def probe_carrier(path: Path) -> dict[str, object]:
    if not path.is_file():
        raise ValidationError(f"carrier does not exist: {path}")
    try:
        payload = json.loads(_run([
            "ffprobe", "-v", "error", "-print_format", "json",
            "-show_format", "-show_streams", str(path),
        ]))
        streams = payload["streams"]
        video = next(stream for stream in streams if stream.get("codec_type") == "video")
        width, height = int(video["width"]), int(video["height"])
        duration = float(video.get("duration") or payload["format"]["duration"])
        rate = Fraction(video.get("avg_frame_rate") or video["r_frame_rate"])
    except (KeyError, StopIteration, TypeError, ValueError, ZeroDivisionError) as exc:
        raise ValidationError(f"{path}: incomplete ffprobe video metadata") from exc
    if width <= 0 or height <= 0 or abs(width / height - 16 / 9) > 0.01:
        raise ValidationError(f"{path}: expected 16:9 video, got {width}x{height}")
    tolerance = max(0.08, 1.5 / float(rate))
    if abs(duration - 4.0) > tolerance:
        raise ValidationError(f"{path}: expected 4-second carrier, got {duration:.6f}s")
    return {
        "width": width, "height": height, "duration_seconds": duration,
        "fps": f"{rate.numerator}/{rate.denominator}",
        "audio_streams": sum(stream.get("codec_type") == "audio" for stream in streams),
        "video_codec": video.get("codec_name", "unknown"),
    }


def _assert_runtime_rgba(path: Path, image: Image.Image) -> None:
    data = path.read_bytes()
    if image.format != "WEBP":
        raise ValidationError(f"{path}: expected WebP, got {image.format}")
    if b"VP8 " not in data or b"ALPH" not in data:
        raise ValidationError(f"{path}: expected high-quality VP8 WebP with alpha")
    if image.mode != "RGBA":
        raise ValidationError(f"{path}: expected decoded RGBA, got {image.mode}")
    extrema = image.getchannel("A").getextrema()
    if extrema[0] != 0 or extrema[1] == 0:
        raise ValidationError(f"{path}: atlas must contain both transparent padding and visible pixels")


def _cell(image: Image.Image, index: int) -> Image.Image:
    left = (index % COLUMNS) * CELL_SIZE
    top = (index // COLUMNS) * CELL_SIZE
    return image.crop((left, top, left + CELL_SIZE, top + CELL_SIZE))


def validate_atlas(path: Path, action: str) -> dict[str, object]:
    if action not in ACTION_LAYOUT:
        raise ValidationError(f"unsupported action: {action}")
    if not path.is_file():
        raise ValidationError(f"atlas does not exist: {path}")
    frame_count, rows = ACTION_LAYOUT[action]
    expected_size = (COLUMNS * CELL_SIZE, rows * CELL_SIZE)
    with Image.open(path) as opened:
        opened.load()
        _assert_runtime_rgba(path, opened)
        if opened.size != expected_size:
            raise ValidationError(f"{path}: expected {expected_size}, got {opened.size}")
        image = opened.copy()
    metrics: list[dict[str, object]] = []
    for index in range(frame_count):
        frame = _cell(image, index)
        bbox = frame.getchannel("A").point(lambda value: 255 if value > 8 else 0).getbbox()
        if bbox is None:
            raise ValidationError(f"{path}: frame {index} is empty")
        width, height = bbox[2] - bbox[0], bbox[3] - bbox[1]
        longest = max(width, height)
        if not 560 <= longest <= 640:
            raise ValidationError(f"{path}: frame {index} longest edge {longest} outside 560..640")
        # Bottom contact is intentional. Other edges indicate clipping.
        if bbox[0] <= 0 or bbox[1] <= 0 or bbox[2] >= CELL_SIZE:
            raise ValidationError(f"{path}: frame {index} clips a non-root cell edge: {bbox}")
        if bbox[3] != CELL_SIZE:
            raise ValidationError(f"{path}: frame {index} feet/root are not bottom locked: {bbox}")
        center = (bbox[0] + bbox[2]) / 2
        if abs(center - CELL_SIZE / 2) > 1:
            raise ValidationError(f"{path}: frame {index} is not bottom-center normalized: x={center}")
        metrics.append({"index": index, "bbox": list(bbox), "longest_edge": longest})
    total_cells = rows * COLUMNS
    for index in range(frame_count, total_cells):
        if _cell(image, index).getchannel("A").getbbox() is not None:
            raise ValidationError(f"{path}: unused padding cell {index} is not transparent")
    return {
        "path": str(path), "sha256": sha256_file(path), "size": list(image.size),
        "mode": "RGBA", "encoding": "vp8-q92-alpha", "frame_count": frame_count,
        "padding_cells": total_cells - frame_count, "frames": metrics,
    }


def validate_mirror(east_path: Path, west_path: Path, action: str) -> dict[str, object]:
    frame_count, _rows = ACTION_LAYOUT[action]
    with Image.open(east_path) as east_opened, Image.open(west_path) as west_opened:
        east = east_opened.convert("RGBA")
        west = west_opened.convert("RGBA")
    if east.size != west.size:
        raise ValidationError(f"mirror dimensions differ: {east.size} != {west.size}")
    maximum_delta = 0
    maximum_mean = 0.0
    for index in range(frame_count):
        expected = _cell(east, index).transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        actual = _cell(west, index)
        if ImageChops.difference(expected.getchannel("A"), actual.getchannel("A")).getbbox() is not None:
            raise ValidationError(f"{west_path}: frame {index} alpha is not an exact mirror")
        difference = ImageChops.difference(expected.convert("RGB"), actual.convert("RGB"))
        extrema = difference.getextrema()
        frame_max = max(channel[1] for channel in extrema)
        frame_mean = max(ImageStat.Stat(difference).mean)
        maximum_delta = max(maximum_delta, frame_max)
        maximum_mean = max(maximum_mean, frame_mean)
        if frame_max > 32 or frame_mean > 3.0:
            raise ValidationError(
                f"{west_path}: frame {index} mirror compression drift max={frame_max} mean={frame_mean:.3f}"
            )
    return {
        "path": str(west_path), "sha256": sha256_file(west_path),
        "exact_alpha_per_frame": True, "maximum_rgb_delta": maximum_delta,
        "maximum_rgb_mean": maximum_mean,
    }


def validate_one(
    atlas: Path,
    mirror: Path,
    action: str,
    carrier: Path | None = None,
    validation_json: Path | None = None,
) -> dict[str, object]:
    east = validate_atlas(atlas, action)
    west = validate_atlas(mirror, action)
    mirror_result = validate_mirror(atlas, mirror, action)
    result: dict[str, object] = {"atlas": east, "mirror_atlas": west, "mirror": mirror_result}
    if carrier is not None:
        result["source_media"] = probe_carrier(carrier)
    if validation_json is not None:
        if not validation_json.is_file():
            raise ValidationError(f"validation JSON does not exist: {validation_json}")
        try:
            record = json.loads(validation_json.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            raise ValidationError(f"{validation_json}: invalid JSON: {exc}") from exc
        checks = {
            "atlas_path": str(atlas.resolve()), "mirror_path": str(mirror.resolve()),
            "atlas_sha256": east["sha256"], "mirror_sha256": west["sha256"],
            "frame_count": ACTION_LAYOUT[action][0],
        }
        for key, expected in checks.items():
            actual = record.get(key)
            if key.endswith("_path"):
                actual = str(Path(str(actual)).resolve())
            if actual != expected:
                raise ValidationError(f"{validation_json}: {key} mismatch: {actual!r} != {expected!r}")
        indices = record.get("frame_indices")
        if not isinstance(indices, list) or len(indices) != ACTION_LAYOUT[action][0] or indices != sorted(set(indices)):
            raise ValidationError(f"{validation_json}: invalid frame_indices")
        frame_metrics = record.get("frames")
        if not isinstance(frame_metrics, list) or len(frame_metrics) != ACTION_LAYOUT[action][0]:
            raise ValidationError(f"{validation_json}: invalid frame metrics")
        for index, metrics in enumerate(frame_metrics):
            if not isinstance(metrics, dict):
                raise ValidationError(f"{validation_json}: frame {index} metrics are not an object")
            compensation = metrics.get("camera_compensation")
            if not isinstance(compensation, (int, float)) or not 0.25 <= float(compensation) <= 4.0:
                raise ValidationError(
                    f"{validation_json}: frame {index} camera compensation {compensation!r} "
                    "indicates a keyed collapse or unbounded subject scale"
                )
        result["validation_json"] = str(validation_json)
    return result


def validate_record(path: Path) -> dict[str, object]:
    try:
        record = json.loads(path.read_text(encoding="utf-8"))
        action = str(record["action"])
        atlas = Path(str(record["atlas_path"]))
        mirror = Path(str(record["mirror_path"]))
        carrier = Path(str(record["carrier"]))
    except (OSError, KeyError, json.JSONDecodeError) as exc:
        raise ValidationError(f"{path}: malformed validation record") from exc
    return validate_one(atlas, mirror, action, carrier, path)


def validate_batch(
    source_root: Path,
    expected_carriers: int | None = None,
    expected_outputs: int | None = None,
) -> dict[str, object]:
    if not source_root.is_dir():
        raise ValidationError(f"source root does not exist: {source_root}")
    carriers = sorted(path for path in source_root.rglob("*.mp4") if path.is_file())
    records = sorted((source_root / "runtime-previews").rglob("*.validation.json"))
    if expected_carriers is not None and len(carriers) != expected_carriers:
        raise ValidationError(f"source carrier count {len(carriers)} != expected {expected_carriers}")
    runtime_output_count = len(records) * 2
    if expected_outputs is not None and runtime_output_count != expected_outputs:
        raise ValidationError(
            f"runtime output count {runtime_output_count} != expected {expected_outputs}"
        )
    manifest_path = source_root / "source_manifest.json"
    if not manifest_path.exists():
        manifest_path = source_root.parent / "source_manifest.json"
    manifest_counts: dict[str, int] | None = None
    if manifest_path.is_file():
        try:
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            manifest_counts = {
                "carriers": len(manifest.get("carriers", [])),
                "runtime_sequences": len(manifest.get("runtime_sequences", [])),
            }
        except (json.JSONDecodeError, TypeError) as exc:
            raise ValidationError(f"{manifest_path}: invalid source manifest") from exc
        if manifest_counts["carriers"] != len(carriers):
            raise ValidationError(
                f"archive carrier count {len(carriers)} != manifest count {manifest_counts['carriers']}"
            )
        if manifest_counts["runtime_sequences"] != len(records) * 2:
            raise ValidationError(
                (
                    f"runtime sequence count {manifest_counts['runtime_sequences']} "
                    f"!= two directions per generated record ({len(records) * 2})"
                )
            )
    elif expected_carriers is None or expected_outputs is None:
        raise ValidationError(
            "batch mode requires source_manifest.json or both --expected-carriers and --expected-outputs"
        )
    results = [validate_record(path) for path in records]
    carrier_metadata = [probe_carrier(path) for path in carriers]
    return {
        "source_root": str(source_root), "carrier_count": len(carriers),
        "generated_record_count": len(records), "output_count": runtime_output_count,
        "manifest_counts": manifest_counts,
        "carriers": carrier_metadata, "outputs": results,
    }


def make_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--atlas", type=Path)
    parser.add_argument("--mirror", type=Path)
    parser.add_argument("--action", choices=tuple(ACTION_LAYOUT))
    parser.add_argument("--carrier", type=Path)
    parser.add_argument("--validation-json", type=Path)
    parser.add_argument("--batch", action="store_true")
    parser.add_argument("--source-root", type=Path)
    parser.add_argument("--expected-carriers", type=int)
    parser.add_argument("--expected-outputs", type=int)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = make_parser()
    args = parser.parse_args(argv)
    try:
        if args.batch:
            if args.source_root is None:
                parser.error("--batch requires --source-root")
            result = validate_batch(args.source_root.resolve(), args.expected_carriers, args.expected_outputs)
        else:
            if args.validation_json is not None and args.atlas is None:
                result = validate_record(args.validation_json.resolve())
            else:
                if args.atlas is None or args.mirror is None or args.action is None:
                    parser.error("individual mode requires --atlas, --mirror, and --action")
                result = validate_one(
                    args.atlas.resolve(), args.mirror.resolve(), args.action,
                    args.carrier.resolve() if args.carrier else None,
                    args.validation_json.resolve() if args.validation_json else None,
                )
    except ValidationError as exc:
        parser.error(str(exc))
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
