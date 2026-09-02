extends SceneTree

const ThemeType := preload("res://scripts/ui/components/aetheria_theme.gd")
const ShellScene := preload("res://scenes/ui/components/aetheria_screen_shell.tscn")
const DialogType := preload("res://scripts/ui/components/lunaris_dialog_sheet.gd")
const LunarisStyleType := preload("res://scripts/ui/components/lunaris_ops_style.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var theme := ThemeType.new()
	var primary_style := theme.get_stylebox(&"normal", &"AuiPrimaryButton") as StyleBoxFlat
	_check(primary_style != null, "Aetheria primary action is not a solid style")
	if primary_style != null:
		_check(primary_style.bg_color.a >= 0.99, "Aetheria primary action is not solid")
		_check(primary_style.content_margin_left >= 12.0 and primary_style.content_margin_top >= 12.0, "Aetheria primary action lacks 12px content padding")
	for variation: StringName in [
		&"AuiReadingPanel", &"AuiHudPanel", &"AuiCardPanel",
		&"AuiModalPanel", &"AuiInspectorPanel", &"AuiRewardPanel",
	]:
		_check_panel_insets(theme.get_stylebox(&"panel", variation), 24.0, String(variation))
	for role: StringName in [
		&"screen", &"dialog", &"hud", &"workspace", &"result",
		&"memorial", &"selected", &"quiet", &"danger",
	]:
		_check_panel_insets(LunarisStyleType.panel_style(role), 24.0, "Lunaris %s" % role)
	var audited_gold := Button.new()
	LunarisStyleType.apply_button(audited_gold, &"gold")
	_check(audited_gold.get_theme_stylebox(&"normal") is StyleBoxFlat, "shared gold action still uses a textured frame")
	_check(audited_gold.get_theme_color(&"font_color").is_equal_approx(Color("040a12")), "shared gold action lacks high-contrast dark ink")
	audited_gold.free()
	_check(theme.get_stylebox(&"panel", &"AuiReadingPanel") is StyleBoxTexture, "reading panel does not use the command-deck frame")
	_check(theme.get_font(&"font", &"AuiTitleLabel") != null, "display typography is missing")

	var shell := ShellScene.instantiate()
	shell.set_anchors_preset(Control.PRESET_TOP_LEFT)
	root.add_child(shell)
	shell.size = Vector2(1280, 720)
	await process_frame
	shell.set_full_safe_area(true)
	shell.relayout(Vector2i(1280, 720))
	await process_frame
	var plate := shell.reading_plate() as Control
	_check(shell.layout_mode() == &"regular_landscape", "landscape mode was not selected")
	_check(plate.custom_minimum_size.x >= 1200.0, "full-safe-area landscape did not occupy the viewport")
	_check(plate.custom_minimum_size.y >= 640.0, "full-safe-area landscape height is too small")

	shell.size = Vector2(720, 1280)
	shell.relayout(Vector2i(720, 1280))
	await process_frame
	_check(shell.layout_mode() == &"portrait", "portrait mode was not selected")
	_check(plate.custom_minimum_size.x >= 680.0, "full-safe-area portrait width is too small")
	_check(plate.custom_minimum_size.y >= 1230.0, "full-safe-area portrait height is too small")

	var locale_selector_scene := load("res://scenes/ui/components/aetheria_locale_selector.tscn") as PackedScene
	var locale_selector := locale_selector_scene.instantiate() as BoxContainer
	locale_selector.call("set_compact_mode", true)
	root.add_child(locale_selector)
	await process_frame
	var locale_buttons: Array[Button] = locale_selector.call("locale_buttons")
	_check(locale_selector.vertical, "locale selector is not permanently vertical")
	_check(locale_buttons.size() == 2, "locale selector did not create two language buttons")
	for locale_button: Button in locale_buttons:
		_check(
			locale_button.custom_minimum_size == Vector2(112.0, 56.0),
			"pre-ready compact locale button sizing was not retained",
		)
	_check(bool(locale_selector.call("select_locale", &"zh-CN")), "default locale selector could not activate Chinese")
	_check(root.get_node("I18n").call("locale") == &"zh-CN", "default locale selector stopped committing its selection")
	_check(bool(locale_selector.call("select_locale", &"en-US")), "default locale selector could not restore English")
	locale_selector.queue_free()
	await process_frame

	var owner := Control.new()
	owner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(owner)
	root.size = Vector2i(540, 960)
	await process_frame
	var return_focus := Button.new()
	return_focus.focus_mode = Control.FOCUS_ALL
	owner.add_child(return_focus)
	var dialog := DialogType.create(owner, "TestDialog", "Confirm operation", "No authoritative state changes until Confirm.", "Confirm", "Cancel")
	var overlay := dialog[&"overlay"] as Control
	var confirm := dialog[&"confirm"] as Button
	var cancel := dialog[&"cancel"] as Button
	var panel := dialog[&"panel"] as PanelContainer
	var placement := dialog[&"placement"] as VBoxContainer
	var actions := dialog[&"actions"] as GridContainer
	_check_panel_insets(panel.get_theme_stylebox(&"panel"), 24.0, "narrow dialog frame")
	_check(overlay != null and not overlay.visible, "dialog should start hidden")
	_check(confirm.custom_minimum_size.y >= 44.0 and cancel.custom_minimum_size.y >= 44.0, "dialog actions are not touch safe")
	_check(panel.custom_minimum_size.x <= 516.0, "narrow dialog exceeds the 540px safe width")
	_check(placement.alignment == BoxContainer.ALIGNMENT_END, "narrow dialog is not bottom attached")
	_check(actions.columns == 1, "narrow dialog actions do not stack")
	_check(cancel.focus_neighbor_top == cancel.get_path_to(confirm), "stacked dialog up does not swap actions")
	_check(cancel.focus_neighbor_left == cancel.get_path_to(cancel), "stacked dialog left should remain on the action")
	_check(confirm.autowrap_mode != TextServer.AUTOWRAP_OFF and cancel.autowrap_mode != TextServer.AUTOWRAP_OFF, "dialog actions do not wrap")
	_check(panel.accessibility_labeled_by_nodes == [panel.get_path_to(dialog[&"title"])], "dialog panel is not labeled by its title")
	_check(panel.accessibility_described_by_nodes.has(panel.get_path_to(dialog[&"body"])), "dialog panel is not described by its body")
	_check(panel.accessibility_described_by_nodes.has(panel.get_path_to(dialog[&"status"])), "dialog panel is not described by its status")
	ProjectSettings.set_setting("accessibility/reduced_motion", false)
	return_focus.grab_focus()
	await process_frame
	_check(DialogType.show_dialog(dialog, return_focus), "dialog did not begin opening")
	_check(DialogType.transition_state_name(dialog) == &"entering", "normal dialog did not expose ENTERING")
	_check(DialogType.ENTRY_SECONDS >= 0.18, "normal dialog entry duration no longer preserves visible motion")
	_check(not cancel.has_focus() and not confirm.has_focus(), "dialog focused an action before entry settled")
	await _wait_for_dialog_state(dialog, &"open")
	_check(overlay.visible and DialogType.transition_state_name(dialog) == &"open", "normal dialog did not settle OPEN before timeout")
	_check(cancel.has_focus(), "Cancel is not the safe default focus after entry")
	_send_action(&"ui_down")
	await process_frame
	_check(confirm.has_focus(), "stacked ui_down did not move to Confirm")
	_send_action(&"ui_left")
	await process_frame
	_check(confirm.has_focus(), "stacked ui_left should keep Confirm focused")
	_send_action(&"ui_up")
	await process_frame
	_check(cancel.has_focus(), "stacked ui_up did not return to Cancel")
	var accepted_count := [0]
	confirm.pressed.connect(func() -> void: accepted_count[0] += 1)
	confirm.grab_focus()
	await _send_button_action(&"ui_accept")
	await process_frame
	_check(accepted_count[0] == 1, "ui_accept did not activate the focused dialog action")
	_check(DialogType.hide_dialog(dialog), "normal dialog did not begin closing")
	_check(DialogType.transition_state_name(dialog) == &"exiting" and overlay.visible, "normal dialog did not remain visible in EXITING")
	_check(confirm.has_focus() and not return_focus.has_focus(), "dialog changed focus before exit completed")
	await _wait_for_dialog_state(dialog, &"closed")
	_check(not overlay.visible and DialogType.transition_state_name(dialog) == &"closed", "normal dialog did not settle CLOSED before timeout")
	_check(return_focus.has_focus(), "normal dialog did not restore focus after exit")
	ProjectSettings.set_setting("accessibility/reduced_motion", true)
	_check(DialogType.show_dialog(dialog, return_focus), "reduced-motion dialog did not open")
	_check(DialogType.transition_state_name(dialog) == &"open" and cancel.has_focus(), "reduced-motion entry did not finalize synchronously")
	_check(DialogType.set_pending(dialog, true), "dialog pending state failed")
	_check(confirm.disabled and cancel.disabled, "pending state did not lock both actions")
	DialogType.set_pending(dialog, false)
	DialogType.hide_dialog(dialog)
	_check(not overlay.visible and DialogType.transition_state_name(dialog) == &"closed", "reduced-motion exit did not finalize synchronously")
	_check(return_focus.has_focus(), "reduced-motion dialog did not restore focus")
	var invalid_return := Button.new()
	owner.add_child(invalid_return)
	_check(DialogType.show_dialog(dialog, invalid_return), "dialog did not reopen for invalid return-focus coverage")
	await process_frame
	invalid_return.queue_free()
	await process_frame
	_check(DialogType.hide_dialog(dialog), "dialog failed to close after return focus was invalidated")
	ProjectSettings.set_setting("accessibility/reduced_motion", false)

	root.size = Vector2i(1280, 720)
	await process_frame
	var full_dialog := DialogType.create(
		owner,
		"FullViewportDialog",
		"Withdraw",
		"This consequence copy remains wrapped inside the body-only scroll region.",
		"Confirm defeat",
		"Return to battle",
		true,
		DialogType.Presentation.FULL_VIEWPORT,
	)
	await process_frame
	var full_overlay := full_dialog[&"overlay"] as Control
	var full_safe := full_dialog[&"safe"] as MarginContainer
	var full_panel := full_dialog[&"panel"] as PanelContainer
	var full_header := full_dialog[&"header"] as Control
	var full_body_scroll := full_dialog[&"body_scroll"] as ScrollContainer
	var full_dock := full_dialog[&"action_dock"] as PanelContainer
	var full_actions := full_dialog[&"actions"] as GridContainer
	var full_cancel := full_dialog[&"cancel"] as Button
	var full_confirm := full_dialog[&"confirm"] as Button
	var full_status := full_dialog[&"status"] as Label
	_check_panel_insets(full_panel.get_theme_stylebox(&"panel"), 24.0, "full dialog frame")
	_check_panel_insets(full_dock.get_theme_stylebox(&"panel"), 24.0, "full dialog action dock")
	_check(full_overlay.mouse_filter == Control.MOUSE_FILTER_STOP, "full dialog root does not stop pointer input")
	_check((full_dialog[&"backdrop"] as ColorRect).color.a >= 0.99, "full dialog background is not opaque")
	_check(full_panel.size_flags_horizontal == Control.SIZE_EXPAND_FILL, "full dialog frame does not fill safe width")
	_check(full_panel.size_flags_vertical == Control.SIZE_EXPAND_FILL, "full dialog frame does not fill safe height")
	_check(full_header.get_parent() == full_body_scroll.get_parent(), "full dialog header is not persistent outside scroll")
	_check(full_dock.get_parent() == full_body_scroll.get_parent(), "full dialog action dock is not persistent outside scroll")
	_check(full_body_scroll.follow_focus, "full dialog body scroll does not follow focus")
	_check(full_actions.columns == 2, "regular full dialog actions are not horizontal")
	_check(full_cancel.focus_neighbor_left == full_cancel.get_path_to(full_confirm), "wide dialog left does not swap actions")
	_check(full_cancel.focus_neighbor_top == full_cancel.get_path_to(full_cancel), "wide dialog up should remain on the action")
	_check(full_cancel.accessibility_name != full_confirm.accessibility_name, "dialog actions do not have distinct accessibility names")
	_check(not full_cancel.accessibility_description.is_empty() and not full_confirm.accessibility_description.is_empty(), "dialog action accessibility descriptions are missing")
	_check(full_status.get_parent().get_parent() == full_dock, "visible status is not in the full action dock")
	_check(DialogType.set_status(full_dialog, "Working", DialogType.StatusLive.POLITE), "dialog status update failed")
	_check(full_status.text == "Working" and full_status.accessibility_live == AccessibilityServer.LIVE_POLITE, "polite dialog status was not exposed")
	_check(full_cancel.custom_minimum_size.y >= 44.0 and full_confirm.custom_minimum_size.y >= 44.0, "full dialog actions are not touch safe")
	_check(full_safe.get_theme_constant(&"margin_left") >= 12, "full dialog safe gutter is missing")
	ProjectSettings.set_setting("accessibility/reduced_motion", true)
	_check(DialogType.show_dialog(full_dialog), "full dialog did not open")
	await process_frame
	_check(full_overlay.get_global_rect().size.is_equal_approx(Vector2(root.size)), "full dialog root does not match viewport")
	_check(DialogType.set_pending(full_dialog, true, "PENDING"), "full dialog pending lock failed")
	_check(DialogType.is_pending(full_dialog) and full_cancel.disabled and full_confirm.disabled, "full dialog pending query/lock drifted")
	DialogType.set_pending(full_dialog, false)
	root.size = Vector2i(540, 960)
	await process_frame
	_check(full_actions.columns == 1, "portrait full dialog actions do not stack")
	_check(full_cancel.focus_neighbor_top == full_cancel.get_path_to(full_confirm), "portrait graph did not rebind to vertical actions")
	_check(full_cancel.focus_neighbor_left == full_cancel.get_path_to(full_cancel), "portrait graph did not self-bind horizontal movement")
	_check(full_cancel.size.x >= full_actions.size.x - 1.0, "portrait safe-first action does not fill the action grid")
	full_confirm.grab_focus()
	root.size = Vector2i(960, 420)
	await process_frame
	_check_panel_insets(full_panel.get_theme_stylebox(&"panel"), 24.0, "short dialog frame")
	_check_panel_insets(full_dock.get_theme_stylebox(&"panel"), 24.0, "short dialog action dock")
	_check(full_actions.columns == 2, "short regular-width full dialog actions should remain horizontal")
	_check(full_confirm.has_focus(), "full dialog lost logical focus across live resize")
	_check(full_header.get_global_rect().end.y <= full_body_scroll.get_global_rect().position.y + 1.0, "short dialog header overlaps scrolling body")
	_check(full_body_scroll.get_global_rect().end.y <= full_dock.get_global_rect().position.y + 1.0, "short dialog body overlaps persistent dock")
	DialogType.hide_dialog(full_dialog, false)
	ProjectSettings.set_setting("accessibility/reduced_motion", false)

	owner.queue_free()
	shell.queue_free()
	_finish()


func _wait_for_dialog_state(dialog: Dictionary, expected: StringName, timeout_seconds := 0.8) -> void:
	var timeout := create_timer(timeout_seconds, true, false, true)
	while DialogType.transition_state_name(dialog) != expected and timeout.time_left > 0.0:
		await process_frame


func _send_action(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)


func _send_button_action(action: StringName) -> void:
	var press := InputEventAction.new()
	press.action = action
	press.pressed = true
	Input.parse_input_event(press)
	await process_frame
	var release := InputEventAction.new()
	release.action = action
	release.pressed = false
	Input.parse_input_event(release)


func _check_panel_insets(style: StyleBox, minimum: float, context: String) -> void:
	_check(style != null and not (style is StyleBoxEmpty), "%s lacks a painted panel style" % context)
	if style == null or style is StyleBoxEmpty:
		return
	_check(
		style.content_margin_left >= minimum
		and style.content_margin_top >= minimum
		and style.content_margin_right >= minimum
		and style.content_margin_bottom >= minimum,
		"%s content padding is below %.0fpx: %.1f/%.1f/%.1f/%.1f" % [
			context, minimum, style.content_margin_left, style.content_margin_top,
			style.content_margin_right, style.content_margin_bottom,
		],
	)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("LUNARIS_UI_FOUNDATION_TEST_OK")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)
