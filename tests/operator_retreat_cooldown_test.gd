extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_validate_class_cooldown(&"guard_1", 10)
	if _failures.is_empty():
		print("OPERATOR_RETREAT_COOLDOWN_TEST_OK")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)


func _validate_class_cooldown(operator_id: StringName, expected_seconds: int) -> void:
	var model := _make_model(operator_id)
	_check(model != null, "%s cooldown fixture failed" % operator_id)
	if model == null:
		return
	model.dp = model.config.dp_cap
	var cell := _first_valid_deploy_cell(model, operator_id)
	_check(cell.x >= 0, "%s has no valid deployment cell" % operator_id)
	if cell.x < 0:
		return
	_check(
		model.apply_action([&"deploy", operator_id, cell, int(UnitState.Facing.RIGHT)]),
		"%s initial deployment failed" % operator_id,
	)
	var unit := model.alive_unit_at(cell)
	_check(unit != null, "%s deployed unit was not projected" % operator_id)
	if unit == null:
		return
	var hash_before_retreat := model.state_hash()
	_check(model.apply_action([&"retreat", unit.id]), "%s retreat failed" % operator_id)
	_check(model.state_hash() != hash_before_retreat, "%s retreat cooldown is absent from the battle hash" % operator_id)
	var expected_ticks := expected_seconds * model.config.ticks_per_second
	_check(
		model.redeploy_cooldown_ticks_remaining(operator_id) == expected_ticks,
		"%s cooldown expected %d ticks, got %d" % [
			operator_id,
			expected_ticks,
			model.redeploy_cooldown_ticks_remaining(operator_id),
		],
	)
	_check(
		model.redeploy_cooldown_seconds_remaining(operator_id) == expected_seconds,
		"%s cooldown expected %d seconds" % [operator_id, expected_seconds],
	)
	_check(not model.is_deployable(operator_id), "%s redeployed during cooldown" % operator_id)
	var snapshot: Dictionary = model.snapshot()
	var cooldowns := snapshot.get("redeploy_cooldowns", {}) as Dictionary
	_check(cooldowns.has(String(operator_id)), "%s cooldown is absent from battle snapshot" % operator_id)
	var ready_tick := int(model.redeploy_ready_tick_by_id[operator_id])
	model.tick = ready_tick - 1
	_check(not model.is_deployable(operator_id), "%s became deployable one tick early" % operator_id)
	_check(model.redeploy_cooldown_seconds_remaining(operator_id) == 1, "%s final partial second must round up" % operator_id)
	model.tick = ready_tick
	_check(model.redeploy_cooldown_ticks_remaining(operator_id) == 0, "%s cooldown did not expire exactly" % operator_id)
	_check(model.is_deployable(operator_id), "%s did not become deployable at the ready tick" % operator_id)
	model.dp = model.config.dp_cap
	_check(
		model.apply_action([&"deploy", operator_id, cell, int(UnitState.Facing.LEFT)]),
		"%s redeployment failed after cooldown" % operator_id,
	)


func _make_model(operator_id: StringName) -> BattleModel:
	var stage := (load("res://data/stages/s1.tres") as StageDef).duplicate(true) as StageDef
	stage.waves = [{"enemy_id": &"grunt", "path_idx": 0, "tick": 5000}]
	stage.wave_starts = PackedInt32Array([0])
	stage.leak_limit = 99
	var config := (load("res://data/config/game.tres") as GameConfig).duplicate(true) as GameConfig
	config.dp_start = 99
	config.dp_cap = 99
	var operator_defs: Dictionary = {}
	for filename: String in DirAccess.get_files_at("res://data/operators"):
		var resource_name := filename.trim_suffix(".remap")
		if not resource_name.ends_with(".tres"):
			continue
		var definition := load("res://data/operators/%s" % resource_name) as OperatorDef
		if definition != null:
			operator_defs[definition.id] = definition
	return BattleModel.create(stage, [operator_id], 7721, config, {}, operator_defs)


func _first_valid_deploy_cell(model: BattleModel, operator_id: StringName) -> Vector2i:
	for y: int in model.stage.grid_size().y:
		for x: int in model.stage.grid_size().x:
			var cell := Vector2i(x, y)
			if model.can_deploy_at(operator_id, cell):
				return cell
	return Vector2i(-1, -1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
