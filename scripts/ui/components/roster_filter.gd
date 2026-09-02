class_name RosterFilter
extends RefCounted

## Pure presentation filtering. Faction identity is never persisted into the
## canonical campaign row, so existing hashes, codecs, and saves remain stable.

const FactionHeraldryType := preload("res://scripts/ui/components/faction_heraldry.gd")

const STATUS_ACTIVE: StringName = &"active"
const STATUS_FALLEN: StringName = &"fallen"
const STATUS_ALL: StringName = &"all"
const FACTION_ALL: StringName = &"all"


static func annotate(row: Dictionary) -> Dictionary:
	var projected := row.duplicate(true)
	projected["faction_id"] = faction_id(row)
	projected["fallen"] = is_fallen(row)
	return projected


static func annotate_all(rows: Array) -> Array[Dictionary]:
	var projected: Array[Dictionary] = []
	for row: Dictionary in rows:
		projected.append(annotate(row))
	return projected


static func faction_id(row: Dictionary) -> StringName:
	var explicit := StringName(_text(row.get("faction_id", "")))
	if FactionHeraldryType.ORDER.has(explicit):
		return explicit
	for source: String in [
		_text(row.get("source_id", "")),
		_text(row.get("operator_def_id", "")),
	]:
		var derived := _faction_from_prefix(source)
		if derived != &"":
			return derived
	return FactionHeraldryType.ACTIVE_FACTION


static func is_fallen(row: Dictionary) -> bool:
	return String(row.get("life_status", "ready")) == "dead" or row.get("death") != null


static func filter_rows(
	rows: Array,
	status: StringName = STATUS_ACTIVE,
	faction: StringName = FACTION_ALL,
) -> Array[Dictionary]:
	var filtered: Array[Dictionary] = []
	for raw: Dictionary in rows:
		var row := annotate(raw)
		if status == STATUS_ALL:
			pass
		elif status == STATUS_FALLEN:
			if not bool(row["fallen"]):
				continue
		elif bool(row["fallen"]):
			continue
		if faction != FACTION_ALL and StringName(row["faction_id"]) != faction:
			continue
		filtered.append(row)
	return filtered


static func count(rows: Array, status: StringName, faction: StringName = FACTION_ALL) -> int:
	return filter_rows(rows, status, faction).size()


static func _faction_from_prefix(value: String) -> StringName:
	var normalized := value.to_lower()
	if normalized.begins_with("solcrest_"):
		return &"solcrest_accord"
	if normalized.begins_with("vesper_"):
		return &"vesper_circuit"
	if normalized.begins_with("lunaris_") or normalized.begins_with("reliquary_"):
		return &"lunaris_reliquary"
	if normalized.begins_with("crimson_"):
		return &"crimson_aegis"
	return &""


static func _text(value: Variant) -> String:
	return "" if value == null else str(value)
