extends RefCounted

const UnitStateType := preload("res://sim/unit_state.gd")

var _ready_state: Dictionary = {}


## Updates the SP bar and emits one cue only when readiness rises false -> true.
func update(
	body: ColorRect,
	unit: UnitStateType,
	fill_color: Color,
	flash_color: Color,
) -> void:
	if unit.sp_cost <= 0:
		return
	var bg := body.get_node("SpBarBg") as ColorRect
	var fill := bg.get_node("SpBarFill") as ColorRect
	fill.size.x = bg.size.x * clampf(float(unit.sp) / float(unit.sp_cost), 0.0, 1.0)
	var is_ready := unit.is_skill_ready()
	var was_ready := bool(_ready_state.get(unit.id, false))
	if is_ready and not was_ready:
		Sfx.play("ability_ready")
	_ready_state[unit.id] = is_ready
	if is_ready:
		var blink := (Engine.get_process_frames() / 8) % 2 == 0
		fill.color = flash_color if blink else fill_color
	else:
		fill.color = fill_color
