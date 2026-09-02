class_name CampaignV3CommandCodec
extends RefCounted

## Canonical persisted command receipts for CampaignSave v3. Records live outside
## the strategic core to avoid self-referential resolution hashes, but remain in
## the full save checksum/hash and carry complete canonical payloads and results.

const U63_MAX := 9_223_372_036_854_775_807
const RECORD_KEYS := [
	"command_id",
	"verb",
	"expected_save_revision",
	"save_revision",
	"payload",
	"receipt",
]
const CHOICE_KEYS := ["hero_id", "to_class_id"]
const VERBS := [
	"begin_attempt", "resolve_attempt", "confirm_promotions", "recruit_person",
	"rename_hero", "honor_fallen",
]
const HISTORY_PATH := "res://sim/campaign_v3_history.gd"
const STATE_CODEC_PATH := "res://sim/campaign_v3_state_codec.gd"
const BattleOutcomeScript := preload("res://sim/battle_outcome_v3.gd")
const CanonicalJsonScript := preload("res://sim/canonical_json.gd")
const BattleTicketScript := preload("res://sim/battle_ticket.gd")
const HeroCodecScript := preload("res://sim/campaign_hero_codec.gd")


static func normalize_records(
	value: Variant,
	data: Dictionary,
	context: Dictionary,
) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return _reject(&"invalid_command_receipts")
	var records: Array[Dictionary] = []
	var ids := {}
	var previous_revision := 0
	for raw: Variant in value:
		if typeof(raw) != TYPE_DICTIONARY or raw.keys() != RECORD_KEYS:
			return _reject(&"invalid_command_receipt")
		var command_id := String(raw["command_id"])
		var verb := String(raw["verb"])
		if (
			not _ascii(command_id)
			or command_id.length() > 160
			or verb not in VERBS
			or ids.has(command_id)
			or not _in_range(raw["expected_save_revision"], 1, U63_MAX - 1)
			or not _in_range(raw["save_revision"], 2, U63_MAX)
			or int(raw["save_revision"]) != int(raw["expected_save_revision"]) + 1
			or int(raw["save_revision"]) <= previous_revision
		):
			return _reject(&"invalid_command_receipt")
		var payload := normalize_payload(verb, raw["payload"], data)
		if not payload["accepted"]:
			return payload
		var receipt := _normalize_receipt(
			verb,
			raw["receipt"],
			command_id,
			int(raw["save_revision"]),
			payload["value"],
			data,
			context,
		)
		if not receipt["accepted"]:
			return receipt
		ids[command_id] = true
		previous_revision = int(raw["save_revision"])
		(
			records
			. append(
				{
					"command_id": command_id,
					"verb": verb,
					"expected_save_revision": int(raw["expected_save_revision"]),
					"save_revision": int(raw["save_revision"]),
					"payload": payload["value"],
					"receipt": receipt["value"],
				}
			)
		)
	if not records.is_empty() and records[-1]["save_revision"] > data["save_revision"]:
		return _reject(&"command_receipt_ahead")
	return _accept(records)


static func normalize_payload(verb: String, value: Variant, data: Dictionary) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return _reject(&"invalid_command_payload")
	match verb:
		"begin_attempt":
			if value.keys() != ["stage_id", "hero_ids", "seed"]:
				return _reject(&"invalid_command_payload")
			if not _ascii(String(value["stage_id"])) or not _signed_63(value["seed"]):
				return _reject(&"invalid_command_payload")
			var hero_ids := _hero_ids(value["hero_ids"], false)
			if not hero_ids["accepted"]:
				return hero_ids
			return _accept(
				{
					"stage_id": String(value["stage_id"]),
					"hero_ids": hero_ids["value"],
					"seed": int(value["seed"]),
				}
			)
		"resolve_attempt":
			if value.keys() != ["attempt_id", "outcome"]:
				return _reject(&"invalid_command_payload")
			if not _in_range(value["attempt_id"], 1, U63_MAX):
				return _reject(&"invalid_command_payload")
			var ticket := _ticket_by_attempt(data.get("tickets", []), int(value["attempt_id"]))
			if ticket.is_empty():
				return _reject(&"missing_resolution_ticket")
			var outcome := BattleOutcomeScript.normalize(value["outcome"], ticket)
			if not outcome["accepted"]:
				return outcome
			return _accept(
				{
					"attempt_id": int(value["attempt_id"]),
					"outcome": outcome["value"],
				}
			)
		"confirm_promotions":
			if value.keys() != ["choices"]:
				return _reject(&"invalid_command_payload")
			var choices := normalize_choices(value["choices"])
			return _accept({"choices": choices["value"]}) if choices["accepted"] else choices
		"recruit_person":
			if value.keys() != ["source", "source_id"]:
				return _reject(&"invalid_command_payload")
			var source := String(value["source"])
			var source_id := String(value["source_id"])
			if (
				typeof(value["source"]) not in [TYPE_STRING, TYPE_STRING_NAME]
				or typeof(value["source_id"]) not in [TYPE_STRING, TYPE_STRING_NAME]
				or source not in [
					"basic_hire", "contract", "recovery", "replacement", "reward",
				]
				or not _ascii(source_id)
			):
				return _reject(&"invalid_command_payload")
			return _accept({"source": source, "source_id": source_id})
		"rename_hero":
			var extended: bool = value.keys() == ["hero_id", "callsign", "title"]
			if not extended and value.keys() != ["hero_id", "callsign"]:
				return _reject(&"invalid_command_payload")
			if (
				typeof(value["hero_id"]) not in [TYPE_STRING, TYPE_STRING_NAME]
				or typeof(value["callsign"]) != TYPE_STRING
			):
				return _reject(&"invalid_command_payload")
			var hero_id := String(value["hero_id"])
			var callsign := _trim_callsign(String(value["callsign"]))
			if not _is_hex(hero_id, 16) or not HeroCodecScript.valid_callsign(callsign):
				return _reject(&"invalid_callsign")
			if not extended:
				return _accept({"hero_id": hero_id, "callsign": callsign})
			var title: Variant = value["title"]
			if title != null:
				if typeof(title) != TYPE_STRING:
					return _reject(&"invalid_command_payload")
				title = _trim_callsign(String(title))
				if String(title).is_empty():
					title = null
			if not HeroCodecScript.valid_title(title):
				return _reject(&"invalid_title")
			return _accept({"hero_id": hero_id, "callsign": callsign, "title": title})
		"honor_fallen":
			if value.keys() != ["hero_id"]:
				return _reject(&"invalid_command_payload")
			if typeof(value["hero_id"]) not in [TYPE_STRING, TYPE_STRING_NAME]:
				return _reject(&"invalid_command_payload")
			var hero_id := String(value["hero_id"])
			if not _is_hex(hero_id, 16):
				return _reject(&"invalid_command_payload")
			return _accept({"hero_id": hero_id})
	return _reject(&"invalid_command_payload")


static func normalize_choices(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_ARRAY or (value as Array).is_empty():
		return _reject(&"invalid_promotion_choices")
	var rows: Array[Dictionary] = []
	var seen := {}
	for raw: Variant in value:
		if typeof(raw) != TYPE_DICTIONARY or raw.keys() != CHOICE_KEYS:
			return _reject(&"invalid_promotion_choice")
		var hero_id := String(raw["hero_id"])
		var to_class_id := String(raw["to_class_id"])
		if not _is_hex(hero_id, 16) or not _ascii_id(to_class_id):
			return _reject(&"invalid_promotion_choice")
		if seen.has(hero_id):
			return _reject(&"duplicate_hero_choice")
		seen[hero_id] = true
		rows.append({"hero_id": hero_id, "to_class_id": to_class_id})
	rows.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return String(a["hero_id"]) < String(b["hero_id"])
	)
	return _accept(rows)


static func record(
	command_id: String,
	verb: String,
	expected_save_revision: int,
	payload: Dictionary,
	receipt: Dictionary,
) -> Dictionary:
	return {
		"command_id": command_id,
		"verb": verb,
		"expected_save_revision": expected_save_revision,
		"save_revision": expected_save_revision + 1,
		"payload": payload.duplicate(true),
		"receipt": receipt.duplicate(true),
	}


static func by_id(records: Array, command_id: String) -> Dictionary:
	for record_row: Dictionary in records:
		if record_row["command_id"] == command_id:
			return record_row.duplicate(true)
	return {}


static func canonical_bytes(record_row: Dictionary) -> PackedByteArray:
	return CanonicalJsonScript.text(record_row).to_utf8_buffer()


static func _normalize_receipt(
	verb: String,
	value: Variant,
	command_id: String,
	save_revision: int,
	payload: Dictionary,
	data: Dictionary,
	context: Dictionary,
) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return _reject(&"invalid_command_receipt")
	match verb:
		"begin_attempt":
			if value.keys() != ["ticket"]:
				return _reject(&"invalid_command_receipt")
			var ticket := BattleTicketScript.normalize(value["ticket"])
			if not ticket["accepted"]:
				return ticket
			var normalized: Dictionary = ticket["value"]
			var squad_ids: Array[String] = []
			for row: Dictionary in normalized["squad"]:
				squad_ids.append(String(row["hero_id"]))
			if (
				normalized["stage_id"] != payload["stage_id"]
				or normalized["seed"] != payload["seed"]
				or normalized["expected_save_revision"] != save_revision
				or squad_ids != payload["hero_ids"]
				or not (data["tickets"] as Array).has(normalized)
			):
				return _reject(&"command_receipt_mismatch")
			return _accept({"ticket": normalized})
		"resolve_attempt":
			if value.keys() != ["resolution"]:
				return _reject(&"invalid_command_receipt")
			var resolution: Dictionary = load(HISTORY_PATH).call(
				"_normalize_receipt", value["resolution"],
			)
			if not resolution["accepted"]:
				return resolution
			var normalized: Dictionary = resolution["value"]
			var outcome: Dictionary = payload["outcome"]
			if (
				normalized["attempt_id"] != payload["attempt_id"]
				or normalized["ticket_hash"] != outcome["ticket_hash"]
				or normalized["outcome_hash"] != outcome["outcome_hash"]
				or normalized["result"] != outcome["result"]
				or normalized["terminal_reason"] != outcome["terminal_reason"]
				or normalized["terminal_tick"] != outcome["terminal_tick"]
			):
				return _reject(&"command_receipt_mismatch")
			return _accept({"resolution": normalized})
		"confirm_promotions":
			if value.keys() != ["promotion"]:
				return _reject(&"invalid_command_receipt")
			var promotions: Dictionary = (
				load(STATE_CODEC_PATH)
				. call(
					"_normalize_receipts", [value["promotion"]], context,
				)
			)
			if not promotions["accepted"]:
				return promotions
			var normalized: Dictionary = promotions["value"][0]
			var receipt_choices: Array[Dictionary] = []
			for choice: Dictionary in normalized["choices"]:
				(
					receipt_choices
					. append(
						{
							"hero_id": choice["hero_id"],
							"to_class_id": choice["to_class_id"],
						}
					)
				)
			if (
				normalized["command_id"] != command_id
				or normalized["save_revision"] != save_revision
				or receipt_choices != payload["choices"]
				or not (data["promotion_receipts"] as Array).has(normalized)
			):
				return _reject(&"command_receipt_mismatch")
			return _accept({"promotion": normalized})
		"recruit_person":
			if value.keys() != ["recruitment"]:
				return _reject(&"invalid_command_receipt")
			var recruitment: Variant = value["recruitment"]
			if (
				typeof(recruitment) != TYPE_DICTIONARY
				or recruitment.keys()
				!= ["hero", "marks_before", "marks_after", "save_revision"]
				or typeof(recruitment["hero"]) != TYPE_DICTIONARY
				or recruitment["save_revision"] != save_revision
			):
				return _reject(&"invalid_command_receipt")
			var hero: Dictionary = recruitment["hero"]
			var persisted := _hero_by_id(data["heroes"], String(hero.get("hero_id", "")))
			var expected_cost := _recruitment_cost(payload, data, context)
			if (
				persisted.is_empty()
				or not _same_acquisition_identity(persisted, hero)
				or hero.get("recruit_source") != payload["source"]
				or hero.get("source_id") != payload["source_id"]
				or not _is_fresh_recruit(hero)
				or typeof(recruitment["marks_before"]) != TYPE_INT
				or typeof(recruitment["marks_after"]) != TYPE_INT
				or expected_cost < 0
				or int(recruitment["marks_before"]) - int(recruitment["marks_after"])
					!= expected_cost
				):
				return _reject(&"command_receipt_mismatch")
			return _accept({"recruitment": recruitment.duplicate(true)})
		"rename_hero":
			if value.keys() != ["rename"]:
				return _reject(&"invalid_command_receipt")
			var rename: Variant = value["rename"]
			if typeof(rename) != TYPE_DICTIONARY:
				return _reject(&"invalid_command_receipt")
			var extended: bool = rename.keys() == [
				"hero_id", "old_callsign", "new_callsign", "old_title", "new_title",
				"save_revision",
			]
			if (
				not extended
				and rename.keys()
				!= ["hero_id", "old_callsign", "new_callsign", "save_revision"]
			):
				return _reject(&"invalid_command_receipt")
			if (
				payload.has("title") != extended
				or typeof(rename["old_callsign"]) != TYPE_STRING
				or typeof(rename["new_callsign"]) != TYPE_STRING
				or rename["hero_id"] != payload["hero_id"]
				or rename["new_callsign"] != payload["callsign"]
				or rename["save_revision"] != save_revision
				or not HeroCodecScript.valid_callsign(rename["old_callsign"])
				or not HeroCodecScript.valid_callsign(rename["new_callsign"])
			):
				return _reject(&"invalid_command_receipt")
			if extended and (
				rename["new_title"] != payload["title"]
				or not HeroCodecScript.valid_title(rename["old_title"])
				or not HeroCodecScript.valid_title(rename["new_title"])
			):
				return _reject(&"invalid_command_receipt")
			return _accept({"rename": rename.duplicate(true)})
		"honor_fallen":
			if value.keys() != ["honor"] or typeof(value["honor"]) != TYPE_DICTIONARY:
				return _reject(&"invalid_command_receipt")
			var honor: Dictionary = value["honor"]
			if honor.keys() != ["hero_id", "marks_before", "marks_after", "save_revision"]:
				return _reject(&"invalid_command_receipt")
			var persisted := _hero_by_id(data["heroes"], String(honor["hero_id"]))
			if (
				typeof(honor["hero_id"]) not in [TYPE_STRING, TYPE_STRING_NAME]
				or typeof(honor["marks_before"]) != TYPE_INT
				or typeof(honor["marks_after"]) != TYPE_INT
				or typeof(honor["save_revision"]) != TYPE_INT
				or honor["hero_id"] != payload["hero_id"]
				or honor["save_revision"] != save_revision
				or not _in_range(honor["marks_before"], 0, 1_000_000_000 - 5)
				or int(honor["marks_after"]) != int(honor["marks_before"]) + 5
				or persisted.is_empty()
				or persisted.get("life_status") != "dead"
			):
				return _reject(&"command_receipt_mismatch")
			return _accept({"honor": honor.duplicate(true)})
	return _reject(&"invalid_command_receipt")


static func _hero_ids(value: Variant, permit_empty: bool) -> Dictionary:
	if typeof(value) != TYPE_ARRAY or ((value as Array).is_empty() and not permit_empty):
		return _reject(&"invalid_command_payload")
	var result: Array[String] = []
	for raw: Variant in value:
		if typeof(raw) not in [TYPE_STRING, TYPE_STRING_NAME]:
			return _reject(&"invalid_command_payload")
		var hero_id := String(raw)
		if not _is_hex(hero_id, 16) or result.has(hero_id):
			return _reject(&"invalid_command_payload")
		result.append(hero_id)
	return _accept(result)


static func _ticket_by_attempt(tickets: Array, attempt_id: int) -> Dictionary:
	for ticket: Dictionary in tickets:
		if ticket["attempt_id"] == attempt_id:
			return ticket
	return {}


static func _recruitment_cost(
	payload: Dictionary,
	data: Dictionary,
	context: Dictionary,
) -> int:
	match String(payload["source"]):
		"basic_hire":
			return int(context["campaign"]["basic_recruit_cost"])
		"contract":
			for offer: Dictionary in data["offers"]:
				if offer["offer_id"] == payload["source_id"]:
					return int(offer["cost"])
		"recovery", "replacement":
			return 0
	return -1


static func _hero_by_id(heroes: Array, hero_id: String) -> Dictionary:
	for hero: Dictionary in heroes:
		if hero["hero_id"] == hero_id:
			return hero
	return {}


static func _same_acquisition_identity(current: Dictionary, recruited: Dictionary) -> bool:
	for key: String in [
		"hero_id", "acquisition_operator_def_id", "progression_rules_version",
		"identity_portrait_id", "portrait_instance_id", "portrait_asset_id",
		"recruitment_index", "recruited_after_resolution_index", "recruit_source",
		"source_id", "name_version", "custom_callsign",
	]:
		if current.get(key) != recruited.get(key):
			return false
	return true


static func _is_fresh_recruit(hero: Dictionary) -> bool:
	return (
		hero.get("acquisition_operator_def_id") == "recruit"
		and hero.get("operator_def_id") == "recruit"
		and hero.get("current_class_id") == "recruit"
		and hero.get("first_class_id") == "recruit"
		and hero.get("advanced_class_id") == null
		and hero.get("xp") == 0
		and hero.get("life_status") == "ready"
		and hero.get("death") == null
	)


static func _signed_63(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and int(value) >= -U63_MAX - 1 and int(value) <= U63_MAX


static func _in_range(value: Variant, minimum: int, maximum: int) -> bool:
	return typeof(value) == TYPE_INT and int(value) >= minimum and int(value) <= maximum


static func _trim_callsign(value: String) -> String:
	var first := 0
	var last := value.length()
	while first < last and value.substr(first, 1) in [" ", "\t"]:
		first += 1
	while last > first and value.substr(last - 1, 1) in [" ", "\t"]:
		last -= 1
	return value.substr(first, last - first)


static func _ascii(value: String) -> bool:
	if value.is_empty():
		return false
	for character: String in value:
		if character.unicode_at(0) > 127:
			return false
	return true


static func _ascii_id(value: String) -> bool:
	if value.is_empty():
		return false
	for character: String in value:
		if character not in "abcdefghijklmnopqrstuvwxyz0123456789_-":
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
