class_name OperatorAnimationDef
extends Resource

## View-only companion resource for one operator template. The simulation never
## loads or hashes this presentation contract.

const DIRECTIONS: Array[StringName] = [&"ne", &"nw"]

@export var schema_version: int = 1
@export var visual_id: StringName = &""
@export var idle_by_direction: Dictionary = {}
@export var attack_by_direction: Dictionary = {}
@export var idle_frame_count: int = 24
@export var attack_frame_count: int = 13
@export var fps: float = 12.0
@export var pivot: Vector2 = Vector2(0.5, 0.94)
@export var source_cell_px: int = 192
@export var display_height_px: int = 64
@export var normalized_subject_height_px: int = 168
@export var placeholder: bool = true
@export var placeholder_source_by_logical_id: Dictionary = {}


func validate_contract() -> PackedStringArray:
	var errors := PackedStringArray()
	if schema_version not in [1, 2]:
		errors.append("schema_version: expected 1 or 2")
	if visual_id.is_empty():
		errors.append("visual_id: expected nonempty StringName")
	_validate_direction_map(&"idle", idle_by_direction, errors)
	_validate_direction_map(&"attack", attack_by_direction, errors)
	if idle_frame_count != 24:
		errors.append("idle_frame_count: expected 24")
	if attack_frame_count != 13:
		errors.append("attack_frame_count: expected 13")
	if not is_equal_approx(fps, 12.0):
		errors.append("fps: expected 12.0")
	if not pivot.is_finite() or pivot.x < 0.0 or pivot.x > 1.0 or pivot.y < 0.0 or pivot.y > 1.0:
		errors.append("pivot: expected finite normalized Vector2")
	if schema_version == 1 and source_cell_px != 192:
		errors.append("source_cell_px: schema 1 expected 192")
	if schema_version == 2 and source_cell_px != 640:
		errors.append("source_cell_px: schema 2 expected 640")
	if schema_version == 2 and not pivot.is_equal_approx(Vector2(0.5, 1.0)):
		errors.append("pivot: schema 2 expected bottom-center (0.5, 1.0)")
	if display_height_px <= 0:
		errors.append("display_height_px: expected positive int")
	if normalized_subject_height_px <= 0 or normalized_subject_height_px > source_cell_px:
		errors.append("normalized_subject_height_px: expected 1..source_cell_px")
	if schema_version == 2 and placeholder:
		errors.append("placeholder: schema 2 generated animation must be production art")
	_validate_placeholders(errors)
	return errors


func is_placeholder(logical_id: StringName) -> bool:
	return placeholder_source_by_logical_id.has(logical_id)


func placeholder_source_direction(logical_id: StringName) -> StringName:
	var stored: Variant = placeholder_source_by_logical_id.get(logical_id, &"")
	return stored if typeof(stored) == TYPE_STRING_NAME else &""


func _validate_placeholders(errors: PackedStringArray) -> void:
	if placeholder != (not placeholder_source_by_logical_id.is_empty()):
		errors.append("placeholder: expected to match exact placeholder source map")
	var admitted_ids: Dictionary = {}
	for mapping: Dictionary in [idle_by_direction, attack_by_direction]:
		for raw_id: Variant in mapping.values():
			if typeof(raw_id) == TYPE_STRING_NAME:
				admitted_ids[raw_id] = true
	for raw_id: Variant in placeholder_source_by_logical_id:
		if typeof(raw_id) != TYPE_STRING_NAME or not admitted_ids.has(raw_id):
			errors.append("placeholder_source_by_logical_id: unknown logical id %s" % raw_id)
			continue
		var raw_direction: Variant = placeholder_source_by_logical_id[raw_id]
		if typeof(raw_direction) != TYPE_STRING_NAME or raw_direction not in DIRECTIONS:
			errors.append(
				"placeholder_source_by_logical_id.%s: expected admitted source direction" % raw_id
			)


static func _validate_direction_map(
	label: StringName, value: Dictionary, errors: PackedStringArray
) -> void:
	if value.size() != DIRECTIONS.size():
		errors.append("%s_by_direction: expected exact NE/NW directions" % label)
		return
	var seen_ids: Dictionary = {}
	for direction: StringName in DIRECTIONS:
		if not value.has(direction):
			errors.append("%s_by_direction: missing %s" % [label, direction])
			continue
		var logical_id: Variant = value[direction]
		if typeof(logical_id) != TYPE_STRING_NAME or StringName(logical_id).is_empty():
			errors.append("%s_by_direction.%s: expected nonempty StringName" % [label, direction])
			continue
		if seen_ids.has(logical_id):
			errors.append("%s_by_direction: duplicate logical id %s" % [label, logical_id])
		seen_ids[logical_id] = true
	for raw_direction: Variant in value:
		if typeof(raw_direction) != TYPE_STRING_NAME or raw_direction not in DIRECTIONS:
			errors.append("%s_by_direction: unknown direction %s" % [label, raw_direction])
