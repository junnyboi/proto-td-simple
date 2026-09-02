extends Node2D

const MAP_NAVIGATOR_SCRIPT: GDScript = preload("res://scripts/view/map_navigator.gd")
const BATTLE_HUD_PRESENTER := preload("res://scripts/view/battle_hud_presenter.gd")
const BattlePalette := preload("res://scripts/view/battle_palette.gd")
const EnemyAnimator := preload("res://scripts/view/enemy_animator.gd")
const BATTLE_HEALTH_BAR_SCRIPT := preload("res://scripts/view/battle_health_bar.gd")
const ENEMY_DAMAGE_FEEDBACK_SCRIPT := preload("res://scripts/view/enemy_damage_feedback.gd")
const SKILL_READY_FEEDBACK_SCRIPT := preload("res://scripts/view/skill_ready_feedback.gd")
const OPERATOR_ANIMATOR_SCRIPT := preload("res://scripts/view/operator_animator.gd")
const OPERATOR_VISUAL_CATALOG_SCRIPT := preload(
	"res://data/presentation/operator_visual_catalog.gd"
)
const FIRST_STAND_TUTORIAL_SCRIPT := preload("res://scripts/ui/first_stand_tutorial.gd")
const MAP_NAVIGATION_OVERLAY_SCRIPT := preload("res://scripts/ui/map_navigation_overlay.gd")
const ACT2_STAGE_TRANSITION_SCRIPT := preload(
	"res://scripts/ui/components/act2_stage_transition.gd"
)
const StageArtThemeType := preload("res://data/presentation/stage_art_theme.gd")
const GameTypographyType := preload("res://scripts/ui/game_typography.gd")
const LunarisOpsType := preload("res://scripts/ui/components/lunaris_ops_style.gd")
const UiCopyType := preload("res://scripts/ui/components/ui_copy.gd")
const ActionHoverFeedbackType := preload(
	"res://scripts/ui/components/action_hover_feedback.gd"
)
const DefeatAmbientLayerType := preload(
	"res://scripts/ui/components/defeat_ambient_layer.gd"
)
const MUSIC_DIRECTOR_SCRIPT := preload("res://scripts/view/music_director.gd")

const HUD_FONT_SIZE := GameTypographyType.ACTION
const SPRITE_SCALE := 2  # 32px art on the 64px grid (pinned 2x integer)
const IDLE_BOB_FRAMES := 24
const ATTACK_POSE_FRAMES := 8

const UI_OVERLAY_Z := 64
const JUICE_Z := 68
const HUD_Z := 72
const BACKDROP_COLOR := Color("11131f")
const ENEMY_COLOR := Color("ef7d57")
const AERIAL_PX := 24.0
const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.35)
const SHADOW_FACE_SCALE := 0.3125
const AERIAL_SHADOW_DROP := 10.0
const TRACER_COLOR := Color("f4f4f4")
const UNIT_PX := 64.0  # 32px art at the pinned 2x scale
const SP_BAR_WIDTH_SCALE := 0.5
const SP_BAR_HEIGHT := 2.5
const SP_BAR_BG := Color("20263a")
const SP_BAR_FILL := Color("f4b41b")
const TERMINAL_CONTINUE_WIDTH := 640.0
const TERMINAL_CONTINUE_WIDE_HEIGHT := 112.0
const TERMINAL_CONTINUE_NARROW_HEIGHT := 160.0
const TERMINAL_CONTINUE_FONT_SIZE := 42
const TERMINAL_CONTINUE_HORIZONTAL_PADDING := 36.0
const TERMINAL_CONTINUE_VERTICAL_PADDING := 24.0
const SP_FULL_FLASH := Color("f4f4f4")
const PORTRAIT_FLASH_PX := 96.0
const CHEVRON_COLOR := Color("f4f4f4")
const TRAP_SPIKE_COLOR := Color("f4b41b")
const TRAP_SPIKE_CORE := Color("1a1c2c")
const TRAP_SPIKE_PX := 24.0
const TAR_OVERLAY_COLOR := Color(0.08, 0.05, 0.14, 0.6)
const OPERATOR_SELECTION_TIME_SCALE := 0.75

var model: BattleModel = null
var startup_succeeded: bool = false
var theme_resolver: Callable = Callable()
var model_factory: Callable = Callable()
var ticks_per_frame_scale: float = 1.0
var cfg: JuiceConfig = null

var _grid_root: Node2D = null
var _grid_scale := 1.0
var _map_nav: RefCounted = MAP_NAVIGATOR_SCRIPT.new()
var _backdrop: ColorRect = null
var _stage: StageDef = null
var _stage_theme: Resource = null
var _enemy_rects: Dictionary = {}
var _unit_nodes: Dictionary = {}
var _tracer_lines: Dictionary = {}
var _tracer_seen_tick: Dictionary = {}
var _tracer_frames_left: Dictionary = {}
var _skill_seen_tick: Dictionary = {}
var _skill_ready_feedback: RefCounted = SKILL_READY_FEEDBACK_SCRIPT.new()
var _portrait_flash: ColorRect = null
var _portrait_flash_frames := 0
var _continue_btn: Button = null
var _defeat_ambient: DefeatAmbientLayerType = null
var _deploy_bar: DeployBar = null
var _controls: BattleControls = null
var _tutorial: Node = null
var _map_navigation_overlay: MapNavigationOverlay = null
var _battle_confirmation_active := false
var _act2_transition: Act2StageTransition = null
var _act2_entry_active := false
var _act2_exit_active := false
var _op_defs: Dictionary = {}
var _trap_defs: Dictionary = {}
var _trap_rects: Dictionary = {}
var _trap_kinds: Dictionary = {}
var _hud: Label = null
var _tick_accum: float = 0.0
var _juice: JuiceLayer = null
var _time_tags: Dictionary = {}
var _hit_stop_frames := 0
var _deploy_seen: Dictionary = {}
var _spark_seen: Dictionary = {}
var _leaked_seen := 0
var _banner_seen_wave := -1
var _stamp_shown := false
var _result_finalize_running := false
var _result_finalized := false
var _snaps_seen := 0
var _trap_trigger_seen: Dictionary = {}
var _enemy_defs: Dictionary = {}
var _base_enemy_defs: Dictionary = {}
var _base_op_defs: Dictionary = {}
var _enemy_anim_keys: Dictionary = {}
var _enemy_blend_frames: Dictionary = {}
var _enemy_anim_seconds := 0.0
var _operator_anim_seconds := 0.0
var _enemy_damage_feedback: RefCounted = ENEMY_DAMAGE_FEEDBACK_SCRIPT.new()
var _attack_pose_left: Dictionary = {}
var _unit_attack_seen: Dictionary = {}
var _music_director: MusicDirector = MUSIC_DIRECTOR_SCRIPT.new()
var _music_elapsed_seconds := 0.0
var _music_last_leaked_count := 0
var _music_recent_danger_until_seconds := 0.0


func _init() -> void:
	theme_resolver = Callable(self, "_resolve_stage_theme")
	model_factory = Callable(BattleModel, "create")


func _ready() -> void:
	var source_stage := Game.pending_stage
	if source_stage == null:
		push_error("battle_view: no pending stage")
		return
	# Required world presentation is preflighted against the authored landscape
	# resource before the portrait copy rotates cell-indexed presentation metadata.
	var theme_result: Dictionary = theme_resolver.call(source_stage)
	var theme_error := String(theme_result["error"])
	if not theme_error.is_empty():
		push_error("battle_view: stage art preflight failed: %s" % theme_error)
		return
	_stage_theme = theme_result["theme"] as Resource
	var viewport_size := get_viewport_rect().size
	var portrait_mode := viewport_size.y > viewport_size.x
	var stage := source_stage.copy_for_viewport(viewport_size).duplicate(true) as StageDef
	if portrait_mode and _stage_theme != null:
		_stage_theme = (_stage_theme as StageArtTheme).clockwise_rotated_copy(
			source_stage.grid_size()
		)
	var config := (load("res://data/config/game.tres") as GameConfig).duplicate(true) as GameConfig
	TweakControls.apply_game_config(config)
	TweakControls.apply_stage(stage)
	var source_enemy_defs := _load_enemy_defs(stage)
	_base_enemy_defs = TweakControls.duplicate_definitions(source_enemy_defs)
	var defs := TweakControls.duplicate_definitions(source_enemy_defs)
	TweakControls.apply_enemy_definitions(defs, _base_enemy_defs)
	_enemy_defs = defs
	# operators load as a full catalog too (squad stays the model's loadout
	var source_operator_defs := _load_catalog("res://data/operators", "OperatorDef")
	_base_op_defs = TweakControls.duplicate_definitions(source_operator_defs)
	_op_defs = TweakControls.duplicate_definitions(source_operator_defs)
	TweakControls.apply_operator_definitions(_op_defs, _base_op_defs)
	_trap_defs = _load_catalog("res://data/traps", "TrapDef")
	var launch: Dictionary = Game.battle_launch()
	var candidate_model: BattleModel = model_factory.call(
		stage,
		launch["input"],
		Game.run_seed,
		config,
		defs,
		_op_defs,
		_trap_defs,
		launch["trusted_ticket_hashes"],
		launch["fixed_operator_ids"],
	)
	if candidate_model == null:
		push_error("battle_view: model factory failed")
		return
	_stage = stage
	Music.prepare_results(_stage.music_profile_id)
	Sfx.prepare_cues([&"victory", &"defeat"])
	if not _build_grid(stage):
		return
	cfg = load("res://data/juice_config.tres") as JuiceConfig
	_juice = JuiceLayer.new()
	_juice.name = "JuiceLayer"
	_juice.z_index = JUICE_Z
	add_child(_juice)
	_juice.setup(cfg, _grid_root)
	_build_hud()
	_portrait_flash = ColorRect.new()
	_portrait_flash.name = "PortraitFlash"
	_portrait_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait_flash.size = Vector2.ONE * PORTRAIT_FLASH_PX
	_portrait_flash.position = Vector2((get_viewport_rect().size.x - PORTRAIT_FLASH_PX) * 0.5, 56.0)
	_portrait_flash.visible = false
	_portrait_flash.z_index = HUD_Z
	add_child(_portrait_flash)
	# unlocked sets while a campaign runs, the full catalogs otherwise —
	# the model stays catalog-validated either way
	var bar_traps: Dictionary = {}
	for trap_id: StringName in launch["trap_ids"]:
		if _trap_defs.has(trap_id):
			bar_traps[trap_id] = _trap_defs[trap_id]
	_deploy_bar = DeployBar.new()
	_deploy_bar.name = "DeployBar"
	_deploy_bar.z_index = UI_OVERLAY_Z
	add_child(_deploy_bar)
	_deploy_bar.setup(candidate_model, self, _op_defs, bar_traps)
	_controls = BattleControls.new()
	_controls.name = "BattleControls"
	_controls.z_index = UI_OVERLAY_Z
	add_child(_controls)
	_controls.setup(candidate_model, self)
	_map_navigation_overlay = MAP_NAVIGATION_OVERLAY_SCRIPT.new()
	_map_navigation_overlay.name = "MapNavigationOverlay"
	add_child(_map_navigation_overlay)
	_map_navigation_overlay.setup()
	model = candidate_model
	var initial_music_state := &"boss" if _stage.music_variant_id == &"boss" else &"low"
	_music_director.configure(Music.minimum_state_hold_seconds(_stage.music_profile_id))
	_music_director.reset(initial_music_state, 0.0)
	_music_last_leaked_count = model.leaked
	_start_stage_tutorial()
	_relayout()
	_refresh_map_navigation_overlay()
	# the view is the ONE resize owner: it recomputes the grid scale first,
	# then drives the bars (self-owned listeners raced the recompute — P14)
	get_viewport().size_changed.connect(_relayout)
	if not I18n.locale_changed.is_connected(_on_locale_changed):
		I18n.locale_changed.connect(_on_locale_changed)
	if not TweakControls.value_changed.is_connected(_on_tweak_value_changed):
		TweakControls.value_changed.connect(_on_tweak_value_changed)
	startup_succeeded = true
	if _is_act2_stage():
		_play_act2_entry_transition.call_deferred()


func _start_stage_tutorial() -> void:
	if _should_show_first_stand_tutorial():
		_tutorial = FIRST_STAND_TUTORIAL_SCRIPT.new()
		_tutorial.name = "FirstStandTutorial"
		_connect_tutorial()
		_tutorial.call("setup", model, self, _deploy_bar)


func _connect_tutorial() -> void:
	_tutorial.connect("hold_changed", _on_tutorial_hold_changed)
	_tutorial.connect("tutorial_finished", _on_tutorial_finished)
	add_child(_tutorial)


func _should_show_first_stand_tutorial() -> bool:
	# Mission 1 is the guided mission on every playthrough, including replays.
	# Campaign completion history must never suppress its field tutorial.
	return (
		_stage != null
		and _stage.id == &"s1"
		and Game.campaign_active
		and bool(TweakControls.value(&"ui.tutorial_hints_enabled", true))
	)


func _on_tutorial_hold_changed(held: bool) -> void:
	if held:
		juice_time_push(&"guided_tutorial", 0.0)
	else:
		juice_time_pop(&"guided_tutorial")
	_refresh_battle_interaction_gates()


func _on_tutorial_finished(_skipped: bool) -> void:
	_tutorial = null
	_refresh_battle_interaction_gates()


func set_battle_confirmation_active(active: bool) -> void:
	if _battle_confirmation_active == active:
		return
	_battle_confirmation_active = active
	if active:
		if _map_nav.cancel_interaction():
			_apply_map_transform()
		if _deploy_bar != null:
			_deploy_bar.cancel_transient_intent()
	_refresh_battle_interaction_gates()
	if not active and model != null and model.result != BattleModel.Result.RUNNING:
		_focus_terminal_continue()


func battle_confirmation_active() -> bool:
	return _battle_confirmation_active


func _tutorial_holding_battle() -> bool:
	return _tutorial != null and bool(_tutorial.call("is_holding_battle"))


func _refresh_battle_interaction_gates() -> void:
	var running := model == null or model.result == BattleModel.Result.RUNNING
	var tutorial_holding := _tutorial_holding_battle()
	var transition_blocked := _act2_entry_active or _act2_exit_active
	if _controls != null:
		_controls.set_interaction_enabled(not tutorial_holding and not transition_blocked and running)
	if _deploy_bar != null:
		# FirstStandTutorial owns its step-specific operator gate. The battle-level
		# confirmation gate composes independently so closing it cannot overwrite
		# ROUTE/BLOCK or DEPLOY tutorial intent.
		_deploy_bar.set_interaction_enabled(
			not _battle_confirmation_active and not transition_blocked and running
		)
	_refresh_map_navigation_overlay()


func _focus_terminal_continue() -> void:
	if (
		_continue_btn != null
		and is_instance_valid(_continue_btn)
		and not _continue_btn.disabled
	):
		_continue_btn.grab_focus.call_deferred()


func _resolve_stage_theme(stage: Resource) -> Dictionary:
	return StageArtThemeType.resolve_for(stage)


## Screen center of a cell's visible face; elevated cells include their lift.
func cell_center(cell: Vector2i) -> Vector2:
	var local := IsoProjection.face_center(cell, _is_lifted_cell(cell))
	return _grid_root.position + local * _grid_scale


func cell_at(screen_pos: Vector2) -> Vector2i:
	var local := (screen_pos - _grid_root.position) / _grid_scale
	return IsoProjection.pick(local, _is_lifted_cell)


## Screen point for continuous flat cell-space positions and VFX anchors.
func screen_of(p: Vector2) -> Vector2:
	return _grid_root.position + IsoProjection.project(p) * _grid_scale


## Current uniform grid scale used by screen-owned overlay footprints.
func grid_scale() -> float:
	return _grid_scale


func map_screen_rect() -> Rect2:
	var box := IsoProjection.terrain_box(_stage)
	return Rect2(_grid_root.position + box.position * _grid_scale, box.size * _grid_scale)


func map_content_rect() -> Rect2:
	return _map_nav.content_screen_rect()


func map_pan() -> Vector2:
	return _map_nav.pan


func map_pan_bounds() -> Rect2:
	return _map_nav.bounds


func map_dragging() -> bool:
	return _map_nav.is_dragging()


func map_inertia_active() -> bool:
	return _map_nav.is_inertia_active()


func consume_map_primary_click_suppression() -> bool:
	return _map_nav.consume_primary_click_suppression()


func _input(event: InputEvent) -> void:
	if _battle_confirmation_active:
		return
	_map_nav.recover_missed_release(event)


func _unhandled_input(event: InputEvent) -> void:
	if _grid_root == null or _map_navigation_blocked():
		return
	if _map_nav.handle_input(event):
		if _map_navigation_overlay != null and _map_nav.is_dragging():
			_map_navigation_overlay.notify_pan_used()
		_apply_map_transform()
		get_viewport().set_input_as_handled()


func _map_navigation_blocked() -> bool:
	var deploy_cursor := find_child("CursorRect", true, false) as CanvasItem
	var deploy_bar := find_child("DeployBar", true, false) as DeployBar
	return (
		_battle_confirmation_active
		or _act2_entry_active
		or _act2_exit_active
		or (model != null and model.result != BattleModel.Result.RUNNING)
		or _tutorial_holding_battle()
		or (deploy_cursor != null and deploy_cursor.visible)
		or (deploy_bar != null and deploy_bar.is_mend_targeting())
	)


func _is_lifted_cell(cell: Vector2i) -> bool:
	return _stage != null and _stage.is_elevated_platform(cell)


func _physics_process(delta: float) -> void:
	if model == null:
		return
	if _act2_entry_active or _act2_exit_active:
		_project()
		return
	# hit-stop: suspend tick consumption only — outcome-safe by rule 6
	if _hit_stop_frames > 0:
		_hit_stop_frames -= 1
		_project()
		return
	_tick_accum += (
		delta
		* model.config.ticks_per_second
		* ticks_per_frame_scale
		* float(TweakControls.value(&"gameplay.simulation_rate", 1.0))
	)
	while _tick_accum >= 1.0:
		_tick_accum -= 1.0
		model.step()
	_project()


func _process(delta: float) -> void:
	if _grid_root != null and _map_nav.is_inertia_active():
		if _map_navigation_blocked():
			_map_nav.cancel_inertia()
		elif _map_nav.advance_inertia(delta):
			_apply_map_transform()
	_refresh_map_navigation_overlay()
	if model == null or _juice == null:
		return
	if model.leaked > _music_last_leaked_count:
		_music_recent_danger_until_seconds = _music_elapsed_seconds + 6.0
	_music_last_leaked_count = model.leaked
	if ticks_per_frame_scale > 0.0 and _hit_stop_frames <= 0:
		_music_elapsed_seconds += delta
		var requested_music_state := _music_director.update(
			model,
			_stage.music_variant_id,
			_music_elapsed_seconds,
			_music_elapsed_seconds < _music_recent_danger_until_seconds,
		) if bool(TweakControls.value(&"audio.dynamic_music_enabled", true)) else &""
		if (
			not requested_music_state.is_empty()
			and Music.request_battle_state(
				requested_music_state,
				requested_music_state in [&"high", &"critical", &"boss", &"boss_critical"],
			)
		):
			_music_director.accept_state(requested_music_state, _music_elapsed_seconds)
	_enemy_anim_seconds += delta * float(TweakControls.value(&"enemies.animation_speed", 1.0))
	_operator_anim_seconds += delta * float(TweakControls.value(&"player.animation_speed", 1.0))
	_enemy_damage_feedback.process(delta, model, _enemy_rects, cfg)
	_detect_deploys()
	_detect_kills()
	_detect_leaks()
	_detect_wave()
	_detect_result_stamp()
	_detect_trap_juice()
	if _portrait_flash_frames > 0:
		_portrait_flash_frames -= 1
		if _portrait_flash_frames == 0 and _portrait_flash != null:
			_portrait_flash.visible = false
	_age_view_transients()


## Tracer and attack-pose countdowns age in render frames, including hit-stop.
func _age_view_transients() -> void:
	for uid: int in _tracer_frames_left.keys():
		var left := int(_tracer_frames_left[uid])
		if left > 0:
			_tracer_frames_left[uid] = left - 1
	for uid: int in _attack_pose_left.keys():
		var left := int(_attack_pose_left[uid])
		if left > 0:
			_attack_pose_left[uid] = left - 1
	for enemy_id: int in _enemy_blend_frames.keys():
		if not _enemy_rects.has(enemy_id):
			_enemy_blend_frames.erase(enemy_id)
			continue
		if (
			enemy_id < model.enemies.size()
			and _enemy_damage_feedback.is_staggered(model, model.enemies[enemy_id])
		):
			continue
		var left := int(_enemy_blend_frames[enemy_id])
		EnemyAnimator.apply_blend(_enemy_rects[enemy_id], left)
		if left > 0:
			_enemy_blend_frames[enemy_id] = left - 1
		else:
			_enemy_blend_frames.erase(enemy_id)
	_enemy_damage_feedback.age(_enemy_rects, cfg)


## Single time-scale owner: strongest slowdown wins; empty stack restores 1.0.
func juice_time_push(tag: StringName, value: float) -> void:
	_time_tags[tag] = value
	_apply_time_scale()


func juice_time_pop(tag: StringName) -> void:
	_time_tags.erase(tag)
	_apply_time_scale()


func _apply_time_scale() -> void:
	var time_scale := 1.0
	for tag: StringName in _time_tags:
		time_scale = minf(time_scale, float(_time_tags[tag]))
	Engine.time_scale = time_scale


func _exit_tree() -> void:
	ActionHoverFeedbackType.reset(_continue_btn)
	if TweakControls.value_changed.is_connected(_on_tweak_value_changed):
		TweakControls.value_changed.disconnect(_on_tweak_value_changed)
	Engine.time_scale = 1.0


func resume_battle_music() -> bool:
	if _stage == null or model == null or model.result != BattleModel.Result.RUNNING:
		return false
	return Music.play_battle(
		_stage.music_profile_id,
		_stage.music_variant_id,
		_music_director.current_state(),
	)


func deploy_drag_started() -> void:
	juice_time_push(&"deploy_drag", cfg.deploy_drag_time_scale)


func deploy_drag_ended() -> void:
	juice_time_pop(&"deploy_drag")


func operator_selection_changed(selected: bool) -> void:
	if selected:
		juice_time_push(&"operator_selection", OPERATOR_SELECTION_TIME_SCALE)
	else:
		juice_time_pop(&"operator_selection")


func _detect_deploys() -> void:
	for u: UnitState in model.units:
		var crouch_left := int(_deploy_seen.get(u.id, -1))
		if crouch_left == 0:
			continue
		var node: Node2D = _unit_nodes.get(u.id)
		if node == null:
			continue
		var elevated_placement := _is_lifted_cell(u.cell)
		var local_center := IsoProjection.face_center(u.cell, elevated_placement)
		if crouch_left < 0:
			crouch_left = cfg.deploy_crouch_frames
			if elevated_placement:
				_juice.placement_elevated(local_center)
				Sfx.play("deploy_elevated")
			else:
				_juice.placement_ground(local_center)
				Sfx.play("deploy_ground")
			_juice.crouch(node)
		var next_left := maxi(crouch_left - 1, 0)
		_deploy_seen[u.id] = next_left
		var t := 1.0 - float(next_left) / float(cfg.deploy_crouch_frames)
		var presentation_scale := Vector2(1.0, 0.7).lerp(Vector2.ONE, t)
		var body := node.get_node("Body") as ColorRect
		var unit_rect := Rect2(
			node.position + body.position * presentation_scale,
			body.size * presentation_scale,
		)
		for bar_path: NodePath in [^"HpBarBg", ^"SpBarBg"]:
			var bar := body.get_node_or_null(bar_path) as ColorRect
			if bar != null:
				unit_rect = (
					unit_rect
					. merge(
						Rect2(
							node.position + (body.position + bar.position) * presentation_scale,
							bar.size * presentation_scale,
						)
					)
				)
		if _map_nav.ensure_local_rect_visible(unit_rect):
			_apply_map_transform()


func _detect_kills() -> void:
	for e: EnemyState in model.enemies:
		if e.died_at_tick < 0 or _spark_seen.has(e.id):
			continue
		_spark_seen[e.id] = true
		var pos := Pathing.position_of(model.path_for(e.path_idx), e.progress_units)
		_juice.spark(IsoProjection.project(pos + Vector2.ONE * 0.5))
		Sfx.play("kill")


## item 4: vignette + HUD knock + whitelisted shake key off the leak counter
func _detect_leaks() -> void:
	if model.leaked <= _leaked_seen:
		return
	for _i: int in model.leaked - _leaked_seen:
		Sfx.play("leak")
	_leaked_seen = model.leaked
	_juice.vignette()
	if _hud != null:
		_juice.knock(_hud)
	_juice.shake(
		"leak",
		cfg.leak_shake_amplitude_px
			* float(TweakControls.value(&"environment.screen_shake_multiplier", 1.0)),
		cfg.leak_shake_frames,
	)
	if cfg.leak_hit_stop_frames > 0:
		_hit_stop_frames = cfg.leak_hit_stop_frames


func _detect_wave() -> void:
	var wave := model.stage.wave_index_at(model.tick)
	if wave <= _banner_seen_wave:
		return
	_banner_seen_wave = wave
	if _stage.is_high_threat_wave(wave):
		_present_high_threat_wave(wave)
	else:
		_juice.banner(_format_copy(
			&"ui.battle.wave", "Wave {wave}", {&"wave": wave + 1},
		))
	Sfx.play("wave")


func _present_high_threat_wave(wave: int) -> void:
	var warning_id: StringName = _stage.high_threat_warning_id
	var heading_key := StringName("ui.battle.high_threat.%s.heading" % warning_id)
	var detail_key := StringName("ui.battle.high_threat.%s.detail" % warning_id)
	_juice.high_threat_warning(
		warning_id,
		_format_copy(heading_key, "HIGH-THREAT WAVE", {}),
		_format_copy(detail_key, "Wave {wave} escalation detected", {&"wave": wave + 1}),
		_high_threat_spawn_centers(),
		bool(ProjectSettings.get_setting("accessibility/reduced_motion", false)),
	)


func _high_threat_spawn_centers() -> Array[Vector2]:
	var centers: Array[Vector2] = []
	var seen: Dictionary = {}
	for path_index: int in _stage.paths.size():
		var cells: Array[Vector2i] = _stage.path_cells(path_index)
		if cells.is_empty():
			continue
		var spawn_cell := cells[0]
		if seen.has(spawn_cell):
			continue
		seen[spawn_cell] = true
		centers.append(IsoProjection.face_center(spawn_cell))
	return centers


## Terminal stamp is one-shot on result flip, shared with campaign unlock flow.
func _detect_result_stamp() -> void:
	if _stamp_shown or model.result == BattleModel.Result.RUNNING:
		return
	if _controls != null:
		_controls.notify_battle_terminal()
	_refresh_battle_interaction_gates()
	_stamp_shown = true
	if model.result == BattleModel.Result.CLEAR:
		_juice.stamp(UiCopyType.text(&"ui.battle.stamp_clear", "Victory"), model.stars)
		Sfx.play("victory")
		Music.play_result(true)
	else:
		_show_defeat_ambient()
		_juice.stamp(
			UiCopyType.text(&"ui.battle.stamp_defeat", "Defeat"),
			0,
			3.0,
		)
		Sfx.play("defeat")
		Music.play_result(false)
	# a real Button (the juice layer is MOUSE_FILTER_IGNORE territory) under
	# the stamp band; no auto-swap — scenarios and bots must be able to
	var next := Button.new()
	next.name = "ContinueButton"
	_continue_btn = next
	next.text = UiCopyType.text(&"ui.battle.finalizing_debrief", "FINALIZING DEBRIEF…")
	next.disabled = true
	# (and Space, once terminal) also proceeds — the "what do I click now"
	var viewport := get_viewport_rect().size
	next.custom_minimum_size = _terminal_continue_size(viewport)
	LunarisOpsType.apply_button(next, &"primary")
	_apply_terminal_continue_style(next)
	ActionHoverFeedbackType.wire(self, next)
	next.z_index = HUD_Z
	add_child(next)
	next.position = Vector2(
		(viewport.x - next.get_combined_minimum_size().x) * 0.5, viewport.y * 0.5 + 120.0
	)
	next.pressed.connect(_on_continue_pressed)
	_finalize_terminal_result()


func _finalize_terminal_result() -> void:
	if _result_finalize_running or _result_finalized or model == null:
		return
	_result_finalize_running = true
	if _continue_btn != null:
		_continue_btn.disabled = true
		_continue_btn.text = UiCopyType.text(
			&"ui.battle.finalizing_debrief", "FINALIZING DEBRIEF…",
		)
	# Guarantee the result stamp and audio reach one rendered frame before any
	# remaining persistence work begins, even on the non-threaded Web build.
	await get_tree().process_frame
	if not is_inside_tree() or model == null:
		_result_finalize_running = false
		return
	var prepared := Game.prepare_result(model.result, model.stars)
	if prepared:
		await get_tree().process_frame
		if not is_inside_tree() or model == null:
			_result_finalize_running = false
			return
	var recorded := prepared and Game.commit_prepared_result()
	_result_finalize_running = false
	if _continue_btn == null or not is_instance_valid(_continue_btn):
		return
	if recorded:
		_result_finalized = true
		_continue_btn.text = UiCopyType.text(
			&"ui.battle.continue_debrief", "CONTINUE",
		)
	else:
		_continue_btn.text = UiCopyType.text(
			&"ui.battle.retry_finalization", "RETRY FINALIZATION",
		)
	_continue_btn.disabled = false
	if not _battle_confirmation_active:
		_focus_terminal_continue()


func _show_defeat_ambient() -> void:
	if _defeat_ambient != null and is_instance_valid(_defeat_ambient):
		return
	_defeat_ambient = DefeatAmbientLayerType.new()
	_defeat_ambient.name = "DefeatAmbient"
	_defeat_ambient.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_defeat_ambient.z_index = JUICE_Z - 1
	_defeat_ambient.position = Vector2.ZERO
	_defeat_ambient.size = get_viewport_rect().size
	add_child(_defeat_ambient)


func _on_locale_changed(_locale_id: StringName) -> void:
	_refresh_hud_copy()
	if _continue_btn != null:
		if _result_finalized:
			_continue_btn.text = UiCopyType.text(
				&"ui.battle.continue_debrief", "CONTINUE",
			)
		elif _result_finalize_running:
			_continue_btn.text = UiCopyType.text(
				&"ui.battle.finalizing_debrief", "FINALIZING DEBRIEF…",
			)
		else:
			_continue_btn.text = UiCopyType.text(
				&"ui.battle.retry_finalization", "RETRY FINALIZATION",
			)
	var wave_label := find_child("WaveBanner", true, false) as Label
	if wave_label != null and _banner_seen_wave >= 0:
		wave_label.text = _format_copy(
			&"ui.battle.wave", "Wave {wave}", {&"wave": _banner_seen_wave + 1},
		)
	if (
		_juice != null
		and _juice.high_threat_warning_visible()
		and _banner_seen_wave >= 0
	):
		var warning_id := _juice.high_threat_warning_id()
		_juice.update_high_threat_copy(
			_format_copy(
				StringName("ui.battle.high_threat.%s.heading" % warning_id),
				"HIGH-THREAT WAVE",
				{},
			),
			_format_copy(
				StringName("ui.battle.high_threat.%s.detail" % warning_id),
				"Wave {wave} escalation detected",
				{&"wave": _banner_seen_wave + 1},
			),
		)
	var stamp_label := find_child("ResultStampLabel", true, false) as Label
	if stamp_label != null and model != null:
		stamp_label.text = UiCopyType.text(
			&"ui.battle.stamp_clear" if model.result == BattleModel.Result.CLEAR else &"ui.battle.stamp_defeat",
			"Victory" if model.result == BattleModel.Result.CLEAR else "Defeat",
		)


func _terminal_continue_size(viewport: Vector2) -> Vector2:
	var width := minf(TERMINAL_CONTINUE_WIDTH, maxf(280.0, viewport.x - 48.0))
	return Vector2(
		width,
		TERMINAL_CONTINUE_NARROW_HEIGHT if width < 520.0 else TERMINAL_CONTINUE_WIDE_HEIGHT,
	)


func _apply_terminal_continue_style(button: Button) -> void:
	button.add_theme_font_size_override(&"font_size", TERMINAL_CONTINUE_FONT_SIZE)
	button.add_theme_color_override(&"font_color", Color.WHITE)
	button.add_theme_color_override(&"font_hover_color", Color.WHITE)
	button.add_theme_color_override(&"font_pressed_color", Color.WHITE)
	button.add_theme_color_override(&"font_focus_color", Color.WHITE)
	button.add_theme_color_override(&"font_disabled_color", Color.WHITE)
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.clip_text = false
	for state: StringName in [&"normal", &"hover", &"pressed", &"disabled"]:
		var source := button.get_theme_stylebox(state)
		if source == null:
			continue
		var style := source.duplicate() as StyleBox
		style.content_margin_left = maxf(
			style.content_margin_left,
			TERMINAL_CONTINUE_HORIZONTAL_PADDING,
		)
		style.content_margin_top = maxf(
			style.content_margin_top,
			TERMINAL_CONTINUE_VERTICAL_PADDING,
		)
		style.content_margin_right = maxf(
			style.content_margin_right,
			TERMINAL_CONTINUE_HORIZONTAL_PADDING,
		)
		style.content_margin_bottom = maxf(
			style.content_margin_bottom,
			TERMINAL_CONTINUE_VERTICAL_PADDING,
		)
		button.add_theme_stylebox_override(state, style)


func _format_copy(key: StringName, fallback: String, args: Dictionary) -> String:
	var value := UiCopyType.text(key, fallback)
	for name: StringName in args:
		value = value.replace("{%s}" % name, str(args[name]))
	return value


func _on_continue_pressed() -> void:
	if not _result_finalized:
		_finalize_terminal_result()
		return
	Sfx.play("ui_confirm")
	if _is_act2_stage() and not _act2_exit_active:
		_play_act2_exit_transition()
		return
	Game.open_results()


func _is_act2_stage() -> bool:
	return _stage != null and _stage.campaign_index >= 9


func _stage_display_title() -> String:
	if _stage == null:
		return ""
	return UiCopyType.text(
		StringName("data.stage.%s.title" % _stage.id),
		_stage.title,
	)


func _reduced_motion() -> bool:
	return bool(ProjectSettings.get_setting("accessibility/reduced_motion", false))


func _play_act2_entry_transition() -> void:
	if not _is_act2_stage() or _act2_entry_active or _act2_exit_active:
		return
	_act2_entry_active = true
	_refresh_battle_interaction_gates()
	_act2_transition = ACT2_STAGE_TRANSITION_SCRIPT.new() as Act2StageTransition
	_act2_transition.name = "ActIIStageTransition"
	add_child(_act2_transition)
	_act2_transition.entry_finished.connect(_on_act2_entry_finished, CONNECT_ONE_SHOT)
	_act2_transition.play_entry(_stage.campaign_index, _stage_display_title(), _reduced_motion())


func _on_act2_entry_finished() -> void:
	_act2_entry_active = false
	_act2_transition = null
	_refresh_battle_interaction_gates()


func _play_act2_exit_transition() -> void:
	_act2_exit_active = true
	if _continue_btn != null:
		_continue_btn.disabled = true
	_refresh_battle_interaction_gates()
	_act2_transition = ACT2_STAGE_TRANSITION_SCRIPT.new() as Act2StageTransition
	_act2_transition.name = "ActIIStageTransition"
	add_child(_act2_transition)
	_act2_transition.exit_finished.connect(_on_act2_exit_finished, CONNECT_ONE_SHOT)
	_act2_transition.play_exit(_stage.campaign_index, _stage_display_title(), _reduced_motion())


func _on_act2_exit_finished() -> void:
	_act2_exit_active = false
	_act2_transition = null
	Game.open_results()


## Trap snap keys off trigger count; final-charge removal uses the adoption path.
func _detect_trap_juice() -> void:
	if model.traps_triggered > _snaps_seen:
		for _i: int in model.traps_triggered - _snaps_seen:
			Sfx.play("trap_snap")
		_snaps_seen = model.traps_triggered
	for t: TrapState in model.traps:
		if (
			t.trigger == TrapDef.Trigger.ON_ENTER
			and t.last_trigger_tick > int(_trap_trigger_seen.get(t.id, -1))
		):
			_trap_trigger_seen[t.id] = t.last_trigger_tick
			var rect: ColorRect = _trap_rects.get(t.id)
			if rect != null:
				_juice.sprung(rect, false)
		elif t.trigger == TrapDef.Trigger.CELL_AURA:
			_shimmer_tar(t)


## item 6: tar shimmer while occupied by a walking ENEMY, static otherwise
func _shimmer_tar(t: TrapState) -> void:
	var rect: ColorRect = _trap_rects.get(t.id)
	if rect == null:
		return
	var occupied := false
	for e: EnemyState in model.enemies:
		if not e.alive or e.aerial:
			continue
		if Pathing.cell_of(model.path_for(e.path_idx), e.progress_units) == t.cell:
			occupied = true
			break
	if occupied:
		rect.modulate = Color(1, 1, 1, 0.55) if _juice.shimmer_on() else Color.WHITE
	else:
		rect.modulate = Color.WHITE

func _load_enemy_defs(stage: StageDef) -> Dictionary:
	var defs: Dictionary = {}
	for w: Dictionary in stage.waves:
		var enemy_id: StringName = w["enemy_id"]
		if not defs.has(enemy_id):
			defs[enemy_id] = load("res://data/enemies/%s.tres" % enemy_id) as EnemyDef
	return defs


## Model validation uses full catalogs; loadout restrictions remain UI-owned.
func _load_catalog(dir_path: String, script_class: String) -> Dictionary:
	var defs: Dictionary = {}
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return defs
	for file: String in dir.get_files():
		# exported builds list "<name>.tres.remap" (text->binary conversion);
		# loading by the original .tres path resolves through the remap
		var res_name := file.trim_suffix(".remap")
		if res_name.ends_with(".tres"):
			var def: Resource = load(dir_path + "/" + res_name)
			if (
				def != null
				and def.get_script() != null
				and (def.get_script() as Script).get_global_name() == StringName(script_class)
			):
				defs[def.get("id")] = def
	return defs


func _build_grid(stage: StageDef) -> bool:
	_backdrop = ColorRect.new()
	_backdrop.name = "Backdrop"
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.color = BACKDROP_COLOR
	_backdrop.z_index = -20
	_backdrop.size = get_viewport_rect().size
	add_child(_backdrop)
	_grid_root = Node2D.new()
	_grid_root.name = "GridRoot"
	var viewport := get_viewport_rect().size
	_map_nav.relayout(stage, viewport)
	_apply_map_transform()
	add_child(_grid_root)
	if not IsoGridBuilder.build_stage_with_theme(_grid_root, stage, _stage_theme):
		return false
	return true


func _apply_map_transform() -> void:
	_map_nav.pan_sensitivity = float(TweakControls.value(&"environment.pan_sensitivity", 1.0))
	_grid_scale = _map_nav.scale
	_grid_root.scale = Vector2.ONE * _grid_scale
	_grid_root.position = _map_nav.root_position()
	if _juice != null:
		_juice.refresh_base()
	_apply_live_tweak_presentation()
	_refresh_map_navigation_overlay()


func _refresh_map_navigation_overlay() -> void:
	if _map_navigation_overlay == null or not is_instance_valid(_map_navigation_overlay):
		return
	var viewport := get_viewport_rect().size
	var tutorial_holding := _tutorial_holding_battle()
	var battle_running := model == null or model.result == BattleModel.Result.RUNNING
	_map_navigation_overlay.set_context(
		viewport.y > viewport.x,
		_map_nav.has_pan_range() and battle_running and not _battle_confirmation_active,
		not tutorial_holding and not _battle_confirmation_active and battle_running,
	)


## Refit to the live viewport, clamp pan, then relayout screen-owned UI.
func _relayout() -> void:
	if _stage == null or _grid_root == null:
		return
	var viewport := get_viewport_rect().size
	_map_nav.relayout(_stage, viewport)
	_apply_map_transform()
	if _backdrop != null:
		_backdrop.size = viewport
	if _defeat_ambient != null and is_instance_valid(_defeat_ambient):
		_defeat_ambient.position = Vector2.ZERO
		_defeat_ambient.size = viewport
	BATTLE_HUD_PRESENTER.relayout(_hud, viewport)
	if _portrait_flash != null:
		_portrait_flash.position = Vector2((viewport.x - PORTRAIT_FLASH_PX) * 0.5, 56.0)
	if _continue_btn != null and is_instance_valid(_continue_btn):
		_continue_btn.custom_minimum_size = _terminal_continue_size(viewport)
		_continue_btn.reset_size()
		_continue_btn.position = Vector2(
			(viewport.x - _continue_btn.get_combined_minimum_size().x) * 0.5,
			viewport.y * 0.5 + 120.0
		)
	if _deploy_bar != null:
		_deploy_bar.relayout()
	if _controls != null:
		_controls.relayout()
	if _map_navigation_overlay != null:
		_map_navigation_overlay.relayout()
		_refresh_map_navigation_overlay()
	if _tutorial != null and is_instance_valid(_tutorial):
		_tutorial.call("relayout")
	if _juice != null:
		_juice.relayout(viewport)
	_apply_live_tweak_presentation()


func _build_hud() -> void:
	_hud = BATTLE_HUD_PRESENTER.create(HUD_FONT_SIZE, HUD_Z, get_viewport_rect().size)
	add_child(_hud)
	_apply_live_tweak_presentation()


func _on_tweak_value_changed(identifier: StringName, _value: Variant) -> void:
	var key := String(identifier)
	if key.begins_with("player.") and _base_op_defs.size() > 0:
		TweakControls.apply_operator_definitions(_op_defs, _base_op_defs)
	elif key.begins_with("enemies.") and _base_enemy_defs.size() > 0:
		TweakControls.apply_enemy_definitions(_enemy_defs, _base_enemy_defs)
	_apply_live_tweak_presentation()
	_refresh_hud_copy()


func _apply_live_tweak_presentation() -> void:
	if _backdrop != null:
		var backdrop: Color = TweakControls.value(
			&"environment.backdrop_color", BACKDROP_COLOR,
		)
		var brightness := float(TweakControls.value(
			&"environment.backdrop_brightness", 1.0,
		))
		_backdrop.color = Color(
			backdrop.r * brightness,
			backdrop.g * brightness,
			backdrop.b * brightness,
			backdrop.a,
		)
	if _hud != null:
		var hud_scale := float(TweakControls.value(&"ui.hud_scale", 1.0))
		_hud.pivot_offset = Vector2(_hud.size.x * 0.5, 0.0)
		_hud.scale = Vector2.ONE * hud_scale
		_hud.modulate.a = float(TweakControls.value(&"ui.hud_opacity", 1.0))
	if _map_navigation_overlay != null:
		_map_navigation_overlay.modulate.a = float(TweakControls.value(
			&"ui.map_hint_opacity", 1.0,
		))
	if _juice != null:
		_juice.modulate.a = float(TweakControls.value(&"environment.vfx_opacity", 1.0))
	if _grid_root == null:
		return
	var terrain_tint: Color = TweakControls.value(&"environment.terrain_tint", Color.WHITE)
	var terrain_opacity := float(TweakControls.value(&"environment.terrain_opacity", 1.0))
	var terrain := _grid_root.get_node_or_null("ProtoIsometricTerrain") as CanvasItem
	if terrain != null:
		terrain.modulate = Color(terrain_tint, terrain_opacity)
	var landmark_scale := float(TweakControls.value(&"environment.landmark_scale", 1.0))
	var restoration_opacity := float(TweakControls.value(
		&"environment.restoration_opacity", 0.88,
	))
	for child: Node in _grid_root.get_children():
		if child.name.begins_with("SpawnLandmark") or child.name.begins_with("CoreLandmark"):
			if child is Control:
				var landmark := child as Control
				landmark.pivot_offset = Vector2(landmark.size.x * 0.5, landmark.size.y)
				landmark.scale = Vector2.ONE * landmark_scale
				landmark.self_modulate = Color(terrain_tint, terrain_opacity)
		elif child.name.begins_with("RestorationLattice") and child is CanvasItem:
			(child as CanvasItem).self_modulate = Color(terrain_tint, terrain_opacity)
			(child as CanvasItem).modulate.a = restoration_opacity
	for rect: ColorRect in _enemy_rects.values():
		_apply_actor_visual(rect, false)
	for unit_node: Node2D in _unit_nodes.values():
		var body := unit_node.get_node_or_null("Body") as ColorRect
		if body != null:
			_apply_actor_visual(body, true)


func _apply_actor_visual(body: ColorRect, player: bool) -> void:
	if body == null:
		return
	var prefix := "player" if player else "enemies"
	var visual_scale := float(TweakControls.value(
		StringName("%s.visual_scale" % prefix), 1.0,
	))
	var tint: Color = TweakControls.value(
		StringName("%s.visual_tint" % prefix), Color.WHITE,
	)
	body.pivot_offset = Vector2(body.size.x * 0.5, body.size.y)
	body.scale = Vector2.ONE * visual_scale
	body.self_modulate = tint
	var shadow := body.get_node_or_null("Shadow") as CanvasItem
	if shadow != null:
		shadow.self_modulate.a = float(TweakControls.value(
			&"environment.shadow_opacity", 1.0,
		))


func _project() -> void:
	for e: EnemyState in model.enemies:
		if e.alive and not _enemy_rects.has(e.id):
			_enemy_rects[e.id] = _make_enemy_rect(e)
			_enemy_damage_feedback.register(e)
		elif not e.alive and _enemy_rects.has(e.id):
			if _enemy_damage_feedback.retain_dead(e):
				_update_hp_bar(_enemy_rects[e.id], _enemy_rects[e.id].size.x, e.hp, e.hp_max)
				continue
			_enemy_rects[e.id].queue_free()
			_enemy_rects.erase(e.id)
			_enemy_anim_keys.erase(e.id)
			_enemy_blend_frames.erase(e.id)
			_enemy_damage_feedback.remove(e.id)
		if e.alive:
			var pos := Pathing.position_of(model.path_for(e.path_idx), e.progress_units)
			var center_p := pos + Vector2.ONE * 0.5
			var rect: ColorRect = _enemy_rects[e.id]
			# feet on the face: bottom-center anchored at the projected point
			rect.position = (
				IsoProjection.project(center_p)
				+ Vector2(-rect.size.x * 0.5, IsoProjection.FEET_OFFSET - rect.size.y)
			)
			rect.z_index = IsoProjection.entity_z(center_p)
			if not _enemy_damage_feedback.is_staggered(model, e):
				EnemyAnimator.refresh(
					e,
					model,
					rect,
					_enemy_damage_feedback.animation_seconds(_enemy_anim_seconds, e.id),
					_enemy_anim_keys,
					_enemy_blend_frames,
					_enemy_defs
				)
			_update_hp_bar(rect, rect.size.x, e.hp, e.hp_max)
			_apply_actor_visual(rect, false)
	_project_traps()
	_project_units()
	_project_tracers()
	_refresh_hud_copy()


func _refresh_hud_copy() -> void:
	if _hud == null or model == null:
		return
	var s := model.snapshot()
	_hud.text = BATTLE_HUD_PRESENTER.text_for(s, get_viewport_rect().size)
	if TweakControls.has_gameplay_tweaks():
		_hud.text += "  [TWEAKED]"
	if int(s["result"]) == BattleModel.Result.CLEAR:
		_hud.text += "  %d*" % int(s["stars"])


## EnemyAnimator owns body art/state/direction/shadow; this view owns HP bars.
func _make_enemy_rect(e: EnemyState) -> ColorRect:
	var rect := EnemyAnimator.make_body(e, model, _enemy_defs)
	_add_hp_bar(rect, rect.size.x, true)
	_grid_root.add_child(rect)
	return rect


## Traps use distinct cell glyphs and disappear with their model record.
func _project_traps() -> void:
	var live: Dictionary = {}
	for t: TrapState in model.traps:
		live[t.id] = true
		if not _trap_rects.has(t.id):
			_trap_rects[t.id] = _make_trap_rect(t)
	for trap_id: int in _trap_rects.keys():
		if not live.has(trap_id):
			var rect := _trap_rects[trap_id] as ColorRect
			# an ON_ENTER trap only leaves the model by exhausting its final
			# charge — the sprung frame must outlive the model entry (J11),
			# so the juice layer adopts the rect and frees it after
			if int(_trap_kinds.get(trap_id, -1)) == TrapDef.Trigger.ON_ENTER and _juice != null:
				var sprite := rect.get_node_or_null("Sprite") as TextureRect
				var sprung_tex := Art.texture(&"trap_spike_sprung")
				if sprite != null and sprung_tex != null:
					sprite.texture = sprung_tex
				_juice.sprung(rect, true)
			else:
				rect.queue_free()
			_trap_rects.erase(trap_id)


func _make_trap_rect(t: TrapState) -> ColorRect:
	_trap_kinds[t.id] = t.trigger
	var rect := ColorRect.new()
	rect.name = "Trap%d" % t.id
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# traps sit on GROUND path cells only — never lifted
	var face := IsoProjection.face_center(t.cell)
	var art_id := &"trap_tar" if t.trigger == TrapDef.Trigger.CELL_AURA else &"trap_spike_armed"
	var tex := Art.texture(art_id)
	if tex != null:
		rect.color = Color(0, 0, 0, 0)
		var art_size := Art.size(art_id)
		if art_size == Vector2i.ZERO:
			art_size = Vector2i(tex.get_width(), tex.get_height())
		rect.size = Vector2(art_size) * SPRITE_SCALE
		rect.position = face - rect.size * 0.5
		var sprite := TextureRect.new()
		sprite.name = "Sprite"
		sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sprite.texture = tex
		sprite.stretch_mode = TextureRect.STRETCH_SCALE
		sprite.size = rect.size
		rect.add_child(sprite)
	elif t.trigger == TrapDef.Trigger.CELL_AURA:
		rect.color = TAR_OVERLAY_COLOR
		rect.size = Vector2(IsoProjection.TILE_W - 2.0, IsoProjection.TILE_H - 2.0)
		rect.position = face - rect.size * 0.5
	else:
		rect.color = TRAP_SPIKE_COLOR
		rect.size = Vector2.ONE * TRAP_SPIKE_PX
		rect.position = face - rect.size * 0.5
		var core := ColorRect.new()
		core.mouse_filter = Control.MOUSE_FILTER_IGNORE
		core.color = TRAP_SPIKE_CORE
		core.size = Vector2.ONE * (TRAP_SPIKE_PX * 0.35)
		core.position = (rect.size - core.size) * 0.5
		rect.add_child(core)
	rect.z_index = IsoProjection.tile_z(t.cell) + 1
	_grid_root.add_child(rect)
	return rect



## Ranged attacks leave a short-lived unit-to-target tracer.
func _project_tracers() -> void:
	for u: UnitState in model.units:
		var is_ranged := (
			u.op_class == OperatorDef.OpClass.SNIPER or u.op_class == OperatorDef.OpClass.CASTER
		)
		if not is_ranged:
			continue
		if (
			u.alive
			and u.last_attack_tick >= 0
			and u.last_attack_tick != int(_tracer_seen_tick.get(u.id, -1))
		):
			_tracer_seen_tick[u.id] = u.last_attack_tick
			_tracer_frames_left[u.id] = cfg.tracer_frames
			var line: Line2D = _tracer_lines.get(u.id)
			if line == null:
				line = Line2D.new()
				line.width = 3.0
				line.default_color = TRACER_COLOR
				_grid_root.add_child(line)
				_tracer_lines[u.id] = line
			line.z_index = IsoProjection.entity_z(Vector2(u.cell) + Vector2.ONE * 0.5)
			line.points = PackedVector2Array(
				[
					IsoProjection.face_center(u.cell, _is_lifted_cell(u.cell)),
					IsoProjection.face_center(u.last_attack_cell),
				]
			)
		# aging happens in _process (rule 10, P14) — here we only project
		if _tracer_lines.has(u.id):
			(_tracer_lines[u.id] as Line2D).visible = int(_tracer_frames_left.get(u.id, 0)) > 0


func _project_units() -> void:
	for u: UnitState in model.units:
		if u.alive and not _unit_nodes.has(u.id):
			_unit_nodes[u.id] = _make_unit_node(u)
		elif not u.alive and _unit_nodes.has(u.id):
			_unit_nodes[u.id].queue_free()
			_unit_nodes.erase(u.id)
		if u.alive:
			var body := (_unit_nodes[u.id] as Node2D).get_node("Body") as ColorRect
			_refresh_unit_sprite(u, body)
			_update_hp_bar(body, body.size.x, u.hp, u.hp_max)
			_apply_actor_visual(body, true)
			_skill_ready_feedback.update(body, u, SP_BAR_FILL, SP_FULL_FLASH)
		_detect_skill_trigger(u)


func _operator_visual_template_id(u: UnitState) -> StringName:
	return OPERATOR_VISUAL_CATALOG_SCRIPT.template_for_unit(
		u.op_id, u.portrait_asset_id, u.hero_id, u.id, u.class_id,
	)


func _refresh_unit_sprite(u: UnitState, body: ColorRect) -> void:
	var sprite := body.get_node_or_null("Sprite") as TextureRect
	if sprite == null:
		return
	_refresh_unit_facing_chevron(u, body)
	var visual_template_id := _operator_visual_template_id(u)
	var animation := OPERATOR_VISUAL_CATALOG_SCRIPT.get_animation(visual_template_id)
	var animated := (
		animation != null
		and OPERATOR_ANIMATOR_SCRIPT.apply(u, model.tick, _operator_anim_seconds, sprite, animation)
	)
	if animated:
		if not bool(body.get_meta(&"operator_animation", false)):
			_activate_unit_animation_body(body, sprite, animation, visual_template_id)
		return
	var def: OperatorDef = _op_defs.get(u.op_id)
	if def == null:
		return
	sprite.flip_h = u.facing == UnitState.Facing.LEFT
	if u.last_attack_tick >= 0 and u.last_attack_tick != int(_unit_attack_seen.get(u.id, -1)):
		_unit_attack_seen[u.id] = u.last_attack_tick
		_attack_pose_left[u.id] = ATTACK_POSE_FRAMES
	# aging happens in _process (rule 10, P14) — here we only pick the frame
	var frame := 0
	if int(_attack_pose_left.get(u.id, 0)) > 0:
		frame = 2
	else:
		frame = (Engine.get_process_frames() / IDLE_BOB_FRAMES + u.id) % 2
	var art_id := u.sprite_id if not u.sprite_id.is_empty() else def.sprite_id
	var tex := Art.texture(art_id, frame)
	if tex != null and sprite.texture != tex:
		sprite.texture = tex


func _refresh_unit_facing_chevron(u: UnitState, body: ColorRect) -> void:
	var chevron := body.get_parent().get_node_or_null("FacingChevron") as Polygon2D
	if chevron == null:
		return
	var dir := _operator_facing_screen_direction(u.facing)
	chevron.position = dir * (maxf(UNIT_PX, body.size.x) * 0.5 + 6.0)
	chevron.rotation = dir.angle()


func _operator_facing_screen_direction(facing: int) -> Vector2:
	var grid_direction := (
		Vector2.UP
		if OPERATOR_ANIMATOR_SCRIPT.direction_for_facing(facing) == &"ne"
		else Vector2.LEFT
	)
	return IsoProjection.project(grid_direction).normalized()


func _activate_unit_animation_body(
	body: ColorRect,
	sprite: TextureRect,
	animation: OperatorAnimationDef,
	visual_template_id: StringName,
) -> void:
	body.color = Color(0.0, 0.0, 0.0, 0.0)
	body.size = OPERATOR_ANIMATOR_SCRIPT.body_size(animation)
	body.position = Vector2(
		-body.size.x * 0.5,
		IsoProjection.FEET_OFFSET - body.size.y * animation.pivot.y,
	)
	body.set_meta(&"operator_animation", true)
	body.set_meta(&"operator_template_id", visual_template_id)
	sprite.size = body.size
	sprite.flip_h = false
	var shadow := body.get_node_or_null("Shadow") as Polygon2D
	if shadow != null:
		shadow.position = Vector2(body.size.x * 0.5, body.size.y)
	var hp_bar := body.get_node_or_null("HpBarBg") as ColorRect
	if hp_bar != null:
		BATTLE_HEALTH_BAR_SCRIPT.layout(body, body.size.x)
	var sp_bar := body.get_node_or_null("SpBarBg") as ColorRect
	if sp_bar != null:
		_layout_sp_bar(body)
	var chevron := body.get_parent().get_node_or_null("FacingChevron") as Polygon2D
	if chevron != null:
		chevron.position = chevron.position.normalized() * (maxf(UNIT_PX, body.size.x) * 0.5 + 6.0)


## Skill trigger flashes the portrait, bursts at the unit, and plays its sting.
func _detect_skill_trigger(u: UnitState) -> void:
	var seen := int(_skill_seen_tick.get(u.id, -1))
	if u.skill_triggered_tick <= seen:
		return
	_skill_seen_tick[u.id] = u.skill_triggered_tick
	Sfx.play(String(u.skill_id))
	if _juice != null:
		if u.skill_effect == SkillDef.Effect.HEAL_TARGET and u.skill_target_unit_id >= 0:
			var target := model.unit_by_id(u.skill_target_unit_id)
			if target != null:
				_juice.heal_burst(
					IsoProjection.face_center(target.cell, _is_lifted_cell(target.cell))
				)
		else:
			_juice.skill_burst(IsoProjection.face_center(u.cell, _is_lifted_cell(u.cell)))
	var def: OperatorDef = _op_defs.get(u.op_id)
	var op_class := def.op_class if def != null else OperatorDef.OpClass.GUARD
	_portrait_flash.color = BattlePalette.OPERATOR_CLASS[op_class]
	_portrait_flash.visible = true
	_portrait_flash_frames = cfg.skill_flash_frames


func _add_hp_bar(
	body: ColorRect,
	width: float,
	enemy: bool = false,
) -> void:
	BATTLE_HEALTH_BAR_SCRIPT.add_to(body, width, enemy)


func _update_hp_bar(body: ColorRect, width: float, hp: int, hp_max: int) -> void:
	BATTLE_HEALTH_BAR_SCRIPT.update(body, width, hp, hp_max)
	var bar := body.get_node_or_null("HpBarBg") as ColorRect
	if bar != null:
		bar.pivot_offset = bar.size * 0.5
		bar.scale = Vector2(
			float(TweakControls.value(&"ui.health_bar_width_scale", 1.0)),
			float(TweakControls.value(&"ui.health_bar_height_scale", 1.0)),
		)


func _add_sp_bar(body: ColorRect) -> void:
	var bg := ColorRect.new()
	bg.name = "SpBarBg"
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.color = SP_BAR_BG
	body.add_child(bg)
	var fill := ColorRect.new()
	fill.name = "SpBarFill"
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.color = SP_BAR_FILL
	bg.add_child(fill)
	_layout_sp_bar(body)


func _layout_sp_bar(body: ColorRect) -> void:
	var bg := body.get_node("SpBarBg") as ColorRect
	var bar_width := body.size.x * SP_BAR_WIDTH_SCALE
	bg.size = Vector2(bar_width, SP_BAR_HEIGHT)
	bg.position = Vector2((body.size.x - bar_width) * 0.5, body.size.y + 3.0)
	var fill := bg.get_node("SpBarFill") as ColorRect
	fill.size.y = SP_BAR_HEIGHT


func _make_unit_node(u: UnitState) -> Node2D:
	var node := Node2D.new()
	node.position = IsoProjection.face_center(u.cell, _is_lifted_cell(u.cell))
	node.z_index = IsoProjection.operator_z(Vector2(u.cell) + Vector2.ONE * 0.5)
	var rect := ColorRect.new()
	rect.name = "Body"
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var def: OperatorDef = _op_defs.get(u.op_id)
	var op_class := def.op_class if def != null else OperatorDef.OpClass.GUARD
	var visual_template_id := _operator_visual_template_id(u)
	var animation := OPERATOR_VISUAL_CATALOG_SCRIPT.get_animation(visual_template_id)
	var direction := OPERATOR_ANIMATOR_SCRIPT.direction_for_facing(u.facing)
	var animation_id := (
		StringName(animation.idle_by_direction.get(direction, &"")) if animation != null else &""
	)
	var tex := Art.texture(animation_id, 0) if not animation_id.is_empty() else null
	var animated := tex != null and animation != null
	if not animated:
		tex = Art.texture(def.sprite_id, 0) if def != null else null
	if tex != null:
		rect.color = Color(0, 0, 0, 0)
		rect.size = (
			OPERATOR_ANIMATOR_SCRIPT.body_size(animation)
			if animated
			else Vector2.ONE * (tex.get_width() * SPRITE_SCALE)
		)
		var sprite := TextureRect.new()
		sprite.name = "Sprite"
		sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sprite.texture = tex
		sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sprite.stretch_mode = TextureRect.STRETCH_SCALE
		sprite.size = rect.size
		sprite.flip_h = false if animated else u.facing == UnitState.Facing.LEFT
		rect.add_child(sprite)
		if animated:
			rect.set_meta(&"operator_animation", true)
			rect.set_meta(&"operator_template_id", visual_template_id)
	else:
		rect.color = BattlePalette.OPERATOR_CLASS[op_class]
		rect.size = Vector2(UNIT_PX, UNIT_PX)
	# Feet stay on the face through each admitted animation definition's versioned
	# pivot; legacy sprites remain bottom-center anchored exactly as before.
	var pivot_y := animation.pivot.y if animated else 1.0
	rect.position = Vector2(-rect.size.x * 0.5, IsoProjection.FEET_OFFSET - rect.size.y * pivot_y)
	EnemyAnimator.add_shadow(rect, false)
	_add_hp_bar(rect, rect.size.x)
	if u.sp_cost > 0:
		_add_sp_bar(rect)
	node.add_child(rect)
	var chevron := Polygon2D.new()
	chevron.name = "FacingChevron"
	chevron.color = CHEVRON_COLOR
	chevron.polygon = PackedVector2Array([Vector2(-5, -7), Vector2(-5, 7), Vector2(7, 0)])
	var dir := _operator_facing_screen_direction(u.facing)
	chevron.position = dir * (maxf(UNIT_PX, rect.size.x) * 0.5 + 6.0)
	chevron.rotation = dir.angle()
	node.add_child(chevron)
	_grid_root.add_child(node)
	return node
