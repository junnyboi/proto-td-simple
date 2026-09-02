extends SceneTree

const BattleTicketRuntimeType := preload("res://sim/battle_ticket_runtime.gd")
const CatalogType := preload("res://data/presentation/operator_visual_catalog.gd")
const PortraitCatalogType := preload("res://data/presentation/operator_portrait_catalog.gd")
const UnitStateType := preload("res://sim/unit_state.gd")

const OPERATOR_BY_CLASS := {
	&"gunner": &"sniper_1",
	&"mage_apprentice": &"caster_1",
	&"swordmaster": &"guard_1",
}
var _failures: Array[String] = []


func _init() -> void:
	for class_id: StringName in PortraitCatalogType.SPECIALIZATION_CLASS_IDS:
		_test_deployed_specialization(class_id)
	if _failures.is_empty():
		print("OPERATOR_SPECIALIZATION_GENDER_DEPLOYMENT_TEST_OK")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)


func _test_deployed_specialization(class_id: StringName) -> void:
	var operator_id := StringName(OPERATOR_BY_CLASS.get(class_id, &""))
	_check(operator_id != &"", "%s has no operator fixture" % class_id)
	if operator_id == &"":
		return
	for portrait_index: int in 8:
		var gender: StringName = &"female" if portrait_index % 2 == 0 else &"male"
		var portrait_id := StringName("portrait_recruit_%02d" % portrait_index)
		# Deliberately choose the opposite result under the old hero-id parity rule.
		var hero_id: StringName = (
			&"0000000000000001" if gender == &"female" else &"0000000000000000"
		)
		var unit := UnitStateType.new()
		BattleTicketRuntimeType.copy_unit(
			_runtime_row(
				class_id,
				operator_id,
				portrait_id,
				hero_id,
			),
			unit,
		)
		var expected := StringName("%s_%s" % [class_id, gender])
		var actual := CatalogType.template_for_unit(
			unit.op_id,
			unit.portrait_asset_id,
			unit.hero_id,
			unit.id,
			unit.class_id,
		)
		_check(
			actual == expected,
			"deployed %s %s identity %s resolved %s instead of %s" % [
				gender, class_id, portrait_id, actual, expected,
			],
		)


func _runtime_row(
	class_id: StringName,
	operator_id: StringName,
	portrait_asset_id: StringName,
	hero_id: StringName,
) -> Dictionary:
	var range_offsets: Array[Vector2i] = []
	return {
		"battle_id": "battle:%s:%s" % [class_id, hero_id],
		"hero_id": String(hero_id),
		"class_id": String(class_id),
		"operator_def_id": String(operator_id),
		"visual_spec": {
			"sprite_id": "",
			"portrait_asset_id": String(portrait_asset_id),
		},
		"combat_spec": {
			"hp": 100,
			"block": 1,
			"dp_cost": 10,
			"atk": 10,
			"defense": 10,
			"resistance_permille": 0,
			"attack_damage_kind": 0,
			"atk_interval_ticks": 30,
			"dp_generation_interval_ticks": 0,
			"splash_dim": 0,
		},
		"range_offsets": range_offsets,
		"target_policy": {},
		"skill_runtime": {},
	}


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
