extends SceneTree

const DialogType := preload("res://scripts/ui/components/lunaris_dialog_sheet.gd")
const ViewPreferencesType := preload("res://scripts/view/view_preferences.gd")
const WAIT_TIMEOUT := 1.5

const FIXTURE_PATHS := [
	"user://campaign_v1.json",
	"user://campaign_v1.bak",
	"user://campaign_v1.tmp",
	"user://campaign_v1.invalid",
	"user://campaign_v1.bak.invalid",
	"user://campaign_v1.tmp.invalid",
	"user://view_preferences.cfg",
	"user://content-packs/fixture.pck",
	"user://cinematic-streams/fixture.ogv",
	"user://future-player-data/nested/profile.bin",
]

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for path: String in FIXTURE_PATHS:
		if path == ViewPreferencesType.DEFAULT_PATH or path.begins_with("user://campaign_v1"):
			continue
		_check(_write_fixture(path), "could not create player-data fixture: %s" % path)
	_check(
		ViewPreferencesType.save_batch({
			&"locale": &"en-US",
			&"title_music_enabled": false,
			&"master_volume": 0.35,
			&"master_muted": true,
			&"music_volume": 0.45,
			&"sfx_volume": 0.55,
			&"frame_limit": 30,
			&"reduced_motion": true,
			&"text_scale": 1.25,
			&"background_downloads_enabled": false,
		}),
		"could not create valid player preference fixture",
	)
	var game := root.get_node_or_null("Game")
	var music := root.get_node_or_null("Music")
	var sfx := root.get_node_or_null("Sfx")
	_check(game != null, "Game autoload is unavailable")
	if game == null:
		await _finish(music, sfx)
		return
	game.call("set_run_seed", 4816)
	_check(bool(game.call("start_campaign", false, true)), "Campaign fixture failed")
	for path: String in FIXTURE_PATHS:
		if path.begins_with("user://campaign_v1"):
			_check(_write_fixture(path), "could not create campaign fixture: %s" % path)
	game.set("selected_stage_id", &"s8")
	game.set("selected_squad", [&"guard_1"])
	var campaign := load("res://scenes/stage_select.tscn").instantiate() as Control
	root.add_child(campaign)
	await process_frame
	await process_frame
	campaign.call("_open_settings")
	var settings := campaign.get_node("TitleSettings") as Control
	await _wait_for_state(settings, &"ACTIVE")
	var clear_button := settings.find_child("ClearPlayerDataButton", true, false) as Button
	var dialog := settings.find_child("ClearPlayerDataConfirmation", true, false) as Control
	_check(clear_button != null and dialog != null, "Clear Player Data action or confirmation is missing")
	_check(clear_button != null and not clear_button.accessibility_description.is_empty(), "Clear Player Data lacks an accessible warning")
	clear_button.pressed.emit()
	await _wait_for_dialog(settings, &"open")
	var cancel := dialog.find_child("CancelButton", true, false) as Button
	var confirm := dialog.find_child("ConfirmButton", true, false) as Button
	_check(cancel != null and confirm != null, "clear confirmation actions are incomplete")
	_check(cancel.has_focus(), "destructive confirmation did not place safe initial focus on Cancel")
	_check(confirm.text == "CLEAR EVERYTHING", "clear confirmation is not explicit")
	cancel.pressed.emit()
	await _wait_for_dialog(settings, &"closed")
	_check(FileAccess.file_exists("user://campaign_v1.json"), "Cancel deleted campaign data")
	_check(clear_button.has_focus(), "Cancel did not restore focus to Clear Player Data")
	clear_button.pressed.emit()
	await _wait_for_dialog(settings, &"open")
	confirm.pressed.emit()
	for _frame: int in range(8):
		await process_frame
	for path: String in FIXTURE_PATHS:
		_check(not FileAccess.file_exists(path), "player-data artifact survived clear: %s" % path)
	_check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("user://future-player-data")), "nested future player-data directory survived clear")
	_check(game.get("campaign") == null and not bool(game.get("campaign_active")), "clear started campaign authority before Start was activated")
	_check(StringName(game.get("selected_stage_id")).is_empty() and (game.get("selected_squad") as Array).is_empty(), "live mission selection survived clear")
	var restarted := game.get("content") as Control
	_check(restarted != null and restarted != campaign and String(restarted.get_script().resource_path) == "res://scripts/ui/title.gd", "clear did not return to the start screen")
	_check(restarted != null and restarted.find_child("StartButton", true, false) != null, "clear did not restore the Start gate")
	_check(ViewPreferencesType.locale() == &"en-US" and ViewPreferencesType.background_downloads_enabled(), "clear did not restore default preferences")
	if is_instance_valid(campaign):
		campaign.queue_free()
	if restarted != null:
		game.set("content", null)
		restarted.queue_free()
	await _finish(music, sfx)


func _wait_for_state(settings: Control, expected: StringName) -> void:
	var elapsed := 0.0
	while StringName(settings.call("transition_state_name")) != expected and elapsed < WAIT_TIMEOUT:
		await create_timer(0.01).timeout
		elapsed += 0.01
	_check(StringName(settings.call("transition_state_name")) == expected, "Settings did not reach %s" % expected)


func _wait_for_dialog(settings: Control, expected: StringName) -> void:
	var elapsed := 0.0
	var dialog: Dictionary = settings.get("_clear_data_dialog") as Dictionary
	while DialogType.transition_state_name(dialog) != expected and elapsed < WAIT_TIMEOUT:
		await create_timer(0.01).timeout
		elapsed += 0.01
	_check(DialogType.transition_state_name(dialog) == expected, "clear confirmation did not reach %s" % expected)


func _write_fixture(path: String) -> bool:
	var directory := path.get_base_dir()
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) != OK:
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string("fixture:%s" % path)
	file.close()
	return true


func _finish(music: Node, sfx: Node) -> void:
	if music != null:
		music.call("stop")
	if sfx != null:
		sfx.call("stop_all")
	for _frame: int in range(16):
		await process_frame
	await create_timer(0.5).timeout
	if _failures.is_empty():
		print("PLAYER_DATA_CLEAR_TEST_OK")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
