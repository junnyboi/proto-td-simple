extends SceneTree

const REMOVED_NARRATIVE_FIELDS: Array[StringName] = [
	&"objective", &"threat", &"human_reason", &"clue", &"core_service",
	&"transmission_speaker", &"transmission", &"battle_start_speaker", &"battle_start",
	&"mid_wave_number", &"mid_wave_speaker", &"mid_wave", &"clear_debrief", &"defeat_debrief",
]
const REMOVED_RUNTIME_PATHS := [
	"res://scripts/ui/battle_dialogue_presenter.gd",
	"res://test/battle_dialogue_visual_harness.gd",
	"res://tests/battle_dialogue_test.gd",
	"res://data/presentation/narrative/stage_narrative_catalog.gd",
	"res://data/presentation/narrative/stage_narrative_catalog.tres",
	"res://data/presentation/narrative/stage_narrative_def.gd",
]
const REMOVED_RESULTS_KEYS := [
	"ui.error.missing_stage_narrative",
	"ui.results.company_intact",
	"ui.results.consequence",
	"ui.results.no_losses",
]

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for stage_index: int in range(1, 17):
		var stage_id := "s%d" % stage_index
		var stage := load("res://data/stages/%s.tres" % stage_id) as StageDef
		_check(stage != null, "stage failed to load: %s" % stage_id)
		if stage != null:
			_check(not _property_names(stage).has(&"intro_hint"), "mission tip field remains: %s.intro_hint" % stage_id)
		_check(
			not FileAccess.file_exists(
				"res://data/presentation/narrative/stages/%s.tres" % stage_id,
			),
			"removed consequence description asset remains: %s" % stage_id,
		)

	for locale_id: String in ["en-US", "zh-CN"]:
		var payload: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string("res://localization/%s.json" % locale_id)
		)
		var entries: Dictionary = payload.get("entries", {})
		for stage_index: int in range(1, 17):
			_check(not entries.has("data.stage.s%d.hint" % stage_index), "%s mission tip key remains for s%d" % [locale_id, stage_index])
			for field: StringName in REMOVED_NARRATIVE_FIELDS:
				_check(
					not entries.has("data.stage.s%d.narrative.%s" % [stage_index, field]),
					"%s mission/transmission key remains for s%d.%s" % [locale_id, stage_index, field],
				)
		for key: String in REMOVED_RESULTS_KEYS:
			_check(not entries.has(key), "%s removed consequence key remains: %s" % [locale_id, key])

	for path: String in REMOVED_RUNTIME_PATHS:
		_check(not FileAccess.file_exists(path), "removed transmission runtime remains: %s" % path)

	if _failures.is_empty():
		print("MISSION_COPY_REMOVAL_TEST_OK")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)


func _property_names(resource: Resource) -> Array[StringName]:
	var names: Array[StringName] = []
	for property: Dictionary in resource.get_property_list():
		names.append(StringName(property.get("name", "")))
	return names


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
