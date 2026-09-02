#!/usr/bin/env python3
"""Audit localization parity, visible fallbacks, and the binding Anima War canon.

The audit is deterministic and network-free. In addition to EN/ZH key and
placeholder parity, it loads ``canon_contract.json`` and checks active runtime
sources for Company Manus, the Simplified Chinese glossary, retired canon,
required canon, literal English fallbacks, and zero-waiver release status.
"""
from __future__ import annotations

import argparse
import ast
import fnmatch
import hashlib
import json
import re
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
CONTRACT_PATH = ROOT / "data/presentation/narrative/canon_contract.json"
PRODUCTION_ROOTS = [ROOT / p for p in ("autoloads", "scripts", "scenes", "sim", "data")]
SOURCE_SUFFIXES = {".gd", ".tscn", ".tres", ".json"}
KEY_RE = re.compile(r'[&]?"((?:ui|data)\.[A-Za-z0-9_.]*[A-Za-z0-9_])"')
PLACEHOLDER_RE = re.compile(r"\{([A-Za-z][A-Za-z0-9_]*)\}")
VISIBLE_PATTERNS = [
    re.compile(r"\b(?:text|title|placeholder_text|tooltip_text|accessibility_name|accessibility_description)\s*=\s*(\"(?:[^\"\\]|\\.)*\")"),
    re.compile(r"\.set_text\(\s*(\"(?:[^\"\\]|\\.)*\")"),
    re.compile(r"\b(?:Label|Button|CheckButton|RichTextLabel)\.new\(\s*(\"(?:[^\"\\]|\\.)*\")"),
]
LOCALIZED_CALL_RE = re.compile(
    r"(?:UiCopyType\.(?:text|format_text)|UI_COPY\.(?:text|format_text)|_copy|_t|_fmt|_format|_format_copy)"
    r"\(\s*[&]?\"((?:ui|data)\.[A-Za-z0-9_.]+)\"\s*,\s*(\"(?:[^\"\\]|\\.)*\")",
    re.S,
)
IGNORE_LITERAL = re.compile(r"^(?:|[A-Za-z0-9_./:-]+|res://.*|user://.*|uid://.*|[0-9 .,:;_+*/%<>=!&|?×←→↔↕•—-]+)$")
FORMAT_TOKEN_RE = re.compile(r"%(?:\d+\$)?[-+#0 ]*(?:\d+|\*)?(?:\.\d+)?[diouxXeEfFgGscv%]")
REVIEWED_RUNTIME_DEFAULTS = {
    ("scenes/ui/title_settings.tscn", "MASTER VOLUME"),
    ("scenes/ui/title_settings.tscn", "MUSIC VOLUME"),
    ("scenes/ui/title_settings.tscn", "SFX VOLUME"),
    ("scenes/ui/title_settings.tscn", "MUSIC // ON"),
    ("scenes/ui/title_settings.tscn", "FRAME LIMIT"),
    ("scenes/ui/title_settings.tscn", "REDUCED MOTION // OFF"),
    ("scenes/ui/title_settings.tscn", "TEXT SCALE  //  100%"),
    ("scenes/ui/title_settings.tscn", "Settings could not be saved."),
}


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "docs/localization/latest-audit.json")
    parser.add_argument("--strict-hardcoded", action="store_true")
    return parser.parse_args()


def _load_json(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError(f"expected object in {path}")
    return payload


def _catalog_payload(locale: str) -> dict[str, Any]:
    return _load_json(ROOT / "localization" / f"{locale}.json")


def _catalog(locale: str) -> dict[str, str]:
    return {str(k): str(v) for k, v in _catalog_payload(locale)["entries"].items()}


def _decode_literal(token: str) -> str:
    value = ast.literal_eval(token)
    return value if isinstance(value, str) else str(value)


def _is_format_only(value: str) -> bool:
    return re.search(r"[A-Za-z\u3400-\u9fff]", FORMAT_TOKEN_RE.sub("", value)) is None


def _line_for_offset(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


def _active_paths(contract: dict[str, Any]) -> list[Path]:
    paths: set[Path] = set()
    for pattern in contract.get("active_surface_sources", []):
        pattern = str(pattern)
        for path in ROOT.glob(pattern):
            if path.is_file() and path.suffix in SOURCE_SUFFIXES:
                paths.add(path)
    return sorted(paths)


def _waiver_for_line(contract: dict[str, Any], relative: str, line: str) -> dict[str, Any] | None:
    for waiver in contract.get("phase6_temporary_waivers", []):
        if waiver.get("path") != relative or "line_pattern" not in waiver:
            continue
        if re.search(str(waiver["line_pattern"]), line):
            return waiver
    return None


def _catalog_entries_for_canon(contract: dict[str, Any], locale: str, entries: dict[str, str]) -> tuple[dict[str, str], list[dict[str, str]]]:
    kept: dict[str, str] = {}
    waived: list[dict[str, str]] = []
    relative = f"localization/{locale}.json"
    prefixes = [
        str(w["json_key_prefix"])
        for w in contract.get("phase6_temporary_waivers", [])
        if w.get("path") == relative and w.get("json_key_prefix")
    ]
    for key, value in entries.items():
        matching = next((p for p in prefixes if key.startswith(p)), None)
        if matching is None:
            kept[key] = value
        else:
            waived.append({"path": relative, "key": key, "reason": "phase6 archive content waiver"})
    return kept, waived


def _matches(text: str, needle: str) -> bool:
    return needle.casefold() in text.casefold()


def main() -> int:
    args = _parse_args()
    contract = _load_json(CONTRACT_PATH)
    catalogs = {locale: _catalog(locale) for locale in ("en-US", "zh-CN")}
    english, chinese = catalogs["en-US"], catalogs["zh-CN"]

    used_keys: dict[str, list[str]] = {}
    hardcoded: list[dict[str, Any]] = []
    fallback_mismatches: list[dict[str, Any]] = []
    for base in PRODUCTION_ROOTS:
        if not base.exists():
            continue
        for path in sorted(p for p in base.rglob("*") if p.is_file() and p.suffix in SOURCE_SUFFIXES):
            relative = path.relative_to(ROOT).as_posix()
            try:
                text = path.read_text(encoding="utf-8")
            except UnicodeDecodeError:
                continue
            lines = text.splitlines()
            for line_number, line in enumerate(lines, 1):
                if line.strip().startswith(("#", ";")):
                    continue
                for match in KEY_RE.finditer(line):
                    used_keys.setdefault(match.group(1), []).append(f"{relative}:{line_number}")
                if path.suffix not in {".gd", ".tscn"}:
                    continue
                for pattern in VISIBLE_PATTERNS:
                    for match in pattern.finditer(line):
                        value = _decode_literal(match.group(1))
                        if value.startswith(("ui.", "data.")) or IGNORE_LITERAL.fullmatch(value) or _is_format_only(value):
                            continue
                        if (relative, value) in REVIEWED_RUNTIME_DEFAULTS:
                            continue
                        if re.search(r"[A-Za-z\u3400-\u9fff]", value):
                            hardcoded.append({"path": relative, "line": line_number, "text": value, "source": line.strip()})
            if path.suffix == ".gd":
                for match in LOCALIZED_CALL_RE.finditer(text):
                    key = match.group(1)
                    fallback = _decode_literal(match.group(2))
                    if key in english and english[key] != fallback:
                        fallback_mismatches.append({
                            "path": relative,
                            "line": _line_for_offset(text, match.start()),
                            "key": key,
                            "fallback": fallback,
                            "catalog": english[key],
                        })

    missing_chinese = sorted(set(english) - set(chinese))
    extra_chinese = sorted(set(chinese) - set(english))
    placeholder_drift: list[dict[str, Any]] = []
    for key in sorted(set(english) & set(chinese)):
        en_tokens = sorted(PLACEHOLDER_RE.findall(english[key]))
        zh_tokens = sorted(PLACEHOLDER_RE.findall(chinese[key]))
        if en_tokens != zh_tokens:
            placeholder_drift.append({"key": key, "english": en_tokens, "chinese": zh_tokens})

    identical = [{"key": key, "value": english[key]} for key in sorted(set(english) & set(chinese)) if english[key] == chinese[key]]
    missing_catalog_keys = sorted(set(used_keys) - set(english))

    canon_path = ROOT / str(contract["bible"]["path"])
    canon_text = canon_path.read_text(encoding="utf-8")
    canon_hash = hashlib.sha256(canon_path.read_bytes()).hexdigest()
    canon_hash_failures: list[dict[str, str]] = []
    if canon_hash != str(contract["bible"].get("sha256", "")):
        canon_hash_failures.append({"path": str(contract["bible"]["path"]), "expected": str(contract["bible"].get("sha256", "")), "actual": canon_hash})

    en_active, waived_en = _catalog_entries_for_canon(contract, "en-US", english)
    zh_active, waived_zh = _catalog_entries_for_canon(contract, "zh-CN", chinese)
    runtime_english = "\n".join(en_active.values())
    active_text_by_path: dict[str, str] = {
        "localization/en-US.json": runtime_english,
        "localization/zh-CN.json": "\n".join(zh_active.values()),
    }
    missing_active_prose: list[str] = []
    waived_sources: list[dict[str, str]] = waived_en + waived_zh
    for path in _active_paths(contract):
        relative = path.relative_to(ROOT).as_posix()
        if relative in active_text_by_path:
            continue
        lines: list[str] = []
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            waiver = _waiver_for_line(contract, relative, line)
            if waiver:
                waived_sources.append({"path": relative, "line": str(number), "reason": str(waiver["reason"])})
                continue
            lines.append(line)
        active_text_by_path[relative] = "\n".join(lines)
    for source in contract.get("active_prose_sources", []):
        relative = str(source)
        path = ROOT / relative
        if not path.is_file():
            missing_active_prose.append(relative)
            continue
        active_text_by_path[relative] = path.read_text(encoding="utf-8")
    all_active_text = "\n".join(active_text_by_path.values())

    required_canon_failures = [
        {"term": str(term), "scope": str(contract["bible"]["path"])}
        for term in contract.get("required_canon_terms", []) if not _matches(canon_text, str(term))
    ]
    required_runtime_failures = [
        {"term": str(term), "scope": "active English runtime catalog"}
        for term in contract.get("required_runtime_terms", []) if not _matches(runtime_english, str(term))
    ]

    company_name_failures: list[dict[str, Any]] = []
    company = contract.get("required_company_display", {})
    company_key = str(company.get("stable_key", ""))
    for locale in ("en-US", "zh-CN"):
        expected = str(company.get(locale, ""))
        actual = catalogs[locale].get(company_key, "")
        if actual != expected:
            company_name_failures.append({"locale": locale, "key": company_key, "expected": expected, "actual": actual})
    for pattern in contract.get("forbidden_company_display_patterns", []):
        for relative, text in active_text_by_path.items():
            if str(pattern).casefold() in text.casefold():
                company_name_failures.append({"path": relative, "forbidden": str(pattern)})

    retired_canon_failures: list[dict[str, Any]] = []
    for term in contract.get("retired_terms", []):
        for relative, text in active_text_by_path.items():
            if str(term).casefold() in text.casefold():
                retired_canon_failures.append({"path": relative, "term": str(term)})
    for pattern in contract.get("retired_claim_patterns", []):
        regex = re.compile(str(pattern), re.I | re.S)
        for relative, text in active_text_by_path.items():
            match = regex.search(text)
            if match:
                retired_canon_failures.append({"path": relative, "pattern": str(pattern), "match": match.group(0)[:240]})

    chinese_glossary_failures: list[dict[str, Any]] = []
    zh_text = "\n".join(zh_active.values())
    for term in contract.get("forbidden_chinese_terms", []):
        if str(term) in zh_text:
            chinese_glossary_failures.append({"forbidden": str(term)})
    glossary = contract.get("chinese_glossary", {})
    for key in ("first_explanation", "company", "anima_engine", "human_farm", "soul", "soul_anchor", "moon_gate", "repair_platform"):
        term = str(glossary.get(key, ""))
        if term and term not in zh_text:
            chinese_glossary_failures.append({"missing": term, "glossary_key": key})
    soul_energy = str(glossary.get("extracted_soul_energy_only", ""))
    if soul_energy:
        for key, value in zh_active.items():
            if soul_energy in value and not any(token in value for token in ("运送", "提取", "抽取", "燃烧", "供能", "能量")):
                chinese_glossary_failures.append({"key": key, "term": soul_energy, "reason": "not clearly extracted energy"})

    report: dict[str, Any] = {
        "schema_version": 4,
        "contract": {"path": CONTRACT_PATH.relative_to(ROOT).as_posix(), "schema_version": contract.get("schema_version")},
        "summary": {},
        "structural": {
            "catalog_counts": {locale: len(entries) for locale, entries in catalogs.items()},
            "missing_chinese": missing_chinese,
            "extra_chinese": extra_chinese,
            "placeholder_drift": placeholder_drift,
            "identical_values": identical,
            "production_key_count": len(used_keys),
            "missing_catalog_keys": [{"key": key, "locations": used_keys[key]} for key in missing_catalog_keys],
            "unreferenced_catalog_keys": sorted(set(english) - set(used_keys)),
            "active_prose_source_count": len(contract.get("active_prose_sources", [])),
            "missing_active_prose_sources": missing_active_prose,
        },
        "fallbacks": {
            "hardcoded_visible_candidates": hardcoded,
            "literal_fallback_mismatches": fallback_mismatches,
            "reviewed_runtime_defaults": [{"path": path, "text": text} for path, text in sorted(REVIEWED_RUNTIME_DEFAULTS)],
        },
        "canon": {
            "bible_hash_failures": canon_hash_failures,
            "required_canon_failures": required_canon_failures,
            "required_runtime_failures": required_runtime_failures,
            "company_name_failures": company_name_failures,
            "retired_canon_failures": retired_canon_failures,
            "chinese_glossary_failures": chinese_glossary_failures,
        },
        "temporary_phase6_waivers": contract.get("phase6_temporary_waivers", []),
        "waived_matches": waived_sources,
    }
    counts = {
        "structural_failures": len(missing_chinese) + len(extra_chinese) + len(placeholder_drift) + len(missing_catalog_keys) + len(missing_active_prose),
        "hardcoded_visible_failures": len(hardcoded),
        "literal_fallback_failures": len(fallback_mismatches),
        "company_name_failures": len(company_name_failures),
        "retired_canon_failures": len(retired_canon_failures),
        "required_canon_failures": len(required_canon_failures) + len(required_runtime_failures) + len(canon_hash_failures),
        "chinese_glossary_failures": len(chinese_glossary_failures),
        "temporary_phase6_waivers": len(contract.get("phase6_temporary_waivers", [])),
    }
    report["summary"] = counts | {"status": "pass" if all(v == 0 for k, v in counts.items() if k != "temporary_phase6_waivers") else "fail"}

    output = args.output if args.output.is_absolute() else ROOT / args.output
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report["summary"] | {"report": str(output)}, ensure_ascii=False, indent=2))

    strict_failure = any(counts[k] for k in counts if k != "temporary_phase6_waivers")
    if not args.strict_hardcoded:
        strict_failure = any(counts[k] for k in counts if k not in {"temporary_phase6_waivers", "hardcoded_visible_failures", "literal_fallback_failures"})
    return 1 if strict_failure else 0


if __name__ == "__main__":
    raise SystemExit(main())
