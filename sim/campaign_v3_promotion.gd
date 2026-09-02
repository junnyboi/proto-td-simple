class_name CampaignV3Promotion
extends RefCounted

const CommandsScript := preload("res://sim/campaign_v3_commands.gd")
const PromotionRulesScript := preload("res://sim/campaign_v3_promotion_rules.gd")
const CommandCodecScript := preload("res://sim/campaign_v3_command_codec.gd")


static func options(data: Dictionary, context: Dictionary, hero_id_value: Variant) -> Dictionary:
	if typeof(hero_id_value) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return _options_reject(&"malformed_hero_id")
	var hero_id := String(hero_id_value)
	var hero := _hero_by_id(data["heroes"], hero_id)
	if hero.is_empty():
		return _options_reject(&"unknown_hero")
	if hero["life_status"] != "ready":
		return _options_reject(&"dead_hero")
	var current: Dictionary = context["class_by_id"].get(hero["current_class_id"], {})
	if current.is_empty():
		return _options_reject(&"missing_catalog")
	var targets: Array = current["promotion_to_class_ids"]
	if targets.is_empty():
		return _options_reject(&"already_promoted_class")
	if int(hero["xp"]) < int(current["promotion_xp_required"]):
		return _options_reject(&"insufficient_xp")
	var choices: Array[Dictionary] = []
	var locked := false
	for target_id: String in targets:
		var target: Dictionary = context["class_by_id"].get(target_id, {})
		if (
			target.is_empty()
			or not context["operator_ticket_by_id"].has(target.get("operator_def_id", ""))
		):
			return _options_reject(&"missing_catalog")
		var entitlement := String(target["entitlement_id"])
		if (
			not entitlement.is_empty()
			and not (data["class_entitlements"] as Array).has(entitlement)
		):
			locked = true
			continue
		(
			choices
			. append(
				{
					"from_class_id": String(hero["current_class_id"]),
					"to_class_id": target_id,
					"operator_def_id": String(target["operator_def_id"]),
					"xp_required": int(current["promotion_xp_required"]),
				}
			)
		)
	if choices.is_empty():
		return _options_reject(&"locked_class" if locked else &"illegal_class_edge")
	choices.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return String(a["to_class_id"]) < String(b["to_class_id"])
	)
	return {"accepted": true, "error_code": &"", "choices": choices}


static func confirm(
	state: Variant,
	command_id: Variant,
	expected_revision: Variant,
	choices_value: Variant,
) -> Dictionary:
	var prepared := (
		CommandsScript
		. prepare(
			state,
			command_id,
			expected_revision,
			"confirm_promotions",
			{
				"choices": choices_value,
			},
		)
	)
	if not prepared["accepted"]:
		return prepared
	if prepared["duplicate"]:
		return prepared["result"]
	if int(state._data["next_attempt_id"]) != int(state._data["next_resolution_index"]):
		return CommandsScript.rejected(&"attempt_pending")
	var payload: Dictionary = prepared["payload"]
	var validated: Array[Dictionary] = []
	for choice: Dictionary in payload["choices"]:
		var result := PromotionRulesScript.validate_choice(
			state._data, state._context_ref(), choice,
		)
		if not result["accepted"]:
			return CommandsScript.rejected(result["error_code"])
		validated.append(result["value"])
	var working: Dictionary = state._data.duplicate(true)
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
	working["save_revision"] = state.save_revision() + 1
	var promotion_receipt := {
		"command_id": prepared["command_id"],
		"save_revision": working["save_revision"],
		"choices": receipt_choices,
	}
	working["promotion_receipts"] = (working["promotion_receipts"] as Array).duplicate(true)
	working["promotion_receipts"].append(promotion_receipt)
	var record := (
		CommandCodecScript
		. record(
			prepared["command_id"],
			"confirm_promotions",
			prepared["expected_save_revision"],
			payload,
			{"promotion": promotion_receipt},
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
			"confirm_promotions",
			prospective["value"],
			record,
			[
				_event(
					&"promotions_confirmed",
					{
						"command_id": prepared["command_id"],
						"hero_ids": _choice_hero_ids(validated),
						"save_revision": working["save_revision"],
					}
				)
			],
			{"promotion": promotion_receipt.duplicate(true)},
		)
	)


static func _hero_by_id(heroes: Array, hero_id: String) -> Dictionary:
	for hero: Dictionary in heroes:
		if hero["hero_id"] == hero_id:
			return hero
	return {}


static func _choice_hero_ids(choices: Array) -> Array[String]:
	var result: Array[String] = []
	for choice: Dictionary in choices:
		result.append(String(choice["hero_id"]))
	return result


static func _event(name: StringName, data: Dictionary) -> Dictionary:
	return {"name": name, "data": data}


static func _options_reject(code: StringName) -> Dictionary:
	return {"accepted": false, "error_code": code, "choices": []}


static func _accept(value: Variant) -> Dictionary:
	return {"accepted": true, "error_code": &"", "value": value}


static func _reject(code: StringName) -> Dictionary:
	return {"accepted": false, "error_code": code}
