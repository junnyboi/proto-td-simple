extends SceneTree

const Catalog := preload("res://data/presentation/operator_visual_catalog.gd")
const Animator := preload("res://scripts/view/operator_animator.gd")
const AnimationDef := preload("res://data/presentation/operator_animation_def.gd")
const Unit := preload("res://sim/unit_state.gd")
const IsoProjectionType := preload("res://scripts/view/iso_projection.gd")
const EXPECTED: Array[StringName] = [&"se", &"sw", &"nw", &"ne"]
var failures: Array[String] = []

func _init() -> void:
	var verified := 0
	for template_id: StringName in Catalog.template_ids():
		var animation := Catalog.get_animation(template_id)
		if animation.schema_version != 3:
			continue
		verified += 1
		check(animation.supported_directions().size() == 4, "%s four directions" % template_id)
		check(animation.validate_contract().is_empty(), "%s contract" % template_id)
		check(animation.normalized_subject_height_px == 106 and animation.display_height_px == 58, "%s recruit scale" % template_id)
		check(is_equal_approx(Animator.ground_offset(animation), IsoProjectionType.TILE_H * 0.5), "%s tile-front contact" % template_id)
		for facing: int in 4:
			var unit := Unit.new()
			unit.facing = facing
			var snapshot := [unit.facing, unit.last_attack_tick, unit.cell]
			check(Animator.direction_for_facing(facing, animation) == EXPECTED[facing], "%s facing %d" % [template_id, facing])
			unit.last_attack_tick = 50
			for tick: int in [51, 60, 65, 80, 83]:
				var selected := Animator.selection(unit, tick, 0.25, animation)
				check(selected[&"direction"] == EXPECTED[facing], "%s attack facing %d" % [template_id, facing])
				check(selected[&"state"] == &"attack", "%s attack state at %d" % [template_id, tick])
				var art := Art.texture(StringName(selected[&"logical_id"]), int(selected[&"frame"]))
				check(art != null, "%s exported frame %s" % [template_id, selected])
			check(Animator.selection(unit, 84, 0.25, animation)[&"state"] == &"idle", "%s recovery" % template_id)
			check(unit.facing == snapshot[0] and unit.cell == snapshot[2] and unit.last_attack_tick == 50, "%s presentation must not mutate simulation" % template_id)
		var invalid := animation.duplicate(true) as AnimationDef
		invalid.idle_by_direction.erase(&"se")
		check(not invalid.validate_contract().is_empty(), "%s rejects missing SE" % template_id)
	check(verified == 6, "all six replacement identities must use schema 3")
	for gender: String in ["male", "female"]:
		var recruit := Catalog.get_animation(StringName("recruit_%s" % gender))
		check(recruit.schema_version == 1 and recruit.source_cell_px == 192, "recruit original schema and cells")
		check(recruit.pivot.is_equal_approx(Vector2(0.5, 0.770833)), "recruit original feet")
		check(recruit.supported_directions() == AnimationDef.DIRECTIONS, "recruit original direction set")
		check(is_equal_approx(Animator.ground_offset(recruit), IsoProjectionType.FEET_OFFSET), "recruit ground offset unchanged")
		check(Animator.direction_for_facing(Unit.Facing.RIGHT, recruit) == &"ne", "recruit RIGHT unchanged")
		check(Animator.direction_for_facing(Unit.Facing.DOWN, recruit) == &"nw", "recruit DOWN unchanged")
	if failures.is_empty():
		print("OPERATOR_FOUR_DIRECTION_TEST_OK")
		quit(0)
	else:
		for failure: String in failures:
			push_error(failure)
		quit(1)

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
