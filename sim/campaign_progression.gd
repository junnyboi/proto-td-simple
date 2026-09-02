class_name CampaignProgression
extends RefCounted

## Versioned personnel progression rules. This module owns only deterministic
## model facts: migration defaults, XP derivation, and legal class projections.

const RULES_VERSION := 1
const XP_PER_OPERATION := 100
const XP_PER_DEFEAT := XP_PER_OPERATION / 2
const XP_MAX := 9_223_372_036_854_775_807
const HERO_FIELD_ORDER := [
	"hero_id", "acquisition_operator_def_id", "operator_def_id",
	"first_class_id", "advanced_class_id", "progression_rules_version", "xp",
	"identity_portrait_id", "recruitment_index", "recruited_after_resolution_index",
	"recruit_source", "source_id", "name_version", "custom_callsign",
	"life_status", "death",
]

const PROFILES := {
	"guard_1": {
		"first_class_id": "swordmaster", "advanced_class_id": null,
	},
	"sniper_1": {
		"first_class_id": "gunner", "advanced_class_id": null,
	},
	"caster_1": {
		"first_class_id": "mage_apprentice", "advanced_class_id": null,
	},
}

const PROMOTION_CHOICE_KEYS := [
	"advanced_class_id", "operator_def_id", "role", "skill_id", "dp_cost",
]


static func initial_fields(operator_def_id: String) -> Dictionary:
	if not PROFILES.has(operator_def_id):
		return {}
	var profile: Dictionary = PROFILES[operator_def_id]
	return {
		"acquisition_operator_def_id": operator_def_id,
		"first_class_id": profile["first_class_id"],
		"advanced_class_id": profile["advanced_class_id"],
		"progression_rules_version": RULES_VERSION,
		"xp": 0,
		"identity_portrait_id": operator_def_id,
	}


static func add_initial_fields(row: Dictionary) -> Dictionary:
	var fields := initial_fields(String(row.get("operator_def_id", "")))
	if fields.is_empty():
		return {}
	var result := {}
	for key: String in HERO_FIELD_ORDER:
		if fields.has(key):
			result[key] = fields[key]
		elif row.has(key):
			result[key] = row[key]
		else:
			return {}
	return result


static func projection_is_valid(row: Dictionary) -> bool:
	var acquisition := String(row.get("acquisition_operator_def_id", ""))
	var current := String(row.get("operator_def_id", ""))
	if not PROFILES.has(acquisition) or not PROFILES.has(current):
		return false
	if row.get("identity_portrait_id") != acquisition:
		return false
	if int(row.get("progression_rules_version", 0)) != RULES_VERSION:
		return false
	var xp: Variant = row.get("xp")
	if typeof(xp) != TYPE_INT or int(xp) < 0:
		return false
	var acquisition_profile: Dictionary = PROFILES[acquisition]
	if row.get("first_class_id") != acquisition_profile["first_class_id"]:
		return false
	return (
		current == acquisition
		and row.get("advanced_class_id") == acquisition_profile["advanced_class_id"]
	)


static func normalize_promotion_rules(value: Variant, operator_ids: Array) -> Dictionary:
	if not value is Resource:
		return _reject(&"invalid_promotion_rules")
	var resource := value as Resource
	var rules := {
		"rules_version": resource.get("rules_version"),
		"source_class_id": resource.get("source_class_id"),
		"xp_required": resource.get("xp_required"),
		"choices": resource.get("choices"),
	}
	if (
		typeof(rules["rules_version"]) != TYPE_INT
		or int(rules["rules_version"]) != RULES_VERSION
		or not _is_ascii_id(rules["source_class_id"])
		or typeof(rules["xp_required"]) != TYPE_INT
		or int(rules["xp_required"]) < 1
		or int(rules["xp_required"]) > XP_MAX
		or typeof(rules["choices"]) != TYPE_ARRAY
	):
		return _reject(&"invalid_promotion_rules")
	var operators := {}
	for operator_id: Variant in operator_ids:
		operators[String(operator_id)] = true
	var choices: Array[Dictionary] = []
	var class_ids := {}
	var destination_ids := {}
	for value_choice: Variant in rules["choices"]:
		if typeof(value_choice) != TYPE_DICTIONARY:
			return _reject(&"invalid_promotion_rules")
		var choice := value_choice as Dictionary
		if not _exact_keys(choice, PROMOTION_CHOICE_KEYS):
			return _reject(&"invalid_promotion_rules")
		for key: String in ["advanced_class_id", "operator_def_id", "role", "skill_id"]:
			if not _is_ascii_id(choice[key]):
				return _reject(&"invalid_promotion_rules")
		if typeof(choice["dp_cost"]) != TYPE_INT or int(choice["dp_cost"]) < 0:
			return _reject(&"invalid_promotion_rules")
		var class_id := String(choice["advanced_class_id"])
		var operator_id := String(choice["operator_def_id"])
		if (
			class_ids.has(class_id) or destination_ids.has(operator_id)
			or not operators.has(operator_id)
		):
			return _reject(&"invalid_promotion_rules")
		class_ids[class_id] = true
		destination_ids[operator_id] = true
		var ordered := {}
		for key: String in PROMOTION_CHOICE_KEYS:
			ordered[key] = int(choice[key]) if key == "dp_cost" else String(choice[key])
		choices.append(ordered)
	if choices.size() != 2:
		return _reject(&"invalid_promotion_rules")
	return _accept({
		"rules_version": int(rules["rules_version"]),
		"source_class_id": String(rules["source_class_id"]),
		"xp_required": int(rules["xp_required"]),
		"choices": choices,
	})


static func promotion_options(hero: Dictionary, rules: Dictionary) -> Dictionary:
	if rules.is_empty():
		return _reject(&"no_path")
	var eligibility := promotion_eligibility(hero, rules)
	if not eligibility["accepted"]:
		return eligibility
	return {
		"accepted": true,
		"error_code": &"",
		"hero_id": String(hero["hero_id"]),
		"xp": int(hero["xp"]),
		"xp_required": int(rules["xp_required"]),
		"choices": (rules["choices"] as Array).duplicate(true),
	}


static func promotion_eligibility(hero: Dictionary, rules: Dictionary) -> Dictionary:
	if rules.is_empty():
		return _reject(&"no_path")
	if hero["life_status"] != "ready" or hero["death"] != null:
		return _reject(&"hero_not_ready")
	if hero["first_class_id"] != rules["source_class_id"]:
		return _reject(&"wrong_source_class")
	if hero["advanced_class_id"] != null:
		return _reject(&"already_promoted")
	if int(hero["xp"]) < int(rules["xp_required"]):
		return _reject(&"insufficient_xp")
	return _accept(hero)


static func promotion_choice(rules: Dictionary, advanced_class_id: String) -> Dictionary:
	if rules.is_empty():
		return {}
	for choice: Dictionary in rules["choices"]:
		if choice["advanced_class_id"] == advanced_class_id:
			return choice.duplicate(true)
	return {}


static func apply_promotion(hero: Dictionary, choice: Dictionary) -> void:
	hero["advanced_class_id"] = choice["advanced_class_id"]
	hero["operator_def_id"] = choice["operator_def_id"]


static func xp_for_outcome(result: Variant, terminal_reason: Variant) -> int:
	if String(terminal_reason) == "resign":
		return 0
	match String(result):
		"clear":
			return XP_PER_OPERATION
		"defeat":
			return XP_PER_DEFEAT
		_:
			return 0


static func derive_xp_awards(
	outcome_heroes: Array,
	before_heroes: Array,
	xp_delta: int = XP_PER_OPERATION,
) -> Array[Dictionary]:
	if xp_delta <= 0:
		return []
	var ready := {}
	for hero: Dictionary in before_heroes:
		if hero["life_status"] == "ready" and hero["death"] == null:
			ready[String(hero["hero_id"])] = true
	var awarded := {}
	for outcome: Dictionary in outcome_heroes:
		var hero_id := String(outcome["hero_id"])
		if (
			ready.has(hero_id)
			and int(outcome["deployments"]) > 0
			and not bool(outcome["fell"])
		):
			awarded[hero_id] = true
	var hero_ids: Array = awarded.keys()
	hero_ids.sort()
	var rows: Array[Dictionary] = []
	for hero_id: String in hero_ids:
		rows.append({"hero_id": hero_id, "delta": xp_delta})
	return rows


static func can_apply_xp(rows: Array, awards: Array) -> bool:
	var by_id := _heroes_by_id(rows)
	for award: Dictionary in awards:
		var hero: Dictionary = by_id.get(String(award["hero_id"]), {})
		if hero.is_empty():
			return false
		var delta := int(award["delta"])
		var prior := int(hero["xp"])
		if delta < 0 or prior > XP_MAX - delta:
			return false
	return true


static func apply_xp(rows: Array, awards: Array) -> bool:
	if not can_apply_xp(rows, awards):
		return false
	var by_id := _heroes_by_id(rows)
	for award: Dictionary in awards:
		var hero: Dictionary = by_id[String(award["hero_id"])]
		hero["xp"] = int(hero["xp"]) + int(award["delta"])
	return true


static func reverse_xp(rows: Array, awards: Array) -> bool:
	var by_id := _heroes_by_id(rows)
	for award: Dictionary in awards:
		var hero: Dictionary = by_id.get(String(award["hero_id"]), {})
		if hero.is_empty() or int(hero["xp"]) < int(award["delta"]):
			return false
	for award: Dictionary in awards:
		var hero: Dictionary = by_id[String(award["hero_id"])]
		hero["xp"] = int(hero["xp"]) - int(award["delta"])
	return true


static func _heroes_by_id(rows: Array) -> Dictionary:
	var result := {}
	for row: Dictionary in rows:
		result[String(row["hero_id"])] = row
	return result


static func _is_ascii_id(value: Variant) -> bool:
	if typeof(value) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return false
	var text := String(value)
	if text.is_empty():
		return false
	for character: String in text:
		if character not in "abcdefghijklmnopqrstuvwxyz0123456789_-":
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


static func _accept(value: Variant) -> Dictionary:
	return {"accepted": true, "error_code": &"", "value": value}


static func _reject(error_code: StringName) -> Dictionary:
	return {"accepted": false, "error_code": error_code}
