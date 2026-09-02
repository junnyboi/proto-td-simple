class_name ViewPreferences
extends RefCounted

## Durable presentation-only preferences. These never enter campaign state,
## tickets, replays, or simulation hashes.

const DEFAULT_PATH := "user://view_preferences.cfg"
const NAVIGATION_SECTION := "navigation"
const PAN_HINT_KEY := "pan_hint_completed"
const COMMAND_TUTORIAL_KEY := "command_tutorial_completed"
const POST_MISSION_TUTORIAL_KEY := "post_mission_tutorial_completed"
const LOCALIZATION_SECTION := "localization"
const LOCALE_KEY := "locale"
const AUDIO_SECTION := "audio"
const TITLE_MUSIC_ENABLED_KEY := "title_music_enabled"
const MASTER_VOLUME_KEY := "master_volume"
const MASTER_MUTED_KEY := "master_muted"
const MUSIC_VOLUME_KEY := "music_volume"
const SFX_VOLUME_KEY := "sfx_volume"
const NETWORK_SECTION := "network"
const BACKGROUND_DOWNLOADS_ENABLED_KEY := "background_downloads_enabled"
const GRAPHICS_SECTION := "graphics"
const REDUCED_MOTION_KEY := "reduced_motion"
const FRAME_LIMIT_KEY := "frame_limit"
const ACCESSIBILITY_SECTION := "accessibility"
const TEXT_SCALE_KEY := "text_scale"
const MIN_TEXT_SCALE := 0.80
const MAX_TEXT_SCALE := 1.50
const TEXT_SCALE_STEP := 0.05
const VALID_FRAME_LIMITS := [0, 30, 60, 120]
const VALID_LOCALES: Array[StringName] = [&"en-US", &"zh-CN"]
const BATCH_KEYS: Array[StringName] = [
		&"locale", &"title_music_enabled", &"master_volume", &"master_muted", &"music_volume",
		&"sfx_volume", &"frame_limit", &"reduced_motion", &"text_scale",
		&"background_downloads_enabled",
	]


static func has_seen_pan_hint(path: String = DEFAULT_PATH) -> bool:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return false
	return bool(config.get_value(NAVIGATION_SECTION, PAN_HINT_KEY, false))


static func mark_pan_hint_seen(path: String = DEFAULT_PATH) -> bool:
	var config := ConfigFile.new()
	var load_error := config.load(path)
	if load_error != OK and load_error != ERR_FILE_NOT_FOUND:
		config = ConfigFile.new()
	config.set_value(NAVIGATION_SECTION, PAN_HINT_KEY, true)
	return config.save(path) == OK


static func has_seen_command_tutorial(path: String = DEFAULT_PATH) -> bool:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return false
	return bool(config.get_value(NAVIGATION_SECTION, COMMAND_TUTORIAL_KEY, false))


static func mark_command_tutorial_seen(path: String = DEFAULT_PATH) -> bool:
	return _set_value(NAVIGATION_SECTION, COMMAND_TUTORIAL_KEY, true, path)


static func has_seen_post_mission_tutorial(path: String = DEFAULT_PATH) -> bool:
	return has_seen_tutorial(POST_MISSION_TUTORIAL_KEY, path)


static func mark_post_mission_tutorial_seen(path: String = DEFAULT_PATH) -> bool:
	return mark_tutorial_seen(POST_MISSION_TUTORIAL_KEY, path)


static func has_seen_tutorial(key: StringName, path: String = DEFAULT_PATH) -> bool:
	if key not in _tutorial_keys():
		return false
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return false
	return bool(config.get_value(NAVIGATION_SECTION, key, false))


static func mark_tutorial_seen(key: StringName, path: String = DEFAULT_PATH) -> bool:
	if key not in _tutorial_keys():
		return false
	return _set_value(NAVIGATION_SECTION, key, true, path)


static func locale(path: String = DEFAULT_PATH) -> StringName:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return &"en-US"
	var value := StringName(config.get_value(LOCALIZATION_SECTION, LOCALE_KEY, &"en-US"))
	return value if value in VALID_LOCALES else &"en-US"


static func set_locale(locale_id: StringName, path: String = DEFAULT_PATH) -> bool:
	if locale_id not in VALID_LOCALES:
		return false
	return _set_value(LOCALIZATION_SECTION, LOCALE_KEY, locale_id, path)


static func title_music_enabled(path: String = DEFAULT_PATH) -> bool:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return true
	return bool(config.get_value(AUDIO_SECTION, TITLE_MUSIC_ENABLED_KEY, true))


static func set_title_music_enabled(enabled: bool, path: String = DEFAULT_PATH) -> bool:
	return _set_value(AUDIO_SECTION, TITLE_MUSIC_ENABLED_KEY, enabled, path)


static func master_volume(path: String = DEFAULT_PATH) -> float:
	return _volume_value(MASTER_VOLUME_KEY, path)


static func set_master_volume(value: float, path: String = DEFAULT_PATH) -> bool:
	return _set_value(AUDIO_SECTION, MASTER_VOLUME_KEY, clampf(value, 0.0, 1.0), path)


static func master_muted(path: String = DEFAULT_PATH) -> bool:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return false
	return bool(config.get_value(AUDIO_SECTION, MASTER_MUTED_KEY, false))


static func set_master_muted(muted: bool, path: String = DEFAULT_PATH) -> bool:
	return _set_value(AUDIO_SECTION, MASTER_MUTED_KEY, muted, path)


static func music_volume(path: String = DEFAULT_PATH) -> float:
	return _volume_value(MUSIC_VOLUME_KEY, path)


static func set_music_volume(value: float, path: String = DEFAULT_PATH) -> bool:
	return _set_value(AUDIO_SECTION, MUSIC_VOLUME_KEY, clampf(value, 0.0, 1.0), path)


static func sfx_volume(path: String = DEFAULT_PATH) -> float:
	return _volume_value(SFX_VOLUME_KEY, path)


static func set_sfx_volume(value: float, path: String = DEFAULT_PATH) -> bool:
	return _set_value(AUDIO_SECTION, SFX_VOLUME_KEY, clampf(value, 0.0, 1.0), path)


static func background_downloads_enabled(path: String = DEFAULT_PATH) -> bool:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return true
	return bool(config.get_value(NETWORK_SECTION, BACKGROUND_DOWNLOADS_ENABLED_KEY, true))


static func set_background_downloads_enabled(enabled: bool, path: String = DEFAULT_PATH) -> bool:
	return _set_value(NETWORK_SECTION, BACKGROUND_DOWNLOADS_ENABLED_KEY, enabled, path)


static func reduced_motion(path: String = DEFAULT_PATH) -> bool:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return false
	return bool(config.get_value(GRAPHICS_SECTION, REDUCED_MOTION_KEY, false))


static func set_reduced_motion(enabled: bool, path: String = DEFAULT_PATH) -> bool:
	return _set_value(GRAPHICS_SECTION, REDUCED_MOTION_KEY, enabled, path)


static func frame_limit(path: String = DEFAULT_PATH) -> int:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return 0
	var value := int(config.get_value(GRAPHICS_SECTION, FRAME_LIMIT_KEY, 0))
	return value if value in VALID_FRAME_LIMITS else 0


static func set_frame_limit(value: int, path: String = DEFAULT_PATH) -> bool:
	var sanitized := value if value in VALID_FRAME_LIMITS else 0
	return _set_value(GRAPHICS_SECTION, FRAME_LIMIT_KEY, sanitized, path)


static func text_scale(path: String = DEFAULT_PATH) -> float:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return 1.0
	return _sanitize_text_scale(float(config.get_value(ACCESSIBILITY_SECTION, TEXT_SCALE_KEY, 1.0)))


static func set_text_scale(value: float, path: String = DEFAULT_PATH) -> bool:
	if not is_finite(value) or value < MIN_TEXT_SCALE or value > MAX_TEXT_SCALE:
		return false
	return _set_value(ACCESSIBILITY_SECTION, TEXT_SCALE_KEY, _sanitize_text_scale(value), path)


## Validates and durably replaces the complete Title Settings preference batch.
## Existing unrelated sections and keys are retained semantically.
static func save_batch(values: Dictionary, path: String = DEFAULT_PATH) -> bool:
	if path.is_empty() or not _valid_batch(values):
		return false
	var config := ConfigFile.new()
	var load_error := config.load(path)
	if load_error != OK and load_error != ERR_FILE_NOT_FOUND:
		return false
	config.set_value(LOCALIZATION_SECTION, LOCALE_KEY, StringName(values[&"locale"]))
	config.set_value(AUDIO_SECTION, TITLE_MUSIC_ENABLED_KEY, bool(values[&"title_music_enabled"]))
	config.set_value(AUDIO_SECTION, MASTER_VOLUME_KEY, float(values[&"master_volume"]))
	config.set_value(AUDIO_SECTION, MASTER_MUTED_KEY, bool(values[&"master_muted"]))
	config.set_value(AUDIO_SECTION, MUSIC_VOLUME_KEY, float(values[&"music_volume"]))
	config.set_value(AUDIO_SECTION, SFX_VOLUME_KEY, float(values[&"sfx_volume"]))
	config.set_value(
		NETWORK_SECTION,
		BACKGROUND_DOWNLOADS_ENABLED_KEY,
		bool(values[&"background_downloads_enabled"]),
	)
	config.set_value(GRAPHICS_SECTION, FRAME_LIMIT_KEY, int(values[&"frame_limit"]))
	config.set_value(GRAPHICS_SECTION, REDUCED_MOTION_KEY, bool(values[&"reduced_motion"]))
	config.set_value(ACCESSIBILITY_SECTION, TEXT_SCALE_KEY, float(values[&"text_scale"]))
	var temporary_path := "%s.tmp" % path
	var global_temporary_path := ProjectSettings.globalize_path(temporary_path)
	if FileAccess.file_exists(temporary_path):
		if DirAccess.remove_absolute(global_temporary_path) != OK:
			return false
	if config.save(temporary_path) != OK:
		return false
	var replace_error := DirAccess.rename_absolute(
		global_temporary_path, ProjectSettings.globalize_path(path),
	)
	if replace_error != OK:
		DirAccess.remove_absolute(global_temporary_path)
		return false
	return true


static func _valid_batch(values: Dictionary) -> bool:
	if values.size() != BATCH_KEYS.size():
		return false
	for key: StringName in BATCH_KEYS:
		if not values.has(key):
			return false
	var locale_value: Variant = values[&"locale"]
	if typeof(locale_value) != TYPE_STRING_NAME or locale_value not in VALID_LOCALES:
		return false
	if typeof(values[&"title_music_enabled"]) != TYPE_BOOL:
		return false
	if typeof(values[&"master_muted"]) != TYPE_BOOL:
		return false
	if typeof(values[&"reduced_motion"]) != TYPE_BOOL:
		return false
	if typeof(values[&"background_downloads_enabled"]) != TYPE_BOOL:
		return false
	for key: StringName in [&"master_volume", &"music_volume", &"sfx_volume"]:
		var value: Variant = values[key]
		if typeof(value) != TYPE_FLOAT or not is_finite(float(value)):
			return false
		if float(value) < 0.0 or float(value) > 1.0:
			return false
	var frame_value: Variant = values[&"frame_limit"]
	if typeof(frame_value) != TYPE_INT or int(frame_value) not in VALID_FRAME_LIMITS:
		return false
	var text_scale_value: Variant = values[&"text_scale"]
	if typeof(text_scale_value) != TYPE_FLOAT or not is_finite(float(text_scale_value)):
		return false
	var text_scale := float(text_scale_value)
	return (
		text_scale >= MIN_TEXT_SCALE
		and text_scale <= MAX_TEXT_SCALE
		and is_equal_approx(text_scale, _sanitize_text_scale(text_scale))
	)


static func _volume_value(key: String, path: String) -> float:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return 1.0
	return clampf(float(config.get_value(AUDIO_SECTION, key, 1.0)), 0.0, 1.0)


static func _sanitize_text_scale(value: float) -> float:
	if not is_finite(value):
		return 1.0
	return clampf(roundf(value / TEXT_SCALE_STEP) * TEXT_SCALE_STEP, MIN_TEXT_SCALE, MAX_TEXT_SCALE)


static func _set_value(section: String, key: String, value: Variant, path: String) -> bool:
	var config := ConfigFile.new()
	var load_error := config.load(path)
	if load_error != OK and load_error != ERR_FILE_NOT_FOUND:
		return false
	config.set_value(section, key, value)
	return config.save(path) == OK


static func _tutorial_keys() -> Array[StringName]:
	return [
		StringName(COMMAND_TUTORIAL_KEY),
		StringName(POST_MISSION_TUTORIAL_KEY),
	]
