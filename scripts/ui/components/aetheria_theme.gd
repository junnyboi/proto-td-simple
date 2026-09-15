class_name AetheriaTheme
extends Theme

const GameTypographyType := preload("res://scripts/ui/game_typography.gd")
const StagingSkinType := preload("res://scripts/ui/components/staging_skin.gd")
const LunarisStyleType := preload("res://scripts/ui/components/lunaris_ops_style.gd")
const CJK_FONT_PATH := "res://assets/template/fonts/ManusGameSC-Common.woff2"
const CJK_FONT: FontFile = preload(CJK_FONT_PATH)
const PRIMARY_FONT := preload("res://assets/fonts/ManusCC0-Regular.ttf")
const MEDIUM_FONT := preload("res://assets/fonts/ManusCC0-Medium.ttf")
const BOLD_FONT := preload("res://assets/fonts/ManusCC0-Bold.ttf")

const COLORS := {
	&"backdrop": Color("040a12"),
	&"panel": Color("07111c"),
	&"secondary": Color("0b1827"),
	&"secondary_hover": Color("173849"),
	&"body": Color("f5efe1"),
	&"muted": Color("aebfd0"),
	&"primary": Color("d9b96e"),
	&"primary_hover": Color("f0d89a"),
	&"primary_pressed": Color("b58e46"),
	&"selected": Color("91eaf1"),
	&"selected_hover": Color("b9f8fb"),
	&"selected_pressed": Color("4f9ca8"),
	&"destructive": Color("6c2632"),
	&"destructive_hover": Color("913844"),
	&"destructive_pressed": Color("4b1822"),
	&"disabled_background": Color("111923"),
	&"disabled_text": Color("758494"),
	&"focus": Color("91eaf1"),
	&"boundary": Color("d9b96e"),
	&"dark_ink": Color("040a12"),
	&"transparent": Color("00000000"),
}

var _body_font: FontVariation
var _display_font: FontVariation


func _init() -> void:
	_body_font = FontVariation.new()
	_body_font.base_font = PRIMARY_FONT
	var cjk_font := _load_cjk_font()
	if cjk_font != null:
		_body_font.fallbacks = [cjk_font]
	else:
		_body_font.fallbacks = []
	_body_font.resource_name = "ManusCC0 with Simplified Chinese fallback"

	_display_font = FontVariation.new()
	_display_font.base_font = MEDIUM_FONT
	_display_font.fallbacks = [_body_font]
	_display_font.resource_name = "ManusCC0 display with Simplified Chinese fallback"

	default_font = _body_font
	default_font_size = GameTypographyType.BODY
	_build_buttons()
	_build_locale_list()
	_build_panels()
	_build_labels()


func _load_cjk_font() -> FontFile:
	if CJK_FONT == null:
		push_error("AetheriaTheme: CJK font unavailable at %s" % CJK_FONT_PATH)
		return null
	return CJK_FONT


func _build_buttons() -> void:
	_button(&"Button", &"secondary", &"body", &"secondary")
	_button(&"AuiPrimaryButton", &"primary", &"body", &"primary")
	_button(&"AuiSecondaryButton", &"secondary", &"body", &"secondary")
	_button(&"AuiSelectedButton", &"selected", &"body", &"selected")
	_button(&"AuiDestructiveButton", &"destructive", &"body", &"destructive")
	_button(&"AuiDisabledButton", &"disabled_background", &"disabled_text", &"disabled")


func _button(
		variation: StringName,
		_background: StringName,
		ink: StringName,
		role: StringName,
		base: StringName = &"Button",
	) -> void:
	if variation != base:
		set_type_variation(variation, base)
	set_font(&"font", variation, _display_font)
	set_font_size(&"font_size", variation, GameTypographyType.ACTION)
	for item_name: StringName in [
		&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color",
	]:
		set_color(item_name, variation, COLORS[ink])
	set_color(&"font_disabled_color", variation, COLORS[&"disabled_text"])
	var selected := role == &"primary" or role == &"selected"
	var normal_fill := (
		LunarisStyleType.SIMPLE_GOLD_SURFACE_SELECTED
		if selected
		else LunarisStyleType.SIMPLE_GOLD_SURFACE
	)
	set_stylebox(
		&"normal", variation, LunarisStyleType.simple_gold_surface(normal_fill, 12.0, 12, 3),
	)
	set_stylebox(
		&"hover",
		variation,
		LunarisStyleType.simple_gold_surface(
			LunarisStyleType.SIMPLE_GOLD_SURFACE_HOVER, 12.0, 12, 4,
		),
	)
	var pressed := LunarisStyleType.simple_gold_surface(
		LunarisStyleType.SIMPLE_GOLD_SURFACE_SELECTED, 12.0, 12, 4,
	)
	set_stylebox(&"pressed", variation, pressed)
	set_stylebox(&"hover_pressed", variation, pressed.duplicate())
	set_stylebox(&"focus", variation, _button_focus_box())
	set_stylebox(
		&"disabled",
		variation,
		LunarisStyleType.simple_gold_surface(Color("111923"), 12.0, 12, 3),
	)
	set_constant(&"outline_size", variation, 0)
	set_constant(&"h_separation", variation, 12)
	set_constant(&"icon_max_width", variation, 96)


func _build_locale_list() -> void:
	var variation := &"AuiLocaleList"
	set_type_variation(variation, &"ItemList")
	set_font(&"font", variation, _body_font)
	set_font_size(&"font_size", variation, GameTypographyType.BODY)
	set_color(&"font_color", variation, COLORS[&"body"])
	set_color(&"font_hovered_color", variation, COLORS[&"body"])
	set_color(&"font_selected_color", variation, COLORS[&"dark_ink"])
	set_color(&"font_hovered_selected_color", variation, COLORS[&"dark_ink"])
	set_stylebox(&"panel", variation, _flat_box(COLORS[&"secondary"], COLORS[&"boundary"], 3, 14, [24, 24, 24, 24]))
	set_stylebox(&"focus", variation, _focus_box(12))
	set_stylebox(&"hovered", variation, _flat_box(COLORS[&"secondary_hover"], COLORS[&"selected"], 3, 12, [8, 4, 8, 4]))
	set_stylebox(&"selected", variation, _flat_box(COLORS[&"selected"], COLORS[&"selected"], 3, 12, [8, 4, 8, 4]))
	set_stylebox(&"selected_focus", variation, _flat_box(COLORS[&"selected"], COLORS[&"focus"], 4, 12, [8, 4, 8, 4]))
	set_stylebox(&"hovered_selected", variation, _flat_box(COLORS[&"selected_hover"], COLORS[&"focus"], 4, 12, [8, 4, 8, 4]))
	set_stylebox(&"hovered_selected_focus", variation, _flat_box(COLORS[&"selected_hover"], COLORS[&"focus"], 4, 12, [8, 4, 8, 4]))
	set_stylebox(&"cursor", variation, _focus_box(12))
	set_stylebox(&"cursor_unfocused", variation, _flat_box(Color.TRANSPARENT, COLORS[&"boundary"], 3, 12, [0, 0, 0, 0]))
	set_constant(&"outline_size", variation, 0)


func _build_panels() -> void:
	_panel_flat(&"AuiReadingPanel", &"panel", &"primary", 28)
	_panel_flat(&"AuiHudPanel", &"backdrop", &"selected", 24)
	_panel_flat(&"AuiCardPanel", &"secondary", &"selected", 24)
	_panel_flat(&"AuiModalPanel", &"panel", &"primary", 28)
	_panel_flat(&"AuiInspectorPanel", &"secondary", &"primary", 24)
	_panel_flat(&"AuiRewardPanel", &"secondary", &"primary", 24)
	set_type_variation(&"AuiFocusRing", &"PanelContainer")
	set_stylebox(&"panel", &"AuiFocusRing", _focus_box(12))


func _panel_flat(
		variation: StringName,
		background: StringName,
		border: StringName,
		content_margin: int,
	) -> void:
	set_type_variation(variation, &"PanelContainer")
	set_stylebox(
		&"panel",
		variation,
		_flat_box(
			COLORS[background], COLORS[border], 3, 14,
			[content_margin, content_margin, content_margin, content_margin],
		),
	)


func _build_labels() -> void:
	_label(&"AuiTitleLabel", GameTypographyType.SCREEN_TITLE, &"body", true)
	_label(&"AuiHeadingLabel", GameTypographyType.SECTION_HEADING, &"primary", true)
	_label(&"AuiBodyLabel", GameTypographyType.BODY, &"body")
	_label(&"AuiDetailLabel", GameTypographyType.DETAIL, &"muted")
	_label(&"AuiDenseHeadingLabel", GameTypographyType.DENSE_HEADING, &"primary", true)
	_label(&"AuiDenseBodyLabel", GameTypographyType.DETAIL, &"body")
	_label(&"AuiDenseDetailLabel", GameTypographyType.BADGE, &"muted")
	_label(&"AuiLocaleLabel", GameTypographyType.BODY, &"body")
	_badge(&"AuiClassBadge", &"selected", &"dark_ink")
	_badge(&"AuiCostBadge", &"primary", &"dark_ink")
	_badge(&"AuiCooldownBadge", &"secondary", &"body")
	_badge(&"AuiLockedBadge", &"disabled_background", &"disabled_text")
	_badge(&"AuiCompletedBadge", &"selected", &"dark_ink")


func _label(variation: StringName, font_size: int, color: StringName, display := false) -> void:
	set_type_variation(variation, &"Label")
	set_font(&"font", variation, _display_font if display else _body_font)
	set_font_size(&"font_size", variation, font_size)
	set_color(&"font_color", variation, COLORS[color])


func _badge(variation: StringName, background: StringName, ink: StringName) -> void:
	_label(variation, GameTypographyType.BADGE, ink, true)
	set_stylebox(&"normal", variation, _flat_box(COLORS[background], COLORS[&"boundary"], 3, 10, [9, 5, 9, 5]))


func _focus_box(corner_radius := 3) -> StyleBoxFlat:
	var style := _flat_box(Color.TRANSPARENT, COLORS[&"primary_hover"], 3, corner_radius, [0, 0, 0, 0])
	style.set_expand_margin_all(3.0)
	return style


func _button_focus_box(corner_radius := 12) -> StyleBoxFlat:
	return StagingSkinType.golden_focus_tint_style(corner_radius)


func _flat_box(
		background: Color,
		border: Color,
		border_width: int,
		corner_radius: int,
		margins: Array,
	) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(corner_radius)
	style.content_margin_left = float(margins[0])
	style.content_margin_top = float(margins[1])
	style.content_margin_right = float(margins[2])
	style.content_margin_bottom = float(margins[3])
	return style
