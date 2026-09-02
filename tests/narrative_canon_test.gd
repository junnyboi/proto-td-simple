extends SceneTree

const CANON_PATH := "res://docs/NARRATIVE_CANON.md"
const CONTRACT_PATH := "res://data/presentation/narrative/canon_contract.json"
const DOCUMENT_CONCEPT_PATHS := [
	"res://docs/narrative/concept-art/anima-war/01-corrupted-protos-avatar.png",
	"res://docs/narrative/concept-art/anima-war/02-human-anima-farm.png",
	"res://docs/narrative/concept-art/anima-war/03-anima-robot-empire-castes.png",
	"res://docs/narrative/concept-art/anima-war/04-act-ii-anima-forge-capital.png",
	"res://docs/narrative/concept-art/anima-war/SHA256SUMS",
]
const REMOVED_FEATURE_PATHS := [
	"res://scenes/narrative_archive.tscn",
	"res://scripts/ui/narrative_archive.gd",
	"res://scripts/ui/components/archive_audio_log_player.gd",
	"res://scripts/ui/components/narrative_archive_unlocks.gd",
	"res://scripts/ui/battle_dialogue_presenter.gd",
	"res://assets/narrative/anima-war",
	"res://assets/audio/narrative/anima-archive",
	"res://data/presentation/narrative/stage_narrative_catalog.gd",
	"res://data/presentation/narrative/stage_narrative_catalog.tres",
	"res://data/presentation/narrative/stage_narrative_def.gd",
]
const REMOVED_NARRATIVE_FIELDS: Array[StringName] = [
	&"objective", &"threat", &"human_reason", &"clue", &"core_service",
	&"transmission_speaker", &"transmission", &"battle_start_speaker", &"battle_start",
	&"mid_wave_number", &"mid_wave_speaker", &"mid_wave", &"clear_debrief", &"defeat_debrief",
]

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for stage_index: int in range(1, 11):
		var stage_id := "s%d" % stage_index
		var stage := load("res://data/stages/%s.tres" % stage_id) as StageDef
		_check(stage != null, "missing stage record %s" % stage_id)
		if stage != null:
			_check(not _property_names(stage).has(&"intro_hint"), "removed mission tip field remains: %s.intro_hint" % stage_id)
		_check(
			not FileAccess.file_exists(
				"res://data/presentation/narrative/stages/%s.tres" % stage_id,
			),
			"removed consequence description asset remains: %s" % stage_id,
		)

	_check(FileAccess.file_exists(CANON_PATH), "canon lore document is missing")
	var canon := FileAccess.get_file_as_string(CANON_PATH)
	var contract: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CONTRACT_PATH))
	_check(not contract.is_empty(), "machine-readable canon contract is invalid")
	var bible: Dictionary = contract.get("bible", {})
	_check(String(bible.get("path", "")) == "docs/NARRATIVE_CANON.md", "canon contract points at the wrong bible")
	_check(String(bible.get("sha256", "")) == _sha256(CANON_PATH), "canon bible hash drifted without a contract update")
	_check(int(contract.get("schema_version", 0)) == 4, "canon contract schema version drifted")
	for term: Variant in contract.get("required_canon_terms", []):
		_check(canon.contains(String(term)), "canon contract term is absent from bible: %s" % term)
	var required_display := contract.get("required_company_display", {}) as Dictionary
	_check(String(required_display.get("stable_key", "")) == "data.company.33.name", "Company Manus stable localization key changed")
	_check(String(required_display.get("en-US", "")) == "COMPANY MANUS", "English Company Manus display contract changed")
	_check(String(required_display.get("zh-CN", "")) == "MANUS连队", "Chinese Company Manus display contract changed")
	_check(not contract.has("phase6_temporary_waivers"), "Phase 6 canon waivers must be removed")
	_check(not contract.has("archive_unlock_gates"), "removed archive unlock contract returned")
	var compatibility := contract.get("campaign_compatibility", {}) as Dictionary
	var runtime_context := CampaignRuntimeContext.build()
	_check(not runtime_context.is_empty(), "campaign compatibility context failed to build")
	if not runtime_context.is_empty():
		_check(
			String(runtime_context.get("environment_sha256", "")) == String(compatibility.get("environment_sha256", "")),
			"narrative migration changed the protected gameplay environment fingerprint",
		)
		_check(String(compatibility.get("save_schema", "")) == CampaignV3Codec.SAVE_SCHEMA, "campaign save schema drifted")
		_check(int(compatibility.get("save_version", 0)) == CampaignV3Codec.SAVE_VERSION, "campaign save version drifted")
		var created := CampaignStateV3.create(
			int(compatibility.get("fixture_seed", 0)),
			int(compatibility.get("fixture_generation", 0)),
			runtime_context,
		)
		_check(created.get("accepted", false), "deterministic campaign compatibility fixture failed to create")
		if created.get("accepted", false):
			var fixture: CampaignStateV3 = created["value"]
			var encoded := fixture.encode_save()
			_check(
				_sha256_text(String(encoded.get("text", ""))) == String(compatibility.get("fresh_save_text_sha256", "")),
				"fresh Campaign V3 save bytes changed during narrative migration",
			)
			_check(
				String(fixture.strategic_hash().get("hex", "")) == String(compatibility.get("fresh_strategic_hash", "")),
				"fresh campaign strategic hash changed during narrative migration",
			)
			_check(
				String(fixture.core_hash().get("hex", "")) == String(compatibility.get("fresh_core_hash", "")),
				"fresh campaign core hash changed during narrative migration",
			)
			var restored := CampaignStateV3.restore_source(String(encoded.get("text", "")), runtime_context)
			_check(restored.get("accepted", false), "fresh Campaign V3 fixture no longer round-trips")
			if restored.get("accepted", false):
				var projection: Dictionary = restored["value"].runtime_projection()
				_check(projection.get("stage_ids", []).size() == 10, "round-tripped campaign lost stage order")
				_check(projection.get("ready_heroes", []).size() == 5, "round-tripped campaign lost starter roster")
				_check(int(projection.get("marks", -1)) == 120, "round-tripped campaign changed Marks")
				_check((projection.get("stage_stars", {}) as Dictionary).is_empty(), "round-tripped campaign invented clears")
	for path: String in DOCUMENT_CONCEPT_PATHS:
		_check(FileAccess.file_exists(path), "durable docs concept is missing: %s" % path)
	for removed_path: String in REMOVED_FEATURE_PATHS:
		_check(
			not FileAccess.file_exists(removed_path)
			and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(removed_path)),
			"removed archive/transmission path remains: %s" % removed_path,
		)

	var i18n := root.get_node_or_null("I18n")
	_check(i18n != null, "I18n autoload missing")
	if i18n != null:
		for locale_id: StringName in [&"en-US", &"zh-CN"]:
			_check(bool(i18n.call("set_locale", locale_id)), "locale activation failed: %s" % locale_id)
			var locale_path := "res://localization/%s.json" % locale_id
			var locale_payload: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(locale_path))
			var entries: Dictionary = locale_payload.get("entries", {})
			for stage_index: int in range(1, 17):
				_check(not entries.has("data.stage.s%d.hint" % stage_index), "%s retained mission tip key for s%d" % [locale_id, stage_index])
				for field: StringName in REMOVED_NARRATIVE_FIELDS:
					_check(
						not entries.has("data.stage.s%d.narrative.%s" % [stage_index, field]),
						"%s retained mission/transmission key for s%d.%s" % [locale_id, stage_index, field],
					)
		i18n.call("set_locale", &"en-US")

	_finish()


func _property_names(resource: Resource) -> Array[StringName]:
	var names: Array[StringName] = []
	for property: Dictionary in resource.get_property_list():
		names.append(StringName(property.get("name", "")))
	return names


func _sha256(path: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(FileAccess.get_file_as_bytes(path))
	return context.finish().hex_encode()


func _sha256_text(value: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(value.to_utf8_buffer())
	return context.finish().hex_encode()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("NARRATIVE_CANON_TEST_OK")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)
