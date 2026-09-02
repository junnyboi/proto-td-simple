class_name AetheriaLocaleSelector
extends BoxContainer

signal locale_selected(locale_id: StringName)

const UiCopyType := preload("res://scripts/ui/components/ui_copy.gd")
const COMPACT_LABEL_MIN_HEIGHT := 0.0
const COMPACT_BUTTON_SIZE := Vector2(112.0, 56.0)
const REGULAR_BUTTON_SIZE := Vector2(128.0, 64.0)
const BUTTON_SEPARATION := 10

var _draft_mode := false
var _selected_locale: StringName = &""
var _compact_mode := false
var _button_group := ButtonGroup.new()
var _locale_buttons: Array[Button] = []

@onready var _label: Label = $LocaleLabel
@onready var _button_row: HBoxContainer = $LocaleButtons


func _ready() -> void:
	vertical = true
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	add_theme_constant_override(&"separation", 8 if _compact_mode else 12)
	_label.clip_text = false
	_label.custom_minimum_size = Vector2(0.0, COMPACT_LABEL_MIN_HEIGHT if _compact_mode else 0.0)
	_button_row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_button_row.add_theme_constant_override(&"separation", BUTTON_SEPARATION)
	_button_group.allow_unpress = false
	_build_locale_buttons()
	refresh()


func set_vertical_layout(_enabled: bool) -> void:
	vertical = true
	if _label != null:
		_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		_label.autowrap_mode = TextServer.AUTOWRAP_OFF


func set_draft_mode(enabled: bool) -> void:
	_draft_mode = enabled
	if _selected_locale.is_empty():
		_selected_locale = I18n.locale()
	refresh()


func set_compact_mode(enabled: bool) -> void:
	_compact_mode = enabled
	if _label != null:
		_label.clip_text = false
		_label.custom_minimum_size = Vector2(0.0, COMPACT_LABEL_MIN_HEIGHT if enabled else 0.0)
	if is_node_ready():
		add_theme_constant_override(&"separation", 8 if enabled else 12)
		_apply_button_metrics()


func set_selected_locale(locale_id: StringName) -> bool:
	if not I18n.supported_locales().has(String(locale_id)):
		return false
	_selected_locale = locale_id
	return refresh()


func selected_locale() -> StringName:
	return _selected_locale if not _selected_locale.is_empty() else I18n.locale()


func locale_buttons() -> Array[Button]:
	return _locale_buttons.duplicate()


func focus_control() -> Button:
	for button: Button in _locale_buttons:
		if StringName(button.get_meta(&"locale_id", &"")) == selected_locale():
			return button
	return _locale_buttons[0] if not _locale_buttons.is_empty() else null


func refresh() -> bool:
	if not is_node_ready():
		return false
	var locales := I18n.supported_locales()
	var active := selected_locale() if _draft_mode else I18n.locale()
	if locales.is_empty() or not locales.has(String(active)):
		return false
	_selected_locale = active
	_label.text = UiCopyType.text(&"ui.locale.label", "Language")
	for button: Button in _locale_buttons:
		var locale_id := StringName(button.get_meta(&"locale_id", &""))
		button.text = _display_name(locale_id)
		button.accessibility_name = button.text
		button.set_pressed_no_signal(locale_id == active)
	return true


func _build_locale_buttons() -> void:
	for child: Node in _button_row.get_children():
		child.free()
	_locale_buttons.clear()
	for locale_text: String in I18n.supported_locales():
		var locale_id := StringName(locale_text)
		var button := Button.new()
		button.name = _button_name(locale_id)
		button.theme_type_variation = &"AuiSecondaryButton"
		button.toggle_mode = true
		button.button_group = _button_group
		button.focus_mode = Control.FOCUS_ALL
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		button.alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		button.set_meta(&"locale_id", locale_id)
		button.pressed.connect(_on_locale_button_pressed.bind(locale_id))
		_button_row.add_child(button)
		_locale_buttons.append(button)
	_apply_button_metrics()


func _apply_button_metrics() -> void:
	var button_size := COMPACT_BUTTON_SIZE if _compact_mode else REGULAR_BUTTON_SIZE
	for button: Button in _locale_buttons:
		button.custom_minimum_size = button_size


func _display_name(locale_id: StringName) -> String:
	if locale_id == &"en-US":
		return UiCopyType.text(&"ui.locale.en_us", "EN")
	if locale_id == &"zh-CN":
		return UiCopyType.text(&"ui.locale.zh_cn", "中文")
	return String(locale_id)


func _button_name(locale_id: StringName) -> String:
	if locale_id == &"en-US":
		return "EnglishLocaleButton"
	if locale_id == &"zh-CN":
		return "ChineseLocaleButton"
	return "LocaleButton%s" % String(locale_id).validate_node_name()


func select_locale(locale_id: StringName) -> bool:
	var previous := selected_locale()
	if _draft_mode:
		if not I18n.supported_locales().has(String(locale_id)):
			return false
		_selected_locale = locale_id
		refresh()
	else:
		if not I18n.set_locale(locale_id):
			return false
		_selected_locale = I18n.locale()
		refresh()
	if locale_id != previous:
		locale_selected.emit(locale_id)
	return true


func _on_locale_button_pressed(locale_id: StringName) -> void:
	select_locale(locale_id)
