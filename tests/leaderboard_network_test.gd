extends SceneTree

const SAVE_PATH := "user://leaderboard_network_test.json"
const TIMEOUT_SECONDS := 10.0

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var base_url := OS.get_environment("LEADERBOARD_TEST_URL")
	var service := root.get_node_or_null("Leaderboard")
	_check(not base_url.is_empty(), "LEADERBOARD_TEST_URL is required")
	_check(service != null, "Leaderboard autoload is unavailable")
	if base_url.is_empty() or service == null:
		_finish()
		return
	service.call("configure_for_testing", SAVE_PATH, base_url)
	service.call("clear_for_testing")
	service.call("set_player_name", "NETWORK ACE")
	service.call("record_mission", {
		"stage_id": &"s3",
		"result": BattleModel.Result.CLEAR,
		"stars": 2,
		"kills": 21,
		"leaks": 1,
	})
	await _wait_until_ready(service)
	_check(StringName(service.get("status")) == &"ready", "live submission did not reach ready state")
	_check(int(service.call("pending_count")) == 0, "successful live submission did not drain the queue")
	var entries := service.get("entries") as Array
	_check(not entries.is_empty(), "live service returned no global rows")
	var matched := false
	for raw: Variant in entries:
		if raw is Dictionary and String((raw as Dictionary).get("name", "")) == "NETWORK ACE":
			matched = true
			_check(
				int((raw as Dictionary).get("score", 0)) == 2_340_550,
				"live service and client score formulas differ",
			)
	_check(matched, "submitted Godot score was absent from the global response")
	service.call("clear_for_testing")
	await process_frame
	_finish()


func _wait_until_ready(service: Node) -> void:
	var elapsed := 0.0
	while elapsed < TIMEOUT_SECONDS:
		if (
			StringName(service.get("status")) == &"ready"
			and int(service.call("pending_count")) == 0
		):
			return
		await create_timer(0.02).timeout
		elapsed += 0.02


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("LEADERBOARD_NETWORK_TEST_OK")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)
