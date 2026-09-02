extends SceneTree

const Catalog := preload("res://scripts/tuning/runtime_tweak_catalog.gd")
const SAVE_PATH := "user://runtime_tweaks.cfg"

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var tweaks := root.get_node_or_null("TweakControls")
	_check(tweaks != null, "TweakControls autoload is unavailable")
	if tweaks == null:
		_finish()
		return
	tweaks.call("reset_all")
	await process_frame
	_check(int(tweaks.call("modified_count")) == 0, "Reset All did not restore a clean baseline")
	_test_catalog()
	_test_launcher_and_modal(tweaks)
	_test_global_settings_composition(tweaks)
	_test_validation_and_persistence(tweaks)
	_test_battle_resource_adapters(tweaks)
	tweaks.call("reset_all")
	tweaks.call("flush_now")
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	_finish()


func _test_catalog() -> void:
	_check(Catalog.validation_errors().is_empty(), "typed tweak catalog failed validation")
	_check(Catalog.descriptors().size() == 58, "catalog does not expose all 58 controls")
	_check(
		Catalog.categories() == [&"UI", &"GAMEPLAY", &"AUDIO", &"PLAYER", &"ENEMIES", &"ENVIRONMENT"],
		"catalog category order changed",
	)
	for category: StringName in Catalog.categories():
		_check(
			not Catalog.descriptors_for_category(category).is_empty(),
			"%s category has no controls" % category,
		)


func _test_launcher_and_modal(tweaks: Node) -> void:
	var launcher := tweaks.get("launcher_button") as Button
	var panel := tweaks.get("panel") as RuntimeTweakPanel
	_check(launcher != null and panel != null, "launcher or panel was not constructed")
	if launcher == null or panel == null:
		return
	var viewport := root.get_visible_rect().size
	_check(launcher.visible, "tweak launcher is not visible")
	_check(launcher.text == "TWEAK CONTROLS", "launcher copy changed")
	_check(_near(launcher.modulate.a, 0.5), "launcher idle opacity is not exactly 50 percent")
	launcher.mouse_entered.emit()
	_check(_near(launcher.modulate.a, 1.0), "launcher does not become opaque on hover")
	launcher.mouse_exited.emit()
	_check(_near(launcher.modulate.a, 0.5), "launcher does not restore 50-percent opacity")
	_check(_near(launcher.position.x + launcher.size.x, viewport.x - 16.0), "launcher is not right anchored")
	_check(_near(launcher.position.y + launcher.size.y, viewport.y - 16.0), "launcher is not bottom anchored")
	_check(panel.category_selector.item_count == 6, "panel does not expose the six requested categories")
	_test_row_typography_and_alignment(panel)
	var original_size := root.size
	root.size = Vector2i(720, 1280)
	tweaks.call("_relayout")
	viewport = root.get_visible_rect().size
	_check(_near(launcher.position.x + launcher.size.x, viewport.x - 16.0), "portrait launcher is not right anchored")
	_check(_near(launcher.position.y + launcher.size.y, viewport.y - 16.0), "portrait launcher is not bottom anchored")
	_check(
		panel.frame.position.y + panel.frame.size.y < launcher.position.y,
		"portrait panel overlaps the always-visible launcher",
	)
	root.size = original_size
	tweaks.call("_relayout")
	_check(not paused, "test unexpectedly started paused")
	_check(bool(tweaks.call("open_panel")), "panel did not open")
	_check(paused and panel.visible, "panel did not pause the SceneTree")
	_check(bool(tweaks.call("close_panel")), "panel did not close")
	_check(not paused and not panel.visible, "panel did not restore the unpaused state")
	paused = true
	_check(bool(tweaks.call("open_panel")), "panel did not open over an existing pause")
	_check(bool(tweaks.call("close_panel")), "panel did not close over an existing pause")
	_check(paused, "panel did not preserve the pre-existing paused state")
	paused = false


func _test_row_typography_and_alignment(panel: RuntimeTweakPanel) -> void:
	var row := panel.rows.get_child(0) as PanelContainer
	_check(row != null, "tweak list does not expose its first row")
	if row == null:
		return
	var label := row.find_child("TweakLabel", true, false) as Label
	var description := row.find_child("TweakDescription", true, false) as Label
	var mode := row.find_child("TweakApplyMode", true, false) as Label
	var slider := row.find_child("TweakSlider", true, false) as HSlider
	var value := row.find_child("TweakValue", true, false) as SpinBox
	var reset := row.find_child("TweakResetButton", true, false) as Button
	_check(label != null and label.get_theme_font_size(&"font_size") == 30, "tweak label typography is not doubled")
	_check(description != null and description.get_theme_font_size(&"font_size") == 24, "tweak description typography is not doubled")
	_check(mode != null and mode.get_theme_font_size(&"font_size") == 22, "tweak apply-mode typography is not doubled")
	for control: Control in [slider, value, reset]:
		_check(control != null, "numeric tweak row is missing a control")
		if control != null:
			_check(
				control.size_flags_vertical == Control.SIZE_SHRINK_CENTER
				and is_equal_approx(control.custom_minimum_size.y, 56.0),
				"%s is not vertically centered at the shared row-control height" % control.name,
			)


func _test_global_settings_composition(tweaks: Node) -> void:
	var text_scale := root.get_node_or_null("TextScale")
	if text_scale != null:
		var original_text_scale := float(text_scale.call("value"))
		tweaks.call("set_value", &"ui.text_scale_multiplier", 1.25)
		text_scale.call("set_scale", 1.2)
		_check(
			_near(float(text_scale.call("value")), 1.5),
			"text-scale tweak did not compose with an external accessibility change",
		)
		tweaks.call("reset_value", &"ui.text_scale_multiplier")
		_check(
			_near(float(text_scale.call("value")), 1.2),
			"resetting text-scale tweak did not preserve the external accessibility value",
		)
		text_scale.call("set_scale", original_text_scale)

	var music_bus := AudioServer.get_bus_index(&"Music")
	if music_bus >= 0:
		var original_linear := db_to_linear(AudioServer.get_bus_volume_db(music_bus))
		var original_mute := AudioServer.is_bus_mute(music_bus)
		tweaks.call("set_value", &"audio.music_gain", 0.5)
		var external_linear := clampf(original_linear * 0.8, 0.1, 1.0)
		AudioServer.set_bus_volume_db(music_bus, linear_to_db(external_linear))
		tweaks.call("_sync_audio_external_changes")
		_check(
			_near(db_to_linear(AudioServer.get_bus_volume_db(music_bus)), external_linear * 0.5),
			"music gain did not compose with an external volume change",
		)
		tweaks.call("reset_value", &"audio.music_gain")
		_check(
			_near(db_to_linear(AudioServer.get_bus_volume_db(music_bus)), external_linear),
			"resetting music gain did not preserve the external volume",
		)
		AudioServer.set_bus_volume_db(music_bus, linear_to_db(original_linear))
		AudioServer.set_bus_mute(music_bus, original_mute)
		tweaks.call("_sync_audio_external_changes")


func _test_validation_and_persistence(tweaks: Node) -> void:
	var rejected: Dictionary = tweaks.call("set_value", &"missing.control", 1)
	_check(not bool(rejected.get(&"ok", false)), "unknown tweak id was accepted")
	var quantized: Dictionary = tweaks.call("set_value", &"player.attack_multiplier", 1.27)
	_check(bool(quantized.get(&"ok", false)), "valid numeric tweak was rejected")
	_check(_near(float(tweaks.call("value", &"player.attack_multiplier")), 1.25), "numeric tweak was not quantized")
	_check(bool(tweaks.call("has_gameplay_tweaks")), "gameplay tweak did not mark integrity")
	_check(bool(tweaks.call("flush_now")), "tweak delta did not persist")
	var config := ConfigFile.new()
	_check(config.load(SAVE_PATH) == OK, "persisted tweak file is unreadable")
	_check(
		_near(float(config.get_value("values", "player.attack_multiplier", 0.0)), 1.25),
		"persisted tweak delta has the wrong value",
	)
	_check(
		not config.has_section_key("values", "ui.hud_scale"),
		"default values were written instead of deltas only",
	)


func _test_battle_resource_adapters(tweaks: Node) -> void:
	tweaks.call("set_value", &"gameplay.base_hp", 24)
	tweaks.call("set_value", &"gameplay.starting_dp", 30)
	tweaks.call("set_value", &"gameplay.dp_cap", 20)
	tweaks.call("set_value", &"gameplay.dp_regen_seconds", 0.5)
	var config := (load("res://data/config/game.tres") as GameConfig).duplicate(true) as GameConfig
	tweaks.call("apply_game_config", config)
	_check(config.base_hp_start == 24, "core-health tweak did not reach GameConfig")
	_check(config.dp_start == 20, "starting DP was not clamped to the tuned cap")
	_check(config.dp_regen_interval_ticks == 15, "DP seconds were not converted to ticks")

	tweaks.call("set_value", &"gameplay.spawn_timing_multiplier", 0.5)
	tweaks.call("set_value", &"gameplay.spawn_count_multiplier", 2)
	tweaks.call("set_value", &"gameplay.leak_limit_bonus", 4)
	var stage := (load("res://data/stages/s1.tres") as StageDef).duplicate(true) as StageDef
	tweaks.call("apply_stage", stage)
	_check(stage.waves.size() == 12, "spawn quantity did not expand the stage deterministically")
	_check(int(stage.waves[0]["tick"]) == 45, "spawn timing did not scale the first entry")
	_check(int(stage.waves[1]["tick"]) == 46, "spawn copies do not have stable tick ordering")
	_check(stage.wave_starts == PackedInt32Array([0, 165]), "wave starts did not scale with spawns")
	_check(stage.leak_limit == 7, "leak-limit bonus did not apply")

	var source_operator := load("res://data/operators/recruit.tres") as OperatorDef
	var operator_baselines := {&"recruit": source_operator.duplicate(true)}
	var operators := {&"recruit": source_operator.duplicate(true)}
	tweaks.call("set_value", &"player.health_multiplier", 1.5)
	tweaks.call("set_value", &"player.deployment_cost_multiplier", 0.5)
	tweaks.call("set_value", &"player.block_bonus", 2)
	tweaks.call("apply_operator_definitions", operators, operator_baselines)
	var operator := operators[&"recruit"] as OperatorDef
	_check(operator.hp == 165, "operator health multiplier did not apply")
	_check(operator.dp_cost == 4, "operator deployment-cost multiplier did not apply")
	_check(operator.block == 3, "operator block bonus did not apply")

	var source_enemy := load("res://data/enemies/grunt.tres") as EnemyDef
	var enemy_baselines := {&"grunt": source_enemy.duplicate(true)}
	var enemies := {&"grunt": source_enemy.duplicate(true)}
	tweaks.call("set_value", &"enemies.health_multiplier", 2.0)
	tweaks.call("set_value", &"enemies.movement_speed_multiplier", 1.5)
	tweaks.call("set_value", &"enemies.leak_damage_multiplier", 3.0)
	tweaks.call("apply_enemy_definitions", enemies, enemy_baselines)
	var enemy := enemies[&"grunt"] as EnemyDef
	_check(enemy.hp == 80, "enemy health multiplier did not apply")
	_check(_near(enemy.speed_tiles_per_s, 1.5), "enemy movement multiplier did not apply")
	_check(enemy.leak_damage == 3, "enemy leak-damage multiplier did not apply")


func _near(actual: float, expected: float) -> bool:
	return absf(actual - expected) <= 0.001


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("RUNTIME_TWEAK_CONTROLS_TEST_OK")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)
