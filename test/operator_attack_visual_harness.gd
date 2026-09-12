extends "res://test/operator_v3_visual_harness.gd"

func _capture_state(state: String, last_attack_tick: int, model_tick: int) -> void:
	_battle.set_physics_process(false)
	_battle.set("ticks_per_frame_scale", 1.0)
	var model: BattleModel = _battle.get("model")
	model.tick = model_tick
	var fx: Node2D = _battle.get("_operator_attack_feedback")
	fx.set_process(false)
	fx.call("clear_transients")
	fx.set("_seen", {})
	for unit: UnitState in model.units:
		unit.last_attack_tick = last_attack_tick
		var axes := [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
		unit.last_attack_cell = unit.cell + axes[unit.facing]
	_battle.call("_project_units")
	if state == "attack":
		# Submit one fresh event, then restore the pose clock for the existing
		# fixture assertions. The actual runtime never changes these model fields.
		for unit: UnitState in model.units:
			unit.last_attack_tick = model_tick
		fx.call("sync_attacks", model)
		for unit: UnitState in model.units:
			unit.last_attack_tick = last_attack_tick
		var phase := 0.12 if model_tick == 7 else (0.42 if model_tick == 16 else 0.78)
		var bursts: Array = fx.get("_bursts")
		for burst: Dictionary in bursts:
			burst["age"] = float(burst["life"]) * phase
		if bursts.size() != (4 if root.size.y > root.size.x else 8):
			push_error("Not all replacement identities emitted visible particles")
			quit(20)
		fx.queue_redraw()
	_suppress_overlays()
	for frame: int in 4:
		await process_frame
	_validate_projection(state)
	var image := root.get_texture().get_image()
	var output := "%s-%s-%02d.png" % [_output_prefix, state, model_tick]
	if image.save_png(output) != OK:
		push_error("Cannot save particle capture")
		quit(21)
