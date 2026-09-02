class_name OperatorVisualCatalog
extends RefCounted

## Exact admitted-template catalog. Unknown or unapproved templates return null
## and BattleView preserves the incumbent legacy body projection.

const OperatorAnimationDefType := preload("res://data/presentation/operator_animation_def.gd")
const OperatorPortraitCatalogType := preload(
	"res://data/presentation/operator_portrait_catalog.gd"
)
const DEFINITIONS: Dictionary = {
	&"caster_1": preload("res://data/presentation/operator_visuals/caster_1.tres"),
	&"gunner_female": preload("res://data/presentation/operator_visuals/gunner_female.tres"),
	&"gunner_male": preload("res://data/presentation/operator_visuals/gunner_male.tres"),
	&"guard_1": preload("res://data/presentation/operator_visuals/guard_1.tres"),
	&"mage_apprentice_female": preload("res://data/presentation/operator_visuals/mage_apprentice_female.tres"),
	&"mage_apprentice_male": preload("res://data/presentation/operator_visuals/mage_apprentice_male.tres"),
	&"recruit_female": preload("res://data/presentation/operator_visuals/recruit_female.tres"),
	&"recruit_male": preload("res://data/presentation/operator_visuals/recruit_male.tres"),
	&"sniper_1": preload("res://data/presentation/operator_visuals/sniper_1.tres"),
	&"swordmaster_female": preload("res://data/presentation/operator_visuals/swordmaster_female.tres"),
	&"swordmaster_male": preload("res://data/presentation/operator_visuals/swordmaster_male.tres"),
}
const ADVANCED_CLASS_IDS: Dictionary = {
	&"gunner": true,
	&"mage_apprentice": true,
	&"swordmaster": true,
}
const VISUAL_ALIASES: Dictionary = {}
static func template_for_unit(
	op_id: StringName,
	portrait_asset_id: StringName,
	hero_id: StringName,
	unit_id: int,
	class_id: StringName = &"",
) -> StringName:
	var advanced_class: Variant = class_id if ADVANCED_CLASS_IDS.has(class_id) else null
	if typeof(advanced_class) == TYPE_STRING_NAME:
		var identity_gender := OperatorPortraitCatalogType.explicit_identity_variant(
			portrait_asset_id,
		)
		if identity_gender == &"":
			identity_gender = deterministic_identity_gender(hero_id, portrait_asset_id, unit_id)
		return StringName(
			"%s_%s"
			% [advanced_class, identity_gender]
		)
	if op_id != &"recruit":
		return op_id
	return StringName(
		"recruit_%s" % deterministic_identity_gender(hero_id, portrait_asset_id, unit_id)
	)


static func deterministic_identity_gender(
	hero_id: StringName, portrait_asset_id: StringName, unit_id: int
) -> StringName:
	var identity := String(hero_id)
	if identity.is_empty():
		identity = String(portrait_asset_id)
	var parity := posmod(unit_id, 2) if identity.is_empty() else 0
	for index: int in identity.length():
		parity = posmod(parity + identity.unicode_at(index), 2)
	return &"female" if parity == 0 else &"male"


static func get_animation(template_id: StringName) -> OperatorAnimationDefType:
	var resolved_id := StringName(VISUAL_ALIASES.get(template_id, template_id))
	var value: Variant = DEFINITIONS.get(resolved_id)
	return value as OperatorAnimationDefType if value is OperatorAnimationDefType else null


static func first_idle_art_id_for_unit(
	op_id: StringName,
	portrait_asset_id: StringName,
	hero_id: StringName,
	unit_id: int,
	class_id: StringName = &"",
	direction: StringName = &"nw",
) -> StringName:
	var template_id := template_for_unit(
		op_id, portrait_asset_id, hero_id, unit_id, class_id,
	)
	var animation := get_animation(template_id)
	if animation == null:
		return &""
	return StringName(animation.idle_by_direction.get(direction, &""))


static func template_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for raw_id: Variant in DEFINITIONS:
		if typeof(raw_id) == TYPE_STRING_NAME:
			result.append(raw_id)
	result.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return result


static func validate_all() -> PackedStringArray:
	return validate_definitions(DEFINITIONS, true)


static func validate_definitions(
	definitions: Dictionary, check_manifest: bool
) -> PackedStringArray:
	var errors := PackedStringArray()
	var visual_ids: Dictionary = {}
	for raw_template_id: Variant in definitions:
		if typeof(raw_template_id) != TYPE_STRING_NAME or StringName(raw_template_id).is_empty():
			errors.append("catalog: expected nonempty StringName template id")
			continue
		var template_id := StringName(raw_template_id)
		var animation := definitions[template_id] as OperatorAnimationDefType
		if animation == null:
			errors.append("%s: expected OperatorAnimationDef" % template_id)
			continue
		for message: String in animation.validate_contract():
			errors.append("%s: %s" % [template_id, message])
		if visual_ids.has(animation.visual_id):
			errors.append("%s: duplicate visual_id %s" % [template_id, animation.visual_id])
		visual_ids[animation.visual_id] = true
		if check_manifest:
			_validate_manifest(template_id, animation, errors)
	return errors


static func _validate_manifest(
	template_id: StringName, animation: OperatorAnimationDefType, errors: PackedStringArray
) -> void:
	for family: StringName in [&"idle", &"attack"]:
		var mapping := animation.idle_by_direction if family == &"idle" else animation.attack_by_direction
		var expected_frames := (
			animation.idle_frame_count if family == &"idle" else animation.attack_frame_count
		)
		for direction: StringName in OperatorAnimationDefType.DIRECTIONS:
			if not mapping.has(direction):
				continue
			var logical_id := StringName(mapping[direction])
			if Art.frame_count(logical_id) != expected_frames:
				errors.append(
					"%s/%s/%s: manifest frame count mismatch" % [template_id, family, direction]
				)
			if Art.size(logical_id) != Vector2i.ONE * animation.source_cell_px:
				errors.append("%s/%s/%s: manifest cell mismatch" % [template_id, family, direction])
			if not is_equal_approx(Art.fps(logical_id), animation.fps):
				errors.append("%s/%s/%s: manifest fps mismatch" % [template_id, family, direction])
			var metadata := Art.metadata(logical_id)
			if metadata.is_empty():
				errors.append("%s/%s/%s: missing manifest row" % [template_id, family, direction])
			else:
				var expected_placeholder := animation.is_placeholder(logical_id)
				if bool(metadata.get(&"placeholder", true)) != expected_placeholder:
					errors.append("%s/%s/%s: placeholder mismatch" % [template_id, family, direction])
				if animation.schema_version == 2:
					if int(metadata.get(&"columns", 0)) != 8:
						errors.append("%s/%s/%s: generated columns mismatch" % [template_id, family, direction])
					if Art.pivot(logical_id) != animation.pivot:
						errors.append("%s/%s/%s: generated pivot mismatch" % [template_id, family, direction])
					var provenance: Variant = metadata.get(&"provenance")
					if provenance is not Dictionary or String(provenance.get(&"atlas_sha256", "")).is_empty():
						errors.append("%s/%s/%s: generated provenance missing" % [template_id, family, direction])
