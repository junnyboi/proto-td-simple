class_name MissionLeaderboardService
extends Node

## Offline-first mission leaderboard. Authoritative mission completion records
## locally before this service attempts any network work.

signal state_changed

const SCHEMA_VERSION := 1
const SCORE_VERSION := 1
const DISPLAY_LIMIT := 10
const LOCAL_LIMIT := 50
const PENDING_LIMIT := 100
const API_PATH := "/api/leaderboard"
const DEFAULT_SAVE_PATH := "user://leaderboard.json"
const DEFAULT_PLAYER_NAME := "COMMANDER"
const MAX_PLAYER_NAME_LENGTH := 16
const MAX_KILLS := 500
const MAX_LEAKS := 100
const MAX_SCORE := 4_000_000

var save_path := DEFAULT_SAVE_PATH
var entries: Array[Dictionary] = []
var status: StringName = &"idle"
var last_operation: StringName = &""
var submitted_entry: Dictionary = {}

var _data: Dictionary = {}
var _http: HTTPRequest = null
var _base_url := ""
var _allow_headless_requests := false
var _active_submission_id := ""
var _latest_submission_id := ""
var _clearing_player_data := false


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.name = "LeaderboardRequest"
	_http.timeout = 8.0
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)
	_data = _load_data()
	_base_url = _resolve_base_url()
	_allow_headless_requests = bool(ProjectSettings.get_setting(
		"leaderboard/enable_in_headless", false,
	))
	status = &"idle" if _can_request() else &"offline"
	if pending_count() > 0:
		call_deferred("sync")


func player_name() -> String:
	return String(_data.get("player_name", DEFAULT_PLAYER_NAME))


func set_player_name(candidate: String) -> String:
	var normalized := normalize_player_name(candidate)
	if normalized == player_name():
		return normalized
	_data["player_name"] = normalized
	_save_data()
	state_changed.emit()
	return normalized


func local_entries(limit: int = DISPLAY_LIMIT) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	var stored: Array = _data.get("local_scores", [])
	for index: int in range(mini(clampi(limit, 0, LOCAL_LIMIT), stored.size())):
		var record := (stored[index] as Dictionary).duplicate(true)
		record["rank"] = index + 1
		records.append(record)
	return records


func pending_count() -> int:
	return (_data.get("pending_submissions", []) as Array).size()


func latest_submission_id() -> String:
	return _latest_submission_id


## Records a completed mission immediately and returns the local public record.
## Network synchronization is deliberately deferred and cannot affect the result.
func record_mission(result: Dictionary) -> Dictionary:
	if _clearing_player_data:
		return {}
	var submission := _submission_from_result(result)
	if submission.is_empty():
		return {}
	var record := submission.duplicate(true)
	record["score"] = calculate_score(submission)
	record["created_at"] = Time.get_datetime_string_from_system(true)
	var local_scores: Array = _data.get("local_scores", [])
	local_scores.append(record)
	sort_entries(local_scores)
	if local_scores.size() > LOCAL_LIMIT:
		local_scores.resize(LOCAL_LIMIT)
	_data["local_scores"] = local_scores
	var pending: Array = _data.get("pending_submissions", [])
	pending.append(submission)
	if pending.size() > PENDING_LIMIT:
		pending.pop_front()
	_data["pending_submissions"] = pending
	_latest_submission_id = String(submission["submission_id"])
	_save_data()
	state_changed.emit()
	call_deferred("sync")
	return record.duplicate(true)


func sync() -> void:
	if _clearing_player_data:
		return
	if not _can_request():
		_set_state(&"offline", &"submit" if pending_count() > 0 else &"fetch")
		return
	if pending_count() > 0:
		_submit_next()
	else:
		_fetch_scores()


func prepare_for_player_data_clear() -> void:
	_clearing_player_data = true
	_cancel_active_request()


func finish_player_data_clear(succeeded: bool) -> void:
	_clearing_player_data = false
	_active_submission_id = ""
	_latest_submission_id = ""
	entries.clear()
	submitted_entry.clear()
	_data = _default_data() if succeeded else _load_data()
	status = &"idle" if _can_request() else &"offline"
	last_operation = &""
	state_changed.emit()


## Test seam used only from repository tests, which already run in disposable
## user:// directories through tools/run_godot_test.sh.
func configure_for_testing(test_save_path: String, test_base_url: String) -> void:
	_cancel_active_request()
	save_path = test_save_path
	_data = _load_data()
	entries.clear()
	submitted_entry.clear()
	_active_submission_id = ""
	_latest_submission_id = ""
	_base_url = test_base_url.strip_edges().trim_suffix("/")
	_allow_headless_requests = true
	status = &"idle" if _can_request() else &"offline"
	last_operation = &""
	state_changed.emit()


func clear_for_testing() -> void:
	_cancel_active_request()
	for suffix: String in ["", ".tmp", ".bak"]:
		var path := save_path + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_data = _default_data()
	entries.clear()
	submitted_entry.clear()
	_active_submission_id = ""
	_latest_submission_id = ""
	status = &"idle" if _can_request() else &"offline"
	last_operation = &""
	state_changed.emit()


func _submission_from_result(result: Dictionary) -> Dictionary:
	var stage_id := String(result.get("stage_id", ""))
	if mission_number(stage_id) == 0:
		return {}
	var outcome := int(result.get("result", -1))
	if outcome not in [BattleModel.Result.CLEAR, BattleModel.Result.DEFEAT]:
		return {}
	return {
		"submission_id": _new_submission_id(),
		"name": player_name(),
		"stage_id": stage_id,
		"victory": outcome == BattleModel.Result.CLEAR,
		"stars": clampi(int(result.get("stars", 0)), 0, 3),
		"kills": clampi(int(result.get("kills", 0)), 0, MAX_KILLS),
		"leaks": clampi(int(result.get("leaks", 0)), 0, MAX_LEAKS),
		"score_version": SCORE_VERSION,
	}


func _new_submission_id() -> String:
	var random_bytes := Crypto.new().generate_random_bytes(16)
	return "%d-%s" % [int(Time.get_unix_time_from_system()), random_bytes.hex_encode()]


func _fetch_scores() -> void:
	_cancel_active_request()
	_active_submission_id = ""
	_set_state(&"loading", &"fetch")
	var error := _http.request(
		_base_url + API_PATH + "?limit=%d" % DISPLAY_LIMIT,
		PackedStringArray(["Accept: application/json"]),
		HTTPClient.METHOD_GET,
	)
	if error != OK:
		_set_state(&"error", &"fetch")


func _submit_next() -> void:
	var pending: Array = _data.get("pending_submissions", [])
	if pending.is_empty():
		_fetch_scores()
		return
	_cancel_active_request()
	var submission := pending.front() as Dictionary
	_active_submission_id = String(submission.get("submission_id", ""))
	_set_state(&"loading", &"submit")
	var error := _http.request(
		_base_url + API_PATH,
		PackedStringArray(["Accept: application/json", "Content-Type: application/json"]),
		HTTPClient.METHOD_POST,
		JSON.stringify(submission),
	)
	if error != OK:
		_set_state(&"error", &"submit")


func _on_request_completed(
		result: int,
		response_code: int,
		_headers: PackedStringArray,
		body: PackedByteArray,
	) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		_set_state(&"error", last_operation)
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not parsed is Dictionary or not (parsed as Dictionary).get("entries", []) is Array:
		_set_state(&"error", last_operation)
		return
	var response := parsed as Dictionary
	entries = _sanitize_public_entries(response.get("entries", []))
	var raw_submitted: Variant = response.get("entry", {})
	if raw_submitted is Dictionary:
		submitted_entry = (raw_submitted as Dictionary).duplicate(true)
	if last_operation == &"submit":
		var pending: Array = _data.get("pending_submissions", [])
		if (
			not pending.is_empty()
			and String((pending.front() as Dictionary).get("submission_id", ""))
			== _active_submission_id
		):
			pending.pop_front()
			_data["pending_submissions"] = pending
			_save_data()
		_active_submission_id = ""
		_set_state(&"ready", &"submit")
		if pending_count() > 0:
			call_deferred("_submit_next")
		return
	_set_state(&"ready", &"fetch")


func _sanitize_public_entries(raw_entries: Array) -> Array[Dictionary]:
	var sanitized: Array[Dictionary] = []
	for raw: Variant in raw_entries:
		if not raw is Dictionary or sanitized.size() >= DISPLAY_LIMIT:
			continue
		var row := raw as Dictionary
		var stage_id := String(row.get("stage_id", ""))
		if mission_number(stage_id) == 0:
			continue
		sanitized.append({
			"rank": clampi(int(row.get("rank", sanitized.size() + 1)), 1, 1000),
			"name": normalize_player_name(String(row.get("name", DEFAULT_PLAYER_NAME))),
			"score": clampi(int(row.get("score", 0)), 0, MAX_SCORE),
			"stage_id": stage_id,
			"victory": bool(row.get("victory", false)),
			"stars": clampi(int(row.get("stars", 0)), 0, 3),
			"created_at": String(row.get("created_at", "")),
		})
	return sanitized


func _resolve_base_url() -> String:
	if OS.has_feature("web"):
		var origin: Variant = JavaScriptBridge.eval("window.location.origin", true)
		if origin is String and (
			String(origin).begins_with("https://")
			or String(origin).begins_with("http://")
		):
			return String(origin).trim_suffix("/")
	return String(ProjectSettings.get_setting(
		"leaderboard/api_base_url", "",
	)).strip_edges().trim_suffix("/")


func _can_request() -> bool:
	return (
		_http != null
		and not _base_url.is_empty()
		and (DisplayServer.get_name() != "headless" or _allow_headless_requests)
	)


func _cancel_active_request() -> void:
	if _http != null and _http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_http.cancel_request()


func _set_state(next_status: StringName, operation: StringName) -> void:
	status = next_status
	last_operation = operation
	state_changed.emit()


func _load_data() -> Dictionary:
	for candidate: String in [save_path, save_path + ".bak"]:
		if not FileAccess.file_exists(candidate):
			continue
		var file := FileAccess.open(candidate, FileAccess.READ)
		if file == null:
			continue
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		if parsed is Dictionary:
			var sanitized := _sanitize_data(parsed as Dictionary)
			if not sanitized.is_empty():
				return sanitized
	return _default_data()


func _sanitize_data(raw: Dictionary) -> Dictionary:
	if int(raw.get("schema_version", 0)) != SCHEMA_VERSION:
		return {}
	var sanitized := _default_data()
	sanitized["player_name"] = normalize_player_name(String(raw.get(
		"player_name", DEFAULT_PLAYER_NAME,
	)))
	var local_scores: Array = []
	var raw_local: Variant = raw.get("local_scores", [])
	if raw_local is Array:
		for value: Variant in raw_local:
			var record := _sanitize_saved_record(value)
			if not record.is_empty():
				local_scores.append(record)
	sort_entries(local_scores)
	if local_scores.size() > LOCAL_LIMIT:
		local_scores.resize(LOCAL_LIMIT)
	sanitized["local_scores"] = local_scores
	var pending: Array = []
	var raw_pending: Variant = raw.get("pending_submissions", [])
	if raw_pending is Array:
		for value: Variant in raw_pending:
			var submission := _sanitize_submission(value)
			if not submission.is_empty():
				pending.append(submission)
	if pending.size() > PENDING_LIMIT:
		pending = pending.slice(pending.size() - PENDING_LIMIT)
	sanitized["pending_submissions"] = pending
	return sanitized


func _sanitize_saved_record(value: Variant) -> Dictionary:
	var submission := _sanitize_submission(value)
	if submission.is_empty():
		return {}
	var raw := value as Dictionary
	var record := submission.duplicate(true)
	record["score"] = calculate_score(submission)
	record["created_at"] = String(raw.get("created_at", ""))
	return record


func _sanitize_submission(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var raw := value as Dictionary
	var submission_id := String(raw.get("submission_id", ""))
	var stage_id := String(raw.get("stage_id", ""))
	if (
		int(raw.get("score_version", 0)) != SCORE_VERSION
		or not _valid_submission_id(submission_id)
		or mission_number(stage_id) == 0
	):
		return {}
	return {
		"submission_id": submission_id,
		"name": normalize_player_name(String(raw.get("name", DEFAULT_PLAYER_NAME))),
		"stage_id": stage_id,
		"victory": bool(raw.get("victory", false)),
		"stars": clampi(int(raw.get("stars", 0)), 0, 3),
		"kills": clampi(int(raw.get("kills", 0)), 0, MAX_KILLS),
		"leaks": clampi(int(raw.get("leaks", 0)), 0, MAX_LEAKS),
		"score_version": SCORE_VERSION,
	}


func _save_data() -> bool:
	if _clearing_player_data:
		return false
	var directory := ProjectSettings.globalize_path(save_path.get_base_dir())
	if (
		not DirAccess.dir_exists_absolute(directory)
		and DirAccess.make_dir_recursive_absolute(directory) != OK
	):
		return false
	var temporary_path := save_path + ".tmp"
	var backup_path := save_path + ".bak"
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(_data, "", true, true) + "\n")
	file.close()
	var save_absolute := ProjectSettings.globalize_path(save_path)
	var temporary_absolute := ProjectSettings.globalize_path(temporary_path)
	var backup_absolute := ProjectSettings.globalize_path(backup_path)
	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(backup_absolute)
	if FileAccess.file_exists(save_path):
		if DirAccess.rename_absolute(save_absolute, backup_absolute) != OK:
			DirAccess.remove_absolute(temporary_absolute)
			return false
	if DirAccess.rename_absolute(temporary_absolute, save_absolute) != OK:
		if FileAccess.file_exists(backup_path):
			DirAccess.rename_absolute(backup_absolute, save_absolute)
		return false
	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(backup_absolute)
	return true


func _default_data() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"player_name": DEFAULT_PLAYER_NAME,
		"local_scores": [],
		"pending_submissions": [],
	}


static func calculate_score(mission: Dictionary) -> int:
	return clampi(
		(2_000_000 if bool(mission.get("victory", false)) else 0)
		+ mission_number(String(mission.get("stage_id", ""))) * 100_000
		+ clampi(int(mission.get("stars", 0)), 0, 3) * 20_000
		+ clampi(int(mission.get("kills", 0)), 0, MAX_KILLS) * 50
		- clampi(int(mission.get("leaks", 0)), 0, MAX_LEAKS) * 500,
		0,
		MAX_SCORE,
	)


static func mission_number(stage_id: String) -> int:
	if not stage_id.begins_with("s") or stage_id.length() < 2:
		return 0
	var suffix := stage_id.substr(1)
	if not suffix.is_valid_int():
		return 0
	var value := int(suffix)
	return value if value >= 1 and value <= 10 and stage_id == "s%d" % value else 0


static func normalize_player_name(value: String) -> String:
	var normalized := ""
	var previous_space := false
	var previous_hyphen := false
	for index: int in value.length():
		var character := value.substr(index, 1).to_upper()
		if character == " ":
			if not normalized.is_empty() and not previous_space:
				normalized += character
			previous_space = true
			previous_hyphen = false
		elif character == "-":
			if not normalized.is_empty() and not previous_hyphen:
				normalized += character
			previous_space = false
			previous_hyphen = true
		elif character == "_" or "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".contains(character):
			normalized += character
			previous_space = false
			previous_hyphen = false
		if normalized.length() >= MAX_PLAYER_NAME_LENGTH:
			break
	normalized = normalized.strip_edges().trim_suffix("-")
	return DEFAULT_PLAYER_NAME if normalized.is_empty() else normalized


static func sort_entries(records: Array) -> void:
	records.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_score := int(left.get("score", 0))
		var right_score := int(right.get("score", 0))
		if left_score != right_score:
			return left_score > right_score
		var left_time := String(left.get("created_at", ""))
		var right_time := String(right.get("created_at", ""))
		if left_time != right_time:
			return left_time < right_time
		return String(left.get("submission_id", "")) < String(right.get("submission_id", ""))
	)


static func _valid_submission_id(value: String) -> bool:
	if value.length() < 8 or value.length() > 96:
		return false
	for character: String in value:
		if character not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-":
			return false
	return true
