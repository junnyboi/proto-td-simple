extends Control


func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var backdrop := ColorRect.new()
	backdrop.color = Color("0d111d")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var controls_script := load("res://scripts/ui/battle_controls.gd") as Script
	if controls_script == null:
		_fail("battle controls script did not load")
		return
	var controls := controls_script.new() as Control
	controls.name = "BattleControls"
	controls.size = Vector2(get_viewport_rect().size)
	add_child(controls)
	controls.call("_build_row")
	for _frame: int in range(6):
		await get_tree().process_frame
	print("viewport=%s root=%s controls=%s deck=%s" % [get_viewport_rect().size, size, controls.size, controls.call("command_deck_rect")])

	for button_name: String in ["PauseButton", "SpeedButton", "ResignButton"]:
		var button := controls.find_child(button_name, true, false) as Button
		if button == null:
			_fail("%s is missing" % button_name)
			return
		if not button.custom_minimum_size.is_equal_approx(Vector2(112.0, 48.0)):
			_fail("%s does not use the compact 112×48 target" % button_name)
			return
		print("%s text=%s position=%s size=%s combined=%s parent_size=%s" % [button_name, button.text, button.position, button.size, button.get_combined_minimum_size(), button.get_parent().size])
		if button.size.y > 48.5 or button.size.y < 44.0:
			_fail("%s rendered at an invalid %.1fpx height" % [button_name, button.size.y])
			return

	var output := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			output = argument.trim_prefix("--out=")
	if not output.is_empty():
		await RenderingServer.frame_post_draw
		var error := get_viewport().get_texture().get_image().save_png(output)
		if error != OK:
			_fail("could not save visual capture: %d" % error)
			return
	print("BATTLE_CONTROLS_HEIGHT_HARNESS_OK")
	get_tree().quit(0)


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
