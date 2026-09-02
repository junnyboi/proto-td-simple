#!/usr/bin/env python3
"""Tests for deterministic advanced-operator carrier processing.

Run directly with:
    python3 tests/advanced_operator_processor_test.py
"""

from __future__ import annotations

import hashlib
import importlib.util
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from types import ModuleType

from PIL import Image, ImageChops, ImageDraw, ImageStat

REPOSITORY = Path(__file__).resolve().parents[1]
BUILDER_PATH = REPOSITORY / "tools/operator_sprites/build_advanced_operator_sprites.py"
VALIDATOR_PATH = REPOSITORY / "tools/operator_sprites/validate_advanced_operator_sprites.py"
REGISTRAR_PATH = REPOSITORY / "tools/operator_sprites/register_advanced_operator_sprites.py"
IMPORT_CONFIGURATOR_PATH = (
    REPOSITORY / "tools/operator_sprites/configure_advanced_operator_imports.py"
)
PROPORTION_AUDITOR_PATH = (
    REPOSITORY / "tools/operator_sprites/audit_operator_proportions.py"
)
CELL = 640


def load_module(name: str, path: Path) -> ModuleType:
    specification = importlib.util.spec_from_file_location(name, path)
    assert specification is not None and specification.loader is not None
    module = importlib.util.module_from_spec(specification)
    sys.modules[name] = module
    specification.loader.exec_module(module)
    return module


builder = load_module("advanced_sprite_builder", BUILDER_PATH)
validator = load_module("advanced_sprite_validator", VALIDATOR_PATH)
registrar = load_module("advanced_sprite_registrar", REGISTRAR_PATH)
proportion_auditor = load_module("advanced_proportion_auditor", PROPORTION_AUDITOR_PATH)


class WebImportBudgetTests(unittest.TestCase):
    def test_all_advanced_atlases_use_browser_safe_import_settings(self) -> None:
        root = REPOSITORY / "assets/sprites/operators/animated"
        imports = sorted(
            path
            for path in root.glob("**/*.webp.import")
            if len(path.relative_to(root).parts) == 3
        )
        self.assertEqual(88, len(imports))
        for path in imports:
            metadata = path.read_text(encoding="utf-8")
            self.assertIn("compress/mode=1", metadata, str(path))
            self.assertIn("compress/lossy_quality=0.92", metadata, str(path))
            self.assertIn("mipmaps/generate=true", metadata, str(path))
            self.assertIn("process/size_limit=0", metadata, str(path))

        completed = run([sys.executable, str(IMPORT_CONFIGURATOR_PATH)])
        self.assertIn("configured=88 changed=0", completed.stdout)

    def test_all_advanced_identities_project_to_one_body_height(self) -> None:
        payload = proportion_auditor.audit(REPOSITORY)
        self.assertEqual(22, payload["identity_count"])
        self.assertEqual([], payload["failures"])
        for row in payload["rows"]:
            self.assertAlmostEqual(
                64.0,
                row["projected_runtime_body_height_px"],
                delta=2.0,
                msg=row["template_id"],
            )

    def test_runtime_direction_contract_is_north_only(self) -> None:
        self.assertEqual(("ne", "nw"), registrar.DIRECTION_ORDER)
        self.assertEqual(("ne",), registrar.GENERATED_DIRECTION_ORDER)
        self.assertEqual({"nw": "ne"}, registrar.MIRROR_SOURCE)
        for class_id in registrar.CLASS_ORDER:
            for gender in registrar.GENDER_ORDER:
                for action in registrar.ACTION_ORDER:
                    for direction in registrar.DIRECTION_ORDER:
                        self.assertEqual(
                            direction,
                            registrar.source_direction_for(
                                class_id, gender, action, direction,
                            ),
                        )


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(command: list[str], expect_success: bool = True) -> subprocess.CompletedProcess[str]:
    completed = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if expect_success and completed.returncode != 0:
        raise AssertionError(
            f"command failed ({completed.returncode}): {' '.join(command)}\n"
            f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
        )
    return completed


def make_synthetic_carrier(path: Path, frame_root: Path, fps: int = 12) -> None:
    """Create a four-second 16:9 carrier with keyed, animated opaque shapes."""
    frame_root.mkdir(parents=True)
    for index in range(4 * fps):
        image = Image.new("RGB", (320, 180), (0, 255, 0))
        draw = ImageDraw.Draw(image)
        # Width varies slightly while height remains the longest edge. The foot
        # stays planted, and an enclosed green badge tests interior protection.
        left = 126 + (index % 5) - 2
        top = 30 + (index % 3) - 1
        draw.rounded_rectangle((left, top, left + 68, 169), radius=12, fill=(205, 40, 55))
        draw.rectangle((left - 20, 90, left + 88, 107), fill=(40, 80, 220))
        draw.ellipse((left + 25, top + 40, left + 43, top + 58), fill=(0, 255, 0), outline=(250, 220, 40), width=3)
        draw.rectangle((left + 28, 166, left + 40, 179), fill=(245, 210, 160))
        image.save(frame_root / f"frame_{index:04d}.png", format="PNG")
    run([
        "ffmpeg", "-v", "error", "-y", "-framerate", str(fps),
        "-i", str(frame_root / "frame_%04d.png"),
        "-f", "lavfi", "-i", "anullsrc=channel_layout=mono:sample_rate=48000",
        "-t", "4", "-c:v", "libx264", "-preset", "medium", "-crf", "14",
        "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest", str(path),
    ])


def atlas_cell(atlas: Image.Image, index: int) -> Image.Image:
    x = (index % 8) * CELL
    y = (index // 8) * CELL
    return atlas.crop((x, y, x + CELL, y + CELL))


class SamplingAndChromaTests(unittest.TestCase):
    def test_idle_endpoint_exclusive_and_attack_endpoint_preserving(self) -> None:
        idle = builder.select_frame_indices(48, "idle", 12.0)
        self.assertEqual(24, len(idle))
        self.assertEqual(list(range(0, 48, 2)), idle)
        self.assertNotIn(48, idle)
        attack = builder.select_frame_indices(48, "attack", 12.0, 0.5, 3.5)
        self.assertEqual(13, len(attack))
        self.assertEqual(6, attack[0])
        self.assertEqual(42, attack[-1])
        self.assertEqual(13, len(set(attack)))

    def test_chroma_soft_alpha_and_interior_colour_protection(self) -> None:
        image = Image.new("RGB", (80, 80), (0, 255, 0))
        draw = ImageDraw.Draw(image)
        draw.rectangle((15, 10, 65, 79), fill=(220, 30, 30))
        draw.rectangle((35, 30, 45, 40), fill=(0, 255, 0))
        keyed = builder.remove_chroma(image, (0, 255, 0))
        alpha = keyed.getchannel("A")
        self.assertEqual(0, alpha.getpixel((0, 0)))
        self.assertEqual(255, alpha.getpixel((40, 35)), "enclosed key colour must remain interior")
        self.assertEqual(255, alpha.getpixel((40, 50)))

    def test_invalid_sampling_windows(self) -> None:
        with self.assertRaisesRegex(ValueError, "requires both"):
            builder.select_frame_indices(48, "attack", 12.0)
        with self.assertRaisesRegex(ValueError, "full carrier"):
            builder.select_frame_indices(48, "idle", 12.0, 0.0, 1.0)
        with self.assertRaisesRegex(ValueError, "too few"):
            builder.select_frame_indices(10, "idle", 12.0)

    def test_pathological_keyed_frame_uses_nearest_valid_sample(self) -> None:
        valid_a = Image.new("RGBA", (100, 100), (0, 0, 0, 0))
        ImageDraw.Draw(valid_a).rectangle((30, 10, 70, 99), fill=(220, 40, 30, 255))
        collapsed = Image.new("RGBA", (100, 100), (0, 0, 0, 0))
        collapsed.putpixel((50, 80), (20, 20, 20, 255))
        valid_b = Image.new("RGBA", (100, 100), (0, 0, 0, 0))
        ImageDraw.Draw(valid_b).rectangle((25, 10, 75, 99), fill=(40, 80, 220, 255))
        repaired, replacements = builder.repair_pathological_keyed_frames(
            [valid_a, collapsed, valid_b], neutral_edge=90,
        )
        self.assertEqual({1: 0}, replacements)
        self.assertEqual(valid_a.tobytes(), repaired[1].tobytes())
        self.assertEqual(valid_b.tobytes(), repaired[2].tobytes())

    def test_manifest_registration_is_idempotent_and_pins_schema(self) -> None:
        with tempfile.TemporaryDirectory(prefix="advanced-operator-registration-") as temporary:
            repository = Path(temporary)
            manifest = repository / "assets/manifest.tres"
            manifest.parent.mkdir(parents=True)
            manifest.write_text(
                '[gd_resource type="Resource" script_class="AssetManifest" format=3]\n\n'
                '[ext_resource type="Script" path="res://assets/asset_manifest.gd" id="1_g6syk"]\n\n'
                '[resource]\nscript = ExtResource("1_g6syk")\nentries = {\n'
                '&"fixture": {\n"animations": {\n&"default": {\n&"fps": 1.0,\n'
                '&"length": 1,\n&"loop": true,\n&"start": 0\n}\n},\n"frames": 1,\n'
                '"pattern": "res://fixture.webp",\n"pivot": Vector2(0.5, 0.5),\n'
                '"placeholder": false,\n"size": Vector2i(1, 1)\n}\n}\n',
                encoding="utf-8",
            )
            for class_id in registrar.CLASS_ORDER:
                for gender in registrar.GENDER_ORDER:
                    for action in registrar.ACTION_ORDER:
                        for direction in registrar.DIRECTION_ORDER:
                            atlas = registrar.atlas_path(
                                repository, class_id, gender, action, direction,
                            )
                            atlas.parent.mkdir(parents=True, exist_ok=True)
                            atlas.write_bytes(
                                f"{class_id}:{gender}:{action}:{direction}".encode("utf-8")
                            )
            self.assertEqual(88, registrar.update_manifest(repository))
            first = manifest.read_bytes()
            self.assertIn(b"schema_version = 3", first)
            self.assertEqual(88, registrar.update_manifest(repository))
            self.assertEqual(first, manifest.read_bytes())


@unittest.skipUnless(shutil.which("ffmpeg") and shutil.which("ffprobe"), "ffmpeg is required")
class EndToEndProcessorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary = tempfile.TemporaryDirectory(prefix="advanced-operator-test-")
        cls.root = Path(cls.temporary.name)
        cls.runtime = cls.root / "runtime"
        cls.sources = cls.root / "sources"
        cls.carrier = cls.sources / "carrier.mp4"
        cls.sources.mkdir(parents=True)
        make_synthetic_carrier(cls.carrier, cls.root / "input-frames")
        cls.carrier_hash = sha256(cls.carrier)
        common = [
            sys.executable, str(BUILDER_PATH), "--carrier", str(cls.carrier),
            "--class-id", "test_guard", "--gender", "female", "--chroma", "#00FF00",
            "--runtime-root", str(cls.runtime), "--source-root", str(cls.sources),
        ]
        cls.idle_command = common + ["--action", "idle", "--direction", "ne"]
        cls.attack_command = common + [
            "--action", "attack", "--direction", "ne",
            "--window-start", "0.5", "--window-end", "3.5",
        ]
        cls.idle_result = json.loads(run(cls.idle_command).stdout)
        cls.attack_result = json.loads(run(cls.attack_command).stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary.cleanup()

    def assert_atlas_contract(self, result: dict[str, str], action: str, count: int) -> None:
        east_path, west_path = Path(result["atlas"]), Path(result["mirror"])
        rows = 3 if action == "idle" else 2
        with Image.open(east_path) as east_open, Image.open(west_path) as west_open:
            east_open.load()
            west_open.load()
            self.assertEqual("RGBA", east_open.mode)
            self.assertEqual((5120, rows * CELL), east_open.size)
            self.assertIn(b"VP8 ", east_path.read_bytes())
            self.assertIn(b"ALPH", east_path.read_bytes())
            self.assertIn(b"VP8 ", west_path.read_bytes())
            self.assertIn(b"ALPH", west_path.read_bytes())
            east, west = east_open.copy(), west_open.copy()
        extrema = east.getchannel("A").getextrema()
        self.assertEqual(0, extrema[0])
        self.assertEqual(255, extrema[1])
        for index in range(count):
            frame = atlas_cell(east, index)
            bbox = frame.getchannel("A").point(lambda value: 255 if value > 8 else 0).getbbox()
            self.assertIsNotNone(bbox)
            assert bbox is not None
            self.assertTrue(560 <= max(bbox[2] - bbox[0], bbox[3] - bbox[1]) <= 640)
            self.assertEqual(CELL, bbox[3])
            expected = frame.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
            actual = atlas_cell(west, index)
            self.assertIsNone(
                ImageChops.difference(
                    expected.getchannel("A"), actual.getchannel("A"),
                ).getbbox(),
            )
            rgb_difference = ImageChops.difference(expected.convert("RGB"), actual.convert("RGB"))
            self.assertLessEqual(max(channel[1] for channel in rgb_difference.getextrema()), 32)
            self.assertLessEqual(max(ImageStat.Stat(rgb_difference).mean), 3.0)
        for index in range(count, rows * 8):
            self.assertIsNone(atlas_cell(east, index).getchannel("A").getbbox())
            self.assertIsNone(atlas_cell(west, index).getchannel("A").getbbox())

    def test_idle_atlas_row_boundaries_mirror_alpha_and_validation(self) -> None:
        self.assert_atlas_contract(self.idle_result, "idle", 24)
        with Image.open(self.idle_result["atlas"]) as atlas:
            # Frame 7 is the final first-row cell; 8 starts row two; 15/16
            # similarly cross the second boundary. All must remain populated.
            for index in (7, 8, 15, 16):
                self.assertIsNotNone(atlas_cell(atlas.convert("RGBA"), index).getchannel("A").getbbox())
        record = json.loads(Path(self.idle_result["validation"]).read_text())
        self.assertEqual(24, len(record["frame_indices"]))
        self.assertEqual(self.carrier_hash, record["carrier_sha256"])
        self.assertEqual(1, record["source_media"]["audio_streams"])
        validated = validator.validate_one(
            Path(self.idle_result["atlas"]), Path(self.idle_result["mirror"]),
            "idle", self.carrier, Path(self.idle_result["validation"]),
        )
        self.assertTrue(validated["mirror"]["exact_alpha_per_frame"])
        self.assertLessEqual(validated["mirror"]["maximum_rgb_delta"], 32)
        self.assertLessEqual(validated["mirror"]["maximum_rgb_mean"], 3.0)

        malformed = json.loads(json.dumps(record))
        malformed["frames"][0]["camera_compensation"] = 9.0
        malformed_path = self.root / "collapsed.validation.json"
        malformed_path.write_text(json.dumps(malformed), encoding="utf-8")
        with self.assertRaisesRegex(validator.ValidationError, "keyed collapse"):
            validator.validate_one(
                Path(self.idle_result["atlas"]), Path(self.idle_result["mirror"]),
                "idle", self.carrier, malformed_path,
            )

    def test_attack_atlas_endpoint_indices_padding_and_validation_cli(self) -> None:
        self.assert_atlas_contract(self.attack_result, "attack", 13)
        record = json.loads(Path(self.attack_result["validation"]).read_text())
        self.assertEqual(13, record["frame_count"])
        self.assertEqual(6, record["frame_indices"][0])
        self.assertEqual(42, record["frame_indices"][-1])
        completed = run([
            sys.executable, str(VALIDATOR_PATH), "--validation-json", self.attack_result["validation"],
        ])
        self.assertEqual(13, json.loads(completed.stdout)["atlas"]["frame_count"])

    def test_force_final_neutral_stabilizes_attack_recovery(self) -> None:
        forced = json.loads(run(self.attack_command + ["--force-final-neutral"]).stdout)
        record = json.loads(Path(forced["validation"]).read_text())
        self.assertTrue(record["force_final_neutral"])
        self.assertEqual(0, record["frames"][-1]["forced_from_output_frame"])
        with Image.open(forced["atlas"]) as opened:
            atlas = opened.convert("RGBA")
        first = atlas_cell(atlas, 0)
        final = atlas_cell(atlas, 12)
        self.assertIsNone(
            ImageChops.difference(first.getchannel("A"), final.getchannel("A")).getbbox()
        )
        rgb_difference = ImageChops.difference(first.convert("RGB"), final.convert("RGB"))
        self.assertLessEqual(max(ImageStat.Stat(rgb_difference).mean), 3.0)

        invalid_idle = run(self.idle_command + ["--force-final-neutral"], expect_success=False)
        self.assertNotEqual(0, invalid_idle.returncode)
        self.assertIn("only valid for attack", invalid_idle.stderr)

    def test_reproducible_output_and_source_never_overwritten(self) -> None:
        first_hashes = (sha256(Path(self.idle_result["atlas"])), sha256(Path(self.idle_result["mirror"])))
        rerun = json.loads(run(self.idle_command).stdout)
        self.assertEqual(first_hashes, (sha256(Path(rerun["atlas"])), sha256(Path(rerun["mirror"]))))
        self.assertEqual(self.carrier_hash, sha256(self.carrier))

    def test_batch_counts(self) -> None:
        result = validator.validate_batch(self.sources, expected_carriers=1, expected_outputs=4)
        self.assertEqual(1, result["carrier_count"])
        self.assertEqual(2, result["generated_record_count"])
        self.assertEqual(4, result["output_count"])
        with self.assertRaisesRegex(validator.ValidationError, "carrier count"):
            validator.validate_batch(self.sources, expected_carriers=2, expected_outputs=4)

    def test_cli_errors_are_clear(self) -> None:
        invalid_direction = run([
            sys.executable, str(BUILDER_PATH), "--carrier", str(self.carrier),
            "--class-id", "test", "--gender", "male", "--action", "idle",
            "--direction", "nw", "--chroma", "#00FF00", "--runtime-root", str(self.runtime),
            "--source-root", str(self.sources),
        ], expect_success=False)
        self.assertNotEqual(0, invalid_direction.returncode)
        self.assertIn("invalid choice", invalid_direction.stderr)
        missing_window = run([
            sys.executable, str(BUILDER_PATH), "--carrier", str(self.carrier),
            "--class-id", "test", "--gender", "male", "--action", "attack",
            "--direction", "ne", "--chroma", "#00FF00", "--runtime-root", str(self.runtime),
            "--source-root", str(self.sources),
        ], expect_success=False)
        self.assertNotEqual(0, missing_window.returncode)
        self.assertIn("requires both", missing_window.stderr)
        malformed_chroma = run([
            sys.executable, str(BUILDER_PATH), "--carrier", str(self.carrier),
            "--class-id", "test", "--gender", "male", "--action", "idle",
            "--direction", "ne", "--chroma", "green", "--runtime-root", str(self.runtime),
            "--source-root", str(self.sources),
        ], expect_success=False)
        self.assertNotEqual(0, malformed_chroma.returncode)
        self.assertIn("#RRGGBB", malformed_chroma.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
