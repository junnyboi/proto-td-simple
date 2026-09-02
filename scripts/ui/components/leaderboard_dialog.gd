class_name MissionLeaderboardDialog
extends Control

## Shared modal used by the title and mission-results screens. It renders only
## projections from the Leaderboard autoload and never owns score authority.

signal closed

const Style := preload("res://scripts/ui/components/lunaris_ops_style.gd")
const UiCopyType := preload("res://scripts/ui/components/ui_copy.gd")
const StagingSkinType := preload("res://scripts/ui/components/staging_skin.gd")

const PANEL_MAX_SIZE := Vector2(980.0, 676.0)
const SAFE_MARGIN := 18
const NARROW_SAFE_MARGIN := 10
const ACTION_HEIGHT := 52.0

var current_tab: StringName = &"local"

var _safe: MarginContainer = null
var _panel: PanelContainer = null
var _stack: VBoxContainer = null
var _title: Label = null
var _name_label: Label = null
var _identity_row: BoxContainer = null
var _name_edit: LineEdit = null
var _save_name_button: Button = null
var _local_tab: Button = null
var _global_tab: Button = null
var _status: Label = null
var _rows: VBoxContainer = null
var _refresh_button: Button = null
var _close_button: Button = null
var _formula: Label = null
var _return_focus: Control = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 200
	visible = false
	set_process_unhandled_input(false)
	_build()
	var leaderboard := _service()
	var service_callback := Callable(self, "_on_service_state_changed")
	if leaderboard != null and not leaderboard.is_connected(&"state_changed", service_callback):
		leaderboard.connect(&"state_changed", service_callback)
	if not I18n.locale_changed.is_connected(_on_locale_changed):
		I18n.locale_changed.connect(_on_locale_changed)
	if not get_viewport().size_changed.is_connected(_apply_responsive_layout):
		get_viewport().size_changed.connect(_apply_responsive_layout)
	_refresh_copy()
	_apply_responsive_layout()


func _exit_tree() -> void:
	var leaderboard := _service()
	var service_callback := Callable(self, "_on_service_state_changed")
	if leaderboard != null and leaderboard.is_connected(&"state_changed", service_callback):
		leaderboard.disconnect(&"state_changed", service_callback)
	if I18n.locale_changed.is_connected(_on_locale_changed):
		I18n.locale_changed.disconnect(_on_locale_changed)
	var viewport := get_viewport()
	if viewport != null and viewport.size_changed.is_connected(_apply_responsive_layout):
		viewport.size_changed.disconnect(_apply_responsive_layout)


func open(return_focus: Control = null) -> void:
	_return_focus = return_focus
	current_tab = &"local"
	var leaderboard := _service()
	if leaderboard != null:
		_name_edit.text = String(leaderboard.call("player_name"))
	visible = true
	set_process_unhandled_input(true)
	_refresh_copy()
	_refresh_rows()
	_apply_responsive_layout()
	_local_tab.grab_focus.call_deferred()
	if leaderboard != null:
		leaderboard.call_deferred("sync")


func close() -> void:
	if not visible:
		return
	_commit_player_name(false)
	visible = false
	set_process_unhandled_input(false)
	var focus := _return_focus
	_return_focus = null
	closed.emit()
	if (
		focus != null
		and is_instance_valid(focus)
		and focus.is_visible_in_tree()
		and (not focus is BaseButton or not (focus as BaseButton).disabled)
	):
		focus.grab_focus.call_deferred()


func is_open() -> bool:
	return visible


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _build() -> void:
	var veil := ColorRect.new()
	veil.name = "Veil"
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.color = Color(Style.INK_DEEP, 0.90)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(veil)

	_safe = MarginContainer.new()
	_safe.name = "SafeMargin"
	_safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_safe)

	var placement := CenterContainer.new()
	placement.name = "Placement"
	placement.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_safe.add_child(placement)

	_panel = PanelContainer.new()
	_panel.name = "LeaderboardPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override(
		&"panel", Style.simple_gold_surface(Style.SIMPLE_GOLD_SURFACE, 20.0, 18, 2),
	)
	placement.add_child(_panel)

	_stack = VBoxContainer.new()
	_stack.name = "LeaderboardContent"
	_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stack.add_theme_constant_override(&"separation", 10)
	_panel.add_child(_stack)

	var header := HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override(&"separation", 12)
	_stack.add_child(header)
	var seal := TextureRect.new()
	seal.name = "LeaderboardSeal"
	seal.custom_minimum_size = Vector2(56.0, 56.0)
	seal.texture = StagingSkinType.LUNARIS_SEAL
	seal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	seal.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(seal)
	_title = _label("Heading", &"heading")
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override(&"font_size", 38)
	header.add_child(_title)

	var rule := ColorRect.new()
	rule.name = "HeaderRule"
	rule.custom_minimum_size.y = 2.0
	rule.color = Color(Style.CYAN, 0.62)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stack.add_child(rule)

	_identity_row = BoxContainer.new()
	_identity_row.name = "IdentityRow"
	_identity_row.add_theme_constant_override(&"separation", 10)
	_stack.add_child(_identity_row)
	_name_label = _label("UsernameLabel", &"eyebrow")
	_name_label.custom_minimum_size.x = 172.0
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_identity_row.add_child(_name_label)
	_name_edit = LineEdit.new()
	_name_edit.name = "UsernameEdit"
	_name_edit.max_length = MissionLeaderboardService.MAX_PLAYER_NAME_LENGTH
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.custom_minimum_size.y = ACTION_HEIGHT
	_name_edit.select_all_on_focus = true
	_name_edit.text_submitted.connect(_on_name_submitted)
	_name_edit.focus_exited.connect(_on_name_focus_exited)
	Style.apply_line_edit(_name_edit)
	_apply_simple_gold_field(_name_edit)
	_identity_row.add_child(_name_edit)
	_save_name_button = _button("SaveUsernameButton", &"gold")
	_save_name_button.custom_minimum_size = Vector2(180.0, ACTION_HEIGHT)
	_save_name_button.pressed.connect(_on_save_name_pressed)
	_identity_row.add_child(_save_name_button)

	var tabs := HBoxContainer.new()
	tabs.name = "LeaderboardTabs"
	tabs.add_theme_constant_override(&"separation", 10)
	_stack.add_child(tabs)
	_local_tab = _button("LocalTab", &"selected")
	_local_tab.toggle_mode = true
	_local_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_local_tab.custom_minimum_size.y = ACTION_HEIGHT
	_local_tab.pressed.connect(_set_tab.bind(&"local"))
	tabs.add_child(_local_tab)
	_global_tab = _button("GlobalTab", &"secondary")
	_global_tab.toggle_mode = true
	_global_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_global_tab.custom_minimum_size.y = ACTION_HEIGHT
	_global_tab.pressed.connect(_set_tab.bind(&"global"))
	tabs.add_child(_global_tab)

	_status = _label("LeaderboardStatus", &"status")
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.accessibility_live = AccessibilityServer.LIVE_POLITE
	_stack.add_child(_status)

	var scroll := ScrollContainer.new()
	scroll.name = "LeaderboardScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.follow_focus = true
	scroll.draw_focus_border = false
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stack.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.name = "LeaderboardRows"
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override(&"separation", 6)
	scroll.add_child(_rows)

	_formula = _label("ScoreFormula", &"detail")
	_formula.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_formula.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_formula.add_theme_font_size_override(&"font_size", 16)
	_stack.add_child(_formula)

	var actions := HBoxContainer.new()
	actions.name = "DialogActions"
	actions.add_theme_constant_override(&"separation", 10)
	_stack.add_child(actions)
	_refresh_button = _button("RefreshButton", &"secondary")
	_refresh_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_refresh_button.custom_minimum_size.y = ACTION_HEIGHT
	_refresh_button.pressed.connect(_on_refresh_pressed)
	actions.add_child(_refresh_button)
	_close_button = _button("CloseButton", &"gold")
	_close_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_close_button.custom_minimum_size.y = ACTION_HEIGHT
	_close_button.pressed.connect(close)
	actions.add_child(_close_button)
	_wire_focus([
		_name_edit, _save_name_button, _local_tab, _global_tab,
		_refresh_button, _close_button,
	])


func _label(node_name: String, role: StringName) -> Label:
	var label := Label.new()
	label.name = node_name
	Style.apply_label(label, role)
	return label


func _button(node_name: String, role: StringName) -> Button:
	var button := Button.new()
	button.name = node_name
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	Style.apply_compact_rounded_button(button, role)
	Style.apply_simple_gold_button(button, role == &"selected")
	return button


func _set_tab(tab: StringName) -> void:
	if tab not in [&"local", &"global"]:
		return
	current_tab = tab
	_update_tabs()
	_refresh_rows()
	if tab == &"global":
		var leaderboard := _service()
		if leaderboard != null:
			leaderboard.call_deferred("sync")


func _update_tabs() -> void:
	var local_selected := current_tab == &"local"
	_local_tab.set_pressed_no_signal(local_selected)
	_global_tab.set_pressed_no_signal(not local_selected)
	Style.apply_compact_rounded_button(_local_tab, &"selected" if local_selected else &"secondary")
	Style.apply_compact_rounded_button(_global_tab, &"secondary" if local_selected else &"selected")
	Style.apply_simple_gold_button(_local_tab, local_selected)
	Style.apply_simple_gold_button(_global_tab, not local_selected)


func _on_save_name_pressed() -> void:
	_commit_player_name(true)


func _on_name_submitted(_value: String) -> void:
	_commit_player_name(true)
	_name_edit.release_focus()


func _on_name_focus_exited() -> void:
	if visible:
		_commit_player_name(false)


func _commit_player_name(announce: bool) -> void:
	var leaderboard := _service()
	if leaderboard == null or _name_edit == null:
		return
	var normalized := String(leaderboard.call("set_player_name", _name_edit.text))
	_name_edit.text = normalized
	if announce:
		_status.text = UiCopyType.text(&"ui.leaderboard.name_saved", "Username saved.")
		_status.modulate = Style.CYAN


func _on_refresh_pressed() -> void:
	var leaderboard := _service()
	if leaderboard != null:
		leaderboard.call("sync")


func _on_service_state_changed() -> void:
	if visible:
		_refresh_rows()


func _on_locale_changed(_locale_id: StringName) -> void:
	_refresh_copy()
	_refresh_rows()
	_apply_responsive_layout()


func _refresh_copy() -> void:
	if _title == null:
		return
	_title.text = UiCopyType.text(
		&"ui.leaderboard.heading", "MISSION LEADERBOARD",
	).to_upper()
	_name_label.text = UiCopyType.text(
		&"ui.leaderboard.username", "USERNAME",
	).to_upper()
	_name_edit.placeholder_text = UiCopyType.text(
		&"ui.leaderboard.username_placeholder", "Enter username",
	)
	_save_name_button.text = UiCopyType.text(
		&"ui.leaderboard.save_name", "Save Name",
	).to_upper()
	_local_tab.text = UiCopyType.text(&"ui.leaderboard.local", "Local").to_upper()
	_global_tab.text = UiCopyType.text(&"ui.leaderboard.global", "Global").to_upper()
	_refresh_button.text = UiCopyType.text(
		&"ui.leaderboard.refresh", "Refresh Global",
	).to_upper()
	_close_button.text = UiCopyType.text(&"ui.leaderboard.close", "Close").to_upper()
	_formula.text = UiCopyType.text(
		&"ui.leaderboard.formula",
		"Score rewards clears, mission progress, stars and kills; leaks reduce it.",
	)
	_update_tabs()


func _refresh_rows() -> void:
	if _rows == null:
		return
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var leaderboard := _service()
	var records: Array[Dictionary] = []
	if leaderboard != null:
		var raw_records: Array = (
			leaderboard.call("local_entries", MissionLeaderboardService.DISPLAY_LIMIT)
			if current_tab == &"local"
			else leaderboard.get("entries") as Array
		)
		for raw_record: Variant in raw_records:
			if raw_record is Dictionary:
				records.append((raw_record as Dictionary).duplicate(true))
	_update_status(leaderboard)
	if records.is_empty():
		var empty := _label("EmptyLeaderboard", &"body")
		empty.text = UiCopyType.text(
			&"ui.leaderboard.empty_local"
			if current_tab == &"local"
			else &"ui.leaderboard.empty_global",
			"Complete a mission to post the first local score."
			if current_tab == &"local"
			else "No global scores are available yet.",
		)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.custom_minimum_size.y = 120.0
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_rows.add_child(empty)
		return
	var latest_id := String(leaderboard.call("latest_submission_id")) if leaderboard != null else ""
	for record: Dictionary in records:
		_rows.add_child(_record_row(record, latest_id))


func _record_row(record: Dictionary, latest_id: String) -> Control:
	var highlighted := (
		current_tab == &"local"
		and not latest_id.is_empty()
		and String(record.get("submission_id", "")) == latest_id
	)
	var panel := PanelContainer.new()
	panel.name = "LeaderboardRow%d" % int(record.get("rank", 0))
	panel.add_theme_stylebox_override(
		&"panel",
		Style.simple_gold_surface(
			Style.SIMPLE_GOLD_SURFACE_SELECTED if highlighted else Style.SIMPLE_GOLD_SURFACE,
			14.0,
			12,
			2 if highlighted else 1,
		),
	)
	var row := VBoxContainer.new()
	row.add_theme_constant_override(&"separation", 1)
	panel.add_child(row)
	var primary := HBoxContainer.new()
	primary.add_theme_constant_override(&"separation", 8)
	row.add_child(primary)
	var rank := _label("Rank", &"eyebrow")
	rank.text = "#%d" % int(record.get("rank", 0))
	rank.custom_minimum_size.x = 58.0
	primary.add_child(rank)
	var username := _label("Username", &"body")
	username.text = String(record.get("name", MissionLeaderboardService.DEFAULT_PLAYER_NAME))
	username.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	username.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	primary.add_child(username)
	var score := _label("Score", &"heading")
	score.text = "%07d" % int(record.get("score", 0))
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score.custom_minimum_size.x = 172.0
	score.add_theme_font_size_override(&"font_size", 28)
	primary.add_child(score)
	var meta := _label("Mission", &"detail")
	var outcome := UiCopyType.text(
		&"ui.results.clear" if bool(record.get("victory", false)) else &"ui.results.defeat",
		"CLEAR" if bool(record.get("victory", false)) else "DEFEAT",
	).to_upper()
	var stars := "★".repeat(clampi(int(record.get("stars", 0)), 0, 3))
	meta.text = "%s  ·  %s%s" % [
		String(record.get("stage_id", "")).to_upper(),
		outcome,
		"  ·  " + stars if not stars.is_empty() else "",
	]
	meta.modulate = Style.CYAN if highlighted else Style.MUTED
	row.add_child(meta)
	return panel


func _update_status(leaderboard: Node) -> void:
	if leaderboard == null:
		_status.text = UiCopyType.text(
			&"ui.leaderboard.offline", "Global service unavailable; local scores are safe.",
		)
		_status.modulate = Style.MUTED
		_refresh_button.disabled = true
		return
	var pending := int(leaderboard.call("pending_count"))
	if current_tab == &"local":
		_status.text = UiCopyType.text(
			&"ui.leaderboard.local_saved", "Scores are saved on this device.",
		)
		if pending > 0:
			_status.text += "  ·  %d %s" % [
				pending,
				UiCopyType.text(&"ui.leaderboard.pending", "awaiting global sync"),
			]
		_status.modulate = Style.CYAN
	else:
		match StringName(leaderboard.get("status")):
			&"loading":
				_status.text = UiCopyType.text(
					&"ui.leaderboard.loading", "Contacting global service…",
				)
				_status.modulate = Style.GOLD
			&"ready":
				_status.text = UiCopyType.text(
					&"ui.leaderboard.live", "Global standings are live.",
				)
				_status.modulate = Style.CYAN
			&"error":
				_status.text = UiCopyType.text(
					&"ui.leaderboard.retry", "Global sync failed. Local scores are safe; retry is available.",
				)
				_status.modulate = Style.DANGER
			_:
				_status.text = UiCopyType.text(
					&"ui.leaderboard.offline", "Global service unavailable; local scores are safe.",
				)
				_status.modulate = Style.MUTED
	_refresh_button.disabled = StringName(leaderboard.get("status")) == &"loading"


func _apply_responsive_layout() -> void:
	if _panel == null:
		return
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var narrow := viewport_size.x < 620.0
	var margin := NARROW_SAFE_MARGIN if narrow else SAFE_MARGIN
	for side: StringName in [&"margin_left", &"margin_top", &"margin_right", &"margin_bottom"]:
		_safe.add_theme_constant_override(side, margin)
	_panel.custom_minimum_size = Vector2(
		minf(PANEL_MAX_SIZE.x, viewport_size.x - float(margin * 2)),
		minf(PANEL_MAX_SIZE.y, viewport_size.y - float(margin * 2)),
	)
	_title.add_theme_font_size_override(&"font_size", 28 if narrow else 38)
	_identity_row.vertical = narrow
	_name_label.custom_minimum_size.x = 0.0 if narrow else 172.0
	_save_name_button.custom_minimum_size.x = 132.0 if narrow else 180.0
	_formula.visible = viewport_size.y >= 600.0
	for row: Node in _rows.get_children():
		var score := row.find_child("Score", true, false) as Label
		if score != null:
			score.custom_minimum_size.x = 118.0 if narrow else 172.0


func _wire_focus(controls: Array[Control]) -> void:
	for index: int in controls.size():
		var current := controls[index]
		var previous := controls[(index - 1 + controls.size()) % controls.size()]
		var following := controls[(index + 1) % controls.size()]
		current.focus_previous = current.get_path_to(previous)
		current.focus_next = current.get_path_to(following)


func _apply_simple_gold_field(field: LineEdit) -> void:
	field.add_theme_stylebox_override(
		&"normal", Style.simple_gold_surface(Style.SIMPLE_GOLD_SURFACE, 12.0, 12, 1),
	)
	field.add_theme_stylebox_override(
		&"focus",
		Style.simple_gold_surface(Style.SIMPLE_GOLD_SURFACE_HOVER, 12.0, 12, 2),
	)
	field.add_theme_stylebox_override(
		&"read_only",
		Style.simple_gold_surface(Color(0.025, 0.035, 0.05, 0.64), 12.0, 12, 1),
	)


func _service() -> Node:
	return get_node_or_null("/root/Leaderboard")
