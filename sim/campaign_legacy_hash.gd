extends RefCounted

## Read-only v1 strategic core hash used only at the migration boundary.
## New campaign state must use CampaignHash v2.

const HeroIdentity := preload("res://sim/hero_identity.gd")
const MAGIC := "PTD-CAMPAIGN-HASH"
const VERSION := 1
const FNV_OFFSET := -3750763034362895579
const FNV_PRIME := 1099511628211
const SOURCE_ENUM := {"starter": 0, "contract": 1, "reward": 2, "recovery": 3}
const LIFE_ENUM := {"ready": 0, "dead": 1}
const TERMINAL_ENUM := {"clear": 0, "leak_defeat": 1, "base_defeat": 2, "resign": 3}
const CORE_KEYS := [
	"campaign_uid", "campaign_seed", "campaign_generation", "save_revision",
	"next_recruitment_index", "next_attempt_id", "next_resolution_index", "marks",
	"stage_stars", "unlocked_traps", "offers", "heroes",
]
const HERO_KEYS := [
	"hero_id", "operator_def_id", "recruitment_index", "recruited_after_resolution_index",
	"recruit_source", "source_id", "name_version", "custom_callsign", "life_status", "death",
]
const STAR_KEYS := [
	"stage_id", "stars", "first_clear_resolution_index", "first_clear_attempt_id",
	"first_clear_terminal_tick",
]
const OFFER_KEYS := ["offer_id", "operator_def_id", "cost", "consumed"]
const DEATH_KEYS := [
	"resolution_index", "attempt_id", "stage_id", "terminal_reason", "terminal_tick",
]


static func of_core_snapshot(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY or not _exact_keys(value, CORE_KEYS):
		return _reject()
	var core := value as Dictionary
	if not _valid_rows(core["stage_stars"], STAR_KEYS):
		return _reject()
	if not _valid_string_array(core["unlocked_traps"]):
		return _reject()
	if not _valid_rows(core["offers"], OFFER_KEYS):
		return _reject()
	if not _valid_heroes(core["heroes"]):
		return _reject()
	var out := PackedByteArray()
	out.append_array(MAGIC.to_ascii_buffer())
	out.append(0)
	_append_u32(out, VERSION)
	_append_string(out, String(core["campaign_uid"]))
	_append_i64(out, int(core["campaign_seed"]))
	_append_i64(out, int(core["campaign_generation"]))
	_append_i64(out, int(core["save_revision"]))
	_append_i64(out, int(core["next_recruitment_index"]))
	_append_i64(out, int(core["next_attempt_id"]))
	_append_i64(out, int(core["next_resolution_index"]))
	_append_i64(out, int(core["marks"]))
	_append_stars(out, core["stage_stars"])
	_append_strings(out, core["unlocked_traps"])
	_append_offers(out, core["offers"])
	_append_heroes(out, core["heroes"])
	out.append(0)
	out.append(0)
	var bits := FNV_OFFSET
	for byte: int in out:
		bits ^= byte
		bits *= FNV_PRIME
	return {"accepted": true, "error_code": &"", "hex": HeroIdentity.format_u64_hex(bits)}


static func _append_stars(out: PackedByteArray, rows: Array) -> void:
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
		_append_string(out, String(row["operator_def_id"]))
		_append_i64(out, int(row["recruitment_index"]))
		_append_i64(out, int(row["recruited_after_resolution_index"]))
		out.append(int(SOURCE_ENUM[String(row["recruit_source"])]))
		_append_string(out, String(row["source_id"]))
		_append_u32(out, int(row["name_version"]))
		_append_nullable_string(out, row["custom_callsign"])
		out.append(int(LIFE_ENUM[String(row["life_status"])]))
		_append_death(out, row["death"])


static func _append_death(out: PackedByteArray, value: Variant) -> void:
	if value == null:
		out.append(0)
		return
	out.append(1)
	var row := value as Dictionary
	_append_i64(out, int(row["resolution_index"]))
	_append_i64(out, int(row["attempt_id"]))
	_append_string(out, String(row["stage_id"]))
	out.append(int(TERMINAL_ENUM[String(row["terminal_reason"])]))
	_append_i64(out, int(row["terminal_tick"]))


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


static func _valid_heroes(value: Variant) -> bool:
	if typeof(value) != TYPE_ARRAY:
		return false
	for raw: Variant in value:
		if typeof(raw) != TYPE_DICTIONARY or not _exact_keys(raw, HERO_KEYS):
			return false
		var row := raw as Dictionary
		if not SOURCE_ENUM.has(String(row["recruit_source"])):
			return false
		if not LIFE_ENUM.has(String(row["life_status"])):
			return false
		var death: Variant = row["death"]
		if death != null:
			if typeof(death) != TYPE_DICTIONARY or not _exact_keys(death, DEATH_KEYS):
				return false
			if not TERMINAL_ENUM.has(String(death["terminal_reason"])):
				return false
	return true


static func _valid_rows(value: Variant, keys: Array) -> bool:
	if typeof(value) != TYPE_ARRAY:
		return false
	for row: Variant in value:
		if typeof(row) != TYPE_DICTIONARY or not _exact_keys(row, keys):
			return false
	return true


static func _valid_string_array(value: Variant) -> bool:
	if typeof(value) != TYPE_ARRAY:
		return false
	for item: Variant in value:
		if typeof(item) != TYPE_STRING:
			return false
	return true


static func _exact_keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size():
		return false
	var actual: Array = value.keys()
	for index: int in expected.size():
		if actual[index] != expected[index]:
			return false
	return true


static func _reject() -> Dictionary:
	return {"accepted": false, "error_code": &"invalid_v1_hash_state"}
