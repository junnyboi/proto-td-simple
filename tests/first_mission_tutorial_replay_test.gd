extends SceneTree

const CampaignFixture := preload("res://test/support/authoritative_campaign_fixture.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game := root.get_node_or_null("Game")
	_check(game != null, "Game autoload missing")
	if game == null:
		_finish()
		return

	game.call("set_run_seed", 83471)
	_check(bool(game.call("start_campaign", false, true)), "campaign fixture failed")
	var clear_fixture := CampaignFixture.clear_stage(
		game, &"s1", "first-mission-tutorial-replay",
	)
	_check(
		clear_fixture.get("accepted", false),
		"authoritative S1 clear fixture failed: %s"
		% clear_fixture.get("error_code", &"unknown"),
	)
	if not clear_fixture.get("accepted", false):
		_cleanup(game)
		_finish()
		return

	var projection: Dictionary = game.call("campaign_projection")
	var stars := projection.get("stage_stars", {}) as Dictionary
	_check(stars.has(&"s1") or stars.has("s1"), "S1 replay fixture is not cleared")
	var ready: Array = projection.get("ready_heroes", [])
	_check(not ready.is_empty(), "S1 replay fixture has no ready hero")
	if ready.is_empty():
		_cleanup(game)
		_finish()
		return

	var hero_id := StringName(ready[0].get("hero_id", &""))
	var launch: Dictionary = game.call(
		"start_stage", &"s1", [hero_id] as Array[StringName], true,
	)
	_check(
		launch.get("accepted", false),
		"cleared S1 replay launch failed: %s" % launch.get("error_code", &"unknown"),
	)
	for _frame: int in range(12):
		await process_frame

	var battle := game.get("content") as Node
	_check(
		battle != null and bool(battle.get("startup_succeeded")),
		"cleared S1 replay battle did not start",
	)
	var tutorial := (
		battle.find_child("FirstStandTutorial", true, false) as Node
		if battle != null
		else null
	)
	_check(tutorial != null, "cleared S1 replay suppressed the First Stand tutorial")
	_check(
		tutorial != null and bool(tutorial.call("is_holding_battle")),
		"cleared S1 replay tutorial did not hold the opening battle",
	)

	_cleanup(game)
	for _frame: int in range(12):
		await process_frame
	await create_timer(0.1).timeout
	_finish()


func _cleanup(game: Node) -> void:
	var content := game.get("content") as Node
	if content != null and is_instance_valid(content):
		var parent := content.get_parent()
		if parent != null:
			parent.remove_child(content)
		content.free()
	game.set("content", null)
	game.set("campaign_active", false)
	game.set("campaign", null)
	game.set("campaign_store", null)
	game.set("selected_stage_id", &"")
	game.set("selected_squad", [])
	game.set("pending_stage", null)
	game.set("current_battle", null)
	game.set("_pending_battle_ticket", {})
	game.set("_pending_campaign_mutation", null)
	game.set("_pending_launch_mutation", null)
	game.set("_campaign_battle_active", false)
	Engine.time_scale = 1.0
	var music := root.get_node_or_null("Music")
	if music != null and music.has_method("stop"):
		music.call("stop")
		for child: Node in music.get_children():
			if child is AudioStreamPlayer:
				var player := child as AudioStreamPlayer
				player.stop()
				player.stream = null
	var sfx := root.get_node_or_null("Sfx")
	if sfx != null and sfx.has_method("stop_all"):
		sfx.call("stop_all")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("FIRST_MISSION_TUTORIAL_REPLAY_TEST_OK")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)
