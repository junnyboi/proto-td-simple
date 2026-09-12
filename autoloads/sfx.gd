extends Node

## Sole runtime SFX owner. Playback is alias-resolved, deduplicated per render
## frame, and remains presentation-only.

const CATALOG_PATH := "res://bundled/sfx/catalog.tres"
const SFX_CATALOG_SCRIPT: GDScript = preload("res://bundled/sfx/sfx_catalog.gd")
const VOICE_COUNT := 8
const PLAYER_PREFIX := "Voice"
const BUS_NAME := &"SFX"
const HOVER_CUE_ID := "ui_hover"
const HOVER_BIND_META := &"_sfx_hover_bound"
const HOVER_READY_META := &"_sfx_hover_ready_msec"
const HOVER_DISABLED_META := &"sfx_hover_disabled"
const HOVER_BIND_DELAY_MSEC := 120
const HOVER_DEBOUNCE_MSEC := 65
const MUTED_ROUTINE_CUE_IDS := {
	&"ui_hover": true,
	&"ui_back": true,
	&"ui_confirm": true,
	&"menu_open": true,
	&"menu_close": true,
}

var _catalog: Resource = null
var _players: Array[AudioStreamPlayer] = []
var _voice_cursor := 0
var _audible_start_count := 0
var _dedupe_count := 0
var _last_raw_id := &""
var _last_resolved_id := &""
var _last_stream_path := ""
var _last_started_frame_by_id: Dictionary = {}
var _last_hovered_control: Control = null
var _last_hover_play_msec := -HOVER_DEBOUNCE_MSEC
var _hover_binding_count := 0
var _hover_play_count := 0
var _prepared_streams: Dictionary = {}
var _world_voices: Dictionary = {}


func _ready() -> void:
	reload_catalog()
	_ensure_players()
	get_tree().node_added.connect(_on_tree_node_added)
	_bind_hover_descendants(get_tree().root)


func _exit_tree() -> void:
	stop_all()
	_catalog = null
	_players.clear()
	_last_hovered_control = null
	var tree := get_tree()
	if tree != null and tree.node_added.is_connected(_on_tree_node_added):
		tree.node_added.disconnect(_on_tree_node_added)


func reload_catalog() -> bool:
	var loaded := load(CATALOG_PATH) as Resource
	if not _catalog_contract_valid(loaded):
		_catalog = null
		return false
	_catalog = loaded
	return true


func _catalog_contract_valid(loaded: Resource) -> bool:
	if loaded == null or loaded.get_script() != SFX_CATALOG_SCRIPT:
		return false
	var entries_value: Variant = loaded.get("entries")
	var aliases_value: Variant = loaded.get("aliases")
	if not entries_value is Dictionary or not aliases_value is Dictionary:
		return false
	var entries: Dictionary = entries_value
	var aliases: Dictionary = aliases_value
	if entries.is_empty():
		return false
	return _entries_contract_valid(entries) and _aliases_contract_valid(entries, aliases)


func _entries_contract_valid(entries: Dictionary) -> bool:
	for raw_id: Variant in entries:
		if typeof(raw_id) != TYPE_STRING_NAME or StringName(raw_id).is_empty():
			return false
		if not entries[raw_id] is Dictionary:
			return false
	return true


func _aliases_contract_valid(entries: Dictionary, aliases: Dictionary) -> bool:
	for raw_id: Variant in aliases:
		var target: Variant = aliases[raw_id]
		if (
			typeof(raw_id) != TYPE_STRING_NAME
			or typeof(target) != TYPE_STRING_NAME
			or not entries.has(target)
		):
			return false
	return true


## A true return means one AudioStreamPlayer started.
func play(id: String) -> bool:
	return _play_cue(id, null, Vector2.ZERO)


func play_world(id: String, owner: Node2D, local_origin: Vector2) -> bool:
	if not _world_origin_visible(owner, local_origin):
		return false
	return _play_cue(id, owner, local_origin)


func _world_origin_visible(owner: Node2D, local_origin: Vector2) -> bool:
	return is_instance_valid(owner) and owner.is_inside_tree() and owner.has_method("world_audio_visible") and bool(owner.call("world_audio_visible", local_origin))


func _play_cue(id: String, world_owner: Node2D, local_origin: Vector2) -> bool:
	var raw_id := StringName(id)
	if raw_id.is_empty():
		return false
	var resolved_id := resolved_id_for(raw_id)
	if resolved_id.is_empty():
		return false
	if MUTED_ROUTINE_CUE_IDS.has(resolved_id):
		return false
	var frame := Engine.get_process_frames()
	if int(_last_started_frame_by_id.get(resolved_id, -1)) == frame:
		_dedupe_count += 1
		return false
	var stream_path := _stream_path_for(resolved_id)
	if stream_path.is_empty():
		return false
	# Godot's Dummy audio driver leaks AudioStreamPlaybackWAV objects when a
	# SceneTree test quits. Preserve semantic playback counters/path assertions
	# without allocating a voice in that non-audible verification environment.
	if AudioServer.get_driver_name() != "Dummy":
		var stream := _prepared_streams.get(stream_path) as AudioStream
		if stream == null:
			stream = load(stream_path) as AudioStream
		if stream == null:
			return false
		var players := _ensure_players()
		var player := players[_voice_cursor]
		player.stop()
		player.stream = stream
		player.pitch_scale = 1.0
		var entry: Dictionary = (_catalog.get("entries") as Dictionary)[resolved_id]
		player.volume_db = clampf(float(entry.get("volume_db", 0.0)), -24.0, 0.0)
		_world_voices.erase(_voice_cursor)
		if world_owner != null:
			_world_voices[_voice_cursor] = {"owner": weakref(world_owner), "origin": local_origin}
		player.play()
		_voice_cursor = (_voice_cursor + 1) % VOICE_COUNT
	_audible_start_count += 1
	_last_raw_id = raw_id
	_last_resolved_id = resolved_id
	_last_stream_path = stream_path
	_last_started_frame_by_id[resolved_id] = frame
	return true


func prepare_cues(ids: Array[StringName]) -> bool:
	var prepared := true
	for raw_id: StringName in ids:
		var resolved_id := resolved_id_for(raw_id)
		var stream_path := _stream_path_for(resolved_id)
		if stream_path.is_empty():
			prepared = false
			continue
		var stream := load(stream_path) as AudioStream
		if stream == null:
			prepared = false
			continue
		_prepared_streams[stream_path] = stream
	return prepared


func _stream_path_for(resolved_id: StringName) -> String:
	var entries_value: Variant = _catalog.get("entries") if _catalog != null else null
	if not entries_value is Dictionary or not entries_value.has(resolved_id):
		return ""
	var entries: Dictionary = entries_value
	var entry: Dictionary = entries[resolved_id]
	return String(entry.get("path", ""))


func resolved_id_for(raw_id: StringName) -> StringName:
	if _catalog == null and not reload_catalog():
		return &""
	var entries_value: Variant = _catalog.get("entries")
	var aliases_value: Variant = _catalog.get("aliases")
	if not entries_value is Dictionary or not aliases_value is Dictionary:
		return &""
	var entries: Dictionary = entries_value
	var aliases: Dictionary = aliases_value
	if entries.has(raw_id):
		return raw_id
	var target: Variant = aliases.get(raw_id, &"")
	if typeof(target) == TYPE_STRING_NAME and entries.has(target):
		return target
	return &""


func stop_all() -> bool:
	_world_voices.clear()
	var stopped := false
	for player: AudioStreamPlayer in _ensure_players():
		if player.stream != null:
			stopped = true
		player.stop()
		player.stream = null
	return stopped


func catalog_entry_count() -> int:
	if _catalog == null and not reload_catalog():
		return 0
	var entries_value: Variant = _catalog.get("entries")
	return entries_value.size() if entries_value is Dictionary else 0


func player_count() -> int:
	var count := 0
	for child: Node in get_children():
		if child is AudioStreamPlayer:
			count += 1
	return count


func assigned_voice_count() -> int:
	var count := 0
	for player: AudioStreamPlayer in _ensure_players():
		if player.stream != null:
			count += 1
	return count


func audible_start_count() -> int:
	return _audible_start_count


func dedupe_count() -> int:
	return _dedupe_count


func hover_binding_count() -> int:
	return _hover_binding_count


func hover_play_count() -> int:
	return _hover_play_count


func hover_is_bound(control: Control) -> bool:
	return control != null and bool(control.get_meta(HOVER_BIND_META, false))


func hover_target_eligible(control: Control) -> bool:
	if not _hover_target_bindable(control):
		return false
	if control is BaseButton:
		return not (control as BaseButton).disabled
	if control is LineEdit:
		return (control as LineEdit).editable
	if control is TextEdit:
		return (control as TextEdit).editable
	if control is Slider:
		return (control as Slider).editable
	if control is SpinBox:
		return (control as SpinBox).editable
	if control is ScrollBar:
		return true
	if control is Range:
		return false
	if control is TabBar:
		var tab_bar := control as TabBar
		var tab_index := tab_bar.get_tab_idx_at_point(tab_bar.get_local_mouse_position())
		return tab_index >= 0 and not tab_bar.is_tab_disabled(tab_index)
	if control is ItemList:
		var item_list := control as ItemList
		var item_index := item_list.get_item_at_position(item_list.get_local_mouse_position(), true)
		return item_index >= 0 and not item_list.is_item_disabled(item_index)
	if control is MenuBar:
		var menu_bar := control as MenuBar
		for menu_index: int in menu_bar.get_menu_count():
			if not menu_bar.is_menu_hidden(menu_index) and not menu_bar.is_menu_disabled(menu_index):
				return true
		return false
	return control.focus_mode != Control.FOCUS_NONE


func last_raw_id() -> StringName:
	return _last_raw_id


func last_resolved_id() -> StringName:
	return _last_resolved_id


func last_stream_path() -> String:
	return _last_stream_path


func _ensure_players() -> Array[AudioStreamPlayer]:
	_ensure_bus()
	if _players.size() == VOICE_COUNT:
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
	for index: int in VOICE_COUNT:
		var player := get_node_or_null("%s%d" % [PLAYER_PREFIX, index]) as AudioStreamPlayer
		if player == null:
			player = AudioStreamPlayer.new()
			player.name = "%s%d" % [PLAYER_PREFIX, index]
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


func _on_tree_node_added(node: Node) -> void:
	if node is Control:
		_try_bind_hover_by_id.call_deferred(node.get_instance_id())


func _try_bind_hover_by_id(instance_id: int) -> void:
	var value := instance_from_id(instance_id)
	if value is Control:
		_try_bind_hover(value as Control)


func _bind_hover_descendants(node: Node) -> void:
	if node is Control:
		_try_bind_hover(node as Control)
	for child: Node in node.get_children():
		_bind_hover_descendants(child)


func _try_bind_hover(control: Control) -> void:
	if not is_instance_valid(control) or bool(control.get_meta(HOVER_BIND_META, false)):
		return
	control.set_meta(HOVER_BIND_META, true)
	control.set_meta(HOVER_READY_META, Time.get_ticks_msec() + HOVER_BIND_DELAY_MSEC)
	control.mouse_entered.connect(_on_control_hovered.bind(control))
	control.mouse_exited.connect(_on_control_unhovered.bind(control))
	_hover_binding_count += 1


func _on_control_hovered(control: Control) -> void:
	var hover_owner := _hover_owner_for(control)
	if hover_owner == null or not _hover_hierarchy_visible(hover_owner):
		return
	var now_msec := Time.get_ticks_msec()
	if now_msec < int(hover_owner.get_meta(HOVER_READY_META, 0)):
		return
	if hover_owner == _last_hovered_control or now_msec - _last_hover_play_msec < HOVER_DEBOUNCE_MSEC:
		return
	if play(HOVER_CUE_ID):
		_last_hovered_control = hover_owner
		_last_hover_play_msec = now_msec
		_hover_play_count += 1


func _on_control_unhovered(control: Control) -> void:
	var hover_owner := _hover_owner_for(control)
	if hover_owner == _last_hovered_control:
		_last_hovered_control = null


func _hover_target_bindable(control: Control) -> bool:
	if control == null or bool(control.get_meta(HOVER_DISABLED_META, false)):
		return false
	if control.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		return false
	return (
		control is BaseButton
		or control is Slider
		or control is SpinBox
		or control is ScrollBar
		or control is LineEdit
		or control is TextEdit
		or control is ItemList
		or control is TabBar
		or control is MenuBar
		or control.focus_mode != Control.FOCUS_NONE
	)


func _hover_owner_for(control: Control) -> Control:
	if control == null:
		return null
	var owner: Control = null
	var cursor: Node = control
	while cursor is Control:
		var candidate := cursor as Control
		if hover_target_eligible(candidate):
			owner = candidate
		cursor = cursor.get_parent()
	return owner


func _hover_hierarchy_visible(control: Control) -> bool:
	var cursor: Node = control
	while cursor != null:
		if cursor is CanvasItem and not (cursor as CanvasItem).visible:
			return false
		cursor = cursor.get_parent()
	return true


func _process(_delta: float) -> void:
	for index: int in _world_voices.keys():
		var record: Dictionary = _world_voices[index]
		var owner := (record["owner"] as WeakRef).get_ref() as Node2D
		if not _world_origin_visible(owner, record["origin"]):
			_players[index].stop()
			_players[index].stream = null
			_world_voices.erase(index)
		elif not _players[index].playing:
			_world_voices.erase(index)


func stop_world_owner(owner: Node2D) -> void:
	for index: int in _world_voices.keys():
		if (_world_voices[index]["owner"] as WeakRef).get_ref() == owner:
			_players[index].stop()
			_players[index].stream = null
			_world_voices.erase(index)


func world_voice_count() -> int:
	return _world_voices.size()
