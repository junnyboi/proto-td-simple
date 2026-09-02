class_name MapNavigator
extends RefCounted

## TD-008 view-only map navigation. Owns height-fill layout, bounded two-axis
## pan state, and pointer/trackpad gesture interpretation; it never reads or
## writes the model.

const WHEEL_STEP_PX := 96.0
## Leave a narrow tactical margin around the endpoint-aware visual envelope.
## This is view-only and preserves exact projection, picking, and pan semantics.
const BATTLE_SCALE_MULTIPLIER := 0.92
const PRIMARY_DRAG_THRESHOLD_PX := 10.0
const OVERSCROLL_LIMIT_PX := 72.0
const OVERSCROLL_DRAG_FACTOR := 0.3
const SNAPBACK_RATE_PER_SECOND := 14.0
const SNAPBACK_STOP_DISTANCE_PX := 0.25
const INERTIA_MAX_SPEED_PX_PER_SECOND := 1800.0
const INERTIA_START_SPEED_PX_PER_SECOND := 90.0
const INERTIA_STOP_SPEED_PX_PER_SECOND := 18.0
const INERTIA_DECELERATION_PX_PER_SECOND_SQUARED := 2600.0
const INERTIA_VELOCITY_BLEND := 0.45
const INERTIA_SAMPLE_MIN_SECONDS := 1.0 / 240.0
const INERTIA_SAMPLE_MAX_SECONDS := 0.08
const INERTIA_RELEASE_MAX_IDLE_USEC := 120_000

var scale := 1.0
var origin := Vector2.ZERO
var pan := Vector2.ZERO
var bounds := Rect2()
var pan_sensitivity := 1.0
var _stage: StageDef = null
var _viewport := Vector2.ZERO
var _safe_rect := Rect2()
var _default_pan := Vector2.ZERO
var _middle_dragging := false
var _primary_pressed := false
var _primary_dragging := false
var _primary_press_position := Vector2.ZERO
var _primary_pointer_position := Vector2.ZERO
var _primary_touch_index := -1
var _suppress_primary_click := false
var _drag_velocity := Vector2.ZERO
var _inertia_velocity := Vector2.ZERO
var _last_drag_sample_usec := 0
var _initialized := false


func relayout(stage: StageDef, viewport: Vector2) -> void:
	cancel_inertia()
	_stage = stage
	_viewport = viewport
	_safe_rect = Rect2(Vector2.ZERO, viewport)
	if _is_portrait():
		var content := _content_box(stage)
		# Portrait stages are rotated clockwise by BattleView. Fill from the exact
		# terrain + endpoint envelope, then unlock each content axis only when its
		# sprite-aware envelope exceeds the viewport on that axis.
		scale = IsoProjection.visual_height_fill_scale(stage, viewport) * BATTLE_SCALE_MULTIPLIER
		origin = IsoProjection.visual_origin_for(stage, viewport, scale)
		bounds = _pan_bounds_for(content, _safe_rect)
		_default_pan = Vector2(bounds.end.x, clampf(0.0, bounds.position.y, bounds.end.y))
		if not _initialized:
			# Clockwise rotation moves the authored right-side base to the left side
			# of the isometric diamond, so boot at the maximum horizontal pan.
			pan = _default_pan
			_initialized = true
		else:
			pan = IsoProjection.clamp_pan(pan, bounds)
		return
	scale = IsoProjection.visual_height_fill_scale(stage, viewport) * BATTLE_SCALE_MULTIPLIER
	origin = IsoProjection.visual_origin_for(stage, viewport, scale)
	bounds = _pan_bounds_for(_content_box(stage), _safe_rect)
	_default_pan = Vector2(bounds.position.x, clampf(0.0, bounds.position.y, bounds.end.y))
	if not _initialized:
		# Landscape-authored stages terminate at the base on the right.
		pan = _default_pan
		pan = IsoProjection.clamp_pan(pan, bounds)
		_initialized = true
	else:
		pan = IsoProjection.clamp_pan(pan, bounds)


func root_position() -> Vector2:
	return origin + pan


func content_screen_rect() -> Rect2:
	var content := _content_box(_stage)
	return Rect2(origin + pan + content.position * scale, content.size * scale)


func is_dragging() -> bool:
	return _middle_dragging or _primary_dragging


func is_inertia_active() -> bool:
	return (
		is_out_of_bounds()
		or
		absf(_inertia_velocity.x) >= INERTIA_STOP_SPEED_PX_PER_SECOND
		or absf(_inertia_velocity.y) >= INERTIA_STOP_SPEED_PX_PER_SECOND
	)


func has_pan_range() -> bool:
	return bounds.size.x > 0.0 or bounds.size.y > 0.0


func is_out_of_bounds() -> bool:
	return not pan.is_equal_approx(IsoProjection.clamp_pan(pan, bounds))


func is_centered() -> bool:
	return pan.distance_to(_default_pan) <= SNAPBACK_STOP_DISTANCE_PX


func default_pan() -> Vector2:
	return _default_pan


func recenter() -> bool:
	cancel_inertia()
	var next_pan := IsoProjection.clamp_pan(_default_pan, bounds)
	var changed := not pan.is_equal_approx(next_pan)
	pan = next_pan
	return changed


func cancel_inertia() -> void:
	_inertia_velocity = Vector2.ZERO
	_drag_velocity = Vector2.ZERO
	_last_drag_sample_usec = 0


func cancel_interaction() -> bool:
	var previous_pan := pan
	cancel_inertia()
	_middle_dragging = false
	_primary_pressed = false
	_primary_dragging = false
	_primary_touch_index = -1
	_suppress_primary_click = false
	pan = IsoProjection.clamp_pan(pan, bounds)
	return not previous_pan.is_equal_approx(pan)


## Advances view-only momentum in render time. Returns true only when the pan
## changed and BattleView needs to re-apply the map transform.
func advance_inertia(delta: float) -> bool:
	if not _is_portrait() or _primary_pressed or _middle_dragging or not is_inertia_active():
		if not _is_portrait():
			cancel_inertia()
		return false
	var frame_delta := maxf(delta, 0.0)
	if is_out_of_bounds():
		return _advance_snapback(frame_delta)
	var previous_pan := pan
	pan = IsoProjection.clamp_pan(pan + _inertia_velocity * frame_delta, bounds)
	var hit_x_edge := (
		(is_equal_approx(pan.x, bounds.position.x) and _inertia_velocity.x < 0.0)
		or (is_equal_approx(pan.x, bounds.end.x) and _inertia_velocity.x > 0.0)
	)
	var hit_y_edge := (
		(is_equal_approx(pan.y, bounds.position.y) and _inertia_velocity.y < 0.0)
		or (is_equal_approx(pan.y, bounds.end.y) and _inertia_velocity.y > 0.0)
	)
	_inertia_velocity.x = (
		0.0
		if hit_x_edge
		else move_toward(
			_inertia_velocity.x,
			0.0,
			INERTIA_DECELERATION_PX_PER_SECOND_SQUARED * frame_delta,
		)
	)
	_inertia_velocity.y = (
		0.0
		if hit_y_edge
		else move_toward(
			_inertia_velocity.y,
			0.0,
			INERTIA_DECELERATION_PX_PER_SECOND_SQUARED * frame_delta,
		)
	)
	if absf(_inertia_velocity.x) < INERTIA_STOP_SPEED_PX_PER_SECOND:
		_inertia_velocity.x = 0.0
	if absf(_inertia_velocity.y) < INERTIA_STOP_SPEED_PX_PER_SECOND:
		_inertia_velocity.y = 0.0
	if not is_inertia_active():
		cancel_inertia()
	return not previous_pan.is_equal_approx(pan)


func _advance_snapback(delta: float) -> bool:
	var target := IsoProjection.clamp_pan(pan, bounds)
	var previous_pan := pan
	var weight := 1.0 - exp(-SNAPBACK_RATE_PER_SECOND * delta)
	pan = pan.lerp(target, clampf(weight, 0.0, 1.0))
	if pan.distance_to(target) <= SNAPBACK_STOP_DISTANCE_PX:
		pan = target
		cancel_inertia()
	return not previous_pan.is_equal_approx(pan)


func consume_primary_click_suppression() -> bool:
	var suppressed := _suppress_primary_click
	_suppress_primary_click = false
	return suppressed


func ensure_local_rect_visible(local_rect: Rect2) -> bool:
	var screen := Rect2(
		origin + pan + local_rect.position * scale,
		local_rect.size * scale,
	)
	var visible_rect := _safe_rect if _safe_rect.has_area() else Rect2(Vector2.ZERO, _viewport)
	var next_pan := pan
	if screen.position.x < visible_rect.position.x:
		next_pan.x += visible_rect.position.x - screen.position.x
	elif screen.end.x > visible_rect.end.x:
		next_pan.x -= screen.end.x - visible_rect.end.x
	if screen.position.y < visible_rect.position.y:
		next_pan.y += visible_rect.position.y - screen.position.y
	elif screen.end.y > visible_rect.end.y:
		next_pan.y -= screen.end.y - visible_rect.end.y
	# Large admitted presentation can extend beyond terrain-owned pan bounds.
	# Expand only toward the exact minimum correction requested by this rect.
	var expanded_min := Vector2(
		minf(bounds.position.x, next_pan.x), minf(bounds.position.y, next_pan.y)
	)
	var expanded_max := Vector2(maxf(bounds.end.x, next_pan.x), maxf(bounds.end.y, next_pan.y))
	bounds = Rect2(expanded_min, expanded_max - expanded_min)
	next_pan = IsoProjection.clamp_pan(next_pan, bounds)
	var changed := not next_pan.is_equal_approx(pan)
	pan = next_pan
	return changed


func _pan_bounds_for(content: Rect2, visible_rect: Rect2) -> Rect2:
	var screen := Rect2(origin + content.position * scale, content.size * scale)
	var min_pan := Vector2.ZERO
	var max_pan := Vector2.ZERO
	if screen.size.x > visible_rect.size.x:
		min_pan.x = visible_rect.end.x - screen.end.x
		max_pan.x = visible_rect.position.x - screen.position.x
	if screen.size.y > visible_rect.size.y:
		min_pan.y = visible_rect.end.y - screen.end.y
		max_pan.y = visible_rect.position.y - screen.position.y
	return Rect2(min_pan, max_pan - min_pan)


func _content_box(stage: StageDef) -> Rect2:
	return IsoProjection.content_box(stage.grid_size())


func _is_portrait() -> bool:
	return _viewport.x < _viewport.y


func recover_missed_release(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_MIDDLE and not button.pressed:
			_middle_dragging = false
		elif button.button_index == MOUSE_BUTTON_LEFT and not button.pressed:
			_finish_primary_drag()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _middle_dragging and motion.button_mask & MOUSE_BUTTON_MASK_MIDDLE == 0:
			_middle_dragging = false
		if _primary_pressed and motion.button_mask & MOUSE_BUTTON_MASK_LEFT == 0:
			_finish_primary_drag()
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if not touch.pressed and touch.index == _primary_touch_index:
			_finish_primary_drag()


## Returns true only for a consumed map-navigation event. BattleView applies
## the resulting transform and marks the viewport event handled.
func handle_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		return _handle_button(event as InputEventMouseButton)
	if event is InputEventScreenTouch:
		return _handle_touch(event as InputEventScreenTouch)
	if event is InputEventScreenDrag:
		return _handle_touch_drag(event as InputEventScreenDrag)
	if event is InputEventMouseMotion and _middle_dragging:
		var motion := event as InputEventMouseMotion
		if motion.button_mask & MOUSE_BUTTON_MASK_MIDDLE == 0:
			_middle_dragging = false
			return false
		pan = IsoProjection.clamp_pan(pan + motion.relative * pan_sensitivity, bounds)
		return true
	if event is InputEventMouseMotion and _primary_pressed:
		return _handle_primary_motion(event as InputEventMouseMotion)
	return false


func _handle_button(event: InputEventMouseButton) -> bool:
	if event.button_index == MOUSE_BUTTON_MIDDLE:
		if event.pressed:
			cancel_inertia()
		_middle_dragging = event.pressed
		return true
	if event.button_index == MOUSE_BUTTON_LEFT:
		return _handle_primary_button(event)
	if not event.pressed:
		return false
	cancel_inertia()
	var delta := Vector2.ZERO
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			delta = (
				Vector2(WHEEL_STEP_PX, 0.0) if event.shift_pressed else Vector2(0.0, WHEEL_STEP_PX)
			)
		MOUSE_BUTTON_WHEEL_DOWN:
			delta = (
				Vector2(-WHEEL_STEP_PX, 0.0)
				if event.shift_pressed
				else Vector2(0.0, -WHEEL_STEP_PX)
			)
		MOUSE_BUTTON_WHEEL_LEFT:
			delta.x = WHEEL_STEP_PX
		MOUSE_BUTTON_WHEEL_RIGHT:
			delta.x = -WHEEL_STEP_PX
		_:
			return false
	pan = IsoProjection.clamp_pan(pan + delta * pan_sensitivity, bounds)
	return true


func _handle_primary_button(event: InputEventMouseButton) -> bool:
	if event.pressed:
		if not _is_portrait() or _primary_touch_index >= 0:
			return false
		cancel_inertia()
		_suppress_primary_click = false
		_primary_pressed = true
		_primary_dragging = false
		_primary_touch_index = -1
		_primary_press_position = event.position
		_primary_pointer_position = event.position
		return false
	var consumed := _primary_dragging or _suppress_primary_click
	_finish_primary_drag()
	return consumed


func _handle_primary_motion(event: InputEventMouseMotion) -> bool:
	if _primary_touch_index >= 0:
		return false
	if event.button_mask & MOUSE_BUTTON_MASK_LEFT == 0:
		_finish_primary_drag()
		return false
	_primary_pointer_position = event.position
	if not _primary_dragging:
		_primary_dragging = (
			_primary_pointer_position.distance_to(_primary_press_position)
			>= PRIMARY_DRAG_THRESHOLD_PX
		)
	if not _primary_dragging:
		return false
	var previous_pan := pan
	pan = _rubber_banded_pan(event.relative * pan_sensitivity)
	_sample_drag_velocity(pan - previous_pan)
	_suppress_primary_click = true
	return true


func _handle_touch(event: InputEventScreenTouch) -> bool:
	if event.pressed:
		if not _is_portrait() or _primary_touch_index >= 0:
			return false
		cancel_inertia()
		_suppress_primary_click = false
		_primary_pressed = true
		_primary_dragging = false
		_primary_touch_index = event.index
		_primary_press_position = event.position
		_primary_pointer_position = event.position
		return false
	if event.index != _primary_touch_index:
		return _primary_touch_index < 0 and _suppress_primary_click
	var consumed := _primary_dragging or _suppress_primary_click
	_finish_primary_drag()
	return consumed


func _handle_touch_drag(event: InputEventScreenDrag) -> bool:
	if not _primary_pressed or event.index != _primary_touch_index:
		return false
	_primary_pointer_position = event.position
	if not _primary_dragging:
		_primary_dragging = (
			_primary_pointer_position.distance_to(_primary_press_position)
			>= PRIMARY_DRAG_THRESHOLD_PX
		)
	if not _primary_dragging:
		return false
	var previous_pan := pan
	pan = _rubber_banded_pan(event.relative * pan_sensitivity)
	_sample_drag_velocity(pan - previous_pan)
	_suppress_primary_click = true
	return true


func _finish_primary_drag() -> void:
	if _primary_dragging:
		_suppress_primary_click = true
		_start_inertia()
	_primary_pressed = false
	_primary_dragging = false
	_primary_touch_index = -1


func _sample_drag_velocity(actual_delta: Vector2) -> void:
	var now := Time.get_ticks_usec()
	var seconds := INERTIA_SAMPLE_MIN_SECONDS
	if _last_drag_sample_usec > 0:
		seconds = clampf(
			float(now - _last_drag_sample_usec) / 1_000_000.0,
			INERTIA_SAMPLE_MIN_SECONDS,
			INERTIA_SAMPLE_MAX_SECONDS,
		)
	var measured := Vector2(
		clampf(
			actual_delta.x / seconds,
			-INERTIA_MAX_SPEED_PX_PER_SECOND,
			INERTIA_MAX_SPEED_PX_PER_SECOND,
		),
		clampf(
			actual_delta.y / seconds,
			-INERTIA_MAX_SPEED_PX_PER_SECOND,
			INERTIA_MAX_SPEED_PX_PER_SECOND,
		),
	)
	_drag_velocity.x = _blend_velocity_component(_drag_velocity.x, measured.x, actual_delta.x)
	_drag_velocity.y = _blend_velocity_component(_drag_velocity.y, measured.y, actual_delta.y)
	_last_drag_sample_usec = now


func _blend_velocity_component(current: float, measured: float, actual_delta: float) -> float:
	if is_zero_approx(actual_delta):
		return 0.0
	if is_zero_approx(current) or signf(measured) != signf(current):
		return measured
	return lerpf(current, measured, INERTIA_VELOCITY_BLEND)


func _start_inertia() -> void:
	if not _is_portrait() or _last_drag_sample_usec <= 0:
		cancel_inertia()
		return
	if Time.get_ticks_usec() - _last_drag_sample_usec > INERTIA_RELEASE_MAX_IDLE_USEC:
		cancel_inertia()
		return
	if is_out_of_bounds():
		_inertia_velocity = Vector2.ZERO
		_drag_velocity = Vector2.ZERO
		_last_drag_sample_usec = 0
		return
	_inertia_velocity = Vector2(
		clampf(
			_drag_velocity.x,
			-INERTIA_MAX_SPEED_PX_PER_SECOND,
			INERTIA_MAX_SPEED_PX_PER_SECOND,
		)
		if absf(_drag_velocity.x) >= INERTIA_START_SPEED_PX_PER_SECOND
		else 0.0,
		clampf(
			_drag_velocity.y,
			-INERTIA_MAX_SPEED_PX_PER_SECOND,
			INERTIA_MAX_SPEED_PX_PER_SECOND,
		)
		if absf(_drag_velocity.y) >= INERTIA_START_SPEED_PX_PER_SECOND
		else 0.0,
	)
	_drag_velocity = Vector2.ZERO
	if not is_inertia_active():
		cancel_inertia()


func _rubber_banded_pan(delta: Vector2) -> Vector2:
	return Vector2(
		_rubber_banded_axis(pan.x, delta.x, bounds.position.x, bounds.end.x),
		_rubber_banded_axis(pan.y, delta.y, bounds.position.y, bounds.end.y),
	)


func _rubber_banded_axis(current: float, delta: float, minimum: float, maximum: float) -> float:
	if maximum <= minimum:
		return minimum
	if current < minimum:
		return (
			minf(current + delta, maximum)
			if delta > 0.0
			else maxf(minimum - OVERSCROLL_LIMIT_PX, current + delta * OVERSCROLL_DRAG_FACTOR)
		)
	if current > maximum:
		return (
			maxf(current + delta, minimum)
			if delta < 0.0
			else minf(maximum + OVERSCROLL_LIMIT_PX, current + delta * OVERSCROLL_DRAG_FACTOR)
		)
	var proposed := current + delta
	if proposed < minimum:
		return maxf(
			minimum - OVERSCROLL_LIMIT_PX,
			minimum + (proposed - minimum) * OVERSCROLL_DRAG_FACTOR,
		)
	if proposed > maximum:
		return minf(
			maximum + OVERSCROLL_LIMIT_PX,
			maximum + (proposed - maximum) * OVERSCROLL_DRAG_FACTOR,
		)
	return proposed
