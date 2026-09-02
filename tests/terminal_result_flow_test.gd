extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game := root.get_node_or_null("Game")
	_check(game != null, "Game autoload missing")
	if game == null:
		_finish()
		return
	game.call("set_run_seed", 818_818)
	_check(bool(game.call("start_campaign", false, true)), "terminal campaign failed to start")
	var projection: Dictionary = game.call("campaign_projection")
	var ready: Array = projection.get("ready_heroes", [])
	_check(not ready.is_empty(), "terminal campaign has no ready operator")
	if ready.is_empty():
		_cleanup(game)
		_finish()
		return
	var squad: Array[StringName] = [StringName(ready[0]["hero_id"])]
	var launch: Dictionary = game.call("start_stage", &"s1", squad, true)
	_check(launch.get("accepted", false), "terminal campaign launch failed")
	for _frame: int in 16:
		await process_frame
	var battle := game.get("content") as Node
	var model := game.get("current_battle") as BattleModel
	_check(battle != null and bool(battle.get("startup_succeeded")), "ticketed battle did not open")
	_check(model != null and model.apply_action([&"resign"]), "ticketed battle did not resign")
	if battle == null or model == null:
		_cleanup(game)
		_finish()
		return
	battle.call("_detect_result_stamp")
	var stamp := battle.find_child("ResultStampLabel", true, false) as Label
	var continuation := battle.find_child("ContinueButton", true, false) as Button
	_check(stamp != null and stamp.text == "Defeat", "defeat feedback did not render immediately")
	_check(continuation != null and continuation.disabled, "debrief enabled before persistence")
	await process_frame
	_check(
		continuation != null and continuation.disabled,
		"strategic preparation and durable commit ran in one frame",
	)
	_check(
		not (game.get("_prepared_battle_result") as Dictionary).is_empty(),
		"first finalization frame did not prepare the strategic result",
	)
	for _frame: int in 8:
		if bool(battle.get("_result_finalized")):
			break
		await process_frame
	_check(bool(battle.get("_result_finalized")), "terminal result did not finish")
	_check(continuation != null and not continuation.disabled, "debrief stayed disabled after commit")
	_check(
		continuation != null and continuation.text == "CONTINUE",
		"terminal action did not advance from finalizing to debrief",
	)
	_check(
		int(game.call("campaign_projection").get("save_revision", -1)) == 3,
		"terminal campaign did not commit exactly begin + resolve",
	)
	_check(
		int((game.get("last_result") as Dictionary).get("result", -1)) == BattleModel.Result.DEFEAT,
		"committed terminal result is not defeat",
	)
	_check(not bool(game.get("_campaign_battle_active")), "terminal campaign stayed active after commit")
	_check(
		(game.get("_pending_battle_ticket") as Dictionary).is_empty(),
		"terminal ticket survived the durable resolution",
	)
	_cleanup(game)
	await create_timer(0.25).timeout
	_finish()


func _cleanup(game: Node) -> void:
	var content := game.get("content") as Node
	game.set("content", null)
	if content != null and is_instance_valid(content):
		var parent := content.get_parent()
		if parent != null:
			parent.remove_child(content)
		content.free()
	game.set("campaign_active", false)
	game.set("campaign", null)
	game.set("campaign_store", null)
	game.set("pending_stage", null)
	game.set("current_battle", null)
	game.set("_pending_battle_ticket", {})
	game.set("_pending_campaign_mutation", null)
	game.set("_prepared_battle_result", {})
	game.set("_campaign_battle_active", false)
	var music := root.get_node_or_null("Music")
	if music != null and music.has_method("stop"):
		music.call("stop")
	var sfx := root.get_node_or_null("Sfx")
	if sfx != null and sfx.has_method("stop_all"):
		sfx.call("stop_all")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("TERMINAL_RESULT_FLOW_TEST_OK")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)
