extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	await process_frame
	var game := root.get_node("Game")
	game.call("set_run_seed", 3302)
	assert(bool(game.call("start_campaign", false, true)))
	game.call("start_battle", &"s1", true)
	for frame: int in 20:
		await process_frame
	var battle := game.get("content") as Node
	assert(battle != null and bool(battle.get("startup_succeeded")))
	for button: Node in battle.find_children("*", "Button", true, false):
		if (button as Button).text == "Skip tutorial":
			button.emit_signal("pressed")
			break
	for frame: int in 5:
		await process_frame
	var output := OS.get_environment("OPERATOR_HUD_CAPTURE")
	assert(not output.is_empty())
	assert(root.get_texture().get_image().save_png(output) == OK)
	game.set("content", null)
	battle.get_parent().remove_child(battle)
	battle.free()
	game.call("_reset_campaign_runtime")
	print("OPERATOR_V3_HUD_CAPTURE_OK")
	quit(0)
