extends SceneTree

const SAVE_PATH := "user://leaderboard_ui_test.json"
const Style := preload("res://scripts/ui/components/lunaris_ops_style.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var service := root.get_node_or_null("Leaderboard")
	var game := root.get_node_or_null("Game")
	_check(service != null and game != null, "required autoloads are unavailable")
	if service == null or game == null:
		_finish()
		return
	service.call("configure_for_testing", SAVE_PATH, "")
	service.call("clear_for_testing")
	service.call("record_mission", {
		"stage_id": &"s2",
		"result": BattleModel.Result.CLEAR,
		"stars": 3,
		"kills": 18,
		"leaks": 0,
	})

	var title := load("res://scenes/title.tscn").instantiate() as Control
	root.add_child(title)
	for _frame: int in 3:
		await process_frame
	var title_button := title.find_child("LeaderboardButton", true, false) as Button
	var title_dialog := title.find_child("LeaderboardDialog", true, false) as Control
	_check(title_button != null, "start screen is missing the Leaderboard button")
	_check(title_dialog != null and not title_dialog.visible, "start-screen dialog did not begin closed")
	if title_button != null:
		_check_simple_gold_style(title_button, &"normal", "start-screen Leaderboard button")
		title_button.pressed.emit()
	await process_frame
	_check(title_dialog != null and title_dialog.visible, "start-screen Leaderboard button did not open the dialog")
	_check(StringName(title.call("screen_state")) == &"LEADERBOARD", "start screen did not enter modal leaderboard state")
	if title_dialog != null:
		_check_simple_gold_style(
			title_dialog.find_child("LeaderboardPanel", true, false) as Control,
			&"panel",
			"leaderboard dialog",
		)
		var name_edit := title_dialog.find_child("UsernameEdit", true, false) as LineEdit
		var save_name := title_dialog.find_child("SaveUsernameButton", true, false) as Button
		var global_tab := title_dialog.find_child("GlobalTab", true, false) as Button
		_check(name_edit != null and save_name != null, "username editor is incomplete")
		_check(title_dialog.find_child("LeaderboardRow1", true, false) != null, "local score row was not rendered")
		_check_simple_gold_style(name_edit, &"normal", "username field")
		_check_simple_gold_style(save_name, &"normal", "Save Name button")
		_check_simple_gold_style(global_tab, &"normal", "Global tab")
		_check_simple_gold_style(
			title_dialog.find_child("LeaderboardRow1", true, false) as Control,
			&"panel",
			"leaderboard score row",
		)
		if name_edit != null and save_name != null:
			name_edit.text = "  star!! keeper  "
			save_name.pressed.emit()
			_check(String(service.call("player_name")) == "STAR KEEPER", "dialog did not persist the edited username")
		if global_tab != null:
			global_tab.pressed.emit()
			_check(StringName(title_dialog.get("current_tab")) == &"global", "Global tab did not activate")
		title_dialog.call("close")
	await process_frame
	_check(title_dialog != null and not title_dialog.visible, "start-screen leaderboard did not close")
	_check(StringName(title.call("screen_state")) == &"TITLE", "start screen did not leave modal leaderboard state")
	if game.get("content") == title:
		game.set("content", null)
	title.queue_free()
	await process_frame

	game.set("last_result", {
		"stage_id": &"s2",
		"result": BattleModel.Result.CLEAR,
		"stars": 3,
		"kills": 18,
		"leaks": 0,
		"rewards_granted": [],
		"dead_hero_ids": [],
	})
	var results := load("res://scenes/results.tscn").instantiate() as Control
	root.add_child(results)
	for _frame: int in 3:
		await process_frame
	var results_button := results.find_child("LeaderboardButton", true, false) as Button
	var results_dialog := results.find_child("LeaderboardDialog", true, false) as Control
	_check(results_button != null, "mission results are missing the Leaderboard button")
	_check(results_dialog != null and not results_dialog.visible, "results dialog opened automatically")
	if results_button != null:
		_check_simple_gold_style(results_button, &"normal", "mission-results Leaderboard button")
		results_button.pressed.emit()
	await process_frame
	_check(results_dialog != null and results_dialog.visible, "results Leaderboard button did not open the dialog")
	if results_dialog != null:
		results_dialog.call("close")
	if game.get("content") == results:
		game.set("content", null)
	results.queue_free()
	service.call("clear_for_testing")
	var music := root.get_node_or_null("Music")
	if music != null:
		music.call("stop")
	var sfx := root.get_node_or_null("Sfx")
	if sfx != null:
		sfx.call("stop_all")
	for _frame: int in 8:
		await process_frame
	_finish()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _check_simple_gold_style(control: Control, style_name: StringName, context: String) -> void:
	if control == null:
		_failures.append("%s is unavailable for style verification" % context)
		return
	var style := control.get_theme_stylebox(style_name) as StyleBoxFlat
	_check(style != null, "%s does not use a simple solid fill" % context)
	if style == null:
		return
	_check(style.bg_color.a > 0.0 and style.bg_color.a < 1.0, "%s fill is not translucent" % context)
	_check(
		is_equal_approx(style.border_color.r, Style.GOLD.r)
		and is_equal_approx(style.border_color.g, Style.GOLD.g)
		and is_equal_approx(style.border_color.b, Style.GOLD.b),
		"%s border is not gold" % context,
	)
	_check(style.corner_radius_top_left >= 12, "%s border is not rounded" % context)


func _finish() -> void:
	if _failures.is_empty():
		print("LEADERBOARD_UI_TEST_OK")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)
