extends SceneTree

const SAVE_PATH := "user://leaderboard_visual_harness.json"


func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(1280, 720)
	var output_path := OS.get_environment("LEADERBOARD_CAPTURE_PATH")
	if output_path.is_empty():
		push_error("LEADERBOARD_CAPTURE_PATH is required")
		quit(64)
		return
	var service := root.get_node_or_null("Leaderboard")
	if service == null:
		push_error("Leaderboard autoload is unavailable")
		quit(1)
		return
	service.call("configure_for_testing", SAVE_PATH, "")
	service.call("clear_for_testing")
	service.call("set_player_name", "LUNARIS ACE")
	for fixture: Dictionary in [
		{"stage_id": &"s4", "result": BattleModel.Result.CLEAR, "stars": 3, "kills": 42, "leaks": 1},
		{"stage_id": &"s3", "result": BattleModel.Result.CLEAR, "stars": 2, "kills": 31, "leaks": 2},
		{"stage_id": &"s8", "result": BattleModel.Result.DEFEAT, "stars": 0, "kills": 58, "leaks": 4},
	]:
		service.call("record_mission", fixture)
	var title := load("res://scenes/title.tscn").instantiate() as Control
	root.add_child(title)
	for _frame: int in 4:
		await process_frame
	title.call("_finish_title_reveal")
	title.call("_open_leaderboard")
	for _frame: int in 4:
		await process_frame
	var viewport_texture := root.get_texture()
	if viewport_texture == null:
		push_error("Active renderer does not support viewport capture")
		quit(1)
		return
	var image := viewport_texture.get_image()
	if image == null:
		push_error("Active renderer returned no viewport image")
		quit(1)
		return
	var error := image.save_png(output_path)
	service.call("clear_for_testing")
	if error != OK:
		push_error("Could not save leaderboard capture: %s" % error_string(error))
		quit(1)
		return
	print("LEADERBOARD_VISUAL_CAPTURE_OK|%s" % output_path)
	quit(0)
