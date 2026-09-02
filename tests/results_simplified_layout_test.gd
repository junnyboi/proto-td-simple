extends SceneTree

const VIEWPORT_SIZE := Vector2i(1280, 720)

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = VIEWPORT_SIZE
	var game := root.get_node_or_null("Game")
	_check(game != null, "Game autoload is unavailable")
	if game == null:
		_finish()
		return
	game.call("set_run_seed", 9302)
	_check(bool(game.call("start_campaign", false, true)), "Campaign fixture failed")
	await _check_results_screen(game, BattleModel.Result.CLEAR, "clear")
	await _check_results_screen(game, BattleModel.Result.DEFEAT, "defeat")
	game.call("_reset_campaign_runtime")
	var music := root.get_node_or_null("Music")
	if music != null:
		music.call("stop")
	var sfx := root.get_node_or_null("Sfx")
	if sfx != null:
		sfx.call("stop_all")
	for _frame: int in range(8):
		await process_frame
	_finish()


func _check_results_screen(game: Node, outcome: int, label: String) -> void:
	game.set("last_result", {
		"stage_id": &"s2",
		"result": outcome,
		"stars": 3 if outcome == BattleModel.Result.CLEAR else 0,
		"kills": 10,
		"leaks": 0 if outcome == BattleModel.Result.CLEAR else 6,
		"rewards_granted": [{"kind": "currency", "id": "marks", "amount": 40}],
		"dead_hero_ids": [],
	})
	var screen := load("res://scenes/results.tscn").instantiate() as Control
	root.add_child(screen)
	for _frame: int in range(3):
		await process_frame

	var header := screen.find_child("OutcomeCeremony", true, false) as PanelContainer
	var body := screen.find_child("ResultsBody", true, false) as GridContainer
	var rewards := screen.find_child("RewardsPanel", true, false) as PanelContainer
	_check(header != null, "%s results header is missing" % label)
	_check(body != null and body.columns == 1, "%s results body is not a single full-width column" % label)
	_check(rewards != null, "%s Mission Yield panel is missing" % label)
	if header != null:
		var style := header.get_theme_stylebox(&"panel") as StyleBoxFlat
		_check(style != null, "%s results header is not a simple solid-fill panel" % label)
		if style != null:
			_check(style.bg_color.a > 0.0 and style.bg_color.a < 1.0, "%s results header fill is not translucent" % label)
			_check(
				style.border_color.is_equal_approx(Color("d9b96ee8")),
				"%s results header border is not gold" % label,
			)
			_check(
				style.border_width_left == 2
				and style.border_width_top == 2
				and style.border_width_right == 2
				and style.border_width_bottom == 2,
				"%s results header does not have a uniform gold border" % label,
			)
			_check(
				style.corner_radius_top_left == 14
				and style.corner_radius_top_right == 14
				and style.corner_radius_bottom_left == 14
				and style.corner_radius_bottom_right == 14,
				"%s results header is not uniformly rounded" % label,
			)
	if body != null and rewards != null:
		var body_rect := body.get_global_rect()
		var rewards_rect := rewards.get_global_rect()
		_check(
			absf(body_rect.position.x - rewards_rect.position.x) <= 1.0
			and absf(body_rect.end.x - rewards_rect.end.x) <= 1.0,
			"%s Mission Yield does not fill the body width" % label,
		)
	for removed_name: String in [
		"ConsequencePanel", "ConsequenceScroll", "ConsequenceColumn",
		"ConsequenceHeading", "ConsequenceLine", "NoCasualties",
	]:
		_check(
			screen.find_child(removed_name, true, false) == null,
			"%s results retained %s" % [label, removed_name],
		)

	if game.get("content") == screen:
		game.set("content", null)
	root.remove_child(screen)
	screen.free()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("RESULTS_SIMPLIFIED_LAYOUT_TEST_OK")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)
