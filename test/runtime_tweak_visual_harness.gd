extends Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	var output_path := _output_path()
	if output_path.is_empty():
		push_error("runtime tweak visual output path missing")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	TweakControls.reset_all()
	TweakControls.set_value(&"player.attack_multiplier", 1.5)
	Game.start_battle(&"s2", true)
	for _frame: int in range(16):
		await get_tree().process_frame
	var battle := Game.content
	if battle == null or not bool(battle.get("startup_succeeded")):
		push_error("runtime tweak visual battle failed to start")
		get_tree().quit(1)
		return
	if not TweakControls.open_panel():
		push_error("runtime tweak visual panel failed to open")
		get_tree().quit(1)
		return
	TweakControls.panel.category_selector.select(3)
	TweakControls.panel.refresh()
	for _frame: int in range(3):
		await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(output_path)
	if error != OK:
		push_error("runtime tweak visual capture failed: %s" % error_string(error))
		get_tree().quit(1)
		return
	print("RUNTIME_TWEAK_VISUAL_OK|%s|%dx%d" % [
		output_path, image.get_width(), image.get_height(),
	])
	TweakControls.close_panel()
	TweakControls.reset_all()
	TweakControls.flush_now()
	if Game.content != null:
		Game.content.queue_free()
	Game.content = null
	Game.current_battle = null
	Game.pending_stage = null
	Music.stop()
	Sfx.stop_all()
	for _frame: int in range(16):
		await get_tree().process_frame
	get_tree().quit(0)


func _output_path() -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			return argument.trim_prefix("--output=")
	return ""
