extends CanvasLayer

signal value_changed(identifier: StringName, value: Variant)
signal persistence_state_changed(state: StringName)
signal panel_visibility_changed(open: bool)

const Catalog := preload("res://scripts/tuning/runtime_tweak_catalog.gd")
const PanelType := preload("res://scripts/tuning/runtime_tweak_panel.gd")
const Style := preload("res://scripts/ui/components/lunaris_ops_style.gd")
const SAVE_PATH := "user://runtime_tweaks.cfg"
const SAVE_DEBOUNCE_SECONDS := 0.35
const LAUNCHER_IDLE_OPACITY := 0.5
const LAUNCHER_HOVER_OPACITY := 1.0
const LAUNCHER_MARGIN := Vector2(16.0, 16.0)

var launcher_button: Button = null
var panel: RuntimeTweakPanel = null
var persistence_state: StringName = &"SAVED"

var _values: Dictionary = {}
var _launcher_docked := false
var _save_remaining := -1.0
var _paused_before_open := false
var _text_scale_baseline := 1.0
var _applying_text_scale := false
var _audio_linear_baselines: Dictionary = {}
var _audio_mute_baselines: Dictionary = {}
var _audio_last_linear: Dictionary = {}
var _audio_last_mute: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 1000
	var errors := Catalog.validation_errors()
	if not errors.is_empty():
		push_error("TweakControls catalog is invalid: %s" % "; ".join(errors))
	_values = Catalog.baseline_values()
	_capture_global_baselines()
	_load_persisted_values()
	_build_panel()
	_build_launcher()
	get_viewport().size_changed.connect(_relayout)
	_relayout()
	_apply_all_global_tweaks()
	set_process(true)


func _process(delta: float) -> void:
	_sync_audio_external_changes()
	if _save_remaining < 0.0:
		return
	_save_remaining = maxf(_save_remaining - maxf(delta, 0.0), 0.0)
	if is_zero_approx(_save_remaining):
		flush_now()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_F10:
			toggle_panel()
			get_viewport().set_input_as_handled()
			return
	if is_panel_open() and event.is_action_pressed(&"ui_cancel"):
		close_panel()
		get_viewport().set_input_as_handled()


func value(identifier: StringName, fallback: Variant = null) -> Variant:
	return _values.get(identifier, fallback)


func descriptor(identifier: StringName) -> Dictionary:
	return Catalog.descriptor(identifier)


func set_value(identifier: StringName, candidate: Variant) -> Dictionary:
	var entry := Catalog.descriptor(identifier)
	if entry.is_empty():
		return {&"ok": false, &"error": "unknown tweak", &"value": null}
	var checked := Catalog.sanitize(entry, candidate)
	if not bool(checked.get(&"ok", false)):
		return {&"ok": false, &"error": "invalid value", &"value": entry[&"default"]}
	var next: Variant = checked[&"value"]
	if _values_equal(entry, _values[identifier], next):
		return {&"ok": true, &"changed": false, &"value": next}
	_values[identifier] = next
	_apply_global_tweak(identifier)
	value_changed.emit(identifier, next)
	_schedule_save()
	return {&"ok": true, &"changed": true, &"value": next}


func reset_value(identifier: StringName) -> bool:
	var entry := Catalog.descriptor(identifier)
	if entry.is_empty():
		return false
	return bool(set_value(identifier, entry[&"default"]).get(&"changed", false))


func reset_all() -> int:
	var changed := 0
	for entry: Dictionary in Catalog.descriptors():
		if reset_value(entry[&"id"]):
			changed += 1
	return changed


func modified_count() -> int:
	var count := 0
	for entry: Dictionary in Catalog.descriptors():
		if not _values_equal(entry, _values[entry[&"id"]], entry[&"default"]):
			count += 1
	return count


func has_gameplay_tweaks() -> bool:
	for entry: Dictionary in Catalog.descriptors():
		if entry[&"integrity"] != &"GAMEPLAY":
			continue
		if not _values_equal(entry, _values[entry[&"id"]], entry[&"default"]):
			return true
	return false


func open_panel() -> bool:
	if panel == null or panel.visible:
		return false
	_paused_before_open = get_tree().paused
	get_tree().paused = true
	panel.visible = true
	panel.refresh()
	panel.close_button.grab_focus.call_deferred()
	panel_visibility_changed.emit(true)
	return true


func close_panel() -> bool:
	if panel == null or not panel.visible:
		return false
	panel.visible = false
	flush_now()
	get_tree().paused = _paused_before_open
	launcher_button.grab_focus.call_deferred()
	panel_visibility_changed.emit(false)
	return true


func toggle_panel() -> bool:
	return close_panel() if is_panel_open() else open_panel()


func is_panel_open() -> bool:
	return panel != null and panel.visible


func duplicate_definitions(source: Dictionary) -> Dictionary:
	var result := {}
	for identifier: Variant in source:
		var definition := source[identifier] as Resource
		result[identifier] = definition.duplicate(true) if definition != null else null
	return result


func apply_game_config(config: GameConfig) -> void:
	if config == null:
		return
	config.base_hp_start = int(value(&"gameplay.base_hp", config.base_hp_start))
	config.dp_cap = int(value(&"gameplay.dp_cap", config.dp_cap))
	config.dp_start = mini(int(value(&"gameplay.starting_dp", config.dp_start)), config.dp_cap)
	config.dp_regen_interval_ticks = maxi(
		1,
		roundi(float(value(&"gameplay.dp_regen_seconds", 1.0)) * config.ticks_per_second),
	)
	config.retreat_refund_percent = int(value(
		&"gameplay.retreat_refund_percent", config.retreat_refund_percent,
	))
	config.sp_progress_interval_ticks = maxi(
		1,
		roundi(float(value(&"gameplay.sp_regen_seconds", 1.0)) * config.ticks_per_second),
	)
	config.damage_stagger_ticks = int(value(
		&"gameplay.damage_stagger_ticks", config.damage_stagger_ticks,
	))


func apply_stage(stage: StageDef) -> void:
	if stage == null:
		return
	var source_waves: Array = stage.get_meta(&"_tweak_source_waves", [])
	if source_waves.is_empty():
		source_waves = stage.waves.duplicate(true)
		stage.set_meta(&"_tweak_source_waves", source_waves.duplicate(true))
	var source_starts: PackedInt32Array = stage.get_meta(
		&"_tweak_source_wave_starts", PackedInt32Array(),
	)
	if source_starts.is_empty() and not stage.wave_starts.is_empty():
		source_starts = stage.wave_starts.duplicate()
		stage.set_meta(&"_tweak_source_wave_starts", source_starts.duplicate())
	if not stage.has_meta(&"_tweak_source_leak_limit"):
		stage.set_meta(&"_tweak_source_leak_limit", stage.leak_limit)
	var timing := float(value(&"gameplay.spawn_timing_multiplier", 1.0))
	var quantity := int(value(&"gameplay.spawn_count_multiplier", 1))
	var tuned_waves: Array[Dictionary] = []
	for source: Dictionary in source_waves:
		for copy_index: int in quantity:
			var entry := source.duplicate(true)
			entry["tick"] = maxi(0, roundi(float(source["tick"]) * timing) + copy_index)
			tuned_waves.append(entry)
	stage.waves = tuned_waves
	var tuned_starts := PackedInt32Array()
	for source_tick: int in source_starts:
		tuned_starts.append(maxi(0, roundi(float(source_tick) * timing)))
	stage.wave_starts = tuned_starts
	stage.leak_limit = maxi(
		0,
		int(stage.get_meta(&"_tweak_source_leak_limit"))
			+ int(value(&"gameplay.leak_limit_bonus", 0)),
	)


func apply_operator_definitions(definitions: Dictionary, baselines: Dictionary) -> void:
	for identifier: Variant in definitions:
		var current := definitions[identifier] as OperatorDef
		var base := baselines.get(identifier) as OperatorDef
		if current == null or base == null:
			continue
		current.hp = maxi(1, roundi(base.hp * float(value(&"player.health_multiplier", 1.0))))
		current.atk = maxi(0, roundi(base.atk * float(value(&"player.attack_multiplier", 1.0))))
		current.defense = maxi(0, roundi(base.defense * float(value(&"player.defense_multiplier", 1.0))))
		current.resistance_permille = clampi(
			base.resistance_permille + int(value(&"player.resistance_bonus_permille", 0)),
			0,
			1000,
		)
		current.atk_interval_ticks = maxi(
			1,
			roundi(base.atk_interval_ticks / float(value(&"player.attack_speed_multiplier", 1.0))),
		)
		current.dp_cost = maxi(
			1,
			roundi(base.dp_cost * float(value(&"player.deployment_cost_multiplier", 1.0))),
		)
		current.block = maxi(0, base.block + int(value(&"player.block_bonus", 0)))
		current.skill = base.skill.duplicate(true) as SkillDef if base.skill != null else null
		if current.skill != null:
			current.skill.sp_cost = maxi(
				1,
				roundi(base.skill.sp_cost * float(value(&"player.skill_cost_multiplier", 1.0))),
			)


func apply_enemy_definitions(definitions: Dictionary, baselines: Dictionary) -> void:
	for identifier: Variant in definitions:
		var current := definitions[identifier] as EnemyDef
		var base := baselines.get(identifier) as EnemyDef
		if current == null or base == null:
			continue
		current.hp = maxi(1, roundi(base.hp * float(value(&"enemies.health_multiplier", 1.0))))
		current.atk = maxi(0, roundi(base.atk * float(value(&"enemies.attack_multiplier", 1.0))))
		current.defense = maxi(0, roundi(base.defense * float(value(&"enemies.defense_multiplier", 1.0))))
		current.resistance_permille = clampi(
			base.resistance_permille + int(value(&"enemies.resistance_bonus_permille", 0)),
			0,
			1000,
		)
		current.atk_interval_ticks = maxi(
			1,
			roundi(base.atk_interval_ticks / float(value(&"enemies.attack_speed_multiplier", 1.0))),
		)
		current.speed_tiles_per_s = maxf(
			0.01,
			base.speed_tiles_per_s * float(value(&"enemies.movement_speed_multiplier", 1.0)),
		)
		current.leak_damage = maxi(
			0,
			roundi(base.leak_damage * float(value(&"enemies.leak_damage_multiplier", 1.0))),
		)


func flush_now() -> bool:
	_save_remaining = -1.0
	var config := ConfigFile.new()
	config.set_value("runtime_tweaks", "schema_version", 1)
	for entry: Dictionary in Catalog.descriptors():
		var identifier: StringName = entry[&"id"]
		if _values_equal(entry, _values[identifier], entry[&"default"]):
			continue
		config.set_value("values", String(identifier), _values[identifier])
	var error := config.save(SAVE_PATH)
	persistence_state = &"SAVED" if error == OK else &"NOT_SAVED"
	persistence_state_changed.emit(persistence_state)
	return error == OK


func _build_panel() -> void:
	panel = PanelType.new() as RuntimeTweakPanel
	panel.name = "RuntimeTweakPanel"
	add_child(panel)
	panel.configure(self)
	panel.close_requested.connect(close_panel)


func _build_launcher() -> void:
	launcher_button = Button.new()
	launcher_button.name = "TweakControlsButton"
	launcher_button.text = "TWEAK CONTROLS"
	launcher_button.tooltip_text = "Open runtime tweak controls (F10)"
	launcher_button.clip_text = true
	launcher_button.focus_mode = Control.FOCUS_ALL
	launcher_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	launcher_button.custom_minimum_size = Vector2(174.0, 42.0)
	launcher_button.add_theme_font_size_override(&"font_size", 12)
	launcher_button.add_theme_color_override(&"font_color", Color("d9fbff"))
	launcher_button.add_theme_color_override(&"font_hover_color", Color.WHITE)
	launcher_button.add_theme_color_override(&"font_pressed_color", Color.WHITE)
	Style.apply_simple_gold_button(launcher_button, false, 8.0, 12, 5.0)
	launcher_button.z_index = 100
	launcher_button.modulate.a = LAUNCHER_IDLE_OPACITY
	launcher_button.mouse_entered.connect(_on_launcher_mouse_entered)
	launcher_button.mouse_exited.connect(_on_launcher_mouse_exited)
	launcher_button.pressed.connect(toggle_panel)
	add_child(launcher_button)


func dock_launcher(container: Container) -> Button:
	if launcher_button == null or container == null:
		return null
	if launcher_button.get_parent() != container:
		launcher_button.reparent(container, false)
	_launcher_docked = true
	launcher_button.position = Vector2.ZERO
	launcher_button.custom_minimum_size = Vector2(0.0, 52.0)
	launcher_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	launcher_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	launcher_button.modulate.a = 1.0
	_relayout()
	return launcher_button


func undock_launcher(container: Container = null) -> void:
	if launcher_button == null:
		return
	if container != null and launcher_button.get_parent() != container:
		return
	if launcher_button.get_parent() != self:
		launcher_button.reparent(self, false)
	_launcher_docked = false
	launcher_button.custom_minimum_size = Vector2(174.0, 42.0)
	launcher_button.size_flags_horizontal = Control.SIZE_FILL
	launcher_button.size_flags_vertical = Control.SIZE_FILL
	launcher_button.disabled = false
	launcher_button.focus_mode = Control.FOCUS_ALL
	launcher_button.focus_neighbor_left = NodePath()
	launcher_button.focus_neighbor_top = NodePath()
	launcher_button.focus_neighbor_right = NodePath()
	launcher_button.focus_neighbor_bottom = NodePath()
	launcher_button.focus_next = NodePath()
	launcher_button.focus_previous = NodePath()
	launcher_button.modulate.a = LAUNCHER_IDLE_OPACITY
	_relayout()


func _relayout() -> void:
	if launcher_button == null:
		return
	var viewport := get_viewport().get_visible_rect().size
	if _launcher_docked:
		launcher_button.position = Vector2.ZERO
		launcher_button.custom_minimum_size = Vector2(0.0, 52.0)
	else:
		var width := minf(174.0, maxf(120.0, viewport.x - 32.0))
		launcher_button.size = Vector2(width, 42.0)
		launcher_button.position = viewport - launcher_button.size - LAUNCHER_MARGIN
	launcher_button.add_theme_font_size_override(
		&"font_size",
		9
		if _launcher_docked and viewport.x <= 520.0
		else (11 if viewport.y > viewport.x else 12),
	)
	if panel != null:
		panel.call("_relayout")


func _on_launcher_mouse_entered() -> void:
	launcher_button.modulate.a = LAUNCHER_HOVER_OPACITY


func _on_launcher_mouse_exited() -> void:
	launcher_button.modulate.a = 1.0 if _launcher_docked else LAUNCHER_IDLE_OPACITY


func _capture_global_baselines() -> void:
	var text_manager := get_node_or_null("/root/TextScale")
	if text_manager != null:
		_text_scale_baseline = float(text_manager.call("value"))
		if not text_manager.scale_changed.is_connected(_on_external_text_scale_changed):
			text_manager.scale_changed.connect(_on_external_text_scale_changed)
	for bus: StringName in [&"Master", &"Music", &"SFX"]:
		var index := AudioServer.get_bus_index(bus)
		if index < 0:
			continue
		_audio_linear_baselines[bus] = db_to_linear(AudioServer.get_bus_volume_db(index))
		_audio_mute_baselines[bus] = AudioServer.is_bus_mute(index)


func _apply_all_global_tweaks() -> void:
	for identifier: StringName in _values:
		_apply_global_tweak(identifier)


func _apply_global_tweak(identifier: StringName) -> void:
	if identifier == &"ui.text_scale_multiplier":
		var text_manager := get_node_or_null("/root/TextScale")
		if text_manager != null:
			_applying_text_scale = true
			text_manager.call(
				"set_scale",
				_text_scale_baseline * float(value(identifier, 1.0)),
			)
			_applying_text_scale = false
	elif identifier == &"ui.panel_opacity" and panel != null:
		panel.call("_refresh_panel_style")
	elif String(identifier).begins_with("audio."):
		_apply_audio_tweaks()


func _apply_audio_tweaks() -> void:
	_apply_audio_bus(&"Master", float(value(&"audio.master_gain", 1.0)), true)
	_apply_audio_bus(
		&"Music",
		float(value(&"audio.music_gain", 1.0)),
		bool(value(&"audio.music_enabled", true)),
	)
	_apply_audio_bus(
		&"SFX",
		float(value(&"audio.sfx_gain", 1.0)),
		bool(value(&"audio.sfx_enabled", true)),
	)


func _apply_audio_bus(bus: StringName, gain: float, enabled: bool) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index < 0:
		return
	if not _audio_linear_baselines.has(bus):
		_audio_linear_baselines[bus] = db_to_linear(AudioServer.get_bus_volume_db(index))
		_audio_mute_baselines[bus] = AudioServer.is_bus_mute(index)
	var linear := float(_audio_linear_baselines[bus]) * maxf(gain, 0.0)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(linear, 0.001)))
	AudioServer.set_bus_mute(
		index,
		bool(_audio_mute_baselines[bus]) or not enabled or linear <= 0.001,
	)
	_audio_last_linear[bus] = db_to_linear(AudioServer.get_bus_volume_db(index))
	_audio_last_mute[bus] = AudioServer.is_bus_mute(index)


func _sync_audio_external_changes() -> void:
	var changed := false
	for bus: StringName in [&"Master", &"Music", &"SFX"]:
		var index := AudioServer.get_bus_index(bus)
		if index < 0 or not _audio_last_linear.has(bus):
			continue
		var current_linear := db_to_linear(AudioServer.get_bus_volume_db(index))
		var current_mute := AudioServer.is_bus_mute(index)
		if not is_equal_approx(current_linear, float(_audio_last_linear[bus])):
			_audio_linear_baselines[bus] = current_linear
			changed = true
		if current_mute != bool(_audio_last_mute[bus]):
			_audio_mute_baselines[bus] = current_mute
			changed = true
	if changed:
		_apply_audio_tweaks()


func _on_external_text_scale_changed(next_scale: float) -> void:
	if _applying_text_scale:
		return
	_text_scale_baseline = next_scale
	_apply_global_tweak(&"ui.text_scale_multiplier")


func _load_persisted_values() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	for entry: Dictionary in Catalog.descriptors():
		var identifier: StringName = entry[&"id"]
		if not config.has_section_key("values", String(identifier)):
			continue
		var checked := Catalog.sanitize(
			entry,
			config.get_value("values", String(identifier), entry[&"default"]),
		)
		if bool(checked.get(&"ok", false)):
			_values[identifier] = checked[&"value"]


func _schedule_save() -> void:
	_save_remaining = SAVE_DEBOUNCE_SECONDS
	persistence_state = &"SAVING"
	persistence_state_changed.emit(persistence_state)


func _values_equal(entry: Dictionary, first: Variant, second: Variant) -> bool:
	match StringName(entry[&"type"]):
		&"float":
			return is_equal_approx(float(first), float(second))
		&"color":
			return (first as Color).is_equal_approx(second as Color)
	return first == second
