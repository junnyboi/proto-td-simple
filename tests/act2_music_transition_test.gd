extends SceneTree

const TRANSITION_SCRIPT := preload("res://scripts/ui/components/act2_stage_transition.gd")
const PROFILE_PATH := "res://data/presentation/audio/lunaris_profile.tres"
const EXPECTED := {
	&"act2_s09": &"lunaris_act2_s09_return_path",
	&"act2_s10": &"lunaris_act2_s10_covenant_orchard",
}

var _failures: Array[String] = []
var _music: Node = null


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_music = root.get_node_or_null("Music")
	_check(_music != null, "Music autoload is missing")
	_test_profile_and_stage_routes()
	await _test_runtime_music_routes()
	await _test_transition_component()
	_music.stop()
	for _frame: int in 16:
		await process_frame
	await create_timer(0.25, true, false, true).timeout
	if _failures.is_empty():
		print("ACT2_MUSIC_TRANSITION_TEST_OK")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)


func _test_profile_and_stage_routes() -> void:
	var profile := load(PROFILE_PATH) as MusicProfile
	var catalog := load("res://assets/music/catalog.tres") as MusicCatalog
	_check(profile != null and profile.is_valid(), "Act II music profile is invalid")
	_check(catalog != null, "music catalog did not load")
	var cue_ids: Dictionary = {}
	for stage_number: int in range(9, 11):
		var variant := StringName("act2_s%02d" % stage_number)
		var cue_id: StringName = EXPECTED[variant]
		cue_ids[cue_id] = true
		var stage := load("res://data/stages/s%d.tres" % stage_number) as StageDef
		_check(stage != null, "S%d did not load" % stage_number)
		if stage != null:
			_check(stage.music_variant_id == variant, "S%d does not route its unique variant" % stage_number)
		for state_id: StringName in [&"low", &"medium", &"high", &"critical"]:
			_check(profile.cue_id_for(variant, state_id) == cue_id, "%s/%s route mismatch" % [variant, state_id])
		var cue := catalog.entries.get(cue_id) as AudioCue
		_check(cue != null and cue.is_valid(), "%s cue is invalid" % cue_id)
		if cue != null:
			_check(cue.loop, "%s must loop" % cue_id)
			_check(cue.approved_surfaces.has(&"battle"), "%s is not approved for battle" % cue_id)
			_check(ResourceLoader.exists(cue.stream_path), "%s stream is missing" % cue_id)
	_check(cue_ids.size() == 2, "Act II stages do not have two distinct cue IDs")


func _test_runtime_music_routes() -> void:
	_music.stop()
	for stage_number: int in range(9, 11):
		var variant := StringName("act2_s%02d" % stage_number)
		var cue_id: StringName = EXPECTED[variant]
		_check(_music.play_battle(&"lunaris", variant, &"low"), "%s did not start" % variant)
		await process_frame
		_check(_music.current_id() == cue_id, "%s started the wrong cue" % variant)
		_check(_music.current_stream_path().contains("/act2/"), "%s did not load an Act II stream" % variant)
		var starts_before: int = _music.start_count()
		_check(_music.request_battle_state(&"medium"), "%s medium request failed" % variant)
		_check(_music.pending_state_id().is_empty(), "%s incorrectly queued its same-cue medium state" % variant)
		_check(_music.current_state_id() == &"medium", "%s medium state was not accepted" % variant)
		_check(_music.start_count() == starts_before, "%s restarted on a same-cue state" % variant)
		_check(_music.request_battle_state(&"critical", true), "%s critical request failed" % variant)
		_check(_music.current_state_id() == &"critical", "%s critical state was not accepted" % variant)
		_check(is_equal_approx(float(_music.current_tempo_scale()), 1.0), "%s did not preserve authored tempo" % variant)


func _test_transition_component() -> void:
	var smooth := TRANSITION_SCRIPT.new() as Act2StageTransition
	root.add_child(smooth)
	_check(is_equal_approx(smooth.transition_duration(true, false), 1.38), "smooth entry duration changed")
	_check(is_equal_approx(smooth.transition_duration(false, false), 0.42), "smooth exit duration changed")
	var flags := {"smooth": false, "reduced": false, "exit": false}
	smooth.entry_finished.connect(func() -> void: flags["smooth"] = true)
	smooth.play_entry(9, "The Green Cage", false)
	await create_timer(1.55, true, false, true).timeout
	_check(bool(flags["smooth"]), "smooth Act II entry did not finish")
	var reduced := TRANSITION_SCRIPT.new() as Act2StageTransition
	root.add_child(reduced)
	reduced.entry_finished.connect(func() -> void: flags["reduced"] = true)
	reduced.play_entry(10, "Rain Debt", true)
	await create_timer(0.25, true, false, true).timeout
	_check(bool(flags["reduced"]), "reduced-motion Act II entry did not finish promptly")
	var exit_transition := TRANSITION_SCRIPT.new() as Act2StageTransition
	root.add_child(exit_transition)
	exit_transition.exit_finished.connect(func() -> void: flags["exit"] = true)
	exit_transition.play_exit(10, "Rain Debt", false)
	await create_timer(0.55, true, false, true).timeout
	_check(bool(flags["exit"]), "smooth Act II exit did not finish")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
