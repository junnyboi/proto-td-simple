extends SceneTree

const PREFS_PATH := "user://campaign_settings_navigation_test.cfg"
const WAIT_SECONDS := 2.0

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game := root.get_node_or_null("Game")
	_check(game != null, "Game autoload is unavailable")
	if game == null:
		_finish()
		return
	game.call("set_run_seed", 4601)
	_check(bool(game.call("start_campaign", false, true)), "Campaign fixture failed")
	if not bool(game.get("campaign_active")):
		_finish()
		return
	var campaign := load("res://scenes/stage_select.tscn").instantiate() as Control
	campaign.call("set_preferences_path", PREFS_PATH)
	root.add_child(campaign)
	await process_frame
	await process_frame

	var utilities := campaign.find_child("CampaignUtilities", true, false) as GridContainer
	var back := campaign.find_child("CampaignBack", true, false) as Button
	var settings_button := campaign.find_child("CampaignSettingsButton", true, false) as Button
	var settings := campaign.get_node_or_null("TitleSettings") as Control
	_check(not ResourceLoader.exists("res://scenes/staging.tscn"), "removed Company Command scene is still loadable")
	_check(campaign.find_child("BarracksButton", true, false) == null, "Campaign still exposes Barracks")
	_check(campaign.find_child("ArmoryButton", true, false) == null, "Campaign still exposes Armory")
	_check(utilities != null and utilities.columns == 2, "Campaign utility group is missing")
	_check(back != null and settings_button != null and settings != null, "Campaign navigation or Settings control is missing")
	_check(
		utilities != null and settings_button != null
		and is_equal_approx(settings_button.get_global_rect().end.x, utilities.get_global_rect().end.x),
		"Settings is not the top-right Campaign utility",
	)

	if settings_button != null and settings != null:
		settings_button.pressed.emit()
		await _wait_for_settings(settings, &"ACTIVE")
		_check(settings.visible, "Settings did not become visible")
		_check(back != null and back.focus_mode == Control.FOCUS_NONE, "Campaign Back remained interactive behind Settings")
		_check(settings_button.focus_mode == Control.FOCUS_NONE, "Settings launcher remained interactive behind Settings")
		campaign.call("_cancel_settings")
		await _wait_for_settings(settings, &"CLOSED")
		_check(not settings.visible, "Settings did not close")
		_check(settings_button.focus_mode == Control.FOCUS_ALL, "Campaign input did not restore after closing Settings")

	if game.get("content") == campaign:
		game.set("content", null)
	campaign.queue_free()
	game.set("campaign_active", false)
	game.set("campaign", null)
	game.set("campaign_store", null)
	for _frame: int in range(8):
		await process_frame
	if FileAccess.file_exists(PREFS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS_PATH))
	_finish()


func _wait_for_settings(settings: Control, expected: StringName) -> void:
	var elapsed := 0.0
	while StringName(settings.call("transition_state_name")) != expected and elapsed < WAIT_SECONDS:
		await create_timer(0.01).timeout
		elapsed += 0.01
	_check(
		StringName(settings.call("transition_state_name")) == expected,
		"Settings did not reach %s" % expected,
	)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("CAMPAIGN_SETTINGS_NAVIGATION_TEST_OK")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)
