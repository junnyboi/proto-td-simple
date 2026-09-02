#!/usr/bin/env python3
"""Register the complete advanced-operator atlas matrix and archive provenance."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import shutil
from pathlib import Path
from typing import Any

CLASS_ORDER = (
    "gunner", "mage_apprentice", "swordmaster",
)
GENDER_ORDER = ("female", "male")
ACTION_ORDER = ("idle", "attack")
DIRECTION_ORDER = ("ne", "nw")
GENERATED_DIRECTION_ORDER = ("ne",)
MIRROR_SOURCE = {"nw": "ne"}
FRAME_COUNTS = {"idle": 24, "attack": 13}
ROWS = {"idle": 3, "attack": 2}
SOURCE_MANIFEST_ID = "advanced_operator_sprites_v2"
PROPORTION_CONFIG = Path("data/presentation/advanced_operator_proportions.json")
BEGIN_MARKER = "; BEGIN GENERATED ADVANCED OPERATOR ANIMATIONS"
END_MARKER = "; END GENERATED ADVANCED OPERATOR ANIMATIONS"
LEGACY_BEGIN_MARKER = "# BEGIN GENERATED ADVANCED OPERATOR ANIMATIONS"
LEGACY_END_MARKER = "# END GENERATED ADVANCED OPERATOR ANIMATIONS"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def atlas_path(repository: Path, class_id: str, gender: str, action: str, direction: str) -> Path:
    return (
        repository / "assets/sprites/operators/animated" / class_id / gender
        / f"{action}_{direction}.webp"
    )


def logical_id(class_id: str, gender: str, action: str, direction: str) -> str:
    return f"op_anim_{class_id}_{gender}_{action}_{direction}"


def source_direction_for(
    class_id: str,
    gender: str,
    action: str,
    logical_direction: str,
) -> str:
    return logical_direction


def validation_path(source_root: Path, class_id: str, gender: str, action: str, direction: str) -> Path:
    return source_root / "runtime-previews" / class_id / gender / f"{action}_{direction}.validation.json"


def ensure_complete(repository: Path, source_root: Path) -> None:
    missing: list[str] = []
    for class_id in CLASS_ORDER:
        for gender in GENDER_ORDER:
            for action in ACTION_ORDER:
                for direction in DIRECTION_ORDER:
                    path = atlas_path(repository, class_id, gender, action, direction)
                    if not path.is_file():
                        missing.append(str(path))
                for direction in GENERATED_DIRECTION_ORDER:
                    record = validation_path(source_root, class_id, gender, action, direction)
                    if not record.is_file():
                        missing.append(str(record))
    if missing:
        raise FileNotFoundError("incomplete advanced-operator matrix:\n" + "\n".join(missing))


def load_proportion_calibrations(repository: Path) -> tuple[int, dict[str, int]]:
    path = repository / PROPORTION_CONFIG
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("schema_version") != 1:
        raise ValueError(f"{path}: expected proportion schema version 1")
    target = int(payload.get("target_runtime_body_height_px", 0))
    if target <= 0:
        raise ValueError(f"{path}: target runtime body height must be positive")
    raw_identities = payload.get("identities")
    if not isinstance(raw_identities, dict):
        raise ValueError(f"{path}: identities must be a dictionary")
    expected = {
        f"{class_id}_{gender}"
        for class_id in CLASS_ORDER
        for gender in GENDER_ORDER
    }
    if set(raw_identities) != expected:
        raise ValueError(f"{path}: expected exact {len(expected)}-identity calibration matrix")
    calibrations: dict[str, int] = {}
    for template_id, record in raw_identities.items():
        if not isinstance(record, dict):
            raise ValueError(f"{path}: {template_id} calibration must be a dictionary")
        measured = int(record.get("normalized_body_height_px", 0))
        if measured < 480 or measured > 640:
            raise ValueError(f"{path}: {template_id} body height must be 480..640")
        calibrations[template_id] = measured
    return target, calibrations


def write_resources(repository: Path) -> list[Path]:
    target = repository / "data/presentation/operator_visuals"
    created: list[Path] = []
    display_height_px, calibrations = load_proportion_calibrations(repository)
    for class_id in CLASS_ORDER:
        for gender in GENDER_ORDER:
            template_id = f"{class_id}_{gender}"
            normalized_body_height_px = calibrations[template_id]
            direction_map_idle = "\n".join(
                f'&"{direction}": &"{logical_id(class_id, gender, "idle", source_direction_for(class_id, gender, "idle", direction))}"'
                + ("," if index < len(DIRECTION_ORDER) - 1 else "")
                for index, direction in enumerate(DIRECTION_ORDER)
            )
            direction_map_attack = "\n".join(
                f'&"{direction}": &"{logical_id(class_id, gender, "attack", source_direction_for(class_id, gender, "attack", direction))}"'
                + ("," if index < len(DIRECTION_ORDER) - 1 else "")
                for index, direction in enumerate(DIRECTION_ORDER)
            )
            text = f'''[gd_resource type="Resource" script_class="OperatorAnimationDef" load_steps=2 format=3]

[ext_resource type="Script" path="res://data/presentation/operator_animation_def.gd" id="1_def"]

[resource]
script = ExtResource("1_def")
schema_version = 2
visual_id = &"operator_{template_id}"
idle_by_direction = {{
{direction_map_idle}
}}
attack_by_direction = {{
{direction_map_attack}
}}
idle_frame_count = 24
attack_frame_count = 13
fps = 12.0
pivot = Vector2(0.5, 1)
source_cell_px = 640
display_height_px = {display_height_px}
normalized_subject_height_px = {normalized_body_height_px}
placeholder = false
'''
            path = target / f"{template_id}.tres"
            path.write_text(text, encoding="utf-8")
            created.append(path)
    return created


def prune_south_resource_maps(repository: Path) -> list[Path]:
    target = repository / "data/presentation/operator_visuals"
    changed: list[Path] = []
    for path in sorted(target.glob("*.tres")):
        lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
        retained = [
            line for line in lines
            if not line.lstrip().startswith(('&"se":', '&"sw":'))
        ]
        normalized = "".join(retained).replace(': &"se"', ': &"ne"').replace(
            ': &"sw"', ': &"nw"',
        )
        if normalized != "".join(lines):
            path.write_text(normalized, encoding="utf-8")
            changed.append(path)
    return changed


def prune_south_manifest_entries(text: str) -> str:
    lines = text.splitlines(keepends=True)
    retained: list[str] = []
    depth = 0
    skipping = False
    for line in lines:
        if not skipping and line.startswith('&"op_anim_'):
            identifier = line.split('"', 2)[1]
            skipping = identifier.endswith(("_se", "_sw"))
            if skipping:
                depth = line.count("{") - line.count("}")
                continue
        if skipping:
            depth += line.count("{") - line.count("}")
            if depth == 0:
                skipping = False
            continue
        retained.append(line)
    return "".join(retained)


def gd_manifest_entry(
    repository: Path,
    class_id: str,
    gender: str,
    action: str,
    direction: str,
) -> str:
    path = atlas_path(repository, class_id, gender, action, direction)
    identifier = logical_id(class_id, gender, action, direction)
    source_direction = MIRROR_SOURCE.get(direction, direction)
    source_kind = "mirrored" if direction in MIRROR_SOURCE else "generated"
    mirrored_from = source_direction if source_kind == "mirrored" else ""
    relative = path.relative_to(repository).as_posix()
    frames = FRAME_COUNTS[action]
    loop = "true" if action == "idle" else "false"
    return f'''&"{identifier}": {{
"animations": {{
&"{action}": {{
&"fps": 12.0,
&"length": {frames},
&"loop": {loop},
&"start": 0
}}
}},
"columns": 8,
"frames": {frames},
"pattern": "res://{relative}",
"pivot": Vector2(0.5, 1),
"placeholder": false,
"provenance": {{
&"action": "{action}",
&"atlas_sha256": "{sha256_file(path)}",
&"class_id": "{class_id}",
&"direction": "{direction}",
&"gender": "{gender}",
&"mirrored_from": "{mirrored_from}",
&"source_kind": "{source_kind}",
&"source_manifest_id": "{SOURCE_MANIFEST_ID}"
}},
"size": Vector2i(640, 640)
}}'''


def update_manifest(repository: Path) -> int:
    manifest_path = repository / "assets/manifest.tres"
    text = manifest_path.read_text(encoding="utf-8")
    schema_line = "schema_version = 3"
    if "\nschema_version = " in text:
        lines = text.splitlines()
        replaced = False
        for index, line in enumerate(lines):
            if not replaced and line.startswith("schema_version = "):
                lines[index] = schema_line
                replaced = True
        text = "\n".join(lines) + ("\n" if text.endswith("\n") else "")
    else:
        resource_script = 'script = ExtResource("1_g6syk")\n'
        if resource_script not in text:
            raise ValueError("assets/manifest.tres is missing its expected resource script")
        text = text.replace(resource_script, resource_script + schema_line + "\n", 1)
    for begin_marker, end_marker in (
        (BEGIN_MARKER, END_MARKER),
        (LEGACY_BEGIN_MARKER, LEGACY_END_MARKER),
    ):
        if begin_marker in text:
            start = text.index(",\n" + begin_marker)
            end = text.index(end_marker, start) + len(end_marker)
            text = text[:start] + text[end:]
    text = prune_south_manifest_entries(text)
    entries = [
        gd_manifest_entry(repository, class_id, gender, action, direction)
        for class_id in CLASS_ORDER
        for gender in GENDER_ORDER
        for action in ACTION_ORDER
        for direction in DIRECTION_ORDER
    ]
    insertion = ",\n" + BEGIN_MARKER + "\n" + ",\n".join(entries) + "\n" + END_MARKER
    # Insert before the entries Dictionary's final brace while retaining the
    # previous asset entry's own closing brace.
    closing = "\n}"
    if not text.endswith(closing + "\n") and not text.endswith(closing):
        raise ValueError("assets/manifest.tres does not end with the expected entries brace")
    suffix = "\n" if text.endswith("\n") else ""
    body = text[:-len(suffix)] if suffix else text
    body = body[:-len(closing)] + insertion + closing
    manifest_path.write_text(body + suffix, encoding="utf-8")
    return len(entries)


def image_geometry(path: Path) -> list[int]:
    from PIL import Image

    with Image.open(path) as image:
        return [image.width, image.height]


def build_source_manifest(repository: Path, source_root: Path) -> dict[str, Any]:
    existing_path = source_root / "source_manifest.json"
    existing: dict[str, Any] = {}
    if existing_path.is_file():
        existing = json.loads(existing_path.read_text(encoding="utf-8"))
    references = existing.get("references", [])
    expected_references = len(CLASS_ORDER) * len(GENDER_ORDER)
    if not isinstance(references, list) or len(references) != expected_references:
        raise ValueError(
            f"source manifest must retain exactly {expected_references} approved GPT Image 2 references"
        )

    keyframes = existing.get("keyframes", [])
    expected_keyframes = expected_references * len(GENERATED_DIRECTION_ORDER)
    if not isinstance(keyframes, list) or len(keyframes) != expected_keyframes:
        raise ValueError(
            f"source manifest must retain exactly {expected_keyframes} approved V2 keyframes"
        )
    keyframe_by_id = {str(row.get("id", "")): row for row in keyframes}
    for class_id in CLASS_ORDER:
        for gender in GENDER_ORDER:
            for direction in GENERATED_DIRECTION_ORDER:
                identifier = f"keyframe:{class_id}:{gender}:{direction}"
                row = keyframe_by_id.get(identifier)
                if not isinstance(row, dict):
                    raise ValueError(f"source manifest is missing {identifier}")
                path = Path(str(row.get("normalized", row.get("path", ""))))
                if not path.is_file():
                    raise FileNotFoundError(path)
                row["path"] = str(path)
                row["sha256"] = sha256_file(path)
                row["dimensions"] = image_geometry(path)
                row["model"] = "gpt-image-2"
                row["approved"] = True

    carriers = existing.get("carriers", [])
    expected_carriers = expected_keyframes * len(ACTION_ORDER)
    if not isinstance(carriers, list) or len(carriers) != expected_carriers:
        raise ValueError(
            f"source manifest must retain exactly {expected_carriers} approved V2 carriers"
        )
    carrier_by_id = {str(row.get("id", "")): row for row in carriers}
    runtime_sequences: list[dict[str, Any]] = []
    for class_id in CLASS_ORDER:
        for gender in GENDER_ORDER:
            for action in ACTION_ORDER:
                for direction in GENERATED_DIRECTION_ORDER:
                    record_path = validation_path(source_root, class_id, gender, action, direction)
                    record = json.loads(record_path.read_text(encoding="utf-8"))
                    carrier_path = Path(record["carrier"])
                    identifier = f"carrier:{class_id}:{gender}:{action}:{direction}"
                    row = carrier_by_id.get(identifier)
                    if not isinstance(row, dict):
                        raise ValueError(f"source manifest is missing {identifier}")
                    row.update({
                        "path": str(carrier_path),
                        "sha256": sha256_file(carrier_path),
                        "source_media": record["source_media"],
                        "first_keyframe": f"keyframe:{class_id}:{gender}:{direction}",
                        "last_keyframe": (
                            f"keyframe:{class_id}:{gender}:{direction}" if action == "idle" else ""
                        ),
                        "approved": True,
                    })
                for direction in DIRECTION_ORDER:
                    path = atlas_path(repository, class_id, gender, action, direction)
                    source_direction = MIRROR_SOURCE.get(direction, direction)
                    record_path = validation_path(source_root, class_id, gender, action, source_direction)
                    record = json.loads(record_path.read_text(encoding="utf-8"))
                    runtime_sequences.append({
                        "id": logical_id(class_id, gender, action, direction),
                        "class_id": class_id,
                        "gender": gender,
                        "action": action,
                        "direction": direction,
                        "source_kind": "mirrored" if direction in MIRROR_SOURCE else "generated",
                        "mirrored_from": source_direction if direction in MIRROR_SOURCE else "",
                        "path": str(path),
                        "sha256": sha256_file(path),
                        "cell_size": [640, 640],
                        "columns": 8,
                        "atlas_dimensions": [5120, ROWS[action] * 640],
                        "frame_count": FRAME_COUNTS[action],
                        "fps": 12.0,
                        "encoding": "webp-vp8-q92-lossless-alpha",
                        "validation_record": str(record_path),
                        "carrier_sha256": record["carrier_sha256"],
                    })

    payload: dict[str, Any] = {
        **existing,
        "schema_version": 2,
        "id": SOURCE_MANIFEST_ID,
        "repository": str(repository),
        "reference_count": len(references),
        "keyframe_count": len(keyframes),
        "carrier_count": len(carriers),
        "runtime_sequence_count": len(runtime_sequences),
        "references": references,
        "keyframes": keyframes,
        "carriers": carriers,
        "runtime_sequences": runtime_sequences,
    }
    existing_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    tsv_path = source_root / "source_manifest.tsv"
    with tsv_path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream, delimiter="\t", lineterminator="\n")
        writer.writerow(["kind", "id", "class_id", "gender", "action", "direction", "path", "sha256"])
        for row in references:
            writer.writerow([
                "reference", row["id"], row["class_id"], row["gender"], "", "",
                row["design_reference"], row["design_reference_sha256"],
            ])
        for row in keyframes:
            writer.writerow(["keyframe", row["id"], row["class_id"], row["gender"], "", row["direction"], row["path"], row["sha256"]])
        for row in carriers:
            writer.writerow(["carrier", row["id"], row["class_id"], row["gender"], row["action"], row["direction"], row["path"], row["sha256"]])
        for row in runtime_sequences:
            writer.writerow(["runtime", row["id"], row["class_id"], row["gender"], row["action"], row["direction"], row["path"], row["sha256"]])
    return payload


def write_archive_docs(repository: Path, source_root: Path) -> None:
    readme = source_root / "README.md"
    readme.write_text(
        "# Advanced Operator Sprite Source Archive V2\n\n"
        "Immutable GPT Image 2 reference boards and directional keyframes, 12 silent "
        "four-second image-conditioned video carriers, validation records, and the exact 24-sequence "
        "runtime projection for the three retained recruit specializations. Runtime atlases "
        "use 640×640 cells with a 560–640px subject edge; in-game footprint is controlled "
        "only by Godot presentation scale. The manifest records the exact Veo 3.1, Veo 3.1 "
        "Fast, or Gemini Omni model used per carrier. `source_manifest.json` is canonical and "
        "`source_manifest.tsv` is its review projection.\n",
        encoding="utf-8",
    )
    (source_root / "requirements.lock").write_text("Pillow==11.3.0\n", encoding="utf-8")
    tools_target = source_root / "tools"
    tools_target.mkdir(parents=True, exist_ok=True)
    for name in [
        "build_advanced_operator_sprites.py",
        "build_advanced_operator_matrix.py",
        "validate_advanced_operator_sprites.py",
        "register_advanced_operator_sprites.py",
        "prepare_reference_archive.py",
    ]:
        source = repository / "tools/operator_sprites" / name
        if source.is_file():
            shutil.copy2(source, tools_target / name)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", type=Path, required=True)
    parser.add_argument("--source-root", type=Path)
    parser.add_argument(
        "--resources-only",
        action="store_true",
        help="Regenerate presentation resources without rewriting immutable source provenance.",
    )
    args = parser.parse_args()
    repository = args.repository.resolve()
    if args.resources_only:
        resources = write_resources(repository)
        pruned = prune_south_resource_maps(repository)
        manifest_rows = update_manifest(repository)
        print(json.dumps({
            "resources": len(resources),
            "pruned_resources": len(pruned),
            "manifest_rows": manifest_rows,
        }, sort_keys=True))
        return 0
    if args.source_root is None:
        parser.error("--source-root is required unless --resources-only is used")
    source_root = args.source_root.resolve()
    ensure_complete(repository, source_root)
    resources = write_resources(repository)
    pruned_resources = prune_south_resource_maps(repository)
    manifest_rows = update_manifest(repository)
    source_manifest = build_source_manifest(repository, source_root)
    write_archive_docs(repository, source_root)
    print(json.dumps({
        "resources": len(resources),
        "pruned_resources": len(pruned_resources),
        "manifest_rows": manifest_rows,
        "references": source_manifest["reference_count"],
        "keyframes": source_manifest["keyframe_count"],
        "carriers": source_manifest["carrier_count"],
        "runtime_sequences": source_manifest["runtime_sequence_count"],
    }, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
