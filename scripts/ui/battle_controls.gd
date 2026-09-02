class_name BattleControls
extends Control

signal confirmation_state_changed(state: StringName)

const GameTypographyType := preload("res://scripts/ui/game_typography.gd")
const Style := preload("res://scripts/ui/components/lunaris_ops_style.gd")
const DialogType := preload("res://scripts/ui/components/lunaris_dialog_sheet.gd")
const UiCopyType := preload("res://scripts/ui/components/ui_copy.gd")

## Pause/resume, speed cycle 1x/2x/4x, Q/E directional stepping, and resign. Every write remains on
## ticks_per_frame_scale or model.apply_action([&"resign"]); presentation never
## enters deterministic state.

const FONT_SIZE := GameTypographyType.DETAIL
const SPEED_CYCLE: Array[float] = [1.0, 2.0, 4.0, 0.0]
const SPEED_STEPS: Array[float] = [0.0, 1.0, 2.0, 4.0]
const PAUSED_LABEL_MIN_WIDTH := 0.0
const COMMAND_TARGET_SIZE := Vector2(112.0, 48.0)
const DECK_PADDING := 24.0
const DECK_VERTICAL_PADDING := DECK_PADDING + 8.0
const ACTION_GAP := 12

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
var _resume_scale: float = 1.0
var _confirmation_scale_snapshot: float = 1.0
var _confirmation_state := ConfirmationState.CLOSED
var _resign_dispatch_count := 0
var _interaction_enabled := true
var _last_paused := false


func setup(battle_model: BattleModel, battle_view: Node2D) -> void:
	model = battle_model
	view = battle_view
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = Vector2.ZERO
	size = get_viewport().get_visible_rect().size
	_build_row()
	_build_confirm()
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


func _make_button(button_name: String, text: String, role: StringName) -> Button:
	var btn := Button.new()
	btn.name = button_name
	btn.text = text
	btn.focus_mode = Control.FOCUS_ALL
	btn.custom_minimum_size = COMMAND_TARGET_SIZE
	Style.apply_compact_rounded_button(btn, role, 6.0, 12)
	btn.add_theme_font_size_override(&"font_size", FONT_SIZE)
	return btn


func _current_scale() -> float:
	return float(view.get("ticks_per_frame_scale"))


func _set_scale(value: float) -> void:
	view.set("ticks_per_frame_scale", value)


func _process(_delta: float) -> void:
	if view == null or model == null:
		return
	if _confirmation_state != ConfirmationState.CLOSED and model.result != BattleModel.Result.RUNNING:
		notify_battle_terminal()
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
		Style.apply_button(_pause_button, &"selected" if paused else &"secondary")
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
	if _confirmation_state != ConfirmationState.CLOSED:
		if event.is_action_pressed("ui_cancel") and _confirmation_state == ConfirmationState.ACTIVE:
			cancel_resign_confirmation()
		# A visible confirmation owns every event that escaped GUI dispatch. This
		# prevents map, tutorial, deployment, pause, and shortcut fallthrough.
		get_viewport().set_input_as_handled()
		return


func _on_pause_pressed() -> void:
	if not _interaction_enabled or _confirmation_state != ConfirmationState.CLOSED or model.result != BattleModel.Result.RUNNING:
		return
	if _current_scale() == 0.0:
		Sfx.play("menu_close")
		_set_scale(_resume_scale)
	else:
		Sfx.play("menu_open")
		_set_scale(0.0)


func _on_speed_pressed() -> void:
	if not _interaction_enabled or _confirmation_state != ConfirmationState.CLOSED or model.result != BattleModel.Result.RUNNING:
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


func request_resign_confirmation() -> bool:
	if (
		_confirmation_state != ConfirmationState.CLOSED
		or not _interaction_enabled
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
	if DialogType.show_dialog(_confirm_dialog, _resign_button, _on_confirmation_entered):
		return true
	view.call("set_battle_confirmation_active", false)
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
		view.call("set_battle_confirmation_active", false)
	_set_confirmation_state(ConfirmationState.CLOSED)


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


func _apply_speed_shortcut_help() -> void:
	if _speed_button == null:
		return
	var help := _copy(&"ui.battle.speed_shortcuts", "Q: LOWER SPEED  •  E: RAISE SPEED")
	_speed_button.tooltip_text = help
	_speed_button.accessibility_description = help


func _copy(key: StringName, fallback: String) -> String:
	return UiCopyType.text(key, fallback)
