class_name OperatorPortraitCatalog
extends RefCounted

## Presentation-only identity and promoted-class routing for recruit portraits.
##
## Campaign identity, command payloads, receipts, save bytes, and promotion
## authority stay unchanged. The already-persisted Recruit identity portrait
## selects a deterministic gender variant. Recruit operators display that
## identity; promoted operators display their matching specialization portrait.

const FEMALE: StringName = &"female"
const MALE: StringName = &"male"

const IDENTITY_VARIANT_BY_PORTRAIT := {
	&"portrait_recruit_00": FEMALE,
	&"portrait_recruit_01": MALE,
	&"portrait_recruit_02": FEMALE,
	&"portrait_recruit_03": MALE,
	&"portrait_recruit_04": FEMALE,
	&"portrait_recruit_05": MALE,
	&"portrait_recruit_06": FEMALE,
	&"portrait_recruit_07": MALE,
}

const SPECIALIZATION_CLASS_IDS: Array[StringName] = [
	&"gunner",
	&"mage_apprentice",
	&"swordmaster",
]


static func identity_variant(portrait_asset_id: StringName) -> StringName:
	var explicit_variant := explicit_identity_variant(portrait_asset_id)
	return explicit_variant if explicit_variant != &"" else FEMALE


static func explicit_identity_variant(portrait_asset_id: StringName) -> StringName:
	var identity_variant_value: Variant = IDENTITY_VARIANT_BY_PORTRAIT.get(
		portrait_asset_id,
	)
	if typeof(identity_variant_value) == TYPE_STRING_NAME:
		return identity_variant_value
	var portrait_text := String(portrait_asset_id)
	if portrait_text.begins_with("portrait_specialization_"):
		if portrait_text.ends_with("_female"):
			return FEMALE
		if portrait_text.ends_with("_male"):
			return MALE
	return &""


static func specialization_asset_id(
		class_id: StringName,
		identity_portrait_asset_id: StringName,
	) -> StringName:
	if not SPECIALIZATION_CLASS_IDS.has(class_id):
		return &""
	return StringName(
		"portrait_specialization_%s_%s" % [
			class_id,
			identity_variant(identity_portrait_asset_id),
		]
		)


static func presentation_asset_id(
		class_id: StringName,
		identity_portrait_asset_id: StringName,
	) -> StringName:
	if identity_portrait_asset_id == &"":
		return identity_portrait_asset_id
	var specialization_id := specialization_asset_id(class_id, identity_portrait_asset_id)
	return identity_portrait_asset_id if specialization_id == &"" else specialization_id


static func specialization_asset_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for class_id: StringName in SPECIALIZATION_CLASS_IDS:
		for variant: StringName in [FEMALE, MALE]:
			result.append(StringName(
				"portrait_specialization_%s_%s" % [class_id, variant]
			))
	return result


static func validate_contract() -> PackedStringArray:
	var errors := PackedStringArray()
	if IDENTITY_VARIANT_BY_PORTRAIT.size() != 8:
		errors.append("identity variants: expected exactly eight Recruit portraits")
	for index: int in 8:
		var asset_id := StringName("portrait_recruit_%02d" % index)
		if not IDENTITY_VARIANT_BY_PORTRAIT.has(asset_id):
			errors.append("identity variants: missing %s" % asset_id)
			continue
		var expected := FEMALE if index % 2 == 0 else MALE
		if IDENTITY_VARIANT_BY_PORTRAIT[asset_id] != expected:
			errors.append("identity variants: %s expected %s" % [asset_id, expected])
	if SPECIALIZATION_CLASS_IDS.size() != 3:
		errors.append("specializations: expected exactly three classes")
	var unique := {}
	for asset_id: StringName in specialization_asset_ids():
		if unique.has(asset_id):
			errors.append("specializations: duplicate %s" % asset_id)
		unique[asset_id] = true
	return errors
