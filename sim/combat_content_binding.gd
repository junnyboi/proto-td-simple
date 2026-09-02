class_name CombatContentBinding
extends RefCounted

## Canonical mitigation-relevant content projection. This deliberately hashes
## semantics rather than .tres bytes so unrelated labels, art, and formatting do
## not invalidate campaign saves. Resource IDs and rows are text-sorted.

const CanonicalJsonScript := preload("res://sim/canonical_json.gd")
const DamageRulesScript := preload("res://sim/damage_rules.gd")

## Filled from the all-zero compatibility manifest during TD-MITIGATION. Old
## version-2 saves upgrade to this binding and therefore retain legacy behavior.
const LEGACY_ZERO_SHA256 := \
	"8cb77b6296a6fe814a6bf6ef458ff7a7153b48a9f4e32eb41accea80f36aeee7"


static func build(catalogs: Dictionary, stages: Array) -> Dictionary:
	var operators := _actor_rows(catalogs.get("operators", []), "operators")
	var traps := _damage_source_rows(catalogs.get("traps", []), "traps")
	var enemy_ids := _enemy_ids(stages)
	var enemies := _actor_rows(enemy_ids, "enemies")
	for result: Dictionary in [operators, enemies, traps]:
		if not result["accepted"]:
			return result
	var manifest := {
		"version": DamageRulesScript.VERSION,
		"minimum_damage_permille": DamageRulesScript.MIN_DAMAGE_PERMILLE,
		"operators": operators["value"],
		"enemies": enemies["value"],
		"traps": traps["value"],
	}
	return {
		"accepted": true,
		"error_code": &"",
		"manifest": manifest,
		"sha256": CanonicalJsonScript.sha256_hex(manifest),
	}


static func _actor_rows(values: Variant, directory: String) -> Dictionary:
	var ids := _sorted_ids(values)
	if ids.is_empty():
		return _reject(&"invalid_combat_catalog")
	var rows: Array[Dictionary] = []
	for actor_id: String in ids:
		var path := "res://data/%s/%s.tres" % [directory, actor_id]
		if not ResourceLoader.exists(path):
			return _reject(&"invalid_combat_catalog")
		var resource := load(path)
		if resource == null or String(resource.get("id")) != actor_id:
			return _reject(&"invalid_combat_catalog")
		var defense := int(resource.get("defense"))
		var resistance := int(resource.get("resistance_permille"))
		var damage_kind := int(resource.get("attack_damage_kind"))
		if not DamageRulesScript.authored_values_valid(
			damage_kind, defense, resistance,
		):
			return _reject(&"invalid_mitigation_definition")
		rows.append({
			"id": actor_id,
			"defense": defense,
			"resistance_permille": resistance,
			"attack_damage_kind": damage_kind,
		})
	return _accept(rows)


static func _damage_source_rows(values: Variant, directory: String) -> Dictionary:
	var ids := _sorted_ids(values)
	if ids.is_empty():
		return _reject(&"invalid_combat_catalog")
	var rows: Array[Dictionary] = []
	for source_id: String in ids:
		var path := "res://data/%s/%s.tres" % [directory, source_id]
		if not ResourceLoader.exists(path):
			return _reject(&"invalid_combat_catalog")
		var resource := load(path)
		if resource == null or String(resource.get("id")) != source_id:
			return _reject(&"invalid_combat_catalog")
		var damage_kind := int(resource.get("damage_kind"))
		if not DamageRulesScript.valid_kind(damage_kind):
			return _reject(&"invalid_mitigation_definition")
		rows.append({"id": source_id, "damage_kind": damage_kind})
	return _accept(rows)


static func _enemy_ids(stages: Array) -> Array[String]:
	var values: Array = []
	for stage: Variant in stages:
		if stage == null:
			continue
		for wave: Dictionary in stage.get("waves"):
			values.append(String(wave.get("enemy_id", "")))
	return _sorted_ids(values)


static func _sorted_ids(values: Variant) -> Array[String]:
	var result: Array[String] = []
	if typeof(values) != TYPE_ARRAY:
		return result
	for value: Variant in values:
		var text := String(value)
		if text.is_empty() or result.has(text):
			continue
		result.append(text)
	result.sort()
	return result


static func _accept(value: Variant) -> Dictionary:
	return {"accepted": true, "error_code": &"", "value": value}


static func _reject(error_code: StringName) -> Dictionary:
	return {"accepted": false, "error_code": error_code}
