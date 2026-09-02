extends SceneTree

const Catalog := preload("res://data/presentation/operator_visual_catalog.gd")

const CLASS_IDS := [
	"gunner", "mage_apprentice", "swordmaster",
]
const GENDERS := ["female", "male"]
const ACTIONS := ["idle", "attack"]
const DIRECTIONS := ["ne", "nw"]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := _args()
	var class_id := String(args.get("class", ""))
	var output := String(args.get("output", ""))
	if class_id not in CLASS_IDS or output.is_empty():
		push_error("Usage: -- --class <class_id> --output <absolute.png>")
		quit(2)
		return
	root.size = Vector2i(1920, 1080)
	var screen := ColorRect.new()
	screen.color = Color("07101c")
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(screen)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override(&"margin_left", 38)
	margin.add_theme_constant_override(&"margin_right", 38)
	margin.add_theme_constant_override(&"margin_top", 28)
	margin.add_theme_constant_override(&"margin_bottom", 28)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 18)
	margin.add_child(column)
	var title := Label.new()
	title.text = "%s — ADVANCED OPERATOR VISUAL MATRIX" % class_id.replace("_", " ").to_upper()
	title.add_theme_font_size_override(&"font_size", 28)
	title.add_theme_color_override(&"font_color", Color("e2c783"))
	column.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override(&"h_separation", 14)
	grid.add_theme_constant_override(&"v_separation", 14)
	column.add_child(grid)

	for gender: String in GENDERS:
		for action: String in ACTIONS:
			for direction: String in DIRECTIONS:
				grid.add_child(_cell(class_id, gender, action, direction))

	for _frame: int in 12:
		await process_frame
	var image := root.get_texture().get_image()
	var error := image.save_png(output)
	if error != OK:
		push_error("Failed to save %s: %s" % [output, error_string(error)])
		screen.queue_free()
		await process_frame
		quit(1)
		return
	print("ADVANCED_OPERATOR_VISUAL_CAPTURE_OK class=%s output=%s" % [class_id, output])
	screen.queue_free()
	image = null
	for _frame: int in 4:
		await process_frame
	quit(0)


func _cell(class_id: String, gender: String, action: String, direction: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(445, 225)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("0c1928")
	style.border_color = Color("6d624d")
	style.set_border_width_all(2)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override(&"panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	panel.add_child(row)
	var sprite := TextureRect.new()
	sprite.custom_minimum_size = Vector2(180, 196)
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var frame := 12 if action == "idle" else 6
	var animation := Catalog.get_animation(StringName("%s_%s" % [class_id, gender]))
	var mapping: Dictionary = animation.idle_by_direction if action == "idle" else animation.attack_by_direction
	var logical_id := StringName(mapping.get(StringName(direction), &""))
	sprite.texture = Art.texture(logical_id, frame)
	row.add_child(sprite)
	var facts := VBoxContainer.new()
	facts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	facts.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(facts)
	for value: String in [gender.to_upper(), action.to_upper(), direction.to_upper(), String(logical_id)]:
		var label := Label.new()
		label.text = value
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override(&"font_size", 18 if value.length() < 12 else 13)
		label.add_theme_color_override(&"font_color", Color("d7dbe2"))
		facts.add_child(label)
	return panel


func _args() -> Dictionary:
	var parsed := {}
	var values := OS.get_cmdline_user_args()
	var index := 0
	while index < values.size():
		var key := String(values[index])
		if key in ["--class", "--output"] and index + 1 < values.size():
			parsed[key.trim_prefix("--")] = String(values[index + 1])
			index += 2
			continue
		index += 1
	return parsed
