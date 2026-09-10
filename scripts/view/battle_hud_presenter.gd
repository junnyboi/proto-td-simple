extends RefCounted

## Presentation-only Battle HUD helper. BattleView owns model observation and
## lifecycle; this helper owns only Label construction, responsive geometry,
## and text formatting.

const Style := preload("res://scripts/ui/components/lunaris_ops_style.gd")
const GameTypographyType := preload("res://scripts/ui/game_typography.gd")
const UiCopyType := preload("res://scripts/ui/components/ui_copy.gd")


static func create(font_size: int, z_index: int, viewport: Vector2) -> Label:
	var hud := Label.new()
	hud.name = "BattleHud"
	hud.position = Vector2(16, 8)
	hud.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hud.clip_text = false
	hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	Style.apply_label(hud, &"body")
	hud.add_theme_font_size_override(&"font_size", font_size)
	hud.add_theme_font_size_override(&"outline_size", 2)
	hud.add_theme_color_override(&"font_color", Style.IVORY)
	hud.add_theme_color_override(&"font_outline_color", Color(Style.INK_DEEP, 0.94))
	var hud_style := Style.panel_style(&"hud").duplicate() as StyleBox
	hud_style.content_margin_left = 48.0
	hud.add_theme_stylebox_override(&"normal", hud_style)
	hud.z_index = z_index
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	relayout(hud, viewport)
	return hud


static func relayout(hud: Label, viewport: Vector2) -> void:
	if hud == null:
		return
	var font_size := hud.get_theme_font_size(&"font_size")
	var layout_key := [viewport, hud.text, font_size]
	if hud.get_meta(&"hud_layout_key", []) == layout_key:
		return
	hud.set_meta(&"hud_layout_key", layout_key)
	var compact := _uses_compact_layout(viewport)
	var margin := 12.0 if compact else 16.0
	var width := maxf(1.0, viewport.x - margin * 2.0)
	var padding := hud.get_theme_stylebox(&"normal").get_minimum_size()
	var text_size := hud.get_theme_font(&"font").get_multiline_string_size(
		hud.text, HORIZONTAL_ALIGNMENT_CENTER, maxf(1.0, width - padding.x), font_size,
		-1, TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE,
	)
	hud.position = Vector2(margin, 8.0)
	# Keep every counter visible at the selected accessibility size. The command
	# deck follows this measured height instead of overlapping a taller HUD.
	hud.size = Vector2(width, maxf(164.0 if compact else 100.0, ceilf(text_size.y + padding.y)))


static func text_for(snapshot: Dictionary, viewport: Vector2) -> String:
	var result_text: String = [
		UiCopyType.text(&"ui.battle.state_active", "ACTIVE"),
		UiCopyType.text(&"ui.battle.state_clear", "CLEAR"),
		UiCopyType.text(&"ui.battle.state_defeat", "DEFEAT"),
	][int(snapshot["result"])]
	if _uses_compact_layout(viewport):
		return UiCopyType.format_text(&"ui.battle.hud_compact", "LEAKS {leaks} / {leak_threshold}   DP {dp}\nELIMS {eliminations}   {state}", {
			&"leaks": int(snapshot["leaked"]),
			&"leak_threshold": int(snapshot["leak_limit"]) + 1,
			&"dp": int(snapshot["dp"]),
			&"eliminations": int(snapshot["killed"]), &"state": result_text,
		})
	return UiCopyType.format_text(&"ui.battle.hud_wide", "LEAKS  {leaks} / {leak_threshold}    DP  {dp}    ELIMINATIONS  {eliminations}    {state}", {
		&"leaks": int(snapshot["leaked"]),
		&"leak_threshold": int(snapshot["leak_limit"]) + 1,
		&"dp": int(snapshot["dp"]),
		&"eliminations": int(snapshot["killed"]), &"state": result_text,
	})


static func _uses_compact_layout(viewport: Vector2) -> bool:
	return viewport.x < viewport.y or viewport.x < 1100.0
