extends Node

const VIEW_PREFERENCES := preload("res://scripts/view/view_preferences.gd")
const PREFERENCES_PATH := "user://title_responsive_visual_harness.cfg"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := _parse_user_args()
	var output_path := String(args.get("output", ""))
	var show_settings := String(args.get("settings", "false")).to_lower() == "true"
	var settings_focus := String(args.get("settings-focus", ""))
	var locale_id := StringName(args.get("locale", "en-US"))
	if output_path.is_empty():
		push_error("visual output path missing")
		get_tree().quit(1)
		return
	_remove_preferences()
	VIEW_PREFERENCES.set_locale(locale_id, PREFERENCES_PATH)
	VIEW_PREFERENCES.set_title_music_enabled(false, PREFERENCES_PATH)
	VIEW_PREFERENCES.set_reduced_motion(true, PREFERENCES_PATH)
	var title := load("res://scenes/title.tscn").instantiate() as Control
	title.call("set_preferences_path", PREFERENCES_PATH)
	add_child(title)
	for _frame: int in range(5):
		await get_tree().process_frame
	if show_settings:
		title.call("_open_settings")
		for _frame: int in range(3):
			await get_tree().process_frame
		var scroll := title.find_child("SettingsScroll", true, false) as ScrollContainer
		if scroll != null:
			scroll.follow_focus = false
			if settings_focus in ["background-downloads", "clear-player-data"]:
				var target_name := (
					"ClearPlayerDataButton"
					if settings_focus == "clear-player-data"
					else "BackgroundDownloadsButton"
				)
				var target := title.find_child(target_name, true, false) as Control
				if target != null:
					target.grab_focus()
					scroll.ensure_control_visible(target)
			else:
				scroll.scroll_vertical = 0
			await get_tree().process_frame
		if title.call("screen_state") != &"SETTINGS":
			push_error("settings visual state did not open")
			get_tree().quit(1)
			return
	# Viewport texture reads can otherwise race the render thread and capture a
	# stale title frame (or a cleared buffer) while a clean cache prepares shaders.
	await get_tree().create_timer(1.0).timeout
	var image: Image = null
	var visible_frames := 0
	for _capture_attempt: int in range(100):
		RenderingServer.force_draw()
		image = get_viewport().get_texture().get_image()
		if _has_visible_content(image):
			visible_frames += 1
			if visible_frames >= 2:
				break
		else:
			visible_frames = 0
		await get_tree().create_timer(0.1).timeout
	if visible_frames < 2:
		push_error("visual capture remained blank after render synchronization")
		get_tree().quit(1)
		return
	var save_error := image.save_png(output_path)
	if save_error != OK:
		push_error("visual capture failed: %s" % error_string(save_error))
		get_tree().quit(1)
		return
	print(
		"TITLE_RESPONSIVE_VISUAL_OK|%s|%dx%d|settings=%s"
		% [output_path, image.get_width(), image.get_height(), show_settings]
	)
	if get_tree().root.get_node_or_null("Game") != null:
		get_tree().root.get_node("Game").set("content", null)
	var music := get_tree().root.get_node_or_null("Music")
	if music != null:
		music.call("stop")
	var sfx := get_tree().root.get_node_or_null("Sfx")
	if sfx != null:
		sfx.call("stop_all")
	title.queue_free()
	for _frame: int in range(16):
		await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	_remove_preferences()
	get_tree().quit(0)


func _parse_user_args() -> Dictionary:
	var parsed: Dictionary = {}
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with("--") or not argument.contains("="):
			continue
		var separator := argument.find("=")
		parsed[argument.substr(2, separator - 2)] = argument.substr(separator + 1)
	return parsed


func _remove_preferences() -> void:
	if FileAccess.file_exists(PREFERENCES_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFERENCES_PATH))


func _has_visible_content(image: Image) -> bool:
	if image == null or image.is_empty():
		return false
	var step_x := maxi(1, image.get_width() / 96)
	var step_y := maxi(1, image.get_height() / 54)
	var bright_samples := 0
	for y: int in range(0, image.get_height(), step_y):
		for x: int in range(0, image.get_width(), step_x):
			var pixel := image.get_pixel(x, y)
			if maxf(pixel.r, maxf(pixel.g, pixel.b)) >= 0.2:
				bright_samples += 1
				if bright_samples >= 8:
					return true
	return false
