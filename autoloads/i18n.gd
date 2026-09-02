extends Node

## Presentation-only localization seam. Locale and catalog data never enter

signal locale_changed(locale_id: StringName)

const DEFAULT_LOCALE := &"en-US"
const SUPPORTED_LOCALES: Array[StringName] = [&"en-US", &"zh-CN"]
const CATALOG_DIR := "res://localization"
const ROOT_KEYS := ["locale", "entries"]
const UiCopyType := preload("res://scripts/ui/components/ui_copy.gd")

var _locale := DEFAULT_LOCALE
var _entries: Dictionary = {}
var _catalogs: Dictionary = {}


func _ready() -> void:
	var loaded := reload_catalogs()
	assert(loaded, "Game template - TD localization catalogs must load")
	_activate_locale(DEFAULT_LOCALE)


func t(key: StringName, fallback: String) -> String:
	var value: Variant = _entries.get(String(key), fallback)
	if value is String and not String(value).is_empty():
		return String(value)
	var english := _catalogs.get(DEFAULT_LOCALE, {}) as Dictionary
	value = english.get(String(key), fallback)
	if value is String and not String(value).is_empty():
		return String(value)
	return fallback


func format_text(key: StringName, fallback: String, args: Dictionary) -> String:
	var expected_all := UiCopyType.placeholder_types()
	var expected: Dictionary = expected_all.get(key, {})
	if not _valid_args(key, fallback, args, expected):
		return fallback
	var template := t(key, fallback)
	if _placeholder_names(template) != _placeholder_names(fallback):
		push_error("I18n.format_text: catalog placeholder drift for %s" % key)
		return fallback
	for raw_name: Variant in expected:
		var name := StringName(raw_name)
		template = template.replace("{%s}" % name, str(args[name]))
	return template


func locale() -> StringName:
	return _locale


func supported_locales() -> PackedStringArray:
	return PackedStringArray(SUPPORTED_LOCALES.map(
		func(locale_id: StringName) -> String: return String(locale_id)
	))


func set_locale(locale_id: StringName) -> bool:
	if not SUPPORTED_LOCALES.has(locale_id) or not _catalogs.has(locale_id):
		return false
	if _locale == locale_id:
		return true
	_activate_locale(locale_id)
	locale_changed.emit(locale_id)
	return true


func reload_catalog() -> bool:
	return reload_catalogs()


func reload_catalogs() -> bool:
	var next_catalogs: Dictionary = {}
	var english_keys: Array[String] = []
	var english_entries: Dictionary = {}
	for locale_id: StringName in SUPPORTED_LOCALES:
		var path := "%s/%s.json" % [CATALOG_DIR, locale_id]
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			return false
		var catalog := parse_catalog_text(file.get_as_text(), locale_id)
		if catalog.is_empty():
			return false
		var entries := catalog["entries"] as Dictionary
		var keys := _sorted_string_keys(entries)
		if locale_id == DEFAULT_LOCALE:
			english_keys = keys
			english_entries = entries
		elif keys != english_keys:
			return false
		for key: String in keys:
			if locale_id != DEFAULT_LOCALE and (
					_placeholder_names(String(entries[key]))
					!= _placeholder_names(String(english_entries[key]))
				):
				return false
		next_catalogs[locale_id] = entries.duplicate(true)
	_catalogs = next_catalogs
	if not _catalogs.has(_locale):
		_locale = DEFAULT_LOCALE
	_entries = (_catalogs[_locale] as Dictionary).duplicate(true)
	return true


func catalog_keys(locale_id: StringName = &"") -> PackedStringArray:
	var requested := _locale if String(locale_id).is_empty() else locale_id
	var source := _catalogs.get(requested, {}) as Dictionary
	var keys := PackedStringArray()
	for raw_key: Variant in source:
		keys.append(String(raw_key))
	keys.sort()
	return keys


static func parse_catalog_text(
		text: String, expected_locale: StringName = DEFAULT_LOCALE,
		) -> Dictionary:
	if not SUPPORTED_LOCALES.has(expected_locale):
		return {}
	var root_keys: Array[String] = []
	var entry_keys: Array[String] = []
	for line: String in text.split("\n"):
		var root_key := _line_key(line, "  ")
		if not root_key.is_empty():
			if root_keys.has(root_key):
				return {}
			root_keys.append(root_key)
			continue
		var entry_key := _line_key(line, "    ")
		if not entry_key.is_empty():
			if entry_keys.has(entry_key):
				return {}
			entry_keys.append(entry_key)
	if root_keys != ROOT_KEYS or entry_keys.is_empty():
		return {}
	var sorted_keys := entry_keys.duplicate()
	sorted_keys.sort()
	if sorted_keys != entry_keys:
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return {}
	var catalog := parsed as Dictionary
	if catalog.keys() != ROOT_KEYS:
		return {}
	if String(catalog.get("locale", "")) != String(expected_locale):
		return {}
	var raw_entries: Variant = catalog.get("entries", {})
	if not raw_entries is Dictionary:
		return {}
	var entries := raw_entries as Dictionary
	if entries.size() != entry_keys.size():
		return {}
	for key: String in entry_keys:
		var value: Variant = entries.get(key)
		if not value is String or String(value).is_empty():
			return {}
	if not _is_canonical_catalog_text(text, entries, expected_locale):
		return {}
	return catalog


static func _line_key(line: String, indent: String) -> String:
	if not line.begins_with(indent + "\""):
		return ""
	if indent == "  " and line.begins_with("    \""):
		return ""
	var key_end := line.find("\":")
	if key_end <= indent.length() + 1:
		return ""
	return line.substr(indent.length() + 1, key_end - indent.length() - 1)


static func _is_canonical_catalog_text(
		text: String, entries: Dictionary, expected_locale: StringName,
		) -> bool:
	if not text.ends_with("\n") or text.contains("\r"):
		return false
	var lines := text.trim_suffix("\n").split("\n")
	if lines.size() != entries.size() + 5:
		return false
	if lines[0] != "{" or lines[1] != '  "locale": "%s",' % expected_locale:
		return false
	if lines[2] != '  "entries": {' or lines[-2] != "  }" or lines[-1] != "}":
		return false
	var keys: Array = entries.keys()
	keys.sort()
	for index: int in keys.size():
		var key := String(keys[index])
		var value := String(entries[keys[index]])
		var comma := "," if index < keys.size() - 1 else ""
		var expected := "    %s: %s%s" % [
			JSON.stringify(key), JSON.stringify(value), comma,
		]
		if lines[index + 3] != expected:
			return false
	return true


func _valid_args(
		key: StringName, fallback: String, args: Dictionary, expected: Dictionary,
	) -> bool:
	var expected_names := _string_keys(expected)
	var actual_names := _string_keys(args)
	if expected_names != actual_names:
		push_error("I18n.format_text: argument set mismatch for %s" % key)
		return false
	if _placeholder_names(fallback) != expected_names:
		push_error("I18n.format_text: fallback placeholder mismatch for %s" % key)
		return false
	for raw_name: Variant in expected:
		var name := StringName(raw_name)
		var expected_type := StringName(expected[raw_name])
		var value: Variant = args.get(name)
		if expected_type == &"int" and typeof(value) != TYPE_INT:
			push_error("I18n.format_text: expected int %s.%s" % [key, name])
			return false
		if expected_type == &"String" and typeof(value) != TYPE_STRING:
			push_error("I18n.format_text: expected String %s.%s" % [key, name])
			return false
	return true


static func _placeholder_names(text: String) -> Array[String]:
	var regex := RegEx.new()
	regex.compile("\\{([A-Za-z][A-Za-z0-9_]*)\\}")
	var names: Array[String] = []
	for result: RegExMatch in regex.search_all(text):
		var name := result.get_string(1)
		if names.has(name):
			return ["<duplicate>"]
		names.append(name)
	names.sort()
	return names


func _string_keys(values: Dictionary) -> Array[String]:
	var names: Array[String] = []
	for raw_name: Variant in values:
		if typeof(raw_name) != TYPE_STRING_NAME:
			return ["<non-StringName>"]
		names.append(String(raw_name))
	names.sort()
	return names


static func _sorted_string_keys(values: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	for raw_key: Variant in values:
		keys.append(String(raw_key))
	keys.sort()
	return keys


func _activate_locale(locale_id: StringName) -> void:
	_locale = locale_id
	_entries = (_catalogs[locale_id] as Dictionary).duplicate(true)
	TranslationServer.set_locale(String(locale_id))
	DisplayServer.window_set_title(t(&"ui.game_title", "Game template - TD"))
