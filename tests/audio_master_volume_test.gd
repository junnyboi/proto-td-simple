extends SceneTree

const PREFS_PATH := "user://audio_master_volume_test.cfg"
const EPSILON := 0.001
const TRANSITION_TIMEOUT := 2.0

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_remove_prefs()
	var game := root.get_node("Game")
	game.call("set_run_seed", 9357)
	_check(bool(game.call("start_campaign", false, true)), "Campaign fixture failed")
	var campaign := load("res://scenes/stage_select.tscn").instantiate() as Control
	campaign.call("set_preferences_path", PREFS_PATH)
	root.add_child(campaign)
	await process_frame
	await process_frame
	var music := root.get_node("Music")
	music.call("play_staging", &"lunaris")
	var master_index := AudioServer.get_bus_index(&"Master")
	var music_index := AudioServer.get_bus_index(&"Music")
	var sfx_index := AudioServer.get_bus_index(&"SFX")
	_check(master_index >= 0 and music_index >= 0 and sfx_index >= 0, "runtime audio buses were not created")
	_check(AudioServer.get_bus_send(music_index) == &"Master", "Music bus is not routed through Master")
	_check(AudioServer.get_bus_send(sfx_index) == &"Master", "SFX bus is not routed through Master")
	var active_player := music.call("_active_player") as AudioStreamPlayer
	_check(active_player != null and active_player.bus == &"Music", "active music player bypasses the Music bus")
	_check(music.call("current_id") == &"lunaris_staging_archive_command", "Campaign music did not start for the volume test")

	campaign.call("_open_settings")
	var settings := campaign.get_node("TitleSettings") as Control
	await _wait_for_transition(settings, &"ACTIVE")
	var master := settings.find_child("MasterVolumeSlider", true, false) as HSlider
	var master_mute := settings.find_child("MasterMuteButton", true, false) as Button
	var music_slider := settings.find_child("MusicVolumeSlider", true, false) as HSlider
	_check(master != null and master.tick_count == 11 and master.ticks_on_borders, "Master volume lacks the requested visual ticked slider")
	_check(master_mute != null and master_mute.toggle_mode, "Master volume lacks the quick mute toggle")
	_check(master_mute.autowrap_mode == TextServer.AUTOWRAP_OFF, "Master mute action is allowed to wrap")
	master.value = 35.0
	music_slider.value = 65.0
	await process_frame
	var master_linear := db_to_linear(AudioServer.get_bus_volume_db(master_index))
	var music_linear := db_to_linear(AudioServer.get_bus_volume_db(music_index))
	var combined_linear := db_to_linear(
		AudioServer.get_bus_volume_db(master_index) + AudioServer.get_bus_volume_db(music_index)
	)
	_check(absf(master_linear - 0.35) <= EPSILON, "Master slider did not preview 35% on the Master bus")
	_check(absf(music_linear - 0.65) <= EPSILON, "Music slider did not preview 65% on the Music bus")
	_check(absf(combined_linear - 0.2275) <= EPSILON, "Master and Music buses do not combine into the expected audible gain")
	_check(not AudioServer.is_bus_mute(master_index), "nonzero Master volume muted the Master bus")

	master_mute.pressed.emit()
	await process_frame
	_check(AudioServer.is_bus_mute(master_index), "quick Master mute did not mute the shared output")
	_check(master_mute.text == "UNMUTE", "quick Master mute did not expose a compact Unmute action")
	_check(master_mute.size.x + 0.5 >= master_mute.get_combined_minimum_size().x, "Unmute action exceeds its rendered button width")
	_check(is_equal_approx(master.value, 35.0), "quick Master mute destructively changed the slider value")
	_check(bool(settings.call("draft").get(&"master_muted", false)), "quick Master mute did not enter the Settings draft")
	_check(active_player.playing, "quick Master mute stopped active music playback")
	master_mute.pressed.emit()
	await process_frame
	_check(not AudioServer.is_bus_mute(master_index), "quick Master unmute did not restore the shared output")
	_check(absf(db_to_linear(AudioServer.get_bus_volume_db(master_index)) - 0.35) <= EPSILON, "quick Master unmute did not retain the slider gain")

	master.value = 0.0
	await process_frame
	_check(AudioServer.is_bus_mute(master_index), "zero Master volume did not mute the Master bus")
	_check(active_player.playing, "Master mute stopped music instead of attenuating the shared output")

	master.value = 35.0
	master_mute.pressed.emit()
	await process_frame
	campaign.call("_cancel_settings")
	await _wait_for_transition(settings, &"CLOSED")
	_check(not AudioServer.is_bus_mute(master_index), "Settings cancel did not restore Master mute state")
	_check(absf(db_to_linear(AudioServer.get_bus_volume_db(master_index)) - 1.0) <= EPSILON, "Settings cancel did not restore Master volume")
	_check(absf(db_to_linear(AudioServer.get_bus_volume_db(music_index)) - 1.0) <= EPSILON, "Settings cancel did not restore Music volume")

	if game.get("content") == campaign:
		game.set("content", null)
	music.call("stop")
	campaign.queue_free()
	game.set("campaign_active", false)
	game.set("campaign", null)
	game.set("campaign_store", null)
	for _frame: int in range(10):
		await process_frame
	_remove_prefs()
	if _failures.is_empty():
		print("AUDIO_MASTER_VOLUME_TEST_OK")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)


func _wait_for_transition(state: Control, expected: StringName) -> void:
	var elapsed := 0.0
	while StringName(state.call("transition_state_name")) != expected and elapsed < TRANSITION_TIMEOUT:
		await create_timer(0.01).timeout
		elapsed += 0.01
	_check(StringName(state.call("transition_state_name")) == expected, "timed out waiting for %s" % expected)


func _remove_prefs() -> void:
	if FileAccess.file_exists(PREFS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS_PATH))


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
