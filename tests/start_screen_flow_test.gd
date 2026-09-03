extends SceneTree

const STATIC_ART := preload("res://assets/loading/lunaris_reliquary_loading.png")
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
		await process_frame
		var backdrop := title.find_child("TitleBackdrop", true, false) as Control
		var start := title.find_child("StartButton", true, false) as Button
		var footer_row := title.find_child("FooterActionsRow", true, false) as HBoxContainer
		var leaderboard := title.find_child("LeaderboardButton", true, false) as Button
		var language := title.find_child("LanguageToggle", true, false) as Button
		var settings := title.find_child("FooterSettingsButton", true, false) as Button
		var tweak_service := root.get_node_or_null("TweakControls")
		var tweak := (
			tweak_service.get("launcher_button") as Button
			if tweak_service != null
			else null
		)
		_check(backdrop != null and backdrop.get("texture") == STATIC_ART, "start screen does not use the static loading backdrop")
		_check(title.find_child("LunarisTitleLoop", true, false) == null, "start screen still creates cinematic playback")
		_check(start != null and not start.disabled, "Start is missing or disabled")
		_check(footer_row != null, "start screen is missing its bottom action row")
		_check(
			footer_row != null
			and leaderboard != null and leaderboard.get_parent() == footer_row
			and language != null and language.get_parent() == footer_row
			and settings != null and settings.get_parent() == footer_row
			and tweak != null and tweak.get_parent() == footer_row,
			"secondary title actions are not grouped in the bottom row",
		)
		if leaderboard != null and language != null and settings != null and tweak != null:
			var baseline := leaderboard.get_global_rect().get_center().y
			for action: Button in [language, settings, tweak]:
				_check(
					is_equal_approx(action.get_global_rect().get_center().y, baseline),
					"bottom title actions are not vertically aligned",
				)
		if start != null:
			start.pressed.emit()
	var campaign := await _wait_for_content_script(game, "res://scripts/ui/stage_select.gd")
	_check(campaign != null, "Start did not navigate directly to the campaign screen")
	_check(bool(game.get("campaign_active")), "Start did not create campaign authority")
	var stage_ids: Array = game.call("campaign_stage_ids")
	_check(not stage_ids.is_empty(), "Campaign has no selectable missions")
	if campaign != null and not stage_ids.is_empty():
		var pending_stage_id := StringName(stage_ids[0])
		_check(
			bool(game.call("start_campaign_stage", pending_stage_id, false)),
			"Could not create the interrupted-mission fixture",
		)
		_check(
			StringName(game.call("pending_campaign_stage_id")) == pending_stage_id,
			"Interrupted-mission fixture did not retain its pending mission",
		)
		game.call("open_title")
		var resumed_title := await _wait_for_content_script(game, "res://scripts/ui/title.gd")
		_check(resumed_title != null, "Interrupted mission did not return to Start")
		if resumed_title != null:
			var resumed_start := resumed_title.find_child("StartButton", true, false) as Button
			_check(resumed_start != null, "Restored Start action is missing")
			if resumed_start != null:
				resumed_start.pressed.emit()
		var resumed_campaign := await _wait_for_content_script(
			game, "res://scripts/ui/stage_select.gd",
		)
		_check(
			resumed_campaign != null,
			"Start auto-launched the pending mission instead of opening Campaign",
		)
		for _frame: int in range(8):
			await process_frame
		_check(
			_content_script_path(game) == "res://scripts/ui/stage_select.gd",
			"Campaign did not remain visible for explicit mission selection",
		)
		_check(
			StringName(game.call("pending_campaign_stage_id")) == pending_stage_id,
			"Campaign navigation discarded the durable pending mission",
		)
		if resumed_campaign != null:
			var pending_card := resumed_campaign.find_child(
				"Stage_%s" % pending_stage_id, true, false,
			) as Button
			_check(
				pending_card != null and not pending_card.disabled,
				"Pending mission is not available for explicit selection",
			)
		_check(
			bool(game.call("start_campaign_stage", pending_stage_id, false)),
			"Explicit selection could not resume the pending mission",
		)
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


func _content_script_path(game: Node) -> String:
	var content := game.get("content") as Node
	if content == null or not is_instance_valid(content):
		return ""
	var script := content.get_script() as Script
	return script.resource_path if script != null else ""


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
