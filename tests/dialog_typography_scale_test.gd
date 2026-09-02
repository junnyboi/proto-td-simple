extends SceneTree

const DialogSheet := preload("res://scripts/ui/components/lunaris_dialog_sheet.gd")
const EPSILON := 1.0
const VIEWPORTS := {
	"regular": Vector2i(1280, 720),
	"short": Vector2i(960, 420),
	"phone": Vector2i(360, 800),
}

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for context: String in VIEWPORTS:
		await _verify_sheet(context, VIEWPORTS[context])
	call_deferred("_finish")


func _verify_sheet(context: String, viewport: Vector2i) -> void:
	root.size = viewport
	var owner := Control.new()
	root.add_child(owner)
	owner.position = Vector2.ZERO
	owner.size = viewport
	await process_frame
	var dialog := DialogSheet.create(
		owner,
		"TypographyDialog",
		"CONFIRM COMMAND ALIGNMENT",
		"This readable confirmation message intentionally wraps across several lines without escaping its scroll-safe container.",
		"CONFIRM ALIGNMENT",
		"RETURN TO COMMAND",
	)
	DialogSheet.show_dialog(dialog)
	await process_frame
	await process_frame
	var overlay := dialog[&"overlay"] as Control
	var panel := dialog[&"panel"] as PanelContainer
	var title := dialog[&"title"] as Label
	var body := dialog[&"body"] as Label
	var confirm := dialog[&"confirm"] as Button
	var cancel := dialog[&"cancel"] as Button
	var actions := dialog[&"actions"] as GridContainer
	var sheet_scroll := dialog[&"sheet_scroll"] as ScrollContainer
	_check(title.get_theme_font_size(&"font_size") == 66, "%s dialog title is not 1.5×" % context)
	_check(body.get_theme_font_size(&"font_size") == 54, "%s dialog body is not 1.5×" % context)
	_check(confirm.get_theme_font_size(&"font_size") == 54 and cancel.get_theme_font_size(&"font_size") == 54, "%s dialog actions are not 1.5×" % context)
	_check(title.autowrap_mode != TextServer.AUTOWRAP_OFF and body.autowrap_mode != TextServer.AUTOWRAP_OFF, "%s dialog copy does not wrap" % context)
	_check(confirm.autowrap_mode != TextServer.AUTOWRAP_OFF and cancel.autowrap_mode != TextServer.AUTOWRAP_OFF, "%s dialog actions do not wrap" % context)
	_check(not confirm.clip_text and not cancel.clip_text, "%s dialog actions clip copy" % context)
	_check(_inside(overlay, panel), "%s dialog panel overflows viewport" % context)
	_check(sheet_scroll != null and sheet_scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO, "%s dialog does not expose its enlarged content through scrolling" % context)
	_check(confirm.custom_minimum_size.y >= 72.0 and cancel.custom_minimum_size.y >= 72.0, "%s dialog action containers are undersized" % context)
	_check(actions.columns == (1 if viewport.x <= 620 else 2), "%s dialog action composition is wrong" % context)
	owner.queue_free()
	for _frame: int in range(4):
		await process_frame


func _inside(parent: Control, child: Control) -> bool:
	var outer := parent.get_global_rect()
	var inner := child.get_global_rect()
	return (
		inner.position.x >= outer.position.x - EPSILON
		and inner.position.y >= outer.position.y - EPSILON
		and inner.end.x <= outer.end.x + EPSILON
		and inner.end.y <= outer.end.y + EPSILON
	)


func _finish() -> void:
	if _failures.is_empty():
		print("DIALOG_TYPOGRAPHY_SCALE_TEST_OK")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
