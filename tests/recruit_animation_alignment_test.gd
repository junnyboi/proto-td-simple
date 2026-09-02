extends SceneTree

const OperatorAnimator := preload("res://scripts/view/operator_animator.gd")
const OperatorVisualCatalog := preload("res://data/presentation/operator_visual_catalog.gd")
const SOURCE_CELL := 192
const EXPECTED_GROUND_Y := 148
const EXPECTED_PIVOT_Y := float(EXPECTED_GROUND_Y) / float(SOURCE_CELL)

var _failures: Array[String] = []


func _init() -> void:
	for identity: StringName in [&"recruit_female", &"recruit_male"]:
		_validate_identity(identity)
	if _failures.is_empty():
		print("RECRUIT_ANIMATION_ALIGNMENT_TEST_OK")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)


func _validate_identity(identity: StringName) -> void:
	var animation = OperatorVisualCatalog.get_animation(identity)
	_check(animation != null, "%s animation definition is missing" % identity)
	if animation == null:
		return
	_check(is_equal_approx(animation.pivot.x, 0.5), "%s horizontal pivot is not centered" % identity)
	_check(absf(animation.pivot.y - EXPECTED_PIVOT_Y) <= 0.00001, "%s ground-line pivot drifted" % identity)
	var body_size: Vector2 = OperatorAnimator.body_size(animation)
	var rect_origin_y: float = IsoProjection.FEET_OFFSET - body_size.y * float(animation.pivot.y)
	var rendered_ground_y: float = rect_origin_y + body_size.y * EXPECTED_PIVOT_Y
	_check(absf(rendered_ground_y - IsoProjection.FEET_OFFSET) <= 0.001, "%s feet do not land on the tile face" % identity)
	var root := "res://assets/sprites/operators/animated/%s/" % identity
	for direction: String in ["ne", "nw"]:
		_validate_strip(identity, root, "idle", direction, 24, 148, 148)
		# Attack poses lunge/crouch by at most six source pixels (3.4 runtime px)
		# while preserving the same authored canvas pivot.
		_validate_strip(identity, root, "attack", direction, 13, 142, 148)


func _validate_strip(
	identity: StringName,
	root: String,
	family: String,
	direction: String,
	frame_count: int,
	minimum_bottom: int,
	maximum_bottom: int,
) -> void:
	var strip := Image.load_from_file(
		ProjectSettings.globalize_path(root + "%s_%s.png" % [family, direction]),
	)
	_check(
		strip != null and not strip.is_empty(),
		"%s/%s/%s strip failed to load" % [identity, family, direction],
	)
	if strip == null or strip.is_empty():
		return
	_check(
		strip.get_size() == Vector2i(SOURCE_CELL * frame_count, SOURCE_CELL),
		"%s/%s/%s strip size drifted" % [identity, family, direction],
	)
	for frame_index: int in frame_count:
		var bottom := _alpha_bottom(strip, frame_index)
		if bottom < minimum_bottom or bottom > maximum_bottom:
			_failures.append(
				"%s/%s/%s frame %d ground line %d left [%d, %d]"
				% [
					identity, family, direction, frame_index, bottom,
					minimum_bottom, maximum_bottom,
				]
			)
			break


func _alpha_bottom(strip: Image, frame_index: int) -> int:
	var start_x := frame_index * SOURCE_CELL
	for y: int in range(SOURCE_CELL - 1, -1, -1):
		for x: int in SOURCE_CELL:
			if strip.get_pixel(start_x + x, y).a > 0.01:
				return y
	return -1


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
