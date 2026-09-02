class_name CampaignStateV3
extends RefCounted

## Authoritative CampaignSave v3 aggregate. Every mutator constructs a fully
## normalized prospective state and returns a CampaignMutation; authority changes
## only after CampaignSaveStore commits and independently restores exact bytes.

const CampaignV3CodecScript := preload("res://sim/campaign_v3_codec.gd")
const CampaignCodecScript := preload("res://sim/campaign_codec.gd")
const HeroCodecScript := preload("res://sim/campaign_hero_codec.gd")
const AttemptsScript := preload("res://sim/campaign_v3_attempts.gd")
const RenamingScript := preload("res://sim/campaign_v3_renaming.gd")
const CanonicalJsonScript := preload("res://sim/canonical_json.gd")
const CommandCodecScript := preload("res://sim/campaign_v3_command_codec.gd")
const CommandHistoryScript := preload("res://sim/campaign_v3_command_history.gd")
const HashScript := preload("res://sim/campaign_v3_hash.gd")

var _data: Dictionary = {}
var _context: Dictionary = {}
var _encoded_save_cache: Dictionary = {}
var _strategic_hash_cache: Dictionary = {}
var _core_hash_cache: Dictionary = {}
var _data_checksum := ""


static func create(seed_value: int, generation: int, context: Dictionary) -> Dictionary:
	var fresh: Dictionary = CampaignV3CodecScript.create_fresh(seed_value, generation, context)
	return _from_normalized_result(fresh, context)


static func restore(data: Variant, context: Dictionary) -> Dictionary:
	var normalized: Dictionary = CampaignV3CodecScript.normalize_data(data, context)
	return _from_normalized_result(normalized, context)


static func restore_source(source: String, context: Dictionary) -> Dictionary:
	var decoded: Dictionary = CampaignCodecScript.decode_save(source, context)
	if not decoded["accepted"]:
		return _reject(decoded["error_code"])
	return _from_normalized_result(
		{
			"accepted": true,
			"error_code": &"",
			"value": decoded["data"],
		},
		context
	)


func campaign_uid() -> String:
	return String(_data["campaign_uid"])


func campaign_seed() -> int:
	return int(_data["campaign_seed"])


func campaign_generation() -> int:
	return int(_data["campaign_generation"])


func save_revision() -> int:
	return int(_data["save_revision"])


func next_attempt_id() -> int:
	return int(_data["next_attempt_id"])


func next_resolution_index() -> int:
	return int(_data["next_resolution_index"])


func runtime_projection() -> Dictionary:
	var stage_ids: Array[StringName] = []
	for stage_id: String in _context["stage_order"]:
		stage_ids.append(StringName(stage_id))
	var stars := {}
	for row: Dictionary in _data["stage_stars"]:
		stars[StringName(row["stage_id"])] = int(row["stars"])
	var heroes: Array[Dictionary] = []
	for hero: Dictionary in _data["heroes"]:
		var projected := hero.duplicate(true)
		projected["life_status"] = "ready"
		projected["death"] = null
		var display := HeroCodecScript.display_callsign(hero)
		projected["callsign"] = String(display.get("value", hero["hero_id"]))
		projected["custom_title"] = RenamingScript.title_for(
			_data, String(hero["hero_id"]),
		)
		heroes.append(projected)
	heroes.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return (
				int(a["recruitment_index"]) < int(b["recruitment_index"])
				or (
					int(a["recruitment_index"]) == int(b["recruitment_index"])
					and String(a["hero_id"]) < String(b["hero_id"])
				)
			)
	)
	var operators: Array[StringName] = []
	for hero: Dictionary in heroes:
		var operator_id := StringName(hero["operator_def_id"])
		if not operators.has(operator_id):
			operators.append(operator_id)
	operators.sort_custom(
		func(a: StringName, b: StringName) -> bool: return String(a) < String(b)
	)
	var traps: Array[StringName] = []
	for trap_id: String in _data["unlocked_traps"]:
		traps.append(StringName(trap_id))
	return {
		"campaign_uid": String(_data["campaign_uid"]),
		"save_revision": int(_data["save_revision"]),
		"next_attempt_id": int(_data["next_attempt_id"]),
		"attempt_pending": int(_data["next_attempt_id"]) != int(_data["next_resolution_index"]),
		"marks": int(_data["marks"]),
		"basic_recruit_cost": int(_context["campaign"]["basic_recruit_cost"]),
		"stage_ids": stage_ids,
		"ready_heroes": heroes,
		"fallen_heroes": [],
		"honored_fallen_hero_ids": [],
		"memorial": [],
		"unlocked_operators": operators,
		"unlocked_traps": traps,
		"stage_stars": stars,
		"offers": (_data["offers"] as Array).duplicate(true),
	}


func data_copy() -> Dictionary:
	return _data.duplicate(true)


func encode_data() -> Dictionary:
	return _copy_encoded(CampaignV3CodecScript.encode_data(_data, _context))


func encode_save() -> Dictionary:
	return _copy_encoded(_encoded_save_cache)


func strategic_hash() -> Dictionary:
	return _copy_encoded(_strategic_hash_cache)


func core_hash() -> Dictionary:
	return _copy_encoded(_core_hash_cache)


func begin_attempt(
	command_id: Variant,
	stage_id: Variant,
	hero_ids: Variant,
	seed: Variant,
	expected_save_revision: Variant,
) -> Dictionary:
	return (
			AttemptsScript
			. begin(
				self,
			command_id,
			stage_id,
			hero_ids,
			seed,
			expected_save_revision,
		)
	)


func resolve_attempt(
	command_id: Variant,
	attempt_id: Variant,
	outcome_document: Variant,
	expected_save_revision: Variant,
) -> Dictionary:
	return (
			AttemptsScript
			. resolve(
				self,
			command_id,
			attempt_id,
			outcome_document,
			expected_save_revision,
		)
	)


func rename_hero(
	command_id: Variant,
	expected_save_revision: Variant,
	hero_id: Variant,
	callsign: Variant,
	title: Variant = null,
) -> Dictionary:
	return RenamingScript.execute(
		self, command_id, expected_save_revision, hero_id, callsign, title,
	)


func restore_factory() -> Callable:
	return _authority_restore_factory()


func restored_copy_without_pending() -> Dictionary:
	return restore(_data, _context)


func _authority_restore_factory() -> Callable:
	var context := _context
	return func(source: String) -> Dictionary:
		return restore_source(source, context)


func _validated_save_text() -> String:
	return String(_encoded_save_cache["text"])


func _validated_hash_hex() -> String:
	return String(_strategic_hash_cache["hex"])


func _validated_core_hash_hex() -> String:
	return String(_core_hash_cache["hex"])


func _certified_data_unchanged() -> bool:
	return CanonicalJsonScript.sha256_hex(_data) == _data_checksum


func _prospective_state(data: Dictionary) -> Dictionary:
	if not _certified_data_unchanged():
		return _reject(&"invalid_campaign_state")
	var appended := CommandHistoryScript.validate_append(_data, data, _context)
	if not appended["accepted"]:
		return _reject(appended["error_code"])
	return _from_certified_append(appended["value"], _context)


## Produce a distinct runtime authority after the store has echoed the exact
## certified bytes from disk. This avoids reparsing and replaying the same
## document while retaining immutable state ownership across the commit seam.
func _certified_committed_copy(source: String) -> Dictionary:
	if source != _validated_save_text() or not _certified_data_unchanged():
		return _reject(&"invalid_campaign_state")
	var state: Variant = (load("res://sim/campaign_state_v3.gd") as GDScript).new()
	state._data = _data.duplicate(true)
	state._context = _context.duplicate(true)
	state._encoded_save_cache = _copy_encoded(_encoded_save_cache)
	state._strategic_hash_cache = _copy_encoded(_strategic_hash_cache)
	state._core_hash_cache = _copy_encoded(_core_hash_cache)
	state._data_checksum = _data_checksum
	return {"accepted": true, "error_code": &"", "value": state}


func _command_record(command_id: String) -> Dictionary:
	return CommandCodecScript.by_id(_data["command_receipts"], command_id)


func _context_ref() -> Dictionary:
	return _context


static func _from_normalized_result(result: Dictionary, context: Dictionary) -> Dictionary:
	if not result["accepted"]:
		return _reject(result["error_code"])
	var data: Dictionary = result["value"]
	var encoded: Dictionary = CampaignV3CodecScript.encode_save(data, context)
	var full_hash: Dictionary = HashScript.of_data(data, context)
	var core := {}
	for key: String in CampaignV3CodecScript.CORE_KEYS:
		core[key] = data[key]
	var core_hash: Dictionary = HashScript.of_core(core, context)
	if not core_hash["accepted"] and _read_only_legacy_rules(data):
		core_hash = HashScript._of_normalized_core(core)
	if not encoded["accepted"] or not full_hash["accepted"] or not core_hash["accepted"]:
		return _reject(&"invalid_campaign_state")
	var state: Variant = (load("res://sim/campaign_state_v3.gd") as GDScript).new()
	state._data = data.duplicate(true)
	state._context = context.duplicate(true)
	state._encoded_save_cache = encoded
	state._strategic_hash_cache = full_hash
	state._core_hash_cache = core_hash
	state._data_checksum = CanonicalJsonScript.sha256_hex(state._data)
	return {"accepted": true, "error_code": &"", "value": state}


static func _from_certified_append(data: Dictionary, context: Dictionary) -> Dictionary:
	var encoded: Dictionary = CampaignV3CodecScript._encode_normalized_save(data)
	var full_hash: Dictionary = HashScript._of_normalized_data(data)
	var core := {}
	for key: String in CampaignV3CodecScript.CORE_KEYS:
		core[key] = data[key]
	var core_hash: Dictionary = HashScript.of_core(core, context)
	if not encoded["accepted"] or not full_hash["accepted"] or not core_hash["accepted"]:
		return _reject(&"invalid_campaign_state")
	var state: Variant = (load("res://sim/campaign_state_v3.gd") as GDScript).new()
	state._data = data.duplicate(true)
	state._context = context.duplicate(true)
	state._encoded_save_cache = encoded
	state._strategic_hash_cache = full_hash
	state._core_hash_cache = core_hash
	state._data_checksum = CanonicalJsonScript.sha256_hex(state._data)
	return {"accepted": true, "error_code": &"", "value": state}


static func _read_only_legacy_rules(data: Dictionary) -> bool:
	if not (data["command_receipts"] as Array).is_empty():
		return false
	for hero: Dictionary in data["heroes"]:
		if hero["progression_rules_version"] != 1:
			return false
	return true


static func _copy_encoded(value: Dictionary) -> Dictionary:
	var result := value.duplicate()
	if result.get("value") is Dictionary or result.get("value") is Array:
		result["value"] = result["value"].duplicate(true)
	if result.get("bytes") is PackedByteArray:
		result["bytes"] = (result["bytes"] as PackedByteArray).duplicate()
	if result.get("bytes") is Array:
		result["bytes"] = (result["bytes"] as Array).duplicate()
	return result


static func _reject(code: StringName) -> Dictionary:
	return {"accepted": false, "error_code": code, "value": null}
