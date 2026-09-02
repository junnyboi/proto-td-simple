class_name CampaignCodec
extends RefCounted
const CampaignHeroCodec := preload("res://sim/campaign_hero_codec.gd")
const CampaignContextValidatorScript := preload("res://sim/campaign_context_validator.gd")
const CampaignProgression := preload("res://sim/campaign_progression.gd")
const CombatContentBindingScript := preload("res://sim/combat_content_binding.gd")
const CanonicalJson := preload("res://sim/canonical_json.gd")
const HeroIdentity := preload("res://sim/hero_identity.gd")
const HeroNames := preload("res://sim/hero_names.gd")
const PromotionReceiptCodecScript := preload("res://sim/campaign_promotion_receipt_codec.gd")
const PromotionProofCodecScript := preload("res://sim/campaign_promotion_proof_codec.gd")
const PromotionSnapshotCodecScript := preload("res://sim/campaign_promotion_snapshot_codec.gd")
const SaveUpgradeScript := preload("res://sim/campaign_save_upgrade.gd")
const V3_CODEC_PATH := "res://sim/campaign_v3_codec.gd"
const SAVE_SCHEMA := "prototype_td_campaign"
const LEGACY_SAVE_VERSION := 1
const SAVE_VERSION := 2
const RECRUIT_SAVE_VERSION := 3
const TERMINAL_VALUES := ["clear", "leak_defeat", "base_defeat", "resign"]
const RESULT_VALUES := ["clear", "defeat"]
const REWARD_VALUES := ["operator", "trap"]
const U32_MAX := 4_294_967_295
const U63_MAX := 9_223_372_036_854_775_807
const MARKS_MAX := 1_000_000_000
const MAX_ROSTER := 1024
const DATA_KEYS := [
	"campaign_uid", "campaign_seed", "campaign_generation", "save_revision",
	"next_recruitment_index", "next_attempt_id", "next_resolution_index", "marks",
	"combat_rules_sha256",
	"stage_stars", "unlocked_traps", "offers", "heroes",
	"promotion_receipts", "promotion_proofs", "resolution_anchor", "last_resolution",
]
const CORE_KEYS := [
	"campaign_uid", "campaign_seed", "campaign_generation", "save_revision",
	"next_recruitment_index", "next_attempt_id", "next_resolution_index", "marks",
	"combat_rules_sha256",
	"stage_stars", "unlocked_traps", "offers", "heroes",
	"promotion_receipts", "promotion_proofs",
]
const RESOLUTION_KEYS := [
	"schema_version", "resolution_index", "campaign_uid", "attempt_id", "stage_id",
	"outcome_hash", "result", "terminal_reason", "terminal_tick", "stars_before", "stars_after",
	"rewards_granted", "created_hero_ids", "dead_hero_ids", "xp_awards", "marks_before",
	"marks_after", "strategic_body_hash_before", "strategic_body_hash_after",
]
const ANCHOR_KEYS := [
	"resolution_index", "save_revision_after",
	"before_core", "after_core",
	"strategic_body_hash_before", "strategic_body_hash_after",
]
const PROMOTION_RECEIPT_KEYS := PromotionReceiptCodecScript.RECEIPT_KEYS
static func normalize_data(data: Variant, context: Dictionary = {}) -> Dictionary:
	if not _valid_context(context):
		return _reject(&"missing_validation_context")
	if SaveUpgradeScript.needs_upgrade(data):
		data = SaveUpgradeScript.upgrade(data, context)
	if typeof(data) != TYPE_DICTIONARY or not _exact_keys(data, DATA_KEYS):
		return _reject(&"invalid_data_schema")
	var core_input := {}
	for key: String in CORE_KEYS:
		core_input[key] = data[key]
	var core := normalize_core_snapshot(core_input, context)
	if not core["accepted"]:
		return core
	var last_resolution: Variant = null
	if data["last_resolution"] != null:
		var normalized_resolution := normalize_resolution(data["last_resolution"])
		if not normalized_resolution["accepted"]:
			return normalized_resolution
		last_resolution = normalized_resolution["value"]
	var resolution_anchor := _normalize_anchor(data["resolution_anchor"], context)
	if not resolution_anchor["accepted"]:
		return resolution_anchor
	var ordered: Dictionary = core["value"].duplicate(true)
	ordered["resolution_anchor"] = resolution_anchor["value"]
	ordered["last_resolution"] = last_resolution
	var invariants := _validate_data_invariants(ordered, context)
	return _accept(ordered) if invariants["accepted"] else invariants
static func normalize_core_snapshot(value: Variant, context: Dictionary) -> Dictionary:
	if not _valid_context(context):
		return _reject(&"missing_validation_context")
	if typeof(value) != TYPE_DICTIONARY or not _exact_keys(value, CORE_KEYS):
		return _reject(&"invalid_core_snapshot")
	var uid := String(value["campaign_uid"])
	if not _is_hex(uid, 16):
		return _reject(&"invalid_campaign_uid")
	for key: String in [
		"campaign_seed", "campaign_generation", "save_revision", "next_recruitment_index",
		"next_attempt_id", "next_resolution_index", "marks",
	]:
		if not _is_integer(value[key]):
			return _reject(&"invalid_integer")
	if not _in_range(value["campaign_generation"], 1, U63_MAX):
		return _reject(&"invalid_counter")
	if not _in_range(value["save_revision"], 1, U63_MAX):
		return _reject(&"invalid_counter")
	if not _in_range(value["next_recruitment_index"], 0, U63_MAX):
		return _reject(&"invalid_counter")
	if not _in_range(value["next_attempt_id"], 1, U63_MAX):
		return _reject(&"invalid_counter")
	if not _in_range(value["next_resolution_index"], 1, U63_MAX):
		return _reject(&"invalid_counter")
	if not _in_range(value["marks"], 0, MARKS_MAX):
		return _reject(&"invalid_counter")
	if not _is_hex(String(value["combat_rules_sha256"]), 64):
		return _reject(&"invalid_combat_rules_hash")
	if String(value["combat_rules_sha256"]) != String(context["combat_rules_sha256"]):
		return _reject(&"combat_rules_mismatch")
	var stage_rows := _normalize_stage_rows(value["stage_stars"])
	if not stage_rows["accepted"]:
		return stage_rows
	var traps := _normalize_string_array(value["unlocked_traps"])
	if not traps["accepted"]:
		return _reject(&"invalid_unlocks")
	var offers := _normalize_offers(value["offers"])
	if not offers["accepted"]:
		return offers
	var heroes := _normalize_heroes(value["heroes"])
	if not heroes["accepted"]:
		return heroes
	if (heroes["value"] as Array).is_empty() or (heroes["value"] as Array).size() > MAX_ROSTER:
		return _reject(&"empty_roster")
	var promotion_receipts := normalize_promotion_receipts(value["promotion_receipts"])
	if not promotion_receipts["accepted"]:
		return promotion_receipts
	var promotion_proofs := PromotionProofCodecScript.normalize(
		value["promotion_proofs"],
		func(snapshot: Variant) -> Dictionary:
			return _normalize_promotion_snapshot(snapshot, context),
	)
	if not promotion_proofs["accepted"]:
		return promotion_proofs
	var ordered := {}
	ordered["campaign_uid"] = uid
	ordered["campaign_seed"] = int(value["campaign_seed"])
	ordered["campaign_generation"] = int(value["campaign_generation"])
	ordered["save_revision"] = int(value["save_revision"])
	ordered["next_recruitment_index"] = int(value["next_recruitment_index"])
	ordered["next_attempt_id"] = int(value["next_attempt_id"])
	ordered["next_resolution_index"] = int(value["next_resolution_index"])
	ordered["marks"] = int(value["marks"])
	ordered["combat_rules_sha256"] = String(value["combat_rules_sha256"])
	ordered["stage_stars"] = stage_rows["value"]
	ordered["unlocked_traps"] = traps["value"]
	ordered["offers"] = offers["value"]
	ordered["heroes"] = heroes["value"]
	ordered["promotion_receipts"] = promotion_receipts["value"]
	ordered["promotion_proofs"] = promotion_proofs["value"]
	var invariants := _validate_core_snapshot_invariants(ordered, context)
	return _accept(ordered) if invariants["accepted"] else invariants
static func _normalize_anchor(value: Variant, context: Dictionary) -> Dictionary:
	if value == null:
		return _accept(null)
	if typeof(value) != TYPE_DICTIONARY or not _exact_keys(value, ANCHOR_KEYS):
		return _reject(&"invalid_resolution_anchor")
	if not _in_range(value["resolution_index"], 1, U63_MAX):
		return _reject(&"invalid_resolution_anchor")
	if not _in_range(value["save_revision_after"], 1, U63_MAX):
		return _reject(&"invalid_resolution_anchor")
	var before_core := normalize_core_snapshot(value["before_core"], context)
	var after_core := normalize_core_snapshot(value["after_core"], context)
	if not before_core["accepted"] or not after_core["accepted"]:
		return _reject(&"invalid_resolution_anchor")
	for key: String in ["strategic_body_hash_before", "strategic_body_hash_after"]:
		if not _is_hex(String(value[key]), 16):
			return _reject(&"invalid_resolution_anchor")
	var ordered := {}
	for key: String in ANCHOR_KEYS:
		if key == "before_core":
			ordered[key] = before_core["value"]
		elif key == "after_core":
			ordered[key] = after_core["value"]
		elif key in ["resolution_index", "save_revision_after"]:
			ordered[key] = int(value[key])
		else:
			ordered[key] = String(value[key])
	return _accept(ordered)
static func encode_data(data: Variant, context: Dictionary = {}) -> Dictionary:
	var normalized := normalize_data(data, context)
	if not normalized["accepted"]:
		return normalized
	return _encoded(normalized["value"])
static func encode_save(data: Variant, context: Dictionary = {}) -> Dictionary:
	var encoded_data := encode_data(data, context)
	if not encoded_data["accepted"]:
		return encoded_data
	var root := {}
	root["schema"] = SAVE_SCHEMA
	root["version"] = SAVE_VERSION
	root["checksum"] = encoded_data["sha256"]
	root["data"] = encoded_data["value"]
	return _encoded(root)
static func encode_save_v3(data: Variant, context: Dictionary) -> Dictionary:
	return (load(V3_CODEC_PATH) as GDScript).encode_save(data, context)
static func decode_save(source: String, context: Dictionary = {}) -> Dictionary:
	if not source.ends_with("\n") or source.ends_with("\n\n") or source.contains("\r"):
		return _reject(&"noncanonical_save")
	var parser := JSON.new()
	if parser.parse(source) != OK:
		return _reject(&"malformed_json")
	var coerced := CanonicalJson.restore_exact_integers(source, parser.data)
	if not coerced["accepted"]:
		return coerced
	var parsed: Variant = coerced["value"]
	if typeof(parsed) != TYPE_DICTIONARY:
		return _reject(&"malformed_json")
	if not _exact_keys(parsed, ["schema", "version", "checksum", "data"]):
		return _reject(&"invalid_root_schema")
	if parsed["schema"] != SAVE_SCHEMA or not _is_integer(parsed["version"]):
		return _reject(&"unsupported_save")
	var source_version := int(parsed["version"])
	if source_version == RECRUIT_SAVE_VERSION:
		return (load(V3_CODEC_PATH) as GDScript).decode_parsed(parsed, source, context)
	if source_version not in [LEGACY_SAVE_VERSION, SAVE_VERSION]:
		return _reject(&"unsupported_save")
	if context.has("environment_sha256"):
		return (load(V3_CODEC_PATH) as GDScript).migrate_legacy_source(source, context)
	if not _is_hex(String(parsed["checksum"]), 64):
		return _reject(&"invalid_checksum")
	var upgraded := SaveUpgradeScript.decode(
		parsed, source, context,
		func(data: Variant, save_context: Dictionary) -> Dictionary:
			return encode_save(data, save_context),
	)
	if upgraded["handled"]:
		return upgraded["result"]
	var encoded_data := encode_data(parsed["data"], context)
	if not encoded_data["accepted"]:
		return encoded_data
	if String(parsed["checksum"]) != String(encoded_data["sha256"]):
		return _reject(&"checksum_mismatch")
	var encoded_save := encode_save(encoded_data["value"], context)
	if encoded_save["text"] != source:
		return _reject(&"noncanonical_save")
	return {
		"accepted": true,
		"error_code": &"",
		"data": encoded_data["value"],
		"value": encoded_save["value"],
		"text": encoded_save["text"],
		"bytes": encoded_save["bytes"],
		"sha256": encoded_save["sha256"],
		"migrated_from_version": null,
	}
static func encode_manifest(rows: Variant) -> Dictionary:
	var normalized := _normalize_manifest(rows)
	if not normalized["accepted"]:
		return normalized
	return _encoded(normalized["value"])
static func encode_ticket(ticket: Variant) -> Dictionary:
	var keys := ["campaign_uid", "attempt_id", "stage_id", "manifest", "manifest_hash"]
	if typeof(ticket) != TYPE_DICTIONARY or not _exact_keys(ticket, keys):
		return _reject(&"invalid_ticket_schema")
	var manifest := _normalize_manifest(ticket["manifest"])
	if not manifest["accepted"]:
		return manifest
	if not _is_hex(String(ticket["campaign_uid"]), 16):
		return _reject(&"invalid_campaign_uid")
	if not _in_range(ticket["attempt_id"], 1, U63_MAX):
		return _reject(&"invalid_attempt_id")
	if not _is_ascii_string(ticket["stage_id"]) or not _is_hex(String(ticket["manifest_hash"]), 64):
		return _reject(&"invalid_ticket_value")
	var ordered := {}
	for key: String in keys:
		match key:
			"manifest": ordered[key] = manifest["value"]
			"attempt_id": ordered[key] = int(ticket[key])
			_: ordered[key] = ticket[key]
	if CanonicalJson.sha256_hex(manifest["value"]) != String(ticket["manifest_hash"]):
		return _reject(&"manifest_hash_mismatch")
	return _encoded(ordered)
static func encode_outcome_body(outcome: Variant) -> Dictionary:
	return _encode_outcome(outcome, false)
static func encode_outcome(outcome: Variant) -> Dictionary:
	return _encode_outcome(outcome, true)
static func normalize_resolution(resolution: Variant) -> Dictionary:
	if typeof(resolution) != TYPE_DICTIONARY or not _exact_keys(resolution, RESOLUTION_KEYS):
		return _reject(&"invalid_resolution_schema")
	for key: String in [
		"schema_version", "resolution_index", "attempt_id", "terminal_tick",
		"stars_before", "stars_after",
		"marks_before", "marks_after",
	]:
		if not _is_integer(resolution[key]):
			return _reject(&"invalid_integer")
	if int(resolution["schema_version"]) != 2:
		return _reject(&"invalid_resolution_value")
	if not _in_range(resolution["resolution_index"], 1, U63_MAX):
		return _reject(&"invalid_resolution_value")
	if not _in_range(resolution["attempt_id"], 1, U63_MAX):
		return _reject(&"invalid_resolution_value")
	if not _in_range(resolution["terminal_tick"], 0, U63_MAX):
		return _reject(&"invalid_resolution_value")
	for key: String in ["stars_before", "stars_after"]:
		if not _in_range(resolution[key], 0, 3):
			return _reject(&"invalid_resolution_value")
	for key: String in ["marks_before", "marks_after"]:
		if not _in_range(resolution[key], 0, MARKS_MAX):
			return _reject(&"invalid_resolution_value")
	if not _is_hex(String(resolution["campaign_uid"]), 16):
		return _reject(&"invalid_campaign_uid")
	if not _is_ascii_string(resolution["stage_id"]):
		return _reject(&"invalid_resolution_value")
	if not _is_hex(String(resolution["outcome_hash"]), 64):
		return _reject(&"invalid_outcome_hash")
	if not _is_hex(String(resolution["strategic_body_hash_before"]), 16):
		return _reject(&"invalid_strategic_hash")
	if not _is_hex(String(resolution["strategic_body_hash_after"]), 16):
		return _reject(&"invalid_strategic_hash")
	if not RESULT_VALUES.has(String(resolution["result"])):
		return _reject(&"invalid_result")
	if not TERMINAL_VALUES.has(String(resolution["terminal_reason"])):
		return _reject(&"invalid_terminal_reason")
	var rewards := _normalize_rewards(resolution["rewards_granted"])
	var created := _normalize_hero_id_array(resolution["created_hero_ids"])
	var dead := _normalize_hero_id_array(resolution["dead_hero_ids"])
	var xp_awards := _normalize_xp_awards(resolution["xp_awards"])
	if (
		not rewards["accepted"] or not created["accepted"]
		or not dead["accepted"] or not xp_awards["accepted"]
	):
		return _reject(&"invalid_resolution_rows")
	var operator_created: Array[String] = []
	for reward: Dictionary in rewards["value"]:
		if reward["kind"] == "operator":
			operator_created.append(String(reward["hero_instance_id"]))
	if operator_created != created["value"]:
		return _reject(&"resolution_created_mismatch")
	if int(resolution["marks_before"]) != int(resolution["marks_after"]):
		return _reject(&"resolution_marks_mismatch")
	var result := String(resolution["result"])
	var reason := String(resolution["terminal_reason"])
	if result == "clear":
		if reason != "clear" or int(resolution["stars_after"]) < 1:
			return _reject(&"invalid_resolution_terminal")
		if int(resolution["stars_after"]) < int(resolution["stars_before"]):
			return _reject(&"invalid_resolution_terminal")
	else:
		if reason == "clear" or int(resolution["stars_after"]) != int(resolution["stars_before"]):
			return _reject(&"invalid_resolution_terminal")
		if not (rewards["value"] as Array).is_empty() or not operator_created.is_empty():
			return _reject(&"invalid_resolution_terminal")
	var ordered := {}
	for key: String in RESOLUTION_KEYS:
		match key:
			"rewards_granted": ordered[key] = rewards["value"]
			"created_hero_ids": ordered[key] = created["value"]
			"dead_hero_ids": ordered[key] = dead["value"]
			"xp_awards": ordered[key] = xp_awards["value"]
			_:
				var numeric := key in [
					"schema_version", "resolution_index", "attempt_id", "terminal_tick", "stars_before",
					"stars_after", "marks_before", "marks_after",
				]
				ordered[key] = int(resolution[key]) if numeric else resolution[key]
	return _accept(ordered)
static func encode_resolution(resolution: Variant) -> Dictionary:
	var normalized := normalize_resolution(resolution)
	if not normalized["accepted"]:
		return normalized
	return _encoded(normalized["value"])

static func normalize_promotion_receipts(value: Variant) -> Dictionary:
	return PromotionReceiptCodecScript.normalize(value)

static func _normalize_promotion_snapshot(value: Variant, context: Dictionary) -> Dictionary:
	return PromotionSnapshotCodecScript.normalize(
		value, context, DATA_KEYS, CORE_KEYS,
		func(core: Variant, core_context: Dictionary) -> Dictionary:
			return normalize_core_snapshot(core, core_context),
		func(resolution: Variant) -> Dictionary:
			return normalize_resolution(resolution),
		func(anchor: Variant, anchor_context: Dictionary) -> Dictionary:
			return _normalize_anchor(anchor, anchor_context),
	)

static func _encode_outcome(outcome: Variant, include_hash: bool) -> Dictionary:
	var keys := [
		"schema_version", "campaign_uid", "attempt_id", "stage_id", "manifest_hash",
		"result", "terminal_reason", "stars", "terminal_tick", "model_state_hash", "heroes",
	]
	if include_hash:
		keys.append("outcome_hash")
	if typeof(outcome) != TYPE_DICTIONARY or not _exact_keys(outcome, keys):
		return _reject(&"invalid_outcome_schema")
	for key: String in ["schema_version", "attempt_id", "stars", "terminal_tick"]:
		if not _is_integer(outcome[key]):
			return _reject(&"invalid_integer")
	if int(outcome["schema_version"]) != 1 or not _in_range(outcome["attempt_id"], 1, U63_MAX):
		return _reject(&"invalid_outcome_value")
	if not _in_range(outcome["stars"], 0, 3):
		return _reject(&"invalid_outcome_value")
	if not _in_range(outcome["terminal_tick"], 0, U63_MAX):
		return _reject(&"invalid_outcome_value")
	for key: String in ["campaign_uid", "model_state_hash"]:
		if not _is_hex(String(outcome[key]), 16):
			return _reject(&"invalid_outcome_hash")
	if not _is_hex(String(outcome["manifest_hash"]), 64):
		return _reject(&"invalid_manifest_hash")
	if not _is_ascii_string(outcome["stage_id"]):
		return _reject(&"invalid_outcome_value")
	if not RESULT_VALUES.has(String(outcome["result"])):
		return _reject(&"invalid_result")
	if not TERMINAL_VALUES.has(String(outcome["terminal_reason"])):
		return _reject(&"invalid_terminal_reason")
	var result := String(outcome["result"])
	var reason := String(outcome["terminal_reason"])
	if result == "clear" and (reason != "clear" or int(outcome["stars"]) < 1):
		return _reject(&"invalid_outcome_terminal")
	if result == "defeat" and (reason == "clear" or int(outcome["stars"]) != 0):
		return _reject(&"invalid_outcome_terminal")
	var heroes := _normalize_outcome_heroes(outcome["heroes"])
	if not heroes["accepted"]:
		return heroes
	for hero: Dictionary in heroes["value"]:
		var fell_after_terminal := (
			hero["first_fall_tick"] != null
			and int(hero["first_fall_tick"]) > int(outcome["terminal_tick"])
		)
		if fell_after_terminal:
			return _reject(&"invalid_outcome_hero")
	var ordered := {}
	for key: String in keys:
		match key:
			"heroes": ordered[key] = heroes["value"]
			"schema_version", "attempt_id", "stars", "terminal_tick":
				ordered[key] = int(outcome[key])
			_: ordered[key] = outcome[key]
	if include_hash:
		if not _is_hex(String(outcome["outcome_hash"]), 64):
			return _reject(&"invalid_outcome_hash")
		var body := ordered.duplicate()
		body.erase("outcome_hash")
		if CanonicalJson.sha256_hex(body) != String(outcome["outcome_hash"]):
			return _reject(&"outcome_hash_mismatch")
	return _encoded(ordered)
static func _normalize_stage_rows(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return _reject(&"invalid_stage_stars")
	var out: Array = []
	var seen := {}
	var previous := ""
	var previous_resolution := 0
	var previous_attempt := 0
	for row: Variant in value:
		var keys := [
			"stage_id", "stars", "first_clear_resolution_index",
			"first_clear_attempt_id", "first_clear_terminal_tick",
		]
		if typeof(row) != TYPE_DICTIONARY or not _exact_keys(row, keys):
			return _reject(&"invalid_stage_stars")
		if not _is_ascii_string(row["stage_id"]) or not _is_integer(row["stars"]):
			return _reject(&"invalid_stage_stars")
		if not _in_range(row["first_clear_resolution_index"], 1, U63_MAX):
			return _reject(&"invalid_stage_stars")
		if not _in_range(row["first_clear_attempt_id"], 1, U63_MAX):
			return _reject(&"invalid_stage_stars")
		if not _in_range(row["first_clear_terminal_tick"], 0, U63_MAX):
			return _reject(&"invalid_stage_stars")
		if int(row["stars"]) < 1 or int(row["stars"]) > 3 or seen.has(String(row["stage_id"])):
			return _reject(&"invalid_stage_stars")
		var stage_id := String(row["stage_id"])
		if not previous.is_empty() and stage_id <= previous:
			return _reject(&"noncanonical_stage_order")
		if int(row["first_clear_resolution_index"]) <= previous_resolution:
			return _reject(&"noncanonical_stage_history")
		if int(row["first_clear_attempt_id"]) <= previous_attempt:
			return _reject(&"noncanonical_stage_history")
		previous = stage_id
		previous_resolution = int(row["first_clear_resolution_index"])
		previous_attempt = int(row["first_clear_attempt_id"])
		seen[stage_id] = true
		out.append({
			"stage_id": stage_id,
			"stars": int(row["stars"]),
			"first_clear_resolution_index": int(row["first_clear_resolution_index"]),
			"first_clear_attempt_id": int(row["first_clear_attempt_id"]),
			"first_clear_terminal_tick": int(row["first_clear_terminal_tick"]),
		})
	return _accept(out)
static func _normalize_string_array(value: Variant, sort_values: bool = true) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return _reject(&"invalid_string_array")
	var out: Array[String] = []
	var previous := ""
	for item: Variant in value:
		var current := String(item)
		if not _is_ascii_string(item) or out.has(current):
			return _reject(&"invalid_string_array")
		if sort_values and not previous.is_empty() and current <= previous:
			return _reject(&"noncanonical_string_order")
		previous = current
		out.append(current)
	return _accept(out)
static func _normalize_hero_id_array(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return _reject(&"invalid_hero_id_array")
	var out: Array[String] = []
	for item: Variant in value:
		var hero_id := String(item)
		if not _is_hex(hero_id, 16) or out.has(hero_id):
			return _reject(&"invalid_hero_id_array")
		out.append(hero_id)
	return _accept(out)

static func _normalize_xp_awards(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return _reject(&"invalid_xp_awards")
	var out: Array[Dictionary] = []
	var previous := ""
	for item: Variant in value:
		if typeof(item) != TYPE_DICTIONARY:
			return _reject(&"invalid_xp_awards")
		var row := item as Dictionary
		if not _exact_keys(row, ["hero_id", "delta"]):
			return _reject(&"invalid_xp_awards")
		var hero_id := String(row["hero_id"])
		if not _is_hex(hero_id, 16) or not _is_integer(row["delta"]):
			return _reject(&"invalid_xp_awards")
		if int(row["delta"]) <= 0 or int(row["delta"]) > U63_MAX:
			return _reject(&"invalid_xp_awards")
		if not previous.is_empty() and hero_id <= previous:
			return _reject(&"noncanonical_xp_award_order")
		previous = hero_id
		out.append({"hero_id": hero_id, "delta": int(row["delta"])})
	return _accept(out)

static func _normalize_offers(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return _reject(&"invalid_offers")
	var out: Array = []
	var seen := {}
	var previous := ""
	for row: Variant in value:
		var keys := ["offer_id", "operator_def_id", "cost", "consumed"]
		if typeof(row) != TYPE_DICTIONARY or not _exact_keys(row, keys):
			return _reject(&"invalid_offer")
		if not _is_ascii_string(row["offer_id"]) or not _is_ascii_string(row["operator_def_id"]):
			return _reject(&"invalid_offer")
		if not _is_integer(row["cost"]) or typeof(row["consumed"]) != TYPE_BOOL:
			return _reject(&"invalid_offer")
		if not _in_range(row["cost"], 0, MARKS_MAX) or seen.has(String(row["offer_id"])):
			return _reject(&"invalid_offer")
		var offer_id := String(row["offer_id"])
		if not previous.is_empty() and offer_id <= previous:
			return _reject(&"noncanonical_offer_order")
		previous = offer_id
		seen[offer_id] = true
		var ordered := {}
		for key: String in keys:
			ordered[key] = int(row[key]) if key == "cost" else row[key]
		out.append(ordered)
	return _accept(out)
static func _normalize_heroes(value: Variant) -> Dictionary:
	return CampaignHeroCodec.normalize_heroes(value)
static func _normalize_manifest(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_ARRAY or (value as Array).is_empty():
		return _reject(&"invalid_manifest")
	var out: Array = []
	var seen := {}
	for row: Variant in value:
		if typeof(row) != TYPE_DICTIONARY or not _exact_keys(row, ["battle_id", "operator_def_id"]):
			return _reject(&"invalid_manifest")
		var battle_id := String(row["battle_id"])
		if not _is_hex(battle_id, 16) or not _is_ascii_string(row["operator_def_id"]):
			return _reject(&"invalid_manifest")
		if seen.has(battle_id):
			return _reject(&"duplicate_manifest_id")
		seen[battle_id] = true
		out.append({"battle_id": battle_id, "operator_def_id": String(row["operator_def_id"])})
	return _accept(out)
static func _normalize_outcome_heroes(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_ARRAY or (value as Array).is_empty():
		return _reject(&"invalid_outcome_heroes")
	var keys := ["hero_id", "operator_def_id", "deployments", "retreats", "fell", "first_fall_tick"]
	var out: Array = []
	var seen := {}
	for row: Variant in value:
		if typeof(row) != TYPE_DICTIONARY or not _exact_keys(row, keys):
			return _reject(&"invalid_outcome_hero")
		if not _is_hex(String(row["hero_id"]), 16) or not _is_ascii_string(row["operator_def_id"]):
			return _reject(&"invalid_outcome_hero")
		if not _in_range(row["deployments"], 0, U32_MAX):
			return _reject(&"invalid_outcome_hero")
		if not _in_range(row["retreats"], 0, U32_MAX):
			return _reject(&"invalid_outcome_hero")
		if typeof(row["fell"]) != TYPE_BOOL:
			return _reject(&"invalid_outcome_hero")
		if bool(row["fell"]) != (row["first_fall_tick"] != null):
			return _reject(&"invalid_outcome_hero")
		if row["first_fall_tick"] != null and not _in_range(row["first_fall_tick"], 0, U63_MAX):
			return _reject(&"invalid_outcome_hero")
		var hero_id := String(row["hero_id"])
		if seen.has(hero_id):
			return _reject(&"duplicate_outcome_hero")
		seen[hero_id] = true
		var ordered := {}
		for key: String in keys:
			ordered[key] = (
				int(row[key])
				if key in ["deployments", "retreats", "first_fall_tick"]
				and row[key] != null
				else row[key]
			)
		out.append(ordered)
	return _accept(out)
static func _normalize_rewards(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return _reject(&"invalid_rewards")
	var out: Array = []
	var seen := {}
	for row: Variant in value:
		var keys := ["kind", "id", "hero_instance_id"]
		if typeof(row) != TYPE_DICTIONARY or not _exact_keys(row, keys):
			return _reject(&"invalid_reward")
		if not REWARD_VALUES.has(String(row["kind"])) or not _is_ascii_string(row["id"]):
			return _reject(&"invalid_reward")
		var reward_key := CanonicalJson.text([String(row["kind"]), String(row["id"])])
		if seen.has(reward_key):
			return _reject(&"duplicate_reward")
		seen[reward_key] = true
		var hero_value: Variant = row["hero_instance_id"]
		if String(row["kind"]) == "operator":
			if not _is_hex(String(hero_value), 16):
				return _reject(&"invalid_reward")
		elif hero_value != null:
			return _reject(&"invalid_reward")
		out.append({"kind": row["kind"], "id": row["id"], "hero_instance_id": hero_value})
	return _accept(out)
static func build_context(
	operator_ids: Array,
	trap_ids: Array,
	stages: Array,
	authored_offers: Array,
	starting_traps: Array = [],
	promotion_rules: Dictionary = {},
	combat_rules_sha256: String = CombatContentBindingScript.LEGACY_ZERO_SHA256,
) -> Dictionary:
	operator_ids = operator_ids.filter(func(value: Variant) -> bool:
		return String(value) != "recruit")
	var stage_order: Array[String] = []
	var stage_rewards := {}
	var stage_recovery_rosters := {}
	var ordered_stages := stages.duplicate()
	ordered_stages.sort_custom(func(a: StageDef, b: StageDef) -> bool:
		return a.campaign_index < b.campaign_index)
	for stage: StageDef in ordered_stages:
		stage_order.append(String(stage.id))
		var rewards: Array = []
		for reward: Dictionary in stage.rewards:
			rewards.append({"kind": String(reward["kind"]), "id": String(reward["id"])})
		stage_rewards[String(stage.id)] = rewards
		stage_recovery_rosters[String(stage.id)] = _string_set(stage.recovery_roster)
	var offers := {}
	for row: Dictionary in authored_offers:
		offers[String(row["offer_id"])] = {
			"operator_def_id": String(row["operator_def_id"]),
			"cost": int(row["cost"]),
		}
	var normalized_promotion_rules := promotion_rules.duplicate(true)
	return {
		"operator_ids": _string_set(operator_ids),
		"trap_ids": _string_set(trap_ids),
		"stage_order": stage_order,
		"stage_rewards": stage_rewards,
		"stage_recovery_rosters": stage_recovery_rosters,
		"offers": offers,
		"starting_traps": _sorted_strings(starting_traps),
		"promotion_rules": normalized_promotion_rules,
		"combat_rules_sha256": combat_rules_sha256,
	}
static func _validate_data_invariants(data: Dictionary, context: Dictionary) -> Dictionary:
	var root := _validate_root_links(data)
	if not root["accepted"]:
		return root
	var progression := _validate_progression(data, context)
	if not progression["accepted"]:
		return progression
	var offers := _validate_offer_context(data, context)
	if not offers["accepted"]:
		return offers
	var heroes := _validate_hero_context(data, context)
	if not heroes["accepted"]:
		return heroes
	var receipt := _validate_receipt_links(data, context)
	if not receipt["accepted"]:
		return receipt
	return _campaign_invariants().validate(data, context)
static func _validate_core_snapshot_invariants(data: Dictionary, context: Dictionary) -> Dictionary:
	var expected_uid := HeroIdentity.campaign_uid(
		int(data["campaign_seed"]), int(data["campaign_generation"]),
	)
	if data["campaign_uid"] != expected_uid:
		return _reject(&"campaign_uid_mismatch")
	var allocated_ids := {}
	for position: int in data["heroes"].size():
		var hero: Dictionary = data["heroes"][position]
		if int(hero["recruitment_index"]) != position:
			return _reject(&"recruitment_history_gap")
		var allocated := HeroIdentity.allocate_hero_id(
			int(data["campaign_seed"]), int(data["campaign_generation"]), position,
			func(candidate: String) -> bool: return allocated_ids.has(candidate),
		)
		if not allocated["accepted"] or allocated["hero_id"] != hero["hero_id"]:
			return _reject(&"hero_identity_mismatch")
		allocated_ids[hero["hero_id"]] = true
	if int(data["next_recruitment_index"]) != data["heroes"].size():
		return _reject(&"recruitment_counter_mismatch")
	for result: Dictionary in [
		_validate_progression(data, context),
		_validate_offer_context(data, context),
		_validate_hero_context(data, context),
	]:
		if not result["accepted"]:
			return result
	var expected_marks: int = _campaign_invariants().INITIAL_MARKS
	for offer: Dictionary in data["offers"]:
		if offer["consumed"]:
			expected_marks -= int(offer["cost"])
	return _accept(data) if int(data["marks"]) == expected_marks else (
		_reject(&"contract_marks_mismatch")
	)

static func _validate_root_links(data: Dictionary) -> Dictionary:
	var expected_uid := HeroIdentity.campaign_uid(
		int(data["campaign_seed"]),
		int(data["campaign_generation"]),
	)
	if data["campaign_uid"] != expected_uid:
		return _reject(&"campaign_uid_mismatch")
	var allocated_ids := {}
	for position: int in data["heroes"].size():
		var hero: Dictionary = data["heroes"][position]
		if int(hero["recruitment_index"]) != position:
			return _reject(&"recruitment_history_gap")
		var allocated := HeroIdentity.allocate_hero_id(
			int(data["campaign_seed"]),
			int(data["campaign_generation"]),
			int(hero["recruitment_index"]),
			func(candidate: String) -> bool: return allocated_ids.has(candidate),
		)
		if not allocated["accepted"] or allocated["hero_id"] != hero["hero_id"]:
			return _reject(&"hero_identity_mismatch")
		allocated_ids[hero["hero_id"]] = true
	if int(data["next_recruitment_index"]) != data["heroes"].size():
		return _reject(&"recruitment_counter_mismatch")
	var receipt: Variant = data["last_resolution"]
	if receipt == null and int(data["next_resolution_index"]) != 1:
		return _reject(&"resolution_counter_mismatch")
	if receipt != null:
		if int(data["next_resolution_index"]) != int(receipt["resolution_index"]) + 1:
			return _reject(&"resolution_counter_mismatch")
		if int(data["next_attempt_id"]) <= int(receipt["attempt_id"]):
			return _reject(&"attempt_counter_mismatch")
	return _accept(data)

static func _validate_progression(data: Dictionary, context: Dictionary) -> Dictionary:
	var stage_order: Array = context["stage_order"]
	var stage_rows: Array = data["stage_stars"]
	if stage_rows.size() > stage_order.size():
		return _reject(&"invalid_stage_prefix")
	for index: int in stage_rows.size():
		if stage_rows[index]["stage_id"] != stage_order[index]:
			return _reject(&"invalid_stage_prefix")
	var expected_traps: Array = context["starting_traps"].duplicate()
	for stage_row: Dictionary in stage_rows:
		for reward: Dictionary in context["stage_rewards"][stage_row["stage_id"]]:
			if reward["kind"] == &"trap":
				expected_traps.append(String(reward["id"]))
	expected_traps = _sorted_strings(expected_traps)
	if data["unlocked_traps"] != expected_traps:
		return _reject(&"trap_unlock_mismatch")
	return _accept(data)

static func _validate_offer_context(data: Dictionary, context: Dictionary) -> Dictionary:
	var authored: Dictionary = context["offers"]
	if (data["offers"] as Array).size() != authored.size():
		return _reject(&"offer_catalog_mismatch")
	for offer: Dictionary in data["offers"]:
		var offer_id := String(offer["offer_id"])
		if not authored.has(offer_id):
			return _reject(&"unknown_offer")
		var expected: Dictionary = authored[offer_id]
		if offer["operator_def_id"] != expected["operator_def_id"]:
			return _reject(&"offer_definition_mismatch")
		if int(offer["cost"]) != int(expected["cost"]):
			return _reject(&"offer_cost_mismatch")
		var matching_contracts := 0
		for hero: Dictionary in data["heroes"]:
			if hero["recruit_source"] == "contract" and hero["source_id"] == offer_id:
				matching_contracts += 1
		if matching_contracts > 1 or bool(offer["consumed"]) != (matching_contracts == 1):
			return _reject(&"offer_consumption_mismatch")
	return _accept(data)

static func _validate_hero_context(data: Dictionary, context: Dictionary) -> Dictionary:
	var callsigns := {}
	var one_shot_sources := {}
	for hero: Dictionary in data["heroes"]:
		if (
			not context["operator_ids"].has(String(hero["operator_def_id"]))
			or not context["operator_ids"].has(String(hero["acquisition_operator_def_id"]))
			or not context["operator_ids"].has(String(hero["identity_portrait_id"]))
		):
			return _reject(&"unknown_operator")
		if int(hero["name_version"]) != HeroNames.VERSION:
			return _reject(&"unsupported_name_version")
		if not _valid_source_pair(hero, context):
			return _reject(&"invalid_hero_source")
		if not CampaignHeroCodec.valid_callsign(hero["custom_callsign"]):
			return _reject(&"invalid_callsign")
		var display := CampaignHeroCodec.display_callsign(hero)
		if not display["accepted"]:
			return display
		var folded := String(display["value"]).to_lower()
		if callsigns.has(folded):
			return _reject(&"duplicate_callsign")
		callsigns[folded] = true
		if hero["death"] != null and not context["stage_rewards"].has(hero["death"]["stage_id"]):
			return _reject(&"unknown_death_stage")
		if hero["recruit_source"] in ["contract", "reward"]:
			var source_key := CanonicalJson.text([
				hero["recruit_source"], hero["source_id"],
				hero["acquisition_operator_def_id"],
			])
			if one_shot_sources.has(source_key):
				return _reject(&"duplicate_hero_source")
			one_shot_sources[source_key] = true
	return _accept(data)

static func _validate_receipt_links(data: Dictionary, context: Dictionary) -> Dictionary:
	var receipt: Variant = data["last_resolution"]
	if receipt == null:
		return _accept(data)
	if receipt["campaign_uid"] != data["campaign_uid"]:
		return _reject(&"receipt_campaign_mismatch")
	if not context["stage_rewards"].has(receipt["stage_id"]):
		return _reject(&"unknown_receipt_stage")
	var expected_rewards: Array = []
	if receipt["result"] == "clear" and int(receipt["stars_before"]) == 0:
		expected_rewards = context["stage_rewards"][receipt["stage_id"]]
	if (receipt["rewards_granted"] as Array).size() != expected_rewards.size():
		return _reject(&"receipt_rewards_mismatch")
	for index: int in expected_rewards.size():
		var actual: Dictionary = receipt["rewards_granted"][index]
		var expected: Dictionary = expected_rewards[index]
		if actual["kind"] != expected["kind"] or actual["id"] != expected["id"]:
			return _reject(&"receipt_rewards_mismatch")
	var heroes_by_id := {}
	for hero: Dictionary in data["heroes"]:
		heroes_by_id[hero["hero_id"]] = hero
	for hero_id: String in receipt["created_hero_ids"]:
		if not heroes_by_id.has(hero_id):
			return _reject(&"missing_created_hero")
	for reward: Dictionary in receipt["rewards_granted"]:
		if reward["kind"] != "operator":
			continue
		var created: Dictionary = heroes_by_id.get(reward["hero_instance_id"], {})
		if created.is_empty():
			return _reject(&"missing_created_hero")
		if (
			created["acquisition_operator_def_id"] != reward["id"]
			or created["recruit_source"] != "reward"
			or created["source_id"] != receipt["stage_id"]
		):
			return _reject(&"created_hero_origin_mismatch")
	for hero_id: String in receipt["dead_hero_ids"]:
		if not heroes_by_id.has(hero_id):
			return _reject(&"missing_dead_hero")
		var death: Variant = heroes_by_id[hero_id]["death"]
		if typeof(death) != TYPE_DICTIONARY or not _death_matches_receipt(death, receipt):
			return _reject(&"death_receipt_mismatch")
	for award: Dictionary in receipt["xp_awards"]:
		var hero: Dictionary = heroes_by_id.get(award["hero_id"], {})
		if hero.is_empty() or int(hero["xp"]) < int(award["delta"]):
			return _reject(&"xp_receipt_mismatch")
	return _accept(data)

static func _death_matches_receipt(death: Dictionary, receipt: Dictionary) -> bool:
	return (
		death["resolution_index"] == receipt["resolution_index"]
		and death["attempt_id"] == receipt["attempt_id"]
		and death["stage_id"] == receipt["stage_id"]
		and death["terminal_reason"] == receipt["terminal_reason"]
		and death["terminal_tick"] == receipt["terminal_tick"]
	)

static func _valid_source_pair(hero: Dictionary, context: Dictionary) -> bool:
	var source := String(hero["recruit_source"])
	var source_id := String(hero["source_id"])
	var acquisition := String(hero["acquisition_operator_def_id"])
	match source:
		"starter": return source_id.is_empty()
		"contract":
			return (
				context["offers"].has(source_id)
				and context["offers"][source_id]["operator_def_id"] == acquisition
			)
		"reward":
			if not context["stage_rewards"].has(source_id):
				return false
			for reward: Dictionary in context["stage_rewards"][source_id]:
				if reward["kind"] == "operator" and reward["id"] == acquisition:
					return true
			return false
		"recovery":
			return (
				context["stage_recovery_rosters"].has(source_id)
				and context["stage_recovery_rosters"][source_id].has(acquisition)
			)
		_: return false

static func _valid_context(context: Dictionary) -> bool:
	return CampaignContextValidatorScript.valid(context)

static func _string_set(values: Array) -> Dictionary:
	var result := {}
	for value: Variant in values:
		result[String(value)] = true
	return result

static func _sorted_strings(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in values:
		var text := String(value)
		if not result.has(text):
			result.append(text)
	result.sort()
	return result

static func _in_range(value: Variant, minimum: int, maximum: int) -> bool:
	return _is_integer(value) and int(value) >= minimum and int(value) <= maximum
static func _encoded(value: Variant) -> Dictionary:
	var source := CanonicalJson.text(value)
	return {
		"accepted": true,
		"error_code": &"",
		"value": value,
		"text": source,
		"bytes": source.to_utf8_buffer(),
		"sha256": CanonicalJson.sha256_text(source),
	}
static func _campaign_invariants() -> Script:
	return load("res://sim/campaign_invariants.gd") as Script

static func _accept(value: Variant) -> Dictionary:
	return {"accepted": true, "error_code": &"", "value": value}

static func _reject(error_code: StringName) -> Dictionary:
	return {"accepted": false, "error_code": error_code}

static func _exact_keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size():
		return false
	var actual: Array = value.keys()
	for index: int in expected.size():
		if actual[index] != expected[index]:
			return false
	return true

static func _is_ascii_string(value: Variant, allow_empty: bool = false) -> bool:
	if typeof(value) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return false
	var text := String(value)
	if text.is_empty():
		return allow_empty
	for character: String in text:
		if character.unicode_at(0) > 127:
			return false
	return true

static func _is_integer(value: Variant) -> bool:
	return typeof(value) == TYPE_INT

static func _is_hex(value: String, length: int) -> bool:
	if value.length() != length:
		return false
	for index: int in value.length():
		if "0123456789abcdef".find(value.substr(index, 1)) < 0:
			return false
	return true
