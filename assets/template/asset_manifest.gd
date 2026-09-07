class_name AssetManifest
extends Resource

const SCHEMA_VERSION := 3
const LEGACY_ENTRY_KEYS: Array[String] = [
	"pattern", "frames", "size", "placeholder", "pivot", "animations",
]
const LEGACY_ATLAS_ENTRY_KEYS: Array[String] = [
	"pattern", "frames", "size", "placeholder", "pivot", "animations", "columns", "display_size",
]
const GENERATED_ENTRY_KEYS: Array[String] = [
	"pattern", "frames", "size", "placeholder", "pivot", "animations", "columns", "provenance",
]
const REGION_KEYS: Array[StringName] = [&"start", &"length", &"fps", &"loop"]

@export var schema_version: int = SCHEMA_VERSION
@export var entries: Dictionary = {}


func validate_contract() -> PackedStringArray:
	var errors := PackedStringArray()
	if schema_version != SCHEMA_VERSION:
		errors.append("schema_version: expected 3")
	for raw_id: Variant in entries:
		if typeof(raw_id) != TYPE_STRING_NAME or raw_id == &"":
			errors.append("entries: expected nonempty StringName key")
			continue
		var raw_entry: Variant = entries[raw_id]
		if typeof(raw_entry) != TYPE_DICTIONARY:
			errors.append("entries.%s: expected Dictionary" % raw_id)
			continue
		for detail: String in entry_diagnostics(raw_id, raw_entry):
			errors.append("entries.%s.%s" % [raw_id, detail])
	return errors


func entry_diagnostics(id: StringName, entry: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var generated := entry.has("provenance")
	var legacy_atlas := entry.has("display_size")
	var expected_keys := (
		GENERATED_ENTRY_KEYS
		if generated
		else (LEGACY_ATLAS_ENTRY_KEYS if legacy_atlas else LEGACY_ENTRY_KEYS)
	)
	if entry.size() != expected_keys.size():
		errors.append(
			(
				"shape: expected exact %s fields"
				% (
					"eight generated"
					if generated
					else ("eight legacy atlas" if legacy_atlas else "six legacy")
				)
			)
		)
	for key: String in expected_keys:
		if not entry.has(key):
			errors.append("shape: missing %s" % key)
	for raw_key: Variant in entry:
		if typeof(raw_key) != TYPE_STRING or not expected_keys.has(raw_key):
			errors.append("shape: unexpected key %s" % raw_key)
	var pattern: Variant = entry.get(&"pattern")
	var frames: Variant = entry.get(&"frames")
	var size: Variant = entry.get(&"size")
	if typeof(pattern) != TYPE_STRING or not String(pattern).begins_with("res://"):
		errors.append("pattern: expected res:// String")
	if typeof(frames) != TYPE_INT or int(frames) < 1:
		errors.append("frames: expected positive int")
	if typeof(size) != TYPE_VECTOR2I or size.x <= 0 or size.y <= 0:
		errors.append("size: expected positive Vector2i")
	if typeof(entry.get(&"placeholder")) != TYPE_BOOL:
		errors.append("placeholder: expected bool")
	var pivot: Variant = entry.get(&"pivot")
	if typeof(pivot) != TYPE_VECTOR2 or not _normalized_vector(pivot):
		errors.append("pivot: expected finite normalized Vector2")
	var animations: Variant = entry.get(&"animations")
	if typeof(animations) != TYPE_DICTIONARY:
		errors.append("animations: expected Dictionary")
	elif typeof(frames) == TYPE_INT and int(frames) > 0:
		_validate_animations(id, animations, int(frames), errors)
	if generated:
		_validate_generated_entry(entry, frames, size, errors)
	elif legacy_atlas:
		_validate_legacy_atlas_entry(entry, frames, errors)
	return errors


func _validate_legacy_atlas_entry(
	entry: Dictionary, frames: Variant, errors: PackedStringArray
) -> void:
	var columns: Variant = entry.get(&"columns")
	if typeof(columns) != TYPE_INT or int(columns) < 1:
		errors.append("columns: expected positive int")
	elif typeof(frames) == TYPE_INT and int(columns) > int(frames):
		errors.append("columns: cannot exceed frame count")
	var display_size: Variant = entry.get(&"display_size")
	if typeof(display_size) != TYPE_VECTOR2I or display_size.x <= 0 or display_size.y <= 0:
		errors.append("display_size: expected positive Vector2i")


func _validate_generated_entry(
	entry: Dictionary, frames: Variant, size: Variant, errors: PackedStringArray
) -> void:
	var columns: Variant = entry.get(&"columns")
	if typeof(columns) != TYPE_INT or int(columns) != 8:
		errors.append("columns: generated atlas expected exactly 8")
	if typeof(size) == TYPE_VECTOR2I and size != Vector2i(640, 640):
		errors.append("size: generated atlas expected 640x640 cell")
	var provenance: Variant = entry.get(&"provenance")
	if typeof(provenance) != TYPE_DICTIONARY:
		errors.append("provenance: expected Dictionary")
		return
	for key: StringName in [
		&"class_id", &"gender", &"action", &"direction", &"source_kind",
		&"mirrored_from", &"source_manifest_id", &"atlas_sha256",
	]:
		var stored: Variant = provenance.get(key)
		if typeof(stored) != TYPE_STRING or String(stored).is_empty() and key != &"mirrored_from":
			errors.append("provenance.%s: expected String" % key)
	var gender := String(provenance.get(&"gender", ""))
	var action := String(provenance.get(&"action", ""))
	var direction := String(provenance.get(&"direction", ""))
	var source_kind := String(provenance.get(&"source_kind", ""))
	var mirrored_from := String(provenance.get(&"mirrored_from", ""))
	var atlas_sha256 := String(provenance.get(&"atlas_sha256", ""))
	if gender not in ["female", "male"]:
		errors.append("provenance.gender: expected female or male")
	if action not in ["idle", "attack"]:
		errors.append("provenance.action: expected idle or attack")
	if direction not in ["ne", "nw"]:
		errors.append("provenance.direction: expected NE or NW")
	if source_kind not in ["generated", "mirrored"]:
		errors.append("provenance.source_kind: expected generated or mirrored")
	elif source_kind == "generated" and (direction != "ne" or not mirrored_from.is_empty()):
		errors.append("provenance: generated atlas must be NE with empty mirrored_from")
	elif source_kind == "mirrored":
		var expected_source := "ne" if direction == "nw" else ""
		if expected_source.is_empty() or mirrored_from != expected_source:
			errors.append("provenance: mirrored atlas source direction mismatch")
	if atlas_sha256.length() != 64 or not atlas_sha256.is_valid_hex_number(false):
		errors.append("provenance.atlas_sha256: expected 64 lowercase hexadecimal characters")
	elif atlas_sha256 != atlas_sha256.to_lower():
		errors.append("provenance.atlas_sha256: expected lowercase hexadecimal characters")


static func legacy_pivot(id: StringName, frames: int) -> Vector2:
	if frames > 1 and not String(id).begins_with("portrait_"):
		return Vector2(0.5, 1.0)
	return Vector2(0.5, 0.5)


static func legacy_animations(frames: int) -> Dictionary:
	if frames == 5:
		return {
			&"idle": {&"start": 0, &"length": 2, &"fps": 5.5, &"loop": true},
			&"attack": {&"start": 2, &"length": 2, &"fps": 8.0, &"loop": false},
			&"deploy": {&"start": 4, &"length": 1, &"fps": 1.0, &"loop": false},
		}
	if frames == 2:
		return {&"walk": {&"start": 0, &"length": 2, &"fps": 5.5, &"loop": true}}
	return {&"default": {&"start": 0, &"length": 1, &"fps": 1.0, &"loop": true}}


func _validate_animations(
	id: StringName, animations: Dictionary, frames: int, errors: PackedStringArray
) -> void:
	if animations.is_empty():
		errors.append("animations: at least one region required")
	var names: Array[StringName] = []
	for raw_name: Variant in animations:
		if typeof(raw_name) != TYPE_STRING_NAME or raw_name == &"":
			errors.append("animations: expected nonempty StringName key")
			continue
		var raw_region: Variant = animations[raw_name]
		if typeof(raw_region) != TYPE_DICTIONARY:
			errors.append("animations.%s: expected Dictionary" % raw_name)
			continue
		names.append(raw_name)
		_validate_region(raw_name, raw_region, frames, errors)
	for i: int in names.size():
		for j: int in range(i + 1, names.size()):
			var a: Dictionary = animations[names[i]]
			var b: Dictionary = animations[names[j]]
			if _regions_overlap(a, b) and a != b:
				errors.append("animations: non-identical overlap %s/%s" % [names[i], names[j]])
	var expected := legacy_animations(frames)
	if frames in [1, 2, 5] and animations != expected:
		errors.append("animations: %s does not match pinned legacy mapping" % id)


func _validate_region(
	name: StringName, region: Dictionary, frames: int, errors: PackedStringArray
) -> void:
	if region.size() != REGION_KEYS.size():
		errors.append("animations.%s: expected exact four fields" % name)
	for key: StringName in REGION_KEYS:
		if not region.has(key):
			errors.append("animations.%s: missing %s" % [name, key])
	for raw_key: Variant in region:
		if typeof(raw_key) != TYPE_STRING_NAME or not REGION_KEYS.has(raw_key):
			errors.append("animations.%s: unexpected key %s" % [name, raw_key])
	if typeof(region.get(&"start")) != TYPE_INT or int(region.get(&"start", -1)) < 0:
		errors.append("animations.%s.start: expected nonnegative int" % name)
	if typeof(region.get(&"length")) != TYPE_INT or int(region.get(&"length", 0)) < 1:
		errors.append("animations.%s.length: expected positive int" % name)
	if typeof(region.get(&"fps")) != TYPE_FLOAT or not is_finite(float(region.get(&"fps", 0.0))) \
		or float(region.get(&"fps", 0.0)) <= 0.0:
		errors.append("animations.%s.fps: expected positive finite float" % name)
	if typeof(region.get(&"loop")) != TYPE_BOOL:
		errors.append("animations.%s.loop: expected bool" % name)
	if typeof(region.get(&"start")) == TYPE_INT and typeof(region.get(&"length")) == TYPE_INT:
		var start := int(region[&"start"])
		var length := int(region[&"length"])
		if start >= 0 and length >= 1 \
			and (start > frames or length > frames - start):
			errors.append("animations.%s: region out of bounds" % name)


static func _regions_overlap(a: Dictionary, b: Dictionary) -> bool:
	if typeof(a.get(&"start")) != TYPE_INT or typeof(a.get(&"length")) != TYPE_INT \
		or typeof(b.get(&"start")) != TYPE_INT or typeof(b.get(&"length")) != TYPE_INT:
		return false
	var a_start := int(a[&"start"])
	var a_length := int(a[&"length"])
	var b_start := int(b[&"start"])
	var b_length := int(b[&"length"])
	if a_start < 0 or a_length < 1 or b_start < 0 or b_length < 1:
		return false
	if a_start <= b_start:
		return b_start - a_start < a_length
	return a_start - b_start < b_length


static func _normalized_vector(value: Vector2) -> bool:
	return is_finite(value.x) and is_finite(value.y) and value.x >= 0.0 and value.x <= 1.0 \
		and value.y >= 0.0 and value.y <= 1.0
