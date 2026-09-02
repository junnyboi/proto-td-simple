class_name CampaignV3CommandHistory
extends RefCounted

## Replays the complete rules-v2 command ledger from the deterministic fresh
## campaign base. Persisted records corroborating one another is insufficient:
## every transition must be one the authoritative command rules could execute.

const RECRUIT_ID := "recruit"
const ATTEMPT_RULES_PATH := "res://sim/campaign_v3_attempts.gd"
const HASH_PATH := "res://sim/campaign_v3_hash.gd"
const RECRUITMENT_RULES_PATH := "res://sim/campaign_v3_recruitment.gd"
const RENAMING_RULES_PATH := "res://sim/campaign_v3_renaming.gd"
const LEGACY_HONOR_MARKS := 5
const LEGACY_MARKS_MAX := 1_000_000_000
const BattleTicketScript := preload("res://sim/battle_ticket.gd")
const BattleOutcomeScript := preload("res://sim/battle_outcome_v3.gd")
const PromotionRulesScript := preload("res://sim/campaign_v3_promotion_rules.gd")
const HeroIdentityScript := preload("res://sim/hero_identity.gd")
const ClassDefScript := preload("res://data/class_def.gd")
const HeroNamesScript := preload("res://sim/hero_names.gd")
const CommandCodecScript := preload("res://sim/campaign_v3_command_codec.gd")


static func validate(data: Dictionary, context: Dictionary) -> Dictionary:
	var records: Array = data["command_receipts"]
	if records.is_empty():
		return _accept(null)
	var fresh := _fresh_data(
		int(data["campaign_seed"]),
		int(data["campaign_generation"]),
		context,
	)
	if not fresh["accepted"]:
		return _reject(&"invalid_command_history")
	var replay: Dictionary = fresh["value"]
	replay["replay_marks_started_at_resolution"] = int(
		data["replay_marks_started_at_resolution"]
	)
	for record: Dictionary in records:
		if record["expected_save_revision"] != replay["save_revision"]:
			return _reject(&"command_history_revision_mismatch")
		var transition := _replay_record(replay, context, record)
		if not transition["accepted"]:
			return transition
		replay = transition["value"]
	if replay != data:
		return _reject(&"command_history_state_mismatch")
	return _accept(null)


## Validate one in-process append against an already certified state. Cold
## restore still uses validate() and replays from genesis; runtime mutations
## need only prove that their single new receipt produces the exact next state.
static func validate_append(
	certified: Dictionary,
	prospective: Dictionary,
	context: Dictionary,
) -> Dictionary:
	if not certified.has("command_receipts") or not prospective.has("command_receipts"):
		return _reject(&"invalid_command_history")
	var before: Array = certified["command_receipts"]
	var after: Array = prospective["command_receipts"]
	if after.size() != before.size() + 1:
		return _reject(&"command_history_append_mismatch")
	for index: int in before.size():
		if after[index] != before[index]:
			return _reject(&"command_history_append_mismatch")
	var raw_record: Variant = after[-1]
	if typeof(raw_record) != TYPE_DICTIONARY:
		return _reject(&"invalid_command_receipt")
	var record: Dictionary = raw_record
	for existing: Dictionary in before:
		if existing["command_id"] == record.get("command_id"):
			return _reject(&"command_id_conflict")
	var normalized := CommandCodecScript.normalize_records([record], prospective, context)
	if not normalized["accepted"] or normalized["value"] != [record]:
		return _reject(
			normalized.get("error_code", &"invalid_command_receipt")
			if not normalized["accepted"]
			else &"invalid_command_receipt"
		)
	if int(record["expected_save_revision"]) != int(certified["save_revision"]):
		return _reject(&"command_history_revision_mismatch")
	var replay := _replay_record(certified.duplicate(true), context, record)
	if not replay["accepted"]:
		return replay
	if replay["value"] != prospective:
		return _reject(&"command_history_state_mismatch")
	return _accept(prospective.duplicate(true))


static func can_append(data: Dictionary, context: Dictionary) -> bool:
	if not (data["command_receipts"] as Array).is_empty():
		return true
	var fresh := _fresh_data(
		int(data["campaign_seed"]),
		int(data["campaign_generation"]),
		context,
	)
	return fresh["accepted"] and fresh["value"] == data


static func _replay_record(
	data: Dictionary,
	context: Dictionary,
	record: Dictionary,
) -> Dictionary:
	match record["verb"]:
		"begin_attempt":
			return _replay_begin(data, context, record)
		"resolve_attempt":
			return _replay_resolution(data, context, record)
		"confirm_promotions":
			return _replay_promotions(data, context, record)
		"recruit_person":
			return _replay_recruitment(data, context, record)
		"rename_hero":
			return _replay_rename(data, record)
		"honor_fallen":
			return _replay_honor(data, record)
	return _reject(&"invalid_command_history")


static func _replay_begin(
	data: Dictionary,
	context: Dictionary,
	record: Dictionary,
) -> Dictionary:
	var attempts := _attempt_rules()
	if attempts.call("_has_unresolved_ticket", data):
		return _reject(&"command_history_transition_mismatch")
	var payload: Dictionary = record["payload"]
	var stage: Dictionary = (
		attempts
		. call(
			"_validate_stage",
			data,
			context,
			payload["stage_id"],
		)
	)
	if not stage["accepted"]:
		return _reject(&"command_history_transition_mismatch")
	if (
		(payload["hero_ids"] as Array).size()
		> int(context["stage_squad_sizes"][payload["stage_id"]])
	):
		return _reject(&"command_history_transition_mismatch")
	var squad: Dictionary = (
		attempts
		. call(
			"_squad",
			data,
			context,
			payload["hero_ids"],
			int(data["next_attempt_id"]),
		)
	)
	if not squad["accepted"]:
		return _reject(&"command_history_transition_mismatch")
	var working: Dictionary = data.duplicate(true)
	working["save_revision"] = int(data["save_revision"]) + 1
	var core: Dictionary = attempts.call("_core", working)
	var strategic: Dictionary = _hash_rules().call("of_core", core, context)
	if not strategic["accepted"]:
		return _reject(&"command_history_transition_mismatch")
	var ticket := (
		BattleTicketScript
		. seal(
			{
				"schema_version": BattleTicketScript.SCHEMA_VERSION,
				"campaign_uid": data["campaign_uid"],
				"attempt_id": data["next_attempt_id"],
				"stage_id": payload["stage_id"],
				"seed": payload["seed"],
				"expected_save_revision": working["save_revision"],
				"strategic_hash": strategic["hex"],
				"squad": squad["value"],
			}
		)
	)
	if not ticket["accepted"] or record["receipt"]["ticket"] != ticket["value"]:
		return _reject(&"command_history_receipt_mismatch")
	working["tickets"] = (working["tickets"] as Array).duplicate(true)
	working["tickets"].append(ticket["value"])
	working["next_attempt_id"] = int(data["next_attempt_id"]) + 1
	_append_record(working, record)
	return _accept(working)


static func _replay_resolution(
	data: Dictionary,
	context: Dictionary,
	record: Dictionary,
) -> Dictionary:
	var attempts := _attempt_rules()
	var payload: Dictionary = record["payload"]
	var attempt_id := int(payload["attempt_id"])
	var ticket: Dictionary = (
		attempts
		. call(
			"_ticket_by_attempt",
			data["tickets"],
			attempt_id,
		)
	)
	if (
		ticket.is_empty()
		or attempt_id != int(data["next_resolution_index"])
		or attempt_id + 1 != int(data["next_attempt_id"])
		or ticket != data["tickets"][-1]
		or ticket["expected_save_revision"] != data["save_revision"]
	):
		return _reject(&"command_history_transition_mismatch")
	var outcome := BattleOutcomeScript.normalize(payload["outcome"], ticket)
	if not outcome["accepted"]:
		return _reject(&"command_history_transition_mismatch")
	var derived: Dictionary = (
		attempts
		. call(
			"_derive_resolution",
			data,
			context,
			ticket,
			outcome["value"],
		)
	)
	if not derived["accepted"] or record["receipt"]["resolution"] != derived["resolution"]:
		return _reject(&"command_history_receipt_mismatch")
	var working: Dictionary = derived["data"]
	_append_record(working, record)
	return _accept(working)


static func _replay_promotions(
	data: Dictionary,
	context: Dictionary,
	record: Dictionary,
) -> Dictionary:
	if _attempt_rules().call("_has_unresolved_ticket", data):
		return _reject(&"command_history_transition_mismatch")
	var validated: Array[Dictionary] = []
	for choice: Dictionary in record["payload"]["choices"]:
		var result := PromotionRulesScript.validate_choice(data, context, choice)
		if not result["accepted"]:
			return _reject(&"command_history_transition_mismatch")
		validated.append(result["value"])
	var working: Dictionary = data.duplicate(true)
	working["heroes"] = (working["heroes"] as Array).duplicate(true)
	var receipt_choices: Array[Dictionary] = []
	for choice: Dictionary in validated:
		var hero := _hero_by_id(working["heroes"], choice["hero_id"])
		hero["current_class_id"] = choice["to_class_id"]
		hero["operator_def_id"] = choice["operator_def_id"]
		if hero["first_class_id"] == "recruit":
			hero["first_class_id"] = choice["to_class_id"]
		else:
			hero["advanced_class_id"] = choice["to_class_id"]
		(
			receipt_choices
			. append(
				{
					"hero_id": choice["hero_id"],
					"from_class_id": choice["from_class_id"],
					"to_class_id": choice["to_class_id"],
				}
			)
		)
	working["save_revision"] = int(data["save_revision"]) + 1
	var promotion := {
		"command_id": record["command_id"],
		"save_revision": working["save_revision"],
		"choices": receipt_choices,
	}
	if record["receipt"]["promotion"] != promotion:
		return _reject(&"command_history_receipt_mismatch")
	working["promotion_receipts"] = (working["promotion_receipts"] as Array).duplicate(true)
	working["promotion_receipts"].append(promotion)
	_append_record(working, record)
	return _accept(working)


static func _replay_recruitment(
	data: Dictionary,
	context: Dictionary,
	record: Dictionary,
) -> Dictionary:
	var derived: Dictionary = (
		load(RECRUITMENT_RULES_PATH)
		. call(
			"_derive",
			data,
			context,
			record["payload"],
		)
	)
	if not derived["accepted"]:
		return _reject(&"command_history_transition_mismatch")
	var working: Dictionary = derived["data"]
	working["save_revision"] = int(data["save_revision"]) + 1
	var receipt: Dictionary = derived["receipt"]
	receipt["save_revision"] = working["save_revision"]
	if record["receipt"] != {"recruitment": receipt}:
		return _reject(&"command_history_receipt_mismatch")
	_append_record(working, record)
	return _accept(working)


static func _replay_rename(data: Dictionary, record: Dictionary) -> Dictionary:
	var derived: Dictionary = load(RENAMING_RULES_PATH).call(
		"_derive", data, record["payload"],
	)
	if not derived["accepted"]:
		return _reject(&"command_history_transition_mismatch")
	var working: Dictionary = derived["data"]
	working["save_revision"] = int(data["save_revision"]) + 1
	var receipt: Dictionary = derived["receipt"]
	receipt["save_revision"] = working["save_revision"]
	if record["receipt"] != {"rename": receipt}:
		return _reject(&"command_history_receipt_mismatch")
	_append_record(working, record)
	return _accept(working)


static func _replay_honor(data: Dictionary, record: Dictionary) -> Dictionary:
	# Honor no longer exists as a command. This decode-only branch validates
	# ledgers written before the mechanic was removed without exposing it again.
	var derived := _derive_legacy_honor(data, record["payload"])
	if not derived["accepted"]:
		return _reject(&"command_history_transition_mismatch")
	var working: Dictionary = derived["data"]
	working["save_revision"] = int(data["save_revision"]) + 1
	var receipt: Dictionary = derived["receipt"]
	receipt["save_revision"] = working["save_revision"]
	if record["receipt"] != {"honor": receipt}:
		return _reject(&"command_history_receipt_mismatch")
	_append_record(working, record)
	return _accept(working)


static func _derive_legacy_honor(data: Dictionary, payload: Dictionary) -> Dictionary:
	if int(data["next_attempt_id"]) != int(data["next_resolution_index"]):
		return _reject(&"attempt_pending")
	var hero_id := String(payload["hero_id"])
	var target := _hero_by_id(data["heroes"], hero_id)
	if target.is_empty():
		return _reject(&"unknown_hero")
	if target["life_status"] != "dead":
		return _reject(&"hero_not_fallen")
	for previous: Dictionary in data.get("command_receipts", []):
		if (
			String(previous.get("verb", "")) == "honor_fallen"
			and String(previous.get("payload", {}).get("hero_id", "")) == hero_id
		):
			return _reject(&"already_honored")
	var marks_before := int(data["marks"])
	if marks_before > LEGACY_MARKS_MAX - LEGACY_HONOR_MARKS:
		return _reject(&"marks_overflow")
	var working: Dictionary = data.duplicate(true)
	working["marks"] = marks_before + LEGACY_HONOR_MARKS
	return {
		"accepted": true,
		"error_code": &"",
		"data": working,
		"receipt": {
			"hero_id": hero_id,
			"marks_before": marks_before,
			"marks_after": marks_before + LEGACY_HONOR_MARKS,
			"save_revision": 0,
		},
	}


static func _append_record(data: Dictionary, record: Dictionary) -> void:
	data["command_receipts"] = (data["command_receipts"] as Array).duplicate(true)
	data["command_receipts"].append(record.duplicate(true))


static func _attempt_rules() -> GDScript:
	return load(ATTEMPT_RULES_PATH) as GDScript


static func _hash_rules() -> GDScript:
	return load(HASH_PATH) as GDScript


static func _fresh_data(seed_value: int, generation: int, context: Dictionary) -> Dictionary:
	var campaign: Dictionary = context["campaign"]
	var heroes: Array[Dictionary] = []
	for index: int in (campaign["starter_rows"] as Array).size():
		var allocated := HeroIdentityScript.allocate_hero_id(
			seed_value,
			generation,
			index,
			func(candidate: String) -> bool:
				for row: Dictionary in heroes:
					if row["hero_id"] == candidate:
						return true
				return false,
		)
		if not allocated["accepted"]:
			return allocated
		var starter: Dictionary = campaign["starter_rows"][index]
		heroes.append(_fresh_hero(String(allocated["hero_id"]), index, starter))
	var offers: Array[Dictionary] = []
	for authored: Dictionary in campaign["paid_offers"]:
		(
			offers
			. append(
				{
					"offer_id": String(authored["offer_id"]),
					"operator_def_id": String(authored["operator_def_id"]),
					"cost": int(authored["cost"]),
					"consumed": false,
				}
			)
		)
	return _accept(
		{
			"campaign_uid": HeroIdentityScript.campaign_uid(seed_value, generation),
			"campaign_seed": seed_value,
			"campaign_generation": generation,
			"save_revision": 1,
			"next_recruitment_index": heroes.size(),
			"next_attempt_id": 1,
			"next_resolution_index": 1,
			"replay_marks_started_at_resolution": 1,
			"marks": int(campaign["initial_marks"]),
			"stage_stars": [],
			"unlocked_traps": [],
			"class_entitlements": [],
			"offers": offers,
			"heroes": heroes,
			"promotion_receipts": [],
			"promotion_proofs": [],
			"tickets": [],
			"memorial": [],
			"resolution_anchor": null,
			"last_resolution": null,
			"command_receipts": [],
		}
	)


static func _fresh_hero(hero_id: String, index: int, starter: Dictionary) -> Dictionary:
	var portrait_asset_id := String(starter["portrait_asset_id"])
	return {
		"hero_id": hero_id,
		"acquisition_operator_def_id": RECRUIT_ID,
		"operator_def_id": RECRUIT_ID,
		"current_class_id": RECRUIT_ID,
		"first_class_id": RECRUIT_ID,
		"advanced_class_id": null,
		"progression_rules_version": ClassDefScript.RULES_VERSION,
		"xp": 0,
		"identity_portrait_id": portrait_asset_id,
		"portrait_instance_id": "portrait:%s" % hero_id,
		"portrait_asset_id": portrait_asset_id,
		"recruitment_index": index,
		"recruited_after_resolution_index": 0,
		"recruit_source": "starter",
		"source_id": "",
		"name_version": HeroNamesScript.VERSION,
		"custom_callsign": null,
		"life_status": "ready",
		"death": null,
	}


static func _hero_by_id(heroes: Array, hero_id: String) -> Dictionary:
	for hero: Dictionary in heroes:
		if hero["hero_id"] == hero_id:
			return hero
	return {}


static func _accept(value: Variant) -> Dictionary:
	return {"accepted": true, "error_code": &"", "value": value}


static func _reject(code: StringName) -> Dictionary:
	return {"accepted": false, "error_code": code, "value": null}
