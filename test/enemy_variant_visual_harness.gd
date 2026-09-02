extends "res://scripts/view/battle_view.gd"

const TARGETS := {
	&"s2": &"shieldbearer",
	&"s3": &"breacher",
	&"s4": &"interceptor",
}
const COMPARATORS := {
	&"s2": &"grunt",
	&"s3": &"runner",
	&"s4": &"drone",
}
const WATCHDOG_SECONDS := 20.0
var _finished := false


func _ready() -> void:
	get_tree().create_timer(WATCHDOG_SECONDS).timeout.connect(_on_watchdog_timeout)
	var stage_id := StringName(OS.get_environment("ENEMY_VARIANT_STAGE"))
	if not TARGETS.has(stage_id):
		stage_id = &"s2"
	var source_stage := load("res://data/stages/%s.tres" % stage_id) as StageDef
	var theme_result := _resolve_stage_theme(source_stage)
	if not String(theme_result["error"]).is_empty():
		push_error("enemy_variant_visual_harness: stage theme failed for %s" % stage_id)
		get_tree().quit(1)
		return
	_stage_theme = theme_result["theme"] as Resource
	_stage = source_stage.copy_for_viewport(get_viewport_rect().size)
	if get_viewport_rect().size.y > get_viewport_rect().size.x and _stage_theme != null:
		_stage_theme = _stage_theme.call("clockwise_rotated_copy", source_stage.grid_size())
	var config := load("res://data/config/game.tres") as GameConfig
	_enemy_defs = _load_enemy_defs(_stage)
	_op_defs = _load_catalog("res://data/operators", "OperatorDef")
	_trap_defs = _load_catalog("res://data/traps", "TrapDef")
	model = BattleModel.create(
		_stage,
		[],
		8270 + int(_stage.campaign_index),
		config,
		_enemy_defs,
		_op_defs,
		_trap_defs,
	)
	if model == null or not _build_grid(_stage):
		set_physics_process(false)
		push_error("enemy_variant_visual_harness: setup failed for %s" % stage_id)
		get_tree().quit(1)
		return
	_build_hud()
	ticks_per_frame_scale = 0.0
	set_process(false)
	var target_id: StringName = TARGETS[stage_id]
	var comparator_id: StringName = COMPARATORS[stage_id]
	_spawn_at_fraction(target_id, 0, 0.38, false)
	_spawn_at_fraction(target_id, 0, 0.58, true)
	_spawn_at_fraction(comparator_id, 0, 0.72, false)
	var focus_enemy := model.enemies[0] as EnemyState
	var focus_position := Pathing.position_of(
		model.path_for(focus_enemy.path_idx), focus_enemy.progress_units
	)
	var desired_pan: Vector2 = (
		get_viewport_rect().size * 0.5
		- _map_nav.origin
		- IsoProjection.project(focus_position) * _map_nav.scale
	)
	_map_nav.pan = IsoProjection.clamp_pan(desired_pan, _map_nav.bounds)
	_apply_map_transform()
	_project()
	_relayout()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var target_bodies := 0
	for enemy: EnemyState in model.enemies:
		var body := _enemy_rects.get(enemy.id) as ColorRect
		if enemy.def_id == target_id and body != null:
			target_bodies += 1
			var sprite := body.get_node_or_null("Sprite") as TextureRect
			if sprite == null or sprite.texture == null:
				push_error("enemy_variant_visual_harness: target sprite missing for %s" % target_id)
				get_tree().quit(1)
				return
	if target_bodies != 2:
		push_error("enemy_variant_visual_harness: expected two target bodies")
		get_tree().quit(1)
		return
	var capture_path := OS.get_environment("ENEMY_VARIANT_CAPTURE")
	if capture_path.is_empty():
		capture_path = "/tmp/enemy-variant-%s.png" % stage_id
	var error := get_viewport().get_texture().get_image().save_png(capture_path)
	if error != OK:
		push_error("enemy_variant_visual_harness: capture failed %s" % error_string(error))
		get_tree().quit(1)
		return
	Sfx.stop_all()
	_finished = true
	print("ENEMY_VARIANT_VISUAL_OK|%s|%s|%s" % [stage_id, target_id, capture_path])
	get_tree().quit(0)


func _on_watchdog_timeout() -> void:
	if _finished:
		return
	push_error("enemy_variant_visual_harness: timed out waiting for a rendered capture")
	get_tree().quit(1)


func _spawn_at_fraction(
	enemy_id: StringName,
	path_idx: int,
	fraction: float,
	attacking: bool,
) -> void:
	model._spawn({"enemy_id": enemy_id, "path_idx": path_idx})
	var enemy := model.enemies[-1] as EnemyState
	var path_length := Pathing.length_units(model.path_for(path_idx))
	enemy.progress_units = clampi(roundi(float(path_length) * fraction), 0, path_length - 1)
	if attacking:
		enemy.blocked_by = 0
		enemy.atk_counter = maxi(1, enemy.atk_interval_ticks / 2)
