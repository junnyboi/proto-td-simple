class_name OperatorAnimator
extends RefCounted

## View-only projection for admitted directional operator art. It reads UnitState
## and model tick but never mutates either object.

const OperatorAnimationDefType := preload("res://data/presentation/operator_animation_def.gd")
const UnitStateType := preload("res://sim/unit_state.gd")

const MODEL_TICKS_PER_SECOND := 30.0
const NO_ATTACK_AGE := 1_000_000
const IDLE_FRAMES := 24


static func direction_for_facing(facing: int) -> StringName:
	match facing:
		UnitStateType.Facing.RIGHT, UnitStateType.Facing.UP:
			return &"ne"
		UnitStateType.Facing.DOWN, UnitStateType.Facing.LEFT:
			return &"nw"
		_:
			return &"nw"


static func attack_age(model_tick: int, last_attack_tick: int) -> int:
	return model_tick - last_attack_tick if last_attack_tick >= 0 else NO_ATTACK_AGE


static func attack_window_ticks(frame_count: int, fps: float) -> int:
	return 1 + ceili(float(frame_count) * MODEL_TICKS_PER_SECOND / fps)


static func attack_active(age_ticks: int, frame_count: int, fps: float) -> bool:
	return age_ticks >= 1 and age_ticks < attack_window_ticks(frame_count, fps)


static func attack_frame(age_ticks: int, frame_count: int, fps: float) -> int:
	if age_ticks <= 0:
		return 0
	var elapsed_seconds := float(age_ticks - 1) / MODEL_TICKS_PER_SECOND
	return clampi(floori(elapsed_seconds * fps), 0, frame_count - 1)


static func idle_frame(idle_seconds: float) -> int:
	return floori(maxf(idle_seconds, 0.0) * 12.0) % IDLE_FRAMES


static func selection(
	u: UnitStateType,
	model_tick: int,
	idle_seconds: float,
	animation: OperatorAnimationDefType,
) -> Dictionary:
	var direction := direction_for_facing(u.facing)
	var age := attack_age(model_tick, u.last_attack_tick)
	if attack_active(age, animation.attack_frame_count, animation.fps):
		return {
			&"state": &"attack",
			&"direction": direction,
			&"frame": attack_frame(age, animation.attack_frame_count, animation.fps),
			&"logical_id": StringName(animation.attack_by_direction.get(direction, &"")),
		}
	return {
		&"state": &"idle",
		&"direction": direction,
		&"frame": idle_frame(idle_seconds),
		&"logical_id": StringName(animation.idle_by_direction.get(direction, &"")),
	}


static func body_size(animation: OperatorAnimationDefType) -> Vector2:
	var scale := float(animation.display_height_px) / float(animation.normalized_subject_height_px)
	return Vector2.ONE * float(animation.source_cell_px) * scale


static func apply(
	u: UnitStateType,
	model_tick: int,
	idle_seconds: float,
	sprite: TextureRect,
	animation: OperatorAnimationDefType,
) -> bool:
	if sprite == null or animation == null or not animation.validate_contract().is_empty():
		return false
	var selected := selection(u, model_tick, idle_seconds, animation)
	var logical_id := StringName(selected[&"logical_id"])
	var frame := int(selected[&"frame"])
	var texture := Art.texture(logical_id, frame)
	if texture == null:
		return false
	if sprite.texture != texture:
		sprite.texture = texture
	sprite.flip_h = false
	sprite.set_meta(&"operator_animation_state", selected[&"state"])
	sprite.set_meta(&"operator_animation_direction", selected[&"direction"])
	sprite.set_meta(&"operator_animation_frame", frame)
	sprite.set_meta(&"operator_animation_id", logical_id)
	return true
