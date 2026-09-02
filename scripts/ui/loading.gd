extends Control

## Boot bridge. The engine boot splash, loading scene, and start screen share
## the same static art so startup stays visually continuous.

const LOADING_ART := preload("res://assets/loading/command_backdrop.png")
const GameTypographyType := preload("res://scripts/ui/game_typography.gd")
const UiCopyType := preload("res://scripts/ui/components/ui_copy.gd")
const TopAlignedCoverType := preload("res://scripts/ui/components/top_aligned_cover.gd")
const GOLD := Color("d8b978")
const MOON_CYAN := Color("86cbd4")
const IVORY := Color("eee8dc")
const MUTED := Color("aebdc3")
const VOID := Color("071019")

const MINIMUM_DISPLAY_SECONDS := 1.8
const FADE_SECONDS := 0.35
const REFERENCE_VIEWPORT := Vector2(1920.0, 1080.0)
const MAX_LARGE_SCREEN_SCALE := 1.6

var _elapsed := 0.0
var _finishing := false
var _progress: ProgressBar
var _status: Label
var _faction: Label
var _chapter: Label
var _detail: Label
var _percentage: Label
var _veil: ColorRect
var _header: MarginContainer
var _footer: MarginContainer
var _lower_shade: ColorRect
var _wordmark: Label
var _stack: VBoxContainer
var _status_row: HBoxContainer


func _ready() -> void:
	_build_screen()
	get_viewport().size_changed.connect(_apply_responsive_layout)
	I18n.locale_changed.connect(_on_locale_changed)
	_refresh_copy()
	_apply_responsive_layout()
	Game.content = self
	set_process(true)


func _process(delta: float) -> void:
	if _finishing:
		return
	_elapsed += delta
	var ratio := clampf(_elapsed / MINIMUM_DISPLAY_SECONDS, 0.0, 1.0)
	var eased := 1.0 - pow(1.0 - ratio, 3.0)
	_progress.value = eased * 100.0
	_percentage.text = "%02d%%" % int(round(eased * 100.0))
	_status.text = _status_for_ratio(ratio)
	if ratio >= 1.0:
		_finish_loading()


func _build_screen() -> void:
	var art := TopAlignedCoverType.new()
	art.name = "CommandArtwork"
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.texture = LOADING_ART
	add_child(art)

	var atmosphere := ColorRect.new()
	atmosphere.name = "Atmosphere"
	atmosphere.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	atmosphere.color = Color(0.01, 0.025, 0.04, 0.12)
	atmosphere.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(atmosphere)

	var top_rule := ColorRect.new()
	top_rule.name = "TopRule"
	top_rule.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_rule.offset_bottom = 3.0
	top_rule.color = GOLD
	top_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_rule)

	_header = MarginContainer.new()
	_header.name = "Header"
	_header.set_anchors_preset(Control.PRESET_TOP_WIDE)
	add_child(_header)

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override(&"separation", 16)
	_header.add_child(header_row)

	_faction = _label("", GameTypographyType.BADGE, GOLD)
	_faction.name = "FactionLabel"
	_faction.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(_faction)

	_chapter = _label("", GameTypographyType.MICRO_LABEL, IVORY)
	_chapter.name = "ArchiveLabel"
	_chapter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header_row.add_child(_chapter)

	_lower_shade = ColorRect.new()
	_lower_shade.name = "LowerShade"
	_lower_shade.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_lower_shade.color = Color(0.015, 0.035, 0.055, 0.88)
	_lower_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_lower_shade)

	_footer = MarginContainer.new()
	_footer.name = "LoadingPanel"
	_footer.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	add_child(_footer)

	_stack = VBoxContainer.new()
	_footer.add_child(_stack)

	_wordmark = _label("Game template - TD", GameTypographyType.SCREEN_TITLE, IVORY)
	_wordmark.name = "Wordmark"
	_wordmark.add_theme_color_override(&"font_outline_color", Color(0.01, 0.02, 0.03, 0.7))
	_stack.add_child(_wordmark)

	_status_row = HBoxContainer.new()
	_stack.add_child(_status_row)

	_status = _label("", GameTypographyType.STATUS, MUTED)
	_status.name = "StatusLabel"
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_row.add_child(_status)

	_percentage = _label("00%", GameTypographyType.STATUS, MOON_CYAN)
	_percentage.name = "PercentageLabel"
	_percentage.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status_row.add_child(_percentage)

	_progress = ProgressBar.new()
	_progress.name = "Progress"
	_progress.custom_minimum_size = Vector2(0.0, 7.0)
	_progress.show_percentage = false
	_progress.value = 0.0
	_progress.add_theme_stylebox_override(&"background", _bar_style(Color(0.22, 0.29, 0.32, 0.62)))
	_progress.add_theme_stylebox_override(&"fill", _bar_style(MOON_CYAN))
	_stack.add_child(_progress)

	_detail = _label(
		"",
		GameTypographyType.CAPTION,
		Color(0.64, 0.72, 0.74),
	)
	_detail.name = "DetailLabel"
	_detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_stack.add_child(_detail)

	_veil = ColorRect.new()
	_veil.name = "FadeVeil"
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_veil.color = Color(VOID, 0.0)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_veil)


func _label(text_value: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", color)
	return label


func _apply_responsive_layout() -> void:
	if _header == null or _footer == null:
		return
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var large_screen_scale := clampf(
		minf(viewport_size.x / REFERENCE_VIEWPORT.x, viewport_size.y / REFERENCE_VIEWPORT.y),
		1.0,
		MAX_LARGE_SCREEN_SCALE,
	)
	var side_inset := 42.0 * large_screen_scale
	_header.offset_left = side_inset
	_header.offset_top = 28.0 * large_screen_scale
	_header.offset_right = -side_inset
	_header.offset_bottom = 86.0 * large_screen_scale
	_lower_shade.offset_top = -194.0 * large_screen_scale
	_footer.offset_left = side_inset
	_footer.offset_top = -174.0 * large_screen_scale
	_footer.offset_right = -side_inset
	_footer.offset_bottom = -30.0 * large_screen_scale
	_stack.add_theme_constant_override(&"separation", roundi(9.0 * large_screen_scale))
	_status_row.add_theme_constant_override(&"separation", roundi(18.0 * large_screen_scale))
	_set_scaled_font(_faction, GameTypographyType.BADGE, large_screen_scale)
	_set_scaled_font(_chapter, GameTypographyType.MICRO_LABEL, large_screen_scale)
	_set_scaled_font(_wordmark, GameTypographyType.SCREEN_TITLE, large_screen_scale)
	_set_scaled_font(_status, GameTypographyType.STATUS, large_screen_scale)
	_set_scaled_font(_percentage, GameTypographyType.STATUS, large_screen_scale)
	_set_scaled_font(_detail, GameTypographyType.CAPTION, large_screen_scale)
	_wordmark.add_theme_constant_override(&"outline_size", roundi(8.0 * large_screen_scale))
	_progress.custom_minimum_size.y = 7.0 * large_screen_scale


func _set_scaled_font(label: Label, base_size: int, scale: float) -> void:
	if label != null:
		label.add_theme_font_size_override(&"font_size", roundi(float(base_size) * scale))


func _bar_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	return style


func _status_for_ratio(ratio: float) -> String:
	if ratio < 0.36:
		return UiCopyType.text(&"ui.loading.phase.awakening", "AWAKENING RELIQUARY")
	if ratio < 0.72:
		return UiCopyType.text(&"ui.loading.phase.aligning", "ALIGNING LUNAR GEOMETRY")
	if ratio < 0.96:
		return UiCopyType.text(&"ui.loading.phase.restoring", "RESTORING OPERATOR RECORDS")
	return UiCopyType.text(&"ui.loading.phase.complete", "ARCHIVE SYNCHRONIZED")


func _on_locale_changed(_locale_id: StringName) -> void:
	_refresh_copy()


func _refresh_copy() -> void:
	if _status == null:
		return
	_faction.text = UiCopyType.text(&"ui.loading.faction", "LUNARIS RELIQUARY")
	_chapter.text = UiCopyType.text(&"ui.loading.archive", "MOON ARCHIVE // 00")
	_detail.text = UiCopyType.text(&"ui.loading.detail", "CUSTODIANS OF MEMORY, GRAVITY, AND RITUAL GEOMETRY")
	_status.text = _status_for_ratio(clampf(_elapsed / MINIMUM_DISPLAY_SECONDS, 0.0, 1.0))
	accessibility_name = _status.text
	accessibility_description = _detail.text


func _finish_loading() -> void:
	_finishing = true
	_status.text = UiCopyType.text(&"ui.loading.phase.complete", "ARCHIVE SYNCHRONIZED")
	_percentage.text = "100%"
	_progress.value = 100.0
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_veil, "color:a", 1.0, FADE_SECONDS)
	await tween.finished
	if is_inside_tree():
		Game.open_title()
