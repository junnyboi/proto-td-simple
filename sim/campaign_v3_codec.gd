class_name CampaignV3Codec
extends RefCounted

## CampaignSave v3 lives beside the immutable v1/v2 codec until the runtime
## cutover. Legacy documents are validated by CampaignCodecScript first, then mapped
## through one deterministic projection. Fresh rules-v2 documents start with
## five distinct persistent Recruit heroes.

const SAVE_SCHEMA := "prototype_td_campaign"
const SAVE_VERSION := 3
const LEGACY_OFFER_OPERATOR := "caster_1"
const RECRUIT_ID := "recruit"
const LEGACY_STAGE_COUNT := 8
const U63_MAX := 9_223_372_036_854_775_807
const MARKS_MAX := 1_000_000_000
const TargetPolicyDefScript := preload("res://data/target_policy_def.gd")
const TargetingScript := preload("res://sim/targeting.gd")
const CombatContentBindingScript := preload("res://sim/combat_content_binding.gd")
const CampaignDefType := preload("res://data/campaign_def.gd")
const ClassDefScript := preload("res://data/class_def.gd")
const CanonicalJsonScript := preload("res://sim/canonical_json.gd")
const HeroIdentityScript := preload("res://sim/hero_identity.gd")
const StateCodecScript := preload("res://sim/campaign_v3_state_codec.gd")
const CampaignCodecScript := preload("res://sim/campaign_codec.gd")
const HeroNamesScript := preload("res://sim/hero_names.gd")
const CampaignProgressionScript := preload("res://sim/campaign_progression.gd")
const CampaignInvariantsScript := preload("res://sim/campaign_invariants.gd")
const LEGACY_DATA_KEYS := [
	"campaign_uid", "campaign_seed", "campaign_generation", "save_revision",
	"next_recruitment_index", "next_attempt_id", "next_resolution_index", "marks",
	"stage_stars", "unlocked_traps", "class_entitlements",
	"offers", "heroes", "promotion_receipts", "promotion_proofs", "tickets", "memorial",
	"resolution_anchor", "last_resolution", "command_receipts",
]
const LEGACY_PRECOMMAND_DATA_KEYS := [
	"campaign_uid", "campaign_seed", "campaign_generation", "save_revision",
	"next_recruitment_index", "next_attempt_id", "next_resolution_index", "marks",
	"stage_stars", "unlocked_traps", "class_entitlements",
	"offers", "heroes", "promotion_receipts", "promotion_proofs", "tickets", "memorial",
	"resolution_anchor", "last_resolution",
]
const LEGACY_CORE_KEYS := [
	"campaign_uid", "campaign_seed", "campaign_generation", "save_revision",
	"next_recruitment_index", "next_attempt_id", "next_resolution_index", "marks",
	"stage_stars", "unlocked_traps", "class_entitlements",
	"offers", "heroes", "promotion_receipts", "promotion_proofs", "tickets", "memorial",
]
const HERO_KEYS := [
	"hero_id", "acquisition_operator_def_id", "operator_def_id", "current_class_id",
	"first_class_id", "advanced_class_id", "progression_rules_version", "xp",
	"identity_portrait_id", "portrait_instance_id", "portrait_asset_id",
	"recruitment_index", "recruited_after_resolution_index", "recruit_source",
	"source_id", "name_version", "custom_callsign", "life_status", "death",
]
const LEGACY_HERO_KEYS := HERO_KEYS
const DATA_KEYS := [
	"campaign_uid", "campaign_seed", "campaign_generation", "save_revision",
	"next_recruitment_index", "next_attempt_id", "next_resolution_index",
	"replay_marks_started_at_resolution", "marks", "stage_stars", "unlocked_traps",
	"class_entitlements", "offers", "heroes", "promotion_receipts",
	"promotion_proofs", "tickets", "memorial", "resolution_anchor", "last_resolution",
	"command_receipts",
]
const PRECOMMAND_DATA_KEYS := [
	"campaign_uid", "campaign_seed", "campaign_generation", "save_revision",
	"next_recruitment_index", "next_attempt_id", "next_resolution_index",
	"replay_marks_started_at_resolution", "marks", "stage_stars", "unlocked_traps",
	"class_entitlements", "offers", "heroes", "promotion_receipts",
	"promotion_proofs", "tickets", "memorial", "resolution_anchor", "last_resolution",
]
const CORE_KEYS := [
	"campaign_uid", "campaign_seed", "campaign_generation", "save_revision",
	"next_recruitment_index", "next_attempt_id", "next_resolution_index",
	"replay_marks_started_at_resolution", "marks", "stage_stars", "unlocked_traps",
	"class_entitlements", "offers", "heroes", "promotion_receipts",
	"promotion_proofs", "tickets", "memorial",
]
const CONTEXT_KEYS := [
	"legacy_context", "operator_ids", "operator_ticket_by_id", "class_rows", "class_by_id", "campaign",
	"stage_order", "stage_squad_sizes", "trap_ids", "environment_sha256",
]


static func derive_environment_sha256(
	operator_defs: Array,
	class_defs: Array,
	trap_ids: Array,
	stages: Array,
	campaign_def: CampaignDefType,
	text_entries: Dictionary,
) -> Dictionary:
	var operator_rows := _normalize_operators(operator_defs)
	if not operator_rows["accepted"]:
		return operator_rows
	var operator_ids: Array = []
	for row: Dictionary in operator_rows["value"]:
		operator_ids.append(StringName(row["id"]))
	var combat := CombatContentBindingScript.build({
		"operators": operator_ids,
		"traps": trap_ids,
	}, _campaign_stages(stages))
	if not combat["accepted"]:
		return combat
	var classes := ClassDefScript.normalize_catalog(class_defs, operator_ids, text_entries)
	if not classes["accepted"]:
		return classes
	var obtainable := ClassDefScript.validate_obtainability(classes["value"], campaign_def)
	if not obtainable["accepted"]:
		return obtainable
	var campaign := _normalize_campaign(campaign_def, classes["value"], false)
	if not campaign["accepted"]:
		return campaign
	var stage_order := _normalize_stage_order(stages)
	if not stage_order["accepted"]:
		return stage_order
	var reward_projection := _validate_v3_reward_projection(
		stages, classes["value"], campaign["value"],
	)
	if not reward_projection["accepted"]:
		return reward_projection
	var manifest := {
		"operators": operator_rows["value"],
		"classes": classes["value"],
		"campaign": campaign["value"],
		"stage_order": stage_order["value"],
		"traps": _sorted_unique_strings(trap_ids),
		"combat_rules": combat["manifest"],
	}
	if (manifest["traps"] as Array).is_empty():
		return _reject(&"invalid_catalog")
	return _accept(CanonicalJsonScript.sha256_hex(manifest))


static func build_context(
	operator_defs: Array,
	class_defs: Array,
	trap_ids: Array,
	stages: Array,
	campaign_def: CampaignDefType,
	text_entries: Dictionary,
	legacy_context: Dictionary,
) -> Dictionary:
	var derived := derive_environment_sha256(
		operator_defs, class_defs, trap_ids, stages, campaign_def, text_entries,
	)
	if not derived["accepted"]:
		return {}
	var environment := String(derived["value"])
	if (
		campaign_def == null
		or campaign_def.environment_sha256 != environment
		or CampaignDefType.P16_V3_ENVIRONMENT_SHA256 != environment
	):
		return {}
	var operator_rows := _normalize_operators(operator_defs)
	var operator_ids: Array = []
	var operator_ticket_by_id := {}
	for row: Dictionary in operator_rows["value"]:
		operator_ids.append(StringName(row["id"]))
	var combat := CombatContentBindingScript.build({
		"operators": operator_ids,
		"traps": trap_ids,
	}, _campaign_stages(stages))
	if not combat["accepted"]:
		return {}
	var legacy_operator_ids := operator_ids.filter(func(value: Variant) -> bool:
		return String(value) != RECRUIT_ID)
	var legacy_stages := _campaign_stages(stages).filter(func(stage: StageDef) -> bool:
		return stage.campaign_index <= LEGACY_STAGE_COUNT)
	var legacy_combat := CombatContentBindingScript.build({
		"operators": legacy_operator_ids,
		"traps": trap_ids,
	}, legacy_stages)
	if (
		not legacy_combat["accepted"]
		or String(legacy_context.get("combat_rules_sha256", "")) != legacy_combat["sha256"]
	):
		return {}
	for definition: OperatorDef in operator_defs:
		operator_ticket_by_id[String(definition.id)] = _ticket_projection(definition)
	var classes := ClassDefScript.normalize_catalog(class_defs, operator_ids, text_entries)
	var campaign := _normalize_campaign(campaign_def, classes["value"], true)
	var stages_result := _normalize_stage_order(stages)
	if not campaign["accepted"] or not stages_result["accepted"]:
		return {}
	var class_by_id := {}
	for row: Dictionary in classes["value"]:
		class_by_id[String(row["class_id"])] = row.duplicate(true)
	var stage_squad_sizes := {}
	for raw_stage: Variant in stages:
		if raw_stage is StageDef and (raw_stage as StageDef).campaign_index >= 1:
			stage_squad_sizes[String((raw_stage as StageDef).id)] = (raw_stage as StageDef).squad_size
	return {
		"legacy_context": legacy_context.duplicate(true),
		"operator_ids": _string_set(operator_ids),
		"operator_ticket_by_id": operator_ticket_by_id,
		"class_rows": (classes["value"] as Array).duplicate(true),
		"class_by_id": class_by_id,
		"campaign": campaign["value"],
		"stage_order": stages_result["value"],
		"stage_squad_sizes": stage_squad_sizes,
		"trap_ids": _string_set(trap_ids),
		"environment_sha256": environment,
	}


static func create_fresh(seed_value: int, generation: int, context: Dictionary) -> Dictionary:
	if not _valid_context(context):
		return _reject(&"missing_validation_context")
	if generation < 1 or generation > U63_MAX:
		return _reject(&"invalid_counter")
	var campaign: Dictionary = context["campaign"]
	var heroes: Array[Dictionary] = []
	for index: int in (campaign["starter_rows"] as Array).size():
		var allocated := HeroIdentityScript.allocate_hero_id(
			seed_value,
			generation,
			index,
			func(candidate: String) -> bool:
				for row: Dictionary in heroes:
					if row["hero_id"] == candidate:
						return true
				return false,
		)
		if not allocated["accepted"]:
			return allocated
		var starter: Dictionary = campaign["starter_rows"][index]
		var hero_id := String(allocated["hero_id"])
		heroes.append(_fresh_hero(hero_id, index, starter))
	var offers: Array[Dictionary] = []
	for authored: Dictionary in campaign["paid_offers"]:
		offers.append({
			"offer_id": String(authored["offer_id"]),
			"operator_def_id": String(authored["operator_def_id"]),
			"cost": int(authored["cost"]),
			"consumed": false,
		})
	var data := {
		"campaign_uid": HeroIdentityScript.campaign_uid(seed_value, generation),
		"campaign_seed": seed_value,
		"campaign_generation": generation,
		"save_revision": 1,
		"next_recruitment_index": heroes.size(),
		"next_attempt_id": 1,
		"next_resolution_index": 1,
		"replay_marks_started_at_resolution": 1,
		"marks": int(campaign["initial_marks"]),
		"stage_stars": [],
		"unlocked_traps": [],
		"class_entitlements": [],
		"offers": offers,
		"heroes": heroes,
		"promotion_receipts": [],
		"promotion_proofs": [],
		"tickets": [],
		"memorial": [],
		"resolution_anchor": null,
		"last_resolution": null,
		"command_receipts": [],
	}
	return normalize_data(data, context)


static func normalize_data(value: Variant, context: Dictionary) -> Dictionary:
	if not _valid_context(context):
		return _reject(&"missing_validation_context")
	if typeof(value) != TYPE_DICTIONARY:
		return _reject(&"invalid_data_schema")
	var source := value as Dictionary
	var data: Dictionary = source
	if source.keys() == LEGACY_DATA_KEYS:
		data = _upgrade_legacy_data(source)
	if not _exact_keys(data, DATA_KEYS):
		return _reject(&"invalid_data_schema")
	if typeof(data["heroes"]) != TYPE_ARRAY or (data["heroes"] as Array).is_empty():
		return _reject(&"empty_roster")
	var rules_versions := {}
	for raw: Variant in data["heroes"]:
		if typeof(raw) != TYPE_DICTIONARY or not raw.has("progression_rules_version"):
			return _reject(&"invalid_hero")
		rules_versions[int(raw["progression_rules_version"])] = true
	if rules_versions.size() != 1:
		return _reject(&"mixed_progression_rules")
	if rules_versions.has(1):
		return _normalize_legacy_projection(data, context)
	if rules_versions.has(ClassDefScript.RULES_VERSION):
		return _normalize_fresh_rules_v2(data, context)
	return _reject(&"invalid_progression_rules_version")


static func normalize_core(value: Variant, context: Dictionary) -> Dictionary:
	if not _valid_context(context):
		return _reject(&"missing_validation_context")
	return StateCodecScript.normalize_core(value, context, CORE_KEYS, HERO_KEYS)


static func encode_data(value: Variant, context: Dictionary) -> Dictionary:
	var normalized := normalize_data(value, context)
	if not normalized["accepted"]:
		return normalized
	return _encoded(normalized["value"])


static func encode_save(value: Variant, context: Dictionary) -> Dictionary:
	var encoded_data := encode_data(value, context)
	if not encoded_data["accepted"]:
		return encoded_data
	return _encoded({
		"schema": SAVE_SCHEMA,
		"version": SAVE_VERSION,
		"checksum": encoded_data["sha256"],
		"data": encoded_data["value"],
	})


## Internal certified-state seam. The caller has already validated the exact
## canonical data transition and must not replay the complete command ledger
## again merely to serialize it.
static func _encode_normalized_save(value: Dictionary) -> Dictionary:
	var encoded_data := _encoded(value)
	return _encoded({
		"schema": SAVE_SCHEMA,
		"version": SAVE_VERSION,
		"checksum": encoded_data["sha256"],
		"data": encoded_data["value"],
	})


static func decode_save(source: String, context: Dictionary) -> Dictionary:
	if not source.ends_with("\n") or source.ends_with("\n\n") or source.contains("\r"):
		return _reject(&"noncanonical_save")
	var parser := JSON.new()
	if parser.parse(source) != OK:
		return _reject(&"malformed_json")
	var restored := CanonicalJsonScript.restore_exact_integers(source, parser.data)
	if not restored["accepted"]:
		return restored
	return decode_parsed(restored["value"], source, context)


static func decode_parsed(parsed: Variant, source: String, context: Dictionary) -> Dictionary:
	if typeof(parsed) != TYPE_DICTIONARY:
		return _reject(&"malformed_json")
	if not _exact_keys(parsed, ["schema", "version", "checksum", "data"]):
		return _reject(&"invalid_root_schema")
	if parsed["schema"] != SAVE_SCHEMA or parsed["version"] != SAVE_VERSION:
		return _reject(&"unsupported_save")
	var checksum := String(parsed["checksum"])
	if not _is_hex(checksum, 64):
		return _reject(&"invalid_checksum")
	var source_data: Variant = parsed["data"]
	if typeof(source_data) == TYPE_DICTIONARY and (source_data as Dictionary).keys() in [
		PRECOMMAND_DATA_KEYS, LEGACY_PRECOMMAND_DATA_KEYS, LEGACY_DATA_KEYS,
	]:
		if checksum != CanonicalJsonScript.sha256_hex(source_data):
			return _reject(&"checksum_mismatch")
		if CanonicalJsonScript.text(parsed) != source:
			return _reject(&"noncanonical_save")
		var upgrade_source: Dictionary = (source_data as Dictionary).duplicate(true)
		if upgrade_source.keys() in [
			PRECOMMAND_DATA_KEYS, LEGACY_PRECOMMAND_DATA_KEYS,
		]:
			upgrade_source["command_receipts"] = []
		var upgraded: Dictionary = upgrade_source
		if upgrade_source.keys() == LEGACY_DATA_KEYS:
			upgraded = _upgrade_legacy_data(upgrade_source)
		var upgraded_save := encode_save(upgraded, context)
		if not upgraded_save["accepted"]:
			return upgraded_save
		return {
			"accepted": true,
			"error_code": &"",
			"data": upgraded_save["value"]["data"],
			"value": upgraded_save["value"],
			"text": upgraded_save["text"],
			"bytes": upgraded_save["bytes"],
			"sha256": upgraded_save["sha256"],
			"migrated_from_version": SAVE_VERSION,
		}
	var encoded_data := encode_data(parsed["data"], context)
	if not encoded_data["accepted"]:
		return encoded_data
	if checksum != encoded_data["sha256"]:
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


static func migrate_legacy_source(source: String, context: Dictionary) -> Dictionary:
	if not _valid_context(context):
		return _reject(&"missing_validation_context")
	var parser := JSON.new()
	if parser.parse(source) != OK:
		return _reject(&"malformed_json")
	var restored := CanonicalJsonScript.restore_exact_integers(source, parser.data)
	if not restored["accepted"] or typeof(restored["value"]) != TYPE_DICTIONARY:
		return _reject(&"malformed_json")
	var root: Dictionary = restored["value"]
	if not root.has("version") or int(root["version"]) not in [1, 2]:
		return _reject(&"unsupported_save")
	var legacy := CampaignCodecScript.decode_save(source, context["legacy_context"])
	if not legacy["accepted"]:
		return legacy
	var migrated := from_v2_data(legacy["data"], context)
	if not migrated["accepted"]:
		return migrated
	var encoded := encode_save(migrated["value"], context)
	if not encoded["accepted"]:
		return encoded
	return {
		"accepted": true,
		"error_code": &"",
		"data": encoded["value"]["data"],
		"value": encoded["value"],
		"text": encoded["text"],
		"bytes": encoded["bytes"],
		"sha256": encoded["sha256"],
		"migrated_from_version": int(root["version"]),
	}


static func from_v2_data(value: Dictionary, context: Dictionary) -> Dictionary:
	if not _valid_context(context):
		return _reject(&"missing_validation_context")
	var normalized := CampaignCodecScript.normalize_data(value, context["legacy_context"])
	if not normalized["accepted"]:
		return normalized
	return _accept(_migrate_data(normalized["value"], context))


static func _normalize_legacy_projection(data: Dictionary, context: Dictionary) -> Dictionary:
	var reversed := _reverse_data(data, context)
	if not reversed["accepted"]:
		return reversed
	var normalized := CampaignCodecScript.normalize_data(reversed["value"], context["legacy_context"])
	if not normalized["accepted"]:
		return normalized
	var expected := _migrate_data(normalized["value"], context)
	if CanonicalJsonScript.text(expected) != CanonicalJsonScript.text(data):
		return _reject(&"noncanonical_v3_migration")
	return _accept(expected)


static func _normalize_fresh_rules_v2(data: Dictionary, context: Dictionary) -> Dictionary:
	return StateCodecScript.normalize_data(data, context, DATA_KEYS, CORE_KEYS, HERO_KEYS)


static func _fresh_hero(hero_id: String, index: int, starter: Dictionary) -> Dictionary:
	var portrait_asset_id := String(starter["portrait_asset_id"])
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
		"recruited_after_resolution_index": 0,
		"recruit_source": "starter",
		"source_id": "",
		"name_version": HeroNamesScript.VERSION,
		"custom_callsign": null,
		"life_status": "ready",
		"death": null,
	}


static func _upgrade_legacy_data(value: Dictionary) -> Dictionary:
	var result := {}
	for key: String in DATA_KEYS:
		if key == "replay_marks_started_at_resolution":
			result[key] = int(value["next_resolution_index"])
		elif key == "resolution_anchor":
			result[key] = _upgrade_legacy_anchor(value[key])
		elif key == "last_resolution":
			result[key] = _upgrade_legacy_resolution(value[key])
		else:
			result[key] = value[key].duplicate(true) \
				if value[key] is Array or value[key] is Dictionary else value[key]
	return result


static func _upgrade_legacy_core(value: Dictionary) -> Dictionary:
	var result := {}
	for key: String in CORE_KEYS:
		if key == "replay_marks_started_at_resolution":
			result[key] = int(value["next_resolution_index"])
		else:
			result[key] = value[key].duplicate(true) \
				if value[key] is Array or value[key] is Dictionary else value[key]
	return result


static func _upgrade_legacy_anchor(value: Variant) -> Variant:
	if value == null:
		return null
	var result: Dictionary = value.duplicate(true)
	result["before_core"] = _upgrade_legacy_core(value["before_core"])
	result["after_core"] = _upgrade_legacy_core(value["after_core"])
	return result


static func _upgrade_legacy_resolution(value: Variant) -> Variant:
	return null if value == null else value.duplicate(true)


static func _migrate_data(value: Dictionary, context: Dictionary) -> Dictionary:
	var result := {}
	for key: String in DATA_KEYS:
		match key:
			"command_receipts":
				result[key] = []
			"replay_marks_started_at_resolution":
				result[key] = int(value["next_resolution_index"])
			"last_resolution":
				result[key] = _upgrade_legacy_resolution(value[key])
			"class_entitlements":
				result[key] = _entitlements_for_stars(value["stage_stars"], context)
			"tickets", "memorial":
				result[key] = []
			"offers":
				result[key] = _migrate_offers(value[key])
			"heroes":
				result[key] = _migrate_heroes(value[key])
			"resolution_anchor":
				result[key] = _migrate_anchor(value[key], context)
			_:
				result[key] = value[key].duplicate(true) \
					if value[key] is Array or value[key] is Dictionary else value[key]
	return result


static func _migrate_core(value: Dictionary, context: Dictionary) -> Dictionary:
	var result := {}
	for key: String in CORE_KEYS:
		match key:
			"replay_marks_started_at_resolution":
				result[key] = int(value["next_resolution_index"])
			"class_entitlements":
				result[key] = _entitlements_for_stars(value["stage_stars"], context)
			"tickets", "memorial":
				result[key] = []
			"offers":
				result[key] = _migrate_offers(value[key])
			"heroes":
				result[key] = _migrate_heroes(value[key])
			_:
				result[key] = value[key].duplicate(true) \
					if value[key] is Array or value[key] is Dictionary else value[key]
	return result


static func _migrate_anchor(value: Variant, context: Dictionary) -> Variant:
	if value == null:
		return null
	var result: Dictionary = value.duplicate(true)
	result["before_core"] = _migrate_core(value["before_core"], context)
	result["after_core"] = _migrate_core(value["after_core"], context)
	return result


static func _migrate_offers(values: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for source: Dictionary in values:
		var row: Dictionary = source.duplicate(true)
		if row["offer_id"] == "p16_caster_contract":
			row["operator_def_id"] = RECRUIT_ID
		result.append(row)
	return result


static func _migrate_heroes(values: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for source: Dictionary in values:
		var row := {}
		for key: String in HERO_KEYS:
			match key:
				"current_class_id":
					row[key] = source["advanced_class_id"] \
						if source["advanced_class_id"] != null else source["first_class_id"]
				"portrait_instance_id":
					row[key] = "portrait:%s" % source["hero_id"]
				"portrait_asset_id":
					row[key] = source["identity_portrait_id"]
				_:
					row[key] = source[key].duplicate(true) \
						if source[key] is Array or source[key] is Dictionary else source[key]
		result.append(row)
	return result


static func _reverse_data(value: Dictionary, context: Dictionary) -> Dictionary:
	var result := {}
	for key: String in CampaignCodecScript.DATA_KEYS:
		match key:
			"combat_rules_sha256":
				result[key] = context["legacy_context"]["combat_rules_sha256"]
			"offers":
				result[key] = _reverse_offers(value[key])
			"heroes":
				var heroes := _reverse_heroes(value[key])
				if not heroes["accepted"]:
					return heroes
				result[key] = heroes["value"]
			"resolution_anchor":
				var anchor := _reverse_anchor(value[key], context)
				if not anchor["accepted"]:
					return anchor
				result[key] = anchor["value"]
			_:
				result[key] = value[key].duplicate(true) \
					if value[key] is Array or value[key] is Dictionary else value[key]
	return _accept(result)


static func _reverse_core(value: Dictionary, context: Dictionary) -> Dictionary:
	var result := {}
	for key: String in CampaignCodecScript.CORE_KEYS:
		match key:
			"combat_rules_sha256":
				result[key] = context["legacy_context"]["combat_rules_sha256"]
			"offers": result[key] = _reverse_offers(value[key])
			"heroes":
				var heroes := _reverse_heroes(value[key])
				if not heroes["accepted"]:
					return heroes
				result[key] = heroes["value"]
			_:
				result[key] = value[key].duplicate(true) \
					if value[key] is Array or value[key] is Dictionary else value[key]
	return _accept(result)


static func _reverse_anchor(value: Variant, context: Dictionary) -> Dictionary:
	if value == null:
		return _accept(null)
	var before := _reverse_core(value["before_core"], context)
	var after := _reverse_core(value["after_core"], context)
	if not before["accepted"] or not after["accepted"]:
		return _reject(&"invalid_resolution_anchor")
	var result: Dictionary = value.duplicate(true)
	result["before_core"] = before["value"]
	result["after_core"] = after["value"]
	return _accept(result)


static func _reverse_offers(values: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for source: Dictionary in values:
		var row: Dictionary = source.duplicate(true)
		if row["offer_id"] == "p16_caster_contract" and row["operator_def_id"] == RECRUIT_ID:
			row["operator_def_id"] = LEGACY_OFFER_OPERATOR
		result.append(row)
	return result


static func _reverse_heroes(values: Array) -> Dictionary:
	var result: Array[Dictionary] = []
	for source: Dictionary in values:
		if not _exact_keys(source, HERO_KEYS):
			return _reject(&"invalid_hero")
		if int(source["progression_rules_version"]) != 1:
			return _reject(&"unsupported_v3_phase")
		var expected_current: Variant = source["advanced_class_id"] \
			if source["advanced_class_id"] != null else source["first_class_id"]
		if (
			source["current_class_id"] != expected_current
			or source["portrait_instance_id"] != "portrait:%s" % source["hero_id"]
			or source["portrait_asset_id"] != source["identity_portrait_id"]
		):
			return _reject(&"invalid_legacy_projection")
		var row := {}
		for key: String in CampaignProgressionScript.HERO_FIELD_ORDER:
			row[key] = source[key].duplicate(true) \
				if source[key] is Array or source[key] is Dictionary else source[key]
		result.append(row)
	return _accept(result)


static func _entitlements_for_stars(stage_rows: Array, context: Dictionary) -> Array[String]:
	var cleared := {}
	for row: Dictionary in stage_rows:
		cleared[String(row["stage_id"])] = true
	var values: Array[String] = []
	for row: Dictionary in context["campaign"]["stage_class_entitlements"]:
		if cleared.has(String(row["stage_id"])):
			values.append(String(row["class_id"]))
	values.sort()
	return values


static func _normalize_campaign(
	definition: CampaignDefType,
	class_rows: Array,
	check_environment: bool,
) -> Dictionary:
	if (
		definition == null
		or definition.schema_version != SAVE_VERSION
		or definition.name_version != HeroNamesScript.VERSION
		or definition.initial_marks != CampaignInvariantsScript.INITIAL_MARKS
		or definition.starter_rows.size() != 5
		or definition.portrait_asset_ids.size() != 8
		or definition.paid_offers.size() != 1
		or definition.v3_stage_rewards.is_empty()
		or definition.v3_stage_rewards.size() > 99
		or definition.basic_recruit_cost != 5
	):
		return _reject(&"invalid_campaign_definition")
	if check_environment and definition.environment_sha256.is_empty():
		return _reject(&"invalid_campaign_definition")
	var portrait_ids := _sorted_unique_strings(definition.portrait_asset_ids)
	if portrait_ids.size() != 8:
		return _reject(&"invalid_campaign_definition")
	var recruit_portrait_ids: Array[String] = []
	for portrait_id: String in portrait_ids:
		if portrait_id.begins_with("portrait_recruit_"):
			recruit_portrait_ids.append(portrait_id)
	if recruit_portrait_ids.size() != 8:
		return _reject(&"invalid_campaign_definition")
	var starter_rows: Array[Dictionary] = []
	var starter_portraits := {}
	for raw: Variant in definition.starter_rows:
		if typeof(raw) != TYPE_DICTIONARY:
			return _reject(&"invalid_campaign_definition")
		var row := raw as Dictionary
		if not _exact_keys(row, ["class_id", "operator_def_id", "portrait_asset_id"]):
			return _reject(&"invalid_campaign_definition")
		if row["class_id"] != RECRUIT_ID or row["operator_def_id"] != RECRUIT_ID:
			return _reject(&"invalid_campaign_definition")
		var portrait_id := String(row["portrait_asset_id"])
		if not portrait_ids.has(portrait_id) or starter_portraits.has(portrait_id):
			return _reject(&"invalid_campaign_definition")
		starter_portraits[portrait_id] = true
		starter_rows.append({
			"class_id": RECRUIT_ID,
			"operator_def_id": RECRUIT_ID,
			"portrait_asset_id": portrait_id,
		})
	var offers: Array[Dictionary] = []
	for row: Dictionary in definition.paid_offers:
		if not _exact_keys(row, ["cost", "offer_id", "operator_def_id"]):
			return _reject(&"invalid_campaign_definition")
		offers.append({
			"offer_id": String(row["offer_id"]),
			"operator_def_id": String(row["operator_def_id"]),
			"cost": int(row["cost"]),
		})
	if offers != [{
		"offer_id": "p16_caster_contract", "operator_def_id": RECRUIT_ID, "cost": 80,
	}]:
		return _reject(&"invalid_campaign_definition")
	var obtainable := ClassDefScript.validate_obtainability(class_rows, definition)
	if not obtainable["accepted"]:
		return obtainable
	var entitlements: Array[Dictionary] = []
	for row: Dictionary in definition.stage_class_entitlements:
		entitlements.append({
			"class_id": String(row["class_id"]),
			"stage_id": String(row["stage_id"]),
		})
	var stage_rewards: Array[Dictionary] = []
	for index: int in definition.v3_stage_rewards.size():
		var row: Dictionary = definition.v3_stage_rewards[index]
		if not _exact_keys(row, ["rewards", "stage_id"]):
			return _reject(&"invalid_v3_stage_rewards")
		if row["stage_id"] != "s%d" % (index + 1) or typeof(row["rewards"]) != TYPE_ARRAY:
			return _reject(&"invalid_v3_stage_rewards")
		var rewards: Array[Dictionary] = []
		var marks_reward_count := 0
		for reward: Variant in row["rewards"]:
			if typeof(reward) != TYPE_DICTIONARY:
				return _reject(&"invalid_v3_stage_rewards")
			var kind := String(reward.get("kind", ""))
			if kind == "currency":
				if (
					not _exact_keys(reward, ["amount", "id", "kind"])
					or String(reward["id"]) != "marks"
					or typeof(reward["amount"]) != TYPE_INT
					or int(reward["amount"]) != 40
				):
					return _reject(&"invalid_v3_stage_rewards")
				marks_reward_count += 1
				rewards.append({"amount": 40, "id": "marks", "kind": "currency"})
			elif kind == "trap":
				if not _exact_keys(reward, ["id", "kind"]):
					return _reject(&"invalid_v3_stage_rewards")
				rewards.append({"id": String(reward["id"]), "kind": kind})
			else:
				return _reject(&"specialist_reward_forbidden")
		if marks_reward_count != 1:
			return _reject(&"invalid_v3_stage_rewards")
		stage_rewards.append({"rewards": rewards, "stage_id": String(row["stage_id"])})
	return _accept({
		"schema_version": SAVE_VERSION,
		"name_version": definition.name_version,
		"initial_marks": definition.initial_marks,
		"starter_rows": starter_rows,
		"starting_class_ids": _strings(definition.starting_class_ids),
		"stage_class_entitlements": entitlements,
		"v3_stage_rewards": stage_rewards,
		"portrait_asset_ids": portrait_ids,
		"recruit_portrait_asset_ids": recruit_portrait_ids,
		"paid_offers": offers,
		"basic_recruit_cost": int(definition.basic_recruit_cost),
	})


static func _ticket_projection(definition: OperatorDef) -> Dictionary:
	var range_cells: Array[Dictionary] = []
	for cell: Vector2i in definition.range_offsets:
		range_cells.append({"x": cell.x, "y": cell.y})
	range_cells.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return "%+03d:%+03d" % [a["x"], a["y"]] < "%+03d:%+03d" % [b["x"], b["y"]])
	var skill_spec := {
		"skill_id": "",
		"skill_content_sha256": CanonicalJsonScript.sha256_hex({}),
		"payload": {},
	}
	if definition.skill != null:
		var skill := definition.skill as SkillDef
		skill_spec = {
			"skill_id": String(skill.id),
			"skill_content_sha256": FileAccess.get_sha256(skill.resource_path),
			"payload": _ticket_skill_payload(skill),
		}
	return {
		"operator_content_sha256": FileAccess.get_sha256(definition.resource_path),
		"combat_spec": {
			"dp_cost": definition.dp_cost,
			"block": definition.block,
			"hp": definition.hp,
			"atk": definition.atk,
			"defense": definition.defense,
			"resistance_permille": definition.resistance_permille,
			"attack_damage_kind": definition.attack_damage_kind,
			"atk_interval_ticks": definition.atk_interval_ticks,
			"placement": int(definition.placement),
			"range_cells": range_cells,
			"dp_generation_interval_ticks": definition.dp_generation_interval_ticks,
			"splash_dim": definition.splash_dim,
		},
		"target_policy_spec": _ticket_target_policy(definition),
		"skill_spec": skill_spec,
		"visual_spec": {
			"sprite_id": String(definition.sprite_id),
			"portrait_asset_id": String(definition.portrait_id),
		},
	}


static func _ticket_target_policy(definition: OperatorDef) -> Dictionary:
	var compiled: Dictionary = TargetingScript.compile(
		definition.target_policy, TargetPolicyDefScript.OwnerKind.OPERATOR,
	)
	return {
		"policy_id": String(compiled["policy_id"]),
		"policy_content_sha256": FileAccess.get_sha256(
			definition.target_policy.resource_path,
		),
		"owner_kind": int(compiled["owner_kind"]),
		"candidate_domain": int(compiled["candidate_domain"]),
		"aerial_rule": int(compiled["aerial_rule"]),
		"primary_rank": int(compiled["primary_rank"]),
	}


static func _ticket_skill_payload(skill: SkillDef) -> Dictionary:
	var payload := {
		"duration_ticks": skill.duration_ticks,
		"effect": int(skill.effect),
		"sp_cost": skill.sp_cost,
	}
	var parameter_keys: Array[String] = []
	for raw_key: Variant in skill.params:
		parameter_keys.append(String(raw_key))
	parameter_keys.sort()
	var parameters := {}
	for key: String in parameter_keys:
		var value: Variant = skill.params[key]
		if typeof(value) == TYPE_FLOAT:
			parameters["%s_milli" % key] = int(round(float(value) * 1000.0))
		else:
			parameters[key] = value
	payload["params"] = parameters
	return payload


static func _normalize_operators(values: Array) -> Dictionary:
	var rows: Array[Dictionary] = []
	var seen := {}
	for value: Variant in values:
		if not value is OperatorDef:
			return _reject(&"invalid_operator_catalog")
		var definition := value as OperatorDef
		var id := String(definition.id)
		if not _ascii_id(id) or seen.has(id) or definition.resource_path.is_empty():
			return _reject(&"invalid_operator_catalog")
		var policy: Dictionary = TargetingScript.compile(
			definition.target_policy, TargetPolicyDefScript.OwnerKind.OPERATOR,
		)
		if (
			not policy["valid"]
			or definition.target_policy.resource_path.is_empty()
		):
			return _reject(&"invalid_operator_target_policy")
		seen[id] = true
		rows.append({
			"id": id,
			"content_sha256": FileAccess.get_sha256(definition.resource_path),
			"skill_content_sha256": (
				FileAccess.get_sha256(definition.skill.resource_path)
				if definition.skill != null else CanonicalJsonScript.sha256_hex({})
			),
			"op_class": int(definition.op_class),
			"dp_cost": definition.dp_cost,
			"block": definition.block,
			"hp": definition.hp,
			"atk": definition.atk,
			"defense": definition.defense,
			"resistance_permille": definition.resistance_permille,
			"attack_damage_kind": definition.attack_damage_kind,
			"atk_interval_ticks": definition.atk_interval_ticks,
			"placement": int(definition.placement),
			"dp_generation_interval_ticks": definition.dp_generation_interval_ticks,
			"splash_dim": definition.splash_dim,
			"target_policy_spec": _ticket_target_policy(definition),
			"sprite_id": String(definition.sprite_id),
			"portrait_id": String(definition.portrait_id),
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["id"]) < String(b["id"]))
	return _accept(rows)


static func _normalize_stage_order(values: Array) -> Dictionary:
	var rows: Array[Dictionary] = []
	for raw: Variant in values:
		if not raw is StageDef:
			return _reject(&"invalid_campaign_stage")
		var stage := raw as StageDef
		if stage.campaign_index >= 1:
			rows.append({"stage_id": String(stage.id), "index": stage.campaign_index})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["index"]) < int(b["index"]))
	if rows.is_empty() or rows.size() > 99:
		return _reject(&"invalid_campaign_stage")
	var ids: Array[String] = []
	for index: int in rows.size():
		if rows[index]["index"] != index + 1:
			return _reject(&"invalid_campaign_stage")
		ids.append(String(rows[index]["stage_id"]))
	return _accept(ids)


static func _campaign_stages(values: Array) -> Array:
	return values.filter(func(value: Variant) -> bool:
		return value is StageDef and (value as StageDef).campaign_index >= 1)


static func _validate_v3_reward_projection(
	stages: Array,
	class_rows: Array,
	campaign: Dictionary,
) -> Dictionary:
	var class_by_operator := {}
	for row: Dictionary in class_rows:
		class_by_operator[String(row["operator_def_id"])] = row
	var entitlement_by_stage := {}
	for row: Dictionary in campaign["stage_class_entitlements"]:
		if not entitlement_by_stage.has(row["stage_id"]):
			entitlement_by_stage[row["stage_id"]] = []
		entitlement_by_stage[row["stage_id"]].append(String(row["class_id"]))
	var authored_by_stage := {}
	for row: Dictionary in campaign["v3_stage_rewards"]:
		var content_rewards: Array[Dictionary] = []
		for reward: Dictionary in row["rewards"]:
			if reward["kind"] != "currency":
				content_rewards.append(reward)
		authored_by_stage[String(row["stage_id"])] = content_rewards
	if authored_by_stage.size() != _campaign_stages(stages).size():
		return _reject(&"invalid_v3_stage_rewards")
	for raw: Variant in stages:
		if not raw is StageDef or raw.campaign_index < 1:
			continue
		var stage := raw as StageDef
		var expected_nonperson: Array[Dictionary] = []
		for reward: Dictionary in stage.rewards:
			if String(reward["kind"]) != "operator":
				expected_nonperson.append({
					"id": String(reward["id"]), "kind": String(reward["kind"]),
				})
				continue
			var operator_id := String(reward["id"])
			if not class_by_operator.has(operator_id):
				return _reject(&"unmapped_specialist_reward")
			var class_row: Dictionary = class_by_operator[operator_id]
			var class_id := String(class_row["class_id"])
			var is_starting_standard := (
				int(class_row["stage"]) == ClassDefScript.Stage.STANDARD
				and (campaign["starting_class_ids"] as Array).has(class_id)
			)
			var is_stage_entitlement := (
				int(class_row["stage"]) == ClassDefScript.Stage.ADVANCED
				and entitlement_by_stage.has(String(stage.id))
				and (entitlement_by_stage[String(stage.id)] as Array).has(class_id)
			)
			if not is_starting_standard and not is_stage_entitlement:
				return _reject(&"unmapped_specialist_reward")
		if not authored_by_stage.has(String(stage.id)):
			return _reject(&"missing_v3_stage_rewards")
		if authored_by_stage[String(stage.id)] != expected_nonperson:
			return _reject(&"v3_stage_reward_mismatch")
	return _accept(null)


static func _valid_context(context: Dictionary) -> bool:
	if not _exact_keys(context, CONTEXT_KEYS):
		return false
	if not _is_hex(String(context["environment_sha256"]), 64):
		return false
	if typeof(context["campaign"]) != TYPE_DICTIONARY:
		return false
	if typeof(context["class_rows"]) != TYPE_ARRAY or (context["class_rows"] as Array).size() != 4:
		return false
	return typeof(context["legacy_context"]) == TYPE_DICTIONARY


static func _sorted_unique_strings(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in values:
		var text := String(value)
		if not _ascii_id(text) or result.has(text):
			return []
		result.append(text)
	result.sort()
	return result


static func _strings(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in values:
		result.append(String(value))
	return result


static func _string_set(values: Array) -> Dictionary:
	var result := {}
	for value: Variant in values:
		result[String(value)] = true
	return result


static func _exact_keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size():
		return false
	var actual: Array = value.keys()
	for index: int in expected.size():
		if actual[index] != expected[index]:
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


static func _encoded(value: Variant) -> Dictionary:
	var source := CanonicalJsonScript.text(value)
	return {
		"accepted": true,
		"error_code": &"",
		"value": value,
		"text": source,
		"bytes": source.to_utf8_buffer(),
		"sha256": CanonicalJsonScript.sha256_text(source),
	}


static func _accept(value: Variant) -> Dictionary:
	return {"accepted": true, "error_code": &"", "value": value}


static func _reject(error_code: StringName) -> Dictionary:
	return {"accepted": false, "error_code": error_code}
