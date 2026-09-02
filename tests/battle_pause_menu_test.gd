extends SceneTree

const LANDSCAPE := Vector2i(1280, 720)
const PREFS_PATH := "user://battle_pause_menu_test.cfg"
const WAIT_SECONDS := 2.0

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = LANDSCAPE
	var game := root.get_node_or_null("Game")
	var i18n := root.get_node_or_null("I18n")
	_check(game != null, "Game autoload is unavailable")
	_check(i18n != null and bool(i18n.call("reload_catalogs")), "localization catalogs failed validation")
	if game == null or i18n == null:
		_finish()
		return
	game.call("set_view_preferences_path", PREFS_PATH)
	game.call("set_run_seed", 9021)
	_check(bool(game.call("start_campaign", false, true)), "pause-menu campaign fixture failed")
	game.call("start_battle", &"s2", true)
	for _frame: int in range(14):
		await process_frame

	var battle := game.get("content") as Node
	var controls := battle.find_child("BattleControls", true, false) as Node if battle != null else null
	var pause_menu := battle.find_child("PauseMenuLayer", true, false) as Control if battle != null else null
	var pause_panel := battle.find_child("PauseMenuPanel", true, false) as PanelContainer if battle != null else null
	var pause_resign := battle.find_child("PauseMenuResignButton", true, false) as Button if battle != null else null
	var pause_settings := battle.find_child("PauseMenuSettingsButton", true, false) as Button if battle != null else null
	var settings := battle.find_child("BattleSettings", true, false) as Control if battle != null else null
	var pause_button := battle.find_child("PauseButton", true, false) as Button if battle != null else null
	var speed_button := battle.find_child("SpeedButton", true, false) as Button if battle != null else null
	var resign_button := battle.find_child("ResignButton", true, false) as Button if battle != null else null
	_check(battle != null and bool(battle.get("startup_succeeded")), "battle did not start")
	_check(
		controls != null and pause_menu != null and pause_panel != null
		and pause_resign != null and pause_settings != null and settings != null,
		"pause menu or Settings UI is missing",
	)
	if controls == null or pause_menu == null or pause_resign == null or pause_settings == null:
		_cleanup(game, battle)
		_finish()
		return

	var menu_buttons := pause_menu.find_children("*", "Button", true, false)
	_check(menu_buttons.size() == 2, "pause menu does not contain exactly two buttons")
	_check(
		pause_resign.text == "RESIGN" and pause_settings.text == "SETTINGS",
		"pause menu actions are not RESIGN and SETTINGS",
	)
	_check(bool(i18n.call("set_locale", &"zh-CN")), "Chinese locale activation failed")
	await process_frame
	_check(
		pause_resign.text == "撤出行动" and pause_settings.text == "设置",
		"pause menu actions did not refresh to Chinese",
	)
	_check(bool(i18n.call("set_locale", &"en-US")), "English locale restoration failed")
	await process_frame
	_check(not pause_menu.visible, "pause menu starts visible")

	var exact_scale := 2.375
	battle.set("ticks_per_frame_scale", exact_scale)
	var escape := _escape_event()
	_check(escape.is_action_pressed(&"ui_cancel"), "Escape is not mapped to ui_cancel")
	controls.call("_unhandled_input", escape)
	await process_frame
	_check(bool(controls.call("pause_menu_active")) and pause_menu.visible, "Escape did not open the pause menu")
	_check(is_equal_approx(float(battle.get("ticks_per_frame_scale")), 0.0), "Escape did not pause battle simulation")
	_check(bool(battle.call("battle_confirmation_active")), "pause menu did not gate battlefield input")
	_check(
		pause_button.disabled and speed_button.disabled and resign_button.disabled,
		"battle commands remain active behind the pause menu",
	)
	_check(pause_settings.has_focus(), "Settings is not the safe default pause-menu focus")
	_check(
		_rect_matches(pause_menu.get_global_rect(), Rect2(Vector2.ZERO, Vector2(LANDSCAPE))),
		"pause menu does not cover the viewport",
	)
	_check(
		Rect2(Vector2.ZERO, Vector2(LANDSCAPE)).encloses(pause_panel.get_global_rect()),
		"pause panel escapes the viewport",
	)

	pause_settings.pressed.emit()
	await _wait_for_settings(settings, &"ACTIVE")
	_check(bool(controls.call("settings_active")) and settings.visible, "SETTINGS did not open the Settings UI")
	_check(not pause_menu.visible, "pause menu remained visible behind Settings")
	_check(is_equal_approx(float(battle.get("ticks_per_frame_scale")), 0.0), "Settings resumed battle simulation")
	controls.call("_unhandled_input", _escape_event())
	await _wait_for_settings(settings, &"CLOSED")
	await process_frame
	_check(
		pause_menu.visible and bool(controls.call("pause_menu_active")),
		"Escape from Settings did not return to the pause menu",
	)
	_check(is_equal_approx(float(battle.get("ticks_per_frame_scale")), 0.0), "closing Settings resumed battle simulation")

	pause_resign.pressed.emit()
	await _wait_for_confirmation(controls, &"active")
	_check(not pause_menu.visible, "pause menu remained visible behind resign confirmation")
	_check(bool(controls.call("cancel_resign_confirmation")), "resign confirmation could not be cancelled")
	await _wait_for_confirmation(controls, &"closed")
	await process_frame
	_check(
		pause_menu.visible and bool(controls.call("pause_menu_active")),
		"cancelled resign did not return to the pause menu",
	)
	_check(is_equal_approx(float(battle.get("ticks_per_frame_scale")), 0.0), "cancelled resign resumed battle simulation")

	controls.call("_unhandled_input", _escape_event())
	await process_frame
	_check(
		not pause_menu.visible and not bool(controls.call("pause_menu_active")),
		"second Escape did not close the pause menu",
	)
	_check(
		is_equal_approx(float(battle.get("ticks_per_frame_scale")), exact_scale),
		"pause menu did not restore the exact prior speed",
	)
	_check(not bool(battle.call("battle_confirmation_active")), "closing pause menu retained the battlefield gate")

	_cleanup(game, battle)
	_finish()


func _wait_for_settings(settings: Control, expected: StringName) -> void:
	var elapsed := 0.0
	while settings != null and StringName(settings.call("transition_state_name")) != expected and elapsed < WAIT_SECONDS:
		await create_timer(0.01).timeout
		elapsed += 0.01
	_check(
		settings != null and StringName(settings.call("transition_state_name")) == expected,
		"Settings did not reach %s" % expected,
	)


func _wait_for_confirmation(controls: Node, expected: StringName) -> void:
	var elapsed := 0.0
	while StringName(controls.call("confirmation_state_name")) != expected and elapsed < WAIT_SECONDS:
		await create_timer(0.01).timeout
		elapsed += 0.01
	_check(
		StringName(controls.call("confirmation_state_name")) == expected,
		"resign confirmation did not reach %s" % expected,
	)


func _escape_event() -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	return event


func _rect_matches(actual: Rect2, expected: Rect2) -> bool:
	return actual.position.distance_to(expected.position) <= 1.0 and actual.size.distance_to(expected.size) <= 1.0


func _cleanup(game: Node, battle: Node) -> void:
	if game.get("content") == battle:
		game.set("content", null)
	if battle != null and is_instance_valid(battle):
		battle.queue_free()
	var music := root.get_node_or_null("Music")
	if music != null:
		music.call("stop")
	if FileAccess.file_exists(PREFS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS_PATH))


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("BATTLE_PAUSE_MENU_TEST_OK")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)
