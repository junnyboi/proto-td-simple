extends SceneTree

const AssetManifestType := preload("res://assets/asset_manifest.gd")
const OperatorAnimationDefType := preload("res://data/presentation/operator_animation_def.gd")
const OperatorAnimatorType := preload("res://scripts/view/operator_animator.gd")
const OperatorVisualCatalogType := preload("res://data/presentation/operator_visual_catalog.gd")

var _failures: Array[String] = []


func _init() -> void:
	_test_manifest_profiles()
	_test_animation_profiles()
	_test_atlas_boundaries()
	_test_generated_cache_policy()
	_test_existing_catalog()
	if _failures.is_empty():
		print("ADVANCED_OPERATOR_SCHEMA_TEST_OK")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)


func _test_manifest_profiles() -> void:
	var manifest := AssetManifestType.new()
	var legacy := _entry(1, Vector2i(128, 128))
	_check(manifest.entry_diagnostics(&"legacy", legacy).is_empty(), "legacy six-field row failed")

	var legacy_atlas := _entry(6, Vector2i(401, 600))
	legacy_atlas["columns"] = 6
	legacy_atlas["display_size"] = Vector2i(64, 80)
	legacy_atlas["animations"] = {
		&"idle": {&"start": 0, &"length": 6, &"fps": 6.0, &"loop": true},
	}
	_check(
		manifest.entry_diagnostics(&"legacy_atlas", legacy_atlas).is_empty(),
		"legacy multi-column row failed",
	)

	var generated := _entry(24, Vector2i(640, 640))
	generated["columns"] = 8
	generated["provenance"] = _provenance("idle", "ne", "generated", "")
	generated["animations"] = {
		&"idle": {&"start": 0, &"length": 24, &"fps": 12.0, &"loop": true},
	}
	_check(
		manifest.entry_diagnostics(&"generated", generated).is_empty(),
		"generated eight-field row failed",
	)
	var invalid_columns := generated.duplicate(true)
	invalid_columns["columns"] = 4
	_check(
		not manifest.entry_diagnostics(&"generated_wrong_columns", invalid_columns).is_empty(),
		"generated row admitted a non-eight-column atlas",
	)
	var invalid_mirror := generated.duplicate(true)
	invalid_mirror["provenance"] = _provenance("idle", "nw", "mirrored", "se")
	_check(
		not manifest.entry_diagnostics(&"generated_wrong_mirror", invalid_mirror).is_empty(),
		"generated row admitted an invalid mirror source",
	)
	generated.erase("provenance")
	_check(
		not manifest.entry_diagnostics(&"generated_without_provenance", generated).is_empty(),
		"generated row admitted without provenance",
	)

	for path: String in [
		"res://assets/manifest.tres",
		"res://assets/act1_shared_manifest.tres",
	]:
		var existing := load(path) as AssetManifestType
		_check(existing != null, "%s failed to load" % path)
		if existing != null:
			_check(existing.schema_version == 3, "%s did not serialize schema version 3" % path)
			_check(existing.validate_contract().is_empty(), "%s contract failed" % path)


func _test_animation_profiles() -> void:
	var generated := OperatorAnimationDefType.new()
	generated.schema_version = 2
	generated.visual_id = &"operator_fixture_male"
	generated.idle_by_direction = _directions("idle")
	generated.attack_by_direction = _directions("attack")
	generated.source_cell_px = 640
	generated.pivot = Vector2(0.5, 1.0)
	generated.display_height_px = 64
	generated.normalized_subject_height_px = 600
	generated.placeholder = false
	generated.placeholder_source_by_logical_id = {}
	_check(generated.validate_contract().is_empty(), "generated animation profile failed")
	var expected := 640.0 * 64.0 / 600.0
	_check(
		OperatorAnimatorType.body_size(generated).is_equal_approx(Vector2.ONE * expected),
		"generated body size ignored source_cell_px",
	)
	generated.source_cell_px = 192
	_check(not generated.validate_contract().is_empty(), "schema 2 admitted a 192-pixel cell")

	var recruit := OperatorVisualCatalogType.get_animation(&"recruit_male")
	_check(recruit != null, "legacy recruit animation missing")
	if recruit != null:
		_check(recruit.schema_version == 1, "legacy recruit schema changed")
		_check(recruit.source_cell_px == 192, "legacy recruit source cell changed")
		_check(recruit.validate_contract().is_empty(), "legacy recruit animation failed")


func _test_atlas_boundaries() -> void:
	var entry := _entry(24, Vector2i(640, 640))
	entry["columns"] = 8
	entry["provenance"] = _provenance("idle", "ne", "generated", "")
	_check(
		Art.atlas_region_for_frame(entry, 7) == Rect2i(4480, 0, 640, 640),
		"frame 7 atlas region drifted",
	)
	_check(
		Art.atlas_region_for_frame(entry, 8) == Rect2i(0, 640, 640, 640),
		"frame 8 did not enter row two",
	)
	_check(
		Art.atlas_region_for_frame(entry, 15) == Rect2i(4480, 640, 640, 640),
		"frame 15 atlas region drifted",
	)
	_check(
		Art.atlas_region_for_frame(entry, 16) == Rect2i(0, 1280, 640, 640),
		"frame 16 did not enter row three",
	)
	_check(Art.atlas_region_for_frame(entry, 24) == Rect2i(), "padded cell became addressable")


func _test_generated_cache_policy() -> void:
	Art._reset_manifests_for_test()
	var first := Art.texture(&"op_anim_gunner_female_idle_ne", 0)
	var second := Art.texture(&"op_anim_gunner_female_idle_ne", 1)
	_check(first != null and second != null, "generated cache test failed to load atlas frames")
	_check(
		Art._cached_texture_count_for_test() == 0,
		"generated animation frames accumulated in the process-lifetime Art cache",
	)


func _test_existing_catalog() -> void:
	for error: String in OperatorVisualCatalogType.validate_all():
		_failures.append("existing catalog: %s" % error)


func _entry(frames: int, size: Vector2i) -> Dictionary:
	return {
		"pattern": "res://tests/fixture.webp",
		"frames": frames,
		"size": size,
		"placeholder": false,
		"pivot": Vector2(0.5, 1.0),
		"animations": AssetManifestType.legacy_animations(frames),
	}


func _provenance(
	action: String, direction: String, source_kind: String, mirrored_from: String
) -> Dictionary:
	return {
		&"class_id": "fixture",
		&"gender": "male",
		&"action": action,
		&"direction": direction,
		&"source_kind": source_kind,
		&"mirrored_from": mirrored_from,
		&"source_manifest_id": "fixture-source",
		&"atlas_sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
	}


func _directions(action: String) -> Dictionary:
	return {
		&"ne": StringName("fixture_%s_ne" % action),
		&"nw": StringName("fixture_%s_nw" % action),
	}


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
