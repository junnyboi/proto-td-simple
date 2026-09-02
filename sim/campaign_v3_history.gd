class_name CampaignV3History
extends RefCounted

## Canonical last-resolution history for rules-v2 CampaignSave. It validates
## the frozen before/after cores, recomputes both body hashes, and proves that
## the receipt describes the only permitted transition between those cores.

const U63_MAX := 9_223_372_036_854_775_807
const MARKS_MAX := 1_000_000_000
const RESULT_VALUES := ["clear", "defeat"]
const TERMINAL_VALUES := ["clear", "leak_defeat", "base_defeat", "resign"]
const ANCHOR_KEYS := [
	"resolution_index", "save_revision_after", "before_core", "after_core",
	"strategic_body_hash_before", "strategic_body_hash_after",
]
const RECEIPT_KEYS := [
	"schema_version", "resolution_index", "campaign_uid", "attempt_id", "stage_id",
	"ticket_hash", "outcome_hash", "result", "terminal_reason", "terminal_tick",
	"stars_before", "stars_after", "rewards_granted", "class_entitlements_granted",
	"created_hero_ids", "dead_hero_ids", "xp_awards",
	"memorial_ids", "marks_before",
	"marks_after", "strategic_body_hash_before", "strategic_body_hash_after",
]
const CONTENT_REWARD_KEYS := ["id", "kind"]
const CURRENCY_REWARD_KEYS := ["amount", "id", "kind"]
const XP_KEYS := ["hero_id", "delta"]
const STATE_CODEC_PATH := "res://sim/campaign_v3_state_codec.gd"
const HashScript := preload("res://sim/campaign_v3_hash.gd")
const PromotionRulesScript := preload("res://sim/campaign_v3_promotion_rules.gd")
const EconomyScript := preload("res://sim/campaign_v3_economy.gd")


static func normalize(
	anchor_value: Variant,
	receipt_value: Variant,
	current_core: Dictionary,
	context: Dictionary,
	core_keys: Array,
	hero_keys: Array,
) -> Dictionary:
	if anchor_value == null and receipt_value == null:
		if current_core["next_resolution_index"] != 1:
			return _reject(&"resolution_counter_mismatch")
		var pristine := _validate_preresolution_core(current_core)
		if not pristine["accepted"]:
			return pristine
		return _accept({"anchor": null, "receipt": null})
	if (anchor_value == null) != (receipt_value == null):
		return _reject(&"resolution_history_mismatch")
	var anchor := _normalize_anchor(anchor_value, context, core_keys, hero_keys)
	var receipt := _normalize_receipt(receipt_value)
	if not anchor["accepted"]:
		return anchor
	if not receipt["accepted"]:
		return receipt
	var closed := _validate_closure(anchor["value"], receipt["value"], current_core, context)
	if not closed["accepted"]:
		return closed
	return _accept({"anchor": anchor["value"], "receipt": receipt["value"]})


static func _normalize_anchor(
	value: Variant,
	context: Dictionary,
	core_keys: Array,
	hero_keys: Array,
) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY or value.keys() != ANCHOR_KEYS:
		return _reject(&"invalid_resolution_anchor")
	if not _in_range(value["resolution_index"], 1, U63_MAX):
		return _reject(&"invalid_resolution_anchor")
	if not _in_range(value["save_revision_after"], 2, U63_MAX):
		return _reject(&"invalid_resolution_anchor")
	var before: Dictionary = load(STATE_CODEC_PATH).call(
		"normalize_core", value["before_core"], context, core_keys, hero_keys,
	)
	var after: Dictionary = load(STATE_CODEC_PATH).call(
		"normalize_core", value["after_core"], context, core_keys, hero_keys,
	)
	if not before["accepted"] or not after["accepted"]:
		return _reject(&"invalid_resolution_anchor")
	var before_hash: Dictionary = HashScript.of_core(before["value"], context)
	var after_hash: Dictionary = HashScript.of_core(after["value"], context)
	if not before_hash["accepted"] or not after_hash["accepted"]:
		return _reject(&"resolution_anchor_hash_mismatch")
	if (
		value["strategic_body_hash_before"] != before_hash["hex"]
		or value["strategic_body_hash_after"] != after_hash["hex"]
	):
		return _reject(&"resolution_anchor_hash_mismatch")
	return _accept({
		"resolution_index": int(value["resolution_index"]),
		"save_revision_after": int(value["save_revision_after"]),
		"before_core": before["value"],
		"after_core": after["value"],
		"strategic_body_hash_before": before_hash["hex"],
		"strategic_body_hash_after": after_hash["hex"],
	})


static func _normalize_receipt(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY or value.keys() != RECEIPT_KEYS:
		return _reject(&"invalid_last_resolution")
	for key: String in [
		"schema_version", "resolution_index", "attempt_id", "terminal_tick", "stars_before",
		"stars_after", "marks_before", "marks_after",
	]:
		if not _in_range(value[key], 0, U63_MAX):
			return _reject(&"invalid_last_resolution")
	if value["schema_version"] != 1:
		return _reject(&"invalid_last_resolution")
	if value["resolution_index"] < 1 or value["attempt_id"] < 1:
		return _reject(&"invalid_last_resolution")
	if not _is_hex(String(value["campaign_uid"]), 16):
		return _reject(&"invalid_last_resolution")
	if not _ascii(String(value["stage_id"])):
		return _reject(&"invalid_last_resolution")
	for key: String in ["ticket_hash", "outcome_hash"]:
		if not _is_hex(String(value[key]), 64):
			return _reject(&"invalid_last_resolution")
	for key: String in ["strategic_body_hash_before", "strategic_body_hash_after"]:
		if not _is_hex(String(value[key]), 16):
			return _reject(&"invalid_last_resolution")
	if String(value["result"]) not in RESULT_VALUES:
		return _reject(&"invalid_last_resolution")
	if String(value["terminal_reason"]) not in TERMINAL_VALUES:
		return _reject(&"invalid_last_resolution")
	if value["stars_before"] > 3 or value["stars_after"] > 3:
		return _reject(&"invalid_last_resolution")
	if value["marks_before"] > MARKS_MAX or value["marks_after"] > MARKS_MAX:
		return _reject(&"invalid_last_resolution")
	var cleared := String(value["result"]) == "clear"
	if cleared != (String(value["terminal_reason"]) == "clear"):
		return _reject(&"invalid_resolution_terminal")
	if cleared and (
		value["stars_after"] < 1 or value["stars_after"] < value["stars_before"]
	):
		return _reject(&"invalid_resolution_terminal")
	if not cleared and value["stars_after"] != value["stars_before"]:
		return _reject(&"invalid_resolution_terminal")
	var rewards := _normalize_rewards(value["rewards_granted"])
	var entitlements := _normalize_strings(
		value["class_entitlements_granted"], false, false,
	)
	var created := _normalize_strings(value["created_hero_ids"], true, false)
	var dead := _normalize_strings(value["dead_hero_ids"], true, false)
	var awards := _normalize_xp_awards(value["xp_awards"])
	var memorial_ids := _normalize_strings(value["memorial_ids"], false, true)
	for result: Dictionary in [
		rewards, entitlements, created, dead, awards, memorial_ids,
	]:
		if not result["accepted"]:
			return result
	return _accept({
		"schema_version": 1,
		"resolution_index": int(value["resolution_index"]),
		"campaign_uid": String(value["campaign_uid"]),
		"attempt_id": int(value["attempt_id"]),
		"stage_id": String(value["stage_id"]),
		"ticket_hash": String(value["ticket_hash"]),
		"outcome_hash": String(value["outcome_hash"]),
		"result": String(value["result"]),
		"terminal_reason": String(value["terminal_reason"]),
		"terminal_tick": int(value["terminal_tick"]),
		"stars_before": int(value["stars_before"]),
		"stars_after": int(value["stars_after"]),
		"rewards_granted": rewards["value"],
		"class_entitlements_granted": entitlements["value"],
		"created_hero_ids": created["value"],
		"dead_hero_ids": dead["value"],
		"xp_awards": awards["value"],
		"memorial_ids": memorial_ids["value"],
		"marks_before": int(value["marks_before"]),
		"marks_after": int(value["marks_after"]),
		"strategic_body_hash_before": String(value["strategic_body_hash_before"]),
		"strategic_body_hash_after": String(value["strategic_body_hash_after"]),
	})


static func _validate_closure(
	anchor: Dictionary,
	receipt: Dictionary,
	current_core: Dictionary,
	context: Dictionary,
) -> Dictionary:
	var before: Dictionary = anchor["before_core"]
	var after: Dictionary = anchor["after_core"]
	if (
		receipt["resolution_index"] != anchor["resolution_index"]
		or receipt["strategic_body_hash_before"] != anchor["strategic_body_hash_before"]
		or receipt["strategic_body_hash_after"] != anchor["strategic_body_hash_after"]
	):
		return _reject(&"resolution_history_mismatch")
	if before["campaign_uid"] != receipt["campaign_uid"]:
		return _reject(&"receipt_campaign_mismatch")
	if (
		before["campaign_uid"] != after["campaign_uid"]
		or before["campaign_seed"] != after["campaign_seed"]
		or before["campaign_generation"] != after["campaign_generation"]
	):
		return _reject(&"resolution_anchor_transition_mismatch")
	if (
		before["save_revision"] + 1 != after["save_revision"]
		or anchor["save_revision_after"] != after["save_revision"]
		or before["next_resolution_index"] != anchor["resolution_index"]
		or after["next_resolution_index"] != anchor["resolution_index"] + 1
	):
		return _reject(&"resolution_anchor_transition_mismatch")
	if (
		before["next_attempt_id"] != receipt["attempt_id"] + 1
		or after["next_attempt_id"] != before["next_attempt_id"]
	):
		return _reject(&"resolution_anchor_transition_mismatch")
	var ticket := _find_ticket(before["tickets"], receipt["attempt_id"])
	if ticket.is_empty():
		return _reject(&"missing_resolution_ticket")
	if (
		ticket["ticket_hash"] != receipt["ticket_hash"]
		or ticket["stage_id"] != receipt["stage_id"]
		or after["tickets"] != before["tickets"]
	):
		return _reject(&"resolution_ticket_mismatch")
	var ticket_snapshot := _validate_ticket_snapshot(before, ticket, context)
	if not ticket_snapshot["accepted"]:
		return ticket_snapshot
	var transition := _validate_transition(before, after, receipt, context)
	if not transition["accepted"]:
		return transition
	return _validate_current_from_anchor(current_core, after, context)


static func _validate_transition(
	before: Dictionary,
	after: Dictionary,
	receipt: Dictionary,
	context: Dictionary,
) -> Dictionary:
	for key: String in [
		"campaign_uid", "campaign_seed", "campaign_generation", "next_recruitment_index",
		"next_attempt_id", "replay_marks_started_at_resolution", "offers",
		"promotion_receipts", "promotion_proofs", "tickets",
	]:
		if before[key] != after[key]:
			return _reject(&"resolution_anchor_transition_mismatch")
	if before["marks"] != receipt["marks_before"]:
		return _reject(&"resolution_marks_mismatch")
	if after["marks"] != receipt["marks_after"]:
		return _reject(&"resolution_marks_mismatch")
	var star_transition := _validate_stars(before, after, receipt)
	if not star_transition["accepted"]:
		return star_transition
	var expected_rewards: Array[Dictionary] = EconomyScript.resolution_rewards(
		before,
		String(receipt["stage_id"]),
		String(receipt["result"]),
		int(receipt["stars_before"]),
		context,
	)
	if receipt["rewards_granted"] != expected_rewards:
		return _reject(&"receipt_rewards_mismatch")
	var expected_marks_after := int(receipt["marks_before"])
	for reward: Dictionary in expected_rewards:
		if reward["kind"] == "currency" and reward["id"] == "marks":
			expected_marks_after += int(reward["amount"])
	if int(receipt["marks_after"]) != expected_marks_after:
		return _reject(&"resolution_marks_mismatch")
	var expected_entitlements := _array_difference(
		after["class_entitlements"], before["class_entitlements"],
	)
	if receipt["class_entitlements_granted"] != expected_entitlements:
		return _reject(&"receipt_entitlements_mismatch")
	if not receipt["created_hero_ids"].is_empty():
		return _reject(&"specialist_creation_forbidden")
	if before["heroes"].size() != after["heroes"].size():
		return _reject(&"resolution_roster_mismatch")
	var hero_transition := _validate_heroes(before["heroes"], after["heroes"], receipt)
	if not hero_transition["accepted"]:
		return hero_transition
	var memorial_transition := _validate_memorial(before["memorial"], after["memorial"], receipt)
	if not memorial_transition["accepted"]:
		return memorial_transition
	var unlocks := _validate_unlocks(before, after, expected_rewards)
	if not unlocks["accepted"]:
		return unlocks
	return _accept(null)


static func _validate_ticket_snapshot(
	before: Dictionary,
	ticket: Dictionary,
	context: Dictionary,
) -> Dictionary:
	if (
		before["tickets"].is_empty()
		or before["tickets"][-1] != ticket
		or ticket["expected_save_revision"] != before["save_revision"]
		or not (context["stage_order"] as Array).has(ticket["stage_id"])
	):
		return _reject(&"ticket_snapshot_mismatch")
	var pre_attempt: Dictionary = before.duplicate(true)
	pre_attempt["tickets"].pop_back()
	pre_attempt["next_attempt_id"] = ticket["attempt_id"]
	var strategic: Dictionary = HashScript.of_core(pre_attempt, context)
	if not strategic["accepted"] or strategic["hex"] != ticket["strategic_hash"]:
		return _reject(&"ticket_snapshot_mismatch")
	var heroes_by_id := {}
	for hero: Dictionary in before["heroes"]:
		heroes_by_id[hero["hero_id"]] = hero
	for row: Dictionary in ticket["squad"]:
		var hero: Dictionary = heroes_by_id.get(row["hero_id"], {})
		if hero.is_empty() or hero["life_status"] != "ready":
			return _reject(&"ticket_snapshot_mismatch")
		if (
			row["class_id"] != hero["current_class_id"]
			or row["operator_def_id"] != hero["operator_def_id"]
		):
			return _reject(&"ticket_snapshot_mismatch")
		var expected: Dictionary = context["operator_ticket_by_id"].get(
			row["operator_def_id"], {},
		).duplicate(true)
		if expected.is_empty():
			return _reject(&"ticket_snapshot_mismatch")
		expected["visual_spec"]["portrait_asset_id"] = hero["portrait_asset_id"]
		for key: String in [
			"operator_content_sha256", "combat_spec", "target_policy_spec",
			"skill_spec", "visual_spec",
		]:
			if row[key] != expected[key]:
				return _reject(&"ticket_snapshot_mismatch")
	return _accept(null)


static func _validate_preresolution_core(core: Dictionary) -> Dictionary:
	for key: String in [
		"stage_stars", "unlocked_traps", "class_entitlements",
		"promotion_receipts", "memorial",
	]:
		if not (core[key] as Array).is_empty():
			return _reject(&"pre_resolution_progress_mismatch")
	for hero: Dictionary in core["heroes"]:
		if (
			hero["xp"] != 0
			or hero["current_class_id"] != "recruit"
			or hero["life_status"] != "ready"
			or hero["death"] != null
		):
			return _reject(&"pre_resolution_progress_mismatch")
	return _accept(null)


static func _validate_current_from_anchor(
	current: Dictionary,
	after: Dictionary,
	context: Dictionary,
) -> Dictionary:
	if current["save_revision"] < after["save_revision"]:
		return _reject(&"post_resolution_mutation_mismatch")
	if current["save_revision"] > after["save_revision"]:
		if (current["command_receipts"] as Array).is_empty():
			return _reject(&"post_resolution_mutation_mismatch")
		var command_history: Dictionary = (
			load("res://sim/campaign_v3_command_history.gd").call("validate", current, context)
		)
		return _accept(null) if command_history["accepted"] else command_history
	for key: String in [
		"campaign_uid", "campaign_seed", "campaign_generation", "next_resolution_index",
		"stage_stars", "unlocked_traps", "class_entitlements",
		"promotion_proofs", "memorial",
	]:
		if current[key] != after[key]:
			return _reject(&"post_resolution_mutation_mismatch")
	var appended_tickets := _post_resolution_ticket_count(current, after)
	if appended_tickets < 0:
		return _reject(&"post_resolution_mutation_mismatch")
	var anchored_receipts: Array = after["promotion_receipts"]
	var current_receipts: Array = current["promotion_receipts"]
	if current_receipts.size() < anchored_receipts.size():
		return _reject(&"post_resolution_mutation_mismatch")
	for index: int in anchored_receipts.size():
		if anchored_receipts[index] != current_receipts[index]:
			return _reject(&"post_resolution_mutation_mismatch")
	var added := current_receipts.size() - anchored_receipts.size()
	var recruited := (current["heroes"] as Array).size() - (after["heroes"] as Array).size()
	if recruited < 0:
		return _reject(&"post_resolution_mutation_mismatch")
	if recruited > 0:
		if (current["command_receipts"] as Array).is_empty():
			return _reject(&"post_resolution_mutation_mismatch")
		var command_history: Dictionary = (
			load("res://sim/campaign_v3_command_history.gd")
			. call("validate", current, context)
		)
		return _accept(null) if command_history["accepted"] else command_history
	for key: String in ["next_recruitment_index", "marks", "offers"]:
		if current[key] != after[key]:
			return _reject(&"post_resolution_mutation_mismatch")
	var revision_delta := int(current["save_revision"]) - int(after["save_revision"])
	if revision_delta not in [added, added + appended_tickets]:
		return _reject(&"post_resolution_revision_mismatch")
	var expected_heroes: Array = after["heroes"].duplicate(true)
	for offset: int in added:
		var receipt: Dictionary = current_receipts[anchored_receipts.size() + offset]
		if receipt["save_revision"] != after["save_revision"] + offset + 1:
			return _reject(&"post_resolution_revision_mismatch")
		for choice: Dictionary in receipt["choices"]:
			if not _apply_choice(
				expected_heroes, after["class_entitlements"], choice, context,
			):
				return _reject(&"post_resolution_mutation_mismatch")
	if current["heroes"] != expected_heroes:
		return _reject(&"post_resolution_mutation_mismatch")
	return _accept(null)


static func _post_resolution_ticket_count(current: Dictionary, after: Dictionary) -> int:
	var anchored: Array = after["tickets"]
	var present: Array = current["tickets"]
	if present.size() not in [anchored.size(), anchored.size() + 1]:
		return -1
	for index: int in anchored.size():
		if present[index] != anchored[index]:
			return -1
	var appended := present.size() - anchored.size()
	if current["next_attempt_id"] != after["next_attempt_id"] + appended:
		return -1
	if appended == 0:
		return 0
	var tail: Dictionary = present[-1]
	return 1 if (
		tail["attempt_id"] == after["next_attempt_id"]
		and tail["expected_save_revision"] == current["save_revision"]
	) else -1


static func _apply_choice(
	heroes: Array,
	class_entitlements: Array,
	choice: Dictionary,
	context: Dictionary,
) -> bool:
	var pre_state := {
		"heroes": heroes,
		"class_entitlements": class_entitlements,
	}
	var validated: Dictionary = PromotionRulesScript.validate_choice(pre_state, context, {
		"hero_id": choice["hero_id"],
		"to_class_id": choice["to_class_id"],
	})
	if not validated["accepted"]:
		return false
	var result: Dictionary = validated["value"]
	if result["from_class_id"] != choice["from_class_id"]:
		return false
	var hero := _hero_by_id(heroes, result["hero_id"])
	hero["current_class_id"] = result["to_class_id"]
	hero["operator_def_id"] = result["operator_def_id"]
	if hero["first_class_id"] == "recruit":
		hero["first_class_id"] = result["to_class_id"]
	else:
		hero["advanced_class_id"] = result["to_class_id"]
	return true


static func _hero_by_id(heroes: Array, hero_id: String) -> Dictionary:
	for hero: Dictionary in heroes:
		if hero["hero_id"] == hero_id:
			return hero
	return {}


static func _validate_stars(
	before: Dictionary,
	after: Dictionary,
	receipt: Dictionary,
) -> Dictionary:
	var before_stars := _stars_for(before["stage_stars"], receipt["stage_id"])
	var after_stars := _stars_for(after["stage_stars"], receipt["stage_id"])
	if before_stars != receipt["stars_before"] or after_stars != receipt["stars_after"]:
		return _reject(&"receipt_stars_mismatch")
	var expected: Array = before["stage_stars"].duplicate(true)
	if receipt["result"] == "clear":
		var found := false
		for row: Dictionary in expected:
			if row["stage_id"] == receipt["stage_id"]:
				row["stars"] = receipt["stars_after"]
				found = true
				break
		if not found:
			expected.append({
				"stage_id": receipt["stage_id"],
				"stars": receipt["stars_after"],
				"first_clear_resolution_index": receipt["resolution_index"],
				"first_clear_attempt_id": receipt["attempt_id"],
				"first_clear_terminal_tick": receipt["terminal_tick"],
			})
	if expected != after["stage_stars"]:
		return _reject(&"resolution_stage_transition_mismatch")
	return _accept(null)


static func _validate_heroes(
	before_heroes: Array,
	after_heroes: Array,
	receipt: Dictionary,
) -> Dictionary:
	var dead: Array[String] = []
	var awards: Array[Dictionary] = []
	for index: int in before_heroes.size():
		var before: Dictionary = before_heroes[index]
		var after: Dictionary = after_heroes[index]
		for key: String in before:
			if key in ["xp", "life_status", "death"]:
				continue
			if before[key] != after[key]:
				return _reject(&"resolution_hero_transition_mismatch")
		var delta := int(after["xp"]) - int(before["xp"])
		if delta < 0:
			return _reject(&"resolution_xp_mismatch")
		if delta > 0:
			awards.append({"hero_id": String(after["hero_id"]), "delta": delta})
		if before["life_status"] == "ready" and after["life_status"] == "dead":
			dead.append(String(after["hero_id"]))
			if not _death_matches(after["death"], receipt):
				return _reject(&"death_receipt_mismatch")
		elif before["life_status"] != after["life_status"] or before["death"] != after["death"]:
			return _reject(&"resolution_life_transition_mismatch")
	awards.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["hero_id"]) < String(b["hero_id"]))
	dead.sort()
	if awards != receipt["xp_awards"]:
		return _reject(&"resolution_xp_mismatch")
	if dead != receipt["dead_hero_ids"]:
		return _reject(&"receipt_dead_set_mismatch")
	return _accept(null)


static func _validate_memorial(
	before: Array,
	after: Array,
	receipt: Dictionary,
) -> Dictionary:
	if after.size() < before.size():
		return _reject(&"resolution_memorial_mismatch")
	var before_by_id := {}
	for row: Dictionary in before:
		before_by_id[row["memorial_id"]] = row
	var new_ids: Array[String] = []
	for row: Dictionary in after:
		var memorial_id := String(row["memorial_id"])
		if before_by_id.has(memorial_id):
			if before_by_id[memorial_id] != row:
				return _reject(&"resolution_memorial_mismatch")
		else:
			new_ids.append(memorial_id)
	new_ids.sort()
	if new_ids != receipt["memorial_ids"]:
		return _reject(&"resolution_memorial_mismatch")
	return _accept(null)


static func _validate_unlocks(
	before: Dictionary,
	after: Dictionary,
	rewards: Array,
) -> Dictionary:
	var traps: Array = before["unlocked_traps"].duplicate()
	for reward: Dictionary in rewards:
		if reward["kind"] == "trap":
			traps.append(reward["id"])
	traps.sort()
	if traps != after["unlocked_traps"]:
		return _reject(&"resolution_unlock_mismatch")
	return _accept(null)


static func _normalize_rewards(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return _reject(&"invalid_resolution_rows")
	var out: Array[Dictionary] = []
	var seen := {}
	for raw: Variant in value:
		if typeof(raw) != TYPE_DICTIONARY:
			return _reject(&"invalid_resolution_rows")
		var kind := String(raw.get("kind", ""))
		if kind == "currency":
			if (
				raw.keys() != CURRENCY_REWARD_KEYS
				or String(raw["id"]) != "marks"
				or typeof(raw["amount"]) != TYPE_INT
				or int(raw["amount"]) not in [
					EconomyScript.REPLAY_CLEAR_MARKS, 40,
				]
			):
				return _reject(&"invalid_resolution_rows")
		elif raw.keys() != CONTENT_REWARD_KEYS or kind != "trap":
			return _reject(&"invalid_resolution_rows")
		if not _ascii(String(raw["id"])):
			return _reject(&"invalid_resolution_rows")
		var key := "%s:%s" % [raw["kind"], raw["id"]]
		if seen.has(key):
			return _reject(&"invalid_resolution_rows")
		seen[key] = true
		if kind == "currency":
			out.append({"amount": int(raw["amount"]), "id": "marks", "kind": "currency"})
		else:
			out.append({"id": String(raw["id"]), "kind": kind})
	return _accept(out)


static func _normalize_strings(
	value: Variant,
	hex_ids: bool,
	memorial_ids: bool,
) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return _reject(&"invalid_resolution_rows")
	var out: Array[String] = []
	for raw: Variant in value:
		if typeof(raw) != TYPE_STRING:
			return _reject(&"invalid_resolution_rows")
		var text := String(raw)
		if hex_ids and not _is_hex(text, 16):
			return _reject(&"invalid_resolution_rows")
		if memorial_ids and (
			not text.begins_with("memorial:")
			or not _is_hex(text.trim_prefix("memorial:"), 16)
		):
			return _reject(&"invalid_resolution_rows")
		if not hex_ids and not memorial_ids and not _ascii(text):
			return _reject(&"invalid_resolution_rows")
		if out.has(text):
			return _reject(&"invalid_resolution_rows")
		out.append(text)
	var sorted := out.duplicate()
	sorted.sort()
	if out != sorted:
		return _reject(&"noncanonical_resolution_rows")
	return _accept(out)


static func _normalize_xp_awards(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return _reject(&"invalid_resolution_rows")
	var out: Array[Dictionary] = []
	var previous := ""
	for raw: Variant in value:
		if typeof(raw) != TYPE_DICTIONARY or raw.keys() != XP_KEYS:
			return _reject(&"invalid_resolution_rows")
		var hero_id := String(raw["hero_id"])
		if not _is_hex(hero_id, 16) or hero_id <= previous:
			return _reject(&"noncanonical_resolution_rows")
		if not _in_range(raw["delta"], 1, U63_MAX):
			return _reject(&"invalid_resolution_rows")
		previous = hero_id
		out.append({"hero_id": hero_id, "delta": int(raw["delta"])})
	return _accept(out)


static func _find_ticket(tickets: Array, attempt_id: int) -> Dictionary:
	for ticket: Dictionary in tickets:
		if ticket["attempt_id"] == attempt_id:
			return ticket
	return {}


static func _stars_for(rows: Array, stage_id: String) -> int:
	for row: Dictionary in rows:
		if row["stage_id"] == stage_id:
			return int(row["stars"])
	return 0


static func _array_difference(after: Array, before: Array) -> Array[String]:
	var result: Array[String] = []
	for item: String in after:
		if not before.has(item):
			result.append(item)
	result.sort()
	return result


static func _death_matches(death: Variant, receipt: Dictionary) -> bool:
	return (
		typeof(death) == TYPE_DICTIONARY
		and death["resolution_index"] == receipt["resolution_index"]
		and death["attempt_id"] == receipt["attempt_id"]
		and death["stage_id"] == receipt["stage_id"]
		and death["terminal_reason"] == receipt["terminal_reason"]
		and death["terminal_tick"] == receipt["terminal_tick"]
	)


static func _in_range(value: Variant, minimum: int, maximum: int) -> bool:
	return typeof(value) == TYPE_INT and int(value) >= minimum and int(value) <= maximum


static func _ascii(value: String) -> bool:
	if value.is_empty():
		return false
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
