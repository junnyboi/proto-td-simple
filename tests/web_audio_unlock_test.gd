extends SceneTree

const EXPORT_PRESETS_PATH := "res://export_presets.cfg"
const SFX_CATALOG_PATH := "res://assets/sfx/catalog.tres"
const OPERATOR_DIRECTORY := "res://data/operators"
const REQUIRED_UNLOCK_TOKENS := [
	"window.AudioContext=Wrapped",
	"window.__protosAudioContexts=contexts",
	"context.state==='suspended'",
	"context.resume()",
	"['pointerdown','touchstart','keydown']",
	"visibilitychange",
]
const REQUIRED_EVENT_ALIASES := {
	&"kill": &"operator_select",
	&"wave": &"placement_ready",
}

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var preset_text := FileAccess.get_file_as_string(EXPORT_PRESETS_PATH)
	_check(not preset_text.is_empty(), "Web export preset is unavailable")
	for token: String in REQUIRED_UNLOCK_TOKENS:
		_check(preset_text.contains(token), "Web Audio unlock token is missing: %s" % token)
	_check(
		int(ProjectSettings.get_setting("audio/general/default_playback_type", -1))
			== AudioServer.PLAYBACK_TYPE_STREAM,
		"project audio does not force the direct streaming mixer",
	)
	var music := root.get_node_or_null("Music")
	var sfx := root.get_node_or_null("Sfx")
	_check(music != null and sfx != null, "audio autoloads are unavailable")
	if music != null:
		for player_value: Variant in music.call("_ensure_players"):
			var player := player_value as AudioStreamPlayer
			_check(
				player != null and player.playback_type == AudioServer.PLAYBACK_TYPE_STREAM,
				"music player can fall back to the Web sample graph",
			)
	if sfx != null:
		for child: Node in sfx.get_children():
			if child is AudioStreamPlayer:
				_check(
					(child as AudioStreamPlayer).playback_type
						== AudioServer.PLAYBACK_TYPE_STREAM,
					"SFX voice can fall back to the Web sample graph",
				)
	var catalog := load(SFX_CATALOG_PATH) as Resource
	_check(catalog != null, "SFX catalog is unavailable")
	var entries_value: Variant = catalog.get("entries") if catalog != null else null
	var aliases_value: Variant = catalog.get("aliases") if catalog != null else null
	_check(entries_value is Dictionary, "SFX entries are unavailable")
	_check(aliases_value is Dictionary, "SFX aliases are unavailable")
	if entries_value is Dictionary and aliases_value is Dictionary:
		var entries: Dictionary = entries_value
		var aliases: Dictionary = aliases_value
		for semantic_id: StringName in REQUIRED_EVENT_ALIASES:
			_check(
				aliases.get(semantic_id, &"") == REQUIRED_EVENT_ALIASES[semantic_id]
				and _resolves_to_direct_entry(semantic_id, entries, aliases),
				"%s is not routed to an audible shipped cue" % semantic_id,
			)
		var skill_ids := _shipping_skill_ids()
		_check(not skill_ids.is_empty(), "no shipped operator skills were discovered")
		for skill_id: StringName in skill_ids:
			_check(
				_resolves_to_direct_entry(skill_id, entries, aliases),
				"shipped skill %s is not routed to a direct audible cue" % skill_id,
			)
	if _failures.is_empty():
		print("WEB_AUDIO_UNLOCK_TEST_OK")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)


func _shipping_skill_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	var files := DirAccess.get_files_at(OPERATOR_DIRECTORY)
	_check(not files.is_empty(), "shipped operator directory is unavailable")
	files.sort()
	for file_name: String in files:
		if not file_name.ends_with(".tres"):
			continue
		var path := "%s/%s" % [OPERATOR_DIRECTORY, file_name]
		var definition := load(path) as OperatorDef
		_check(definition != null, "shipped operator is unavailable: %s" % path)
		if definition == null or definition.skill == null:
			continue
		var skill_id := definition.skill.id
		_check(not skill_id.is_empty(), "shipped operator skill id is empty: %s" % path)
		if not skill_id.is_empty() and not result.has(skill_id):
			result.append(skill_id)
	return result


func _resolves_to_direct_entry(
	semantic_id: StringName,
	entries: Dictionary,
	aliases: Dictionary,
) -> bool:
	if entries.has(semantic_id):
		return true
	var target := StringName(aliases.get(semantic_id, &""))
	return not target.is_empty() and entries.has(target) and not aliases.has(target)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
