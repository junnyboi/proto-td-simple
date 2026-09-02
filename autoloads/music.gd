extends Node

## Sole runtime music owner. Playback is presentation-only: it never enters the
## deterministic BattleModel, state hash, save data, ticket, or replay.

const CATALOG_PATH := "res://assets/music/catalog.tres"
const MUSIC_CATALOG_SCRIPT: GDScript = preload("res://assets/music/music_catalog.gd")
const AUDIO_CUE_SCRIPT: GDScript = preload("res://data/presentation/audio/audio_cue.gd")
const MUSIC_PROFILE_SCRIPT: GDScript = preload("res://data/presentation/audio/music_profile.gd")
const PROFILE_PATHS := {
	&"lunaris": "res://data/presentation/audio/lunaris_profile.tres",
}
const PLAYER_NAMES := [&"Player", &"TransitionPlayer"]
const BUS_NAME := &"Music"
const CRITICAL_STATES := [&"critical", &"boss_critical"]
const CRITICAL_TEMPO_SCALE := 1.08

var _catalog: Resource = null
var _players: Array[AudioStreamPlayer] = []
var _active_index := 1
var _current_id: StringName = &""
var _current_profile_id: StringName = &""
var _current_variant_id: StringName = &""
var _current_state_id: StringName = &""
var _pending_cue_id: StringName = &""
var _pending_state_id: StringName = &""
var _pending_due_msec := -1
var _pending_audio_seconds := -1.0
var _pending_previous_position := 0.0
var _pending_fade_seconds := 0.0
var _fade_tween: Tween = null
var _enabled := true
var _start_count := 0
var _stop_count := 0
var _last_transition_fade_seconds := 0.0
var _prepared_streams: Dictionary = {}


func _ready() -> void:
	reload_catalog()
	_ensure_players()
	set_process(true)


func _process(_delta: float) -> void:
	if _pending_audio_seconds < 0.0:
		return
	var player := _active_player()
	if not player.playing:
		return
	var position := player.get_playback_position()
	var advanced := position - _pending_previous_position
	if advanced < 0.0 and player.stream != null:
		advanced += player.stream.get_length()
	_pending_previous_position = position
	_pending_audio_seconds = maxf(_pending_audio_seconds - maxf(advanced, 0.0), 0.0)
	_pending_due_msec = roundi(_pending_audio_seconds * 1000.0)
	if _pending_audio_seconds > 0.01:
		return
	var cue_id := _pending_cue_id
	var state_id := _pending_state_id
	var fade_seconds := _pending_fade_seconds
	_clear_pending()
	if _transition_to(cue_id, fade_seconds, _tempo_scale_for_state(state_id)):
		_current_state_id = state_id


func reload_catalog() -> bool:
	var loaded := load(CATALOG_PATH) as Resource
	if loaded == null or loaded.get_script() != MUSIC_CATALOG_SCRIPT:
		_catalog = null
		return false
	var entries_value: Variant = loaded.get("entries")
	if not entries_value is Dictionary or entries_value.is_empty():
		_catalog = null
		return false
	_catalog = loaded
	return true


func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	if not _enabled:
		stop()


func is_enabled() -> bool:
	return _enabled


## Valid repeats are successful no-ops: no seek and no restart.
func play_cue(cue_id: StringName) -> bool:
	if not _enabled or cue_id.is_empty():
		return false
	if _current_id == cue_id and _active_player().playing:
		_clear_pending()
		return true
	if not _transition_to(cue_id, 0.0):
		return false
	_clear_pending()
	return true


func transition_to_cue(cue_id: StringName, fade_seconds: float = 0.75) -> bool:
	if not _enabled or cue_id.is_empty():
		return false
	if _current_id == cue_id and _active_player().playing:
		_clear_pending()
		return true
	if not _transition_to(cue_id, maxf(fade_seconds, 0.0)):
		return false
	_clear_pending()
	return true


func transition_to_staging(
	profile_id: StringName = &"lunaris",
	fade_seconds: float = 0.75,
) -> bool:
	var profile := _profile_for(profile_id)
	if profile == null or not transition_to_cue(profile.staging_cue_id, fade_seconds):
		return false
	_current_profile_id = profile_id
	_current_variant_id = &"staging"
	_current_state_id = &"staging"
	return true


func play_staging(profile_id: StringName = &"lunaris") -> bool:
	var profile := _profile_for(profile_id)
	if profile == null:
		return false
	if not play_cue(profile.staging_cue_id):
		return false
	_current_profile_id = profile_id
	_current_variant_id = &"staging"
	_current_state_id = &"staging"
	return true


func play_battle(
	profile_id: StringName,
	variant_id: StringName,
	state_id: StringName = &"low",
) -> bool:
	if not _enabled:
		return false
	var profile := _profile_for(profile_id)
	if profile == null:
		return false
	var cue_id := profile.cue_id_for(variant_id, state_id)
	if cue_id.is_empty():
		return false
	if not _transition_to(cue_id, 0.0):
		return false
	_clear_pending()
	_current_profile_id = profile_id
	_current_variant_id = variant_id
	_current_state_id = state_id
	return true


func request_battle_state(state_id: StringName, danger: bool = false) -> bool:
	if not _enabled or _current_profile_id.is_empty() or _current_variant_id.is_empty():
		return false
	if state_id == _current_state_id:
		if not _pending_state_id.is_empty() and _pending_state_id != state_id:
			_clear_pending()
		return true
	if state_id == _pending_state_id:
		return true
	var profile := _profile_for(_current_profile_id)
	if profile == null:
		return false
	var cue_id := profile.cue_id_for(_current_variant_id, state_id)
	var cue := _cue_for(cue_id)
	var active_cue := _cue_for(_current_id)
	if cue == null or active_cue == null:
		return false
	if (
		cue_id == _current_id
		and _active_player().playing
		and String(_current_variant_id).begins_with("act2_")
	):
		_clear_pending()
		_current_state_id = state_id
		return true
	var bar_seconds := active_cue.seconds_per_bar()
	if bar_seconds <= 0.0 or not _active_player().playing:
		if not _transition_to(
			cue_id,
			profile.danger_crossfade_seconds if danger else profile.routine_crossfade_seconds,
			_tempo_scale_for_state(state_id),
		):
			return false
		_current_state_id = state_id
		return true
	var playback_position := _active_player().get_playback_position()
	var current_bar := playback_position / bar_seconds
	var target_bar := (
		floori(current_bar) + 1
		if danger
		else (floori(current_bar / 4.0) + 1) * 4
	)
	var wait_seconds := maxf(float(target_bar) * bar_seconds - playback_position, 0.01)
	_pending_cue_id = cue_id
	_pending_state_id = state_id
	_pending_audio_seconds = wait_seconds
	_pending_previous_position = playback_position
	_pending_due_msec = roundi(wait_seconds * 1000.0)
	_pending_fade_seconds = (
		profile.danger_crossfade_seconds if danger else profile.routine_crossfade_seconds
	)
	return true


func play_result(clear: bool) -> bool:
	var profile := _profile_for(_current_profile_id if not _current_profile_id.is_empty() else &"lunaris")
	if profile == null:
		return false
	if not _transition_to(profile.victory_cue_id if clear else profile.defeat_cue_id, 0.35):
		return false
	_clear_pending()
	_current_variant_id = &"result"
	_current_state_id = &"victory" if clear else &"defeat"
	return true


func prepare_results(profile_id: StringName = &"lunaris") -> bool:
	var profile := _profile_for(profile_id)
	if profile == null:
		return false
	var prepared := true
	for cue_id: StringName in [profile.victory_cue_id, profile.defeat_cue_id]:
		var cue := _cue_for(cue_id)
		if cue == null or not cue.is_valid():
			prepared = false
			continue
		var stream := load(cue.stream_path) as AudioStream
		if stream == null:
			prepared = false
			continue
		_prepared_streams[cue.stream_path] = stream
	return prepared


func stop() -> bool:
	_clear_pending()
	if _current_id.is_empty() and not _any_player_active():
		return false
	if _fade_tween != null and is_instance_valid(_fade_tween):
		_fade_tween.kill()
	_fade_tween = null
	for player: AudioStreamPlayer in _ensure_players():
		player.stop()
		player.stream = null
		player.pitch_scale = 1.0
		player.volume_db = 0.0
	_current_id = &""
	_current_profile_id = &""
	_current_variant_id = &""
	_current_state_id = &""
	_stop_count += 1
	return true


func current_id() -> StringName:
	return _current_id


func current_profile_id() -> StringName:
	return _current_profile_id


func current_variant_id() -> StringName:
	return _current_variant_id


func current_state_id() -> StringName:
	return _current_state_id


func pending_state_id() -> StringName:
	return _pending_state_id


func pending_due_msec() -> int:
	return _pending_due_msec


func minimum_state_hold_seconds(profile_id: StringName) -> float:
	var profile := _profile_for(profile_id)
	return profile.minimum_state_hold_seconds if profile != null else 0.0


func commit_pending_now_for_test() -> bool:
	if _pending_audio_seconds < 0.0:
		return false
	_pending_audio_seconds = 0.0
	_pending_due_msec = 0
	_process(0.0)
	return true


func start_count() -> int:
	return _start_count


func stop_count() -> int:
	return _stop_count


func player_count() -> int:
	return _ensure_players().size()


func current_stream_path() -> String:
	var player := _active_player()
	return player.stream.resource_path if player.stream != null else ""


func current_tempo_scale() -> float:
	return _active_player().pitch_scale


func last_transition_fade_seconds() -> float:
	return _last_transition_fade_seconds


func _transition_to(
	cue_id: StringName,
	fade_seconds: float,
	tempo_scale: float = 1.0,
) -> bool:
	fade_seconds *= float(TweakControls.value(
		&"audio.transition_duration_multiplier", 1.0,
	))
	var cue := _cue_for(cue_id)
	if cue == null or not cue.is_valid():
		return false
	var stream := _prepared_streams.get(cue.stream_path) as AudioStream
	if stream == null:
		stream = load(cue.stream_path) as AudioStream
	if stream == null:
		return false
	stream.set("loop", cue.loop)
	var players := _ensure_players()
	var old_index := _active_index
	var new_index := 1 - _active_index
	var old_player := players[old_index]
	var new_player := players[new_index]
	if _fade_tween != null and is_instance_valid(_fade_tween):
		_fade_tween.kill()
	_fade_tween = null
	new_player.stop()
	new_player.stream = stream
	new_player.pitch_scale = maxf(
		tempo_scale * float(TweakControls.value(&"audio.music_pitch_multiplier", 1.0)),
		0.01,
	)
	new_player.volume_db = cue.volume_db if fade_seconds <= 0.0 else -60.0
	new_player.play()
	_active_index = new_index
	_current_id = cue_id
	_last_transition_fade_seconds = maxf(fade_seconds, 0.0)
	_start_count += 1
	if not old_player.playing or fade_seconds <= 0.0:
		new_player.volume_db = cue.volume_db
		old_player.stop()
		old_player.stream = null
		old_player.pitch_scale = 1.0
		old_player.volume_db = 0.0
		return true
	_fade_tween = create_tween().set_parallel(true)
	_fade_tween.tween_property(new_player, "volume_db", cue.volume_db, fade_seconds)
	_fade_tween.tween_property(old_player, "volume_db", -60.0, fade_seconds)
	_fade_tween.chain().tween_callback(_finish_crossfade.bind(old_index))
	return true


func _finish_crossfade(old_index: int) -> void:
	var players := _ensure_players()
	if old_index >= 0 and old_index < players.size() and old_index != _active_index:
		players[old_index].stop()
		players[old_index].stream = null
		players[old_index].pitch_scale = 1.0
		players[old_index].volume_db = 0.0
	_fade_tween = null


func _cue_for(cue_id: StringName) -> AudioCue:
	if cue_id.is_empty():
		return null
	if _catalog == null and not reload_catalog():
		return null
	var entries_value: Variant = _catalog.get("entries")
	if not entries_value is Dictionary:
		return null
	var entries: Dictionary = entries_value
	var value: Variant = entries.get(cue_id)
	if value is Resource and (value as Resource).get_script() == AUDIO_CUE_SCRIPT:
		return value as AudioCue
	if value is Dictionary:
		var legacy_entry: Dictionary = value
		var stream_path := String(legacy_entry.get("path", ""))
		if stream_path.is_empty():
			return null
		var cue := AUDIO_CUE_SCRIPT.new() as AudioCue
		cue.id = cue_id
		cue.stream_path = stream_path
		cue.loop = bool(legacy_entry.get("loop", true))
		return cue
	return null


func _profile_for(profile_id: StringName) -> MusicProfile:
	var path := String(PROFILE_PATHS.get(profile_id, ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var profile := load(path) as Resource
	if profile == null or profile.get_script() != MUSIC_PROFILE_SCRIPT:
		return null
	return profile as MusicProfile


func _ensure_players() -> Array[AudioStreamPlayer]:
	_ensure_bus()
	if _players.size() == PLAYER_NAMES.size():
		var all_valid := true
		for player: AudioStreamPlayer in _players:
			if not is_instance_valid(player):
				all_valid = false
				break
		if all_valid:
			for player: AudioStreamPlayer in _players:
				player.bus = BUS_NAME
				player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
			return _players
	_players.clear()
	for player_name: StringName in PLAYER_NAMES:
		var player := get_node_or_null(NodePath(String(player_name))) as AudioStreamPlayer
		if player == null:
			player = AudioStreamPlayer.new()
			player.name = player_name
			add_child(player)
		player.bus = BUS_NAME
		player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
		_players.append(player)
	return _players


func _ensure_bus() -> void:
	var index := AudioServer.get_bus_index(BUS_NAME)
	if index < 0:
		AudioServer.add_bus()
		index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, BUS_NAME)
	if AudioServer.get_bus_send(index) != &"Master":
		AudioServer.set_bus_send(index, &"Master")


func _active_player() -> AudioStreamPlayer:
	return _ensure_players()[_active_index]


func _any_player_active() -> bool:
	for player: AudioStreamPlayer in _ensure_players():
		if player.playing or player.stream != null:
			return true
	return false


func _tempo_scale_for_state(state_id: StringName) -> float:
	return CRITICAL_TEMPO_SCALE if state_id in CRITICAL_STATES else 1.0


func _clear_pending() -> void:
	_pending_cue_id = &""
	_pending_state_id = &""
	_pending_due_msec = -1
	_pending_audio_seconds = -1.0
	_pending_previous_position = 0.0
	_pending_fade_seconds = 0.0
