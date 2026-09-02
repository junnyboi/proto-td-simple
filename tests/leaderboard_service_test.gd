extends SceneTree

const SAVE_PATH := "user://leaderboard_service_test.json"
const ServiceType := preload("res://autoloads/leaderboard.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var service := root.get_node_or_null("Leaderboard")
	_check(service != null, "Leaderboard autoload is unavailable")
	if service == null:
		_finish()
		return
	service.call("configure_for_testing", SAVE_PATH, "")
	service.call("clear_for_testing")
	_check(
		ServiceType.normalize_player_name("  commander!! jun---7  ") == "COMMANDER JUN-7",
		"username normalization drifted",
	)
	_check(
		ServiceType.calculate_score({
			"stage_id": "s4",
			"victory": true,
			"stars": 3,
			"kills": 42,
			"leaks": 1,
		}) == 2_461_600,
		"mission score formula drifted",
	)
	_check(ServiceType.mission_number("s10") == 10, "valid stage parsing failed")
	_check(ServiceType.mission_number("s11") == 0, "removed stage parsing was accepted")
	_check(
		String(service.call("set_player_name", "  moon--ace!  ")) == "MOON-ACE",
		"saved username was not normalized",
	)
	var defeat: Dictionary = service.call("record_mission", {
		"stage_id": &"s10",
		"result": BattleModel.Result.DEFEAT,
		"stars": 0,
		"kills": 0,
		"leaks": 1,
	})
	var clear: Dictionary = service.call("record_mission", {
		"stage_id": &"s1",
		"result": BattleModel.Result.CLEAR,
		"stars": 1,
		"kills": 0,
		"leaks": 0,
	})
	_check(not defeat.is_empty() and not clear.is_empty(), "valid mission result was not recorded")
	_check(int(service.call("pending_count")) == 2, "offline submissions were not queued")
	var local: Array = service.call("local_entries", 10)
	_check(local.size() == 2, "local leaderboard did not retain both missions")
	if local.size() == 2:
		_check(String((local[0] as Dictionary).get("stage_id", "")) == "s1", "local scores were not sorted descending")
		_check(int((local[0] as Dictionary).get("rank", 0)) == 1, "local rank projection is incorrect")
		_check(String((local[0] as Dictionary).get("name", "")) == "MOON-ACE", "local score lost the saved username")
	_check(FileAccess.file_exists(SAVE_PATH), "leaderboard data was not persisted")

	var restored := ServiceType.new()
	restored.save_path = SAVE_PATH
	restored.name = "RestoredLeaderboard"
	root.add_child(restored)
	await process_frame
	_check(restored.player_name() == "MOON-ACE", "persisted username did not reload")
	_check(restored.local_entries(10).size() == 2, "persisted local scores did not reload")
	_check(restored.pending_count() == 2, "persisted offline queue did not reload")
	restored.queue_free()
	service.call("clear_for_testing")
	await process_frame
	_finish()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("LEADERBOARD_SERVICE_TEST_OK")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)
