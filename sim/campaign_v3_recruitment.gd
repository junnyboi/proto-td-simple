class_name CampaignV3Recruitment
extends RefCounted

const CommandsScript := preload("res://sim/campaign_v3_commands.gd")
const CommandCodecScript := preload("res://sim/campaign_v3_command_codec.gd")
const StateCodecScript := preload("res://sim/campaign_v3_state_codec.gd")
const HeroIdentityScript := preload("res://sim/hero_identity.gd")
const ClassDefScript := preload("res://data/class_def.gd")
const HeroNamesScript := preload("res://sim/hero_names.gd")

## Every nonlegacy persistent person enters as a Recruit. Source-specific policy
## authorizes creation, but identity/class/portrait construction has one path.

const RECRUIT_ID := "recruit"


static func execute(
	state: Variant,
	command_id: Variant,
	expected_revision: Variant,
	source_value: Variant,
	source_id_value: Variant,
) -> Dictionary:
	var prepared := (
		CommandsScript
		. prepare(
			state,
			command_id,
			expected_revision,
			"recruit_person",
			{"source": source_value, "source_id": source_id_value},
		)
	)
	if not prepared["accepted"]:
		return prepared
	if prepared["duplicate"]:
		return prepared["result"]
	var derived := _derive(
		state._data,
		state._context_ref(),
		prepared["payload"],
	)
	if not derived["accepted"]:
		return CommandsScript.rejected(derived["error_code"])
	var working: Dictionary = derived["data"]
	working["save_revision"] = state.save_revision() + 1
	var receipt: Dictionary = derived["receipt"]
	receipt["save_revision"] = working["save_revision"]
	var record := (
		CommandCodecScript
		. record(
			prepared["command_id"],
			"recruit_person",
			prepared["expected_save_revision"],
			prepared["payload"],
			{"recruitment": receipt},
		)
	)
	working["command_receipts"] = (working["command_receipts"] as Array).duplicate(true)
	working["command_receipts"].append(record)
	var prospective: Dictionary = state._prospective_state(working)
	if not prospective["accepted"]:
		return CommandsScript.rejected(prospective["error_code"])
	return (
		CommandsScript
		. mutation(
			state,
			"recruit_person",
			prospective["value"],
			record,
			[
				{
					"name": &"recruit_created",
					"data":
					{
						"hero_id": receipt["hero"]["hero_id"],
						"source": prepared["payload"]["source"],
						"source_id": prepared["payload"]["source_id"],
						"save_revision": working["save_revision"],
					},
				},
			],
			{"recruitment": receipt.duplicate(true)},
		)
	)


static func _derive(
	data: Dictionary,
	context: Dictionary,
	payload: Dictionary,
) -> Dictionary:
	if int(data["next_attempt_id"]) != int(data["next_resolution_index"]):
		return _reject(&"attempt_pending")
	if (data["heroes"] as Array).size() >= StateCodecScript.MAX_ROSTER:
		return _reject(&"roster_limit")
	var source := String(payload["source"])
	var source_id := String(payload["source_id"])
	var working: Dictionary = data.duplicate(true)
	var marks_before := int(data["marks"])
	var policy := _authorize_source(working, context, source, source_id)
	if not policy["accepted"]:
		return policy
	var index := int(data["next_recruitment_index"])
	var allocated := HeroIdentityScript.allocate_hero_id(
		int(data["campaign_seed"]),
		int(data["campaign_generation"]),
		index,
		func(candidate: String) -> bool:
			for hero: Dictionary in data["heroes"]:
				if hero["hero_id"] == candidate:
					return true
			return false,
	)
	if not allocated["accepted"]:
		return _reject(allocated["error_code"])
	# Existing command ledgers must replay against the exact legacy sorted pool.
	# Only the newly introduced source adopts the recruit-only pool.
	var portrait_ids: Array = (
		context["campaign"]["recruit_portrait_asset_ids"]
		if source == "basic_hire"
		else context["campaign"]["portrait_asset_ids"]
	)
	if portrait_ids.is_empty():
		return _reject(&"missing_portrait_catalog")
	var hero := _fresh_hero(
		String(allocated["hero_id"]),
		index,
		String(portrait_ids[index % portrait_ids.size()]),
		source,
		source_id,
		int(data["next_resolution_index"]) - 1,
	)
	working["heroes"] = (working["heroes"] as Array).duplicate(true)
	working["heroes"].append(hero)
	working["next_recruitment_index"] = index + 1
	return {
		"accepted": true,
		"error_code": &"",
		"data": working,
		"receipt":
		{
			"hero": hero.duplicate(true),
			"marks_before": marks_before,
			"marks_after": int(working["marks"]),
			"save_revision": 0,
		},
	}


static func _authorize_source(
	data: Dictionary,
	context: Dictionary,
	source: String,
	source_id: String,
) -> Dictionary:
	match source:
		"basic_hire":
			if source_id != "mission_control":
				return _reject(&"invalid_basic_hire_source")
			var cost := int(context["campaign"]["basic_recruit_cost"])
			if int(data["marks"]) < cost:
				return _reject(&"insufficient_marks")
			data["marks"] = int(data["marks"]) - cost
			return _accept(null)
		"contract":
			for offer: Dictionary in data["offers"]:
				if offer["offer_id"] != source_id:
					continue
				if offer["consumed"]:
					return _reject(&"offer_consumed")
				if int(data["marks"]) < int(offer["cost"]):
					return _reject(&"insufficient_marks")
				offer["consumed"] = true
				data["marks"] = int(data["marks"]) - int(offer["cost"])
				return _accept(null)
			return _reject(&"unknown_offer")
		"recovery":
			if not _stage_cleared(data["stage_stars"], source_id):
				return _reject(&"recovery_stage_not_cleared")
			if _source_already_used(data["heroes"], source, source_id):
				return _reject(&"recovery_already_used")
			return _accept(null)
		"replacement":
			var dead := _hero_by_id(data["heroes"], source_id)
			if dead.is_empty() or dead["life_status"] != "dead":
				return _reject(&"replacement_source_not_dead")
			if _source_already_used(data["heroes"], source, source_id):
				return _reject(&"replacement_already_used")
			return _accept(null)
		"reward":
			return _reject(&"reward_person_creation_disabled")
	return _reject(&"invalid_recruit_source")


static func _fresh_hero(
	hero_id: String,
	index: int,
	portrait_asset_id: String,
	source: String,
	source_id: String,
	recruited_after_resolution_index: int,
) -> Dictionary:
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
		"recruited_after_resolution_index": recruited_after_resolution_index,
		"recruit_source": source,
		"source_id": source_id,
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


static func _stage_cleared(rows: Array, stage_id: String) -> bool:
	for row: Dictionary in rows:
		if row["stage_id"] == stage_id:
			return true
	return false


static func _source_already_used(heroes: Array, source: String, source_id: String) -> bool:
	for hero: Dictionary in heroes:
		if hero["recruit_source"] == source and hero["source_id"] == source_id:
			return true
	return false


static func _accept(value: Variant) -> Dictionary:
	return {"accepted": true, "error_code": &"", "value": value}


static func _reject(code: StringName) -> Dictionary:
	return {"accepted": false, "error_code": code}
