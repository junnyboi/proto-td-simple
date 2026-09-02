class_name BattleControls
extends Control

signal confirmation_state_changed(state: StringName)

const GameTypographyType := preload("res://scripts/ui/game_typography.gd")
const Style := preload("res://scripts/ui/components/lunaris_ops_style.gd")
const DialogType := preload("res://scripts/ui/components/lunaris_dialog_sheet.gd")
const UiCopyType := preload("res://scripts/ui/components/ui_copy.gd")
const ViewPreferencesType := preload("res://scripts/view/view_preferences.gd")

## Pause/resume, speed cycle 1x/2x/4x, Q/E directional stepping, and resign. Every write remains on
## ticks_per_frame_scale or model.apply_action([&"resign"]); presentation never
## enters deterministic state.

const FONT_SIZE := GameTypographyType.DETAIL
const SPEED_CYCLE: Array[float] = [1.0, 2.0, 4.0, 0.0]
const SPEED_STEPS: Array[float] = [0.0, 1.0, 2.0, 4.0]
const PAUSED_LABEL_MIN_WIDTH := 0.0
const COMMAND_TARGET_SIZE := Vector2(112.0, 48.0)
const COMMAND_CONTENT_PADDING := 6.0
const COMMAND_CORNER_RADIUS := 12
const DECK_PADDING := 24.0
const DECK_VERTICAL_PADDING := DECK_PADDING + 8.0
const ACTION_GAP := 12
const PAUSE_MENU_WIDTH := 520.0
const PAUSE_MENU_ACTION_SIZE := Vector2(360.0, 72.0)
const MASTER_BUS := &"Master"
const MUSIC_BUS := &"Music"
const SFX_BUS := &"SFX"

enum ConfirmationState {
	CLOSED,
	ENTERING,
	ACTIVE,
	COMMITTING,
	EXITING,
}

var model: BattleModel = null
var view: Node2D = null

var _pause_button: Button = null
var _speed_button: Button = null
var _resign_button: Button = null
var _paused_label: Label = null
var _controls_deck: PanelContainer = null
var _controls_box: GridContainer = null
var _confirm: Control = null
var _confirm_dialog: Dictionary = {}
var _pause_menu: Control = null
var _pause_menu_panel: PanelContainer = null
var _pause_menu_title: Label = null
var _pause_menu_body: Label = null
var _pause_menu_resign_button: Button = null
var _pause_menu_settings_button: Button = null
var _settings_state = null
var _resume_scale: float = 1.0
var _pause_scale_snapshot: float = 1.0
var _confirmation_scale_snapshot: float = 1.0
var _confirmation_state := ConfirmationState.CLOSED
var _resign_dispatch_count := 0
var _interaction_enabled := true
var _last_paused := false
var _pause_menu_open := false
var _pause_return_focus: Control = null
var _settings_open := false
var _settings_committing := false
var _settings_snapshot: Dictionary = {}


func setup(battle_model: BattleModel, battle_view: Node2D) -> void:
	model = battle_model
	view = battle_view
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = Vector2.ZERO
	size = get_viewport().get_visible_rect().size
	_build_row()
	_build_pause_menu()
	_build_confirm()
	_build_settings()
	if not I18n.locale_changed.is_connected(_on_locale_changed):
		I18n.locale_changed.connect(_on_locale_changed)


func set_interaction_enabled(enabled: bool) -> void:
	_interaction_enabled = enabled
	_refresh_action_enabled()


func interaction_enabled() -> bool:
	return _interaction_enabled


func command_deck_rect() -> Rect2:
	return _controls_deck.get_global_rect() if _controls_deck != null else Rect2()


func relayout() -> void:
	size = get_viewport().get_visible_rect().size
	if not _confirm_dialog.is_empty():
		DialogType.relayout(_confirm_dialog)
	if _pause_menu_panel != null:
		_pause_menu_panel.custom_minimum_size.x = minf(
			PAUSE_MENU_WIDTH,
			maxf(size.x - 32.0, 280.0),
		)
	if _controls_deck != null:
		var portrait := size.y > size.x
		var compact := portrait or size.x < 760.0
		_controls_box.columns = 2 if compact else 4
		var target_width := minf(size.x - 32.0, 360.0 if compact else 620.0)
		_controls_deck.custom_minimum_size = Vector2(target_width, 0.0)
		_controls_deck.reset_size()
		var y := 180.0 if portrait else 112.0
		var deck_size := _controls_deck.get_combined_minimum_size()
		_controls_deck.size = Vector2(maxf(target_width, deck_size.x), deck_size.y)
		_controls_deck.position = Vector2(size.x - _controls_deck.size.x - 16.0, y)


func _build_row() -> void:
	_controls_deck = PanelContainer.new()
	_controls_deck.name = "BattleCommandDeck"
	_controls_deck.mouse_filter = Control.MOUSE_FILTER_PASS
	var deck_style := Style.panel_style(&"hud").duplicate() as StyleBox
	deck_style.content_margin_left = DECK_PADDING
	deck_style.content_margin_top = DECK_VERTICAL_PADDING
	deck_style.content_margin_right = DECK_PADDING
	deck_style.content_margin_bottom = DECK_VERTICAL_PADDING
	_controls_deck.add_theme_stylebox_override(&"panel", deck_style)
	add_child(_controls_deck)
	var center := CenterContainer.new()
	center.name = "ControlsCenter"
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_controls_deck.add_child(center)
	var box := GridContainer.new()
	box.name = "ControlsBox"
	box.columns = 4
	box.add_theme_constant_override(&"h_separation", ACTION_GAP)
	box.add_theme_constant_override(&"v_separation", ACTION_GAP)
	center.add_child(box)
	_controls_box = box
	_pause_button = _make_button("PauseButton", _copy(&"ui.battle.pause", "PAUSE"), &"secondary")
	_pause_button.pressed.connect(_on_pause_pressed)
	box.add_child(_pause_button)
	_speed_button = _make_button("SpeedButton", "1×", &"secondary")
	_apply_speed_shortcut_help()
	_speed_button.pressed.connect(_on_speed_pressed)
	box.add_child(_speed_button)
	_resign_button = _make_button("ResignButton", _copy(&"ui.battle.resign", "RESIGN"), &"danger")
	_resign_button.pressed.connect(_on_resign_pressed)
	box.add_child(_resign_button)
	_paused_label = Label.new()
	_paused_label.name = "PausedLabel"
	_paused_label.text = ""
	_paused_label.custom_minimum_size = Vector2(PAUSED_LABEL_MIN_WIDTH, 0)
	_paused_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	Style.apply_label(_paused_label, &"status")
	_paused_label.add_theme_font_size_override(&"font_size", GameTypographyType.ACTION)
	_paused_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_paused_label)
	_controls_deck.reset_size()
	relayout()


func _build_pause_menu() -> void:
	_pause_menu = Control.new()
	_pause_menu.name = "PauseMenuLayer"
	_pause_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_menu.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_ENABLED
	_pause_menu.z_index = 90
	_pause_menu.visible = false
	add_child(_pause_menu)

	var veil := ColorRect.new()
	veil.name = "PauseMenuVeil"
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.color = Color(Style.INK_DEEP, 0.86)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_menu.add_child(veil)

	var center := CenterContainer.new()
	center.name = "PauseMenuCenter"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_menu.add_child(center)

	_pause_menu_panel = PanelContainer.new()
	_pause_menu_panel.name = "PauseMenuPanel"
	_pause_menu_panel.custom_minimum_size = Vector2(PAUSE_MENU_WIDTH, 0.0)
	_pause_menu_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_pause_menu_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	Style.apply_panel(_pause_menu_panel, &"dialog")
	center.add_child(_pause_menu_panel)

	var stack := VBoxContainer.new()
	stack.name = "PauseMenuContent"
	stack.add_theme_constant_override(&"separation", 18)
	_pause_menu_panel.add_child(stack)

	_pause_menu_title = Label.new()
	_pause_menu_title.name = "PauseMenuTitle"
	_pause_menu_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_menu_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	Style.apply_label(_pause_menu_title, &"heading")
	_pause_menu_title.add_theme_font_size_override(&"font_size", GameTypographyType.SECTION_HEADING)
	stack.add_child(_pause_menu_title)

	var rule := ColorRect.new()
	rule.name = "PauseMenuRule"
	rule.custom_minimum_size = Vector2(0.0, 2.0)
	rule.color = Color(Style.CYAN, 0.66)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(rule)

	_pause_menu_body = Label.new()
	_pause_menu_body.name = "PauseMenuBody"
	_pause_menu_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_menu_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	Style.apply_label(_pause_menu_body, &"body")
	_pause_menu_body.add_theme_font_size_override(&"font_size", GameTypographyType.DETAIL)
	stack.add_child(_pause_menu_body)

	var actions := VBoxContainer.new()
	actions.name = "PauseMenuActions"
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override(&"separation", ACTION_GAP)
	stack.add_child(actions)

	_pause_menu_resign_button = _make_pause_menu_button("PauseMenuResignButton", &"danger")
	_pause_menu_resign_button.pressed.connect(_on_pause_menu_resign_pressed)
	actions.add_child(_pause_menu_resign_button)
	_pause_menu_settings_button = _make_pause_menu_button("PauseMenuSettingsButton", &"secondary")
	_pause_menu_settings_button.pressed.connect(_on_pause_menu_settings_pressed)
	actions.add_child(_pause_menu_settings_button)
	_pause_menu_resign_button.focus_neighbor_top = _pause_menu_resign_button.get_path_to(
		_pause_menu_settings_button,
	)
	_pause_menu_resign_button.focus_neighbor_bottom = _pause_menu_resign_button.get_path_to(
		_pause_menu_settings_button,
	)
	_pause_menu_resign_button.focus_previous = _pause_menu_resign_button.get_path_to(
		_pause_menu_settings_button,
	)
	_pause_menu_resign_button.focus_next = _pause_menu_resign_button.get_path_to(
		_pause_menu_settings_button,
	)
	_pause_menu_settings_button.focus_neighbor_top = _pause_menu_settings_button.get_path_to(
		_pause_menu_resign_button,
	)
	_pause_menu_settings_button.focus_neighbor_bottom = _pause_menu_settings_button.get_path_to(
		_pause_menu_resign_button,
	)
	_pause_menu_settings_button.focus_previous = _pause_menu_settings_button.get_path_to(
		_pause_menu_resign_button,
	)
	_pause_menu_settings_button.focus_next = _pause_menu_settings_button.get_path_to(
		_pause_menu_resign_button,
	)
	_pause_menu_panel.accessibility_labeled_by_nodes = [
		_pause_menu_panel.get_path_to(_pause_menu_title),
	]
	_pause_menu_panel.accessibility_described_by_nodes = [
		_pause_menu_panel.get_path_to(_pause_menu_body),
	]
	_refresh_pause_menu_copy()


func _make_pause_menu_button(button_name: String, role: StringName) -> Button:
	var button := Button.new()
	button.name = button_name
	button.custom_minimum_size = PAUSE_MENU_ACTION_SIZE
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.focus_mode = Control.FOCUS_ALL
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	Style.apply_button(button, role)
	button.add_theme_font_size_override(&"font_size", GameTypographyType.ACTION)
	return button


func _build_confirm() -> void:
	_confirm_dialog = DialogType.create(
		self,
		"ResignConfirmLayer",
		_copy(&"ui.battle.withdraw_title", "WITHDRAW FROM OPERATION?"),
		_copy(&"ui.battle.withdraw_body", "Withdrawal immediately seals this attempt as a defeat. Current deployment progress is not preserved."),
		_copy(&"ui.battle.confirm_defeat", "CONFIRM DEFEAT"),
		_copy(&"ui.battle.return", "RETURN TO BATTLE"),
		true,
		DialogType.Presentation.FULL_VIEWPORT,
	)
	_confirm = _confirm_dialog.get(&"overlay") as Control
	var panel := _confirm_dialog.get(&"panel") as PanelContainer
	panel.name = "ResignConfirm"
	var confirm := _confirm_dialog.get(&"confirm") as Button
	var cancel := _confirm_dialog.get(&"cancel") as Button
	confirm.name = "ConfirmResign"
	cancel.name = "CancelResign"
	confirm.accessibility_name = _copy(&"ui.battle.confirm_defeat", "CONFIRM DEFEAT")
	confirm.accessibility_description = _copy(
		&"ui.battle.confirm_defeat_description",
		"Withdraw from the operation and record this attempt as a defeat.",
	)
	cancel.accessibility_name = _copy(&"ui.battle.return", "RETURN TO BATTLE")
	cancel.accessibility_description = _copy(
		&"ui.battle.return_description",
		"Close the withdrawal confirmation and resume the prior battle speed.",
	)
	Style.apply_button(confirm, &"danger")
	Style.apply_button(cancel, &"secondary")
	confirm.pressed.connect(_on_confirm_resign)
	cancel.pressed.connect(_on_cancel_resign)


func _build_settings() -> void:
	var settings_scene := load("res://scenes/ui/title_settings.tscn") as PackedScene
	_settings_state = settings_scene.instantiate()
	_settings_state.name = "BattleSettings"
	_settings_state.z_index = 200
	add_child(_settings_state)
	_settings_state.cancel_requested.connect(_cancel_settings)
	_settings_state.apply_requested.connect(_apply_settings)
	_settings_state.preview_requested.connect(_preview_settings)
	_settings_state.clear_player_data_requested.connect(_clear_player_data)
	_settings_state.close_completed.connect(_on_settings_close_completed)


func _make_button(button_name: String, text: String, role: StringName) -> Button:
	var btn := Button.new()
	btn.name = button_name
	btn.text = text
	btn.focus_mode = Control.FOCUS_ALL
	btn.custom_minimum_size = COMMAND_TARGET_SIZE
	_apply_command_button_style(btn, role)
	return btn


func _apply_command_button_style(button: Button, role: StringName) -> void:
	Style.apply_compact_rounded_button(
		button,
		role,
		COMMAND_CONTENT_PADDING,
		COMMAND_CORNER_RADIUS,
	)
	button.add_theme_font_size_override(&"font_size", FONT_SIZE)


func _current_scale() -> float:
	return float(view.get("ticks_per_frame_scale"))


func _set_scale(value: float) -> void:
	view.set("ticks_per_frame_scale", value)


func _process(_delta: float) -> void:
	if view == null or model == null:
		return
	if _confirmation_state != ConfirmationState.CLOSED and model.result != BattleModel.Result.RUNNING:
		notify_battle_terminal()
	if _pause_menu_open and model.result != BattleModel.Result.RUNNING:
		_dismiss_pause_menu_for_terminal()
	var current := _current_scale()
	if current > 0.0 and _confirmation_state == ConfirmationState.CLOSED:
		_resume_scale = current
	var paused := current == 0.0
	var running := model.result == BattleModel.Result.RUNNING
	_pause_button.text = _copy(&"ui.battle.resume", "RESUME") if paused else _copy(&"ui.battle.pause", "PAUSE")
	_paused_label.text = _copy(&"ui.battle.paused", "PAUSED") if paused and _confirmation_state == ConfirmationState.CLOSED else ""
	_speed_button.text = "%d×" % int(round(current))
	_refresh_action_enabled()
	if paused != _last_paused:
		_apply_command_button_style(_pause_button, &"selected" if paused else &"secondary")
		_last_paused = paused
		relayout()


func _input(event: InputEvent) -> void:
	# Battle pause owns Space before GUI dispatch so a focused Pause, Speed, or
	# Resign button cannot also activate through Space's ui_accept binding. Speed
	# shortcuts are owned here for the same reason and never leak into map/UI input.
	var pause_pressed := event.is_action_pressed(&"battle_pause")
	var speed_down_pressed := event.is_action_pressed(&"battle_speed_down")
	var speed_up_pressed := event.is_action_pressed(&"battle_speed_up")
	if not pause_pressed and not speed_down_pressed and not speed_up_pressed:
		return
	if (
		_interaction_enabled
		and _confirmation_state == ConfirmationState.CLOSED
		and not _pause_menu_open
		and not _settings_open
		and model != null
		and model.result == BattleModel.Result.RUNNING
	):
		if pause_pressed:
			_on_pause_pressed()
		elif speed_down_pressed:
			_step_speed(-1)
		else:
			_step_speed(1)
	get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _settings_open:
		if (
			event.is_action_pressed("ui_cancel")
			and not _settings_committing
			and _settings_state.transition_state_name() == &"ACTIVE"
		):
			_cancel_settings()
		get_viewport().set_input_as_handled()
		return
	if _confirmation_state != ConfirmationState.CLOSED:
		if event.is_action_pressed("ui_cancel") and _confirmation_state == ConfirmationState.ACTIVE:
			cancel_resign_confirmation()
		# A visible confirmation owns every event that escaped GUI dispatch. This
		# prevents map, tutorial, deployment, pause, and shortcut fallthrough.
		get_viewport().set_input_as_handled()
		return
	if _pause_menu_open:
		if event.is_action_pressed("ui_cancel"):
			close_pause_menu()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel") and open_pause_menu():
		get_viewport().set_input_as_handled()


func _on_pause_pressed() -> void:
	if (
		not _interaction_enabled
		or _confirmation_state != ConfirmationState.CLOSED
		or _pause_menu_open
		or _settings_open
		or model.result != BattleModel.Result.RUNNING
	):
		return
	if _current_scale() == 0.0:
		Sfx.play("menu_close")
		_set_scale(_resume_scale)
	else:
		Sfx.play("menu_open")
		_set_scale(0.0)


func _on_speed_pressed() -> void:
	if (
		not _interaction_enabled
		or _confirmation_state != ConfirmationState.CLOSED
		or _pause_menu_open
		or _settings_open
		or model.result != BattleModel.Result.RUNNING
	):
		return
	Sfx.play("ui_click")
	var base := _current_scale()
	var idx := SPEED_CYCLE.find(base)
	var next: float = SPEED_CYCLE[(idx + 1) % SPEED_CYCLE.size()] if idx >= 0 else 1.0
	if next > 0.0:
		_resume_scale = next
	_set_scale(next)


func _step_speed(direction: int) -> bool:
	if (
		direction == 0
		or not _interaction_enabled
		or _confirmation_state != ConfirmationState.CLOSED
		or _pause_menu_open
		or _settings_open
		or model == null
		or view == null
		or model.result != BattleModel.Result.RUNNING
	):
		return false
	var current := _current_scale()
	var target: float = SPEED_STEPS.front() if direction < 0 else SPEED_STEPS.back()
	if direction < 0:
		for step: float in SPEED_STEPS:
			if step >= current - 0.0001:
				break
			target = step
	else:
		for step: float in SPEED_STEPS:
			if step > current + 0.0001:
				target = step
				break
	if is_equal_approx(target, current):
		return false
	Sfx.play("ui_click")
	if target > 0.0:
		_resume_scale = target
	_set_scale(target)
	return true


func _on_resign_pressed() -> void:
	request_resign_confirmation()


func open_pause_menu() -> bool:
	if (
		_pause_menu_open
		or _settings_open
		or _confirmation_state != ConfirmationState.CLOSED
		or model == null
		or view == null
		or model.result != BattleModel.Result.RUNNING
	):
		return false
	_pause_scale_snapshot = _current_scale()
	_pause_return_focus = get_viewport().gui_get_focus_owner()
	_pause_menu_open = true
	_set_scale(0.0)
	_pause_menu.visible = true
	view.call("set_battle_confirmation_active", true)
	_refresh_action_enabled()
	Sfx.play("menu_open")
	_pause_menu_settings_button.grab_focus.call_deferred()
	return true


func close_pause_menu() -> bool:
	if (
		not _pause_menu_open
		or _settings_open
		or _confirmation_state != ConfirmationState.CLOSED
	):
		return false
	_pause_menu_open = false
	_pause_menu.visible = false
	if view != null:
		view.call("set_battle_confirmation_active", false)
	if model != null and model.result == BattleModel.Result.RUNNING:
		_set_scale(_pause_scale_snapshot)
	_refresh_action_enabled()
	Sfx.play("menu_close")
	var focus_target := _pause_return_focus
	_pause_return_focus = null
	if (
		focus_target != null
		and is_instance_valid(focus_target)
		and focus_target.is_visible_in_tree()
		and focus_target.focus_mode != Control.FOCUS_NONE
		and (not focus_target is BaseButton or not (focus_target as BaseButton).disabled)
	):
		focus_target.grab_focus.call_deferred()
	return true


func pause_menu_active() -> bool:
	return _pause_menu_open


func settings_active() -> bool:
	return _settings_open


func _dismiss_pause_menu_for_terminal() -> void:
	if not _pause_menu_open:
		return
	_pause_menu_open = false
	_pause_menu.visible = false
	_pause_return_focus = null
	_refresh_action_enabled()


func _on_pause_menu_resign_pressed() -> void:
	if not _pause_menu_open or _settings_open:
		return
	_pause_menu.visible = false
	if not request_resign_confirmation(_pause_menu_resign_button):
		_pause_menu.visible = true
		_pause_menu_settings_button.grab_focus.call_deferred()


func _on_pause_menu_settings_pressed() -> void:
	if (
		not _pause_menu_open
		or _settings_open
		or _confirmation_state != ConfirmationState.CLOSED
	):
		return
	_settings_snapshot = _current_preferences()
	_settings_open = true
	_settings_committing = false
	_pause_menu.visible = false
	_refresh_action_enabled()
	Sfx.play("menu_open")
	_settings_state.open(_settings_snapshot)


func _cancel_settings() -> void:
	if (
		not _settings_open
		or _settings_committing
		or _settings_state.transition_state_name() != &"ACTIVE"
	):
		return
	var snapshot := _settings_snapshot.duplicate(true)
	if not _settings_state.close():
		return
	_apply_preference_values(snapshot)
	Sfx.play("menu_close")


func _apply_settings(draft: Dictionary) -> void:
	if not _settings_open or _settings_committing:
		return
	_settings_committing = true
	_settings_state.set_committing(true)
	if not ViewPreferencesType.save_batch(draft, Game.view_preferences_path()):
		_settings_committing = false
		_settings_state.show_save_failure()
		return
	_apply_preference_values(draft)
	Sfx.play("ui_confirm")
	_settings_committing = false
	_settings_state.close()


func _preview_settings(draft: Dictionary) -> void:
	if _settings_open and not _settings_committing:
		_apply_preference_values(draft, false)


func _clear_player_data() -> void:
	if not _settings_open or _settings_committing:
		return
	var result: Dictionary = Game.clear_player_data()
	if bool(result.get(&"accepted", false)):
		Sfx.play("ui_confirm")
		return
	_settings_state.show_player_data_clear_failure()


func _on_settings_close_completed() -> void:
	if not _settings_open:
		return
	_settings_snapshot = {}
	_settings_open = false
	_settings_committing = false
	if (
		_pause_menu_open
		and model != null
		and model.result == BattleModel.Result.RUNNING
	):
		_pause_menu.visible = true
		_pause_menu_settings_button.grab_focus.call_deferred()
	else:
		_dismiss_pause_menu_for_terminal()
		if view != null:
			view.call("set_battle_confirmation_active", false)
	_refresh_action_enabled()


func _current_preferences() -> Dictionary:
	var path := Game.view_preferences_path()
	return {
		&"locale": I18n.locale(),
		&"title_music_enabled": ViewPreferencesType.title_music_enabled(path),
		&"master_volume": ViewPreferencesType.master_volume(path),
		&"master_muted": ViewPreferencesType.master_muted(path),
		&"music_volume": ViewPreferencesType.music_volume(path),
		&"sfx_volume": ViewPreferencesType.sfx_volume(path),
		&"frame_limit": ViewPreferencesType.frame_limit(path),
		&"reduced_motion": ViewPreferencesType.reduced_motion(path),
		&"text_scale": ViewPreferencesType.text_scale(path),
		&"background_downloads_enabled": ViewPreferencesType.background_downloads_enabled(path),
	}


func _apply_preference_values(values: Dictionary, apply_background_policy := true) -> void:
	var locale_id := StringName(values.get(&"locale", I18n.locale()))
	if locale_id != I18n.locale():
		I18n.set_locale(locale_id)
	Engine.max_fps = int(values.get(&"frame_limit", Engine.max_fps))
	var reduced_motion := bool(values.get(
		&"reduced_motion",
		ProjectSettings.get_setting("accessibility/reduced_motion", false),
	))
	ProjectSettings.set_setting("accessibility/reduced_motion", reduced_motion)
	TextScale.set_scale(float(values.get(&"text_scale", TextScale.value())))
	_set_bus_volume(
		MASTER_BUS,
		float(values.get(&"master_volume", 1.0)),
		bool(values.get(&"master_muted", false)),
	)
	_set_bus_volume(MUSIC_BUS, float(values.get(&"music_volume", 1.0)))
	_set_bus_volume(SFX_BUS, float(values.get(&"sfx_volume", 1.0)))
	_settings_state.set_reduced_motion(reduced_motion)
	if apply_background_policy:
		var content_packs := get_node_or_null("/root/ContentPacks")
		if content_packs != null and content_packs.has_method("set_background_downloads_enabled"):
			content_packs.call(
				"set_background_downloads_enabled",
				bool(values.get(&"background_downloads_enabled", true)),
			)
	var music_was_enabled := Music.is_enabled()
	var music_enabled := bool(values.get(&"title_music_enabled", music_was_enabled))
	Music.set_enabled(music_enabled)
	if music_enabled and not music_was_enabled and view != null:
		view.call("resume_battle_music")
	_settings_state.call_deferred("_apply_responsive_layout")


func _set_bus_volume(bus_name: StringName, value: float, force_mute := false) -> void:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index < 0:
		return
	AudioServer.set_bus_mute(bus_index, force_mute or value <= 0.001)
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(maxf(value, 0.001)))


func request_resign_confirmation(return_focus: Control = null) -> bool:
	if (
		_confirmation_state != ConfirmationState.CLOSED
		or (not _interaction_enabled and not _pause_menu_open)
		or model == null
		or view == null
		or model.result != BattleModel.Result.RUNNING
	):
		return false
	_confirmation_scale_snapshot = _current_scale()
	_set_scale(0.0)
	_set_confirmation_state(ConfirmationState.ENTERING)
	view.call("set_battle_confirmation_active", true)
	DialogType.set_status(_confirm_dialog, "", DialogType.StatusLive.OFF)
	Sfx.play("menu_open")
	var focus_target := return_focus if return_focus != null else _resign_button
	if DialogType.show_dialog(_confirm_dialog, focus_target, _on_confirmation_entered):
		return true
	view.call("set_battle_confirmation_active", _pause_menu_open)
	_set_scale(_confirmation_scale_snapshot)
	_set_confirmation_state(ConfirmationState.CLOSED)
	return false


func _on_confirmation_entered() -> void:
	if _confirmation_state == ConfirmationState.ENTERING:
		_set_confirmation_state(ConfirmationState.ACTIVE)


func _on_cancel_resign() -> void:
	cancel_resign_confirmation()


func cancel_resign_confirmation() -> bool:
	if _confirmation_state != ConfirmationState.ACTIVE:
		return false
	_set_confirmation_state(ConfirmationState.EXITING)
	Sfx.play("menu_close")
	return DialogType.hide_dialog(_confirm_dialog, true, _finish_cancel_exit)


func _finish_cancel_exit() -> void:
	if _confirmation_state != ConfirmationState.EXITING:
		return
	_set_scale(_confirmation_scale_snapshot)
	if view != null:
		view.call("set_battle_confirmation_active", _pause_menu_open)
	_set_confirmation_state(ConfirmationState.CLOSED)
	if _pause_menu_open:
		_pause_menu.visible = true
		_pause_menu_settings_button.grab_focus.call_deferred()


func _on_confirm_resign() -> void:
	commit_resign_confirmation()


func commit_resign_confirmation() -> bool:
	if _confirmation_state != ConfirmationState.ACTIVE or model.result != BattleModel.Result.RUNNING:
		return false
	_set_confirmation_state(ConfirmationState.COMMITTING)
	Sfx.play("ui_confirm")
	var withdrawing := _copy(&"ui.battle.withdrawing", "WITHDRAWING…")
	DialogType.set_pending(_confirm_dialog, true, withdrawing)
	DialogType.set_status(_confirm_dialog, withdrawing, DialogType.StatusLive.POLITE)
	_resign_dispatch_count += 1
	var accepted := model.apply_action([&"resign"])
	if accepted or model.result != BattleModel.Result.RUNNING:
		notify_battle_terminal()
		return accepted
	_set_confirmation_state(ConfirmationState.ACTIVE)
	DialogType.set_pending(_confirm_dialog, false)
	DialogType.set_status(
		_confirm_dialog,
		_copy(&"ui.battle.withdraw_rejected", "Withdrawal was not accepted. Return to battle or try again."),
		DialogType.StatusLive.ASSERTIVE,
	)
	var cancel := _confirm_dialog.get(&"cancel") as Button
	if cancel != null:
		cancel.grab_focus.call_deferred()
	return false


func confirmation_state() -> int:
	return _confirmation_state


func confirmation_state_name() -> StringName:
	match _confirmation_state:
		ConfirmationState.ENTERING:
			return &"entering"
		ConfirmationState.ACTIVE:
			return &"active"
		ConfirmationState.COMMITTING:
			return &"committing"
		ConfirmationState.EXITING:
			return &"exiting"
		_:
			return &"closed"


func confirmation_active() -> bool:
	return _confirmation_state != ConfirmationState.CLOSED


func resign_dispatch_count() -> int:
	return _resign_dispatch_count


func notify_battle_terminal() -> bool:
	if _confirmation_state == ConfirmationState.CLOSED:
		return false
	if _confirmation_state == ConfirmationState.EXITING:
		return true
	DialogType.set_pending(_confirm_dialog, false)
	_set_confirmation_state(ConfirmationState.EXITING)
	return DialogType.hide_dialog(_confirm_dialog, false, _finish_terminal_exit)


func _finish_terminal_exit() -> void:
	if _confirmation_state != ConfirmationState.EXITING:
		return
	_dismiss_pause_menu_for_terminal()
	if view != null:
		view.call("set_battle_confirmation_active", false)
	_set_confirmation_state(ConfirmationState.CLOSED)


func _set_confirmation_state(state: int) -> void:
	if _confirmation_state == state:
		return
	_confirmation_state = state
	confirmation_state_changed.emit(confirmation_state_name())
	_refresh_action_enabled()


func _refresh_action_enabled() -> void:
	if model == null:
		return
	var enabled := (
		_interaction_enabled
		and model.result == BattleModel.Result.RUNNING
		and _confirmation_state == ConfirmationState.CLOSED
		and not _pause_menu_open
		and not _settings_open
	)
	if _pause_button != null:
		_pause_button.disabled = not enabled
	if _speed_button != null:
		_speed_button.disabled = not enabled
	if _resign_button != null:
		_resign_button.disabled = not enabled


func _on_locale_changed(_locale_id: StringName) -> void:
	DialogType.set_copy(
		_confirm_dialog,
		_copy(&"ui.battle.withdraw_title", "WITHDRAW FROM OPERATION?"),
		_copy(&"ui.battle.withdraw_body", "Withdrawal immediately seals this attempt as a defeat. Current deployment progress is not preserved."),
		_copy(&"ui.battle.confirm_defeat", "CONFIRM DEFEAT"),
		_copy(&"ui.battle.return", "RETURN TO BATTLE"),
		_copy(&"ui.battle.withdrawing", "WITHDRAWING…"),
	)
	var confirm := _confirm_dialog.get(&"confirm") as Button
	var cancel := _confirm_dialog.get(&"cancel") as Button
	if confirm != null:
		confirm.accessibility_name = _copy(&"ui.battle.confirm_defeat", "CONFIRM DEFEAT")
		confirm.accessibility_description = _copy(
			&"ui.battle.confirm_defeat_description",
			"Withdraw from the operation and record this attempt as a defeat.",
		)
	if cancel != null:
		cancel.accessibility_name = _copy(&"ui.battle.return", "RETURN TO BATTLE")
		cancel.accessibility_description = _copy(
			&"ui.battle.return_description",
			"Close the withdrawal confirmation and resume the prior battle speed.",
		)
	_pause_button.text = _copy(&"ui.battle.resume", "RESUME") if _current_scale() == 0.0 else _copy(&"ui.battle.pause", "PAUSE")
	_apply_speed_shortcut_help()
	_resign_button.text = _copy(&"ui.battle.resign", "RESIGN")
	_refresh_pause_menu_copy()


func _refresh_pause_menu_copy() -> void:
	if _pause_menu_title == null:
		return
	_pause_menu_title.text = _copy(&"ui.battle.paused", "PAUSED").to_upper()
	_pause_menu_body.text = _copy(
		&"ui.battle.pause_menu_body",
		"The operation is suspended. Press Escape to return to battle.",
	)
	_pause_menu_resign_button.text = _copy(&"ui.battle.resign", "RESIGN").to_upper()
	_pause_menu_resign_button.accessibility_name = _pause_menu_resign_button.text
	_pause_menu_resign_button.accessibility_description = _copy(
		&"ui.battle.pause_menu_resign_description",
		"Open the confirmation to resign from this operation.",
	)
	_pause_menu_settings_button.text = _copy(&"ui.title.settings", "SETTINGS").to_upper()
	_pause_menu_settings_button.accessibility_name = _pause_menu_settings_button.text
	_pause_menu_settings_button.accessibility_description = _copy(
		&"ui.battle.pause_menu_settings_description",
		"Open game settings while the operation remains paused.",
	)
	_pause_menu.accessibility_name = _pause_menu_title.text
	_pause_menu.accessibility_description = _pause_menu_body.text


func _apply_speed_shortcut_help() -> void:
	if _speed_button == null:
		return
	var help := _copy(&"ui.battle.speed_shortcuts", "Q: LOWER SPEED  •  E: RAISE SPEED")
	_speed_button.tooltip_text = help
	_speed_button.accessibility_description = help


func _copy(key: StringName, fallback: String) -> String:
	return UiCopyType.text(key, fallback)
