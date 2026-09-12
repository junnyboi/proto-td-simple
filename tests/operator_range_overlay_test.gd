extends SceneTree

const OverlayScript := preload("res://scripts/view/operator_range_overlay.gd")

var _failures: Array[String] = []


class RangeBattleView:
	extends Node2D

	const CELL_SIZE := 64.0
	var map_origin := Vector2(40.0, 24.0)
	var map_scale := 1.0

	func cell_at(screen_position: Vector2) -> Vector2i:
		var local := (screen_position - map_origin) / map_scale
		return Vector2i(floori(local.x / CELL_SIZE), floori(local.y / CELL_SIZE))

	func cell_center(cell: Vector2i) -> Vector2:
		return map_origin + (Vector2(cell) + Vector2.ONE * 0.5) * CELL_SIZE * map_scale

	func map_screen_rect() -> Rect2:
		return Rect2(map_origin, Vector2(960.0, 640.0))

	func grid_scale() -> float:
		return map_scale

	func deploy_drag_started() -> void:
		pass

	func deploy_drag_ended() -> void:
		pass

	func operator_selection_changed(_selected: bool) -> void:
		pass

	func consume_map_primary_click_suppression() -> bool:
		return false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var operator_defs := _load_definitions("res://data/operators", "OperatorDef")
	var model := _make_model(operator_defs)
	_check(model != null, "range-overlay fixture model failed")
	if model == null:
		_finish()
		return
	var recruit_cell := _first_valid_deploy_cell(model, &"recruit")
	var sniper_cell := _first_valid_deploy_cell(model, &"sniper_1")
	_check(recruit_cell.x >= 0, "range-overlay fixture has no recruit cell")
	_check(sniper_cell.x >= 0, "range-overlay fixture has no sniper cell")
	if recruit_cell.x < 0 or sniper_cell.x < 0:
		_finish()
		return
	_check(
		model.apply_action([&"deploy", &"recruit", recruit_cell, int(UnitState.Facing.LEFT)]),
		"range-overlay fixture could not deploy recruit",
	)
	_check(
		model.apply_action([&"deploy", &"sniper_1", sniper_cell, int(UnitState.Facing.LEFT)]),
		"range-overlay fixture could not deploy sniper",
	)
	var recruit := model.alive_unit_at(recruit_cell)
	var sniper := model.alive_unit_at(sniper_cell)
	_check(recruit != null and sniper != null, "deployed range fixture units are missing")
	if recruit == null or sniper == null:
		_finish()
		return

	_verify_actual_range_shape(model, recruit, sniper)
	await _verify_overlay_priority_and_geometry(model, recruit, sniper)
	await _verify_deploy_bar_picking_and_lifecycle(model, operator_defs, recruit, sniper)
	_finish()


func _verify_actual_range_shape(model: BattleModel, recruit: UnitState, sniper: UnitState) -> void:
	var recruit_cells := OverlayScript.coverage_cells(recruit, model.stage)
	_check(recruit_cells == [recruit.cell], "recruit range UI must contain only its actual origin cell")
	var expected: Dictionary = Targeting.omni_range_cells(sniper.cell, sniper.range_offsets)
	var actual := OverlayScript.coverage_cells(sniper, model.stage)
	var actual_set: Dictionary = {}
	for cell: Vector2i in actual:
		actual_set[cell] = true
	for cell: Variant in expected.keys():
		if model.stage.tile_at(cell as Vector2i) != StageDef.Tile.VOID:
			_check(actual_set.has(cell), "sniper overlay omitted authoritative covered cell %s" % cell)
	for cell: Vector2i in actual:
		_check(expected.has(cell), "sniper overlay added non-authoritative cell %s" % cell)
		_check(model.stage.tile_at(cell) != StageDef.Tile.VOID, "overlay painted VOID cell %s" % cell)


func _verify_overlay_priority_and_geometry(
	model: BattleModel,
	recruit: UnitState,
	sniper: UnitState,
) -> void:
	var view := RangeBattleView.new()
	view.name = "RangeFixtureView"
	var grid := Node2D.new()
	grid.name = "GridRoot"
	grid.position = view.map_origin
	grid.scale = Vector2.ONE * view.map_scale
	view.add_child(grid)
	root.add_child(view)
	var overlay := OverlayScript.new()
	_check(overlay.setup(model, view), "overlay did not attach to the battle GridRoot")
	await process_frame
	_check(overlay.get_parent() == grid, "overlay is not world-parented under GridRoot")
	_check(overlay.z_index == 1, "overlay must remain below actor depth layers")
	overlay.set_selected_unit_id(sniper.id)
	_check(overlay.active_unit_id() == sniper.id, "selected operator did not paint its range")
	var selected_cells := overlay.painted_cells()
	overlay.set_hovered_unit_id(recruit.id)
	_check(overlay.active_unit_id() == recruit.id, "hovered operator did not temporarily override selection")
	_check(overlay.painted_cells() == [recruit.cell], "hovered recruit did not show truthful one-cell coverage")
	overlay.set_hovered_unit_id(-1)
	_check(overlay.active_unit_id() == sniper.id, "leaving hover did not restore selected operator range")
	_check(overlay.painted_cells() == selected_cells, "selected coverage changed after hover restoration")
	var original_offsets := sniper.range_offsets.duplicate()
	sniper.range_offsets.append(Vector2i(4, 0))
	overlay.refresh()
	_check(overlay.painted_cells() == OverlayScript.coverage_cells(sniper, model.stage), "changed authoritative offsets did not refresh")
	sniper.range_offsets = original_offsets
	overlay.refresh()
	var elevated := Vector2i(2, 2)
	var expected_center := IsoProjection.face_center(elevated, true)
	_check(
		overlay.local_center_for_cell(elevated).is_equal_approx(expected_center),
		"overlay did not apply elevated-cell lift exactly once",
	)
	grid.position += Vector2(91.0, -37.0)
	grid.scale = Vector2.ONE * 1.75
	_check(
		overlay.get_global_transform_with_canvas().origin.is_equal_approx(grid.get_global_transform_with_canvas().origin),
		"world-parented overlay did not inherit map pan and zoom",
	)
	overlay.clear()
	_check(overlay.painted_cells().is_empty(), "overlay clear left stale painted cells")
	overlay.queue_free()
	view.queue_free()
	await process_frame


func _verify_deploy_bar_picking_and_lifecycle(
	model: BattleModel,
	operator_defs: Dictionary,
	recruit: UnitState,
	sniper: UnitState,
) -> void:
	var view := RangeBattleView.new()
	view.name = "DeployBarRangeFixtureView"
	var grid := Node2D.new()
	grid.name = "GridRoot"
	grid.position = view.map_origin
	view.add_child(grid)
	root.add_child(view)
	var recruit_node := Node2D.new()
	recruit_node.position = view.cell_center(recruit.cell) - view.map_origin
	var recruit_body := ColorRect.new()
	recruit_body.name = "Body"
	recruit_body.position = Vector2(-24.0, -76.0)
	recruit_body.size = Vector2(48.0, 72.0)
	recruit_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	recruit_node.add_child(recruit_body)
	grid.add_child(recruit_node)
	var bar := (load("res://scripts/ui/deploy_bar.gd") as GDScript).new() as Control
	root.add_child(bar)
	bar.setup(model, view, operator_defs)
	await process_frame
	var sprite_body_point := recruit_body.get_global_rect().get_center()
	var picked := bar.call("_unit_at_screen_position", sprite_body_point) as UnitState
	_check(picked != null and picked.id == recruit.id, "visible operator sprite body did not pick its operator")
	var mask := Image.create(10, 10, false, Image.FORMAT_RGBA8)
	mask.fill(Color.TRANSPARENT)
	mask.fill_rect(Rect2i(3, 3, 4, 4), Color.WHITE)
	var sprite := TextureRect.new()
	sprite.name = "Sprite"
	sprite.texture = ImageTexture.create_from_image(mask)
	sprite.size = recruit_body.size
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	recruit_body.add_child(sprite)
	_check(bool(bar.call("_operator_body_contains", recruit_body, sprite_body_point)), "opaque sprite pixels must be pickable")
	_check(not bool(bar.call("_operator_body_contains", recruit_body, recruit_body.global_position + Vector2(2, 2))), "transparent sprite padding must not be pickable")
	bar.call("_select_unit", sniper.id)
	_check(bar.call("selected_unit_id") == sniper.id, "selected unit state was not exposed")
	bar.set("_pointer", view.cell_center(recruit.cell))
	bar.call("_refresh_pointer_cursor")
	_check(bar.call("hovered_unit_id") == recruit.id, "operator hover did not reach range overlay")
	_check(bar.call("painted_range_cells") == [recruit.cell], "hover did not take priority over selected range")
	bar.set("_pointer", Vector2(-100.0, -100.0))
	bar.call("_refresh_pointer_cursor")
	_check(bar.call("hovered_unit_id") == -1, "pointer exit left stale range hover")
	_check(
		bar.call("painted_range_cells") == OverlayScript.coverage_cells(sniper, model.stage),
		"range did not restore selected operator after hover exit",
	)
	bar.set_interaction_enabled(false)
	_check(bar.call("painted_range_cells").is_empty(), "interaction lock left a stale range overlay")
	bar.set_interaction_enabled(true)
	bar.call("_select_unit", sniper.id)
	sniper.alive = false
	bar.call("_process", 0.0)
	_check(bar.call("selected_unit_id") == -1, "dead selected operator remained selected")
	_check(bar.call("painted_range_cells").is_empty(), "dead selected operator left stale range tiles")
	bar.queue_free()
	view.queue_free()
	await process_frame


func _make_model(operator_defs: Dictionary) -> BattleModel:
	var stage := (load("res://data/stages/s1.tres") as StageDef).duplicate(true) as StageDef
	stage.waves = [{"enemy_id": &"grunt", "path_idx": 0, "tick": 5000}]
	stage.wave_starts = PackedInt32Array([0])
	stage.leak_limit = 99
	var config := (load("res://data/config/game.tres") as GameConfig).duplicate(true) as GameConfig
	config.dp_start = 99
	config.dp_cap = 99
	return BattleModel.create(stage, [&"recruit", &"sniper_1"], 52731, config, {}, operator_defs)


func _load_definitions(directory: String, expected_class: String) -> Dictionary:
	var definitions: Dictionary = {}
	for filename: String in DirAccess.get_files_at(directory):
		var resource_name := filename.trim_suffix(".remap")
		if not resource_name.ends_with(".tres"):
			continue
		var definition := load("%s/%s" % [directory, resource_name]) as Resource
		if (
			definition != null
			and definition.get_script() != null
			and (definition.get_script() as Script).get_global_name() == StringName(expected_class)
		):
			definitions[definition.get("id")] = definition
	return definitions


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


func _finish() -> void:
	if _failures.is_empty():
		print("OPERATOR_RANGE_OVERLAY_TEST_OK")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)
