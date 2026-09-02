extends SceneTree

const EXPECTED_TITLE_FONT_SIZE := 59
const EXPECTED_SECTION_FONT_SIZE := 28
const EXPECTED_BODY_FONT_SIZE := 22
const EXPECTED_DETAIL_FONT_SIZE := 19
const EXPECTED_ACTION_FONT_SIZE := 24
const EXPECTED_LOCALE_FONT_SIZE := 33
const EXPECTED_CONTROL_HEIGHT := 64.0

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var settings := load("res://scenes/ui/title_settings.tscn").instantiate() as Control
	root.add_child(settings)
	await process_frame
	await process_frame
	settings.size = Vector2(1280.0, 720.0)
	settings.call("_apply_responsive_layout")
	await process_frame

	_check_font_size(settings, "SettingsTitle", EXPECTED_TITLE_FONT_SIZE)
	for heading_name: String in [
		"LocaleLabel",
		"AudioHeading",
		"GraphicsHeading",
		"NetworkHeading",
		"AccessibilityHeading",
		"PlayerDataHeading",
	]:
		_check_font_size(settings, heading_name, EXPECTED_SECTION_FONT_SIZE)
	for body_name: String in [
		"MasterVolumeLabel",
		"MusicVolumeLabel",
		"SfxVolumeLabel",
		"FrameLimitLabel",
		"TextScaleLabel",
	]:
		_check_font_size(settings, body_name, EXPECTED_BODY_FONT_SIZE)
	for detail_name: String in ["BackgroundDownloadsHint", "PlayerDataHint"]:
		_check_font_size(settings, detail_name, EXPECTED_DETAIL_FONT_SIZE)
	for action_name: String in [
		"SettingsBackButton",
		"MasterMuteButton",
		"MusicButton",
		"FrameLimitOption",
		"MotionButton",
		"BackgroundDownloadsButton",
		"ClearPlayerDataButton",
		"SettingsApplyButton",
	]:
		_check_font_size(settings, action_name, EXPECTED_ACTION_FONT_SIZE)
	_check_font_size(settings, "EnglishLocaleButton", EXPECTED_LOCALE_FONT_SIZE)
	_check_font_size(settings, "ChineseLocaleButton", EXPECTED_LOCALE_FONT_SIZE)
	for control_name: String in [
		"SettingsBackButton",
		"MasterMuteButton",
		"MusicButton",
		"FrameLimitOption",
		"MotionButton",
		"BackgroundDownloadsButton",
		"ClearPlayerDataButton",
		"SettingsApplyButton",
		"EnglishLocaleButton",
		"ChineseLocaleButton",
	]:
		_check_control_height(settings, control_name, EXPECTED_CONTROL_HEIGHT)

	for panel_name: String in [
		"CommandFrame",
		"LanguageAudioSection",
		"GraphicsAccessibilitySection",
	]:
		var panel := settings.find_child(panel_name, true, false) as PanelContainer
		_check(panel != null, "%s is missing" % panel_name)
		if panel != null:
			_check_flat_style(panel.get_theme_stylebox(&"panel"), "%s panel" % panel_name)

	for button_name: String in [
		"SettingsBackButton",
		"MasterMuteButton",
		"MusicButton",
		"MotionButton",
		"BackgroundDownloadsButton",
		"ClearPlayerDataButton",
		"FrameLimitOption",
		"EnglishLocaleButton",
		"ChineseLocaleButton",
	]:
		var button := settings.find_child(button_name, true, false) as BaseButton
		_check(button != null, "%s is missing" % button_name)
		if button == null:
			continue
		for state: StringName in [&"normal", &"hover", &"pressed", &"disabled", &"focus"]:
			_check_flat_style(button.get_theme_stylebox(state), "%s %s" % [button_name, state])

	var locale_row := settings.find_child("LocaleButtons", true, false) as HBoxContainer
	var english_button := settings.find_child("EnglishLocaleButton", true, false) as Button
	var chinese_button := settings.find_child("ChineseLocaleButton", true, false) as Button
	_check(locale_row != null, "LocaleButtons row is missing")
	_check(english_button != null and chinese_button != null, "compact locale buttons are missing")
	_check(settings.find_child("LocaleList", true, false) == null, "legacy full-width LocaleList still exists")
	if english_button != null and chinese_button != null:
		_check(
			english_button.get_parent() == locale_row and chinese_button.get_parent() == locale_row,
			"locale buttons are not kept in one horizontal row",
		)
		_check(
			english_button.custom_minimum_size == Vector2(128.0, 64.0)
			and chinese_button.custom_minimum_size == Vector2(128.0, 64.0),
			"locale buttons are not compact and equally sized",
		)
		_check(
			is_equal_approx(english_button.position.y, chinese_button.position.y),
			"locale buttons are not vertically aligned",
		)
		var locale_selector := settings.find_child("LocaleSelector", true, false) as BoxContainer
		_check(locale_selector != null, "LocaleSelector is missing")
		if locale_selector != null:
			locale_selector.call("set_selected_locale", &"en-US")
			chinese_button.pressed.emit()
			_check(
				StringName(locale_selector.call("selected_locale")) == &"zh-CN",
				"Chinese locale button did not update the draft",
			)
			_check(chinese_button.button_pressed, "Chinese locale button did not show its selected state")
			_check(not english_button.button_pressed, "English locale button remained selected")

	var apply_button := settings.find_child("SettingsApplyButton", true, false) as Button
	_check(apply_button != null, "SettingsApplyButton is missing")
	if apply_button != null:
		for state: StringName in [&"normal", &"hover", &"pressed", &"disabled"]:
			_check(
				apply_button.get_theme_stylebox(state) is StyleBoxTexture,
				"APPLY %s no longer uses its ornate texture" % state,
			)

	settings.queue_free()
	for _frame: int in range(4):
		await process_frame
	_finish()


func _check_font_size(settings: Control, node_name: String, expected: int) -> void:
	var control := settings.find_child(node_name, true, false) as Control
	_check(control != null, "%s is missing" % node_name)
	if control != null:
		_check(
			control.get_theme_font_size(&"font_size") == expected,
			"%s font size is %d instead of %d" % [
				node_name,
				control.get_theme_font_size(&"font_size"),
				expected,
			],
		)


func _check_control_height(settings: Control, node_name: String, expected: float) -> void:
	var control := settings.find_child(node_name, true, false) as Control
	_check(control != null, "%s is missing" % node_name)
	if control != null:
		_check(
			is_equal_approx(control.custom_minimum_size.y, expected),
			"%s height is %.1f instead of %.1f" % [node_name, control.custom_minimum_size.y, expected],
		)


func _check_flat_style(style: StyleBox, context: String) -> void:
	_check(style is StyleBoxFlat, "%s still uses a stylized background" % context)
	if not style is StyleBoxFlat:
		return
	var flat := style as StyleBoxFlat
	_check(flat.bg_color.a < 1.0, "%s fill is not translucent" % context)
	_check(flat.border_width_left > 0, "%s is missing its gold border" % context)
	_check(flat.corner_radius_top_left > 0, "%s is missing rounded corners" % context)
	_check(flat.border_color.r > flat.border_color.b, "%s border is not gold-toned" % context)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("TITLE_SETTINGS_STYLE_TEST_OK")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)
