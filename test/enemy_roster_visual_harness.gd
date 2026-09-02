extends "res://scripts/view/battle_view.gd"

const ENEMY_IDS: Array[StringName] = [
	&"grunt",
	&"runner",
	&"shieldbearer",
	&"breacher",
	&"heavy",
	&"drone",
	&"interceptor",
	&"spellcaster",
	&"mini_boss",
]
const WATCHDOG_SECONDS := 30.0
var _finished := false


func _ready() -> void:
	get_tree().create_timer(WATCHDOG_SECONDS).timeout.connect(_on_watchdog_timeout)
	var source_stage := load("res://data/stages/s16.tres") as StageDef
	var theme_result := _resolve_stage_theme(source_stage)
	if not String(theme_result["error"]).is_empty():
		push_error("enemy_roster_visual_harness: stage theme failed")
		get_tree().quit(1)
		return
	_stage_theme = theme_result["theme"] as Resource
	_stage = source_stage.copy_for_viewport(get_viewport_rect().size)
	var config := load("res://data/config/game.tres") as GameConfig
	_enemy_defs = _load_enemy_defs(_stage)
	_op_defs = _load_catalog("res://data/operators", "OperatorDef")
	_trap_defs = _load_catalog("res://data/traps", "TrapDef")
	model = BattleModel.create(
		_stage,
		[],
		9182,
		config,
		_enemy_defs,
		_op_defs,
		_trap_defs,
	)
	if model == null or not _build_grid(_stage):
		push_error("enemy_roster_visual_harness: setup failed")
		get_tree().quit(1)
		return
	ticks_per_frame_scale = 0.0
	set_process(false)
	for index: int in ENEMY_IDS.size():
		_spawn_enemy(ENEMY_IDS[index], index)
	_project()
	if OS.get_environment("ENEMY_EFFECTS_PREVIEW") == "1":
		_preview_static_enemy_effects()
	_relayout()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var missing: Array[String] = []
	for enemy: EnemyState in model.enemies:
		var body := _enemy_rects.get(enemy.id) as ColorRect
		var sprite := body.get_node_or_null("Sprite") as TextureRect if body != null else null
		var resolved := sprite != null and sprite.texture != null
		if not resolved:
			missing.append(String(enemy.def_id))
		print("ENEMY_ROSTER_VISUAL|%s|sprite=%s|fallback=%s" % [
			enemy.def_id,
			resolved,
			body != null and body.color.a > 0.0,
		])
		if body != null:
			_add_nameplate(body, enemy.def_id, resolved)
	await RenderingServer.frame_post_draw
	var capture_path := OS.get_environment("ENEMY_ROSTER_CAPTURE")
	if capture_path.is_empty():
		capture_path = "/tmp/enemy-roster.png"
	var error := get_viewport().get_texture().get_image().save_png(capture_path)
	if error != OK:
		push_error("enemy_roster_visual_harness: capture failed %s" % error_string(error))
		get_tree().quit(1)
		return
	Sfx.stop_all()
	_finished = true
	print("ENEMY_ROSTER_VISUAL_OK|%s|missing=%s" % [capture_path, ",".join(missing)])
	get_tree().quit(0)


func _spawn_enemy(enemy_id: StringName, index: int) -> void:
	var path_count := maxi(1, _stage.paths.size())
	var path_idx: int = index % path_count
	model._spawn({"enemy_id": enemy_id, "path_idx": path_idx})
	var enemy := model.enemies[-1] as EnemyState
	var path_length := Pathing.length_units(model.path_for(path_idx))
	var lane_index: int = index / path_count
	var fraction := 0.22 + 0.22 * float(lane_index)
	enemy.progress_units = clampi(roundi(float(path_length) * fraction), 0, path_length - 1)


func _add_nameplate(body: ColorRect, enemy_id: StringName, resolved: bool) -> void:
	var label := Label.new()
	label.name = "DebugName"
	label.text = String(enemy_id)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color("eaf8ff") if resolved else Color("ff7777"))
	label.position = Vector2(-44.0, -28.0)
	label.size = Vector2(body.size.x + 88.0, 24.0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(label)


func _preview_static_enemy_effects() -> void:
	for enemy: EnemyState in model.enemies:
		if not EnemyAnimator.uses_static_sprite(enemy.def_id):
			continue
		var body := _enemy_rects.get(enemy.id) as ColorRect
		if body == null:
			continue
		var total := EnemyAnimator.damage_flash_frames_for(enemy.def_id, 6)
		EnemyAnimator.apply_damage_flash(
			body,
			maxi(1, total / 2),
			total,
			Color.WHITE,
			Color.RED,
			enemy.def_id,
		)
		EnemyAnimator.begin_death_effect(body, enemy.def_id, enemy.id, false)
		EnemyAnimator.advance_death_effect(
			body,
			EnemyAnimator.static_effect_duration(enemy.def_id) * 0.34,
		)


func _on_watchdog_timeout() -> void:
	if _finished:
		return
	push_error("enemy_roster_visual_harness: timed out")
	get_tree().quit(1)
