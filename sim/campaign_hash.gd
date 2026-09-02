class_name CampaignHash
extends RefCounted

const CampaignCodec := preload("res://sim/campaign_codec.gd")
const CampaignProgression := preload("res://sim/campaign_progression.gd")
const CombatContentBindingScript := preload("res://sim/combat_content_binding.gd")
const CanonicalJson := preload("res://sim/canonical_json.gd")
const HeroIdentity := preload("res://sim/hero_identity.gd")
const HeroNames := preload("res://sim/hero_names.gd")
const MAGIC := "PTD-CAMPAIGN-HASH"
const VERSION := 2
const FNV_OFFSET := -3750763034362895579
const FNV_PRIME := 1099511628211
const SOURCE_ENUM := {"starter": 0, "contract": 1, "reward": 2, "recovery": 3}
const LIFE_ENUM := {"ready": 0, "dead": 1}
const TERMINAL_ENUM := {"clear": 0, "leak_defeat": 1, "base_defeat": 2, "resign": 3}
const RESULT_ENUM := {"clear": 0, "defeat": 1}
const REWARD_ENUM := {"operator": 0, "trap": 1}


static func of_data(data: Variant, context: Dictionary) -> Dictionary:
	return _hash(data, context, false)


static func of_core(data: Variant, context: Dictionary) -> Dictionary:
	return _hash(data, context, true)


static func of_core_snapshot(data: Variant, context: Dictionary) -> Dictionary:
	var normalized := CampaignCodec.normalize_core_snapshot(data, context)
	if not normalized["accepted"]:
		return normalized
	return _hash_encoded(_bytes_of_normalized(normalized["value"], true))


## Private performance seam: callers must have just accepted this exact value
## through CampaignCodec.normalize_data. It changes no hash grammar or bytes.
static func _of_normalized_data(data: Dictionary) -> Dictionary:
	return _hash_encoded(_bytes_of_normalized(data, false))


static func _of_normalized_core(data: Dictionary) -> Dictionary:
	return _hash_encoded(_bytes_of_normalized(data, true))


static func of_normalized_data(data: Dictionary, omit_last_resolution: bool) -> Dictionary:
	## Test/invariant seam for ban-list paranoia. Callers must already own a
	## canonical normalized value; public gameplay uses of_data()/of_core().
	return _hash_encoded(_bytes_of_normalized(data, omit_last_resolution))


static func bytes_of(
	data: Variant,
	context: Dictionary,
	omit_last_resolution: bool = false,
) -> Dictionary:
	var normalized := CampaignCodec.normalize_data(data, context)
	if not normalized["accepted"]:
		return normalized
	var value: Dictionary = normalized["value"]
	return _bytes_of_normalized(value, omit_last_resolution)


static func _bytes_of_normalized(
	value: Dictionary,
	omit_last_resolution: bool,
) -> Dictionary:
	var out := PackedByteArray()
	out.append_array(MAGIC.to_ascii_buffer())
	out.append(0)
	_append_u32(out, VERSION)
	_append_string(out, String(value["campaign_uid"]))
	_append_i64(out, int(value["campaign_seed"]))
	_append_i64(out, int(value["campaign_generation"]))
	_append_i64(out, int(value["save_revision"]))
	_append_i64(out, int(value["next_recruitment_index"]))
	_append_i64(out, int(value["next_attempt_id"]))
	_append_i64(out, int(value["next_resolution_index"]))
	_append_i64(out, int(value["marks"]))
	_append_stage_stars(out, value["stage_stars"])
	_append_strings(out, value["unlocked_traps"])
	_append_offers(out, value["offers"])
	_append_heroes(out, value["heroes"])
	_append_promotion_receipts(
		out, value["promotion_receipts"], int(value["save_revision"]),
	)
	if omit_last_resolution:
		out.append(0)
		out.append(0)
	else:
		_append_anchor_nullable(out, value["resolution_anchor"])
		_append_resolution_nullable(out, value["last_resolution"])
	# TD-MITIGATION append-only extension. The all-zero compatibility binding
	# appends no bytes, preserving every pre-feature strategic hash exactly.
	if value["combat_rules_sha256"] != CombatContentBindingScript.LEGACY_ZERO_SHA256:
		out.append(0x4D)
		_append_string(out, String(value["combat_rules_sha256"]))
	return {"accepted": true, "error_code": &"", "bytes": out}


static func format_hex(bits: int) -> String:
	return HeroIdentity.format_u64_hex(bits)


static func _hash(
	data: Variant,
	context: Dictionary,
	omit_last_resolution: bool,
) -> Dictionary:
	var encoded := bytes_of(data, context, omit_last_resolution)
	if not encoded["accepted"]:
		return encoded
	return _hash_encoded(encoded)


static func _hash_encoded(encoded: Dictionary) -> Dictionary:
	var bits := FNV_OFFSET
	for byte: int in encoded["bytes"]:
		bits ^= byte
		bits *= FNV_PRIME
	return {
		"accepted": true,
		"error_code": &"",
		"bits": bits,
		"hex": format_hex(bits),
		"bytes": encoded["bytes"],
	}


static func _append_stage_stars(out: PackedByteArray, rows: Array) -> void:
	_append_u32(out, rows.size())
	for row: Dictionary in rows:
		_append_string(out, String(row["stage_id"]))
		out.append(int(row["stars"]) & 0xFF)
		_append_i64(out, int(row["first_clear_resolution_index"]))
		_append_i64(out, int(row["first_clear_attempt_id"]))
		_append_i64(out, int(row["first_clear_terminal_tick"]))


static func _append_strings(out: PackedByteArray, values: Array) -> void:
	_append_u32(out, values.size())
	for value: Variant in values:
		_append_string(out, String(value))


static func _append_anchor_nullable(out: PackedByteArray, value: Variant) -> void:
	if value == null:
		out.append(0)
		return
	out.append(1)
	_append_i64(out, int(value["resolution_index"]))
	_append_i64(out, int(value["save_revision_after"]))
	_append_string(out, CanonicalJson.text(_anchor_core_projection(value["before_core"])))
	_append_string(out, CanonicalJson.text(_anchor_core_projection(value["after_core"])))
	_append_string(out, String(value["strategic_body_hash_before"]))
	_append_string(out, String(value["strategic_body_hash_after"]))


static func _anchor_core_projection(value: Dictionary) -> Dictionary:
	var projected := value.duplicate(true)
	if projected["combat_rules_sha256"] == CombatContentBindingScript.LEGACY_ZERO_SHA256:
		projected.erase("combat_rules_sha256")
	return projected


static func _append_offers(out: PackedByteArray, rows: Array) -> void:
	_append_u32(out, rows.size())
	for row: Dictionary in rows:
		_append_string(out, String(row["offer_id"]))
		_append_string(out, String(row["operator_def_id"]))
		_append_i64(out, int(row["cost"]))
		out.append(1 if bool(row["consumed"]) else 0)


static func _append_heroes(out: PackedByteArray, rows: Array) -> void:
	_append_u32(out, rows.size())
	for row: Dictionary in rows:
		_append_string(out, String(row["hero_id"]))
		_append_string(out, String(row["acquisition_operator_def_id"]))
		_append_string(out, String(row["operator_def_id"]))
		_append_string(out, String(row["first_class_id"]))
		_append_nullable_string(out, row["advanced_class_id"])
		_append_u32(out, int(row["progression_rules_version"]))
		_append_i64(out, int(row["xp"]))
		_append_string(out, String(row["identity_portrait_id"]))
		_append_i64(out, int(row["recruitment_index"]))
		_append_i64(out, int(row["recruited_after_resolution_index"]))
		out.append(int(SOURCE_ENUM[String(row["recruit_source"])]))
		_append_string(out, String(row["source_id"]))
		_append_u32(out, int(row["name_version"]))
		_append_nullable_string(out, row["custom_callsign"])
		out.append(int(LIFE_ENUM[String(row["life_status"])]))
		_append_death_nullable(out, row["death"])


static func _append_promotion_receipts(
	out: PackedByteArray,
	rows: Array,
	current_revision: int,
) -> void:
	# Preserve every pre-promotion frozen hash. Once history exists, the section
	# marker and count make its boundary unambiguous. Only the receipt produced at
	# the current revision is self-referential; older after-hashes are state.
	if rows.is_empty():
		return
	out.append(0x50)
	_append_u32(out, rows.size())
	for row: Dictionary in rows:
		_append_u32(out, int(row["version"]))
		_append_string(out, String(row["command_id"]))
		_append_string(out, String(row["verb"]))
		_append_string(out, String(row["hero_id"]))
		_append_string(out, String(row["prior_class_id"]))
		_append_string(out, String(row["new_class_id"]))
		_append_string(out, String(row["prior_operator_def_id"]))
		_append_string(out, String(row["new_operator_def_id"]))
		_append_i64(out, int(row["prior_save_revision"]))
		_append_i64(out, int(row["new_save_revision"]))
		_append_string(out, String(row["before_strategic_hash"]))
		if int(row["new_save_revision"]) != current_revision:
			_append_string(out, String(row["after_strategic_hash"]))


static func _append_death_nullable(out: PackedByteArray, value: Variant) -> void:
	if value == null:
		out.append(0)
		return
	out.append(1)
	var row: Dictionary = value
	_append_i64(out, int(row["resolution_index"]))
	_append_i64(out, int(row["attempt_id"]))
	_append_string(out, String(row["stage_id"]))
	out.append(int(TERMINAL_ENUM[String(row["terminal_reason"])]))
	_append_i64(out, int(row["terminal_tick"]))


static func _append_resolution_nullable(out: PackedByteArray, value: Variant) -> void:
	if value == null:
		out.append(0)
		return
	out.append(1)
	var row: Dictionary = value
	_append_u32(out, int(row["schema_version"]))
	_append_i64(out, int(row["resolution_index"]))
	_append_string(out, String(row["campaign_uid"]))
	_append_i64(out, int(row["attempt_id"]))
	_append_string(out, String(row["stage_id"]))
	_append_string(out, String(row["outcome_hash"]))
	out.append(int(RESULT_ENUM[String(row["result"])]))
	out.append(int(TERMINAL_ENUM[String(row["terminal_reason"])]))
	_append_i64(out, int(row["terminal_tick"]))
	_append_u32(out, int(row["stars_before"]))
	_append_u32(out, int(row["stars_after"]))
	var rewards: Array = row["rewards_granted"]
	_append_u32(out, rewards.size())
	for reward: Dictionary in rewards:
		out.append(int(REWARD_ENUM[String(reward["kind"])]))
		_append_string(out, String(reward["id"]))
		_append_nullable_string(out, reward["hero_instance_id"])
	_append_strings(out, row["created_hero_ids"])
	_append_strings(out, row["dead_hero_ids"])
	var xp_awards: Array = row["xp_awards"]
	_append_u32(out, xp_awards.size())
	for award: Dictionary in xp_awards:
		_append_string(out, String(award["hero_id"]))
		_append_i64(out, int(award["delta"]))
	_append_i64(out, int(row["marks_before"]))
	_append_i64(out, int(row["marks_after"]))
	_append_string(out, String(row["strategic_body_hash_before"]))
	_append_string(out, String(row["strategic_body_hash_after"]))


static func _append_nullable_string(out: PackedByteArray, value: Variant) -> void:
	if value == null:
		out.append(0)
		return
	out.append(1)
	_append_string(out, String(value))


static func _append_string(out: PackedByteArray, value: String) -> void:
	var encoded := value.to_utf8_buffer()
	_append_u32(out, encoded.size())
	out.append_array(encoded)


static func _append_u32(out: PackedByteArray, value: int) -> void:
	for shift: int in range(0, 32, 8):
		out.append((value >> shift) & 0xFF)


static func _append_i64(out: PackedByteArray, value: int) -> void:
	for shift: int in range(0, 64, 8):
		out.append((value >> shift) & 0xFF)


static func derive_transaction(
	ticket: Variant,
	outcome: Variant,
	state_before: Variant,
	context: Dictionary,
) -> Dictionary:
	var encoded_ticket := CampaignCodec.encode_ticket(ticket)
	if not encoded_ticket["accepted"]:
		return _derive_reject(encoded_ticket["error_code"])
	var encoded_outcome := CampaignCodec.encode_outcome(outcome)
	if not encoded_outcome["accepted"]:
		return _derive_reject(encoded_outcome["error_code"])
	var before := CampaignCodec.normalize_data(state_before, context)
	if not before["accepted"]:
		return _derive_reject(&"invalid_transaction_state")
	return _derive_normalized_transaction(
		encoded_ticket["value"], encoded_outcome["value"], before["value"], context, true,
	)


static func _derive_certified_transaction(
	ticket: Variant,
	outcome: Variant,
	state_before: Dictionary,
	context: Dictionary,
) -> Dictionary:
	var encoded_ticket := CampaignCodec.encode_ticket(ticket)
	if not encoded_ticket["accepted"]:
		return _derive_reject(encoded_ticket["error_code"])
	var encoded_outcome := CampaignCodec.encode_outcome(outcome)
	if not encoded_outcome["accepted"]:
		return _derive_reject(encoded_outcome["error_code"])
	return _derive_normalized_transaction(
		encoded_ticket["value"], encoded_outcome["value"], state_before, context, false,
	)


static func _derive_normalized_transaction(
	ticket_value: Dictionary,
	outcome_value: Dictionary,
	before: Dictionary,
	context: Dictionary,
	full_after_validation: bool,
) -> Dictionary:
	var identity := _derive_identity(ticket_value, outcome_value, before)
	if not identity["accepted"]:
		return _derive_reject(identity["error_code"])
	var derived := _derive_fresh_receipt(
		ticket_value, outcome_value, before, context, full_after_validation,
	)
	if not derived["accepted"]:
		return _derive_reject(derived["error_code"])
	var validated := _validate_normalized_transaction(
		ticket_value, outcome_value, derived["resolution"], before,
		derived["state_after"], context,
	)
	if not validated["accepted"]:
		return _derive_reject(validated["error_code"])
	return {
		"accepted": true,
		"error_code": &"",
		"resolution": derived["resolution"],
		"state_after": derived["state_after"],
	}


static func _derive_identity(
	ticket: Dictionary,
	outcome: Dictionary,
	before: Dictionary,
) -> Dictionary:
	if ticket["campaign_uid"] != outcome["campaign_uid"]:
		return _reject(&"transaction_campaign_mismatch")
	if ticket["campaign_uid"] != before["campaign_uid"]:
		return _reject(&"transaction_campaign_mismatch")
	if ticket["attempt_id"] != outcome["attempt_id"]:
		return _reject(&"transaction_identity_mismatch")
	if ticket["stage_id"] != outcome["stage_id"]:
		return _reject(&"transaction_identity_mismatch")
	if ticket["manifest_hash"] != outcome["manifest_hash"]:
		return _reject(&"transaction_manifest_mismatch")
	if not _manifest_matches_outcome(ticket["manifest"], outcome["heroes"]):
		return _reject(&"transaction_roster_mismatch")
	if int(before["next_attempt_id"]) != int(ticket["attempt_id"]) + 1:
		return _reject(&"transaction_attempt_counter_mismatch")
	var owned := _heroes_by_id(before["heroes"])
	for row: Dictionary in ticket["manifest"]:
		var hero: Dictionary = owned.get(row["battle_id"], {})
		if hero.is_empty() or hero["operator_def_id"] != row["operator_def_id"]:
			return _reject(&"transaction_roster_mismatch")
		if hero["life_status"] != "ready" or hero["death"] != null:
			return _reject(&"transaction_roster_mismatch")
	return _accept()


static func _derive_fresh_receipt(
	ticket: Dictionary,
	outcome: Dictionary,
	before: Dictionary,
	context: Dictionary,
	full_after_validation: bool,
) -> Dictionary:
	var resolution_index := int(before["next_resolution_index"])
	var stars_before := _stage_stars(before, ticket["stage_id"])
	var stars_after := stars_before
	if outcome["result"] == "clear":
		stars_after = maxi(stars_before, int(outcome["stars"]))
	var expected := _transaction_working_copy(before)
	expected["save_revision"] = int(before["save_revision"]) + 1
	expected["next_resolution_index"] = resolution_index + 1
	_set_stage_stars(
		expected["stage_stars"], ticket["stage_id"], stars_after,
		resolution_index, int(ticket["attempt_id"]), int(outcome["terminal_tick"]),
	)
	var draft := {
		"resolution_index": resolution_index,
		"attempt_id": ticket["attempt_id"],
		"stage_id": ticket["stage_id"],
		"terminal_reason": outcome["terminal_reason"],
	}
	var rewards := _derive_rewards_and_heroes(before, expected, outcome, draft, context)
	if not rewards["accepted"]:
		return rewards
	var xp_awards := CampaignProgression.derive_xp_awards(
			outcome["heroes"],
			before["heroes"],
			CampaignProgression.xp_for_outcome(
				outcome["result"], outcome["terminal_reason"],
			),
	)
	_copy_awarded_hero_rows(expected["heroes"], xp_awards)
	if not CampaignProgression.apply_xp(expected["heroes"], xp_awards):
		return _reject(&"xp_overflow")
	var dead := _apply_casualties(expected, outcome, draft)
	if not dead["accepted"]:
		return dead
	expected["unlocked_traps"] = _expected_unlocks(before, rewards["authored"])
	var before_hash := _of_normalized_core(before)
	var after_hash := _of_normalized_core(expected)
	if not before_hash["accepted"] or not after_hash["accepted"]:
		return _reject(&"invalid_transaction_state")
	var resolution := {
		"schema_version": CampaignCodec.SAVE_VERSION,
		"resolution_index": resolution_index,
		"campaign_uid": ticket["campaign_uid"],
		"attempt_id": ticket["attempt_id"],
		"stage_id": ticket["stage_id"],
		"outcome_hash": outcome["outcome_hash"],
		"result": outcome["result"],
		"terminal_reason": outcome["terminal_reason"],
		"terminal_tick": outcome["terminal_tick"],
		"stars_before": stars_before,
		"stars_after": stars_after,
		"rewards_granted": rewards["rewards"],
		"created_hero_ids": rewards["created"],
		"dead_hero_ids": dead["value"],
		"xp_awards": xp_awards,
		"marks_before": before["marks"],
		"marks_after": expected["marks"],
		"strategic_body_hash_before": before_hash["hex"],
		"strategic_body_hash_after": after_hash["hex"],
	}
	expected["resolution_anchor"] = {
		"resolution_index": resolution_index,
		"save_revision_after": expected["save_revision"],
		"before_core": _core_snapshot(before),
		"after_core": _core_snapshot(expected),
		"strategic_body_hash_before": before_hash["hex"],
		"strategic_body_hash_after": after_hash["hex"],
	}
	expected["last_resolution"] = resolution.duplicate(true)
	var normalized_resolution := CampaignCodec.encode_resolution(resolution)
	if not normalized_resolution["accepted"]:
		return _reject(normalized_resolution["error_code"])
	var after_value := expected
	if full_after_validation:
		var normalized_after := CampaignCodec.normalize_data(expected, context)
		if not normalized_after["accepted"]:
			return _reject(&"invalid_transaction_state")
		after_value = normalized_after["value"]
	return {
		"accepted": true,
		"error_code": &"",
		"resolution": normalized_resolution["value"],
		"state_after": after_value,
	}


static func _derive_reject(code: StringName) -> Dictionary:
	return {
		"accepted": false,
		"error_code": code,
		"resolution": null,
		"state_after": null,
	}



static func validate_transaction(
	ticket: Variant,
	outcome: Variant,
	resolution: Variant,
	state_before: Variant,
	state_after: Variant,
	context: Dictionary,
) -> Dictionary:
	var encoded_ticket := CampaignCodec.encode_ticket(ticket)
	var encoded_outcome := CampaignCodec.encode_outcome(outcome)
	var encoded_resolution := CampaignCodec.encode_resolution(resolution)
	for encoded: Dictionary in [encoded_ticket, encoded_outcome, encoded_resolution]:
		if not encoded["accepted"]:
			return encoded
	var before := CampaignCodec.normalize_data(state_before, context)
	var after := CampaignCodec.normalize_data(state_after, context)
	if not before["accepted"] or not after["accepted"]:
		return _reject(&"invalid_transaction_state")
	return _validate_normalized_transaction(
		encoded_ticket["value"], encoded_outcome["value"], encoded_resolution["value"],
		before["value"], after["value"], context,
	)


static func _validate_normalized_transaction(
	ticket: Dictionary,
	outcome: Dictionary,
	resolution: Dictionary,
	before: Dictionary,
	after: Dictionary,
	context: Dictionary,
) -> Dictionary:
	var identity := _validate_identity(
		ticket, outcome, resolution,
	)
	if not identity["accepted"]:
		return identity
	var prior := _validate_before(
		ticket, resolution, before,
	)
	if not prior["accepted"]:
		return prior
	return _validate_after(outcome, resolution, before, after, context)


static func _validate_identity(
	ticket: Dictionary,
	outcome: Dictionary,
	resolution: Dictionary,
) -> Dictionary:
	for key: String in ["campaign_uid", "attempt_id", "stage_id"]:
		if ticket[key] != outcome[key] or ticket[key] != resolution[key]:
			return _reject(&"transaction_identity_mismatch")
	if ticket["manifest_hash"] != outcome["manifest_hash"]:
		return _reject(&"transaction_manifest_mismatch")
	if resolution["outcome_hash"] != outcome["outcome_hash"]:
		return _reject(&"transaction_outcome_hash_mismatch")
	for key: String in ["result", "terminal_reason"]:
		if outcome[key] != resolution[key]:
			return _reject(&"transaction_terminal_mismatch")
	if int(outcome["terminal_tick"]) != int(resolution["terminal_tick"]):
		return _reject(&"transaction_terminal_mismatch")
	if not _manifest_matches_outcome(ticket["manifest"], outcome["heroes"]):
		return _reject(&"transaction_roster_mismatch")
	return _accept()


static func _validate_before(
	ticket: Dictionary,
	resolution: Dictionary,
	before: Dictionary,
) -> Dictionary:
	if before["campaign_uid"] != ticket["campaign_uid"]:
		return _reject(&"transaction_campaign_mismatch")
	if int(before["next_attempt_id"]) != int(ticket["attempt_id"]) + 1:
		return _reject(&"transaction_attempt_counter_mismatch")
	if int(before["next_resolution_index"]) != int(resolution["resolution_index"]):
		return _reject(&"transaction_resolution_counter_mismatch")
	if int(before["marks"]) != int(resolution["marks_before"]):
		return _reject(&"transaction_marks_before_mismatch")
	if _stage_stars(before, ticket["stage_id"]) != int(resolution["stars_before"]):
		return _reject(&"transaction_stars_before_mismatch")
	var before_hash := _of_normalized_core(before)
	if not before_hash["accepted"]:
		return _reject(&"transaction_hash_before_mismatch")
	if before_hash["hex"] != resolution["strategic_body_hash_before"]:
		return _reject(&"transaction_hash_before_mismatch")
	var owned := _heroes_by_id(before["heroes"])
	for row: Dictionary in ticket["manifest"]:
		var hero: Dictionary = owned.get(row["battle_id"], {})
		if hero.is_empty() or hero["operator_def_id"] != row["operator_def_id"]:
			return _reject(&"transaction_roster_mismatch")
		if hero["life_status"] != "ready" or hero["death"] != null:
			return _reject(&"transaction_roster_mismatch")
	return _accept()


static func _validate_after(
	outcome: Dictionary,
	resolution: Dictionary,
	before: Dictionary,
	after: Dictionary,
	context: Dictionary,
) -> Dictionary:
	var derived := _derive_expected_after(outcome, resolution, before, context)
	if not derived["accepted"]:
		return derived
	var body_hash := _of_normalized_core(derived["value"])
	if not body_hash["accepted"] or body_hash["hex"] != resolution["strategic_body_hash_after"]:
		return _reject(&"transaction_hash_after_mismatch")
	var expected: Dictionary = derived["value"]
	if expected != after:
		return _reject(&"transaction_after_state_mismatch")
	return _accept()


static func _derive_expected_after(
	outcome: Dictionary,
	resolution: Dictionary,
	before: Dictionary,
	context: Dictionary,
) -> Dictionary:
	var expected := _transaction_working_copy(before)
	expected["save_revision"] = int(before["save_revision"]) + 1
	expected["next_resolution_index"] = int(resolution["resolution_index"]) + 1
	expected["marks"] = int(resolution["marks_after"])
	var stars_before := _stage_stars(before, outcome["stage_id"])
	var stars_after := stars_before
	if outcome["result"] == "clear":
		stars_after = maxi(stars_before, int(outcome["stars"]))
	var stars_mismatch := (
		int(resolution["stars_before"]) != stars_before
		or int(resolution["stars_after"]) != stars_after
	)
	if stars_mismatch:
		return _reject(&"transaction_stars_after_mismatch")
	_set_stage_stars(
		expected["stage_stars"], outcome["stage_id"], stars_after,
		int(resolution["resolution_index"]), int(resolution["attempt_id"]),
		int(outcome["terminal_tick"]),
	)
	var rewards := _derive_rewards_and_heroes(before, expected, outcome, resolution, context)
	if not rewards["accepted"]:
		return rewards
	if resolution["rewards_granted"] != rewards["rewards"]:
		return _reject(&"transaction_rewards_mismatch")
	if resolution["created_hero_ids"] != rewards["created"]:
		return _reject(&"transaction_created_hero_mismatch")
	var xp_awards := CampaignProgression.derive_xp_awards(
			outcome["heroes"],
			before["heroes"],
			CampaignProgression.xp_for_outcome(
				outcome["result"], outcome["terminal_reason"],
			),
	)
	if resolution["xp_awards"] != xp_awards:
		return _reject(&"transaction_xp_mismatch")
	_copy_awarded_hero_rows(expected["heroes"], xp_awards)
	if not CampaignProgression.apply_xp(expected["heroes"], xp_awards):
		return _reject(&"xp_overflow")
	var dead := _apply_casualties(expected, outcome, resolution)
	if not dead["accepted"]:
		return dead
	if resolution["dead_hero_ids"] != dead["value"]:
		return _reject(&"transaction_casualty_mismatch")
	expected["unlocked_traps"] = _expected_unlocks(before, rewards["authored"])
	expected["resolution_anchor"] = {
		"resolution_index": resolution["resolution_index"],
		"save_revision_after": expected["save_revision"],
		"before_core": _core_snapshot(before),
		"after_core": _core_snapshot(expected),
		"strategic_body_hash_before": resolution["strategic_body_hash_before"],
		"strategic_body_hash_after": resolution["strategic_body_hash_after"],
	}
	expected["last_resolution"] = resolution.duplicate(true)
	return {"accepted": true, "error_code": &"", "value": expected}


static func _derive_rewards_and_heroes(
	before: Dictionary,
	expected: Dictionary,
	outcome: Dictionary,
	resolution: Dictionary,
	context: Dictionary,
) -> Dictionary:
	var authored: Array = []
	if outcome["result"] == "clear" and _stage_stars(before, outcome["stage_id"]) == 0:
		authored = context["stage_rewards"][outcome["stage_id"]]
	var rewards: Array = []
	var created: Array[String] = []
	var taken := _heroes_by_id(expected["heroes"])
	var recruitment_index := int(before["next_recruitment_index"])
	for reward: Dictionary in authored:
		var hero_id: Variant = null
		if reward["kind"] == "operator":
			var allocated := HeroIdentity.allocate_hero_id(
				int(before["campaign_seed"]), int(before["campaign_generation"]),
				recruitment_index, func(candidate: String) -> bool: return taken.has(candidate),
			)
			if not allocated["accepted"]:
				return _reject(&"transaction_created_hero_mismatch")
			hero_id = allocated["hero_id"]
			created.append(hero_id)
			taken[hero_id] = true
			var new_hero := CampaignProgression.add_initial_fields({
				"hero_id": hero_id,
				"operator_def_id": reward["id"],
				"recruitment_index": recruitment_index,
				"recruited_after_resolution_index": resolution["resolution_index"],
				"recruit_source": "reward",
				"source_id": outcome["stage_id"],
				"name_version": HeroNames.VERSION,
				"custom_callsign": null,
				"life_status": "ready",
				"death": null,
			})
			if new_hero.is_empty():
				return _reject(&"transaction_created_hero_mismatch")
			expected["heroes"].append(new_hero)
			recruitment_index += 1
		rewards.append({"kind": reward["kind"], "id": reward["id"], "hero_instance_id": hero_id})
	expected["next_recruitment_index"] = recruitment_index
	return {
		"accepted": true,
		"error_code": &"",
		"rewards": rewards,
		"created": created,
		"authored": authored,
	}


static func _apply_casualties(
	expected: Dictionary,
	outcome: Dictionary,
	resolution: Dictionary,
) -> Dictionary:
	var dead: Array[String] = []
	for row: Dictionary in outcome["heroes"]:
		if not bool(row["fell"]):
			continue
		var hero_index := _hero_index(expected["heroes"], String(row["hero_id"]))
		if hero_index < 0:
			return _reject(&"transaction_casualty_mismatch")
		var hero: Dictionary = expected["heroes"][hero_index].duplicate(true)
		hero["life_status"] = "dead"
		hero["death"] = {
			"resolution_index": resolution["resolution_index"],
			"attempt_id": resolution["attempt_id"],
			"stage_id": resolution["stage_id"],
			"terminal_reason": resolution["terminal_reason"],
				"terminal_tick": outcome["terminal_tick"],
		}
		expected["heroes"][hero_index] = hero
		dead.append(String(row["hero_id"]))
	return {"accepted": true, "error_code": &"", "value": dead}


static func _copy_awarded_hero_rows(rows: Array, awards: Array) -> void:
	var awarded := {}
	for award: Dictionary in awards:
		awarded[String(award["hero_id"])] = true
	for index: int in rows.size():
		if awarded.has(String(rows[index]["hero_id"])):
			rows[index] = (rows[index] as Dictionary).duplicate(true)


static func _set_stage_stars(
	rows: Array,
	stage_id: String,
	stars: int,
	resolution_index: int,
	attempt_id: int,
	terminal_tick: int,
) -> void:
	for row: Dictionary in rows:
		if row["stage_id"] == stage_id:
			row["stars"] = stars
			return
	if stars > 0:
		rows.append({
			"stage_id": stage_id,
			"stars": stars,
			"first_clear_resolution_index": resolution_index,
			"first_clear_attempt_id": attempt_id,
			"first_clear_terminal_tick": terminal_tick,
		})


static func _manifest_matches_outcome(manifest: Array, heroes: Array) -> bool:
	if manifest.size() != heroes.size():
		return false
	for index: int in manifest.size():
		if manifest[index]["battle_id"] != heroes[index]["hero_id"]:
			return false
		if manifest[index]["operator_def_id"] != heroes[index]["operator_def_id"]:
			return false
	return true


static func _expected_unlocks(before: Dictionary, rewards: Array) -> Array:
	var traps: Array = before["unlocked_traps"].duplicate()
	for reward: Dictionary in rewards:
		if reward["kind"] == "trap" and not traps.has(reward["id"]):
			traps.append(reward["id"])
	traps.sort()
	return traps


static func _stage_stars(data: Dictionary, stage_id: String) -> int:
	for row: Dictionary in data["stage_stars"]:
		if row["stage_id"] == stage_id:
			return int(row["stars"])
	return 0


static func _heroes_by_id(rows: Array) -> Dictionary:
	var result := {}
	for row: Dictionary in rows:
		result[row["hero_id"]] = row
	return result


static func _hero_index(rows: Array, hero_id: String) -> int:
	for index: int in rows.size():
		if rows[index]["hero_id"] == hero_id:
			return index
	return -1


static func _transaction_working_copy(data: Dictionary) -> Dictionary:
	var working := data.duplicate()
	working["stage_stars"] = (data["stage_stars"] as Array).duplicate(true)
	working["unlocked_traps"] = (data["unlocked_traps"] as Array).duplicate()
	working["offers"] = (data["offers"] as Array).duplicate(true)
	working["heroes"] = (data["heroes"] as Array).duplicate()
	return working


static func _core_snapshot(data: Dictionary) -> Dictionary:
	var snapshot: Dictionary = data.duplicate()
	snapshot.erase("resolution_anchor")
	snapshot.erase("last_resolution")
	return snapshot


static func _accept() -> Dictionary:
	return {"accepted": true, "error_code": &""}


static func _reject(code: StringName) -> Dictionary:
	return {"accepted": false, "error_code": code}
