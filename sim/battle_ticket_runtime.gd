class_name BattleTicketRuntime
extends RefCounted

## Pure BattleTicket -> BattleModel adapter. Campaign battle construction reads
## only normalized ticket data; live OperatorDef, SkillDef, ClassDef, and
## campaign resources are never consulted after attempt issuance.

const SKILL_PAYLOAD_KEYS := ["duration_ticks", "effect", "params", "sp_cost"]
const OP_CLASS_BY_OPERATOR := {
	"guard_1": OperatorDef.OpClass.GUARD,
	"sniper_1": OperatorDef.OpClass.SNIPER,
	"caster_1": OperatorDef.OpClass.CASTER,
	"recruit": OperatorDef.OpClass.RECRUIT,
}
const BattleTicketScript := preload("res://sim/battle_ticket.gd")
const CanonicalJsonScript := preload("res://sim/canonical_json.gd")
const TargetPolicyDefScript := preload("res://data/target_policy_def.gd")


static func configure(
	model: BattleModel,
	battle_input: Variant,
	stage: StageDef,
	seed_value: int,
	trusted_ticket_hashes: Array,
) -> bool:
	if typeof(battle_input) == TYPE_DICTIONARY:
		var prepared := prepare(battle_input, stage)
		if not prepared["accepted"]:
			return false
		if not trusted_ticket_hashes.has(prepared["ticket"]["ticket_hash"]):
			return false
		model._ticket = prepared["ticket"]
		model.run_seed = int(model._ticket["seed"])
		for row: Dictionary in prepared["rows"]:
			var battle_id := StringName(row["battle_id"])
			model.battle_squad.append(battle_id)
			model._ticket_rows[battle_id] = row.duplicate(true)
			model._battle_records.append(_fresh_record(row))
		return true
	if typeof(battle_input) != TYPE_ARRAY:
		return false
	for raw_id: Variant in battle_input:
		if typeof(raw_id) not in [TYPE_STRING, TYPE_STRING_NAME]:
			return false
		model.squad.append(StringName(raw_id))
	model.run_seed = seed_value
	return true


static func prepare(value: Variant, stage: StageDef) -> Dictionary:
	if stage == null:
		return _reject(&"invalid_ticket_stage")
	var normalized := BattleTicketScript.normalize(value)
	if not normalized["accepted"]:
		return normalized
	var ticket: Dictionary = normalized["value"]
	for index: int in ticket["squad"].size():
		var row: Dictionary = ticket["squad"][index]
		var expected_battle_id := (
			CanonicalJsonScript
			. sha256_hex(
				[
					ticket["campaign_uid"],
					ticket["attempt_id"],
					index,
					row["hero_id"],
				]
			)
			. substr(0, 16)
		)
		if row["battle_id"] != expected_battle_id:
			return _reject(&"battle_id_mismatch")
	if ticket["stage_id"] != String(stage.id):
		return _reject(&"ticket_stage_mismatch")
	if (ticket["squad"] as Array).size() > stage.squad_size:
		return _reject(&"invalid_ticket_capacity")
	var rows: Array[Dictionary] = []
	for frozen: Dictionary in ticket["squad"]:
		var runtime := _runtime_row(frozen)
		if not runtime["accepted"]:
			return runtime
		rows.append(runtime["value"])
	return {
		"accepted": true,
		"error_code": &"",
		"ticket": ticket.duplicate(true),
		"rows": rows,
	}


static func copy_unit(row: Dictionary, unit: UnitState) -> void:
	var combat: Dictionary = row["combat_spec"]
	unit.battle_id = StringName(row["battle_id"])
	unit.hero_id = StringName(row["hero_id"])
	unit.class_id = StringName(row["class_id"])
	unit.op_id = StringName(row["operator_def_id"])
	unit.sprite_id = StringName(row["visual_spec"]["sprite_id"])
	unit.portrait_asset_id = StringName(row["visual_spec"]["portrait_asset_id"])
	unit.op_class = int(OP_CLASS_BY_OPERATOR[row["operator_def_id"]]) as OperatorDef.OpClass
	unit.hp = int(combat["hp"])
	unit.hp_max = int(combat["hp"])
	unit.block = int(combat["block"])
	unit.dp_cost = int(combat["dp_cost"])
	unit.atk = int(combat["atk"])
	unit.defense = int(combat["defense"])
	unit.resistance_permille = int(combat["resistance_permille"])
	unit.attack_damage_kind = int(combat["attack_damage_kind"])
	unit.atk_interval_ticks = int(combat["atk_interval_ticks"])
	unit.dp_generation_interval_ticks = int(combat["dp_generation_interval_ticks"])
	unit.splash_dim_base = int(combat["splash_dim"])
	unit.range_offsets = row["range_offsets"].duplicate()
	unit.target_policy = row["target_policy"].duplicate(true)
	var skill: Dictionary = row["skill_runtime"]
	if not skill.is_empty():
		unit.skill_id = StringName(skill["skill_id"])
		unit.sp_cost = int(skill["sp_cost"])
		unit.skill_effect = int(skill["effect"])
		unit.skill_params = skill["params"].duplicate(true)
		unit.skill_duration_ticks = int(skill["duration_ticks"])


static func copy_legacy_unit(definition: OperatorDef, unit: UnitState) -> void:
	unit.op_id = definition.id
	unit.hp = definition.hp
	unit.hp_max = definition.hp
	unit.block = definition.block
	unit.dp_cost = definition.dp_cost
	unit.atk = definition.atk
	unit.defense = definition.defense
	unit.resistance_permille = definition.resistance_permille
	unit.attack_damage_kind = definition.attack_damage_kind
	unit.atk_interval_ticks = definition.atk_interval_ticks
	unit.dp_generation_interval_ticks = definition.dp_generation_interval_ticks
	unit.op_class = definition.op_class
	unit.splash_dim_base = definition.splash_dim
	unit.range_offsets = definition.range_offsets.duplicate()
	unit.target_policy = (
		Targeting
		. compile(
			definition.target_policy,
			TargetPolicyDefScript.OwnerKind.OPERATOR,
		)
	)
	if definition.skill != null:
		unit.skill_id = definition.skill.id
		unit.sp_cost = definition.skill.sp_cost
		unit.skill_effect = definition.skill.effect
		unit.skill_params = definition.skill.params.duplicate()
		unit.skill_duration_ticks = definition.skill.duration_ticks


static func is_deployable(model: BattleModel, battle_id: StringName) -> bool:
	if not model._ticket_rows.has(battle_id):
		return false
	if model.is_redeploy_cooling_down(battle_id):
		return false
	var record := record_for(model._battle_records, battle_id)
	if record.is_empty() or bool(record["fell"]):
		return false
	for unit: UnitState in model.units:
		if unit.alive and unit.battle_id == battle_id:
			return false
	return model.dp >= int(model._ticket_rows[battle_id]["combat_spec"]["dp_cost"])


static func cell_in_domain(row: Dictionary, stage: StageDef, cell: Vector2i) -> bool:
	var placement := int(row["combat_spec"]["placement"])
	if placement == OperatorDef.Placement.GROUND:
		return stage.tile_at(cell) == StageDef.Tile.GROUND
	if placement == OperatorDef.Placement.ELEVATED:
		return stage.is_elevated_platform(cell)
	return false


static func record_for(records: Array[Dictionary], battle_id: StringName) -> Dictionary:
	for record: Dictionary in records:
		if StringName(record["battle_id"]) == battle_id:
			return record
	return {}


static func _fresh_record(row: Dictionary) -> Dictionary:
	return {
		"slot_index": int(row["slot_index"]),
		"battle_id": String(row["battle_id"]),
		"hero_id": String(row["hero_id"]),
		"class_id": String(row["class_id"]),
		"operator_def_id": String(row["operator_def_id"]),
		"deployments": 0,
		"retreats": 0,
		"fell": false,
		"first_fall_tick": null,
	}


static func _runtime_row(frozen: Dictionary) -> Dictionary:
	if not OP_CLASS_BY_OPERATOR.has(frozen["operator_def_id"]):
		return _reject(&"invalid_ticket_operator_class")
	var target_policy := _target_policy(frozen["target_policy_spec"])
	if not target_policy["accepted"]:
		return target_policy
	var skill := _skill_runtime(frozen["skill_spec"])
	if not skill["accepted"]:
		return skill
	var range_offsets: Array[Vector2i] = []
	for cell: Dictionary in frozen["combat_spec"]["range_cells"]:
		range_offsets.append(Vector2i(int(cell["x"]), int(cell["y"])))
	return _accept(
		{
			"slot_index": int(frozen["slot_index"]),
			"battle_id": String(frozen["battle_id"]),
			"hero_id": String(frozen["hero_id"]),
			"class_id": String(frozen["class_id"]),
			"operator_def_id": String(frozen["operator_def_id"]),
			"operator_content_sha256": String(frozen["operator_content_sha256"]),
			"combat_spec": frozen["combat_spec"].duplicate(true),
			"target_policy_spec": frozen["target_policy_spec"].duplicate(true),
			"skill_spec": frozen["skill_spec"].duplicate(true),
			"visual_spec": frozen["visual_spec"].duplicate(true),
			"range_offsets": range_offsets,
			"target_policy": target_policy["value"],
			"skill_runtime": skill["value"],
		}
	)


static func _target_policy(value: Dictionary) -> Dictionary:
	if int(value["owner_kind"]) != TargetPolicyDefScript.OwnerKind.OPERATOR:
		return _reject(&"invalid_ticket_target_policy")
	return _accept(
		{
			"valid": true,
			"invalid_reason": "",
			"policy_id": String(value["policy_id"]),
			"owner_kind": int(value["owner_kind"]),
			"candidate_domain": int(value["candidate_domain"]),
			"aerial_rule": int(value["aerial_rule"]),
			"primary_rank": int(value["primary_rank"]),
		}
	)


static func _skill_runtime(value: Dictionary) -> Dictionary:
	var skill_id := String(value["skill_id"])
	var payload: Dictionary = value["payload"]
	if skill_id.is_empty():
		return _accept({}) if payload.is_empty() else _reject(&"invalid_ticket_skill")
	if payload.keys() != SKILL_PAYLOAD_KEYS:
		return _reject(&"invalid_ticket_skill")
	for key: String in ["duration_ticks", "effect", "sp_cost"]:
		if typeof(payload[key]) != TYPE_INT or int(payload[key]) < 0:
			return _reject(&"invalid_ticket_skill")
	if int(payload["effect"]) >= SkillDef.Effect.size() or int(payload["sp_cost"]) == 0:
		return _reject(&"invalid_ticket_skill")
	if typeof(payload["params"]) != TYPE_DICTIONARY:
		return _reject(&"invalid_ticket_skill")
	var parameters := {}
	for raw_key: Variant in payload["params"]:
		var key := String(raw_key)
		var parameter: Variant = payload["params"][raw_key]
		if key.ends_with("_milli"):
			if typeof(parameter) != TYPE_INT:
				return _reject(&"invalid_ticket_skill")
			parameters[key.trim_suffix("_milli")] = float(parameter) / 1000.0
		else:
			parameters[key] = parameter
	return _accept(
		{
			"skill_id": skill_id,
			"duration_ticks": int(payload["duration_ticks"]),
			"effect": int(payload["effect"]),
			"sp_cost": int(payload["sp_cost"]),
			"params": parameters,
		}
	)


static func _accept(value: Variant) -> Dictionary:
	return {"accepted": true, "error_code": &"", "value": value}


static func _reject(code: StringName) -> Dictionary:
	return {"accepted": false, "error_code": code}
