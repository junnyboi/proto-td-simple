class_name CampaignV3StateCodec
extends RefCounted

## Rules-v2 CampaignSave grammar. This module validates representable future
## states before mutators exist; it does not grant rewards or apply commands.

const U32_MAX := 4_294_967_295
const U63_MAX := 9_223_372_036_854_775_807
const MARKS_MAX := 1_000_000_000
const MAX_ROSTER := 1024
const SOURCE_VALUES := [
	"starter", "basic_hire", "contract", "reward", "recovery", "replacement",
]
const LIFE_VALUES := ["ready", "dead"]
const TERMINAL_VALUES := ["clear", "leak_defeat", "base_defeat", "resign"]
const RECEIPT_KEYS := ["command_id", "save_revision", "choices"]
const CHOICE_KEYS := ["hero_id", "from_class_id", "to_class_id"]
const MEMORIAL_KEYS := [
	"memorial_id", "hero_id", "portrait_instance_id", "portrait_asset_id",
	"class_id", "death",
]
const DEATH_KEYS := [
	"resolution_index", "attempt_id", "stage_id", "terminal_reason", "terminal_tick",
]
const COMMAND_CODEC_PATH := "res://sim/campaign_v3_command_codec.gd"
const HISTORY_PATH := "res://sim/campaign_v3_history.gd"
const COMMAND_HISTORY_PATH := "res://sim/campaign_v3_command_history.gd"
const HASH_PATH := "res://sim/campaign_v3_hash.gd"
const HeroIdentityScript := preload("res://sim/hero_identity.gd")
const HeroCodecScript := preload("res://sim/campaign_hero_codec.gd")
const ClassDefScript := preload("res://data/class_def.gd")
const HeroNamesScript := preload("res://sim/hero_names.gd")
const BattleTicketScript := preload("res://sim/battle_ticket.gd")




static func normalize_data(
	data: Dictionary,
	context: Dictionary,
	data_keys: Array,
	core_keys: Array,
	hero_keys: Array,
) -> Dictionary:
	var core_input := {}
	for key: String in core_keys:
		core_input[key] = data[key]
	var core := normalize_core(core_input, context, core_keys, hero_keys)
	if not core["accepted"]:
		return core
	var commands: Dictionary = load(COMMAND_CODEC_PATH).call("normalize_records",
		data["command_receipts"], core["value"], context,
	)
	if not commands["accepted"]:
		return commands
	var current: Dictionary = core["value"].duplicate(true)
	current["command_receipts"] = commands["value"]
	current["resolution_anchor"] = data["resolution_anchor"]
	current["last_resolution"] = data["last_resolution"]
	var history: Dictionary = load(HISTORY_PATH).call("normalize",
		data["resolution_anchor"], data["last_resolution"], current, context,
		core_keys, hero_keys,
	)
	if not history["accepted"]:
		return history
	current["resolution_anchor"] = history["value"]["anchor"]
	current["last_resolution"] = history["value"]["receipt"]
	var command_history: Dictionary = load(COMMAND_HISTORY_PATH).call(
		"validate", current, context,
	)
	if not command_history["accepted"]:
		return command_history
	var ordered := {}
	for key: String in data_keys:
		ordered[key] = current[key]
	return _accept(ordered)


static func normalize_core(
	value: Variant,
	context: Dictionary,
	core_keys: Array,
	hero_keys: Array,
) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY or value.keys() != core_keys:
		return _reject(&"invalid_core_snapshot")
	for key: String in [
		"campaign_seed", "campaign_generation", "save_revision", "next_recruitment_index",
		"next_attempt_id", "next_resolution_index", "replay_marks_started_at_resolution", "marks",
	]:
		if typeof(value[key]) != TYPE_INT:
			return _reject(&"invalid_integer")
	if not _is_hex(String(value["campaign_uid"]), 16):
		return _reject(&"invalid_campaign_uid")
	if (
		value["campaign_uid"]
			!= HeroIdentityScript.campaign_uid(value["campaign_seed"], value["campaign_generation"])
	):
		return _reject(&"campaign_uid_mismatch")
	for key: String in [
		"campaign_generation", "save_revision", "next_attempt_id", "next_resolution_index",
	]:
		if not _in_range(value[key], 1, U63_MAX):
			return _reject(&"invalid_counter")
	if not _in_range(value["next_recruitment_index"], 0, U63_MAX):
		return _reject(&"invalid_counter")
	if not _in_range(value["replay_marks_started_at_resolution"], 1, U63_MAX):
		return _reject(&"invalid_counter")
	if not _in_range(value["marks"], 0, MARKS_MAX):
		return _reject(&"invalid_counter")
	var stage_stars := _normalize_stage_stars(value["stage_stars"], context)
	var traps := _normalize_string_set(value["unlocked_traps"], context["trap_ids"])
	if not stage_stars["accepted"]:
		return stage_stars
	if not traps["accepted"]:
		return _reject(&"invalid_unlocks")
	var entitlements := _normalize_entitlements(value["class_entitlements"], context)
	if not entitlements["accepted"]:
		return entitlements
	var offers := _normalize_offers(value["offers"], context)
	var heroes := _normalize_heroes(value["heroes"], context, hero_keys)
	var receipts := _normalize_receipts(value["promotion_receipts"], context)
	var tickets := _normalize_tickets(value["tickets"], value["campaign_uid"])
	var memorial := _normalize_memorial(value["memorial"], context)
	for result: Dictionary in [offers, heroes, receipts, tickets, memorial]:
		if not result["accepted"]:
			return result
	if value["promotion_proofs"] != []:
		return _reject(&"invalid_v3_promotion_proofs")
	if heroes["value"].size() != value["next_recruitment_index"]:
		return _reject(&"recruitment_counter_mismatch")
	if value["next_attempt_id"] not in [
		value["next_resolution_index"], value["next_resolution_index"] + 1,
	]:
		return _reject(&"attempt_resolution_counter_mismatch")
	var linked := _validate_links(
		heroes["value"], receipts["value"], tickets["value"], memorial["value"], context,
		int(value["next_resolution_index"]),
	)
	if not linked["accepted"]:
		return linked
	if (
		not receipts["value"].is_empty()
		and receipts["value"][-1]["save_revision"] > value["save_revision"]
	):
		return _reject(&"promotion_revision_ahead")
	var expected_attempt := 1
	if not tickets["value"].is_empty():
		expected_attempt = int(tickets["value"][-1]["attempt_id"]) + 1
	if value["next_attempt_id"] != expected_attempt:
		return _reject(&"attempt_counter_mismatch")
	var ordered := {
		"campaign_uid": String(value["campaign_uid"]),
		"campaign_seed": int(value["campaign_seed"]),
		"campaign_generation": int(value["campaign_generation"]),
		"save_revision": int(value["save_revision"]),
		"next_recruitment_index": int(value["next_recruitment_index"]),
		"next_attempt_id": int(value["next_attempt_id"]),
		"next_resolution_index": int(value["next_resolution_index"]),
		"replay_marks_started_at_resolution": int(value["replay_marks_started_at_resolution"]),
		"marks": int(value["marks"]),
		"stage_stars": stage_stars["value"],
		"unlocked_traps": traps["value"],
		"class_entitlements": entitlements["value"],
		"offers": offers["value"],
		"heroes": heroes["value"],
		"promotion_receipts": receipts["value"],
		"promotion_proofs": [],
		"tickets": tickets["value"],
		"memorial": memorial["value"],
	}
	var pending := _validate_unresolved_ticket_issuance(ordered, context)
	if not pending["accepted"]:
		return pending
	return _accept(ordered)


static func _normalize_stage_stars(value: Variant, context: Dictionary) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return _reject(&"invalid_stage_stars")
	var out: Array[Dictionary] = []
	var previous_index := 0
	for row: Variant in value:
		var keys := [
			"stage_id", "stars", "first_clear_resolution_index",
			"first_clear_attempt_id", "first_clear_terminal_tick",
		]
		if typeof(row) != TYPE_DICTIONARY or row.keys() != keys:
			return _reject(&"invalid_stage_stars")
		var stage_id := String(row["stage_id"])
		var stage_index := (context["stage_order"] as Array).find(stage_id) + 1
		if stage_index <= previous_index:
			return _reject(&"noncanonical_stage_order")
		previous_index = stage_index
		if not _in_range(row["stars"], 1, 3):
			return _reject(&"invalid_stage_stars")
		for key: String in [
			"first_clear_resolution_index", "first_clear_attempt_id",
			"first_clear_terminal_tick",
		]:
			if not _in_range(row[key], 1 if key != "first_clear_terminal_tick" else 0, U63_MAX):
				return _reject(&"invalid_stage_stars")
		out.append({
			"stage_id": stage_id,
			"stars": int(row["stars"]),
			"first_clear_resolution_index": int(row["first_clear_resolution_index"]),
			"first_clear_attempt_id": int(row["first_clear_attempt_id"]),
			"first_clear_terminal_tick": int(row["first_clear_terminal_tick"]),
		})
	return _accept(out)


static func _normalize_string_set(value: Variant, allowed: Dictionary) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return _reject(&"invalid_string_set")
	var out: Array[String] = []
	for raw: Variant in value:
		var text := String(raw)
		if not allowed.has(text) or out.has(text):
			return _reject(&"invalid_string_set")
		out.append(text)
	var sorted := out.duplicate()
	sorted.sort()
	return _accept(out) if out == sorted else _reject(&"noncanonical_string_order")


static func _normalize_entitlements(value: Variant, context: Dictionary) -> Dictionary:
	var allowed := {}
	for row: Dictionary in context["campaign"]["stage_class_entitlements"]:
		allowed[String(row["class_id"])] = true
	return _normalize_string_set(value, allowed)


static func _normalize_offers(value: Variant, context: Dictionary) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return _reject(&"invalid_offers")
	var authored: Array = context["campaign"]["paid_offers"]
	if (value as Array).size() != authored.size():
		return _reject(&"invalid_offers")
	var out: Array[Dictionary] = []
	for index: int in authored.size():
		var raw: Variant = value[index]
		if typeof(raw) != TYPE_DICTIONARY:
			return _reject(&"invalid_offer")
		if raw.keys() != ["offer_id", "operator_def_id", "cost", "consumed"]:
			return _reject(&"invalid_offer")
		var expected: Dictionary = authored[index]
		if (
			raw["offer_id"] != expected["offer_id"]
			or raw["operator_def_id"] != "recruit"
			or raw["cost"] != expected["cost"]
			or typeof(raw["consumed"]) != TYPE_BOOL
		):
			return _reject(&"invalid_offer")
		out.append(raw.duplicate(true))
	return _accept(out)


static func _normalize_heroes(value: Variant, context: Dictionary, hero_keys: Array) -> Dictionary:
	if typeof(value) != TYPE_ARRAY or (value as Array).is_empty():
		return _reject(&"empty_roster")
	if (value as Array).size() > MAX_ROSTER:
		return _reject(&"roster_too_large")
	var out: Array[Dictionary] = []
	var hero_ids := {}
	var portrait_instances := {}
	for index: int in (value as Array).size():
		var raw: Variant = value[index]
		if typeof(raw) != TYPE_DICTIONARY or raw.keys() != hero_keys:
			return _reject(&"invalid_hero")
		if raw["recruitment_index"] != index or not _is_hex(String(raw["hero_id"]), 16):
			return _reject(&"invalid_hero")
		if raw["progression_rules_version"] != ClassDefScript.RULES_VERSION:
			return _reject(&"invalid_progression_rules_version")
		if not _validate_class_projection(raw, context):
			return _reject(&"invalid_class_projection")
		if not _in_range(raw["xp"], 0, U63_MAX):
			return _reject(&"invalid_hero")
		if not _in_range(raw["recruited_after_resolution_index"], 0, U63_MAX):
			return _reject(&"invalid_hero")
		if raw["name_version"] != HeroNamesScript.VERSION:
			return _reject(&"invalid_hero")
		if String(raw["recruit_source"]) not in SOURCE_VALUES:
			return _reject(&"invalid_hero")
		if not _ascii(String(raw["source_id"]), true):
			return _reject(&"invalid_hero")
		if not HeroCodecScript.valid_callsign(raw["custom_callsign"]):
			return _reject(&"invalid_hero")
		if String(raw["life_status"]) not in LIFE_VALUES:
			return _reject(&"invalid_hero")
		var death := _normalize_death(raw["death"])
		if not death["accepted"]:
			return death
		if (raw["life_status"] == "dead") != (death["value"] != null):
			return _reject(&"invalid_life_state")
		var portrait_instance := String(raw["portrait_instance_id"])
		if portrait_instance != "portrait:%s" % raw["hero_id"]:
			return _reject(&"invalid_portrait_instance")
		if not (context["campaign"]["portrait_asset_ids"] as Array).has(
			String(raw["portrait_asset_id"]),
		):
			return _reject(&"invalid_portrait_asset")
		if raw["identity_portrait_id"] != raw["portrait_asset_id"]:
			return _reject(&"invalid_portrait_asset")
		if hero_ids.has(raw["hero_id"]) or portrait_instances.has(portrait_instance):
			return _reject(&"duplicate_hero")
		if raw["acquisition_operator_def_id"] != "recruit":
			return _reject(&"invalid_recruit_hero")
		hero_ids[raw["hero_id"]] = true
		portrait_instances[portrait_instance] = true
		if index < 5:
			var starter: Dictionary = context["campaign"]["starter_rows"][index]
			if (
				raw["recruit_source"] != "starter"
				or raw["source_id"] != ""
				or raw["recruited_after_resolution_index"] != 0
				or raw["portrait_asset_id"] != starter["portrait_asset_id"]
			):
				return _reject(&"invalid_starter")
		elif raw["recruit_source"] == "starter":
			return _reject(&"invalid_starter")
		var ordered := {}
		for key: String in hero_keys:
			ordered[key] = death["value"] if key == "death" else raw[key]
		out.append(ordered)
	return _accept(out)


static func _validate_class_projection(hero: Dictionary, context: Dictionary) -> bool:
	var class_id := String(hero["current_class_id"])
	if not context["class_by_id"].has(class_id):
		return false
	var row: Dictionary = context["class_by_id"][class_id]
	if hero["operator_def_id"] != row["operator_def_id"]:
		return false
	if class_id == "recruit":
		return hero["first_class_id"] == "recruit" and hero["advanced_class_id"] == null
	if int(row["stage"]) == ClassDefScript.Stage.STANDARD:
		return hero["first_class_id"] == class_id and hero["advanced_class_id"] == null
	return (
		hero["first_class_id"] == row["promotion_from_class_id"]
		and hero["advanced_class_id"] == class_id
	)


static func _normalize_receipts(value: Variant, context: Dictionary) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return _reject(&"invalid_promotion_receipts")
	var out: Array[Dictionary] = []
	var previous_revision := 1
	for raw: Variant in value:
		if typeof(raw) != TYPE_DICTIONARY or raw.keys() != RECEIPT_KEYS:
			return _reject(&"invalid_promotion_receipt")
		var command_id := String(raw["command_id"])
		if not _ascii(command_id):
			return _reject(&"invalid_promotion_receipt")
		if not _in_range(raw["save_revision"], 2, U63_MAX):
			return _reject(&"invalid_promotion_receipt")
		if int(raw["save_revision"]) <= previous_revision:
			return _reject(&"noncanonical_promotion_receipt_order")
		previous_revision = int(raw["save_revision"])
		if typeof(raw["choices"]) != TYPE_ARRAY or (raw["choices"] as Array).is_empty():
			return _reject(&"invalid_promotion_receipt")
		var choices: Array[Dictionary] = []
		var previous_hero := ""
		for choice: Variant in raw["choices"]:
			if typeof(choice) != TYPE_DICTIONARY or choice.keys() != CHOICE_KEYS:
				return _reject(&"invalid_promotion_choice")
			var hero_id := String(choice["hero_id"])
			if not _is_hex(hero_id, 16) or (not previous_hero.is_empty() and hero_id <= previous_hero):
				return _reject(&"noncanonical_promotion_choice_order")
			previous_hero = hero_id
			if not _legal_edge(String(choice["from_class_id"]), String(choice["to_class_id"]), context):
				return _reject(&"invalid_promotion_choice")
			choices.append(choice.duplicate(true))
		out.append({
			"command_id": command_id,
			"save_revision": int(raw["save_revision"]),
			"choices": choices,
		})
	return _accept(out)


static func _normalize_tickets(value: Variant, campaign_uid: String) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return _reject(&"invalid_tickets")
	var out: Array[Dictionary] = []
	var previous_attempt := 0
	for raw: Variant in value:
		var ticket := BattleTicketScript.normalize(raw)
		if not ticket["accepted"]:
			return ticket
		if ticket["value"]["campaign_uid"] != campaign_uid:
			return _reject(&"ticket_campaign_mismatch")
		if ticket["value"]["attempt_id"] <= previous_attempt:
			return _reject(&"noncanonical_ticket_order")
		previous_attempt = ticket["value"]["attempt_id"]
		out.append(ticket["value"])
	return _accept(out)


static func _normalize_memorial(value: Variant, context: Dictionary) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return _reject(&"invalid_memorial")
	var out: Array[Dictionary] = []
	var previous := ""
	for raw: Variant in value:
		if typeof(raw) != TYPE_DICTIONARY or raw.keys() != MEMORIAL_KEYS:
			return _reject(&"invalid_memorial_row")
		var hero_id := String(raw["hero_id"])
		if not _is_hex(hero_id, 16) or (not previous.is_empty() and hero_id <= previous):
			return _reject(&"noncanonical_memorial_order")
		previous = hero_id
		if raw["memorial_id"] != "memorial:%s" % hero_id:
			return _reject(&"invalid_memorial_row")
		if raw["portrait_instance_id"] != "portrait:%s" % hero_id:
			return _reject(&"invalid_memorial_row")
		if not (context["campaign"]["portrait_asset_ids"] as Array).has(
			String(raw["portrait_asset_id"]),
		):
			return _reject(&"invalid_memorial_row")
		if not context["class_by_id"].has(String(raw["class_id"])):
			return _reject(&"invalid_memorial_row")
		var death := _normalize_death(raw["death"])
		if not death["accepted"] or death["value"] == null:
			return _reject(&"invalid_memorial_row")
		var row: Dictionary = raw.duplicate(true)
		row["death"] = death["value"]
		out.append(row)
	return _accept(out)


static func _validate_links(
	heroes: Array,
	receipts: Array,
	tickets: Array,
	memorial: Array,
	context: Dictionary,
	next_resolution_index: int,
) -> Dictionary:
	var by_id := {}
	var class_cursor := {}
	for hero: Dictionary in heroes:
		by_id[hero["hero_id"]] = hero
		class_cursor[hero["hero_id"]] = "recruit"
	for receipt: Dictionary in receipts:
		for choice: Dictionary in receipt["choices"]:
			if not by_id.has(choice["hero_id"]):
				return _reject(&"promotion_hero_missing")
			if class_cursor[choice["hero_id"]] != choice["from_class_id"]:
				return _reject(&"promotion_receipt_chain_mismatch")
			class_cursor[choice["hero_id"]] = choice["to_class_id"]
	for hero_id: String in class_cursor:
		if by_id[hero_id]["current_class_id"] != class_cursor[hero_id]:
			return _reject(&"promotion_projection_mismatch")
	var memorial_by_id := {}
	for row: Dictionary in memorial:
		memorial_by_id[row["hero_id"]] = row
	for hero: Dictionary in heroes:
		if hero["life_status"] == "dead":
			if not memorial_by_id.has(hero["hero_id"]):
				return _reject(&"missing_memorial")
			var row: Dictionary = memorial_by_id[hero["hero_id"]]
			for key: String in ["portrait_instance_id", "portrait_asset_id"]:
				if row[key] != hero[key]:
					return _reject(&"memorial_identity_mismatch")
			if row["class_id"] != hero["current_class_id"] or row["death"] != hero["death"]:
				return _reject(&"memorial_identity_mismatch")
		elif memorial_by_id.has(hero["hero_id"]):
				return _reject(&"memorial_life_mismatch")
	for ticket: Dictionary in tickets:
		var unresolved: bool = ticket["attempt_id"] == next_resolution_index
		for squad: Dictionary in ticket["squad"]:
			if not by_id.has(squad["hero_id"]):
				return _reject(&"ticket_hero_missing")
			var hero: Dictionary = by_id[squad["hero_id"]]
			var class_row: Dictionary = context["class_by_id"].get(squad["class_id"], {})
			if (
				class_row.is_empty()
				or squad["operator_def_id"] != class_row["operator_def_id"]
				or squad["visual_spec"]["portrait_asset_id"] != hero["portrait_asset_id"]
				or (
					unresolved
					and (
						hero["life_status"] != "ready"
						or squad["class_id"] != hero["current_class_id"]
						or squad["operator_def_id"] != hero["operator_def_id"]
					)
				)
			):
				return _reject(&"ticket_snapshot_mismatch")
			var expected: Dictionary = context["operator_ticket_by_id"].get(
				squad["operator_def_id"], {},
			).duplicate(true)
			if expected.is_empty():
				return _reject(&"ticket_snapshot_mismatch")
			expected["visual_spec"]["portrait_asset_id"] = hero["portrait_asset_id"]
			for key: String in [
				"operator_content_sha256", "combat_spec", "target_policy_spec",
				"skill_spec", "visual_spec",
			]:
				if squad[key] != expected[key]:
					return _reject(&"ticket_snapshot_mismatch")
	return _accept(null)


static func _normalize_death(value: Variant) -> Dictionary:
	if value == null:
		return _accept(null)
	if typeof(value) != TYPE_DICTIONARY or value.keys() != DEATH_KEYS:
		return _reject(&"invalid_death")
	for key: String in ["resolution_index", "attempt_id"]:
		if not _in_range(value[key], 1, U63_MAX):
			return _reject(&"invalid_death")
	if not _in_range(value["terminal_tick"], 0, U63_MAX):
		return _reject(&"invalid_death")
	if not _ascii(String(value["stage_id"])):
		return _reject(&"invalid_death")
	if String(value["terminal_reason"]) not in TERMINAL_VALUES:
		return _reject(&"invalid_death")
	var ordered := {}
	for key: String in DEATH_KEYS:
		ordered[key] = value[key]
	return _accept(ordered)


static func _validate_unresolved_ticket_issuance(
	core: Dictionary,
	context: Dictionary,
) -> Dictionary:
	if core["next_attempt_id"] == core["next_resolution_index"]:
		return _accept(null)
	var tickets: Array = core["tickets"]
	if tickets.is_empty():
		return _reject(&"ticket_issuance_mismatch")
	var ticket: Dictionary = tickets[-1]
	if (
		ticket["attempt_id"] != core["next_resolution_index"]
		or ticket["expected_save_revision"] != core["save_revision"]
		or not (context["stage_order"] as Array).has(ticket["stage_id"])
	):
		return _reject(&"ticket_issuance_mismatch")
	var pre_attempt: Dictionary = core.duplicate(true)
	pre_attempt["tickets"] = tickets.slice(0, tickets.size() - 1)
	pre_attempt["next_attempt_id"] = int(core["next_attempt_id"]) - 1
	var expected_hash: Dictionary = load(HASH_PATH).call("_of_normalized_core", pre_attempt)
	if ticket["strategic_hash"] != expected_hash["hex"]:
		return _reject(&"ticket_issuance_mismatch")
	return _accept(null)


static func _legal_edge(from_id: String, to_id: String, context: Dictionary) -> bool:
	return (
		context["class_by_id"].has(from_id)
		and context["class_by_id"].has(to_id)
		and (context["class_by_id"][from_id]["promotion_to_class_ids"] as Array).has(to_id)
	)


static func _in_range(value: Variant, minimum: int, maximum: int) -> bool:
	return typeof(value) == TYPE_INT and int(value) >= minimum and int(value) <= maximum


static func _ascii(value: String, allow_empty: bool = false) -> bool:
	if value.is_empty():
		return allow_empty
	for character: String in value:
		if character.unicode_at(0) > 127:
			return false
	return true


static func _is_hex(value: String, length: int) -> bool:
	if value.length() != length:
		return false
	for character: String in value:
		if character not in "0123456789abcdef":
			return false
	return true


static func _accept(value: Variant) -> Dictionary:
	return {"accepted": true, "error_code": &"", "value": value}


static func _reject(error_code: StringName) -> Dictionary:
	return {"accepted": false, "error_code": error_code}
