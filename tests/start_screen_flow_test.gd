extends SceneTree

const STATIC_ART := preload("res://assets/loading/command_backdrop.png")
const TRANSITION_FRAMES := 180

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game := root.get_node_or_null("Game")
	_check(game != null, "Game autoload is unavailable")
	if game == null:
		_finish()
		return
	game.call("_reset_campaign_runtime")
	var loading := load("res://scenes/loading.tscn").instantiate() as Control
	root.add_child(loading)
	await process_frame
	loading.call("_finish_loading")
	var title := await _wait_for_content_script(game, "res://scripts/ui/title.gd")
	_check(title != null, "loading did not enter the start screen")
	_check(not bool(game.get("campaign_active")), "loading started a campaign before Start was activated")
	if title != null:
		var backdrop := title.find_child("TitleBackdrop", true, false) as Control
		var start := title.find_child("StartButton", true, false) as Button
		_check(backdrop != null and backdrop.get("texture") == STATIC_ART, "start screen does not use the static loading backdrop")
		_check(title.find_child("LunarisTitleLoop", true, false) == null, "start screen still creates cinematic playback")
		_check(start != null and not start.disabled, "Start is missing or disabled")
		if start != null:
			start.pressed.emit()
	var campaign := await _wait_for_content_script(game, "res://scripts/ui/stage_select.gd")
	_check(campaign != null, "Start did not navigate directly to the campaign screen")
	_check(bool(game.get("campaign_active")), "Start did not create campaign authority")
	var content := game.get("content") as Node
	if content != null and is_instance_valid(content):
		game.set("content", null)
		content.queue_free()
	game.call("_reset_campaign_runtime")
	var music := root.get_node_or_null("Music")
	if music != null:
		music.call("stop")
	var sfx := root.get_node_or_null("Sfx")
	if sfx != null:
		sfx.call("stop_all")
	for _frame: int in range(12):
		await process_frame
	_finish()


func _wait_for_content_script(game: Node, expected_path: String) -> Control:
	for _frame: int in range(TRANSITION_FRAMES):
		var content := game.get("content") as Control
		if content != null and is_instance_valid(content):
			var script := content.get_script() as Script
			if script != null and script.resource_path == expected_path:
				return content
		await process_frame
	return null


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("START_SCREEN_FLOW_TEST_OK")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)
