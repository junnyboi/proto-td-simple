extends RefCounted

## Shared battle-world health-bar presentation. Operators and enemies use the
## same compact geometry, while hostile health remains immediately identifiable.

const WIDTH_SCALE := 0.5
const HEIGHT := 2.5
const BODY_GAP := 3.0
const BACKGROUND_COLOR := Color("3a2026")
const OPERATOR_FILL_COLOR := Color("a7f070")
const ENEMY_FILL_COLOR := Color("ef4747")


static func add_to(body: ColorRect, width: float, enemy: bool = false) -> void:
	var bg := ColorRect.new()
	bg.name = "HpBarBg"
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.color = BACKGROUND_COLOR
	body.add_child(bg)
	var fill := ColorRect.new()
	fill.name = "HpBarFill"
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.color = ENEMY_FILL_COLOR if enemy else OPERATOR_FILL_COLOR
	bg.add_child(fill)
	layout(body, width)
	fill.size.x = bg.size.x


static func update(body: ColorRect, width: float, hp: int, hp_max: int) -> void:
	layout(body, width)
	var bg := body.get_node("HpBarBg") as ColorRect
	var fill := body.get_node("HpBarBg/HpBarFill") as ColorRect
	fill.size.x = bg.size.x * clampf(float(hp) / float(maxi(hp_max, 1)), 0.0, 1.0)


static func layout(body: ColorRect, width: float) -> void:
	var bg := body.get_node_or_null("HpBarBg") as ColorRect
	if bg == null:
		return
	var visible := Rect2(body.get_meta(&"operator_visual_bounds", Rect2(Vector2.ZERO, Vector2(width, body.size.y))))
	var bar_width := visible.size.x * WIDTH_SCALE
	bg.size = Vector2(bar_width, HEIGHT)
	bg.position = Vector2((width - bar_width) * 0.5, visible.position.y - HEIGHT - BODY_GAP)
	var fill := bg.get_node_or_null("HpBarFill") as ColorRect
	if fill != null:
		fill.size.y = HEIGHT
