extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var run_id := OS.get_environment("PROTO_TD_TEST_RUN_ID")
	var expected_name := "GameTemplateTDTests-%s" % run_id
	var actual_user_dir := OS.get_user_data_dir().replace("\\", "/")
	_check(OS.get_environment("PROTO_TD_TEST_ISOLATED") == "1", "isolation marker missing")
	_check(not run_id.is_empty(), "test run id missing")
	_check(
		bool(ProjectSettings.get_setting(
			"application/config/use_custom_user_dir", false,
		)),
		"custom user directory is disabled",
	)
	_check(
		String(ProjectSettings.get_setting(
			"application/config/custom_user_dir_name", "",
		)) == expected_name,
		"custom user directory name does not match the run id",
	)
	_check(
		actual_user_dir.get_file() == expected_name,
		"Godot resolved the wrong user directory: %s" % actual_user_dir,
	)

	var canary_path := "user://test_user_data_isolation.canary"
	var canary := FileAccess.open(canary_path, FileAccess.WRITE)
	_check(canary != null, "isolated user directory is not writable")
	if canary != null:
		canary.store_string(run_id)
		canary.close()
		_check(FileAccess.get_file_as_string(canary_path) == run_id, "canary bytes changed")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(canary_path))

	if _failures.is_empty():
		print("TEST_USER_DATA_ISOLATION_OK user_dir=%s" % actual_user_dir)
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
