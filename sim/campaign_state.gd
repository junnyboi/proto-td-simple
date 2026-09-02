class_name CampaignState
extends "res://sim/campaign_training_projection.gd"

## Canonical model-only P16 aggregate (D16-08). The private value is always a
## whole-document-normalized CampaignSave data object. P16.2 commands construct
## validated prospective states; collections are defensive views and durability
## enters only through deterministic CampaignMutation command seams.

const CampaignPromotionScript := preload("res://sim/campaign_promotion.gd")
const CombatContentBindingScript := preload("res://sim/combat_content_binding.gd")
const P16_STARTERS: Array[StringName] = [
	&"caster_1", &"guard_1", &"sniper_1",
]
const P16_OFFER := {
	"offer_id": "p16_caster_contract",
	"operator_def_id": "caster_1",
	"cost": 80,
}



static func create(
	seed_value: int,
	generation: int,
	campaign_def: CampaignDef,
	catalogs: Dictionary,
	stage_defs: Array,
) -> Dictionary:
	var environment := _build_environment(campaign_def, catalogs, stage_defs)
	if not environment["accepted"]:
		return environment
	var fresh := _fresh_data(
		seed_value, generation, environment["definition"], environment["starting"],
		environment["combat_rules_sha256"],
	)
	if not fresh["accepted"]:
		return fresh
	return _public_restore(_restore_normalized(fresh["value"], environment))


static func restore(
	data: Dictionary,
	campaign_def: CampaignDef,
	catalogs: Dictionary,
	stage_defs: Array,
) -> Dictionary:
	var environment := _build_environment(campaign_def, catalogs, stage_defs)
	if not environment["accepted"]:
		return environment
	var normalized := CampaignCodec.normalize_data(data, environment["context"])
	if not normalized["accepted"]:
		return normalized
	return _public_restore(_restore_normalized(normalized["value"], environment))


func campaign_uid() -> String:
	return String(_data["campaign_uid"])


func campaign_seed() -> int:
	return int(_data["campaign_seed"])


func campaign_generation() -> int:
	return int(_data["campaign_generation"])


func save_revision() -> int:
	return int(_data["save_revision"])


func next_recruitment_index() -> int:
	return int(_data["next_recruitment_index"])


func next_attempt_id() -> int:
	return int(_data["next_attempt_id"])


func next_resolution_index() -> int:
	return int(_data["next_resolution_index"])


func marks() -> int:
	return int(_data["marks"])


func roster() -> RosterState:
	return RosterState.from_normalized_rows(_data["heroes"])


func offers() -> Array[Dictionary]:
	var values: Array[Dictionary] = []
	for row: Dictionary in _data["offers"]:
		values.append(row.duplicate(true))
	return values


func offer(offer_id: String) -> Dictionary:
	for row: Dictionary in _data["offers"]:
		if row["offer_id"] == offer_id:
			return row.duplicate(true)
	return {}


func data_copy() -> Dictionary:
	return _data.duplicate(true)


func encode_data() -> Dictionary:
	return CampaignCodec.encode_data(_data, _context)


func strategic_hash() -> Dictionary:
	return cached_strategic_hash()


func promotion_options(hero_id: Variant) -> Dictionary:
	if typeof(hero_id) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return _reject(&"invalid_argument_type")
	var hero_key := String(hero_id)
	for hero: Dictionary in _data["heroes"]:
		if hero["hero_id"] == hero_key:
			return CampaignProgressionType.promotion_options(
				hero, _context["promotion_rules"],
			)
	return _reject(&"unknown_hero")


func promote_hero(command: Variant) -> Dictionary:
	var result: Dictionary = CampaignPromotionScript.execute(_data, _context, command)
	if result["accepted"]:
		_encoded_save_cache = {}
		_strategic_hash_cache = {}
		seed_validated_caches()
	return result


func campaign_stage_ids() -> Array[StringName]:
	var values: Array[StringName] = []
	for stage_id: String in _context["stage_order"]:
		values.append(StringName(stage_id))
	return values


func is_stage_unlocked(stage_id: StringName) -> bool:
	var position: int = _context["stage_order"].find(String(stage_id))
	if position < 0:
		return true
	if position == 0:
		return true
	return _stage_stars_by_id().has(StringName(_context["stage_order"][position - 1]))


func compatibility_projection() -> Dictionary:
	return {
		"unlocked_operators": roster().owned_operator_def_ids(),
		"unlocked_traps": _string_names(_data["unlocked_traps"]),
		"stage_stars": _stage_stars_by_id(),
	}


func preview_first_clear_rewards(stage_id: StringName) -> Dictionary:
	var stage_key := String(stage_id)
	if not _context["stage_rewards"].has(stage_key):
		return _reject(&"unknown_campaign_stage")
	if not is_stage_unlocked(stage_id):
		return _reject(&"stage_locked")
	if _stage_stars_by_id().has(stage_id):
		return _preview_accept(false, [], [], next_recruitment_index())
	var working_roster := roster()
	var next_index := next_recruitment_index()
	var reward_rows: Array[Dictionary] = []
	var hero_rows: Array[Dictionary] = []
	for authored: Dictionary in _context["stage_rewards"][stage_key]:
		var hero_id: Variant = null
		if authored["kind"] == "operator":
			if working_roster.rows_copy().size() >= CampaignCodec.MAX_ROSTER:
				return _reject(&"roster_limit")
			var allocated := working_roster.plan_allocation(
				campaign_seed(), campaign_generation(), next_index,
				StringName(authored["id"]), &"reward", stage_key,
				next_resolution_index(),
			)
			if not allocated["accepted"]:
				return allocated
			var hero_row: Dictionary = allocated["row"]
			hero_rows.append(hero_row.duplicate(true))
			hero_id = hero_row["hero_id"]
			next_index = int(allocated["next_recruitment_index"])
			var combined := working_roster.rows_copy()
			combined.append(hero_row)
			working_roster = RosterState.from_normalized_rows(combined)
		reward_rows.append({
			"kind": authored["kind"],
			"id": authored["id"],
			"hero_instance_id": hero_id,
		})
	return _preview_accept(true, reward_rows, hero_rows, next_index)


static func _build_environment(
	campaign_def: CampaignDef,
	catalogs: Dictionary,
	stage_defs: Array,
) -> Dictionary:
	var definition := _normalize_campaign_definition(campaign_def)
	if not definition["accepted"]:
		return definition
	var normalized_catalogs := _normalize_catalogs(catalogs)
	if not normalized_catalogs["accepted"]:
		return normalized_catalogs
	if not _definition_references_exist(
		definition["value"], normalized_catalogs["value"],
	):
		return _reject(&"invalid_campaign_definition")
	var normalized_stages := _normalize_stages(
		stage_defs, normalized_catalogs["value"],
	)
	if not normalized_stages["accepted"]:
		return normalized_stages
	var stages: Array = normalized_stages["value"]
	var canonical_catalogs: Dictionary = normalized_catalogs["value"]
	var combat_binding := CombatContentBindingScript.build(canonical_catalogs, stages)
	if not combat_binding["accepted"]:
		return combat_binding
	var promotion_rules := {"accepted": true, "error_code": &"", "value": {}}
	var environment_hash := CanonicalJson.sha256_hex(
		_environment_manifest(
			canonical_catalogs, stages, promotion_rules["value"],
			combat_binding["manifest"],
		),
	)
	if environment_hash != definition["value"]["environment_sha256"]:
		return _reject(&"campaign_environment_mismatch")
	var starting := _derive_starting_unlocks(canonical_catalogs, stages)
	if starting["operators"] != definition["value"]["starter_operator_ids"]:
		return _reject(&"starter_contract_mismatch")
	var context := CampaignCodec.build_context(
		canonical_catalogs["operators"], canonical_catalogs["traps"],
		stages, definition["value"]["paid_offers"], starting["traps"],
		promotion_rules["value"], combat_binding["sha256"],
	)
	return {
		"accepted": true,
		"error_code": &"",
		"context": context,
		"command_context": _build_command_context(stages),
		"starting": starting,
		"combat_rules_sha256": combat_binding["sha256"],
		"definition": definition["value"],
		"campaign_def_resource": campaign_def,
		"catalogs": canonical_catalogs,
		"stage_defs": stages,
	}


static func _fresh_data(
	seed_value: int,
	generation: int,
	campaign_def: Dictionary,
	starting: Dictionary,
	combat_rules_sha256: String,
) -> Dictionary:
	if generation < 1:
		return _reject(&"invalid_campaign_identity")
	var rows: Array[Dictionary] = []
	var working := RosterState.from_normalized_rows(rows)
	for operator_id: StringName in campaign_def["starter_operator_ids"]:
		var allocated := working.plan_allocation(
			seed_value, generation, rows.size(), operator_id,
			&"starter", "", 0, int(campaign_def["name_version"]),
		)
		if not allocated["accepted"]:
			return allocated
		rows.append((allocated["row"] as Dictionary).duplicate(true))
		working = RosterState.from_normalized_rows(rows)
	var offers: Array[Dictionary] = []
	for authored: Dictionary in campaign_def["paid_offers"]:
		offers.append({
			"offer_id": String(authored["offer_id"]),
			"operator_def_id": String(authored["operator_def_id"]),
			"cost": int(authored["cost"]),
			"consumed": false,
		})
	offers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["offer_id"]) < String(b["offer_id"]))
	return {
		"accepted": true,
		"error_code": &"",
		"value": {
			"campaign_uid": HeroIdentity.campaign_uid(seed_value, generation),
			"campaign_seed": seed_value,
			"campaign_generation": generation,
			"save_revision": 1,
			"next_recruitment_index": rows.size(),
			"next_attempt_id": 1,
			"next_resolution_index": 1,
			"marks": int(campaign_def["initial_marks"]),
			"combat_rules_sha256": combat_rules_sha256,
			"stage_stars": [],
			"unlocked_traps": _strings(starting["traps"]),
			"offers": offers,
			"heroes": rows,
			"promotion_receipts": [],
			"promotion_proofs": [],
			"resolution_anchor": null,
			"last_resolution": null,
		},
	}


static func _restore_normalized(data: Dictionary, environment: Dictionary) -> Dictionary:
	var context: Dictionary = environment["context"]
	var normalized := CampaignCodec.normalize_data(data, context)
	if not normalized["accepted"]:
		return normalized
	var state := CampaignState.new()
	state._data = normalized["value"]
	state._context = context
	state._command_context = environment["command_context"]
	var definition: CampaignDef = environment["campaign_def_resource"]
	var catalogs: Dictionary = (environment["catalogs"] as Dictionary).duplicate(true)
	var stage_defs: Array = (environment["stage_defs"] as Array).duplicate()
	state._campaign_def = definition
	state._catalogs = catalogs
	state._stage_defs = stage_defs
	state._restore_callable = func(value: Dictionary) -> Dictionary:
		return CampaignState._restore_normalized(value, environment)
	state._certified_restore_callable = func(value: Dictionary) -> Dictionary:
		return CampaignState._restore_certified(value, environment)
	var authority := _new_pending_authority()
	state._pending_control = authority["control"]
	state.seed_validated_caches()
	return {
		"accepted": true,
		"error_code": &"",
		"value": state,
		"pending_issue": authority["issue"],
	}


static func _restore_certified(data: Dictionary, environment: Dictionary) -> Dictionary:
	var state := CampaignState.new()
	state._data = data
	state._context = environment["context"]
	state._command_context = environment["command_context"]
	state._campaign_def = environment["campaign_def_resource"]
	state._catalogs = environment["catalogs"]
	state._stage_defs = environment["stage_defs"]
	state._restore_callable = func(value: Dictionary) -> Dictionary:
		return CampaignState._restore_normalized(value, environment)
	state._certified_restore_callable = func(value: Dictionary) -> Dictionary:
		return CampaignState._restore_certified(value, environment)
	var authority := _new_pending_authority()
	state._pending_control = authority["control"]
	state.seed_validated_caches()
	return {
		"accepted": true, "error_code": &"", "value": state,
		"pending_issue": authority["issue"],
	}


static func _new_pending_authority() -> Dictionary:
	var status_cell := RefCounted.new()
	status_cell.set_meta(&"status", CampaignPendingAttempt.ABORTED)
	var record := {
		"pending": null,
		"status": CampaignPendingAttempt.ABORTED,
		"attempt_id": 0,
		"stage_id": &"",
		"manifest_hash": "",
		"committed_hash": "",
	}
	var control := func(action: StringName, pending: Variant) -> Dictionary:
		var same: bool = pending != null and pending == record["pending"]
		var status: StringName = record["status"]
		var active: bool = status in [CampaignPendingAttempt.ACTIVE, CampaignPendingAttempt.RESERVED]
		match action:
			&"has": return {"accepted": record["pending"] != null and active}
			&"current": return {"accepted": active, "pending": record["pending"]}
			&"validate":
				if not same or not active:
					return {"accepted": false, "status": status}
				var candidate: CampaignPendingAttempt = pending
				var exact: bool = (
					candidate.attempt_id() == record["attempt_id"]
					and candidate.stage_id() == record["stage_id"]
					and candidate.manifest_hash() == record["manifest_hash"]
					and candidate.committed_strategic_hash() == record["committed_hash"]
				)
				return {"accepted": exact, "status": status}
			&"reserve":
				if not same or status != CampaignPendingAttempt.ACTIVE:
					return {"accepted": false, "status": status}
				record["status"] = CampaignPendingAttempt.RESERVED
				status_cell.set_meta(&"status", record["status"])
				return {"accepted": true, "status": record["status"]}
			&"release":
				if not same or status != CampaignPendingAttempt.RESERVED:
					return {"accepted": false, "status": status}
				record["status"] = CampaignPendingAttempt.ACTIVE
				status_cell.set_meta(&"status", record["status"])
				return {"accepted": true, "status": record["status"]}
			&"resolve":
				if not same or status != CampaignPendingAttempt.RESERVED:
					return {"accepted": false, "status": status}
				record["status"] = CampaignPendingAttempt.RESOLVED
				status_cell.set_meta(&"status", record["status"])
				return {"accepted": true, "status": record["status"]}
			&"abort":
				if not same or not active:
					return {"accepted": false, "status": status}
				record["status"] = CampaignPendingAttempt.ABORTED
				status_cell.set_meta(&"status", record["status"])
				return {"accepted": true, "status": record["status"]}
		return {"accepted": false, "status": status}
	var issue := func(ticket: CampaignBattleTicket, committed_hash: String) -> Dictionary:
		if record["pending"] != null or ticket == null or committed_hash.is_empty():
			return {"accepted": false, "pending": null}
		var pending := CampaignPendingAttempt.new()
		pending._ticket = ticket
		pending._committed_hash = committed_hash
		pending._status_cell = status_cell
		record["pending"] = pending
		record["status"] = CampaignPendingAttempt.ACTIVE
		status_cell.set_meta(&"status", record["status"])
		record["attempt_id"] = ticket.attempt_id()
		record["stage_id"] = ticket.stage_id()
		record["manifest_hash"] = ticket.manifest_hash()
		record["committed_hash"] = committed_hash
		return {"accepted": true, "pending": pending}
	return {"control": control, "issue": issue}


static func _public_restore(result: Dictionary) -> Dictionary:
	if not result["accepted"]:
		return result
	return {
		"accepted": true,
		"error_code": &"",
		"value": result["value"],
	}


static func _build_command_context(stages: Array) -> Dictionary:
	var squad_sizes := {}
	var recovery_rosters := {}
	for stage: StageDef in stages:
		var stage_id := String(stage.id)
		squad_sizes[stage_id] = stage.squad_size
		recovery_rosters[stage_id] = _strings(stage.recovery_roster)
	return {
		"squad_sizes": squad_sizes,
		"recovery_rosters": recovery_rosters,
	}


static func _normalize_campaign_definition(campaign_def: CampaignDef) -> Dictionary:
	if campaign_def == null:
		return _reject(&"invalid_campaign_definition")
	if (
		campaign_def.schema_version != CampaignCodec.SAVE_VERSION
		or campaign_def.name_version != HeroNames.VERSION
		or campaign_def.initial_marks != CampaignInvariants.INITIAL_MARKS
		or campaign_def.starter_operator_ids != P16_STARTERS
		or not _is_hex_sha256(campaign_def.environment_sha256)
		or campaign_def.environment_sha256 != CampaignDef.P16_ENVIRONMENT_SHA256
	):
		return _reject(&"invalid_campaign_definition")
	var offers := _normalize_campaign_offers(campaign_def.paid_offers)
	if not offers["accepted"]:
		return offers
	if (offers["value"] as Array).size() != 1 or offers["value"][0] != P16_OFFER:
		return _reject(&"invalid_campaign_definition")
	return {
		"accepted": true,
		"error_code": &"",
		"value": {
			"schema_version": campaign_def.schema_version,
			"name_version": campaign_def.name_version,
			"initial_marks": campaign_def.initial_marks,
			"starter_operator_ids": P16_STARTERS.duplicate(),
			"paid_offers": offers["value"],
			"environment_sha256": campaign_def.environment_sha256,
		},
	}


static func _normalize_catalogs(catalogs: Dictionary) -> Dictionary:
	if catalogs.keys().size() != 2:
		return _reject(&"invalid_catalog")
	var normalized := {}
	var all_ids := {}
	for key: String in ["operators", "traps"]:
		if not catalogs.has(key) or typeof(catalogs[key]) != TYPE_ARRAY:
			return _reject(&"invalid_catalog")
		var ids: Array[StringName] = []
		for raw_id: Variant in catalogs[key]:
			if typeof(raw_id) not in [TYPE_STRING, TYPE_STRING_NAME]:
				return _reject(&"invalid_catalog")
			var item_id := String(raw_id)
			if key == "operators" and item_id == "recruit":
				continue
			if not _is_ascii_id(item_id) or all_ids.has(item_id):
				return _reject(&"invalid_catalog")
			all_ids[item_id] = true
			ids.append(StringName(item_id))
		if ids.is_empty():
			return _reject(&"invalid_catalog")
		ids.sort_custom(func(a: StringName, b: StringName) -> bool:
			return String(a) < String(b))
		normalized[key] = ids
	return {"accepted": true, "error_code": &"", "value": normalized}


static func _definition_references_exist(
	definition: Dictionary,
	catalogs: Dictionary,
) -> bool:
	var operators: Array = catalogs["operators"]
	for operator_id: StringName in definition["starter_operator_ids"]:
		if not operators.has(operator_id):
			return false
	for offer: Dictionary in definition["paid_offers"]:
		if not operators.has(StringName(offer["operator_def_id"])):
			return false
	return true


static func _normalize_stages(stage_defs: Array, catalogs: Dictionary) -> Dictionary:
	var stages: Array = []
	var stage_ids := {}
	var stage_indices := {}
	var rewarded := {}
	for value: Variant in stage_defs:
		if not value is StageDef:
			return _reject(&"invalid_campaign_stage")
		var stage := value as StageDef
		if stage.campaign_index < 1:
			continue
		var stage_id := String(stage.id)
		if (
			not _is_ascii_id(stage_id) or stage_ids.has(stage_id)
			or stage_indices.has(stage.campaign_index)
		):
			return _reject(&"invalid_campaign_stage")
		stage_ids[stage_id] = true
		stage_indices[stage.campaign_index] = true
		var rewards_valid := _validate_stage_rewards(stage.rewards, catalogs, rewarded)
		if not rewards_valid["accepted"]:
			return rewards_valid
		if not _valid_recovery_shape(
			stage.recovery_roster, catalogs["operators"], stage.squad_size,
		):
			return _reject(&"invalid_campaign_stage")
		stages.append(stage)
	stages.sort_custom(func(a: StageDef, b: StageDef) -> bool:
		return a.campaign_index < b.campaign_index)
	if stages.is_empty():
		return _reject(&"invalid_campaign_stage")
	for position: int in stages.size():
		if (stages[position] as StageDef).campaign_index != position + 1:
			return _reject(&"invalid_campaign_stage")
	if not _recovery_rosters_are_available(stages, catalogs):
		return _reject(&"invalid_campaign_stage")
	return {"accepted": true, "error_code": &"", "value": stages}


static func _derive_starting_unlocks(catalogs: Dictionary, stages: Array) -> Dictionary:
	var rewarded := {}
	for stage: StageDef in stages:
		for reward: Dictionary in stage.rewards:
			rewarded[String(reward["id"])] = true
	var result := {"operators": [], "traps": []}
	for kind: String in result:
		var starting: Array[StringName] = []
		for item_id: Variant in catalogs[kind]:
			if not rewarded.has(String(item_id)) and not (
				kind == "operators" and String(item_id) == "recruit"
			):
				starting.append(StringName(item_id))
		starting.sort_custom(func(a: StringName, b: StringName) -> bool:
			return String(a) < String(b))
		result[kind] = starting
	return result


static func _normalize_campaign_offers(values: Array[Dictionary]) -> Dictionary:
	var rows: Array[Dictionary] = []
	var seen := {}
	for value: Dictionary in values:
		if value.keys().size() != 3:
			return _reject(&"invalid_campaign_definition")
		for key: String in ["offer_id", "operator_def_id", "cost"]:
			if not value.has(key):
				return _reject(&"invalid_campaign_definition")
		if (
			typeof(value["offer_id"]) != TYPE_STRING
			or typeof(value["operator_def_id"]) != TYPE_STRING
			or typeof(value["cost"]) != TYPE_INT
		):
			return _reject(&"invalid_campaign_definition")
		var offer_id: String = value["offer_id"]
		var operator_id: String = value["operator_def_id"]
		if (
			not _is_ascii_id(offer_id) or not _is_ascii_id(operator_id)
			or seen.has(offer_id) or int(value["cost"]) < 0
		):
			return _reject(&"invalid_campaign_definition")
		seen[offer_id] = true
		rows.append({
			"offer_id": offer_id,
			"operator_def_id": operator_id,
			"cost": int(value["cost"]),
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["offer_id"]) < String(b["offer_id"]))
	return {"accepted": true, "error_code": &"", "value": rows}


static func _validate_stage_rewards(
	rewards: Array[Dictionary],
	catalogs: Dictionary,
	seen: Dictionary,
) -> Dictionary:
	for reward: Dictionary in rewards:
		if not _exact_keys(reward, ["kind", "id"]):
			return _reject(&"invalid_stage_reward")
		if (
			typeof(reward["kind"]) not in [TYPE_STRING, TYPE_STRING_NAME]
			or typeof(reward["id"]) not in [TYPE_STRING, TYPE_STRING_NAME]
		):
			return _reject(&"invalid_stage_reward")
		var kind := String(reward["kind"])
		var item_id := String(reward["id"])
		var catalog_key := kind + "s"
		var reward_key := kind + ":" + item_id
		if (
			kind not in ["operator", "trap"]
			or not _is_ascii_id(item_id) or seen.has(reward_key)
			or not catalogs[catalog_key].has(StringName(item_id))
		):
			return _reject(&"invalid_stage_reward")
		seen[reward_key] = true
	return {"accepted": true, "error_code": &""}


static func _valid_recovery_shape(
	values: Array[StringName],
	operators: Array,
	squad_size: int,
) -> bool:
	if values.is_empty() or squad_size < 1 or values.size() > squad_size:
		return false
	var seen := {}
	for value: StringName in values:
		var operator_id := String(value)
		if (
			not _is_ascii_id(operator_id) or seen.has(operator_id)
			or not operators.has(value)
		):
			return false
		seen[operator_id] = true
	return true


static func _recovery_rosters_are_available(stages: Array, catalogs: Dictionary) -> bool:
	var available := {}
	var starting: Array = _derive_starting_unlocks(catalogs, stages)["operators"]
	for operator_id: StringName in starting:
		available[operator_id] = true
	for stage: StageDef in stages:
		for operator_id: StringName in stage.recovery_roster:
			if not available.has(operator_id):
				return false
		for reward: Dictionary in stage.rewards:
			if reward["kind"] == &"operator":
				available[StringName(reward["id"])] = true
	return true


static func _environment_manifest(
	catalogs: Dictionary,
	stages: Array,
	promotion_rules: Dictionary,
	combat_rules: Dictionary,
) -> Dictionary:
	var stage_rows: Array[Dictionary] = []
	for stage: StageDef in stages:
		var rewards: Array[Dictionary] = []
		for reward: Dictionary in stage.rewards:
			rewards.append({
				"kind": String(reward["kind"]),
				"id": String(reward["id"]),
			})
		stage_rows.append({
			"stage_id": String(stage.id),
			"campaign_index": stage.campaign_index,
			"squad_size": stage.squad_size,
			"recovery_roster": _strings(stage.recovery_roster),
			"rewards": rewards,
		})
	return {
		"operators": _strings(catalogs["operators"]),
		"traps": _strings(catalogs["traps"]),
		"stages": stage_rows,
		"promotion_rules": promotion_rules.duplicate(true),
		"combat_rules": combat_rules.duplicate(true),
	}


static func _exact_keys(value: Dictionary, expected: Array[String]) -> bool:
	if value.keys().size() != expected.size():
		return false
	for key: String in expected:
		if not value.has(key):
			return false
	return true


static func _is_ascii_id(value: String) -> bool:
	if value.is_empty():
		return false
	for character: String in value:
		if character not in "abcdefghijklmnopqrstuvwxyz0123456789_-":
			return false
	return true


static func _is_hex_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for character: String in value:
		if character not in "0123456789abcdef":
			return false
	return true


func _stage_stars_by_id() -> Dictionary:
	var values := {}
	for row: Dictionary in _data["stage_stars"]:
		values[StringName(row["stage_id"])] = int(row["stars"])
	return values


static func _string_names(values: Array) -> Array[StringName]:
	var result: Array[StringName] = []
	for value: Variant in values:
		result.append(StringName(value))
	return result


static func _strings(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in values:
		result.append(String(value))
	return result


static func _preview_accept(
	first_clear: bool,
	rewards_granted: Array,
	created_hero_rows: Array,
	next_index: int,
) -> Dictionary:
	return {
		"accepted": true,
		"error_code": &"",
		"first_clear": first_clear,
		"rewards_granted": rewards_granted.duplicate(true),
		"created_hero_rows": created_hero_rows.duplicate(true),
		"next_recruitment_index": next_index,
	}


static func _reject(error_code: StringName) -> Dictionary:
	return {"accepted": false, "error_code": error_code}
