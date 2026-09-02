class_name LunarisOpsStyle
extends RefCounted

const StagingSkinType := preload("res://scripts/ui/components/staging_skin.gd")
const GameTypographyType := preload("res://scripts/ui/game_typography.gd")

const INK := Color("07111c")
const INK_DEEP := Color("040a12")
const GLASS := Color("0b1827e8")
const GLASS_SOFT := Color("13263bd9")
const GLASS_SELECTED := Color("173849eb")
const IVORY := Color("f5efe1")
const MUTED := Color("aebfd0")
const CYAN := Color("91eaf1")
const CYAN_DIM := Color("4f9ca8")
const GOLD := Color("d9b96e")
const GOLD_DIM := Color("79683f")
const VIOLET := Color("66577f")
const DANGER := Color("d16f78")
const MIN_CONTENT_PANEL_INSET := 24.0
const SIMPLE_GOLD_SURFACE := Color(0.025, 0.045, 0.07, 0.86)
const SIMPLE_GOLD_SURFACE_HOVER := Color(0.08, 0.07, 0.04, 0.90)
const SIMPLE_GOLD_SURFACE_SELECTED := Color(0.16, 0.12, 0.045, 0.90)


static func add_backdrop(root: Control, texture: Texture2D = null) -> void:
	var backdrop := ColorRect.new()
	backdrop.name = "AstralBackdrop"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = INK_DEEP
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(backdrop)
	if texture == null:
		return
	var art := TextureRect.new()
	art.name = "AstralBackdropArt"
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.texture = texture
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.modulate = Color(0.48, 0.62, 0.72, 0.24)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(art)


static func apply_panel(panel: PanelContainer, role: StringName) -> void:
	panel.add_theme_stylebox_override(&"panel", panel_style(role))


static func ensure_content_panel_insets(
	panel: PanelContainer,
	minimum: float = MIN_CONTENT_PANEL_INSET,
) -> void:
	if panel == null:
		return
	var source := panel.get_theme_stylebox(&"panel")
	if source == null or source is StyleBoxEmpty:
		return
	var style := source.duplicate() as StyleBox
	style.content_margin_left = maxf(style.content_margin_left, minimum)
	style.content_margin_top = maxf(style.content_margin_top, minimum)
	style.content_margin_right = maxf(style.content_margin_right, minimum)
	style.content_margin_bottom = maxf(style.content_margin_bottom, minimum)
	panel.add_theme_stylebox_override(&"panel", style)


static func panel_style(role: StringName) -> StyleBox:
	if role == &"screen" or role == &"dialog":
		return _texture_margin(StagingSkinType.command_deck_style(), MIN_CONTENT_PANEL_INSET)
	if role == &"hud":
		return _texture_margin(StagingSkinType.command_deck_style(), MIN_CONTENT_PANEL_INSET)
	if role == &"workspace":
		return _flat_panel(Color(0.035, 0.075, 0.12, 0.94), Color(CYAN.r, CYAN.g, CYAN.b, 0.34), 1, MIN_CONTENT_PANEL_INSET)
	if role == &"result" or role == &"memorial":
		var tint := Color.WHITE if role == &"result" else Color(0.88, 0.78, 0.90, 1.0)
		return _texture_margin(StagingSkinType.mission_card_style(tint), MIN_CONTENT_PANEL_INSET)
	if role == &"selected":
		return _flat_panel(GLASS_SELECTED, CYAN, 2, MIN_CONTENT_PANEL_INSET)
	if role == &"quiet":
		return _texture_margin(StagingSkinType.operation_tile_style(Color(0.86, 0.93, 1.0, 0.92)), MIN_CONTENT_PANEL_INSET)
	if role == &"danger":
		return _flat_panel(Color(0.18, 0.06, 0.09, 0.94), DANGER, 2, MIN_CONTENT_PANEL_INSET)
	return _flat_panel(GLASS, Color(GOLD.r, GOLD.g, GOLD.b, 0.46), 1, MIN_CONTENT_PANEL_INSET)


static func apply_button(button: Button, role: StringName) -> void:
	var ink := IVORY
	var normal: StyleBox
	var hover: StyleBox
	var pressed: StyleBox
	var disabled: StyleBox
	match role:
		&"primary", &"gold":
			normal = _texture_margin(
				StagingSkinType.primary_button_style(GOLD, Color("f0d89a")), 12.0,
			)
			hover = _texture_margin(
				StagingSkinType.primary_button_style(Color("f0d89a"), Color("fff8df")), 12.0,
			)
			pressed = _texture_margin(
				StagingSkinType.primary_button_style(Color("b58e46"), GOLD), 12.0,
			)
			ink = INK_DEEP
		&"selected":
			normal = _texture_margin(StagingSkinType.operation_tile_style(Color("b9f8fb")), 10.0)
			hover = _texture_margin(StagingSkinType.operation_tile_style(Color.WHITE), 10.0)
			pressed = _texture_margin(StagingSkinType.operation_tile_style(CYAN), 10.0)
		&"disabled":
			var muted_tint := Color(0.42, 0.48, 0.55, 0.56)
			normal = _texture_margin(StagingSkinType.operation_tile_style(muted_tint), 10.0)
			hover = normal
			pressed = normal
			ink = Color(MUTED.r, MUTED.g, MUTED.b, 0.58)
		&"danger":
			normal = _button_box(Color(0.18, 0.06, 0.09, 0.96), DANGER, 1)
			hover = _button_box(Color(0.28, 0.08, 0.12, 0.98), GOLD, 2)
			pressed = _button_box(Color(0.12, 0.03, 0.06, 1.0), GOLD, 2)
		_:
			normal = _texture_margin(StagingSkinType.operation_tile_style(), 10.0)
			hover = _texture_margin(StagingSkinType.operation_tile_style(Color("b9f8fb")), 10.0)
			pressed = _texture_margin(StagingSkinType.operation_tile_style(CYAN), 10.0)
	disabled = _button_box(Color(0.10, 0.14, 0.18, 0.86), Color(0.4, 0.46, 0.52, 0.28), 1)
	button.add_theme_stylebox_override(&"normal", normal)
	button.add_theme_stylebox_override(&"hover", hover)
	button.add_theme_stylebox_override(&"pressed", pressed)
	button.add_theme_stylebox_override(&"focus", StagingSkinType.golden_focus_tint_style())
	button.add_theme_stylebox_override(&"disabled", disabled)
	StagingSkinType.apply_display_type(button, 27, ink, 560)
	var presentation := button.get_node_or_null("PresentationLabel") as Label
	if presentation != null:
		var transparent := Color(0, 0, 0, 0)
		for item: StringName in [
			&"font_color", &"font_hover_color", &"font_pressed_color",
			&"font_hover_pressed_color", &"font_focus_color", &"font_disabled_color",
		]:
			button.add_theme_color_override(item, transparent)
		StagingSkinType.apply_display_type(presentation, 27, ink, 560)
	else:
		for item: StringName in [
			&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color",
		]:
			button.add_theme_color_override(item, ink)
		button.add_theme_color_override(&"font_disabled_color", ink)


static func apply_compact_rounded_button(
		button: Button,
		role: StringName,
		content_padding: float = 12.0,
		corner_radius: int = 12,
	) -> void:
	var ink := IVORY
	var normal_background := GLASS_SOFT
	var normal_border := Color(CYAN.r, CYAN.g, CYAN.b, 0.56)
	var hover_background := Color(0.08, 0.22, 0.29, 0.98)
	var hover_border := CYAN
	var pressed_background := Color(0.035, 0.11, 0.16, 1.0)
	var pressed_border := GOLD
	if role == &"gold" or role == &"primary":
		normal_background = Color(0.17, 0.12, 0.04, 0.96)
		normal_border = GOLD
		hover_background = Color(0.24, 0.17, 0.05, 0.98)
		hover_border = Color("fff2c6")
		pressed_background = Color(0.10, 0.07, 0.02, 1.0)
	elif role == &"danger":
		normal_background = Color(0.18, 0.06, 0.09, 0.96)
		normal_border = DANGER
		hover_background = Color(0.28, 0.08, 0.12, 0.98)
		hover_border = GOLD
		pressed_background = Color(0.12, 0.03, 0.06, 1.0)
	elif role == &"selected":
		normal_background = GLASS_SELECTED
		normal_border = CYAN
	var normal := _rounded_button_box(
		normal_background, normal_border, 1, corner_radius, content_padding,
	)
	var hover := _rounded_button_box(
		hover_background, hover_border, 2, corner_radius, content_padding,
	)
	var pressed := _rounded_button_box(
		pressed_background, pressed_border, 2, corner_radius, content_padding,
	)
	var disabled := _rounded_button_box(
		Color(0.10, 0.14, 0.18, 0.86),
		Color(0.4, 0.46, 0.52, 0.28),
		1,
		corner_radius,
		content_padding,
	)
	button.add_theme_stylebox_override(&"normal", normal)
	button.add_theme_stylebox_override(&"hover", hover)
	button.add_theme_stylebox_override(&"pressed", pressed)
	button.add_theme_stylebox_override(
		&"focus", StagingSkinType.golden_focus_tint_style(corner_radius),
	)
	button.add_theme_stylebox_override(&"disabled", disabled)
	StagingSkinType.apply_display_type(button, GameTypographyType.ACTION, ink, 560)
	for item: StringName in [
		&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color",
	]:
		button.add_theme_color_override(item, ink)
	button.add_theme_color_override(&"font_disabled_color", Color(MUTED.r, MUTED.g, MUTED.b, 0.68))


## Texture-free surface used by the leaderboard. The fill remains uniformly
## translucent in every state and the rounded gold edge carries the hierarchy.
static func apply_simple_gold_button(
		button: Button,
		selected: bool = false,
		content_padding: float = 12.0,
		corner_radius: int = 12,
	) -> void:
	var normal_fill := SIMPLE_GOLD_SURFACE_SELECTED if selected else SIMPLE_GOLD_SURFACE
	button.add_theme_stylebox_override(
		&"normal",
		simple_gold_surface(normal_fill, content_padding, corner_radius, 1),
	)
	button.add_theme_stylebox_override(
		&"hover",
		simple_gold_surface(SIMPLE_GOLD_SURFACE_HOVER, content_padding, corner_radius, 2),
	)
	button.add_theme_stylebox_override(
		&"pressed",
		simple_gold_surface(SIMPLE_GOLD_SURFACE_SELECTED, content_padding, corner_radius, 2),
	)
	button.add_theme_stylebox_override(
		&"focus",
		simple_gold_surface(Color(GOLD.r, GOLD.g, GOLD.b, 0.10), 0.0, corner_radius, 2),
	)
	button.add_theme_stylebox_override(
		&"disabled",
		simple_gold_surface(Color(0.025, 0.035, 0.05, 0.64), content_padding, corner_radius, 1),
	)


static func simple_gold_surface(
		background: Color = SIMPLE_GOLD_SURFACE,
		content_padding: float = MIN_CONTENT_PANEL_INSET,
		corner_radius: int = 14,
		border_width: int = 1,
	) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = GOLD
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(corner_radius)
	style.content_margin_left = content_padding
	style.content_margin_top = content_padding
	style.content_margin_right = content_padding
	style.content_margin_bottom = content_padding
	return style


static func apply_label(label: Label, role: StringName) -> void:
	var color := IVORY
	var size := 27
	var display := false
	var weight := 520
	match role:
		&"eyebrow":
			color = GOLD
			size = GameTypographyType.DETAIL
			display = true
		&"title":
			color = IVORY
			size = 57
			display = true
			weight = 620
		&"heading":
			color = GOLD
			size = 33
			display = true
			weight = 580
		&"body":
			color = IVORY
			size = 27
		&"detail", &"dense_detail":
			color = MUTED
			size = GameTypographyType.DETAIL
		&"metric":
			color = CYAN
			size = 32
			display = true
	if display:
		StagingSkinType.apply_display_type(label, size, color, weight)
	else:
		StagingSkinType.apply_body_type(label, size, color)
	label.add_theme_constant_override(&"outline_size", 0)


static func apply_line_edit(field: LineEdit, invalid: bool = false) -> void:
	var border := DANGER if invalid else Color(CYAN.r, CYAN.g, CYAN.b, 0.52)
	field.add_theme_stylebox_override(&"normal", _button_box(GLASS_SOFT, border, 1))
	field.add_theme_stylebox_override(&"focus", _button_box(Color(CYAN.r, CYAN.g, CYAN.b, 0.08), GOLD, 2))
	field.add_theme_stylebox_override(&"read_only", _button_box(Color(0.12, 0.16, 0.2, 0.78), GOLD_DIM, 1))
	field.add_theme_color_override(&"font_color", IVORY)
	field.add_theme_color_override(&"font_selected_color", INK_DEEP)
	field.add_theme_color_override(&"font_uneditable_color", MUTED)
	field.add_theme_color_override(&"caret_color", GOLD)
	field.add_theme_color_override(&"selection_color", CYAN_DIM)
	field.add_theme_color_override(&"placeholder_color", MUTED)
	StagingSkinType.apply_body_type(field, 27, IVORY)


static func apply_progress(progress: ProgressBar) -> void:
	progress.add_theme_stylebox_override(&"background", _progress_box(Color(0.22, 0.3, 0.36, 0.64)))
	progress.add_theme_stylebox_override(&"fill", _progress_box(CYAN))


static func _texture_margin(style: StyleBox, margin: float) -> StyleBox:
	style.content_margin_left = margin
	style.content_margin_top = margin
	style.content_margin_right = margin
	style.content_margin_bottom = margin
	return style


static func _flat_panel(background: Color, border: Color, width: int, margin: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(3)
	style.content_margin_left = margin
	style.content_margin_top = margin
	style.content_margin_right = margin
	style.content_margin_bottom = margin
	return style


static func _button_box(background: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(3)
	style.content_margin_left = 18.0
	style.content_margin_top = 10.0
	style.content_margin_right = 18.0
	style.content_margin_bottom = 10.0
	return style


static func _rounded_button_box(
		background: Color,
		border: Color,
		width: int,
		corner_radius: int,
		content_padding: float,
	) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(corner_radius)
	style.content_margin_left = content_padding
	style.content_margin_top = content_padding
	style.content_margin_right = content_padding
	style.content_margin_bottom = content_padding
	return style


static func _progress_box(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(1)
	return style
