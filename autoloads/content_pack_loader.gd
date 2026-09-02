extends Node

## Downloads presentation-only atlas packs after the cold-start core is playable.
## Packs may add absent resources but never replace core files. Missing content
## always falls back to incumbent art while a verified pack is in flight.

signal pack_state_changed(pack_id: StringName, state: StringName, current: int, total: int)
signal pack_ready(pack_id: StringName)
signal pack_failed(pack_id: StringName, reason: String)
signal background_policy_changed(enabled: bool, network_profile: StringName, class_limit: int)

const BackgroundDownloadStatusType := preload("res://scripts/view/background_download_status.gd")
const ARG_PREFIX := "--content-pack="
const NETWORK_PROFILE_ARG_PREFIX := "--network-profile="
const CACHE_DIR := "user://content-packs"
const COPY_CHUNK_BYTES := 256 * 1024
const DOWNLOAD_TIMEOUT_SECONDS := 180.0
const MAX_PACK_BYTES := 64 * 1024 * 1024
const MAX_PREDICTIVE_CLASSES := 3
const NETWORK_REFRESH_SECONDS := 5.0
const ADVANCED_CLASSES := [
	"gunner",
	"mage_apprentice",
	"swordmaster",
]

var _specs: Dictionary = {}
var _queue: Array[String] = []
var _queued: Dictionary = {}
var _background_requests: Dictionary = {}
var _loaded: Dictionary = {}
var _failed: Dictionary = {}
var _request: HTTPRequest = null
var _active_id := ""
var _active_total := 0
var _last_progress := 0
var _active_background := false
var _background_downloads_enabled := true
var _network_profile: StringName = &"standard"
var _background_class_limit := 2


func _ready() -> void:
	set_process(false)
	if OS.has_feature("web"):
		var network_timer := Timer.new()
		network_timer.name = "NetworkProfileRefresh"
		network_timer.wait_time = NETWORK_REFRESH_SECONDS
		network_timer.autostart = true
		network_timer.timeout.connect(_refresh_web_network_profile)
		add_child(network_timer)


func configure(arguments: PackedStringArray = OS.get_cmdline_user_args()) -> void:
	_apply_network_profile(network_profile_from_arguments(arguments))
	for argument: String in arguments:
		if not argument.begins_with(ARG_PREFIX):
			continue
		var spec := parse_argument(argument)
		if spec.is_empty():
			continue
		_specs[String(spec[&"id"])] = spec
	background_policy_changed.emit(
		_background_downloads_enabled, _network_profile, _background_class_limit,
	)


func prefetch_from_title(arguments: PackedStringArray = OS.get_cmdline_user_args()) -> void:
	configure(arguments)


func request_resource(path: String) -> bool:
	if path.is_empty() or FileAccess.file_exists(path):
		return true
	var pack_id := pack_id_for_resource(path)
	if pack_id.is_empty():
		return false
	request_pack(pack_id, true)
	return FileAccess.file_exists(path)


func request_pack(pack_id: String, prioritize := true, background := false) -> bool:
	if _loaded.has(pack_id):
		return true
	if not _specs.has(pack_id):
		return false
	if _mount_cached(pack_id):
		return true
	if _failed.has(pack_id):
		return false
	if _active_id == pack_id:
		if not background:
			_active_background = false
			BackgroundDownloadStatusType.publish(&"operator", StringName(pack_id), &"foreground")
		return false
	if _queued.has(pack_id):
		if not background:
			_background_requests[pack_id] = false
			BackgroundDownloadStatusType.publish(&"operator", StringName(pack_id), &"foreground")
		if prioritize:
			_queue.erase(pack_id)
			_queue.push_front(pack_id)
		return false
	if prioritize:
		_queue.push_front(pack_id)
	else:
		_queue.append(pack_id)
	_queued[pack_id] = true
	_background_requests[pack_id] = background
	var spec: Dictionary = _specs[pack_id]
	pack_state_changed.emit(StringName(pack_id), &"queued", 0, int(spec[&"bytes"]))
	if background:
		BackgroundDownloadStatusType.publish(
			&"operator", StringName(pack_id), &"queued", 0, int(spec[&"bytes"]),
		)
	_pump_queue.call_deferred()
	return false


func request_class(class_id: String, prioritize := true, background := true) -> bool:
	var pack_id := pack_id_for_class(class_id)
	if pack_id.is_empty():
		return false
	if background:
		return _request_background_pack(pack_id, prioritize)
	return request_pack(pack_id, prioritize, false)


func prefetch_class_ids(
		class_ids: Array,
		prioritize := false,
		limit := 0,
	) -> Array[String]:
	var requested: Array[String] = []
	if not _background_downloads_enabled or _background_class_limit <= 0:
		return requested
	var effective_limit := _background_class_limit
	if limit > 0:
		effective_limit = mini(effective_limit, limit)
	for value: Variant in class_ids:
		var class_id := String(value)
		var pack_id := pack_id_for_class(class_id)
		if pack_id.is_empty() or requested.has(pack_id):
			continue
		requested.append(pack_id)
		if requested.size() >= effective_limit:
			break
	if prioritize:
		for index: int in range(requested.size() - 1, -1, -1):
			_request_background_pack(requested[index], true)
	else:
		for pack_id: String in requested:
			_request_background_pack(pack_id, false)
	return requested


func prefetch_roster(
		roster_rows: Array,
		selected_hero_ids: Array = [],
	) -> Array[String]:
	return prefetch_class_ids(
		predictive_class_order(roster_rows, selected_hero_ids), false,
	)


func configured_pack_count() -> int:
	return _specs.size()


func set_background_downloads_enabled(enabled: bool) -> void:
	if _background_downloads_enabled == enabled:
		return
	_background_downloads_enabled = enabled
	if not enabled:
		_enforce_background_limit(0)
		BackgroundDownloadStatusType.publish(&"operator", &"", &"disabled")
	background_policy_changed.emit(enabled, _network_profile, _background_class_limit)


func background_downloads_enabled() -> bool:
	return _background_downloads_enabled


func network_profile() -> StringName:
	return _network_profile


func background_class_limit() -> int:
	return _background_class_limit


func adaptive_prefetch_limits() -> Dictionary:
	return prefetch_limits_for_profile(_network_profile)


func is_pack_ready(pack_id: String) -> bool:
	return _loaded.has(pack_id)


func active_pack_id() -> String:
	return _active_id


func queued_pack_ids() -> Array[String]:
	return _queue.duplicate()


func reset_for_tests() -> void:
	prepare_for_player_data_clear()
	_specs.clear()
	_loaded.clear()
	_background_downloads_enabled = true
	_network_profile = &"standard"
	_background_class_limit = 2


func prepare_for_player_data_clear() -> void:
	_cancel_active()
	_queue.clear()
	_queued.clear()
	_background_requests.clear()
	_failed.clear()


func _process(_delta: float) -> void:
	if _request == null or _active_id.is_empty():
		return
	var downloaded := _request.get_downloaded_bytes()
	var total := _request.get_body_size()
	if total <= 0:
		total = _active_total
	if downloaded == _last_progress:
		return
	_last_progress = downloaded
	pack_state_changed.emit(StringName(_active_id), &"downloading", downloaded, total)
	if _active_background:
		BackgroundDownloadStatusType.publish(
			&"operator", StringName(_active_id), &"downloading", downloaded, total,
		)


func _pump_queue() -> void:
	if _request != null or not _active_id.is_empty():
		return
	while not _queue.is_empty():
		var pack_id: String = _queue.pop_front()
		_queued.erase(pack_id)
		_active_background = bool(_background_requests.get(pack_id, false))
		_background_requests.erase(pack_id)
		if _loaded.has(pack_id):
			continue
		if _mount_cached(pack_id):
			if _active_background:
				var bytes := int((_specs.get(pack_id, {}) as Dictionary).get(&"bytes", 0))
				BackgroundDownloadStatusType.publish(
					&"operator", StringName(pack_id), &"ready", bytes, bytes,
				)
			_active_background = false
			continue
		_start_download(pack_id)
		return


func _start_download(pack_id: String) -> void:
	var spec: Dictionary = _specs.get(pack_id, {})
	if spec.is_empty():
		_finish_failed(pack_id, "Content pack is not configured.")
		return
	_active_id = pack_id
	_active_total = int(spec[&"bytes"])
	_last_progress = 0
	_request = HTTPRequest.new()
	_request.name = "ContentPackDownload"
	_request.accept_gzip = false
	_request.body_size_limit = _active_total + COPY_CHUNK_BYTES
	_request.download_chunk_size = COPY_CHUNK_BYTES
	_request.timeout = DOWNLOAD_TIMEOUT_SECONDS
	_request.request_completed.connect(_on_request_completed)
	add_child(_request)
	set_process(true)
	pack_state_changed.emit(StringName(pack_id), &"downloading", 0, _active_total)
	if _active_background:
		BackgroundDownloadStatusType.publish(
			&"operator", StringName(pack_id), &"downloading", 0, _active_total,
		)
	var error := _request.request(String(spec[&"url"]))
	if error != OK:
		_finish_failed(pack_id, "Request could not start (%s)." % error_string(error))


func _on_request_completed(
		result: int,
		response_code: int,
		_headers: PackedStringArray,
		body: PackedByteArray,
) -> void:
	var pack_id := _active_id
	var completed_background := _active_background
	var spec: Dictionary = _specs.get(pack_id, {})
	_dispose_request()
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		_finish_failed(pack_id, "Download failed (result %d, HTTP %d)." % [result, response_code])
		return
	if body.size() != int(spec.get(&"bytes", 0)):
		_finish_failed(pack_id, "Downloaded content pack failed its byte-length check.")
		return
	_ensure_cache_dir()
	var path := _cache_path(pack_id)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_finish_failed(pack_id, "Downloaded content pack could not be cached.")
		return
	file.store_buffer(body)
	file.close()
	if not _verify_file(path, spec):
		_cleanup_file(path)
		_finish_failed(pack_id, "Downloaded content pack failed SHA-256 verification.")
		return
	_clear_active()
	if not _mount_pack(pack_id, path):
		_cleanup_file(path)
		_finish_failed(pack_id, "Verified content pack could not be mounted.")
		return
	if completed_background:
		BackgroundDownloadStatusType.publish(
			&"operator", StringName(pack_id), &"ready",
			int(spec.get(&"bytes", 0)), int(spec.get(&"bytes", 0)),
		)
	_pump_queue.call_deferred()


func _mount_cached(pack_id: String) -> bool:
	var spec: Dictionary = _specs.get(pack_id, {})
	if spec.is_empty():
		return false
	var path := _cache_path(pack_id)
	if not _verify_file(path, spec):
		_cleanup_file(path)
		return false
	return _mount_pack(pack_id, path)


func _mount_pack(pack_id: String, path: String) -> bool:
	# `replace_files = false` is the security boundary: downloaded packs may only
	# provide resources intentionally omitted from the signed core export.
	if not ProjectSettings.load_resource_pack(path, false):
		return false
	_loaded[pack_id] = true
	_failed.erase(pack_id)
	pack_state_changed.emit(StringName(pack_id), &"ready", int(_specs[pack_id][&"bytes"]), int(_specs[pack_id][&"bytes"]))
	pack_ready.emit(StringName(pack_id))
	return true


func _finish_failed(pack_id: String, reason: String) -> void:
	var failed_background := _active_background
	_dispose_request()
	_clear_active()
	_failed[pack_id] = reason
	push_warning("Content pack '%s' failed: %s" % [pack_id, reason])
	pack_state_changed.emit(StringName(pack_id), &"failed", 0, 0)
	if failed_background:
		BackgroundDownloadStatusType.publish(&"operator", StringName(pack_id), &"failed")
	pack_failed.emit(StringName(pack_id), reason)
	_pump_queue.call_deferred()


func _dispose_request() -> void:
	if _request == null:
		return
	if _request.request_completed.is_connected(_on_request_completed):
		_request.request_completed.disconnect(_on_request_completed)
	_request.queue_free()
	_request = null


func _cancel_active() -> void:
	if _request != null:
		_request.cancel_request()
	_dispose_request()
	_clear_active()


func _clear_active() -> void:
	_active_id = ""
	_active_total = 0
	_last_progress = 0
	_active_background = false
	set_process(false)


func _cache_path(pack_id: String) -> String:
	var digest := String((_specs.get(pack_id, {}) as Dictionary).get(&"sha256", ""))
	return "%s/%s-%s.pck" % [CACHE_DIR, pack_id, digest.left(16)]


func _verify_file(path: String, spec: Dictionary) -> bool:
	if path.is_empty() or not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var actual_bytes := file.get_length()
	file.close()
	if actual_bytes != int(spec.get(&"bytes", 0)):
		return false
	return FileAccess.get_sha256(path).to_lower() == String(spec.get(&"sha256", "")).to_lower()


func _ensure_cache_dir() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE_DIR))


func _cleanup_file(path: String) -> void:
	if not path.is_empty() and FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


static func parse_argument(argument: String) -> Dictionary:
	if not argument.begins_with(ARG_PREFIX):
		return {}
	var fields := argument.substr(ARG_PREFIX.length()).split("|", false)
	if fields.size() != 4:
		return {}
	var pack_id := String(fields[0])
	var url := String(fields[1])
	var byte_text := String(fields[2])
	var digest := String(fields[3]).to_lower()
	if not valid_pack_ids().has(pack_id):
		return {}
	if not (url.begins_with("https://") or url.begins_with("http://")):
		return {}
	if not byte_text.is_valid_int():
		return {}
	var bytes := byte_text.to_int()
	if bytes <= 0 or bytes > MAX_PACK_BYTES:
		return {}
	if digest.length() != 64 or not digest.is_valid_hex_number(false):
		return {}
	return {&"id": pack_id, &"url": url, &"bytes": bytes, &"sha256": digest}


static func pack_id_for_resource(path: String) -> String:
	const prefix := "res://assets/sprites/operators/animated/"
	if not path.begins_with(prefix):
		return ""
	var relative := path.substr(prefix.length())
	var class_id := relative.get_slice("/", 0)
	return pack_id_for_class(class_id)


static func pack_id_for_class(class_id: String) -> String:
	if not ADVANCED_CLASSES.has(class_id):
		return ""
	return "operator-%s" % class_id.replace("_", "-")


func _request_background_pack(pack_id: String, prioritize: bool) -> bool:
	if not _background_downloads_enabled or _background_class_limit <= 0:
		return false
	if _loaded.has(pack_id) or _active_id == pack_id or _queued.has(pack_id):
		return request_pack(pack_id, prioritize, true)
	var pending := _background_pending_count()
	if pending >= _background_class_limit:
		if not prioritize:
			return false
		var displaced := _last_queued_background_pack()
		if displaced.is_empty():
			return false
		_queue.erase(displaced)
		_queued.erase(displaced)
		_background_requests.erase(displaced)
	return request_pack(pack_id, prioritize, true)


func _background_pending_count() -> int:
	var count := 1 if _active_background else 0
	for pack_id: String in _queue:
		if bool(_background_requests.get(pack_id, false)):
			count += 1
	return count


func _last_queued_background_pack() -> String:
	for index: int in range(_queue.size() - 1, -1, -1):
		var pack_id := _queue[index]
		if bool(_background_requests.get(pack_id, false)):
			return pack_id
	return ""


func _enforce_background_limit(limit: int) -> void:
	var allowance := maxi(limit - (1 if _active_background else 0), 0)
	if limit <= 0 and _active_background:
		_cancel_active()
		allowance = 0
	var background_total := 0
	for pack_id: String in _queue:
		if bool(_background_requests.get(pack_id, false)):
			background_total += 1
	for index: int in range(_queue.size() - 1, -1, -1):
		if background_total <= allowance:
			break
		var queued_id := _queue[index]
		if not bool(_background_requests.get(queued_id, false)):
			continue
		_queue.remove_at(index)
		_queued.erase(queued_id)
		_background_requests.erase(queued_id)
		background_total -= 1
	if _request == null and _active_id.is_empty() and not _queue.is_empty():
		_pump_queue.call_deferred()


func _refresh_web_network_profile() -> void:
	if not OS.has_feature("web"):
		return
	var value: Variant = JavaScriptBridge.eval(
		"String(window.__protosNetworkProfile || 'standard')", true,
	)
	var profile := StringName(String(value))
	if profile not in [&"constrained", &"slow", &"standard", &"fast"]:
		profile = &"standard"
	if profile == _network_profile:
		return
	_apply_network_profile(profile)
	background_policy_changed.emit(
		_background_downloads_enabled, _network_profile, _background_class_limit,
	)


func _apply_network_profile(profile: StringName) -> void:
	_network_profile = profile
	_background_class_limit = int(prefetch_limits_for_profile(profile)[&"classes"])
	_enforce_background_limit(_background_class_limit if _background_downloads_enabled else 0)


static func network_profile_from_arguments(arguments: PackedStringArray) -> StringName:
	for argument: String in arguments:
		if not argument.begins_with(NETWORK_PROFILE_ARG_PREFIX):
			continue
		var profile := StringName(argument.substr(NETWORK_PROFILE_ARG_PREFIX.length()))
		if profile in [&"constrained", &"slow", &"standard", &"fast"]:
			return profile
	return &"standard"


static func prefetch_limits_for_profile(profile: StringName) -> Dictionary:
	match profile:
		&"constrained":
			return {&"classes": 0, &"missions": 0}
		&"slow":
			return {&"classes": 1, &"missions": 0}
		&"fast":
			return {&"classes": 3, &"missions": 6}
		_:
			return {&"classes": 2, &"missions": 2}


static func predictive_class_order(
		roster_rows: Array,
		selected_hero_ids: Array = [],
		max_classes := MAX_PREDICTIVE_CLASSES,
	) -> Array[String]:
	var rows_by_hero: Dictionary = {}
	for value: Variant in roster_rows:
		if value is not Dictionary:
			continue
		var row := value as Dictionary
		var hero_id := String(row.get("hero_id", ""))
		if not hero_id.is_empty():
			rows_by_hero[hero_id] = row
	var ordered: Array[String] = []
	for value: Variant in selected_hero_ids:
		var selected_row := rows_by_hero.get(String(value), {}) as Dictionary
		_append_predictive_class(ordered, String(selected_row.get("current_class_id", "")))
	var target_count := maxi(max_classes, ordered.size())
	for value: Variant in roster_rows:
		if ordered.size() >= target_count:
			break
		if value is Dictionary:
			_append_predictive_class(
				ordered, String((value as Dictionary).get("current_class_id", "")),
			)
	return ordered


static func _append_predictive_class(ordered: Array[String], class_id: String) -> void:
	if pack_id_for_class(class_id).is_empty() or ordered.has(class_id):
		return
	ordered.append(class_id)


static func valid_pack_ids() -> Array[String]:
	var result: Array[String] = []
	for class_id: String in ADVANCED_CLASSES:
		result.append("operator-%s" % class_id.replace("_", "-"))
	return result
