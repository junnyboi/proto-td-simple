extends Node


var _mode := "campaign"
var _output_path := "/tmp/proto-td-narrative.png"
var _locale := "en-US"
var _text_scale := 1.0
var _stage_id := "s9"
var _results_outcome := "clear"


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--mode="):
			_mode = argument.trim_prefix("--mode=")
		elif argument.begins_with("--out="):
			_output_path = argument.trim_prefix("--out=")
		elif argument.begins_with("--locale="):
			_locale = argument.trim_prefix("--locale=")
		elif argument.begins_with("--text-scale="):
			_text_scale = clampf(argument.trim_prefix("--text-scale=").to_float(), 0.8, 1.5)
		elif argument.begins_with("--stage="):
			_stage_id = argument.trim_prefix("--stage=")
		elif argument.begins_with("--outcome="):
			_results_outcome = argument.trim_prefix("--outcome=")
	call_deferred("_run")


func _run() -> void:
	var i18n := get_tree().root.get_node_or_null("I18n")
	if i18n != null:
		i18n.call("set_locale", StringName(_locale))
	var text_scale := get_tree().root.get_node_or_null("TextScale")
	if text_scale != null:
		text_scale.call("set_scale", _text_scale)
	var game := get_tree().root.get_node("Game")
	if _mode == "campaign":
		game.call("set_run_seed", 3310)
		game.call("start_campaign", false, true)
		var scene_path := "res://scenes/stage_select.tscn"
		var screen := load(scene_path).instantiate() as Control
		_mount(screen)
		for _frame: int in range(10):
			await get_tree().process_frame
	elif _mode == "results":
		var cleared := _results_outcome == "clear"
		game.call("set_run_seed", 3309)
		game.call("start_campaign", false, true)
		game.set("last_result", {
			"stage_id": &"s1",
			"result": BattleModel.Result.CLEAR if cleared else BattleModel.Result.DEFEAT,
			"stars": 3 if cleared else 0,
			"kills": 14,
			"leaks": 0 if cleared else 6,
			"rewards_granted": [{"kind": "currency", "id": "marks", "amount": 40}],
			"dead_hero_ids": [],
		})
		_mount(load("res://scenes/results.tscn").instantiate())
		await get_tree().create_timer(0.9).timeout
		for _frame: int in range(3):
			await get_tree().process_frame
	else:
		push_error("Unknown narrative visual mode: %s" % _mode)
		get_tree().quit(1)
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(_output_path)
	if error != OK:
		push_error("Could not save narrative capture: %s" % error)
		get_tree().quit(1)
		return
	await _cleanup()
	print("NARRATIVE_VISUAL_CAPTURE_OK mode=%s path=%s locale=%s stage=%s text_scale=%.2f outcome=%s" % [_mode, _output_path, _locale, _stage_id, _text_scale, _results_outcome])
	get_tree().quit(0)


func _mount(node: Node) -> void:
	get_tree().root.add_child(node)


func _cleanup() -> void:
	var game := get_tree().root.get_node_or_null("Game")
	if game != null:
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
	var music := get_tree().root.get_node_or_null("Music")
	if music != null and music.has_method("stop"):
		music.call("stop")
	var sfx := get_tree().root.get_node_or_null("Sfx")
	if sfx != null and sfx.has_method("stop_all"):
		sfx.call("stop_all")
	for _frame: int in range(12):
		await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
