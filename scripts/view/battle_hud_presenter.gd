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
	hud.autowrap_mode = TextServer.AUTOWRAP_OFF
	hud.clip_text = true
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
	var compact := _uses_compact_layout(viewport)
	hud.position = Vector2(12, 8) if compact else Vector2(16, 8)
	hud.size = (
		Vector2(viewport.x * 0.50, 164.0)
		if compact
		else Vector2(viewport.x - 32.0, 100.0)
	)


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
