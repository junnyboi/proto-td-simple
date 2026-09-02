extends SceneTree

const HEALTH_BAR_SCRIPT := preload("res://scripts/view/battle_health_bar.gd")
const OCCLUDER_SCRIPT := preload("res://scripts/view/elevated_platform_occluder.gd")
const OPERATOR_HP_COLOR := Color("a7f070")
const ENEMY_HP_COLOR := Color("ef4747")
const EPSILON := 0.001

var _failures := PackedStringArray()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_verify_health_bars()
	_verify_operator_enemy_depth_order()
	_verify_elevated_platform_depths()
	if _failures.is_empty():
		print("BATTLE_HEALTH_AND_DEPTH_TEST_OK")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)


func _verify_health_bars() -> void:
	var operator_body := ColorRect.new()
	operator_body.size = Vector2(80.0, 64.0)
	HEALTH_BAR_SCRIPT.add_to(operator_body, operator_body.size.x)
	_verify_bar(operator_body, 40.0, OPERATOR_HP_COLOR, "operator")

	var enemy_body := ColorRect.new()
	enemy_body.size = Vector2(120.0, 96.0)
	HEALTH_BAR_SCRIPT.add_to(enemy_body, enemy_body.size.x, true)
	_verify_bar(enemy_body, 60.0, ENEMY_HP_COLOR, "enemy")
	HEALTH_BAR_SCRIPT.update(enemy_body, enemy_body.size.x, 25, 100)
	var enemy_fill := enemy_body.get_node("HpBarBg/HpBarFill") as ColorRect
	_check(_close(enemy_fill.size.x, 15.0), "enemy health ratio did not use reduced width")

	# Animated bodies can change dimensions after construction. The update path
	# must preserve the centered 50% geometry for those replacements too.
	enemy_body.size.x = 100.0
	HEALTH_BAR_SCRIPT.update(enemy_body, enemy_body.size.x, 25, 100)
	var enemy_bg := enemy_body.get_node("HpBarBg") as ColorRect
	_check(_close(enemy_bg.size.x, 50.0), "resized enemy health bar is not half width")
	_check(_close(enemy_bg.position.x, 25.0), "resized enemy health bar is not centered")
	_check(_close(enemy_fill.size.x, 12.5), "resized enemy fill ratio is incorrect")
	operator_body.free()
	enemy_body.free()


func _verify_bar(body: ColorRect, expected_width: float, color: Color, label: String) -> void:
	var bg := body.get_node_or_null("HpBarBg") as ColorRect
	var fill := body.get_node_or_null("HpBarBg/HpBarFill") as ColorRect
	_check(bg != null and fill != null, "%s health bar is missing" % label)
	if bg == null or fill == null:
		return
	_check(_close(bg.size.x, expected_width), "%s health bar is not half width" % label)
	_check(_close(bg.size.y, 2.5), "%s health bar is not half height" % label)
	_check(
		_close(bg.position.x, (body.size.x - expected_width) * 0.5),
		"%s health bar is not centered" % label,
	)
	_check(fill.color.is_equal_approx(color), "%s health color is incorrect" % label)
	_check(_close(fill.size.x, expected_width), "%s full-health fill width is incorrect" % label)
	_check(_close(fill.size.y, 2.5), "%s fill is not half height" % label)


func _verify_operator_enemy_depth_order() -> void:
	for cell: Vector2i in [Vector2i.ZERO, Vector2i(3, 2), Vector2i(9, 4)]:
		var center := Vector2(cell) + Vector2.ONE * 0.5
		var enemy_z := IsoProjection.entity_z(center)
		var operator_z := IsoProjection.operator_z(center)
		_check(operator_z > enemy_z, "operator does not render above same-depth enemy at %s" % cell)
		_check(
			operator_z < IsoProjection.tile_z(cell + Vector2i.RIGHT),
			"operator depth at %s spills into the next terrain layer" % cell,
		)


func _verify_elevated_platform_depths() -> void:
	for stage_number: int in range(1, 9):
		var stage_id := "s%d" % stage_number
		var stage := load("res://data/stages/%s.tres" % stage_id) as StageDef
		_check(stage != null, "%s failed to load" % stage_id)
		if stage == null:
			continue
		var grid := Node2D.new()
		root.add_child(grid)
		_check(IsoGridBuilder.build_stage(grid, stage), "%s grid failed to build" % stage_id)
		var terrain := grid.get_node_or_null("ProtoIsometricTerrain") as Node2D
		_check(terrain != null, "%s terrain is missing" % stage_id)
		if terrain != null:
			_verify_stage_occluders(stage_id, stage, terrain)
		root.remove_child(grid)
		grid.free()


func _verify_stage_occluders(stage_id: String, stage: StageDef, terrain: Node2D) -> void:
	var platform_count := 0
	var size := stage.grid_size()
	for y: int in size.y:
		for x: int in size.x:
			var cell := Vector2i(x, y)
			if not stage.is_elevated_platform(cell):
				continue
			platform_count += 1
			var node_name := "ElevatedPlatformOccluder_%d_%d" % [x, y]
			var occluder := terrain.get_node_or_null(node_name) as Node2D
			_check(occluder != null, "%s is missing %s" % [stage_id, node_name])
			if occluder == null:
				continue
			_check(occluder.get_script() == OCCLUDER_SCRIPT, "%s uses wrong occluder script" % node_name)
			var platform_z := IsoProjection.tile_z(cell)
			_check(occluder.z_index == platform_z, "%s has incorrect platform depth" % node_name)
			for offset: Vector2i in [Vector2i(-1, 0), Vector2i(0, -1)]:
				var behind := Vector2(cell + offset) + Vector2.ONE * 0.5
				_check(
					IsoProjection.entity_z(behind) < platform_z,
					"%s does not occlude an enemy behind it" % node_name,
				)
				_check(
					IsoProjection.operator_z(behind) < platform_z,
					"%s does not occlude an operator behind it" % node_name,
				)
			var on_platform := Vector2(cell) + Vector2.ONE * 0.5
			_check(
				IsoProjection.entity_z(on_platform) > platform_z,
				"%s covers an enemy standing on it" % node_name,
			)
			_check(
				IsoProjection.operator_z(on_platform) > platform_z,
				"%s covers an operator standing on it" % node_name,
			)
	_check(platform_count > 0, "%s has no elevated platform fixture" % stage_id)


func _close(actual: float, expected: float) -> bool:
	return absf(actual - expected) <= EPSILON


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
