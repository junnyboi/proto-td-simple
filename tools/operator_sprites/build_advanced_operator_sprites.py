#!/usr/bin/env python3
"""Build deterministic high-quality advanced-operator WebP atlases from one carrier.

Only ffmpeg/ffprobe, the Python standard library, and Pillow are required.  The
source carrier is opened read-only and all extracted frames live in a temporary
directory.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import shutil
import subprocess
import tempfile
from collections import deque
from dataclasses import dataclass
from fractions import Fraction
from pathlib import Path
from statistics import median
from typing import Any, Iterable, Sequence

from PIL import Image, ImageChops, ImageDraw

CELL_SIZE = 640
ATLAS_COLUMNS = 8
TARGET_EDGE = 600
EDGE_MIN = 560
EDGE_MAX = 640
IDLE_FRAMES = 24
ATTACK_FRAMES = 13
ACTIONS = ("idle", "attack")
EAST_DIRECTIONS = ("ne",)
GENDERS = ("male", "female")
CHROMA_RE = re.compile(r"^#[0-9a-fA-F]{6}$")


@dataclass(frozen=True)
class MediaMetadata:
    width: int
    height: int
    fps_num: int
    fps_den: int
    duration: float
    frame_count: int | None
    audio_streams: int
    video_codec: str

    @property
    def fps(self) -> float:
        return self.fps_num / self.fps_den

    def as_json(self) -> dict[str, object]:
        return {
            "width": self.width,
            "height": self.height,
            "display_aspect_ratio": "16:9",
            "fps": f"{self.fps_num}/{self.fps_den}",
            "duration_seconds": self.duration,
            "frame_count_reported": self.frame_count,
            "audio_streams": self.audio_streams,
            "video_codec": self.video_codec,
        }


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def run_checked(command: Sequence[str]) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            list(command), check=True, text=True, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except FileNotFoundError as exc:
        raise RuntimeError(f"required executable not found: {command[0]}") from exc
    except subprocess.CalledProcessError as exc:
        detail = exc.stderr.strip() or exc.stdout.strip() or "unknown error"
        raise RuntimeError(f"{command[0]} failed: {detail}") from exc


def probe_media(path: Path) -> MediaMetadata:
    result = run_checked([
        "ffprobe", "-v", "error", "-print_format", "json",
        "-show_format", "-show_streams", str(path),
    ])
    try:
        payload = json.loads(result.stdout)
        streams = payload["streams"]
        video = next(stream for stream in streams if stream.get("codec_type") == "video")
        rate_text = video.get("avg_frame_rate") or video.get("r_frame_rate")
        rate = Fraction(rate_text)
        duration_text = video.get("duration") or payload["format"].get("duration")
        duration = float(duration_text)
        width, height = int(video["width"]), int(video["height"])
    except (KeyError, StopIteration, TypeError, ValueError, ZeroDivisionError) as exc:
        raise ValueError(f"{path}: ffprobe did not report usable video metadata") from exc
    if width <= 0 or height <= 0 or rate <= 0 or duration <= 0:
        raise ValueError(f"{path}: invalid video geometry, frame rate, or duration")
    # Encoded display-aspect tags are frequently omitted, so validate geometry.
    if abs(width / height - 16 / 9) > 0.01:
        raise ValueError(f"{path}: carrier must be 16:9, got {width}x{height}")
    if abs(duration - 4.0) > max(0.08, 1.5 / float(rate)):
        raise ValueError(f"{path}: carrier must be 4 seconds, ffprobe reports {duration:.6f}s")
    count_text = video.get("nb_frames")
    frame_count = int(count_text) if count_text not in (None, "N/A") else None
    return MediaMetadata(
        width=width, height=height, fps_num=rate.numerator, fps_den=rate.denominator,
        duration=duration, frame_count=frame_count,
        audio_streams=sum(stream.get("codec_type") == "audio" for stream in streams),
        video_codec=str(video.get("codec_name", "unknown")),
    )


def parse_chroma(value: str) -> tuple[int, int, int]:
    if not CHROMA_RE.fullmatch(value):
        raise argparse.ArgumentTypeError("chroma must use #RRGGBB syntax")
    return tuple(int(value[index:index + 2], 16) for index in (1, 3, 5))  # type: ignore[return-value]


def evenly_spaced_indices(start: int, end: int, count: int, preserve_endpoint: bool) -> list[int]:
    """Return deterministic integer samples without floating-point drift."""
    if count < 1 or start < 0 or end < start:
        raise ValueError("invalid sample range")
    span = end - start
    divisor = count - 1 if preserve_endpoint else count
    if preserve_endpoint and count == 1:
        return [start]
    if span + (1 if preserve_endpoint else 0) < count:
        raise ValueError(f"sample range has too few frames for {count} unique samples")
    # Round half up. Endpoint-exclusive callers pass end as the exclusive bound.
    values = [start + (2 * index * span + divisor) // (2 * divisor) for index in range(count)]
    if not preserve_endpoint and values[-1] >= end:
        values[-1] = end - 1
    if preserve_endpoint:
        values[0], values[-1] = start, end
    if len(set(values)) != count:
        raise ValueError(f"sample range cannot yield {count} unique frames")
    return values


def select_frame_indices(
    total_frames: int,
    action: str,
    fps: float,
    window_start: float | None = None,
    window_end: float | None = None,
) -> list[int]:
    if total_frames <= 0 or fps <= 0:
        raise ValueError("carrier contains no usable frames")
    if action == "idle":
        if window_start is not None or window_end is not None:
            raise ValueError("idle sampling uses the full carrier; do not supply an action window")
        return evenly_spaced_indices(0, total_frames, IDLE_FRAMES, preserve_endpoint=False)
    if action != "attack":
        raise ValueError(f"unsupported action: {action}")
    if window_start is None or window_end is None:
        raise ValueError("attack requires both --window-start and --window-end")
    if not math.isfinite(window_start) or not math.isfinite(window_end):
        raise ValueError("action window values must be finite")
    if window_start < 0 or window_end <= window_start:
        raise ValueError("attack window must have 0 <= start < end")
    # A complete action window names frame presentation times. Preserve both
    # nearest endpoints, clamped to the extracted carrier.
    first = max(0, min(total_frames - 1, int(math.floor(window_start * fps + 0.5))))
    last = max(0, min(total_frames - 1, int(math.floor(window_end * fps + 0.5))))
    if last <= first:
        raise ValueError("attack window covers fewer than two source frames")
    return evenly_spaced_indices(first, last, ATTACK_FRAMES, preserve_endpoint=True)


def extract_native_frames(carrier: Path, output_dir: Path) -> list[Path]:
    pattern = output_dir / "frame_%06d.png"
    run_checked([
        "ffmpeg", "-v", "error", "-nostdin", "-i", str(carrier),
        "-map", "0:v:0", "-vsync", "0", "-start_number", "0", str(pattern),
    ])
    frames = sorted(output_dir.glob("frame_*.png"))
    if not frames:
        raise RuntimeError(f"ffmpeg extracted no frames from {carrier}")
    return frames


def _sample_border_rgb(image: Image.Image, stride: int = 4) -> Iterable[tuple[int, int, int]]:
    rgb = image.convert("RGB")
    width, height = rgb.size
    pixels = rgb.load()
    band = max(2, min(width, height) // 32)
    for y in range(0, height, stride):
        for x in range(0, band, stride):
            yield pixels[x, y]
        for x in range(max(band, width - band), width, stride):
            yield pixels[x, y]
    for x in range(band, max(band, width - band), stride):
        for y in range(0, band, stride):
            yield pixels[x, y]
        for y in range(max(band, height - band), height, stride):
            yield pixels[x, y]


def measure_chroma(images: Sequence[Image.Image], requested: tuple[int, int, int]) -> tuple[int, int, int]:
    candidates: list[tuple[int, int, int]] = []
    for image in images:
        for pixel in _sample_border_rgb(image):
            if sum((pixel[channel] - requested[channel]) ** 2 for channel in range(3)) <= 90 ** 2:
                candidates.append(pixel)
    if not candidates:
        raise ValueError("could not measure requested chroma on carrier borders")
    measured = tuple(int(median(pixel[channel] for pixel in candidates)) for channel in range(3))
    if sum((measured[channel] - requested[channel]) ** 2 for channel in range(3)) > 55 ** 2:
        raise ValueError(f"measured border chroma {measured} is too far from requested {requested}")
    return measured  # type: ignore[return-value]


def _connected_key_mask(distance: Image.Image, outer: int) -> Image.Image:
    candidate = distance.point([255 if value < outer else 0 for value in range(256)])
    padded = Image.new("L", (candidate.width + 2, candidate.height + 2), 255)
    padded.paste(candidate, (1, 1))
    ImageDraw.floodfill(padded, (0, 0), 128, thresh=0)
    connected = padded.crop((1, 1, padded.width - 1, padded.height - 1))
    return connected.point([255 if value == 128 else 0 for value in range(256)])


def remove_chroma(
    image: Image.Image,
    chroma: tuple[int, int, int],
    inner: int = 10,
    outer: int = 82,
    key_interior: bool = False,
) -> Image.Image:
    """Recover soft alpha only in key-coloured regions connected to the border.

    Restricting transparency to the border-connected matte protects intentional
    key-like colours enclosed by the subject. RGB spill is subsequently removed
    from partially transparent pixels by straight-alpha decontamination.
    """
    rgb = image.convert("RGB")
    key = Image.new("RGB", rgb.size, chroma)
    difference = ImageChops.difference(rgb, key)
    red, green, blue = difference.split()
    distance = ImageChops.lighter(ImageChops.lighter(red, green), blue)
    connected = (
        distance.point([255 if value < outer else 0 for value in range(256)])
        if key_interior else _connected_key_mask(distance, outer)
    )
    alpha_lut = [
        0 if value <= inner else 255 if value >= outer
        else (value - inner) * 255 // (outer - inner)
        for value in range(256)
    ]
    soft = distance.point(alpha_lut)
    alpha = Image.composite(soft, Image.new("L", rgb.size, 255), connected)
    rgba = rgb.convert("RGBA")
    rgba.putalpha(alpha)
    return rgba


def retain_primary_subject(image: Image.Image, threshold: int = 8) -> Image.Image:
    """Keep the visible component nearest the expected centered operator anchor."""
    alpha = image.getchannel("A")
    mask = alpha.point([0 if value <= threshold else 255 for value in range(256)])
    anchor = (image.width // 2, image.height * 2 // 3)
    seed: tuple[int, int] | None = None
    for radius in range(max(image.width, image.height)):
        candidates = (
            (anchor[0] - radius, anchor[1]), (anchor[0] + radius, anchor[1]),
            (anchor[0], anchor[1] - radius), (anchor[0], anchor[1] + radius),
        )
        for x, y in candidates:
            if 0 <= x < image.width and 0 <= y < image.height and mask.getpixel((x, y)):
                seed = (x, y)
                break
        if seed is not None:
            break
    if seed is None:
        raise ValueError("chroma removal produced no centered subject component")
    ImageDraw.floodfill(mask, seed, 128, thresh=0)
    selected = mask.point([255 if value == 128 else 0 for value in range(256)])
    result = image.copy()
    result.putalpha(ImageChops.multiply(alpha, selected))
    return result


def subject_bbox(image: Image.Image, threshold: int = 8) -> tuple[int, int, int, int]:
    alpha = image.getchannel("A").point([0 if value <= threshold else 255 for value in range(256)])
    bbox = alpha.getbbox()
    if bbox is None:
        raise ValueError("chroma removal produced an empty subject")
    return bbox


def union_boxes(boxes: Sequence[tuple[int, int, int, int]]) -> tuple[int, int, int, int]:
    if not boxes:
        raise ValueError("cannot union an empty bbox sequence")
    return (
        min(box[0] for box in boxes), min(box[1] for box in boxes),
        max(box[2] for box in boxes), max(box[3] for box in boxes),
    )


def repair_pathological_keyed_frames(
    frames: Sequence[Image.Image], neutral_edge: int, minimum_ratio: float = 0.25,
) -> tuple[list[Image.Image], dict[int, int]]:
    """Replace keyed collapse frames with the nearest valid authored sample.

    Video carriers can occasionally contain a single nearly-empty chroma frame.
    Magnifying a one-pixel remnant to the runtime target creates a full-cell blank
    flash. Preserve timing and deterministic frame count by borrowing the nearest
    valid sampled pose; ties resolve to the earlier frame.
    """
    if neutral_edge < 1:
        raise ValueError("neutral subject edge must be positive")
    edges = []
    for frame in frames:
        box = subject_bbox(frame)
        edges.append(max(box[2] - box[0], box[3] - box[1]))
    valid = [index for index, edge in enumerate(edges) if edge >= neutral_edge * minimum_ratio]
    if not valid:
        raise ValueError("all sampled keyed frames collapsed below the neutral subject threshold")
    repaired = list(frames)
    replacements: dict[int, int] = {}
    for index, edge in enumerate(edges):
        if edge >= neutral_edge * minimum_ratio:
            continue
        source = min(valid, key=lambda candidate: (abs(candidate - index), candidate))
        repaired[index] = frames[source].copy()
        replacements[index] = source
    return repaired, replacements


def _decontaminate_spill(image: Image.Image, chroma: tuple[int, int, int]) -> Image.Image:
    """Estimate foreground RGB from straight alpha for fringe pixels only."""
    pixels = image.load()
    for y in range(image.height):
        for x in range(image.width):
            red, green, blue, alpha = pixels[x, y]
            if alpha == 0:
                pixels[x, y] = (0, 0, 0, 0)
            elif alpha < 248:
                # C = aF + (1-a)K. Clamp protects very low-alpha noise.
                a = max(alpha, 24)
                channels = (red, green, blue)
                recovered = tuple(
                    max(0, min(255, (channels[i] * 255 - (255 - a) * chroma[i] + a // 2) // a))
                    for i in range(3)
                )
                pixels[x, y] = (*recovered, alpha)
    return image


def normalize_frame(image: Image.Image, scale: float, chroma: tuple[int, int, int]) -> tuple[Image.Image, dict[str, object]]:
    bbox = subject_bbox(image)
    crop = image.crop(bbox)
    neutral_width = max(1, int(math.floor(crop.width * scale + 0.5)))
    neutral_height = max(1, int(math.floor(crop.height * scale + 0.5)))
    neutral = crop.resize((neutral_width, neutral_height), Image.Resampling.LANCZOS)
    neutral = _decontaminate_spill(neutral, chroma)
    trimmed = neutral.crop(subject_bbox(neutral))
    correction = TARGET_EDGE / max(trimmed.width, trimmed.height)
    width = max(1, int(math.floor(trimmed.width * correction + 0.5)))
    height = max(1, int(math.floor(trimmed.height * correction + 0.5)))
    cell, final_bbox = _render_normalized_cell(trimmed, width, height, chroma)
    longest = max(final_bbox[2] - final_bbox[0], final_bbox[3] - final_bbox[1])
    if not EDGE_MIN <= longest <= EDGE_MAX:
        raise ValueError(f"normalized subject longest edge {longest} is outside {EDGE_MIN}..{EDGE_MAX}")
    metrics: dict[str, object] = {
        "source_bbox": list(bbox), "bbox": list(final_bbox), "longest_edge": longest,
        "post_key_trim_size": [trimmed.width, trimmed.height],
        "root": [320, 640], "bbox_bottom_center": [(final_bbox[0] + final_bbox[2]) / 2, final_bbox[3]],
    }
    return cell, metrics


def _render_normalized_cell(
    crop: Image.Image, width: int, height: int, chroma: tuple[int, int, int]
) -> tuple[Image.Image, tuple[int, int, int, int]]:
    resized = crop.resize((width, height), Image.Resampling.LANCZOS)
    resized = resized.crop(subject_bbox(resized))
    width, height = resized.size
    cell = Image.new("RGBA", (CELL_SIZE, CELL_SIZE), (0, 0, 0, 0))
    left = 320 - width // 2
    top = CELL_SIZE - height
    if left < 0 or left + width > CELL_SIZE or top < 0:
        raise ValueError(f"normalized subject clips cell: size={width}x{height}, origin=({left},{top})")
    cell.alpha_composite(resized, (left, top))
    return cell, subject_bbox(cell)


def pack_atlas(cells: Sequence[Image.Image], action: str) -> Image.Image:
    rows = 3 if action == "idle" else 2
    expected = IDLE_FRAMES if action == "idle" else ATTACK_FRAMES
    if len(cells) != expected:
        raise ValueError(f"{action} requires exactly {expected} cells, got {len(cells)}")
    atlas = Image.new("RGBA", (ATLAS_COLUMNS * CELL_SIZE, rows * CELL_SIZE), (0, 0, 0, 0))
    for index, cell in enumerate(cells):
        atlas.alpha_composite(cell, ((index % ATLAS_COLUMNS) * CELL_SIZE, (index // ATLAS_COLUMNS) * CELL_SIZE))
    return atlas


def mirror_atlas_cells(atlas: Image.Image, frame_count: int) -> Image.Image:
    mirrored = Image.new("RGBA", atlas.size, (0, 0, 0, 0))
    for index in range(frame_count):
        left = (index % ATLAS_COLUMNS) * CELL_SIZE
        top = (index // ATLAS_COLUMNS) * CELL_SIZE
        cell = atlas.crop((left, top, left + CELL_SIZE, top + CELL_SIZE))
        mirrored.paste(cell.transpose(Image.Transpose.FLIP_LEFT_RIGHT), (left, top))
    return mirrored


def save_runtime_webp(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    # Runtime cells remain 640 px and source carriers stay immutable at full
    # resolution. High-quality VP8 + lossless alpha avoids adding ~550 MiB to the
    # Web PCK while preserving the authored silhouette and transparent edge.
    image.save(path, format="WEBP", lossless=False, quality=92, method=6, exact=True)
    data = path.read_bytes()
    if b"VP8 " not in data or b"ALPH" not in data:
        raise RuntimeError(f"Pillow did not emit a lossy-alpha WebP: {path}")


def build(args: argparse.Namespace) -> dict[str, object]:
    carrier = args.carrier.resolve()
    runtime_root = args.runtime_root.resolve()
    source_root = args.source_root.resolve()
    if not carrier.is_file():
        raise FileNotFoundError(f"carrier does not exist: {carrier}")
    if args.force_final_neutral and args.action != "attack":
        raise ValueError("--force-final-neutral is only valid for attack sequences")
    carrier_before = sha256_file(carrier)
    metadata = probe_media(carrier)
    west_direction = "nw"
    target_dir = runtime_root / "assets/sprites/operators/animated" / args.class_id / args.gender
    east_path = target_dir / f"{args.action}_{args.direction}.webp"
    west_path = target_dir / f"{args.action}_{west_direction}.webp"
    validation_path = source_root / "runtime-previews" / args.class_id / args.gender / f"{args.action}_{args.direction}.validation.json"

    with tempfile.TemporaryDirectory(prefix="advanced-operator-") as temporary:
        extracted = extract_native_frames(carrier, Path(temporary))
        indices = select_frame_indices(
            len(extracted), args.action, metadata.fps, args.window_start, args.window_end,
        )
        opened: list[Image.Image] = []
        endpoints: list[Image.Image] = []
        try:
            for index in indices:
                with Image.open(extracted[index]) as frame:
                    opened.append(frame.convert("RGB"))
            for endpoint_path in (extracted[0], extracted[-1]):
                with Image.open(endpoint_path) as frame:
                    endpoints.append(frame.convert("RGB"))
            requested = parse_chroma(args.chroma)
            measured = measure_chroma(endpoints, requested)
            keyed = [
                retain_primary_subject(remove_chroma(frame, measured, key_interior=args.key_interior))
                for frame in opened
            ]
            keyed_endpoints = [
                retain_primary_subject(
                    remove_chroma(frame, measured, key_interior=args.key_interior)
                )
                for frame in endpoints
            ]
            end_union = union_boxes(tuple(subject_bbox(frame) for frame in keyed_endpoints))
            union_width, union_height = end_union[2] - end_union[0], end_union[3] - end_union[1]
            scale = TARGET_EDGE / max(union_width, union_height)
            keyed, repaired_frames = repair_pathological_keyed_frames(
                keyed, max(union_width, union_height),
            )
            cells: list[Image.Image] = []
            frame_metrics: list[dict[str, object]] = []
            for frame in keyed:
                frame_box = subject_bbox(frame)
                frame_edge = max(frame_box[2] - frame_box[0], frame_box[3] - frame_box[1])
                stabilized_scale = TARGET_EDGE / frame_edge
                cell, metrics = normalize_frame(frame, stabilized_scale, measured)
                metrics["neutral_scale"] = scale
                metrics["stabilized_scale"] = stabilized_scale
                metrics["camera_compensation"] = stabilized_scale / scale
                cells.append(cell)
                frame_metrics.append(metrics)
            if args.force_final_neutral:
                cells[-1] = cells[0].copy()
                frame_metrics[-1] = dict(frame_metrics[0])
                frame_metrics[-1]["forced_from_output_frame"] = 0
            east = pack_atlas(cells, args.action)
            west = mirror_atlas_cells(east, len(cells))
            save_runtime_webp(east, east_path)
            save_runtime_webp(west, west_path)
        finally:
            for image in opened:
                image.close()
            for image in endpoints:
                image.close()

    carrier_after = sha256_file(carrier)
    if carrier_after != carrier_before:
        raise RuntimeError("source carrier changed during processing")
    payload: dict[str, object] = {
        "schema_version": 1,
        "class_id": args.class_id, "gender": args.gender, "action": args.action,
        "direction": args.direction, "mirror_direction": west_direction,
        "carrier": str(carrier), "carrier_sha256": carrier_before,
        "source_media": metadata.as_json(), "extracted_frame_count": len(extracted),
        "frame_indices": indices,
        "window": {"start": args.window_start, "end": args.window_end},
        "force_final_neutral": args.force_final_neutral,
        "requested_chroma": args.chroma.upper(), "measured_chroma": "#%02X%02X%02X" % measured,
        "neutral_scale": scale, "endpoint_union_bbox": list(end_union),
        "repaired_frame_indices": {str(index): source for index, source in repaired_frames.items()},
        "cell_size": [CELL_SIZE, CELL_SIZE], "columns": ATLAS_COLUMNS,
        "atlas_path": str(east_path), "atlas_sha256": sha256_file(east_path),
        "mirror_path": str(west_path), "mirror_sha256": sha256_file(west_path),
        "atlas_size": list(east.size), "frame_count": len(cells),
        "frames": frame_metrics,
    }
    validation_path.parent.mkdir(parents=True, exist_ok=True)
    validation_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return {"atlas": str(east_path), "mirror": str(west_path), "validation": str(validation_path)}


def make_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--carrier", type=Path, required=True)
    parser.add_argument("--class-id", required=True)
    parser.add_argument("--gender", choices=GENDERS, required=True)
    parser.add_argument("--action", choices=ACTIONS, required=True)
    parser.add_argument("--direction", choices=EAST_DIRECTIONS, required=True)
    parser.add_argument("--chroma", required=True)
    parser.add_argument("--runtime-root", type=Path, required=True)
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--window-start", type=float)
    parser.add_argument("--window-end", type=float)
    parser.add_argument(
        "--key-interior", action="store_true",
        help="remove enclosed chroma gaps as well as border-connected matte",
    )
    parser.add_argument(
        "--force-final-neutral", action="store_true",
        help="replace the final attack cell with the first approved neutral cell",
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = make_parser()
    args = parser.parse_args(argv)
    try:
        parse_chroma(args.chroma)
        if not args.class_id or any(part in args.class_id for part in ("/", "\\", "..")):
            raise ValueError("class-id must be one non-empty path-safe identifier")
        result = build(args)
    except (FileNotFoundError, RuntimeError, ValueError) as exc:
        parser.error(str(exc))
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
