class_name CampaignV3Attempts
extends RefCounted

const U63_MAX := 9_223_372_036_854_775_807
const CODEC_PATH := "res://sim/campaign_v3_codec.gd"
const EconomyScript := preload("res://sim/campaign_v3_economy.gd")
const CommandsScript := preload("res://sim/campaign_v3_commands.gd")
const HashScript := preload("res://sim/campaign_v3_hash.gd")
const StateCodecScript := preload("res://sim/campaign_v3_state_codec.gd")
const BattleTicketScript := preload("res://sim/battle_ticket.gd")
const CommandCodecScript := preload("res://sim/campaign_v3_command_codec.gd")
const CanonicalJsonScript := preload("res://sim/canonical_json.gd")


static func begin(
	state: Variant,
	command_id: Variant,
	stage_id: Variant,
	hero_ids: Variant,
	seed: Variant,
	expected_revision: Variant,
) -> Dictionary:
	var prepared := (
		CommandsScript
		. prepare(
			state,
			command_id,
			expected_revision,
			"begin_attempt",
			{
				"stage_id": stage_id,
				"hero_ids": hero_ids,
				"seed": seed,
			},
		)
	)
	if not prepared["accepted"]:
		return prepared
	if prepared["duplicate"]:
		return prepared["result"]
	if _has_unresolved_ticket(state._data):
		return CommandsScript.rejected(&"attempt_pending")
	var payload: Dictionary = prepared["payload"]
	var stage_check := _validate_stage(state._data, state._context_ref(), payload["stage_id"])
	if not stage_check["accepted"]:
		return CommandsScript.rejected(stage_check["error_code"])
	if (
		(payload["hero_ids"] as Array).size()
		> int(
			state._context_ref()["stage_squad_sizes"][payload["stage_id"]],
		)
	):
		return CommandsScript.rejected(&"squad_too_large")
	if state.next_attempt_id() >= U63_MAX:
		return CommandsScript.rejected(&"attempt_counter_exhausted")
	var squad := _squad(
		state._data,
		state._context_ref(),
		payload["hero_ids"],
		state.next_attempt_id(),
	)
	if not squad["accepted"]:
		return CommandsScript.rejected(squad["error_code"])
	var working: Dictionary = state._data.duplicate(true)
	working["save_revision"] = state.save_revision() + 1
	var pre_ticket_core := _core(working)
	var strategic := HashScript.of_core(pre_ticket_core, state._context_ref())
	if not strategic["accepted"]:
		return CommandsScript.rejected(&"invalid_campaign_state")
	var ticket := (
		BattleTicketScript
		. seal(
			{
				"schema_version": BattleTicketScript.SCHEMA_VERSION,
				"campaign_uid": state.campaign_uid(),
				"attempt_id": state.next_attempt_id(),
				"stage_id": payload["stage_id"],
				"seed": payload["seed"],
				"expected_save_revision": working["save_revision"],
				"strategic_hash": strategic["hex"],
				"squad": squad["value"],
			}
		)
	)
	if not ticket["accepted"]:
		return CommandsScript.rejected(ticket["error_code"])
	working["tickets"] = (working["tickets"] as Array).duplicate(true)
	working["tickets"].append(ticket["value"])
	working["next_attempt_id"] = state.next_attempt_id() + 1
	var record := (
		CommandCodecScript
		. record(
			prepared["command_id"],
			"begin_attempt",
			prepared["expected_save_revision"],
			payload,
			{"ticket": ticket["value"]},
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
			"begin_attempt",
			prospective["value"],
			record,
			[
				_event(
					&"campaign_attempt_started",
					{
						"command_id": prepared["command_id"],
						"attempt_id": ticket["value"]["attempt_id"],
						"stage_id": ticket["value"]["stage_id"],
						"ticket_hash": ticket["value"]["ticket_hash"],
						"save_revision": working["save_revision"],
					}
				)
			],
			{"ticket": ticket["value"].duplicate(true)},
		)
	)


static func resolve(
	state: Variant,
	command_id: Variant,
	attempt_id: Variant,
	outcome_document: Variant,
	expected_revision: Variant,
) -> Dictionary:
	var prepared := (
		CommandsScript
		. prepare(
			state,
			command_id,
			expected_revision,
			"resolve_attempt",
			{
				"attempt_id": attempt_id,
				"outcome": outcome_document,
			},
		)
	)
	if not prepared["accepted"]:
		return prepared
	if prepared["duplicate"]:
		return prepared["result"]
	var payload: Dictionary = prepared["payload"]
	var ticket := _ticket_by_attempt(state._data["tickets"], payload["attempt_id"])
	if ticket.is_empty():
		return CommandsScript.rejected(&"missing_resolution_ticket")
	if (
		payload["attempt_id"] != state.next_resolution_index()
		or payload["attempt_id"] + 1 != state.next_attempt_id()
		or ticket != state._data["tickets"][-1]
	):
		return CommandsScript.rejected(&"wrong_attempt")
	if ticket["expected_save_revision"] != state.save_revision():
		return CommandsScript.rejected(&"ticket_revision_mismatch")
	var derived := _derive_resolution(
		state._data,
		state._context_ref(),
		ticket,
		payload["outcome"],
	)
	if not derived["accepted"]:
		return CommandsScript.rejected(derived["error_code"])
	var working: Dictionary = derived["data"]
	var record := (
		CommandCodecScript
		. record(
			prepared["command_id"],
			"resolve_attempt",
			prepared["expected_save_revision"],
			payload,
			{"resolution": derived["resolution"]},
		)
	)
	working["command_receipts"] = (working["command_receipts"] as Array).duplicate(true)
	working["command_receipts"].append(record)
	var prospective: Dictionary = state._prospective_state(working)
	if not prospective["accepted"]:
		return CommandsScript.rejected(prospective["error_code"])
	var events: Array[Dictionary] = [
		_event(
			&"campaign_resolution_committed",
			{
				"command_id": prepared["command_id"],
				"resolution_index": derived["resolution"]["resolution_index"],
				"attempt_id": derived["resolution"]["attempt_id"],
				"outcome_hash": derived["resolution"]["outcome_hash"],
				"save_revision": working["save_revision"],
			}
		)
	]
	for hero_id: String in derived["resolution"]["dead_hero_ids"]:
		(
			events
			. append(
				_event(
					&"permanent_death_committed",
					{
						"hero_id": hero_id,
						"resolution_index": derived["resolution"]["resolution_index"],
						"memorial_id": "memorial:%s" % hero_id,
					}
				)
			)
		)
	return (
		CommandsScript
		. mutation(
			state,
			"resolve_attempt",
			prospective["value"],
			record,
			events,
			{
				"resolution": derived["resolution"].duplicate(true),
				"outcome": payload["outcome"].duplicate(true),
			},
		)
	)


static func _derive_resolution(
	data: Dictionary,
	context: Dictionary,
	ticket: Dictionary,
	outcome: Dictionary,
) -> Dictionary:
	if data["save_revision"] >= U63_MAX or data["next_resolution_index"] >= U63_MAX:
		return _reject(&"resolution_counter_exhausted")
	var before := _core(data)
	var after: Dictionary = before.duplicate(true)
	after["save_revision"] = int(before["save_revision"]) + 1
	after["next_resolution_index"] = int(before["next_resolution_index"]) + 1
	var stage_id := String(ticket["stage_id"])
	var stars_before := _stars_for(before["stage_stars"], stage_id)
	var stars_after := stars_before
	if outcome["result"] == "clear":
		stars_after = maxi(stars_before, int(outcome["stars"]))
		if stars_before == 0:
			after["stage_stars"] = (after["stage_stars"] as Array).duplicate(true)
			(
				after["stage_stars"]
				. append(
					{
						"stage_id": stage_id,
						"stars": stars_after,
						"first_clear_resolution_index": before["next_resolution_index"],
						"first_clear_attempt_id": ticket["attempt_id"],
						"first_clear_terminal_tick": outcome["terminal_tick"],
					}
				)
			)
		elif stars_after != stars_before:
			var upgraded := false
			var stage_rows := after["stage_stars"] as Array
			for index: int in stage_rows.size():
				var row := stage_rows[index] as Dictionary
				if row["stage_id"] == stage_id:
					var upgraded_row := row.duplicate(true)
					upgraded_row["stars"] = stars_after
					stage_rows[index] = upgraded_row
					upgraded = true
					break
			if not upgraded:
				return _reject(&"invalid_campaign_state")
	var rewards: Array[Dictionary] = EconomyScript.resolution_rewards(
		before,
		stage_id,
		String(outcome["result"]),
		stars_before,
		context,
	)
	after["unlocked_traps"] = (after["unlocked_traps"] as Array).duplicate()
	for reward: Dictionary in rewards:
		if reward["kind"] == "trap":
			after["unlocked_traps"].append(reward["id"])
		elif reward["kind"] == "currency" and reward["id"] == "marks":
			var marks_after_reward := int(after["marks"]) + int(reward["amount"])
			if marks_after_reward > StateCodecScript.MARKS_MAX:
				return _reject(&"marks_overflow")
			after["marks"] = marks_after_reward
	after["unlocked_traps"].sort()
	after["class_entitlements"] = (before["class_entitlements"] as Array).duplicate()
	after["heroes"] = (after["heroes"] as Array).duplicate(true)
	# These fields remain in the save schema for legacy decoding only. Mission
	# resolution no longer awards XP or unlocks class paths.
	var entitlements_granted: Array[String] = []
	var xp_awards: Array[Dictionary] = []
	# A tactical fall ends the unit's participation in this battle only. Campaign
	# operators remain available and no persistent casualty record is created.
	var dead_ids: Array[String] = []
	var memorial_ids: Array[String] = []
	var before_hash := HashScript.of_core(before, context)
	var after_hash := HashScript.of_core(after, context)
	if not before_hash["accepted"] or not after_hash["accepted"]:
		return _reject(&"invalid_campaign_state")
	var resolution := {
		"schema_version": 1,
		"resolution_index": before["next_resolution_index"],
		"campaign_uid": before["campaign_uid"],
		"attempt_id": ticket["attempt_id"],
		"stage_id": stage_id,
		"ticket_hash": ticket["ticket_hash"],
		"outcome_hash": outcome["outcome_hash"],
		"result": outcome["result"],
		"terminal_reason": outcome["terminal_reason"],
		"terminal_tick": outcome["terminal_tick"],
		"stars_before": stars_before,
		"stars_after": stars_after,
		"rewards_granted": rewards,
		"class_entitlements_granted": entitlements_granted,
		"created_hero_ids": [],
		"dead_hero_ids": dead_ids,
		"xp_awards": xp_awards,
		"memorial_ids": memorial_ids,
		"marks_before": before["marks"],
		"marks_after": after["marks"],
		"strategic_body_hash_before": before_hash["hex"],
		"strategic_body_hash_after": after_hash["hex"],
	}
	var working: Dictionary = data.duplicate(true)
	for key: String in _codec().CORE_KEYS:
		working[key] = after[key]
	working["resolution_anchor"] = {
		"resolution_index": resolution["resolution_index"],
		"save_revision_after": after["save_revision"],
		"before_core": before,
		"after_core": after,
		"strategic_body_hash_before": before_hash["hex"],
		"strategic_body_hash_after": after_hash["hex"],
	}
	working["last_resolution"] = resolution
	return {"accepted": true, "error_code": &"", "data": working, "resolution": resolution}


static func _squad(
	data: Dictionary,
	context: Dictionary,
	hero_ids: Array,
	attempt_id: int,
) -> Dictionary:
	var squad: Array[Dictionary] = []
	var battle_ids := {}
	for index: int in hero_ids.size():
		var hero := _hero_by_id(data["heroes"], hero_ids[index])
		if hero.is_empty():
			return _reject(&"unknown_hero")
		var projection: Dictionary = (
			context["operator_ticket_by_id"]
			. get(
				hero["operator_def_id"],
				{},
			)
		)
		if projection.is_empty():
			return _reject(&"missing_catalog")
		var battle_id := (
			CanonicalJsonScript
			. sha256_hex(
				[
					data["campaign_uid"],
					attempt_id,
					index,
					hero["hero_id"],
				]
			)
			. substr(0, 16)
		)
		if battle_ids.has(battle_id):
			return _reject(&"battle_identity_collision")
		battle_ids[battle_id] = true
		var visual: Dictionary = projection["visual_spec"].duplicate(true)
		visual["portrait_asset_id"] = hero["portrait_asset_id"]
		var skill: Dictionary = projection["skill_spec"].duplicate(true)
		skill["payload"] = _canonical_payload(skill["payload"])
		(
			squad
			. append(
				{
					"slot_index": index,
					"battle_id": battle_id,
					"hero_id": hero["hero_id"],
					"class_id": hero["current_class_id"],
					"operator_def_id": hero["operator_def_id"],
					"operator_content_sha256": projection["operator_content_sha256"],
					"combat_spec": projection["combat_spec"].duplicate(true),
					"target_policy_spec": projection["target_policy_spec"].duplicate(true),
					"skill_spec": skill,
					"visual_spec": visual,
				}
			)
		)
	return {"accepted": true, "error_code": &"", "value": squad}


static func _canonical_payload(value: Variant) -> Variant:
	if value is Array:
		var items: Array = []
		for item: Variant in value:
			items.append(_canonical_payload(item))
		return items
	if value is Dictionary:
		var names: Array[String] = []
		for raw_key: Variant in value:
			names.append(String(raw_key))
		names.sort()
		var object := {}
		for key: String in names:
			object[key] = _canonical_payload(value[key])
		return object
	return value


static func _validate_stage(data: Dictionary, context: Dictionary, stage_id: String) -> Dictionary:
	var position := (context["stage_order"] as Array).find(stage_id)
	if position < 0:
		return _reject(&"unknown_campaign_stage")
	if position == 0:
		return _accept(null)
	var prior := String(context["stage_order"][position - 1])
	return _accept(null) if _stars_for(data["stage_stars"], prior) > 0 else _reject(&"stage_locked")


static func _has_unresolved_ticket(data: Dictionary) -> bool:
	return int(data["next_attempt_id"]) == int(data["next_resolution_index"]) + 1


static func _ticket_by_attempt(tickets: Array, attempt_id: int) -> Dictionary:
	for ticket: Dictionary in tickets:
		if ticket["attempt_id"] == attempt_id:
			return ticket
	return {}


static func _hero_by_id(heroes: Array, hero_id: String) -> Dictionary:
	for hero: Dictionary in heroes:
		if hero["hero_id"] == hero_id:
			return hero
	return {}


static func _core(data: Dictionary) -> Dictionary:
	var core := {}
	for key: String in _codec().CORE_KEYS:
		core[key] = (
			data[key].duplicate(true)
			if data[key] is Array or data[key] is Dictionary
			else data[key]
		)
	return core


static func _stars_for(rows: Array, stage_id: String) -> int:
	for row: Dictionary in rows:
		if row["stage_id"] == stage_id:
			return int(row["stars"])
	return 0


static func _codec() -> GDScript:
	return load(CODEC_PATH) as GDScript


static func _event(name: StringName, data: Dictionary) -> Dictionary:
	return {"name": name, "data": data}


static func _accept(value: Variant) -> Dictionary:
	return {"accepted": true, "error_code": &"", "value": value}


static func _reject(code: StringName) -> Dictionary:
	return {"accepted": false, "error_code": code}
