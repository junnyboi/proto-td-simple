extends SceneTree

const MUSIC_DIRECTOR_SCRIPT := preload("res://scripts/view/music_director.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var music := root.get_node_or_null("Music")
	_check(music != null, "Music autoload is available")
	if music != null:
		await _exercise_runtime(music)
	_exercise_director()
	call_deferred("_finish")


func _exercise_runtime(music: Node) -> void:
	music.call("set_enabled", true)
	music.call("stop")
	_check(bool(music.call("reload_catalog")), "expanded cue catalog loads")
	_check(bool(music.call("play_staging", &"lunaris")), "staging profile starts")
	_check(
		music.call("current_id") == &"lunaris_staging_archive_command",
		"staging resolves the command cue",
	)
	_check(bool(music.call("play_battle", &"lunaris", &"orbit_early", &"low")), "battle low starts")
	_check(music.call("current_state_id") == &"low", "battle state begins low")
	_check(bool(music.call("request_battle_state", &"medium", false)), "medium request schedules")
	_check(music.call("pending_state_id") == &"medium", "medium is pending at a bar boundary")
	_check(
		int(music.call("pending_due_msec")) >= 7000,
		"routine transition targets the next four-bar phrase",
	)
	var pending_due_before_reject := int(music.call("pending_due_msec"))
	_check(not bool(music.call("play_cue", &"missing_audio")), "missing cue rejects while pending")
	_check(music.call("pending_state_id") == &"medium", "rejected cue preserves pending state")
	_check(
		int(music.call("pending_due_msec")) == pending_due_before_reject,
		"rejected cue preserves pending timing",
	)
	_check(bool(music.call("request_battle_state", &"low", false)), "incumbent state reaffirms")
	_check(StringName(music.call("pending_state_id")).is_empty(), "incumbent state cancels stale pending route")
	_check(bool(music.call("request_battle_state", &"medium", false)), "medium request reschedules")
	_check(music.call("current_state_id") == &"low", "scheduled state does not switch early")
	_check(bool(music.call("commit_pending_now_for_test")), "pending state can be committed")
	await process_frame
	_check(music.call("current_state_id") == &"medium", "bar-safe commit switches state")
	_check(
		music.call("current_id") == &"lunaris_battle_orbit_early_medium",
		"medium state resolves the correct cue",
	)
	_check(bool(music.call("request_battle_state", &"high", true)), "danger request schedules")
	_check(
		int(music.call("pending_due_msec")) <= 2500,
		"danger transition targets the next single-bar boundary",
	)
	_check(bool(music.call("commit_pending_now_for_test")), "danger state can be committed")
	await process_frame
	_check(music.call("current_state_id") == &"high", "danger commit switches state")
	_check(bool(music.call("request_battle_state", &"critical", true)), "critical request schedules")
	_check(
		int(music.call("pending_due_msec")) <= 2500,
		"critical transition targets the next single-bar boundary",
	)
	_check(bool(music.call("commit_pending_now_for_test")), "critical state can be committed")
	await process_frame
	_check(music.call("current_state_id") == &"critical", "critical commit switches state")
	_check(
		music.call("current_id") == &"lunaris_battle_orbit_early_high",
		"critical state reuses the authored high-intensity arrangement",
	)
	_check(
		is_equal_approx(float(music.call("current_tempo_scale")), 1.08),
		"critical state raises battle tempo by eight percent",
	)
	_check(bool(music.call("request_battle_state", &"high", false)), "critical recovery schedules")
	_check(music.call("pending_state_id") == &"high", "critical recovery is pending")
	_check(bool(music.call("request_battle_state", &"critical", true)), "critical incumbent reaffirms")
	_check(
		StringName(music.call("pending_state_id")).is_empty(),
		"critical reaffirmation cancels stale recovery",
	)
	_check(bool(music.call("request_battle_state", &"high", false)), "critical recovery reschedules")
	_check(bool(music.call("commit_pending_now_for_test")), "critical recovery can be committed")
	await process_frame
	_check(music.call("current_state_id") == &"high", "critical recovery restores high state")
	_check(
		is_equal_approx(float(music.call("current_tempo_scale")), 1.0),
		"critical recovery restores authored tempo",
	)
	var before_invalid_profile := StringName(music.call("current_profile_id"))
	var before_invalid_variant := StringName(music.call("current_variant_id"))
	var before_invalid_state := StringName(music.call("current_state_id"))
	var before_invalid_cue := StringName(music.call("current_id"))
	_check(
		not bool(music.call("play_battle", &"lunaris", &"missing_variant", &"low")),
		"missing battle variant rejects",
	)
	_check(music.call("current_profile_id") == before_invalid_profile, "failed battle preserves profile")
	_check(music.call("current_variant_id") == before_invalid_variant, "failed battle preserves variant")
	_check(music.call("current_state_id") == before_invalid_state, "failed battle preserves state")
	_check(music.call("current_id") == before_invalid_cue, "failed battle preserves active cue")
	_check(bool(music.call("play_result", true)), "victory stinger starts")
	_check(music.call("current_id") == &"lunaris_result_victory", "victory cue resolves")
	var before_missing := StringName(music.call("current_id"))
	_check(not bool(music.call("play_cue", &"missing_audio")), "missing cue rejects")
	_check(music.call("current_id") == before_missing, "missing cue preserves active audio")
	music.call("set_enabled", false)
	_check(StringName(music.call("current_id")).is_empty(), "global mute stops active music")
	_check(not bool(music.call("play_staging", &"lunaris")), "global mute blocks gameplay music")
	music.call("set_enabled", true)
	music.call("stop")
	for _frame: int in range(12):
		await process_frame


func _exercise_director() -> void:
	var director: MusicDirector = MUSIC_DIRECTOR_SCRIPT.new()
	director.configure(8.0)
	director.reset(&"low", 0.0)
	var model := BattleModel.new()
	model.config = GameConfig.new()
	model.config.base_hp_start = 10
	model.base_hp = 10
	model.stage = StageDef.new()
	model.stage.wave_starts = PackedInt32Array([0, 300])
	_check(director.desired_state(model, &"orbit_early") == &"low", "empty setup stays low")
	for index: int in 4:
		var enemy := EnemyState.new()
		enemy.id = index
		model.enemies.append(enemy)
	_check(director.desired_state(model, &"orbit_early") == &"medium", "four enemies request medium")
	model.base_hp = 3
	_check(
		director.desired_state(model, &"orbit_early") == &"high",
		"exactly thirty-percent health does not enter critical state",
	)
	model.base_hp = 2
	_check(
		director.desired_state(model, &"orbit_early") == &"critical",
		"health below thirty percent requests critical state",
	)
	var critical_director: MusicDirector = MUSIC_DIRECTOR_SCRIPT.new()
	critical_director.configure(8.0)
	critical_director.reset(&"low", 0.0)
	_check(
		critical_director.update(model, &"orbit_early", 0.05).is_empty(),
		"critical health begins a short anti-flap candidate window",
	)
	_check(
		critical_director.update(model, &"orbit_early", 0.25) == &"critical",
		"critical health bypasses the routine minimum hold after stabilization",
	)
	_check(
		critical_director.desired_state(model, &"boss") == &"boss_critical",
		"low-health boss remains explicitly boss-authored while escalating",
	)
	model.base_hp = 10
	_check(director.update(model, &"orbit_early", 1.0).is_empty(), "candidate respects hold time")
	_check(director.update(model, &"orbit_early", 9.0) == &"medium", "stable pressure promotes medium")
	director.accept_state(&"medium", 9.0)
	_check(
		director.desired_state(model, &"orbit_early", true) == &"high",
		"recent leak pressure requests high",
	)
	_check(director.update(model, &"orbit_early", 10.0, true).is_empty(), "high candidate begins hysteresis")
	_check(director.update(model, &"orbit_early", 18.0, true) == &"high", "stable danger promotes high")
	director.accept_state(&"high", 18.0)
	_check(
		director.desired_state(model, &"orbit_early", false) == &"medium",
		"expired leak danger allows recovery",
	)
	_check(director.update(model, &"orbit_early", 19.0, false).is_empty(), "recovery enters hysteresis")
	_check(director.update(model, &"orbit_early", 30.0, false) == &"medium", "stable recovery de-escalates")
	_check(director.desired_state(model, &"boss") == &"boss", "boss variant remains boss-authored")


func _finish() -> void:
	if _failures.is_empty():
		print("MUSIC_REDESIGN_TEST_OK")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
