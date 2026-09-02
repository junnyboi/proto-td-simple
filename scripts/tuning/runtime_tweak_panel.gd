class_name RuntimeTweakPanel
extends Control

signal close_requested

const Catalog := preload("res://scripts/tuning/runtime_tweak_catalog.gd")
const ACCENT := Color("64e6ff")
const TEXT := Color("f4f4f4")
const MUTED := Color("9aa8b5")
const PANEL_COLOR := Color("111827")
const ROW_COLOR := Color("172235")
const ROW_HEIGHT := 104.0
const ROW_TITLE_FONT_SIZE := 30
const ROW_DESCRIPTION_FONT_SIZE := 24
const ROW_MODE_FONT_SIZE := 22
const ROW_CONTROL_HEIGHT := 56.0
const ROW_MODE_WIDTH := 180.0

var service: Node = null
var frame: PanelContainer = null
var category_selector: OptionButton = null
var search_field: LineEdit = null
var rows: VBoxContainer = null
var status_label: Label = null
var close_button: Button = null
var reset_all_button: Button = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 90
	visible = false
	_build_ui()
	get_viewport().size_changed.connect(_relayout)
	_relayout()


func configure(authority: Node) -> void:
	service = authority
	_populate_categories()
	if not service.value_changed.is_connected(_on_value_changed):
		service.value_changed.connect(_on_value_changed)
	if not service.persistence_state_changed.is_connected(_on_persistence_state_changed):
		service.persistence_state_changed.connect(_on_persistence_state_changed)
	refresh()


func refresh() -> void:
	if service == null or category_selector.item_count == 0:
		return
	_refresh_panel_style()
	_clear_rows()
	var category := StringName(category_selector.get_selected_metadata())
	var query := search_field.text.strip_edges().to_lower()
	for descriptor: Dictionary in Catalog.descriptors_for_category(category):
		var searchable := "%s %s %s" % [
			descriptor[&"label"], descriptor[&"description"], descriptor[&"id"],
		]
		if not query.is_empty() and query not in searchable.to_lower():
			continue
		rows.add_child(_build_row(descriptor))
	_refresh_status()


func _build_ui() -> void:
	var backdrop := ColorRect.new()
	backdrop.name = "ModalBackdrop"
	backdrop.color = Color(0.01, 0.02, 0.04, 0.78)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	frame = PanelContainer.new()
	frame.name = "TweakFrame"
	add_child(frame)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override(&"margin_left", 16)
	margin.add_theme_constant_override(&"margin_top", 14)
	margin.add_theme_constant_override(&"margin_right", 16)
	margin.add_theme_constant_override(&"margin_bottom", 14)
	frame.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override(&"separation", 8)
	margin.add_child(content)

	var header := HBoxContainer.new()
	header.custom_minimum_size.y = 44.0
	content.add_child(header)
	var title := Label.new()
	title.text = "RUNTIME TWEAK CONTROLS"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override(&"font_size", 22)
	title.add_theme_color_override(&"font_color", TEXT)
	header.add_child(title)
	var hint := Label.new()
	hint.text = "F10"
	hint.add_theme_color_override(&"font_color", ACCENT)
	header.add_child(hint)
	close_button = Button.new()
	close_button.name = "CloseButton"
	close_button.text = "RESUME"
	close_button.pressed.connect(close_requested.emit)
	header.add_child(close_button)

	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override(&"separation", 8)
	content.add_child(toolbar)
	category_selector = OptionButton.new()
	category_selector.name = "CategorySelector"
	category_selector.custom_minimum_size = Vector2(190.0, 38.0)
	category_selector.item_selected.connect(_on_category_selected)
	toolbar.add_child(category_selector)
	search_field = LineEdit.new()
	search_field.name = "SearchField"
	search_field.placeholder_text = "Search this category"
	search_field.clear_button_enabled = true
	search_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_field.text_changed.connect(_on_search_changed)
	toolbar.add_child(search_field)
	reset_all_button = Button.new()
	reset_all_button.name = "ResetAllButton"
	reset_all_button.text = "RESET ALL"
	reset_all_button.pressed.connect(_on_reset_all)
	toolbar.add_child(reset_all_button)

	var scroll := ScrollContainer.new()
	scroll.name = "TweakScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.follow_focus = true
	content.add_child(scroll)
	rows = VBoxContainer.new()
	rows.name = "Rows"
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override(&"separation", 5)
	scroll.add_child(rows)

	var footer := HBoxContainer.new()
	footer.custom_minimum_size.y = 30.0
	content.add_child(footer)
	var boundary_note := Label.new()
	boundary_note.text = "Application timing is shown per control. Gameplay changes mark the battle TWEAKED."
	boundary_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	boundary_note.add_theme_color_override(&"font_color", MUTED)
	boundary_note.add_theme_font_size_override(&"font_size", 12)
	boundary_note.clip_text = true
	footer.add_child(boundary_note)
	status_label = Label.new()
	status_label.name = "StatusLabel"
	status_label.custom_minimum_size.x = 170.0
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_label.add_theme_color_override(&"font_color", ACCENT)
	status_label.add_theme_font_size_override(&"font_size", 12)
	footer.add_child(status_label)


func _build_row(descriptor: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.name = "Row_%s" % String(descriptor[&"id"]).replace(".", "_")
	panel.custom_minimum_size.y = ROW_HEIGHT
	panel.tooltip_text = "%s\n%s" % [descriptor[&"description"], descriptor[&"id"]]
	panel.add_theme_stylebox_override(&"panel", _flat_style(Color(ROW_COLOR, 0.88), 6.0))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override(&"margin_left", 10)
	margin.add_theme_constant_override(&"margin_top", 6)
	margin.add_theme_constant_override(&"margin_right", 8)
	margin.add_theme_constant_override(&"margin_bottom", 6)
	panel.add_child(margin)
	var line := HBoxContainer.new()
	line.add_theme_constant_override(&"separation", 8)
	margin.add_child(line)

	var copy := VBoxContainer.new()
	copy.name = "TweakCopy"
	copy.custom_minimum_size.x = 330.0
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(copy)
	var label := Label.new()
	label.name = "TweakLabel"
	label.text = String(descriptor[&"label"])
	label.add_theme_color_override(&"font_color", TEXT)
	label.add_theme_font_size_override(&"font_size", ROW_TITLE_FONT_SIZE)
	copy.add_child(label)
	var description := Label.new()
	description.name = "TweakDescription"
	description.text = String(descriptor[&"description"])
	description.add_theme_color_override(&"font_color", MUTED)
	description.add_theme_font_size_override(&"font_size", ROW_DESCRIPTION_FONT_SIZE)
	description.clip_text = true
	description.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	copy.add_child(description)

	var mode := Label.new()
	mode.name = "TweakApplyMode"
	mode.custom_minimum_size.x = ROW_MODE_WIDTH
	mode.text = String(descriptor[&"apply_mode"]).replace("_", " ")
	mode.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mode.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mode.add_theme_color_override(&"font_color", ACCENT)
	mode.add_theme_font_size_override(&"font_size", ROW_MODE_FONT_SIZE)
	line.add_child(mode)

	var control_host := HBoxContainer.new()
	control_host.name = "TweakControlHost"
	control_host.custom_minimum_size.x = 330.0
	control_host.custom_minimum_size.y = ROW_CONTROL_HEIGHT
	control_host.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	control_host.add_theme_constant_override(&"separation", 6)
	line.add_child(control_host)
	var current: Variant = service.call("value", descriptor[&"id"], descriptor[&"default"])
	match StringName(descriptor[&"type"]):
		&"bool":
			var toggle := CheckButton.new()
			toggle.name = "TweakToggle"
			toggle.text = "ON" if bool(current) else "OFF"
			toggle.button_pressed = bool(current)
			toggle.custom_minimum_size.y = ROW_CONTROL_HEIGHT
			toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			toggle.toggled.connect(func(enabled: bool) -> void:
				toggle.text = "ON" if enabled else "OFF"
				_request_value(descriptor[&"id"], enabled)
			)
			control_host.add_child(toggle)
		&"color":
			var picker := ColorPickerButton.new()
			picker.name = "TweakColorPicker"
			picker.color = current as Color
			picker.custom_minimum_size = Vector2(240.0, ROW_CONTROL_HEIGHT)
			picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			picker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			picker.color_changed.connect(func(color: Color) -> void:
				_request_value(descriptor[&"id"], color)
			)
			control_host.add_child(picker)
		_:
			_add_numeric_control(control_host, descriptor, current)
	var reset := Button.new()
	reset.name = "TweakResetButton"
	reset.text = "↺"
	reset.tooltip_text = "Reset to default"
	reset.custom_minimum_size = Vector2(ROW_CONTROL_HEIGHT, ROW_CONTROL_HEIGHT)
	reset.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	reset.pressed.connect(func() -> void:
		service.call("reset_value", descriptor[&"id"])
		refresh()
	)
	control_host.add_child(reset)
	return panel


func _add_numeric_control(host: HBoxContainer, descriptor: Dictionary, current: Variant) -> void:
	var guard: Array[bool] = [false]
	var slider := HSlider.new()
	slider.name = "TweakSlider"
	slider.min_value = float(descriptor[&"minimum"])
	slider.max_value = float(descriptor[&"maximum"])
	slider.step = float(descriptor[&"step"])
	slider.value = float(current)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(165.0, ROW_CONTROL_HEIGHT)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	host.add_child(slider)
	var spin := SpinBox.new()
	spin.name = "TweakValue"
	spin.min_value = slider.min_value
	spin.max_value = slider.max_value
	spin.step = slider.step
	spin.value = slider.value
	spin.custom_minimum_size = Vector2(118.0, ROW_CONTROL_HEIGHT)
	spin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	spin.suffix = String(descriptor[&"unit"])
	host.add_child(spin)
	slider.value_changed.connect(func(next: float) -> void:
		if guard[0]:
			return
		guard[0] = true
		spin.value = next
		guard[0] = false
		_request_value(descriptor[&"id"], next)
	)
	spin.value_changed.connect(func(next: float) -> void:
		if guard[0]:
			return
		guard[0] = true
		slider.value = next
		guard[0] = false
		_request_value(descriptor[&"id"], next)
	)


func _request_value(identifier: StringName, candidate: Variant) -> void:
	var result: Dictionary = service.call("set_value", identifier, candidate)
	if not bool(result.get(&"ok", false)):
		status_label.text = "Invalid value"


func _populate_categories() -> void:
	category_selector.clear()
	for category: StringName in Catalog.categories():
		category_selector.add_item(String(category).capitalize())
		category_selector.set_item_metadata(category_selector.item_count - 1, category)


func _clear_rows() -> void:
	for child: Node in rows.get_children():
		rows.remove_child(child)
		child.queue_free()


func _refresh_panel_style() -> void:
	var opacity := 0.96
	if service != null:
		opacity = float(service.call("value", &"ui.panel_opacity", opacity))
	frame.add_theme_stylebox_override(&"panel", _flat_style(Color(PANEL_COLOR, opacity), 10.0))


func _flat_style(color: Color, radius: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = roundi(radius)
	style.corner_radius_top_right = roundi(radius)
	style.corner_radius_bottom_left = roundi(radius)
	style.corner_radius_bottom_right = roundi(radius)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(ACCENT, 0.28)
	return style


func _relayout() -> void:
	var viewport := get_viewport_rect().size
	position = Vector2.ZERO
	size = viewport
	var margin := 10.0 if viewport.y > viewport.x else 18.0
	frame.position = Vector2.ONE * margin
	frame.size = Vector2(
		viewport.x - margin * 2.0,
		viewport.y - margin * 2.0 - 58.0,
	)
	if category_selector != null:
		var portrait := viewport.y > viewport.x
		category_selector.custom_minimum_size.x = 150.0 if portrait else 190.0
		reset_all_button.visible = not portrait
		close_button.text = "X" if portrait else "RESUME"


func _on_category_selected(_index: int) -> void:
	refresh()


func _on_search_changed(_query: String) -> void:
	refresh()


func _on_reset_all() -> void:
	service.call("reset_all")
	refresh()


func _on_value_changed(_identifier: StringName, _value: Variant) -> void:
	_refresh_panel_style()
	_refresh_status()


func _on_persistence_state_changed(_state: StringName) -> void:
	_refresh_status()


func _refresh_status() -> void:
	if service == null or status_label == null:
		return
	status_label.text = "%d modified  •  %s" % [
		int(service.call("modified_count")),
		String(service.get("persistence_state")).replace("_", " ").capitalize(),
	]
