extends SceneTree

const MAP_NAVIGATOR_SCRIPT := preload("res://scripts/view/map_navigator.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures := PackedStringArray()
	var source := load("res://data/stages/s8.tres") as StageDef
	if source == null:
		failures.append("S8 failed to load")
	else:
		_validate_portrait(source, failures)
		_validate_landscape(source, failures)
	_validate_campaign_matrix(failures)
	if failures.is_empty():
		print("MAP_NAVIGATOR_ORIENTATION_SMOKE_OK")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _validate_portrait(source: StageDef, failures: PackedStringArray) -> void:
	var viewport := Vector2(720.0, 1280.0)
	var stage := source.copy_for_viewport(viewport)
	var navigator: RefCounted = MAP_NAVIGATOR_SCRIPT.new()
	navigator.relayout(stage, viewport)
	var fill_scale: float = IsoProjection.visual_height_fill_scale(stage, viewport)
	var expected_scale: float = fill_scale * MAP_NAVIGATOR_SCRIPT.BATTLE_SCALE_MULTIPLIER
	if not is_equal_approx(navigator.scale, expected_scale):
		failures.append("portrait must use the tactical zoom-out scale")
	if navigator.scale >= fill_scale:
		failures.append("portrait did not zoom out below endpoint-aware height fill")
	var visual_height: float = IsoProjection.visual_box(stage).size.y * float(navigator.scale)
	if not is_equal_approx(visual_height, viewport.y * 0.92):
		failures.append("portrait visual envelope does not occupy exactly 92 percent height")
	if not is_equal_approx(navigator.pan.x, navigator.bounds.end.x):
		failures.append("portrait must start on the clockwise-rotated base side")
	if navigator.bounds.size.x <= 0.0:
		failures.append("S8 portrait must expose horizontal overflow for panning")
		return
	if not navigator.pan.is_equal_approx(navigator.default_pan()):
		failures.append("portrait default pan must match its boot framing")
	var edge_press := InputEventScreenTouch.new()
	edge_press.index = 0
	edge_press.position = Vector2(360.0, 640.0)
	edge_press.pressed = true
	navigator.handle_input(edge_press)
	var edge_drag := InputEventScreenDrag.new()
	edge_drag.index = 0
	edge_drag.position = Vector2(520.0, 640.0)
	edge_drag.relative = Vector2(160.0, 0.0)
	if not navigator.handle_input(edge_drag):
		failures.append("portrait edge drag was not consumed")
	if navigator.pan.x <= navigator.bounds.end.x:
		failures.append("portrait edge drag did not rubber-band past the bound")
	if navigator.pan.x > navigator.bounds.end.x + MAP_NAVIGATOR_SCRIPT.OVERSCROLL_LIMIT_PX:
		failures.append("portrait rubber-band exceeded its visual limit")
	var edge_release := InputEventScreenTouch.new()
	edge_release.index = 0
	edge_release.position = edge_drag.position
	edge_release.pressed = false
	navigator.handle_input(edge_release)
	var snap_frames := 0
	while navigator.is_inertia_active() and snap_frames < 300:
		navigator.advance_inertia(1.0 / 60.0)
		snap_frames += 1
	if not is_equal_approx(navigator.pan.x, navigator.bounds.end.x):
		failures.append("portrait rubber-band did not snap to the edge")
	if snap_frames >= 300:
		failures.append("portrait snap-back did not settle in bounded time")
	var press := InputEventScreenTouch.new()
	press.index = 0
	press.position = Vector2(360.0, 640.0)
	press.pressed = true
	navigator.handle_input(press)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = Vector2(240.0, 640.0)
	drag.relative = Vector2(-120.0, 0.0)
	if not navigator.handle_input(drag):
		failures.append("portrait touch drag was not consumed")
	if navigator.pan.x >= navigator.bounds.end.x:
		failures.append("portrait touch drag did not move horizontally")
	var release := InputEventScreenTouch.new()
	release.index = 0
	release.position = drag.position
	release.pressed = false
	if not navigator.handle_input(release):
		failures.append("portrait drag release was not consumed")
	if not navigator.consume_primary_click_suppression():
		failures.append("portrait drag must suppress the deployment click")
	if not navigator.recenter():
		failures.append("recenter must report a changed panned view")
	if not navigator.pan.is_equal_approx(navigator.default_pan()):
		failures.append("recenter must restore the portrait default pan")


func _validate_landscape(source: StageDef, failures: PackedStringArray) -> void:
	var viewport := Vector2(1280.0, 720.0)
	var navigator: RefCounted = MAP_NAVIGATOR_SCRIPT.new()
	var stage := source.copy_for_viewport(viewport)
	navigator.relayout(stage, viewport)
	var expected_scale: float = (
		IsoProjection.visual_height_fill_scale(stage, viewport)
		* MAP_NAVIGATOR_SCRIPT.BATTLE_SCALE_MULTIPLIER
	)
	if not is_equal_approx(navigator.scale, expected_scale):
		failures.append("landscape must use the same tactical zoom-out scale")
	var press := InputEventScreenTouch.new()
	press.index = 0
	press.position = Vector2(640.0, 360.0)
	press.pressed = true
	if navigator.handle_input(press):
		failures.append("landscape primary touch must remain available for deployment")
	if navigator.is_dragging() or navigator.is_inertia_active():
		failures.append("landscape must not enter portrait drag state")


func _validate_campaign_matrix(failures: PackedStringArray) -> void:
	var viewports: Array[Vector2] = [
		Vector2(600.0, 1024.0),
		Vector2(720.0, 1280.0),
		Vector2(1024.0, 600.0),
		Vector2(1280.0, 720.0),
		Vector2(1920.0, 720.0),
	]
	for stage_index: int in range(1, 11):
		var source := load("res://data/stages/s%d.tres" % stage_index) as StageDef
		if source == null:
			failures.append("S%d failed to load in layout matrix" % stage_index)
			continue
		for viewport: Vector2 in viewports:
			_validate_layout(source, viewport, failures)
		_validate_live_portrait_resize(source, failures)


func _validate_layout(
	source: StageDef,
	viewport: Vector2,
	failures: PackedStringArray,
) -> void:
	var stage := source.copy_for_viewport(viewport)
	var navigator: RefCounted = MAP_NAVIGATOR_SCRIPT.new()
	navigator.relayout(stage, viewport)
	var label := "%s@%dx%d" % [source.id, int(viewport.x), int(viewport.y)]
	var expected_scale: float = (
		IsoProjection.visual_height_fill_scale(stage, viewport)
		* MAP_NAVIGATOR_SCRIPT.BATTLE_SCALE_MULTIPLIER
	)
	if not is_equal_approx(navigator.scale, expected_scale):
		failures.append("%s scale left tactical contract" % label)
	var clamped: Vector2 = IsoProjection.clamp_pan(navigator.pan, navigator.bounds)
	if not navigator.pan.is_equal_approx(clamped):
		failures.append("%s boot pan is outside bounds" % label)
	if not navigator.default_pan().is_equal_approx(
		IsoProjection.clamp_pan(navigator.default_pan(), navigator.bounds)
	):
		failures.append("%s default pan is outside bounds" % label)
	var original_pan: Vector2 = navigator.pan
	for axis: int in 2:
		var span: float = navigator.bounds.size[axis]
		if span <= 0.001:
			var locked_rect: Rect2 = navigator.content_screen_rect()
			if (
				locked_rect.position[axis] < -0.51
				or locked_rect.end[axis] > viewport[axis] + 0.51
			):
				failures.append("%s locked axis %d clips content" % [label, axis])
			continue
		var edge_pan: Vector2 = original_pan
		edge_pan[axis] = navigator.bounds.position[axis]
		navigator.pan = edge_pan
		var minimum_rect: Rect2 = navigator.content_screen_rect()
		if absf(minimum_rect.end[axis] - viewport[axis]) > 0.51:
			failures.append("%s minimum pan cannot reach content edge %d" % [label, axis])
		edge_pan[axis] = navigator.bounds.end[axis]
		navigator.pan = edge_pan
		var maximum_rect: Rect2 = navigator.content_screen_rect()
		if absf(maximum_rect.position[axis]) > 0.51:
			failures.append(
				"%s maximum pan cannot reach content edge %d: %f bounds=%s"
				% [label, axis, maximum_rect.position[axis], navigator.bounds]
			)
		navigator.pan = original_pan


func _validate_live_portrait_resize(source: StageDef, failures: PackedStringArray) -> void:
	var first_viewport := Vector2(720.0, 1280.0)
	var first_stage := source.copy_for_viewport(first_viewport)
	var navigator: RefCounted = MAP_NAVIGATOR_SCRIPT.new()
	navigator.relayout(first_stage, first_viewport)
	navigator.pan = navigator.bounds.position + navigator.bounds.size * 0.5
	var resized_viewport := Vector2(600.0, 1024.0)
	var resized_stage := source.copy_for_viewport(resized_viewport)
	navigator.relayout(resized_stage, resized_viewport)
	if not navigator.pan.is_equal_approx(IsoProjection.clamp_pan(navigator.pan, navigator.bounds)):
		failures.append("%s portrait live resize left pan outside bounds" % source.id)
