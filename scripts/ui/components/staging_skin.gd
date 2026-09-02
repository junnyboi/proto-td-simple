class_name StagingSkin
extends RefCounted

const CINZEL := preload("res://assets/fonts/Cinzel-Variable.ttf")
const CJK_FONT := preload("res://assets/fonts/GameTemplateTDSansSC.otf")

const LUNARIS_SEAL := preload("res://assets/ui/staging/icons/lunaris_seal.png")
const MISSION_ICON := preload("res://assets/ui/staging/icons/mission.png")
const EXIT_ICON := preload("res://assets/ui/staging/icons/exit.png")
const SETTINGS_ICON := preload("res://assets/ui/staging/icons/settings.png")
const STATUS_DIAMOND := preload("res://assets/ui/staging/icons/status_diamond.png")
const AETHER_ICON := preload("res://assets/ui/staging/icons/resource_aether.png")
const SIGIL_ICON := preload("res://assets/ui/staging/icons/resource_sigil.png")
const STAMINA_ICON := preload("res://assets/ui/staging/icons/resource_stamina.png")

const COMMAND_DECK_FRAME := preload("res://assets/ui/staging/frames/command_deck.png")
const MISSION_CARD_FRAME := preload("res://assets/ui/staging/frames/mission_card.png")
const OPERATION_TILE_FRAME := preload("res://assets/ui/staging/frames/operation_tile.png")
const PRIMARY_BUTTON_FRAME := preload("res://assets/ui/staging/frames/primary_button.png")
const RESOURCE_CHIP_FRAME := preload("res://assets/ui/staging/frames/resource_chip.png")
const NAVBAR_FRAME := preload("res://assets/ui/staging/frames/navbar.png")
const COMPANY_HUD_PLATE_FRAME := preload(
	"res://assets/ui/staging/frames/company_hud_plate.png"
)
const COMPANY_NAVIGATION_RAIL_FRAME := preload(
	"res://assets/ui/staging/frames/company_navigation_rail.png"
)

const GOLD := Color("d9b96e")
const BRIGHT_GOLD := Color("f0d89a")
const MOON_CYAN := Color("91eaf1")
const IVORY := Color("f5efe1")
const MUTED := Color("aebfd0")
const INK := Color("07111c")
const FOCUS_TINT_ALPHA := 0.12

static var _display_font: FontVariation
static var _body_font: FontVariation


static func body_font() -> FontVariation:
	if _body_font != null:
		return _body_font
	_body_font = FontVariation.new()
	_body_font.base_font = CJK_FONT
	_body_font.fallbacks = [ThemeDB.fallback_font]
	_body_font.resource_name = "Game template - TD bundled Chinese body"
	return _body_font


static func display_font() -> FontVariation:
	if _display_font != null:
		return _display_font
	_display_font = FontVariation.new()
	_display_font.base_font = CINZEL
	_display_font.fallbacks = [body_font()]
	_display_font.variation_opentype = {&"wght": 520}
	_display_font.resource_name = "Cinzel with Game template - TD CJK fallback"
	return _display_font


static func apply_body_type(
	control: Control,
	size: int,
	color: Color = IVORY,
) -> void:
	control.add_theme_font_override(&"font", body_font())
	control.add_theme_font_size_override(&"font_size", size)
	control.add_theme_color_override(&"font_color", color)


static func apply_display_type(
	control: Control,
	size: int,
	color: Color = IVORY,
	weight: int = 520,
) -> void:
	var font := FontVariation.new()
	font.base_font = CINZEL
	font.fallbacks = [body_font()]
	font.variation_opentype = {&"wght": weight}
	control.add_theme_font_override(&"font", font)
	control.add_theme_font_size_override(&"font_size", size)
	control.add_theme_color_override(&"font_color", color)


static func command_deck_style(modulate: Color = Color.WHITE) -> StyleBoxTexture:
	return _texture_style(
		COMMAND_DECK_FRAME,
		Vector4(68.0, 52.0, 68.0, 52.0),
		Vector4(48.0, 36.0, 48.0, 36.0),
		modulate,
	)


static func mission_card_style(modulate: Color = Color.WHITE) -> StyleBoxTexture:
	return _texture_style(
		MISSION_CARD_FRAME,
		Vector4(62.0, 42.0, 62.0, 42.0),
		Vector4(48.0, 48.0, 48.0, 48.0),
		modulate,
	)


static func operation_tile_style(modulate: Color = Color.WHITE) -> StyleBoxTexture:
	return _texture_style(
		OPERATION_TILE_FRAME,
		Vector4(56.0, 28.0, 56.0, 28.0),
		Vector4(28.0, 16.0, 28.0, 16.0),
		modulate,
	)


static func primary_button_style(
	fill: Color = GOLD,
	edge: Color = BRIGHT_GOLD,
) -> StyleBoxFlat:
	var style := clean_button_style(fill, edge, 4)
	style.content_margin_left = 12.0
	style.content_margin_top = 12.0
	style.content_margin_right = 12.0
	style.content_margin_bottom = 12.0
	return style


static func ornate_primary_button_style(
	modulate: Color = Color.WHITE,
) -> StyleBoxTexture:
	return _texture_style(
		PRIMARY_BUTTON_FRAME,
		Vector4(58.0, 30.0, 58.0, 30.0),
		Vector4(28.0, 18.0, 28.0, 18.0),
		modulate,
	)


static func clean_button_style(
	fill: Color,
	edge: Color,
	corner_radius: int = 4,
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(1)
	style.set_corner_radius_all(corner_radius)
	style.content_margin_left = 24.0
	style.content_margin_top = 10.0
	style.content_margin_right = 24.0
	style.content_margin_bottom = 10.0
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.34)
	style.shadow_size = 4
	style.shadow_offset = Vector2(0.0, 2.0)
	return style


static func resource_chip_style(modulate: Color = Color.WHITE) -> StyleBoxTexture:
	return _texture_style(
		RESOURCE_CHIP_FRAME,
		Vector4(38.0, 24.0, 54.0, 24.0),
		Vector4.ZERO,
		modulate,
	)


static func navbar_style(modulate: Color = Color.WHITE) -> StyleBoxTexture:
	return _texture_style(
		NAVBAR_FRAME,
		Vector4(68.0, 34.0, 68.0, 34.0),
		Vector4.ZERO,
		modulate,
	)


static func company_hud_plate_style(modulate: Color = Color.WHITE) -> StyleBoxTexture:
	return _texture_style(
		COMPANY_HUD_PLATE_FRAME,
		Vector4(72.0, 54.0, 72.0, 54.0),
		Vector4(20.0, 14.0, 20.0, 14.0),
		modulate,
	)


static func company_navigation_rail_style(
	modulate: Color = Color.WHITE,
) -> StyleBoxTexture:
	return _texture_style(
		COMPANY_NAVIGATION_RAIL_FRAME,
		Vector4(56.0, 72.0, 56.0, 72.0),
		Vector4(24.0, 64.0, 24.0, 36.0),
		modulate,
	)


static func golden_focus_tint_style(
	corner_radius: int = 4,
	alpha: float = FOCUS_TINT_ALPHA,
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(GOLD, clampf(alpha, 0.0, 1.0))
	style.border_color = Color.TRANSPARENT
	style.set_border_width_all(0)
	style.set_corner_radius_all(corner_radius)
	style.set_expand_margin_all(0.0)
	return style


## Compatibility alias for existing callers. Focus is no longer transparent:
## keyboard/controller focus is communicated by a restrained gold surface tint.
static func transparent_focus_style(_color: Color = MOON_CYAN) -> StyleBoxFlat:
	return golden_focus_tint_style()


static func _texture_style(
	texture: Texture2D,
	texture_margins: Vector4,
	content_margins: Vector4,
	modulate: Color,
) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture
	style.texture_margin_left = texture_margins.x
	style.texture_margin_top = texture_margins.y
	style.texture_margin_right = texture_margins.z
	style.texture_margin_bottom = texture_margins.w
	style.content_margin_left = content_margins.x
	style.content_margin_top = content_margins.y
	style.content_margin_right = content_margins.z
	style.content_margin_bottom = content_margins.w
	style.modulate_color = modulate
	style.draw_center = true
	return style
