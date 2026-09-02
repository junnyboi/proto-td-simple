extends SceneTree

const CampaignDefType := preload("res://data/campaign_def.gd")
const CampaignV3CodecType := preload("res://sim/campaign_v3_codec.gd")
const CampaignRuntimeContextType := preload("res://sim/campaign_runtime_context.gd")
const PortraitCatalogType := preload("res://data/presentation/operator_portrait_catalog.gd")
const VisualCatalogType := preload("res://data/presentation/operator_visual_catalog.gd")

const EXPECTED_CLASSES := ["gunner", "mage_apprentice", "recruit", "swordmaster"]
const EXPECTED_OPERATORS := ["caster_1", "guard_1", "recruit", "sniper_1"]
const EXPECTED_SKILLS := ["conflagration", "deadeye", "flurry"]
const EXPECTED_SPECIALIZATIONS: Array[StringName] = [
	&"gunner", &"mage_apprentice", &"swordmaster",
]
const EXPECTED_VISUALS: Array[StringName] = [
	&"caster_1",
	&"guard_1",
	&"gunner_female",
	&"gunner_male",
	&"mage_apprentice_female",
	&"mage_apprentice_male",
	&"recruit_female",
	&"recruit_male",
	&"sniper_1",
	&"swordmaster_female",
	&"swordmaster_male",
]
const REMOVED_CLASSES := [
	"banner_guard", "defender", "immovable", "shock_trooper",
	"sniper", "sorcerer", "sword_saint", "witch_doctor",
]
const REMOVED_OPERATORS := [
	"caster_2", "defender_1", "defender_2", "guard_2",
	"sniper_2", "vanguard_1", "vanguard_2", "witch_doctor_1",
]

var _failures: Array[String] = []


func _init() -> void:
	_test_exact_data_catalogs()
	_test_class_graph()
	_test_presentation_catalogs()
	_test_removed_assets_absent()
	_test_manifest_integrity()
	_test_campaign_context()
	if _failures.is_empty():
		print("CLASS_ROSTER_PRUNE_TEST_OK")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)


func _test_exact_data_catalogs() -> void:
	_check(_resource_ids("res://data/classes") == EXPECTED_CLASSES, "class catalog is not the exact four-class roster")
	_check(_resource_ids("res://data/operators") == EXPECTED_OPERATORS, "operator catalog contains a removed implementation")
	_check(_resource_ids("res://data/skills") == EXPECTED_SKILLS, "skill catalog contains a removed-class skill")


func _test_class_graph() -> void:
	var recruit := load("res://data/classes/recruit.tres")
	_check(recruit != null, "Recruit class resource is missing")
	if recruit != null:
		var promotions: Array[String] = []
		for class_id: StringName in recruit.promotion_to_class_ids:
			promotions.append(String(class_id))
		promotions.sort()
		_check(promotions == ["gunner", "mage_apprentice", "swordmaster"], "Recruit promotion choices are not the three retained specializations")
	for class_id: String in ["gunner", "mage_apprentice", "swordmaster"]:
		var definition = load("res://data/classes/%s.tres" % class_id)
		_check(definition != null, "%s class resource is missing" % class_id)
		if definition != null:
			_check(definition.promotion_from_class_id == &"recruit", "%s must promote directly from Recruit" % class_id)
			_check(definition.promotion_to_class_ids.is_empty(), "%s must be a terminal specialization" % class_id)


func _test_presentation_catalogs() -> void:
	_check(PortraitCatalogType.SPECIALIZATION_CLASS_IDS == EXPECTED_SPECIALIZATIONS, "portrait catalog exposes removed specializations")
	_check(PortraitCatalogType.validate_contract().is_empty(), "portrait catalog contract failed")
	_check(VisualCatalogType.template_ids() == EXPECTED_VISUALS, "visual catalog exposes removed class templates")
	for error: String in VisualCatalogType.validate_all():
		_failures.append("visual catalog: %s" % error)


func _test_removed_assets_absent() -> void:
	for class_id: String in REMOVED_CLASSES:
		_check(not FileAccess.file_exists("res://data/classes/%s.tres" % class_id), "removed class resource remains: %s" % class_id)
		_check(not _directory_exists("res://assets/sprites/operators/animated/%s" % class_id), "removed class sprite directory remains: %s" % class_id)
		for variant: String in ["female", "male"]:
			_check(not FileAccess.file_exists("res://assets/portraits/specializations/%s_%s.png" % [class_id, variant]), "removed specialization portrait remains: %s/%s" % [class_id, variant])
	for operator_id: String in REMOVED_OPERATORS:
		_check(not FileAccess.file_exists("res://data/operators/%s.tres" % operator_id), "removed operator resource remains: %s" % operator_id)
		_check(not FileAccess.file_exists("res://assets/portraits/%s.png" % operator_id), "removed operator portrait remains: %s" % operator_id)
		_check(not _directory_exists("res://assets/sprites/operators/animated/%s" % operator_id), "removed operator sprite directory remains: %s" % operator_id)


func _test_manifest_integrity() -> void:
	var manifest = load("res://assets/manifest.tres")
	_check(manifest != null, "asset manifest failed to load")
	if manifest == null:
		return
	var diagnostics: PackedStringArray = manifest.validate_contract()
	_check(diagnostics.is_empty(), "asset manifest contract failed: %s" % diagnostics)
	for raw_id: Variant in manifest.entries:
		var asset_id := String(raw_id)
		_check(not _is_removed_manifest_id(asset_id), "retired manifest entry remains: %s" % asset_id)
		var pattern := String((manifest.entries[raw_id] as Dictionary).get("pattern", ""))
		var probe := pattern.replace("%d", "0")
		_check(FileAccess.file_exists(probe), "manifest path is missing: %s -> %s" % [asset_id, probe])


func _test_campaign_context() -> void:
	var campaign := load("res://data/campaigns/p16_v3.tres") as CampaignDefType
	var operators := _resources("res://data/operators")
	var classes := _resources("res://data/classes")
	var traps: Array = []
	for trap_id: String in _resource_ids("res://data/traps"):
		traps.append(StringName(trap_id))
	var stages: Array = []
	for stage_number: int in range(1, 11):
		stages.append(load("res://data/stages/s%d.tres" % stage_number))
	var text_entries := {}
	for definition in classes:
		text_entries[String(definition.name_key)] = definition.name
		text_entries[String(definition.role_key)] = definition.role
		text_entries[String(definition.description_key)] = definition.description
	var derived := CampaignV3CodecType.derive_environment_sha256(
		operators, classes, traps, stages, campaign, text_entries,
	)
	_check(bool(derived.get("accepted", false)), "four-class campaign environment could not be derived")
	if bool(derived.get("accepted", false)):
		var environment := String(derived.get("value", ""))
		print("CLASS_ROSTER_ENVIRONMENT_SHA256=%s" % environment)
		_check(environment == campaign.environment_sha256, "campaign resource environment hash is stale")
		_check(environment == CampaignDefType.P16_V3_ENVIRONMENT_SHA256, "campaign code environment hash is stale")
	var context := CampaignRuntimeContextType.build()
	_check(not context.is_empty(), "production campaign context rejected the four-class roster")
	if not context.is_empty():
		_check((context.get("class_rows", []) as Array).size() == 4, "runtime context does not contain exactly four classes")
	for stage in stages:
		_check(Array(stage.recovery_roster) == [&"caster_1", &"guard_1", &"sniper_1"], "%s recovery roster exposes a removed operator" % stage.id)


func _resource_ids(path: String) -> Array[String]:
	var directory := DirAccess.open(path)
	if directory == null:
		return []
	var result: Array[String] = []
	for filename: String in directory.get_files():
		var source := filename.trim_suffix(".remap")
		if source.ends_with(".tres"):
			result.append(source.trim_suffix(".tres"))
	result.sort()
	return result


func _resources(path: String) -> Array:
	var result: Array = []
	for resource_id: String in _resource_ids(path):
		result.append(load("%s/%s.tres" % [path, resource_id]))
	return result


func _directory_exists(path: String) -> bool:
	return DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path))


func _is_removed_manifest_id(asset_id: String) -> bool:
	if asset_id in REMOVED_OPERATORS:
		return true
	for operator_id: String in REMOVED_OPERATORS:
		if asset_id == "portrait_%s" % operator_id or asset_id.begins_with("op_anim_%s_" % operator_id):
			return true
	for class_id: String in REMOVED_CLASSES:
		if asset_id.begins_with("portrait_specialization_%s_" % class_id):
			return true
		for gender: String in ["female", "male"]:
			if asset_id.begins_with("op_anim_%s_%s_" % [class_id, gender]):
				return true
	return false


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
