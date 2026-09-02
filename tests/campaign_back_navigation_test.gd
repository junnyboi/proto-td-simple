extends SceneTree

const TRANSITION_FRAMES := 180
const CAMPAIGN_SCRIPT_PATH := "res://scripts/ui/stage_select.gd"
const TITLE_SCRIPT_PATH := "res://scripts/ui/title.gd"

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game := root.get_node_or_null("Game")
	_check(game != null, "Game autoload is unavailable")
	if game == null:
		_finish()
		return
	game.call("set_run_seed", 9281)
	_check(bool(game.call("start_campaign", true, true)), "Campaign fixture failed")
	var campaign := await _wait_for_content_script(game, CAMPAIGN_SCRIPT_PATH)
	_check(campaign != null, "Campaign screen did not open")
	if campaign != null:
		var back := campaign.find_child("CampaignBack", true, false) as Button
		_check(back != null, "Campaign Back button is missing")
		if back != null:
			back.pressed.emit()
	var title := await _wait_for_content_script(game, TITLE_SCRIPT_PATH)
	_check(title != null, "Campaign Back did not return to the start screen")
	_check(not bool(game.get("campaign_active")), "Campaign Back left campaign authority active")

	if title != null:
		var start := title.find_child("StartButton", true, false) as Button
		_check(start != null, "Start screen did not restore the Start action")
		if start != null:
			start.pressed.emit()
	campaign = await _wait_for_content_script(game, CAMPAIGN_SCRIPT_PATH)
	_check(campaign != null, "Start did not reopen the campaign screen")
	if campaign != null:
		var cancel := InputEventAction.new()
		cancel.action = &"ui_cancel"
		cancel.pressed = true
		campaign.call("_unhandled_input", cancel)
	title = await _wait_for_content_script(game, TITLE_SCRIPT_PATH)
	_check(title != null, "Escape did not return to the start screen")
	_check(not bool(game.get("campaign_active")), "Escape left campaign authority active")

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
		print("CAMPAIGN_BACK_NAVIGATION_TEST_OK")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)
