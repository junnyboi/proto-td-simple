class_name Art
extends RefCounted

## Manifest-resolved texture access for all view/UI code (parent plan §6.6:
## scene code never hardcodes asset paths). Returns null for unknown ids so
## callers can keep their rect fallback — a missing asset degrades to the
## placeholder look instead of crashing a battle.

static var _manifest: AssetManifest = null
static var _supplemental_manifest: AssetManifest = null
static var _enemy_static_manifest: AssetManifest = null
static var _manifest_entries: Dictionary = {}
static var _manifest_error := false
static var _cache: Dictionary = {}


static func _load_manifests() -> void:
	if (
		(
			_manifest != null
				and _supplemental_manifest != null
				and _enemy_static_manifest != null
			)
		or _manifest_error
	):
		return
	_manifest = load("res://assets/manifest.tres") as AssetManifest
	_supplemental_manifest = load("res://assets/act1_shared_manifest.tres") as AssetManifest
	_enemy_static_manifest = load("res://assets/enemy_static_manifest.tres") as AssetManifest
	if (
		_manifest == null
			or _supplemental_manifest == null
			or _enemy_static_manifest == null
		):
		_manifest_error = true
		push_error("Art: failed to load base, supplemental, or enemy-static manifest")
		return
	var merged := merge_manifest_entries(_manifest.entries, _supplemental_manifest.entries)
	if not bool(merged[&"ok"]):
		_manifest_error = true
		push_error("Art: duplicate asset id across manifest layers: %s" % merged[&"duplicate_id"])
		return
	var merged_static := merge_manifest_entries(
		merged[&"entries"], _enemy_static_manifest.entries
	)
	if not bool(merged_static[&"ok"]):
		_manifest_error = true
		push_error(
			"Art: duplicate enemy-static asset id across manifest layers: %s"
			% merged_static[&"duplicate_id"]
		)
		return
	_manifest_entries = merged_static[&"entries"]


## Pure test seam: base owns precedence, but overlap fails closed rather than shadowing.
static func merge_manifest_entries(
	base_entries: Dictionary, supplemental_entries: Dictionary
) -> Dictionary:
	var entries := base_entries.duplicate(true)
	for raw_id: Variant in supplemental_entries:
		if entries.has(raw_id):
			return {&"ok": false, &"entries": {}, &"duplicate_id": raw_id}
		entries[raw_id] = supplemental_entries[raw_id]
	return {&"ok": true, &"entries": entries, &"duplicate_id": &""}


## Internal reset seam for focused tests; never returns mutable manifest state.
static func _reset_manifests_for_test() -> void:
	_manifest = null
	_supplemental_manifest = null
	_enemy_static_manifest = null
	_manifest_entries = {}
	_manifest_error = false
	_cache.clear()


static func _entry(id: StringName) -> Dictionary:
	_load_manifests()
	if _manifest_error:
		return {}
	var entry: Variant = _manifest_entries.get(id)
	return entry if entry is Dictionary else {}


static func frame_count(id: StringName) -> int:
	return int(_entry(id).get("frames", 0))


static func fps(id: StringName) -> float:
	var animations: Variant = _entry(id).get("animations", {})
	if animations is not Dictionary or animations.is_empty():
		return 0.0
	var names: Array = animations.keys()
	names.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
	var region: Variant = animations[names[0]]
	return float(region.get(&"fps", 0.0)) if region is Dictionary else 0.0


## Native pixel size from the manifest (P12.1: tiles are no longer a
## uniform canvas). Vector2i.ZERO for unknown ids or entries without a
## size, so callers can keep their fallback sizing.
static func size(id: StringName) -> Vector2i:
	var stored: Variant = _entry(id).get("size", Vector2i.ZERO)
	if stored is Vector2i:
		return stored
	return Vector2i.ZERO


static func metadata(id: StringName) -> Dictionary:
	return _entry(id).duplicate(true)


static func pivot(id: StringName) -> Vector2:
	var stored: Variant = _entry(id).get("pivot", Vector2.ZERO)
	return stored if stored is Vector2 else Vector2.ZERO


static func animation_names(id: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	var stored: Variant = _entry(id).get("animations", {})
	if stored is not Dictionary:
		return result
	for raw_name: Variant in stored:
		if typeof(raw_name) == TYPE_STRING_NAME:
			result.append(raw_name)
	result.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return result


static func animation_frame_index(id: StringName, animation: StringName, local_frame: int) -> int:
	if local_frame < 0:
		return -1
	var stored: Variant = _entry(id).get("animations", {})
	if stored is not Dictionary or not stored.has(animation):
		return -1
	var raw_region: Variant = stored[animation]
	if raw_region is not Dictionary:
		return -1
	var length := int(raw_region.get("length", 0))
	if local_frame >= length:
		return -1
	return int(raw_region.get("start", -1)) + local_frame


static func animation_texture(id: StringName, animation: StringName, local_frame: int) -> Texture2D:
	var frame := animation_frame_index(id, animation, local_frame)
	return texture(id, frame) if frame >= 0 else null


static func texture(id: StringName, frame := 0) -> Texture2D:
	var entry := _entry(id)
	if entry.is_empty():
		return null
	# Generated 640px animation frames deliberately bypass the process-lifetime
	# frame cache. The live TextureRect owns the current AtlasTexture; replacing
	# it releases old frame/atlas references instead of accumulating every atlas
	# visited across a campaign session.
	var cache_frame := not entry.has(&"provenance")
	var key := "%s/%d" % [id, frame]
	if cache_frame and _cache.has(key):
		var cached: Variant = _cache[key]
		if cached is Texture2D:
			return cached
		_cache.erase(key)
	var frames := int(entry.get("frames", 0))
	if frame < 0 or frame >= frames:
		return null
	var pattern: String = entry["pattern"]
	var tex: Texture2D = null
	if frames > 1 and not pattern.contains("%d"):
		var frame_size := size(id)
		var atlas_source := _load_texture(pattern)
		if atlas_source != null and frame_size != Vector2i.ZERO:
			var atlas := AtlasTexture.new()
			atlas.atlas = atlas_source
			atlas.region = atlas_region_for_frame(entry, frame)
			atlas.filter_clip = true
			tex = atlas
	else:
		var path := pattern % frame if frames > 1 else pattern
		tex = _load_texture(path)
	if tex != null and cache_frame:
		_cache[key] = tex
	return tex


static func _cached_texture_count_for_test() -> int:
	return _cache.size()


static func atlas_region_for_frame(entry: Dictionary, frame: int) -> Rect2i:
	var frames := int(entry.get(&"frames", 0))
	var stored_size: Variant = entry.get(&"size", Vector2i.ZERO)
	if frame < 0 or frame >= frames or stored_size is not Vector2i or stored_size == Vector2i.ZERO:
		return Rect2i()
	var columns := maxi(1, int(entry.get(&"columns", frames)))
	return Rect2i(
		(frame % columns) * stored_size.x,
		(frame / columns) * stored_size.y,
		stored_size.x,
		stored_size.y,
	)


static func _load_texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
		var main_loop := Engine.get_main_loop()
		if main_loop is SceneTree:
			var content_packs := (main_loop as SceneTree).root.get_node_or_null("ContentPacks")
			if content_packs != null:
				content_packs.call("request_resource", path)
		return null
	if not _import_cache_missing(path):
		var imported := ResourceLoader.load(path) as Texture2D
		if imported != null:
			return imported
	return _load_source_image(path)


static func _import_cache_missing(path: String) -> bool:
	var import_path := path + ".import"
	if not FileAccess.file_exists(import_path):
		return false
	var config := ConfigFile.new()
	if config.load(import_path) != OK:
		return false
	var cache_path := String(config.get_value("remap", "path", ""))
	return not cache_path.is_empty() and not FileAccess.file_exists(cache_path)


static func _load_source_image(path: String) -> Texture2D:
	if path.get_extension().to_lower() not in ["png", "webp"] or not FileAccess.file_exists(path):
		return null
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	if image == null or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)
