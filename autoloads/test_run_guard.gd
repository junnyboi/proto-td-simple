extends Node

## Prevent repository tests and visual harnesses from touching the playable
## application's user:// directory. The supported runners generate a temporary
## project configuration with a unique custom user-data name before Godot starts.

const ISOLATED_ENV := "PROTO_TD_TEST_ISOLATED"
const RUN_ID_ENV := "PROTO_TD_TEST_RUN_ID"
const USER_DIR_PREFIX := "GameTemplateTDTests-"
const REFUSAL_EXIT_CODE := 78
const REFUSAL_MARKER := "TEST_USER_DATA_ISOLATION_REQUIRED"

var _emergency_user_dir := ""


func _enter_tree() -> void:
	if not is_test_invocation() or isolated_test_user_data_active():
		return
	_emergency_user_dir = _redirect_unisolated_test_user_data()
	push_error((
		"%s: run repository tests through tools/run_godot_test.sh or "
		+ "tools/run_godot_isolated.sh; refusing shared production user:// access."
	) % REFUSAL_MARKER)
	get_tree().quit(REFUSAL_EXIT_CODE)


func _exit_tree() -> void:
	if (
		not _emergency_user_dir.is_empty()
		and _emergency_user_dir.replace("\\", "/").get_file().begins_with(
			USER_DIR_PREFIX + "refused-",
		)
	):
		_remove_tree(_emergency_user_dir)


static func _redirect_unisolated_test_user_data() -> String:
	# SceneTree test bodies in this repository defer their work until after
	# autoload creation. Redirect immediately so even the final message-queue
	# flush performed by quit() cannot expose the playable user:// directory.
	var emergency_name := "%srefused-%d-%d" % [
		USER_DIR_PREFIX, OS.get_process_id(), Time.get_ticks_msec(),
	]
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting(
		"application/config/custom_user_dir_name", emergency_name,
	)
	return OS.get_user_data_dir()


static func _remove_tree(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var child_path := path.path_join(entry)
			if directory.is_link(entry):
				DirAccess.remove_absolute(child_path)
			elif directory.current_is_dir():
				_remove_tree(child_path)
			else:
				DirAccess.remove_absolute(child_path)
		entry = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(path)


static func is_test_invocation() -> bool:
	for raw_arg: String in OS.get_cmdline_args():
		var arg := raw_arg.replace("\\", "/")
		for prefix: String in ["--script=", "-s=", "-gtest="]:
			if arg.begins_with(prefix):
				arg = arg.trim_prefix(prefix)
				break
		if _is_test_target(arg):
			return true
	return false


static func isolated_test_user_data_active() -> bool:
	if OS.get_environment(ISOLATED_ENV) != "1":
		return false
	var run_id := OS.get_environment(RUN_ID_ENV)
	if not _valid_run_id(run_id):
		return false
	if not bool(ProjectSettings.get_setting(
		"application/config/use_custom_user_dir", false,
	)):
		return false
	var expected_name := USER_DIR_PREFIX + run_id
	if String(ProjectSettings.get_setting(
		"application/config/custom_user_dir_name", "",
	)) != expected_name:
		return false
	return OS.get_user_data_dir().replace("\\", "/").get_file() == expected_name


static func _is_test_target(arg: String) -> bool:
	var normalized := arg.trim_prefix("./")
	if not (
		normalized.ends_with(".gd")
		or normalized.ends_with(".tscn")
		or normalized.ends_with(".scn")
	):
		return false
	return (
		normalized.begins_with("res://tests/")
		or normalized.begins_with("res://test/")
		or normalized.begins_with("tests/")
		or normalized.begins_with("test/")
		or normalized.contains("/tests/")
		or normalized.contains("/test/")
	)


static func _valid_run_id(value: String) -> bool:
	if value.is_empty() or value.length() > 96:
		return false
	for character: String in value:
		if character not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-":
			return false
	return true
