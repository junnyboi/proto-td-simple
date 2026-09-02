extends SceneTree

const Catalog := preload("res://data/presentation/operator_visual_catalog.gd")
const AnimationDef := preload("res://data/presentation/operator_animation_def.gd")
const Animator := preload("res://scripts/view/operator_animator.gd")
const UnitStateType := preload("res://sim/unit_state.gd")
const PROPORTION_CONFIG_PATH := "res://data/presentation/advanced_operator_proportions.json"

const CLASS_BY_OPERATOR := {
	&"caster_1": &"mage_apprentice",
	&"guard_1": &"swordmaster",
	&"sniper_1": &"gunner",
}
const DIRECTIONS: Array[StringName] = [&"ne", &"nw"]

var _failures: Array[String] = []


func _init() -> void:
	_test_complete_catalog()
	_test_identity_routing()
	_test_runtime_application()
	if _failures.is_empty():
		print("ADVANCED_OPERATOR_ANIMATION_TEST_OK")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)


func _test_complete_catalog() -> void:
	var calibration := _load_proportion_config()
	var target_height := int(calibration.get("target_runtime_body_height_px", 0))
	var identities: Dictionary = calibration.get("identities", {}) as Dictionary
	_check(target_height == 64, "advanced runtime body-height target must remain 64px")
	_check(identities.size() == 6, "expected exact 6-identity proportion calibration matrix")
	var advanced_templates := 0
	var manifest_rows := 0
	for template_id: StringName in Catalog.template_ids():
		var text := String(template_id)
		if not (text.ends_with("_female") or text.ends_with("_male")):
			continue
		if text.begins_with("recruit_"):
			continue
		advanced_templates += 1
		var animation := Catalog.get_animation(template_id) as AnimationDef
		_check(animation != null, "%s definition missing" % template_id)
		if animation == null:
			continue
		var proportion: Dictionary = identities.get(text, {}) as Dictionary
		var expected_body_height := int(proportion.get("normalized_body_height_px", 0))
		_check(animation.schema_version == 2, "%s must use generated schema 2" % template_id)
		_check(animation.source_cell_px == 640, "%s must use 640px source cells" % template_id)
		_check(
			animation.normalized_subject_height_px == expected_body_height,
			"%s body calibration drifted" % template_id,
		)
		_check(animation.pivot == Vector2(0.5, 1.0), "%s pivot must be bottom-center" % template_id)
		_check(not animation.placeholder, "%s must not be placeholder art" % template_id)
		_check(
			Animator.body_size(animation).is_equal_approx(
				Vector2.ONE * (640.0 * float(target_height) / float(expected_body_height))
			),
			"%s display calibration drifted" % template_id,
		)
		for family: StringName in [&"idle", &"attack"]:
			var mapping: Dictionary = animation.idle_by_direction if family == &"idle" else animation.attack_by_direction
			var frame_count := 24 if family == &"idle" else 13
			for direction: StringName in DIRECTIONS:
				var logical_id := StringName(mapping.get(direction, &""))
				var expected_logical_id := StringName(
					"op_anim_%s_%s_%s" % [text, family, direction]
				)
				_check(
					logical_id == expected_logical_id,
					"%s %s %s should select %s" % [
						template_id, family, direction, expected_logical_id,
					],
				)
				var metadata := Art.metadata(logical_id)
				manifest_rows += 1
				_check(not metadata.is_empty(), "%s missing manifest row" % logical_id)
				_check(Art.frame_count(logical_id) == frame_count, "%s frame count drifted" % logical_id)
				_check(Art.size(logical_id) == Vector2i(640, 640), "%s source cell drifted" % logical_id)
				_check(int(metadata.get(&"columns", 0)) == 8, "%s atlas columns drifted" % logical_id)
				_check(Art.atlas_region_for_frame(metadata, 7).position.x == 4480, "%s frame 7 region drifted" % logical_id)
				_check(Art.atlas_region_for_frame(metadata, 8).position == Vector2i(0, 640), "%s row boundary drifted" % logical_id)
				var provenance: Variant = metadata.get(&"provenance")
				_check(provenance is Dictionary, "%s provenance missing" % logical_id)
				if provenance is Dictionary:
					_check(String(provenance.get(&"atlas_sha256", "")).length() == 64, "%s atlas hash missing" % logical_id)
					_check(
						provenance.get(&"source_manifest_id") == "advanced_operator_sprites_v2",
						"%s did not route to the V2 immutable source archive" % logical_id,
					)
					var expected_kind := "mirrored" if direction == &"nw" else "generated"
					_check(provenance.get(&"source_kind") == expected_kind, "%s provenance kind drifted" % logical_id)
	_check(advanced_templates == 6, "expected 6 retained class/gender templates, got %d" % advanced_templates)
	_check(manifest_rows == 24, "expected 24 retained class manifest rows, got %d" % manifest_rows)
	for error: String in Catalog.validate_all():
		_failures.append("catalog: %s" % error)


func _load_proportion_config() -> Dictionary:
	var file := FileAccess.open(PROPORTION_CONFIG_PATH, FileAccess.READ)
	if file == null:
		_failures.append("missing advanced operator proportion config")
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary:
		_failures.append("advanced operator proportion config must contain a JSON object")
		return {}
	return parsed as Dictionary


func _test_identity_routing() -> void:
	for operator_id: StringName in CLASS_BY_OPERATOR:
		var class_id: StringName = CLASS_BY_OPERATOR[operator_id]
		var routed := {}
		for index: int in 128:
			var template_id := Catalog.template_for_unit(
				operator_id, &"", StringName("hero_%03d" % index), index, class_id,
			)
			routed[template_id] = true
		_check(routed.has(StringName("%s_female" % class_id)), "%s never routes female" % operator_id)
		_check(routed.has(StringName("%s_male" % class_id)), "%s never routes male" % operator_id)
		_check(routed.size() == 2, "%s routes outside its two identity variants" % operator_id)
	var expected_gender := Catalog.deterministic_identity_gender(&"persistent_hero", &"", 17)
	_check(
		Catalog.template_for_unit(
			&"guard_1", &"", &"persistent_hero", 17, &"mage_apprentice",
		) == StringName("mage_apprentice_%s" % expected_gender),
		"canonical class_id must override a stale operator fallback without changing identity gender",
	)
	_check(
		Catalog.template_for_unit(&"guard_1", &"portrait_guard_1", &"legacy", 18) == &"guard_1",
		"classless legacy/replay units must preserve incumbent operator-id presentation",
	)


func _test_runtime_application() -> void:
	var cases := [
		{&"template": &"gunner_female", &"facing": UnitStateType.Facing.RIGHT},
		{&"template": &"mage_apprentice_male", &"facing": UnitStateType.Facing.DOWN},
		{&"template": &"swordmaster_female", &"facing": UnitStateType.Facing.LEFT},
		{&"template": &"swordmaster_male", &"facing": UnitStateType.Facing.UP},
	]
	for record: Dictionary in cases:
		var animation := Catalog.get_animation(record[&"template"]) as AnimationDef
		var unit := UnitStateType.new()
		unit.facing = int(record[&"facing"])
		var sprite := TextureRect.new()
		_check(
			Animator.apply(unit, 120, 1.0, sprite, animation),
			"%s idle frame failed live animator application" % record[&"template"],
		)
		_check(sprite.texture != null, "%s idle texture is null" % record[&"template"])
		_check(sprite.get_meta(&"operator_animation_state") == &"idle", "%s idle state missing" % record[&"template"])
		unit.last_attack_tick = 119
		_check(
			Animator.apply(unit, 120, 1.0, sprite, animation),
			"%s attack frame failed live animator application" % record[&"template"],
		)
		_check(sprite.texture != null, "%s attack texture is null" % record[&"template"])
		_check(sprite.get_meta(&"operator_animation_state") == &"attack", "%s attack state missing" % record[&"template"])
		sprite.free()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
