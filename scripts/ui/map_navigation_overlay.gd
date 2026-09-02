class_name MapNavigationOverlay
extends Control

const AETHERIA_THEME := preload("res://scripts/ui/components/aetheria_theme.gd")
const AETHERIA_PANEL := preload("res://scripts/ui/components/aetheria_panel.gd")
const LUNARIS_STYLE := preload("res://scripts/ui/components/lunaris_ops_style.gd")
const VIEW_PREFERENCES := preload("res://scripts/view/view_preferences.gd")

const HINT_LIVE_SECONDS := 7.0
const HINT_PULSE_PERIOD_SECONDS := 1.6
const PORTRAIT_MARGIN := 16.0
const CONTROL_TOP := 104.0
const OVERLAY_Z := 78

var _preferences_path := VIEW_PREFERENCES.DEFAULT_PATH
var _hint_complete := false
var _hint_expired := false
var _hint_elapsed := 0.0
var _portrait := false
var _can_pan := false
var _hint_allowed := false

var _hint_panel: PanelContainer = null
var _hint_direction: Control = null
var _hint_title: Label = null
var _hint_detail: Label = null


class PanDirectionGlyph:
	extends Control

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(62.0, 48.0)
		queue_redraw()

	func _draw() -> void:
		var color := get_theme_color(&"font_color", &"AuiHeadingLabel")
		_draw_arrow(Vector2(8, 16), Vector2(54, 16), color)
		_draw_arrow(Vector2(31, 4), Vector2(31, 44), color)

	func _draw_arrow(start: Vector2, finish: Vector2, color: Color) -> void:
		draw_line(start, finish, color, 3.0, true)
		var direction := (finish - start).normalized()
		var normal := Vector2(-direction.y, direction.x)
		for point: Vector2 in [start, finish]:
			var inward := direction if point == start else -direction
			draw_polyline(
				PackedVector2Array([point + inward * 8.0 + normal * 6.0, point, point + inward * 8.0 - normal * 6.0]),
				color, 3.0, true,
			)


func setup(preferences_path: String = VIEW_PREFERENCES.DEFAULT_PATH) -> void:
	_preferences_path = preferences_path
	_hint_complete = VIEW_PREFERENCES.has_seen_pan_hint(_preferences_path)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = Vector2.ZERO
	size = get_viewport().get_visible_rect().size
	z_index = OVERLAY_Z
	theme = AETHERIA_THEME.new()
	_build_hint()
	var i18n := get_node_or_null("/root/I18n")
	var locale_callback := Callable(self, "_on_locale_changed")
	if (
		i18n != null
		and i18n.has_signal(&"locale_changed")
		and not i18n.is_connected(&"locale_changed", locale_callback)
	):
		i18n.connect(&"locale_changed", locale_callback)
	_refresh_visibility()
	relayout()


func set_context(
	portrait: bool,
	can_pan: bool,
	hint_allowed: bool,
) -> void:
	_portrait = portrait
	_can_pan = can_pan
	_hint_allowed = hint_allowed
	_refresh_visibility()


func relayout() -> void:
	size = get_viewport().get_visible_rect().size
	if _hint_panel != null:
		var width := minf(size.x - PORTRAIT_MARGIN * 2.0, 340.0)
		var height := 126.0
		_hint_panel.custom_minimum_size = Vector2(width, height)
		_hint_panel.reset_size()
		_hint_panel.position = Vector2(
			(size.x - width) * 0.5,
			maxf(CONTROL_TOP + 64.0, size.y - height - 320.0),
		)
		_hint_panel.size = Vector2(width, height)
		_hint_panel.set_deferred(&"size", Vector2(width, height))


func notify_pan_used() -> void:
	if _hint_complete:
		return
	_hint_complete = true
	_hint_expired = true
	if not VIEW_PREFERENCES.mark_pan_hint_seen(_preferences_path):
		push_warning("MapNavigationOverlay: could not persist pan hint completion")
	_refresh_visibility()


func hint_visible() -> bool:
	return _hint_panel != null and _hint_panel.visible


func _process(delta: float) -> void:
	if _hint_panel == null or not _hint_panel.visible:
		return
	_enforce_hint_rect()
	_hint_elapsed += maxf(delta, 0.0)
	if _hint_elapsed >= HINT_LIVE_SECONDS:
		_hint_expired = true
		_refresh_visibility()
		return
	var phase := fmod(_hint_elapsed, HINT_PULSE_PERIOD_SECONDS) / HINT_PULSE_PERIOD_SECONDS
	var pulse := 0.78 + sin(phase * TAU) * 0.16
	_hint_direction.modulate.a = pulse


func _enforce_hint_rect() -> void:
	var width := minf(size.x - PORTRAIT_MARGIN * 2.0, 340.0)
	var height := 126.0
	_hint_panel.position = Vector2(
		(size.x - width) * 0.5,
		maxf(CONTROL_TOP + 64.0, size.y - height - 320.0),
	)
	_hint_panel.size = Vector2(width, height)


func _build_hint() -> void:
	_hint_panel = AETHERIA_PANEL.new()
	_hint_panel.name = "MapPanHint"
	_hint_panel.apply_role(&"hud")
	LUNARIS_STYLE.apply_panel(_hint_panel, &"selected")
	_hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint_panel)
	var row := HBoxContainer.new()
	row.name = "HintRow"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 14)
	_hint_panel.add_child(row)
	_hint_direction = PanDirectionGlyph.new()
	_hint_direction.name = "PanDirections"
	_hint_direction.accessibility_name = _copy(
		&"ui.map_navigation.hint_title", "DRAG TO PAN",
	)
	row.add_child(_hint_direction)
	var copy_column := VBoxContainer.new()
	copy_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	copy_column.custom_minimum_size.x = 230.0
	copy_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy_column.add_theme_constant_override("separation", 2)
	row.add_child(copy_column)
	_hint_title = Label.new()
	_hint_title.name = "HintTitle"
	_hint_title.text = _copy(&"ui.map_navigation.hint_title", "DRAG TO PAN")
	_hint_title.theme_type_variation = &"AuiDenseHeadingLabel"
	_hint_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	copy_column.add_child(_hint_title)
	_hint_detail = Label.new()
	_hint_detail.name = "HintDetail"
	_hint_detail.text = _copy(
		&"ui.map_navigation.hint_body",
		"Explore the full battlefield on every open axis.",
	)
	_hint_detail.theme_type_variation = &"AuiDenseDetailLabel"
	_hint_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	copy_column.add_child(_hint_detail)

func _on_locale_changed(_locale_id: StringName) -> void:
	if _hint_title != null:
		_hint_title.text = _copy(&"ui.map_navigation.hint_title", "DRAG TO PAN")
	if _hint_detail != null:
		_hint_detail.text = _copy(
			&"ui.map_navigation.hint_body",
			"Explore the full battlefield on every open axis.",
		)
	if _hint_direction != null:
		_hint_direction.accessibility_name = _copy(
			&"ui.map_navigation.hint_title", "DRAG TO PAN",
		)


func _refresh_visibility() -> void:
	if _hint_panel != null:
		_hint_panel.visible = (
			_portrait
			and _can_pan
				and _hint_allowed
				and not _hint_complete
			and not _hint_expired
		)


func _copy(key: StringName, fallback: String) -> String:
	var service := get_node_or_null("/root/I18n")
	if service != null and service.has_method("t"):
		return String(service.call("t", key, fallback))
	return fallback
