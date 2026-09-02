extends SceneTree

const TargetDecisionProjectionType := preload("res://sim/target_decision_projection.gd")
const UnitStateType := preload("res://sim/unit_state.gd")

var _failures: Array[String] = []


func _init() -> void:
	_test_omnidirectional_range_union()
	_test_default_deployment_and_enemy_driven_facing()
	if _failures.is_empty():
		print("OPERATOR_AUTO_FACING_TEST_OK")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)


func _test_omnidirectional_range_union() -> void:
	var origin := Vector2i(4, 4)
	var offsets: Array[Vector2i] = [Vector2i(1, 0)]
	var cells := Targeting.omni_range_cells(origin, offsets)
	_check(cells.size() == 4, "one-cell range did not rotate into four unique cells")
	for cell: Vector2i in [
		Vector2i(5, 4), Vector2i(4, 5), Vector2i(3, 4), Vector2i(4, 3),
	]:
		_check(cells.has(cell), "omnidirectional range omitted %s" % cell)
	_check(
		Targeting.north_facing_toward(origin, Vector2i(5, 4))
		== Targeting.FACING_NORTHEAST,
		"enemy on the isometric right did not select NE",
	)
	_check(
		Targeting.north_facing_toward(origin, Vector2i(3, 4))
		== Targeting.FACING_NORTHWEST,
		"enemy on the isometric left did not select NW",
	)


func _test_default_deployment_and_enemy_driven_facing() -> void:
	var stage := StageDef.new()
	stage.grid_rows = PackedStringArray([
		"GGGGG",
		"GGGGG",
		"GGEGG",
		"GGGGG",
		"GGGGG",
	])
	var config := GameConfig.new()
	config.dp_start = 99
	config.dp_cap = 99
	var definition := (load("res://data/operators/sniper_1.tres") as OperatorDef).duplicate(true)
	var model := BattleModel.new()
	model.stage = stage
	model.config = config
	model.dp = config.dp_start
	model.squad = [&"sniper_1"]
	model._op_defs = {&"sniper_1": definition}
	model._paths.append([Vector2i(1, 2)] as Array[Vector2i])
	model._paths.append([Vector2i(3, 2)] as Array[Vector2i])

	_check(
		model.apply_action([
			&"deploy", &"sniper_1", Vector2i(2, 2), int(UnitStateType.Facing.RIGHT),
		]),
		"valid deployment was rejected",
	)
	if model.units.is_empty():
		return
	var unit: UnitState = model.units[0]
	unit.atk = 0
	_check(
		unit.facing == UnitStateType.DEFAULT_FACING,
		"deployment did not normalize the historical facing field to NW",
	)

	var enemy := EnemyState.new()
	enemy.id = 0
	enemy.path_idx = 0
	enemy.progress_units = 0
	model.enemies.append(enemy)
	unit.facing = UnitStateType.Facing.RIGHT
	var left_decision := TargetDecisionProjectionType.unit_target_decision(model, unit.id)
	_check(
		int(left_decision["selected_id"]) == enemy.id,
		"operator did not acquire a target behind its legacy facing",
	)
	model._tick_combat()
	_check(
		unit.facing == UnitStateType.Facing.LEFT,
		"operator did not turn NW toward an enemy arriving from the left",
	)

	enemy.path_idx = 1
	var right_decision := TargetDecisionProjectionType.unit_target_decision(model, unit.id)
	_check(
		int(right_decision["selected_id"]) == enemy.id,
		"operator did not retain omnidirectional acquisition after turning",
	)
	model._tick_combat()
	_check(
		unit.facing == UnitStateType.Facing.UP,
		"operator did not turn NE toward an enemy arriving from the right",
	)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
