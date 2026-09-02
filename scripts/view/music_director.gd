class_name MusicDirector
extends RefCounted

## Reads battle presentation facts and requests soundtrack states. It never
## mutates BattleModel, hashes, snapshots, saves, tickets, or replay state.

const STATE_LOW := &"low"
const STATE_MEDIUM := &"medium"
const STATE_HIGH := &"high"
const STATE_CRITICAL := &"critical"
const STATE_BOSS := &"boss"
const STATE_BOSS_CRITICAL := &"boss_critical"
const CRITICAL_HEALTH_RATIO := 0.30

var _current_state: StringName = &""
var _candidate_state: StringName = &""
var _candidate_since_seconds := 0.0
var _hold_until_seconds := 0.0
var _minimum_hold_seconds := 8.0


func configure(minimum_hold_seconds: float) -> void:
	_minimum_hold_seconds = maxf(minimum_hold_seconds, 0.0)


func reset(initial_state: StringName = STATE_LOW, now_seconds: float = 0.0) -> void:
	_current_state = initial_state
	_candidate_state = initial_state
	_candidate_since_seconds = now_seconds
	_hold_until_seconds = now_seconds + _minimum_hold_seconds


func current_state() -> StringName:
	return _current_state


func update(
	model: BattleModel,
	variant_id: StringName,
	now_seconds: float,
	recent_danger: bool = false,
) -> StringName:
	if model == null:
		return &""
	var desired := desired_state(model, variant_id, recent_danger)
	if _current_state.is_empty():
		reset(desired, now_seconds)
		return desired
	if desired == _current_state:
		_candidate_state = desired
		_candidate_since_seconds = now_seconds
		return &""
	if desired != _candidate_state:
		_candidate_state = desired
		_candidate_since_seconds = now_seconds
		return &""
	var critical_escalation := (
		desired in [STATE_CRITICAL, STATE_BOSS_CRITICAL]
		and _current_state != desired
	)
	if not critical_escalation and now_seconds < _hold_until_seconds:
		return &""
	var escalating := _rank(desired) > _rank(_current_state)
	var stable_seconds := now_seconds - _candidate_since_seconds
	var required_seconds := 0.15 if critical_escalation else (0.75 if escalating else 3.0)
	if stable_seconds < required_seconds:
		return &""
	return desired


func accept_state(state_id: StringName, now_seconds: float) -> void:
	if state_id.is_empty():
		return
	_current_state = state_id
	_candidate_state = state_id
	_candidate_since_seconds = now_seconds
	_hold_until_seconds = now_seconds + _minimum_hold_seconds


func desired_state(
	model: BattleModel,
	variant_id: StringName,
	recent_danger: bool = false,
) -> StringName:
	var starting_hp := maxi(model.config.base_hp_start, 1)
	var hp_ratio := float(model.base_hp) / float(starting_hp)
	if variant_id == &"boss":
		return STATE_BOSS_CRITICAL if hp_ratio < CRITICAL_HEALTH_RATIO else STATE_BOSS
	if hp_ratio < CRITICAL_HEALTH_RATIO:
		return STATE_CRITICAL
	var alive := model.alive_enemy_count()
	var wave_index := model.stage.wave_index_at(model.tick)
	if recent_danger or hp_ratio <= 0.45 or alive >= 8:
		return STATE_HIGH
	if alive >= 4 or wave_index >= 1:
		return STATE_MEDIUM
	return STATE_LOW


func _rank(state_id: StringName) -> int:
	match state_id:
		STATE_MEDIUM:
			return 1
		STATE_HIGH, STATE_BOSS:
			return 2
		STATE_CRITICAL, STATE_BOSS_CRITICAL:
			return 3
		_:
			return 0
