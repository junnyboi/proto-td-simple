extends SceneTree

const ThemeType := preload("res://scripts/ui/components/aetheria_theme.gd")
const StagingSkinType := preload("res://scripts/ui/components/staging_skin.gd")
const LunarisStyleType := preload("res://scripts/ui/components/lunaris_ops_style.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var theme := ThemeType.new()
	_check_focus(theme.get_stylebox(&"focus", &"Button"), "global Button")
	_check_focus(theme.get_stylebox(&"focus", &"AuiPrimaryButton"), "Aetheria primary")
	_check_focus(theme.get_stylebox(&"focus", &"AuiSecondaryButton"), "Aetheria secondary")
	_check_focus(theme.get_stylebox(&"focus", &"AuiSelectedButton"), "Aetheria selected")
	_check_focus(StagingSkinType.transparent_focus_style(Color.CYAN), "shared staging focus")
	_check_focus(StagingSkinType.golden_focus_tint_style(), "canonical golden focus")
	_check_non_button_focus(theme.get_stylebox(&"focus", &"AuiLocaleList"), "Aetheria locale list")

	var regular := Button.new()
	LunarisStyleType.apply_button(regular, &"quiet")
	_check_focus(regular.get_theme_stylebox(&"focus"), "regular Lunaris button")
	regular.free()

	var compact := Button.new()
	LunarisStyleType.apply_compact_rounded_button(compact, &"secondary")
	_check_focus(compact.get_theme_stylebox(&"focus"), "compact Lunaris button")
	compact.free()

	_finish()


func _check_focus(raw_style: StyleBox, context: String) -> void:
	var style := raw_style as StyleBoxFlat
	_check(style != null, "%s focus style is not inspectable" % context)
	if style == null:
		return
	_check(style.bg_color.a >= 0.08 and style.bg_color.a <= 0.18, "%s focus tint is not slight" % context)
	_check(style.bg_color.r > style.bg_color.b and style.bg_color.g > style.bg_color.b, "%s focus tint is not warm gold" % context)
	for side: int in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		_check(style.get_border_width(side) == 0, "%s focus retained a border" % context)
		_check(is_zero_approx(style.get_expand_margin(side)), "%s focus retained expanded outline geometry" % context)
	_check(style.border_color.a <= 0.01, "%s focus retained a visible border color" % context)


func _check_non_button_focus(raw_style: StyleBox, context: String) -> void:
	var style := raw_style as StyleBoxFlat
	_check(style != null, "%s non-Button focus style is not inspectable" % context)
	if style == null:
		return
	_check(style.bg_color.a <= 0.01, "%s non-Button focus unexpectedly inherited the Button tint" % context)
	for side: int in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		_check(style.get_border_width(side) == 2, "%s non-Button focus border changed" % context)
		_check(is_equal_approx(style.get_expand_margin(side), 3.0), "%s non-Button focus expansion changed" % context)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("BUTTON_FOCUS_STYLE_TEST_OK")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)
