extends SceneTree

const COVER_SCRIPT := preload("res://scripts/ui/components/top_aligned_cover.gd")
const LOADING_ART := preload("res://assets/loading/command_backdrop.png")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var cover := COVER_SCRIPT.new()
	cover.texture = LOADING_ART
	root.add_child(cover)
	await process_frame

	var landscape := cover.source_rect_for_target(Vector2(1280.0, 720.0))
	_check(landscape.is_equal_approx(Rect2(0.0, 0.0, 1920.0, 1080.0)), "landscape should use the complete source")

	var portrait := cover.source_rect_for_target(Vector2(720.0, 1280.0))
	_check(is_equal_approx(portrait.position.x, 656.25), "portrait crop should remain horizontally centered")
	_check(is_zero_approx(portrait.position.y), "portrait crop must begin at the source top")
	_check(is_equal_approx(portrait.size.x, 607.5), "portrait crop width is incorrect")
	_check(is_equal_approx(portrait.size.y, 1080.0), "portrait crop must retain full source height")

	var ultrawide := cover.source_rect_for_target(Vector2(1920.0, 720.0))
	_check(is_zero_approx(ultrawide.position.y), "wide crop must remain pinned to the source top")
	_check(is_equal_approx(ultrawide.size.y, 720.0), "wide crop height is incorrect")
	_check(cover.mouse_filter == Control.MOUSE_FILTER_IGNORE, "cover must not intercept input")

	await _verify_loading_layout(Vector2i(3440, 1440), 64, "native ultrawide")
	await _verify_loading_layout(Vector2i(3840, 2160), 76, "4K")
	cover.queue_free()
	for _frame: int in range(4):
		await process_frame
	_finish()


func _verify_loading_layout(viewport_size: Vector2i, minimum_wordmark_size: int, context: String) -> void:
	DisplayServer.window_set_size(viewport_size)
	root.size = viewport_size
	await process_frame
	var loading := load("res://scenes/loading.tscn").instantiate() as Control
	root.add_child(loading)
	await process_frame
	await process_frame
	var artwork := loading.get_node_or_null("CommandArtwork")
	var header := loading.get_node_or_null("Header") as Control
	var footer := loading.get_node_or_null("LoadingPanel") as Control
	var wordmark := loading.get_node_or_null("LoadingPanel/VBoxContainer/Wordmark") as Label
	if wordmark == null:
		wordmark = loading.find_child("Wordmark", true, false) as Label
	var status := loading.find_child("StatusLabel", true, false) as Label
	var detail := loading.find_child("DetailLabel", true, false) as Label
	var progress := loading.find_child("Progress", true, false) as ProgressBar
	_check(artwork != null, "%s loading scene is missing CommandArtwork" % context)
	_check(artwork != null and artwork.get_script() == COVER_SCRIPT, "%s loading scene does not use top-aligned cover" % context)
	_check(artwork != null and artwork.texture == LOADING_ART, "%s loading scene uses the wrong artwork" % context)
	_check(header != null and _contains(loading, header), "%s loading header overflows" % context)
	_check(footer != null and _contains(loading, footer), "%s loading footer overflows" % context)
	_check(wordmark != null and wordmark.get_theme_font_size(&"font_size") >= minimum_wordmark_size, "%s wordmark did not scale for the display" % context)
	_check(status != null and status.get_theme_font_size(&"font_size") >= roundi(float(minimum_wordmark_size) * 0.40), "%s status typography is undersized" % context)
	_check(detail != null and detail.get_theme_font_size(&"font_size") >= roundi(float(minimum_wordmark_size) * 0.34), "%s detail typography is undersized" % context)
	_check(progress != null and progress.custom_minimum_size.y >= (9.0 if viewport_size.x < 3840 else 11.0), "%s progress rail did not scale" % context)
	loading.queue_free()
	await process_frame


func _contains(outer: Control, inner: Control) -> bool:
	if outer == null or inner == null:
		return false
	var outer_rect := outer.get_global_rect().grow(1.0)
	var inner_rect := inner.get_global_rect()
	return outer_rect.has_point(inner_rect.position) and outer_rect.has_point(inner_rect.end - Vector2.ONE)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("LOADING_ART_ALIGNMENT_TEST_OK")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)
