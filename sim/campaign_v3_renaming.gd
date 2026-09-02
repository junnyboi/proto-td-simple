class_name CampaignV3Renaming
extends RefCounted

const CommandsScript := preload("res://sim/campaign_v3_commands.gd")
const CommandCodecScript := preload("res://sim/campaign_v3_command_codec.gd")
const HeroCodecScript := preload("res://sim/campaign_hero_codec.gd")


static func execute(
	state: Variant,
	command_id: Variant,
	expected_revision: Variant,
	hero_id_value: Variant,
	callsign_value: Variant,
	title_value: Variant = null,
) -> Dictionary:
	var prepared := (
		CommandsScript
		. prepare(
			state,
			command_id,
			expected_revision,
			"rename_hero",
			{"hero_id": hero_id_value, "callsign": callsign_value, "title": title_value},
		)
	)
	if not prepared["accepted"]:
		return prepared
	if prepared["duplicate"]:
		return prepared["result"]
	var derived := _derive(state._data, prepared["payload"])
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
			"rename_hero",
			prepared["expected_save_revision"],
			prepared["payload"],
			{"rename": receipt},
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
			"rename_hero",
			prospective["value"],
			record,
			[
				{
					"name": &"hero_renamed",
					"data":
					{
						"hero_id": receipt["hero_id"],
						"old_callsign": receipt["old_callsign"],
						"new_callsign": receipt["new_callsign"],
						"old_title": receipt.get("old_title"),
						"new_title": receipt.get("new_title"),
						"save_revision": receipt["save_revision"],
					},
				},
			],
			{"rename": receipt.duplicate(true)},
		)
	)


static func title_for(data: Dictionary, hero_id: String) -> Variant:
	var title: Variant = null
	for record: Dictionary in data.get("command_receipts", []):
		if record.get("verb") != "rename_hero":
			continue
		var payload: Dictionary = record.get("payload", {})
		if String(payload.get("hero_id", "")) != hero_id or not payload.has("title"):
			continue
		var receipt: Dictionary = record.get("receipt", {}).get("rename", {})
		if receipt.has("new_title"):
			title = receipt["new_title"]
	return title


static func _derive(data: Dictionary, payload: Dictionary) -> Dictionary:
	if int(data["next_attempt_id"]) != int(data["next_resolution_index"]):
		return _reject(&"attempt_pending")
	var hero_id := String(payload["hero_id"])
	var callsign := String(payload["callsign"])
	var title: Variant = payload.get("title", null)
	var target_index := -1
	for index: int in (data["heroes"] as Array).size():
		if data["heroes"][index]["hero_id"] == hero_id:
			target_index = index
			break
	if target_index < 0:
		return _reject(&"unknown_hero")
	var target: Dictionary = data["heroes"][target_index]
	if target["life_status"] != "ready":
		return _reject(&"hero_not_ready")
	if not HeroCodecScript.valid_callsign(callsign):
		return _reject(&"invalid_callsign")
	if not HeroCodecScript.valid_title(title):
		return _reject(&"invalid_title")
	var previous := HeroCodecScript.display_callsign(target)
	if not previous["accepted"]:
		return _reject(&"invalid_campaign_state")
	var previous_title: Variant = title_for(data, hero_id)
	if String(previous["value"]) == callsign and previous_title == title:
		return _reject(&"identity_unchanged" if payload.has("title") else &"callsign_unchanged")
	var folded := callsign.to_lower()
	for hero: Dictionary in data["heroes"]:
		if hero["hero_id"] == hero_id:
			continue
		var display := HeroCodecScript.display_callsign(hero)
		if not display["accepted"]:
			return _reject(&"invalid_campaign_state")
		if String(display["value"]).to_lower() == folded:
			return _reject(&"duplicate_callsign")
	var working: Dictionary = data.duplicate(true)
	working["heroes"] = (data["heroes"] as Array).duplicate(true)
	var changed: Dictionary = working["heroes"][target_index].duplicate(true)
	changed["custom_callsign"] = callsign
	working["heroes"][target_index] = changed
	var receipt := {
		"hero_id": hero_id,
		"old_callsign": String(previous["value"]),
		"new_callsign": callsign,
		"save_revision": 0,
	}
	if payload.has("title"):
		receipt = {
			"hero_id": hero_id,
			"old_callsign": String(previous["value"]),
			"new_callsign": callsign,
			"old_title": previous_title,
			"new_title": title,
			"save_revision": 0,
		}
	return {
		"accepted": true,
		"error_code": &"",
		"data": working,
		"receipt": receipt,
	}


static func _reject(code: StringName) -> Dictionary:
	return {"accepted": false, "error_code": code}
