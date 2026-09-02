class_name CampaignInvariants
extends RefCounted

const CampaignCodec := preload("res://sim/campaign_codec.gd")
const CampaignHash := preload("res://sim/campaign_hash.gd")
const CampaignProgression := preload("res://sim/campaign_progression.gd")
const CampaignPromotionHistory := preload("res://sim/campaign_promotion_history.gd")
const CanonicalJson := preload("res://sim/canonical_json.gd")
const HeroIdentity := preload("res://sim/hero_identity.gd")
const STARTERS := [&"caster_1", &"guard_1", &"sniper_1"]
const INITIAL_MARKS := 120
const U63_MAX := 9_223_372_036_854_775_807


static func validate(data: Dictionary, context: Dictionary) -> Dictionary:
	var cleared_count: int = data["stage_stars"].size()
	var starter_seen := {}
	var reward_counts := {}
	var reward_stages: Array[int] = []
	var death_groups := {}
	var operator_history := {}
	var clear_resolutions := _clear_resolutions(data["stage_stars"])
	var latest_deaths: Array[String] = []
	var receipt: Variant = data["last_resolution"]
	var previous_clear := 0
	var previous_clear_attempt := 0
	for row: Dictionary in data["stage_stars"]:
		var first_clear := int(row["first_clear_resolution_index"])
		var first_attempt := int(row["first_clear_attempt_id"])
		if receipt == null or first_clear <= previous_clear:
			return _reject(&"stage_clear_history_mismatch")
		if first_clear >= int(data["next_resolution_index"]):
			return _reject(&"stage_clear_history_mismatch")
		if first_clear > int(receipt["resolution_index"]):
			return _reject(&"stage_clear_history_mismatch")
		if first_attempt <= previous_clear_attempt or first_attempt >= int(data["next_attempt_id"]):
			return _reject(&"stage_clear_attempt_history_mismatch")
		previous_clear = first_clear
		previous_clear_attempt = first_attempt
	var previous_created_after := -1
	for position: int in data["heroes"].size():
		var hero: Dictionary = data["heroes"][position]
		var source := String(hero["recruit_source"])
		var source_id := String(hero["source_id"])
		var index := int(hero["recruitment_index"])
		var created_after := int(hero["recruited_after_resolution_index"])
		var operator_id := String(hero["acquisition_operator_def_id"])
		if created_after < previous_created_after:
			return _reject(&"recruitment_history_order_mismatch")
		if created_after >= int(data["next_resolution_index"]):
			return _reject(&"recruitment_history_order_mismatch")
		previous_created_after = created_after
		if source == "starter":
			if created_after != 0 or index >= STARTERS.size():
				return _reject(&"starter_origin_mismatch")
			if StringName(operator_id) != STARTERS[index]:
				return _reject(&"starter_origin_mismatch")
			starter_seen[index] = true
		elif index < STARTERS.size():
			return _reject(&"starter_origin_mismatch")
		if source == "contract" and not _consumed_contract(data["offers"], source_id):
			return _reject(&"contract_history_mismatch")
		if source in ["reward", "recovery"]:
			var stage_index: int = context["stage_order"].find(source_id)
			var maximum := cleared_count - 1 if source == "reward" else cleared_count
			if stage_index < 0 or stage_index > maximum:
				return _reject(&"hero_source_history_mismatch")
			if source == "reward" and clear_resolutions.get(source_id, -1) != created_after:
				return _reject(&"reward_history_order_mismatch")
			if source == "recovery" and not _recovery_reachable_indexed(
				operator_history.get(operator_id, {}), source_id,
				created_after, context, clear_resolutions,
			):
				return _reject(&"recovery_not_required")
		if source == "reward":
			var key := _source_key(source_id, operator_id)
			reward_counts[key] = int(reward_counts.get(key, 0)) + 1
			reward_stages.append(context["stage_order"].find(source_id))
		var death_check := _record_death(
			hero, receipt, data, context, cleared_count, death_groups, latest_deaths,
		)
		if not death_check["accepted"]:
			return death_check
		_update_operator_history(operator_history, hero)
	if starter_seen.size() != STARTERS.size():
		return _reject(&"starter_origin_mismatch")
	if int(data["marks"]) != _expected_marks(data["offers"]):
		return _reject(&"contract_marks_mismatch")
	var rewards := _validate_reward_history(data, context, reward_counts, reward_stages)
	if not rewards["accepted"]:
		return rewards
	var deaths := _validate_death_groups(death_groups, receipt)
	if not deaths["accepted"]:
		return deaths
	var events := _validate_global_events(data)
	if not events["accepted"]:
		return events
	var promotions := CampaignPromotionHistory.validate(data, context)
	if not promotions["accepted"]:
		return promotions
	return _validate_latest_receipt(data, context, latest_deaths)


static func _recovery_reachable(
	heroes: Array,
	position: int,
	operator_id: String,
	stage_id: String,
	created_after: int,
	context: Dictionary,
	clear_resolutions: Dictionary,
) -> bool:
	var seen := false
	var prior_death := false
	for index: int in position:
		var earlier: Dictionary = heroes[index]
		if earlier["acquisition_operator_def_id"] == operator_id:
			seen = true
			if earlier["life_status"] == "ready":
				return false
			if int(earlier["death"]["resolution_index"]) <= created_after:
				prior_death = true
	var stage_index: int = context["stage_order"].find(stage_id)
	var prerequisite_clear := 0
	if stage_index > 0:
		var prerequisite: String = context["stage_order"][stage_index - 1]
		prerequisite_clear = int(clear_resolutions.get(prerequisite, U63_MAX))
	var source_clear := int(clear_resolutions.get(stage_id, U63_MAX))
	return (
		seen and prior_death
		and prerequisite_clear <= created_after
		and created_after < source_clear
	)


static func _recovery_reachable_indexed(
	history: Dictionary,
	stage_id: String,
	created_after: int,
	context: Dictionary,
	clear_resolutions: Dictionary,
) -> bool:
	var stage_index: int = context["stage_order"].find(stage_id)
	var prerequisite_clear := 0
	if stage_index > 0:
		var prerequisite: String = context["stage_order"][stage_index - 1]
		prerequisite_clear = int(clear_resolutions.get(prerequisite, U63_MAX))
	var source_clear := int(clear_resolutions.get(stage_id, U63_MAX))
	return (
		bool(history.get("seen", false))
		and not bool(history.get("has_ready", false))
		and int(history.get("earliest_death_resolution", U63_MAX)) <= created_after
		and prerequisite_clear <= created_after
		and created_after < source_clear
	)


static func _update_operator_history(history: Dictionary, hero: Dictionary) -> void:
	var operator_id := String(hero["operator_def_id"])
	var entry: Dictionary = history.get(operator_id, {
		"seen": false,
		"has_ready": false,
		"earliest_death_resolution": U63_MAX,
	})
	entry["seen"] = true
	if hero["life_status"] == "ready":
		entry["has_ready"] = true
	elif hero["death"] != null:
		entry["earliest_death_resolution"] = min(
			int(entry["earliest_death_resolution"]),
			int(hero["death"]["resolution_index"]),
		)
	history[operator_id] = entry


static func _record_death(
	hero: Dictionary,
	receipt: Variant,
	data: Dictionary,
	context: Dictionary,
	cleared_count: int,
	groups: Dictionary,
	latest: Array[String],
) -> Dictionary:
	var death: Variant = hero["death"]
	if death == null:
		return _accept()
	var stage_index: int = context["stage_order"].find(String(death["stage_id"]))
	if receipt == null or stage_index < 0 or stage_index > cleared_count:
		return _reject(&"death_history_mismatch")
	var resolution_index := int(death["resolution_index"])
	if resolution_index <= int(hero["recruited_after_resolution_index"]):
		return _reject(&"death_before_recruitment")
	if resolution_index > int(receipt["resolution_index"]):
		return _reject(&"death_history_mismatch")
	if int(death["attempt_id"]) >= int(data["next_attempt_id"]):
		return _reject(&"death_history_mismatch")
	if resolution_index == int(receipt["resolution_index"]):
		latest.append(String(hero["hero_id"]))
	var tuple := [death["attempt_id"], death["stage_id"], death["terminal_reason"]]
	if groups.has(resolution_index) and groups[resolution_index] != tuple:
		return _reject(&"conflicting_death_history")
	groups[resolution_index] = tuple
	return _accept()


static func _validate_reward_history(
	data: Dictionary,
	context: Dictionary,
	counts: Dictionary,
	stages: Array[int],
) -> Dictionary:
	for row: Dictionary in data["stage_stars"]:
		for reward: Dictionary in context["stage_rewards"][row["stage_id"]]:
			if reward["kind"] == "operator":
				var key := _source_key(String(row["stage_id"]), String(reward["id"]))
				if int(counts.get(key, 0)) != 1:
					return _reject(&"reward_history_mismatch")
	var previous := -1
	for stage_index: int in stages:
		if stage_index <= previous:
			return _reject(&"reward_history_order_mismatch")
		previous = stage_index
	return _accept()


static func _validate_death_groups(groups: Dictionary, receipt: Variant) -> Dictionary:
	var indices: Array = groups.keys()
	indices.sort()
	var previous_attempt := 0
	for resolution_index: int in indices:
		var attempt := int(groups[resolution_index][0])
		if attempt <= previous_attempt:
			return _reject(&"death_history_order_mismatch")
		if receipt != null:
			if resolution_index > int(receipt["resolution_index"]):
				return _reject(&"death_history_order_mismatch")
			if resolution_index < int(receipt["resolution_index"]):
				if attempt >= int(receipt["attempt_id"]):
					return _reject(&"death_history_order_mismatch")
		previous_attempt = attempt
	return _accept()


static func _validate_global_events(data: Dictionary) -> Dictionary:
	var events := {}
	for row: Dictionary in data["stage_stars"]:
		var clear_event := {
			"stage_id": row["stage_id"],
			"attempt_id": row["first_clear_attempt_id"],
			"terminal_reason": "clear",
			"terminal_tick": row["first_clear_terminal_tick"],
		}
		var merged := _merge_event(events, row["first_clear_resolution_index"], clear_event)
		if not merged["accepted"]:
			return merged
	for hero: Dictionary in data["heroes"]:
		if hero["death"] == null:
			continue
		var death: Dictionary = hero["death"]
		var death_event := {
			"stage_id": death["stage_id"],
			"attempt_id": death["attempt_id"],
			"terminal_reason": death["terminal_reason"],
			"terminal_tick": death["terminal_tick"],
		}
		var merged := _merge_event(events, death["resolution_index"], death_event)
		if not merged["accepted"]:
			return merged
	if data["last_resolution"] != null:
		var receipt: Dictionary = data["last_resolution"]
		var receipt_event := {
			"stage_id": receipt["stage_id"],
			"attempt_id": receipt["attempt_id"],
			"terminal_reason": receipt["terminal_reason"],
			"terminal_tick": receipt["terminal_tick"],
		}
		var merged := _merge_event(events, receipt["resolution_index"], receipt_event)
		if not merged["accepted"]:
			return merged
	var resolution_indices: Array = events.keys()
	resolution_indices.sort()
	var previous_attempt := 0
	for resolution_index: int in resolution_indices:
		var attempt := int(events[resolution_index]["attempt_id"])
		if attempt <= previous_attempt:
			return _reject(&"resolution_attempt_history_mismatch")
		previous_attempt = attempt
	return _accept()


static func _merge_event(
	events: Dictionary,
	resolution_index: Variant,
	event: Dictionary,
) -> Dictionary:
	var key := int(resolution_index)
	if events.has(key) and events[key] != event:
		return _reject(&"resolution_event_mismatch")
	events[key] = event
	return _accept()


static func _clear_resolutions(rows: Array) -> Dictionary:
	var values := {}
	for row: Dictionary in rows:
		values[row["stage_id"]] = row["first_clear_resolution_index"]
	return values


static func _consumed_contract(offers: Array, offer_id: String) -> bool:
	for offer: Dictionary in offers:
		if offer["offer_id"] == offer_id:
			return bool(offer["consumed"])
	return false


static func _expected_marks(offers: Array) -> int:
	var value := INITIAL_MARKS
	for offer: Dictionary in offers:
		if offer["consumed"]:
			value -= int(offer["cost"])
	return value


static func _validate_latest_receipt(
	data: Dictionary,
	context: Dictionary,
	latest_deaths: Array[String],
) -> Dictionary:
	var receipt: Variant = data["last_resolution"]
	if receipt == null:
		return _accept() if data["resolution_anchor"] == null else _reject(&"orphan_resolution_anchor")
	var anchor: Variant = data["resolution_anchor"]
	if anchor == null:
		return _reject(&"missing_resolution_anchor")
	if int(anchor["resolution_index"]) != int(receipt["resolution_index"]):
		return _reject(&"resolution_anchor_mismatch")
	if anchor["strategic_body_hash_before"] != receipt["strategic_body_hash_before"]:
		return _reject(&"resolution_anchor_mismatch")
	if anchor["strategic_body_hash_after"] != receipt["strategic_body_hash_after"]:
		return _reject(&"resolution_anchor_mismatch")
	if int(anchor["save_revision_after"]) > int(data["save_revision"]):
		return _reject(&"resolution_anchor_mismatch")
	var before_core: Dictionary = anchor["before_core"]
	var after_core: Dictionary = anchor["after_core"]
	if int(after_core["save_revision"]) != int(anchor["save_revision_after"]):
		return _reject(&"resolution_anchor_mismatch")
	if int(before_core["save_revision"]) + 1 != int(after_core["save_revision"]):
		return _reject(&"resolution_anchor_mismatch")
	if int(before_core["next_resolution_index"]) != int(anchor["resolution_index"]):
		return _reject(&"resolution_anchor_mismatch")
	if int(after_core["next_resolution_index"]) != int(anchor["resolution_index"]) + 1:
		return _reject(&"resolution_anchor_mismatch")
	if int(before_core["next_attempt_id"]) != int(receipt["attempt_id"]) + 1:
		return _reject(&"resolution_anchor_transition_mismatch")
	if int(after_core["next_attempt_id"]) != int(before_core["next_attempt_id"]):
		return _reject(&"resolution_anchor_transition_mismatch")
	if int(before_core["marks"]) != int(receipt["marks_before"]):
		return _reject(&"resolution_anchor_transition_mismatch")
	if int(after_core["marks"]) != int(receipt["marks_after"]):
		return _reject(&"resolution_anchor_transition_mismatch")
	var anchored_before := CampaignHash._of_normalized_core(before_core)
	var anchored_after := CampaignHash._of_normalized_core(after_core)
	if not anchored_before["accepted"] or not anchored_after["accepted"]:
		return _reject(&"resolution_anchor_hash_mismatch")
	if anchored_before["hex"] != anchor["strategic_body_hash_before"]:
		return _reject(&"resolution_anchor_hash_mismatch")
	if anchored_after["hex"] != anchor["strategic_body_hash_after"]:
		return _reject(&"resolution_anchor_hash_mismatch")
	var reversed := _reverse_latest(after_core, receipt)
	if reversed.is_empty() or reversed != before_core:
		return _reject(&"resolution_anchor_transition_mismatch")
	var current_closure := _validate_current_from_anchor(data, after_core, receipt)
	if not current_closure["accepted"]:
		return current_closure
	var current_stars := 0
	for row: Dictionary in data["stage_stars"]:
		if row["stage_id"] == receipt["stage_id"]:
			current_stars = int(row["stars"])
	if int(receipt["stars_after"]) != current_stars:
		return _reject(&"receipt_stars_mismatch")
	var expected_rewards: Array = []
	if receipt["result"] == "clear" and int(receipt["stars_before"]) == 0:
		expected_rewards = context["stage_rewards"][receipt["stage_id"]]
	if receipt["rewards_granted"].size() != expected_rewards.size():
		return _reject(&"receipt_rewards_mismatch")
	var created: Array[String] = []
	for index: int in expected_rewards.size():
		var actual: Dictionary = receipt["rewards_granted"][index]
		var expected: Dictionary = expected_rewards[index]
		if actual["kind"] != expected["kind"] or actual["id"] != expected["id"]:
			return _reject(&"receipt_rewards_mismatch")
		if actual["hero_instance_id"] != null:
			created.append(String(actual["hero_instance_id"]))
	if receipt["created_hero_ids"] != created:
		return _reject(&"receipt_created_set_mismatch")
	if not _same_set(receipt["dead_hero_ids"], latest_deaths):
		return _reject(&"receipt_dead_set_mismatch")
	if int(data["next_resolution_index"]) != int(receipt["resolution_index"]) + 1:
		return _reject(&"receipt_counter_mismatch")
	if int(data["next_attempt_id"]) < int(receipt["attempt_id"]) + 1:
		return _reject(&"receipt_counter_mismatch")
	return _accept()

static func _validate_current_from_anchor(
	data: Dictionary,
	after_core: Dictionary,
	receipt: Dictionary,
) -> Dictionary:
	var current_core := _core_snapshot(data)
	if int(data["save_revision"]) == int(after_core["save_revision"]):
		return _accept() if current_core == after_core else (
			_reject(&"post_resolution_mutation_mismatch")
		)
	var revision_delta := int(data["save_revision"]) - int(after_core["save_revision"])
	var attempt_delta := int(data["next_attempt_id"]) - int(after_core["next_attempt_id"])
	for key: String in [
		"campaign_uid", "campaign_seed", "campaign_generation", "next_resolution_index",
		"stage_stars", "unlocked_traps",
	]:
		if data[key] != after_core[key]:
			return _reject(&"post_resolution_mutation_mismatch")
	if int(data["save_revision"]) < int(after_core["save_revision"]):
		return _reject(&"post_resolution_mutation_mismatch")
	if int(data["next_attempt_id"]) < int(after_core["next_attempt_id"]):
		return _reject(&"post_resolution_mutation_mismatch")
	var anchored_offers: Array = after_core["offers"]
	var current_offers: Array = data["offers"]
	if anchored_offers.size() != current_offers.size():
		return _reject(&"post_resolution_mutation_mismatch")
	for index: int in anchored_offers.size():
		var anchored_offer: Dictionary = anchored_offers[index]
		var current_offer: Dictionary = current_offers[index]
		for key: String in ["offer_id", "operator_def_id", "cost"]:
			if anchored_offer[key] != current_offer[key]:
				return _reject(&"post_resolution_mutation_mismatch")
			if bool(anchored_offer["consumed"]) and not bool(current_offer["consumed"]):
				return _reject(&"post_resolution_mutation_mismatch")
	var anchored_promotions: Array = after_core["promotion_receipts"]
	var current_promotions: Array = data["promotion_receipts"]
	if current_promotions.size() < anchored_promotions.size():
		return _reject(&"post_resolution_mutation_mismatch")
	for index: int in anchored_promotions.size():
		if anchored_promotions[index] != current_promotions[index]:
			return _reject(&"post_resolution_mutation_mismatch")
	var anchored_proofs: Array = after_core["promotion_proofs"]
	var current_proofs: Array = data["promotion_proofs"]
	if current_proofs.size() < anchored_proofs.size():
		return _reject(&"post_resolution_mutation_mismatch")
	for index: int in anchored_proofs.size():
		if anchored_proofs[index] != current_proofs[index]:
			return _reject(&"post_resolution_mutation_mismatch")
	var later_promotions := {}
	for index: int in range(anchored_promotions.size(), current_promotions.size()):
		var promotion: Dictionary = current_promotions[index]
		if int(promotion["prior_save_revision"]) < int(after_core["save_revision"]):
			return _reject(&"post_resolution_mutation_mismatch")
		later_promotions[promotion["hero_id"]] = promotion
	var anchored_heroes: Array = after_core["heroes"]
	var current_heroes: Array = data["heroes"]
	if current_heroes.size() < anchored_heroes.size():
		return _reject(&"post_resolution_mutation_mismatch")
	var renamed_count := 0
	for index: int in anchored_heroes.size():
		var anchored_hero: Dictionary = anchored_heroes[index].duplicate(true)
		var current_hero: Dictionary = current_heroes[index].duplicate(true)
		if anchored_hero["custom_callsign"] != current_hero["custom_callsign"]:
			renamed_count += 1
		var promotion: Dictionary = later_promotions.get(current_hero["hero_id"], {})
		if not promotion.is_empty():
			if (
				anchored_hero["advanced_class_id"] != null
				or anchored_hero["operator_def_id"] != promotion["prior_operator_def_id"]
				or current_hero["advanced_class_id"] != promotion["new_class_id"]
				or current_hero["operator_def_id"] != promotion["new_operator_def_id"]
			):
				return _reject(&"post_resolution_mutation_mismatch")
			anchored_hero["advanced_class_id"] = current_hero["advanced_class_id"]
			anchored_hero["operator_def_id"] = current_hero["operator_def_id"]
		anchored_hero.erase("custom_callsign")
		current_hero.erase("custom_callsign")
		if anchored_hero != current_hero:
			return _reject(&"post_resolution_mutation_mismatch")
	for index: int in range(anchored_heroes.size(), current_heroes.size()):
		var hero: Dictionary = current_heroes[index]
		if hero["recruit_source"] not in ["contract", "recovery"]:
			return _reject(&"post_resolution_mutation_mismatch")
		if int(hero["recruited_after_resolution_index"]) < int(receipt["resolution_index"]):
			return _reject(&"post_resolution_mutation_mismatch")
		if hero["custom_callsign"] != null:
			renamed_count += 1
	var recruit_delta := current_heroes.size() - anchored_heroes.size()
	var promotion_delta := current_promotions.size() - anchored_promotions.size()
	var minimum_revision_delta := attempt_delta + recruit_delta + renamed_count + promotion_delta
	var hidden_rename_count := revision_delta - minimum_revision_delta
	if revision_delta < minimum_revision_delta:
		return _reject(&"post_resolution_revision_mismatch")
	if hidden_rename_count == 1 and renamed_count == 0:
		return _reject(&"post_resolution_revision_mismatch")
	return _accept()


static func _core_snapshot(data: Dictionary) -> Dictionary:
	var snapshot := {}
	for key: String in CampaignCodec.CORE_KEYS:
		snapshot[key] = data[key]
	return snapshot


static func _reverse_latest(data: Dictionary, receipt: Dictionary) -> Dictionary:
	if int(data["save_revision"]) <= 1:
		return {}
	var before := data.duplicate(true)
	before.erase("resolution_anchor")
	before.erase("last_resolution")
	before["save_revision"] = int(data["save_revision"]) - 1
	before["next_resolution_index"] = int(receipt["resolution_index"])
	before["marks"] = int(receipt["marks_before"])
	var created: Array = receipt["created_hero_ids"]
	var first_created := int(data["next_recruitment_index"])
	for hero_id: String in created:
		for hero: Dictionary in before["heroes"]:
			if hero["hero_id"] == hero_id:
				first_created = min(first_created, int(hero["recruitment_index"]))
	before["heroes"] = before["heroes"].filter(
		func(hero: Dictionary) -> bool: return not created.has(hero["hero_id"]),
	)
	if not created.is_empty():
		if before["heroes"].size() != first_created:
			return {}
		before["next_recruitment_index"] = first_created
	for hero: Dictionary in before["heroes"]:
		if receipt["dead_hero_ids"].has(hero["hero_id"]):
			hero["life_status"] = "ready"
			hero["death"] = null
	if not CampaignProgression.reverse_xp(before["heroes"], receipt["xp_awards"]):
		return {}
	if int(receipt["stars_before"]) == 0:
		before["stage_stars"] = before["stage_stars"].filter(
			func(row: Dictionary) -> bool: return row["stage_id"] != receipt["stage_id"],
		)
	else:
		for row: Dictionary in before["stage_stars"]:
			if row["stage_id"] == receipt["stage_id"]:
				row["stars"] = receipt["stars_before"]
	if int(receipt["stars_before"]) == 0:
		for reward: Dictionary in receipt["rewards_granted"]:
			if reward["kind"] == "trap":
				before["unlocked_traps"].erase(reward["id"])
	return before


static func _same_set(left: Array, right: Array[String]) -> bool:
	if left.size() != right.size():
		return false
	var values := {}
	for item: String in right:
		values[item] = true
	for item: String in left:
		if not values.has(item):
			return false
	return true


static func _source_key(stage_id: String, operator_id: String) -> String:
	return CanonicalJson.text([stage_id, operator_id])


static func _accept() -> Dictionary:
	return {"accepted": true, "error_code": &""}


static func _reject(code: StringName) -> Dictionary:
	return {"accepted": false, "error_code": code}
