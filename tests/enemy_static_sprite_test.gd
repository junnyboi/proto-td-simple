extends SceneTree

const STATIC_ENEMIES: Array[StringName] = [
	&"runner", &"shieldbearer", &"breacher", &"heavy",
	&"drone", &"interceptor", &"spellcaster", &"mini_boss",
]

var _failures := PackedStringArray()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	Art._reset_manifests_for_test()
	_validate_manifest()
	_validate_asset_contract()
	_validate_projection_and_motion()
	_validate_combat_effects()
	_validate_grunt_exception()
	Art._reset_manifests_for_test()
	EnemyAnimator._damage_flash_shader = null
	if _failures.is_empty():
		print("ENEMY_STATIC_SPRITE_TEST_OK")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)


func _validate_manifest() -> void:
	var manifest := load("res://assets/enemy_static_manifest.tres") as AssetManifest
	_check(manifest != null, "static enemy manifest must load")
	if manifest == null:
		return
	_check(manifest.validate_contract().is_empty(), "static enemy manifest must satisfy AssetManifest schema")
	_check(manifest.entries.size() == STATIC_ENEMIES.size(), "static enemy manifest must expose exactly eight entries")


func _validate_asset_contract() -> void:
	for enemy_id: StringName in STATIC_ENEMIES:
		var asset_id := EnemyAnimator.static_sprite_id(enemy_id)
		_check(asset_id == StringName("enemy_static_%s" % enemy_id), "%s static asset id drifted" % enemy_id)
		_check(EnemyAnimator.uses_static_sprite(enemy_id), "%s must use static sprite routing" % enemy_id)
		_check(not EnemyAnimator.uses_directional_animation(enemy_id), "%s must not use frame animation" % enemy_id)
		var metadata := Art.metadata(asset_id)
		_check(not metadata.is_empty(), "%s metadata must load" % asset_id)
		if metadata.is_empty():
			continue
		_check(int(metadata.get("frames", 0)) == 1, "%s must have exactly one frame" % asset_id)
		_check(not bool(metadata.get("placeholder", true)), "%s must be production art" % asset_id)
		_check(Art.size(asset_id) == Vector2i(640, 640), "%s source canvas must be 640x640" % asset_id)
		var pattern := String(metadata.get("pattern", ""))
		_check(pattern == "res://assets/sprites/enemies/static/%s.png" % enemy_id, "%s must resolve from the core static directory" % asset_id)
		_check(FileAccess.file_exists(pattern), "%s source PNG must be core-resident" % asset_id)
		var import_text := FileAccess.get_file_as_string(pattern + ".import")
		_check(import_text.contains("compress/mode=0"), "%s must preserve lossless imported storage" % asset_id)
		_check(import_text.contains("mipmaps/generate=true"), "%s must generate mipmaps for tile-scale sampling" % asset_id)
		var texture := Art.texture(asset_id, 0)
		_check(texture != null, "%s texture must load" % asset_id)
		if texture != null:
			_check(texture.get_width() == 640 and texture.get_height() == 640, "%s imported texture must preserve 640px canvas" % asset_id)


func _validate_projection_and_motion() -> void:
	var stage := load("res://data/stages/s16.tres") as StageDef
	var config := load("res://data/config/game.tres") as GameConfig
	var enemy_defs := _load_catalog("res://data/enemies")
	var operator_defs := _load_catalog("res://data/operators")
	var model := BattleModel.create(stage, [], 9217, config, enemy_defs, operator_defs)
	_check(model != null, "static enemy projection fixture must create")
	if model == null:
		return
	var original_reduced := bool(ProjectSettings.get_setting("accessibility/reduced_motion", false))
	ProjectSettings.set_setting("accessibility/reduced_motion", false)
	for index: int in STATIC_ENEMIES.size():
		var enemy_id := STATIC_ENEMIES[index]
		model._spawn({"enemy_id": enemy_id, "path_idx": index % stage.paths.size()})
		var enemy := model.enemies[-1] as EnemyState
		var snapshot_before := model.snapshot().duplicate(true)
		var body := EnemyAnimator.make_body(enemy, model, enemy_defs)
		_check(body.get_meta(&"enemy_static", false), "%s body must declare static routing" % enemy_id)
		_check(not body.get_meta(&"enemy_texture_missing", true), "%s must never expose fallback state" % enemy_id)
		_check(body.color.a == 0.0, "%s body fallback color must be transparent" % enemy_id)
		_check(body.size == Vector2.ONE * EnemyAnimator.static_body_px(enemy_id, enemy.aerial), "%s body footprint must match profile" % enemy_id)
		var sprite := body.get_node_or_null("Sprite") as TextureRect
		_check(sprite != null and sprite.texture != null, "%s body must contain its static texture" % enemy_id)
		_check(body.get_node_or_null("BlendSprite") == null, "%s must not allocate animation blend frames" % enemy_id)
		if sprite != null:
			_check(sprite.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED, "%s must preserve source aspect ratio" % enemy_id)
			EnemyAnimator.refresh(enemy, model, body, 0.25, {}, {}, enemy_defs)
			var first_position := sprite.position
			EnemyAnimator.refresh(enemy, model, body, 0.55, {}, {}, enemy_defs)
			_check(sprite.position != first_position, "%s must receive procedural locomotion" % enemy_id)
			_check(model.snapshot() == snapshot_before, "%s presentation must not mutate authoritative state" % enemy_id)
		body.free()
	ProjectSettings.set_setting("accessibility/reduced_motion", true)
	var reduced := EnemyAnimator.static_motion_state(&"interceptor", 4, 0.37, false, 0.0, false, true, true)
	_check(is_zero_approx(float(reduced[&"rotation"])), "Reduced Motion must remove static enemy rotation")
	_check(is_zero_approx((reduced[&"offset"] as Vector2).x), "Reduced Motion must remove static enemy lateral drift")
	_check((reduced[&"scale"] as Vector2).is_equal_approx(Vector2.ONE), "Reduced Motion must remove static enemy squash")
	var attack := EnemyAnimator.static_motion_state(&"breacher", 3, 0.5, true, 0.82, true, false, false)
	_check(float(attack[&"telegraph"]) > 0.4, "static attack profile must expose a readable telegraph phase")
	ProjectSettings.set_setting("accessibility/reduced_motion", original_reduced)


func _validate_combat_effects() -> void:
	var stage := load("res://data/stages/s16.tres") as StageDef
	var config := load("res://data/config/game.tres") as GameConfig
	var enemy_defs := _load_catalog("res://data/enemies")
	var operator_defs := _load_catalog("res://data/operators")
	var model := BattleModel.create(stage, [], 9531, config, enemy_defs, operator_defs)
	_check(model != null, "enemy effect fixture must create")
	if model == null:
		return
	var seen_modes: Dictionary = {}
	var seen_styles: Dictionary = {}
	for index: int in STATIC_ENEMIES.size():
		var enemy_id := STATIC_ENEMIES[index]
		var profile := EnemyAnimator.static_effect_profile(enemy_id)
		_check(not profile.is_empty(), "%s must define a combat effect profile" % enemy_id)
		_check(float(profile.get(&"flash_seconds", 0.0)) >= 0.08, "%s hit flash is too brief" % enemy_id)
		_check(float(profile.get(&"dissolve_seconds", 0.0)) >= 0.28, "%s dissolve is too brief" % enemy_id)
		_check(int(profile.get(&"particle_count", 0)) >= 8, "%s death burst is under-authored" % enemy_id)
		seen_modes[profile.get(&"dissolve_mode", -1.0)] = true
		seen_styles[profile.get(&"particle_style", &"")] = true
		model._spawn({"enemy_id": enemy_id, "path_idx": index % stage.paths.size()})
		var enemy := model.enemies[-1] as EnemyState
		var snapshot_before := model.snapshot().duplicate(true)
		var body := EnemyAnimator.make_body(enemy, model, enemy_defs)
		var sprite := body.get_node_or_null("Sprite") as TextureRect
		var total := EnemyAnimator.damage_flash_frames_for(enemy_id, 6)
		EnemyAnimator.apply_damage_flash(body, total, total, Color.WHITE, Color.RED, enemy_id)
		var material := sprite.material as ShaderMaterial if sprite != null else null
		_check(material != null, "%s must expose its combat shader" % enemy_id)
		if material != null:
			_check(float(material.get_shader_parameter("flash_strength")) > 0.9, "%s hit flash did not activate" % enemy_id)
		_check(EnemyAnimator.begin_death_effect(body, enemy_id, enemy.id, false), "%s death effect did not start" % enemy_id)
		var particles := body.get_node_or_null("DeathParticles") as EnemyDeathParticles
		_check(particles != null, "%s death particles are missing" % enemy_id)
		if particles != null:
			_check(particles.rendered_particle_count() == int(profile[&"particle_count"]), "%s particle count drifted" % enemy_id)
		var duration := EnemyAnimator.static_effect_duration(enemy_id)
		_check(not EnemyAnimator.advance_death_effect(body, duration * 0.5), "%s death effect ended too early" % enemy_id)
		_check(EnemyAnimator.death_effect_progress(body) > 0.4, "%s dissolve did not advance" % enemy_id)
		_check(EnemyAnimator.advance_death_effect(body, duration), "%s death effect did not complete" % enemy_id)
		body.free()
		_check(model.snapshot() == snapshot_before, "%s combat effects mutated authoritative battle state" % enemy_id)
	_check(seen_modes.size() == STATIC_ENEMIES.size(), "each static enemy must have a unique dissolve mode")
	_check(seen_styles.size() == STATIC_ENEMIES.size(), "each static enemy must have a unique particle signature")
	model._spawn({"enemy_id": &"mini_boss", "path_idx": 0})
	var reduced_enemy := model.enemies[-1] as EnemyState
	var reduced_body := EnemyAnimator.make_body(reduced_enemy, model, enemy_defs)
	_check(EnemyAnimator.begin_death_effect(reduced_body, &"mini_boss", reduced_enemy.id, true), "Reduced Motion death effect did not start")
	var reduced_particles := reduced_body.get_node_or_null("DeathParticles") as EnemyDeathParticles
	_check(reduced_particles != null and reduced_particles.rendered_particle_count() <= 8, "Reduced Motion must cap moving death particles")
	reduced_body.free()


func _validate_grunt_exception() -> void:
	_check(EnemyAnimator.uses_grunt(&"grunt"), "Grunt must remain the animated exception")
	_check(EnemyAnimator.uses_directional_animation(&"grunt"), "Grunt must retain directional animation")
	_check(not EnemyAnimator.uses_static_sprite(&"grunt"), "Grunt must not use static sprite routing")
	var grunt_id := EnemyAnimator.animation_id(&"walk", &"se")
	_check(Art.frame_count(grunt_id) > 1, "Grunt must remain frame-animated")
	for enemy_id: StringName in STATIC_ENEMIES:
		_check(Art.frame_count(EnemyAnimator.static_sprite_id(enemy_id)) == 1, "%s must remain single-frame" % enemy_id)


func _load_catalog(path: String) -> Dictionary:
	var result: Dictionary = {}
	for filename: String in DirAccess.get_files_at(path):
		var resource_name := filename.trim_suffix(".remap")
		if not resource_name.ends_with(".tres"):
			continue
		var resource := load("%s/%s" % [path, resource_name])
		if resource != null and "id" in resource:
			result[resource.id] = resource
	return result


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
