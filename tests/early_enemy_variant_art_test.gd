extends SceneTree

## Compatibility gate for the retired S2–S4 animation-atlas route. Historical
## sources remain in-repository, but production presentation must resolve the new
## core static sprites and must never wait on the legacy enemy-variants pack.

const ENEMIES: Array[StringName] = [&"shieldbearer", &"breacher", &"interceptor"]
var _failures := PackedStringArray()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	Art._reset_manifests_for_test()
	var stage := load("res://data/stages/s4.tres") as StageDef
	var config := load("res://data/config/game.tres") as GameConfig
	var enemy_defs := _load_catalog("res://data/enemies")
	var operator_defs := _load_catalog("res://data/operators")
	var model := BattleModel.create(stage, [], 4104, config, enemy_defs, operator_defs)
	_check(model != null, "static production projection fixture must create")
	if model != null:
		for enemy_id: StringName in ENEMIES:
			model._spawn({"enemy_id": enemy_id, "path_idx": 0})
			var enemy := model.enemies[-1] as EnemyState
			var asset_id := EnemyAnimator.animation_id_for(enemy, model)
			_check(asset_id == EnemyAnimator.static_sprite_id(enemy_id), "%s must use core static routing" % enemy_id)
			_check(not String(asset_id).begins_with("enemy_variant_"), "%s must not select the retired variant atlas" % enemy_id)
			_check(Art.frame_count(asset_id) == 1, "%s must expose exactly one production frame" % enemy_id)
			var body := EnemyAnimator.make_body(enemy, model, enemy_defs)
			var sprite := body.get_node_or_null("Sprite") as TextureRect
			_check(sprite != null and sprite.texture != null, "%s static body must load" % enemy_id)
			_check(body.get_node_or_null("BlendSprite") == null, "%s must not allocate retired blend-frame state" % enemy_id)
			EnemyAnimator.refresh(enemy, model, body, 0.25, {}, {}, enemy_defs)
			_check(sprite != null and sprite.modulate == Color.WHITE, "%s static identity must keep its authored colors" % enemy_id)
			body.free()
	_validate_historical_sources_are_not_core_runtime_dependencies()
	Art._reset_manifests_for_test()
	EnemyAnimator._damage_flash_shader = null
	if _failures.is_empty():
		print("EARLY_ENEMY_VARIANT_ART_OK")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)


func _validate_historical_sources_are_not_core_runtime_dependencies() -> void:
	var preset := FileAccess.get_file_as_string("res://export_presets.cfg")
	for enemy_id: StringName in ENEMIES:
		var static_path := "assets/sprites/enemies/static/%s.png" % enemy_id
		_check(not preset.contains(static_path), "%s must not be excluded from the core Web PCK" % static_path)
		var metadata := Art.metadata(EnemyAnimator.static_sprite_id(enemy_id))
		_check(not bool(metadata.get("placeholder", true)), "%s static replacement must be production art" % enemy_id)
		_check(String(metadata.get("pattern", "")).begins_with("res://assets/sprites/enemies/static/"), "%s must resolve from the core static directory" % enemy_id)


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
