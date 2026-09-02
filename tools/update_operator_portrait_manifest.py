#!/usr/bin/env python3
"""Register generated operator portraits in assets/manifest.tres."""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "assets/manifest.tres"

RECRUITS = {
    "portrait_recruit_00": "res://assets/portraits/recruits/solcrest_female.png",
    "portrait_recruit_01": "res://assets/portraits/recruits/solcrest_male.png",
    "portrait_recruit_02": "res://assets/portraits/recruits/vesper_female.png",
    "portrait_recruit_03": "res://assets/portraits/recruits/vesper_male.png",
    "portrait_recruit_04": "res://assets/portraits/recruits/lunaris_female.png",
    "portrait_recruit_05": "res://assets/portraits/recruits/lunaris_male.png",
    "portrait_recruit_06": "res://assets/portraits/recruits/crimson_female.png",
    "portrait_recruit_07": "res://assets/portraits/recruits/crimson_male.png",
}

LEGACY = {
    "portrait_caster_1": "res://assets/portraits/caster_1.png",
    "portrait_guard_1": "res://assets/portraits/guard_1.png",
    "portrait_sniper_1": "res://assets/portraits/sniper_1.png",
}

SPECIALIZATIONS = {
    f"portrait_specialization_{class_id}_{variant}": (
        f"res://assets/portraits/specializations/{class_id}_{variant}.png"
    )
    for class_id in (
        "gunner",
        "mage_apprentice",
        "swordmaster",
    )
    for variant in ("female", "male")
}


def entry_block(asset_id: str, path: str) -> str:
    return f'''&"{asset_id}": {{
"animations": {{
&"default": {{
&"fps": 1.0,
&"length": 1,
&"loop": true,
&"start": 0
}}
}},
"frames": 1,
"pattern": "{path}",
"pivot": Vector2(0.5, 0.5),
"placeholder": false,
"size": Vector2i(512, 512)
}}'''


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


def replace_or_insert(text: str, asset_id: str, path: str) -> str:
    replacement = entry_block(asset_id, path)
    span = entry_span(text, asset_id)
    if span is not None:
        start, end = span
        return text[:start] + replacement + text[end:]
    anchor = '&"portrait_recruit_00": {'
    index = text.find(anchor)
    if index < 0:
        raise RuntimeError("portrait insertion anchor not found")
    return text[:index] + replacement + ",\n" + text[index:]


def main() -> None:
    text = MANIFEST.read_text(encoding="utf-8")
    for asset_id, path in {**LEGACY, **RECRUITS, **SPECIALIZATIONS}.items():
        text = replace_or_insert(text, asset_id, path)
    MANIFEST.write_text(text, encoding="utf-8")
    print(
        f"registered {len(RECRUITS)} Recruit, {len(SPECIALIZATIONS)} specialization, "
        f"and refreshed {len(LEGACY)} legacy portrait entries"
    )


if __name__ == "__main__":
    main()
