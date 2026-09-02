#!/usr/bin/env python3
"""Remove retired class/operator assets from the Godot asset manifest."""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "assets/manifest.tres"

REMOVED_CLASS_IDS = (
    "banner_guard",
    "defender",
    "immovable",
    "shock_trooper",
    "sniper",
    "sorcerer",
    "sword_saint",
    "witch_doctor",
)
REMOVED_OPERATOR_IDS = (
    "caster_2",
    "defender_1",
    "defender_2",
    "guard_2",
    "sniper_2",
    "vanguard_1",
    "vanguard_2",
    "witch_doctor_1",
)


def entry_span(text: str, asset_id: str) -> tuple[int, int] | None:
    marker = f'&"{asset_id}": {{'
    start = text.find(marker)
    if start < 0:
        return None
    brace = text.find("{", start)
    depth = 0
    in_string = False
    escaped = False
    for index in range(brace, len(text)):
        char = text[index]
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            continue
        if char == '"':
            in_string = True
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return start, index + 1
    raise RuntimeError(f"unterminated manifest entry: {asset_id}")


def top_level_asset_ids(text: str) -> list[str]:
    entries_marker = "entries = {"
    index = text.find(entries_marker)
    if index < 0:
        raise RuntimeError("asset manifest has no entries dictionary")
    index += len(entries_marker)
    depth = 1
    in_string = False
    escaped = False
    asset_ids: list[str] = []
    while index < len(text) and depth > 0:
        char = text[index]
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            index += 1
            continue
        if char == '"':
            in_string = True
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
        elif depth == 1 and text.startswith('&"', index):
            end = text.find('"', index + 2)
            if end < 0:
                raise RuntimeError("unterminated manifest asset identifier")
            asset_ids.append(text[index + 2 : end])
            index = end
        index += 1
    return asset_ids


def retired_asset_id(asset_id: str) -> bool:
    if asset_id in REMOVED_OPERATOR_IDS:
        return True
    for operator_id in REMOVED_OPERATOR_IDS:
        if asset_id == f"portrait_{operator_id}" or asset_id.startswith(
            f"op_anim_{operator_id}_"
        ):
            return True
    for class_id in REMOVED_CLASS_IDS:
        if asset_id.startswith(f"portrait_specialization_{class_id}_"):
            return True
        for gender in ("female", "male"):
            if asset_id.startswith(f"op_anim_{class_id}_{gender}_"):
                return True
    return False


def remove_entry(text: str, asset_id: str) -> str:
    span = entry_span(text, asset_id)
    if span is None:
        return text
    start, end = span
    if text.startswith(",\n", end):
        end += 2
    elif start >= 2 and text[start - 2 : start] == ",\n":
        start -= 2
    return text[:start] + text[end:]


def main() -> None:
    text = MANIFEST.read_text(encoding="utf-8")
    retired = [asset_id for asset_id in top_level_asset_ids(text) if retired_asset_id(asset_id)]
    for asset_id in retired:
        text = remove_entry(text, asset_id)
    MANIFEST.write_text(text, encoding="utf-8")
    print(f"removed {len(retired)} retired class/operator manifest entries")


if __name__ == "__main__":
    main()
