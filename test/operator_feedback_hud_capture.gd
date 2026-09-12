extends SceneTree
const Tickets := preload("res://sim/battle_ticket_runtime.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var portrait := OS.get_environment("FEEDBACK_PORTRAIT") == "1"
	root.size = Vector2i(768, 1024) if portrait else Vector2i(1280, 720)
	await process_frame
	var game := root.get_node("Game")
	game.call("set_run_seed", 3302)
	assert(bool(game.call("start_campaign", false, true)))
	game.call("start_battle", &"s1", true)
	for frame: int in 20:
		await process_frame
	var battle := game.get("content") as Node2D
	assert(battle != null and bool(battle.get("startup_succeeded")))
	for button: Node in battle.find_children("*", "Button", true, false):
		if (button as Button).text == "Skip tutorial":
			button.emit_signal("pressed")
			break
	for frame: int in 8:
		await process_frame
	battle.set_physics_process(false)
	battle.set_process(false)
	battle.set("ticks_per_frame_scale", 1.0)
	var model: BattleModel = battle.get("model")
	var unit := UnitState.new()
	unit.id = 9000
	unit.hero_id = &"feedback-hero"
	unit.class_id = &"gunner"
	var chosen := Vector2i(-1, -1)
	var closest := INF
	for y: int in model.stage.grid_size().y:
		for x: int in model.stage.grid_size().x:
			var cell := Vector2i(x, y)
			if not model.stage.is_elevated_platform(cell):
				continue
			var point: Vector2 = battle.call("cell_center", cell)
			var distance := point.distance_squared_to(Vector2(root.size) * Vector2(0.5, 0.63))
			if distance < closest:
				chosen = cell
				closest = distance
	assert(chosen.x >= 0)
	unit.cell = chosen
	Tickets.copy_legacy_unit(load("res://data/operators/sniper_1.tres") as OperatorDef, unit)
	model.units.append(unit)
	battle.call("_project_units")
	var navigator: RefCounted = battle.get("_map_nav")
	var unit_node: Node2D = (battle.get("_unit_nodes") as Dictionary)[unit.id]
	var body := unit_node.get_node("Body") as Control
	navigator.call("ensure_local_rect_visible", Rect2(unit_node.position + Vector2(-35, -64), Vector2(70, 90)))
	battle.call("_apply_map_transform")
	var navigation_hint: Node = battle.get("_map_navigation_overlay")
	if navigation_hint != null:
		navigation_hint.call("notify_pan_used")
	# Wave banner is transient and unrelated to range UI; use its normal hidden
	# resting state for the frozen capture rather than freezing it mid-animation.
	var banner := battle.find_child("WaveBanner", true, false) as CanvasItem
	if banner != null:
		banner.visible = false
	var banner_back := battle.find_child("WaveBannerBack", true, false) as CanvasItem
	if banner_back != null:
		banner_back.visible = false
	var bar: Control = battle.get("_deploy_bar")
	bar.set_process(false)
	bar.call("_handle_grid_click", battle.call("cell_center", chosen))
	bar.set("_pointer", Vector2(-100, -100))
	bar.call("_refresh_pointer_cursor")
	assert(not (bar.call("painted_range_cells") as Array).is_empty())
	var prefix := OS.get_environment("FEEDBACK_CAPTURE_PREFIX")
	assert(not prefix.is_empty())
	for frame: int in 8:
		await process_frame
		bar.call("_layout_operator_action_panel")
	assert(root.get_texture().get_image().save_png(prefix + "-selected.png") == OK)
	bar.call("_select_unit", -1)
	bar.set("_pointer", battle.call("cell_center", chosen))
	bar.call("_refresh_pointer_cursor")
	assert(int(bar.call("hovered_unit_id")) == unit.id)
	for frame: int in 4:
		await process_frame
	assert(root.get_texture().get_image().save_png(prefix + "-hover.png") == OK)
	game.set("content", null)
	battle.get_parent().remove_child(battle)
	battle.free()
	game.call("_reset_campaign_runtime")
	print("OPERATOR_FEEDBACK_HUD_CAPTURE_OK")
	quit(0)
