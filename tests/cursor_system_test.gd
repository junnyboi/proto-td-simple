extends SceneTree

const EXPECTED_ROLES: Array[StringName] = [
	&"action",
	&"busy",
	&"default",
	&"deploy",
	&"heal",
	&"invalid",
	&"pan",
	&"pan_grab",
	&"select",
	&"text",
	&"trap",
]

var _failures: Array[String] = []


class CursorBattleView:
	extends Node2D

	const CELL_SIZE := 64.0

	func cell_at(screen_position: Vector2) -> Vector2i:
		return Vector2i(
			floori(screen_position.x / CELL_SIZE),
			floori(screen_position.y / CELL_SIZE),
		)

	func cell_center(cell: Vector2i) -> Vector2:
		return (Vector2(cell) + Vector2.ONE * 0.5) * CELL_SIZE

	func map_screen_rect() -> Rect2:
		return Rect2(Vector2.ZERO, Vector2(960, 640))

	func grid_scale() -> float:
		return 1.0

	func deploy_drag_started() -> void:
		pass

	func deploy_drag_ended() -> void:
		pass

	func operator_selection_changed(_selected: bool) -> void:
		pass


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var manager := root.get_node_or_null("CursorManager")
	_check(manager != null, "CursorManager autoload is missing")
	if manager == null:
		_finish()
		return

	_check(manager.call("registered_roles") == EXPECTED_ROLES, "semantic role catalog changed")
	var fingerprints: Dictionary = {}
	var seen_shapes: Dictionary = {}
	for role: StringName in EXPECTED_ROLES:
		var texture := manager.call("texture_for_role", role) as Texture2D
		_check(texture != null, "%s cursor texture is missing" % role)
		if texture == null:
			continue
		_check(texture.get_size() == Vector2(32, 32), "%s cursor is not 32x32" % role)
		var image := texture.get_image()
		_check(image != null and not image.is_empty(), "%s cursor image cannot be read" % role)
		if image == null or image.is_empty():
			continue
		var visible_pixels := _visible_pixel_count(image)
		_check(visible_pixels >= 18, "%s cursor has too little visible artwork" % role)
		_check(visible_pixels < 900, "%s cursor lost its transparent gutter" % role)
		var fingerprint := image.get_data().hex_encode().sha256_text()
		_check(not fingerprints.has(fingerprint), "%s cursor duplicates another role" % role)
		fingerprints[fingerprint] = role
		var hotspot := manager.call("hotspot_for_role", role) as Vector2
		_check(Rect2(Vector2.ZERO, texture.get_size()).has_point(hotspot), "%s hotspot is outside its texture" % role)
		var shape := int(manager.call("shape_for_role", role))
		_check(not seen_shapes.has(shape), "%s reuses a native cursor channel" % role)
		seen_shapes[shape] = role

	_verify_control_semantics(manager)
	_verify_claim_priority(manager)
	_verify_window_boundary_behavior(manager)
	await _verify_battle_cursor_semantics(manager)
	await _capture_catalog_if_requested(manager)
	_finish()


func _verify_control_semantics(manager: Node) -> void:
	var button := Button.new()
	_check(
		int(manager.call("shape_for_control", button)) == Control.CURSOR_POINTING_HAND,
		"enabled button does not use the action cursor",
	)
	button.disabled = true
	_check(
		int(manager.call("shape_for_control", button)) == Control.CURSOR_FORBIDDEN,
		"disabled button does not use the invalid cursor",
	)
	_check(bool(manager.call("set_control_role", button, &"busy")), "explicit busy role was rejected")
	_check(
		int(manager.call("shape_for_control", button)) == Control.CURSOR_BUSY,
		"explicit Control role did not override automatic classification",
	)
	manager.call("clear_control_role", button)
	var edit := LineEdit.new()
	_check(
		int(manager.call("shape_for_control", edit)) == Control.CURSOR_IBEAM,
		"editable text does not use the text cursor",
	)
	var slider := HSlider.new()
	_check(
		int(manager.call("shape_for_control", slider)) == Control.CURSOR_POINTING_HAND,
		"slider does not use the action cursor",
	)
	button.free()
	edit.free()
	slider.free()


func _verify_claim_priority(manager: Node) -> void:
	var map_owner := Node.new()
	var action_owner := Node.new()
	_check(bool(manager.call("claim", map_owner, &"pan", 10)), "map cursor claim failed")
	_check(StringName(manager.call("active_role")) == &"pan", "map claim did not become active")
	_check(bool(manager.call("claim", action_owner, &"deploy", 100)), "deploy cursor claim failed")
	_check(StringName(manager.call("active_role")) == &"deploy", "high-priority deploy claim did not win")
	manager.call("claim", map_owner, &"select", 40)
	_check(StringName(manager.call("active_role")) == &"deploy", "lower-priority selection displaced deploy")
	manager.call("release_claim", action_owner)
	_check(StringName(manager.call("active_role")) == &"select", "selection did not resume after deploy")
	map_owner.free()
	manager.call("_process", 0.0)
	_check(StringName(manager.call("active_role")) == &"default", "freed claim owner stranded the cursor")
	_check(not bool(manager.call("claim", action_owner, &"unknown", 100)), "unknown cursor role was accepted")
	action_owner.free()


func _verify_window_boundary_behavior(manager: Node) -> void:
	var owner := Node.new()
	_check(bool(manager.get("_custom_cursors_installed")), "custom cursors were not installed at startup")
	manager.call("claim", owner, &"pan", 10)
	manager.notification(Node.NOTIFICATION_WM_MOUSE_EXIT)
	_check(
		not bool(manager.get("_custom_cursors_installed")),
		"custom cursors remained installed after the pointer left the game window",
	)
	_check(
		StringName(manager.call("active_role")) == &"pan",
		"leaving the game window discarded the active cursor role",
	)
	manager.notification(Node.NOTIFICATION_WM_MOUSE_ENTER)
	_check(
		bool(manager.get("_custom_cursors_installed")),
		"custom cursors were not restored after the pointer re-entered the game window",
	)
	manager.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	_check(
		not bool(manager.get("_custom_cursors_installed")),
		"custom cursors remained installed after the game window lost focus",
	)
	manager.notification(Node.NOTIFICATION_WM_MOUSE_EXIT)
	manager.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN)
	_check(
		not bool(manager.get("_custom_cursors_installed")),
		"custom cursors were restored while the pointer was outside the game window",
	)
	manager.notification(Node.NOTIFICATION_WM_MOUSE_ENTER)
	_check(
		bool(manager.get("_custom_cursors_installed")),
		"custom cursors were not restored after focus and pointer returned",
	)
	manager.call("release_claim", owner)
	owner.free()


func _verify_battle_cursor_semantics(manager: Node) -> void:
	var stage := (load("res://data/stages/s1.tres") as StageDef).duplicate(true) as StageDef
	stage.waves = [{"enemy_id": &"grunt", "path_idx": 0, "tick": 5000}]
	stage.wave_starts = PackedInt32Array([0])
	stage.leak_limit = 99
	var config := (load("res://data/config/game.tres") as GameConfig).duplicate(true) as GameConfig
	config.dp_start = 99
	config.dp_cap = 99
	var operator_defs := _load_definitions("res://data/operators", "OperatorDef")
	var trap_defs := _load_definitions("res://data/traps", "TrapDef")
	var model := BattleModel.create(
		stage,
		[&"recruit", &"guard_1"],
		9127,
		config,
		{},
		operator_defs,
		trap_defs,
	)
	_check(model != null, "cursor battle fixture could not create a model")
	if model == null:
		return
	var view := CursorBattleView.new()
	root.add_child(view)
	var deploy_bar_script := load("res://scripts/ui/deploy_bar.gd") as GDScript
	_check(deploy_bar_script != null, "DeployBar cursor integration script did not load")
	if deploy_bar_script == null:
		root.remove_child(view)
		view.free()
		return
	var bar := deploy_bar_script.new() as Control
	root.add_child(bar)
	bar.setup(model, view, operator_defs, trap_defs)
	await process_frame

	var first_deployment := StringName(bar.call("first_deployment_id"))
	var first_cell := _first_valid_deploy_cell(model, first_deployment)
	_check(first_cell.x >= 0, "cursor fixture has no valid operator cell")
	if first_cell.x >= 0:
		bar.call("_start_placement", first_deployment)
		bar.set("_pointer", view.cell_center(first_cell))
		bar.call("_update_placement_hover")
		_check(StringName(manager.call("active_role")) == &"deploy", "valid operator cell did not claim deploy cursor")
		bar.set("_pointer", Vector2(-64, -64))
		bar.call("_update_placement_hover")
		_check(StringName(manager.call("active_role")) == &"invalid", "invalid operator cell did not claim invalid cursor")
		bar.call("_cancel_placement")

	var trap_cell := _first_valid_trap_cell(model, &"spike_plate")
	_check(trap_cell.x >= 0, "cursor fixture has no valid trap cell")
	if trap_cell.x >= 0:
		bar.call("_start_trap_placement", &"spike_plate")
		bar.set("_pointer", view.cell_center(trap_cell))
		bar.call("_update_placement_hover")
		_check(StringName(manager.call("active_role")) == &"trap", "valid trap cell did not claim trap cursor")
		bar.call("_cancel_placement")

	model.dp = model.config.dp_cap
	if first_cell.x >= 0:
		_check(
			model.apply_action([&"deploy", first_deployment, first_cell, int(UnitState.Facing.RIGHT)]),
			"cursor fixture could not deploy its first operator",
		)
		var healer := model.alive_unit_at(first_cell)
		bar.set("_pointer", view.cell_center(first_cell))
		bar.call("_refresh_pointer_cursor")
		_check(StringName(manager.call("active_role")) == &"select", "allied operator hover did not claim select cursor")
		var second_deployment := _other_deployment_id(model, first_deployment)
		var second_cell := _first_valid_deploy_cell(model, second_deployment)
		model.dp = model.config.dp_cap
		_check(
			second_cell.x >= 0
			and model.apply_action([&"deploy", second_deployment, second_cell, int(UnitState.Facing.RIGHT)]),
			"cursor fixture could not deploy a mend target",
		)
		var target := model.alive_unit_at(second_cell) if second_cell.x >= 0 else null
		if healer != null and target != null:
			healer.skill_id = &"mend"
			healer.sp_cost = 10
			healer.sp = 10
			healer.skill_effect = SkillDef.Effect.HEAL_TARGET
			healer.skill_params = {"amount": 20, "range_cells": 99}
			target.hp = maxi(1, target.hp_max - 20)
			bar.call("_begin_heal_targeting", healer)
			bar.set("_pointer", view.cell_center(second_cell))
			bar.call("_update_heal_hover")
			_check(StringName(manager.call("active_role")) == &"heal", "valid mend target did not claim heal cursor")
			bar.call("_cancel_heal_targeting")

	root.remove_child(bar)
	bar.free()
	root.remove_child(view)
	view.free()
	var sfx := root.get_node_or_null("Sfx")
	if sfx != null and sfx.has_method("stop_all"):
		sfx.call("stop_all")
	_check(StringName(manager.call("active_role")) == &"default", "battle cursor claim survived cleanup")


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


func _first_valid_deploy_cell(model: BattleModel, deployment_id: StringName) -> Vector2i:
	if deployment_id.is_empty():
		return Vector2i(-1, -1)
	for y: int in model.stage.grid_size().y:
		for x: int in model.stage.grid_size().x:
			var cell := Vector2i(x, y)
			if model.can_deploy_at(deployment_id, cell):
				return cell
	return Vector2i(-1, -1)


func _first_valid_trap_cell(model: BattleModel, trap_id: StringName) -> Vector2i:
	for y: int in model.stage.grid_size().y:
		for x: int in model.stage.grid_size().x:
			var cell := Vector2i(x, y)
			if model.can_place_trap_at(trap_id, cell):
				return cell
	return Vector2i(-1, -1)


func _other_deployment_id(model: BattleModel, excluded: StringName) -> StringName:
	var deployment_ids: Array[StringName] = (
		model.battle_squad if not model.battle_squad.is_empty() else model.squad
	)
	for deployment_id: StringName in deployment_ids:
		if deployment_id != excluded:
			return deployment_id
	return &""


func _capture_catalog_if_requested(manager: Node) -> void:
	var output_path := OS.get_environment("PROTO_TD_CURSOR_CAPTURE")
	if output_path.is_empty():
		return
	DisplayServer.window_set_size(Vector2i(720, 540))
	root.size = Vector2i(720, 540)
	var tweak_launcher := root.find_child("TweakControlsButton", true, false) as Control
	var tweak_launcher_was_visible := tweak_launcher != null and tweak_launcher.visible
	if tweak_launcher != null:
		tweak_launcher.visible = false
	var background := ColorRect.new()
	background.color = Color("08101c")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(background)
	var title := Label.new()
	title.text = "LUNARIS COMMAND GLYPHS"
	title.position = Vector2(32, 24)
	title.add_theme_font_size_override(&"font_size", 26)
	background.add_child(title)
	for index: int in EXPECTED_ROLES.size():
		var column := index % 4
		var row_index := index / 4
		var cell_position := Vector2(32 + column * 168, 82 + row_index * 142)
		var panel := ColorRect.new()
		panel.color = Color("111f31")
		panel.position = cell_position
		panel.size = Vector2(144, 118)
		background.add_child(panel)
		var icon := TextureRect.new()
		icon.texture = manager.call("texture_for_role", EXPECTED_ROLES[index]) as Texture2D
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.position = Vector2(40, 8)
		icon.size = Vector2(64, 64)
		panel.add_child(icon)
		var label := Label.new()
		label.text = String(EXPECTED_ROLES[index]).to_upper().replace("_", " ")
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.position = Vector2(6, 78)
		label.size = Vector2(132, 32)
		panel.add_child(label)
	for _frame: int in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_viewport().get_texture().get_image()
	var error := image.save_png(output_path)
	_check(error == OK, "cursor visual catalog could not be saved")
	if error == OK:
		print("CURSOR_VISUAL_OK path=%s" % output_path)
	background.queue_free()
	if tweak_launcher != null:
		tweak_launcher.visible = tweak_launcher_was_visible
	await process_frame


func _visible_pixel_count(image: Image) -> int:
	var count := 0
	for y: int in image.get_height():
		for x: int in image.get_width():
			if image.get_pixel(x, y).a > 0.05:
				count += 1
	return count


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("CURSOR_SYSTEM_TEST_OK")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)
