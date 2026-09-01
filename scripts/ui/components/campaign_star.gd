class_name CampaignStar
extends Control

var _accent := Color.WHITE
var _lit := false


func _ready() -> void:
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(34.0, 34.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func set_state(accent: Color, lit: bool) -> void:
	_accent = accent
	_lit = lit
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var outer := minf(size.x, size.y) * 0.45
	var inner := outer * 0.43
	var points := PackedVector2Array()
	for index: int in 10:
		var radius := outer if index % 2 == 0 else inner
		var angle := -PI * 0.5 + float(index) * PI / 5.0
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	var color := _accent if _lit else Color(0.46, 0.54, 0.62, 0.24)
	draw_colored_polygon(points, color)
	if _lit:
		var outline := PackedVector2Array(points)
		outline.append(points[0])
		draw_polyline(outline, Color(1.0, 1.0, 1.0, 0.42), 1.0, true)
