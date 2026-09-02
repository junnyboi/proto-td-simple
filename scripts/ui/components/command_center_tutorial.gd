class_name CommandCenterTutorial
extends Control

signal finished(skipped: bool, persisted: bool)

const AetheriaButtonType := preload("res://scripts/ui/components/aetheria_button.gd")
const AetheriaPanelType := preload("res://scripts/ui/components/aetheria_panel.gd")
const StagingSkinType := preload("res://scripts/ui/components/staging_skin.gd")
const UiCopyType := preload("res://scripts/ui/components/ui_copy.gd")
const ViewPreferencesType := preload("res://scripts/view/view_preferences.gd")
const GameTypographyType := preload("res://scripts/ui/game_typography.gd")

const GOLD := Color("d8b978")
const BRIGHT_GOLD := Color("f0d89a")
const IVORY := Color("f5efe1")
const MUTED := Color("aebfd0")
const CARD_MAX_WIDTH := 560.0
const CARD_MIN_HEIGHT := 272.0
const VIEWPORT_MARGIN := 24.0
const TARGET_GROW := 9.0
const CARD_Z := 122
const CALLOUT_PADDING_HORIZONTAL := 12
const CALLOUT_PADDING_VERTICAL := 24
const ACTION_PADDING := 12
const ARROW_HEAD_LENGTH := 18.0
const ARROW_HEAD_HALF_WIDTH := 8.0

var _targets: Array[Control] = []
var _steps: Array[Dictionary] = []
var _preferences_path := ViewPreferencesType.DEFAULT_PATH
var _completion_key := StringName(ViewPreferencesType.COMMAND_TUTORIAL_KEY)
var _accessibility_key := &"ui.onboarding.command.a11y"
var _accessibility_fallback := "Command Center tutorial"
var _reduced_motion := false
var _step_index := 0
var _finished := false
var _entry_tween: Tween = null

var _shield: ColorRect = null
var _target_ring: PanelContainer = null
var _connector: Line2D = null
var _arrow_head: Polygon2D = null
var _card: PanelContainer = null
var _step_label: Label = null
var _title: Label = null
var _body: Label = null
var _skip: Button = null
var _primary: Button = null


func setup(
	mission_control: Control,
	preferences_path: String = ViewPreferencesType.DEFAULT_PATH,
	reduced_motion: bool = false,
) -> bool:
	return setup_custom(
		"CommandCenterTutorial",
		[mission_control],
		[
			{
				"id": &"mission_control",
				"step_key": &"ui.onboarding.command.mission.step",
				"step_fallback": "1 / 1  MISSION CONTROL",
				"title_key": &"ui.onboarding.command.mission.title",
				"title_fallback": "Choose an operation",
				"body_key": &"ui.onboarding.command.mission.body",
				"body_fallback": "Mission Control lists every available operation. Select one to begin the mission immediately.",
				"action_key": &"ui.onboarding.command.done",
				"action_fallback": "DONE",
			},
		],
		StringName(ViewPreferencesType.COMMAND_TUTORIAL_KEY),
		&"ui.onboarding.command.a11y",
		"Command Center tutorial",
		preferences_path,
		reduced_motion,
	)


func setup_custom(
	tutorial_name: String,
	targets: Array[Control],
	steps: Array[Dictionary],
	completion_key: StringName,
	accessibility_key: StringName,
	accessibility_fallback: String,
	preferences_path: String = ViewPreferencesType.DEFAULT_PATH,
	reduced_motion: bool = false,
) -> bool:
	if (
		tutorial_name.is_empty()
		or targets.is_empty()
		or targets.size() != steps.size()
		or preferences_path.is_empty()
	):
		return false
	for target: Control in targets:
		if target == null:
			return false
	for step: Dictionary in steps:
		if not _valid_step(step):
			return false
	_targets = targets.duplicate()
	_steps = steps.duplicate(true)
	_completion_key = completion_key
	_accessibility_key = accessibility_key
	_accessibility_fallback = accessibility_fallback
	_preferences_path = preferences_path
	_reduced_motion = reduced_motion
	name = tutorial_name
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = CARD_Z
	accessibility_name = UiCopyType.text(
		_accessibility_key, _accessibility_fallback,
	)
	_build()
	I18n.locale_changed.connect(_on_locale_changed)
	get_viewport().size_changed.connect(relayout)
	_set_step(0)
	return true


func current_step_name() -> StringName:
	return StringName(_current_step().get("id", &""))


func current_target_name() -> StringName:
	var target := _current_target()
	return StringName(target.name) if target != null else &""


func current_target_rect() -> Rect2:
	return _target_ring.get_global_rect() if _target_ring != null else Rect2()


func is_active() -> bool:
	return not _finished and is_visible_in_tree()


func advance() -> void:
	_on_primary_pressed()


func skip() -> void:
	_finish(true)


func _exit_tree() -> void:
	if _entry_tween != null and _entry_tween.is_valid():
		_entry_tween.kill()
	if I18n.locale_changed.is_connected(_on_locale_changed):
		I18n.locale_changed.disconnect(_on_locale_changed)
	if get_viewport() != null and get_viewport().size_changed.is_connected(relayout):
		get_viewport().size_changed.disconnect(relayout)


func _unhandled_input(event: InputEvent) -> void:
	if not _finished and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_finish(true)


func _process(_delta: float) -> void:
	if _finished or _primary == null or not is_visible_in_tree():
		return
	var target := _current_target()
	if target != null:
		if not get_global_rect().grow(1.0).encloses(target.get_global_rect()):
			_ensure_current_target_visible()
		var expected_rect := target.get_global_rect().grow(TARGET_GROW)
		if not _target_ring.get_global_rect().is_equal_approx(expected_rect):
			relayout()
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner == null or not is_ancestor_of(focus_owner):
		_primary.grab_focus.call_deferred()


func _build() -> void:
	_shield = ColorRect.new()
	_shield.name = "TutorialShield"
	_shield.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shield.color = Color(0.0, 0.0, 0.0, 0.52)
	_shield.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_shield)

	_connector = Line2D.new()
	_connector.name = "TutorialConnector"
	_connector.width = 2.0
	_connector.default_color = Color(GOLD, 0.88)
	_connector.antialiased = true
	add_child(_connector)

	_arrow_head = Polygon2D.new()
	_arrow_head.name = "TutorialArrowHead"
	_arrow_head.color = Color(GOLD, 0.94)
	add_child(_arrow_head)

	_target_ring = AetheriaPanelType.new()
	_target_ring.name = "TutorialTargetRing"
	_target_ring.apply_role(&"focus_ring")
	_target_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_target_ring.visible = false
	add_child(_target_ring)

	_card = AetheriaPanelType.new()
	_card.name = "TutorialCallout"
	_card.apply_role(&"modal")
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_card)

	var card_insets := MarginContainer.new()
	card_insets.name = "CalloutInsets"
	card_insets.add_theme_constant_override(&"margin_left", CALLOUT_PADDING_HORIZONTAL)
	card_insets.add_theme_constant_override(&"margin_right", CALLOUT_PADDING_HORIZONTAL)
	card_insets.add_theme_constant_override(&"margin_top", CALLOUT_PADDING_VERTICAL)
	card_insets.add_theme_constant_override(&"margin_bottom", CALLOUT_PADDING_VERTICAL)
	_card.add_child(card_insets)

	var column := VBoxContainer.new()
	column.name = "CalloutColumn"
	column.add_theme_constant_override(&"separation", 12)
	card_insets.add_child(column)

	_step_label = Label.new()
	_step_label.name = "TutorialStep"
	_step_label.theme_type_variation = &"AuiDenseDetailLabel"
	_step_label.add_theme_color_override(&"font_color", GOLD)
	column.add_child(_step_label)

	_title = Label.new()
	_title.name = "TutorialTitle"
	_title.theme_type_variation = &"AuiDenseHeadingLabel"
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_title)

	_body = Label.new()
	_body.name = "TutorialBody"
	_body.theme_type_variation = &"AuiDenseBodyLabel"
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_body)

	var actions := HBoxContainer.new()
	actions.name = "TutorialActions"
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override(&"separation", 12)
	var action_insets := MarginContainer.new()
	action_insets.name = "TutorialActionInsets"
	for margin: StringName in [&"margin_left", &"margin_top", &"margin_right", &"margin_bottom"]:
		action_insets.add_theme_constant_override(margin, ACTION_PADDING)
	action_insets.add_child(actions)
	column.add_child(action_insets)

	_skip = AetheriaButtonType.new()
	_skip.name = "TutorialSkip"
	_skip.apply_role(&"secondary")
	_skip.custom_minimum_size = Vector2(164.0, 56.0)
	_skip.add_theme_stylebox_override(&"focus", StagingSkinType.golden_focus_tint_style())
	_skip.pressed.connect(_on_skip_pressed)
	actions.add_child(_skip)

	_primary = AetheriaButtonType.new()
	_primary.name = "TutorialPrimary"
	_primary.apply_role(&"primary")
	_primary.custom_minimum_size = Vector2(164.0, 56.0)
	_primary.add_theme_stylebox_override(&"focus", StagingSkinType.golden_focus_tint_style())
	_primary.pressed.connect(_on_primary_pressed)
	actions.add_child(_primary)

	_skip.focus_next = _skip.get_path_to(_primary)
	_skip.focus_neighbor_right = _skip.get_path_to(_primary)
	_primary.focus_previous = _primary.get_path_to(_skip)
	_primary.focus_neighbor_left = _primary.get_path_to(_skip)
	_primary.focus_next = _primary.get_path_to(_skip)
	_primary.focus_neighbor_right = _primary.get_path_to(_skip)
	_skip.focus_previous = _skip.get_path_to(_primary)
	_skip.focus_neighbor_left = _skip.get_path_to(_primary)


func _set_step(value: int) -> void:
	if _finished:
		return
	_step_index = clampi(value, 0, _steps.size() - 1)
	_refresh_copy()
	_ensure_current_target_visible.call_deferred()
	relayout.call_deferred()
	_animate_card.call_deferred()
	_primary.grab_focus.call_deferred()


func _refresh_copy() -> void:
	if _step_label == null:
		return
	accessibility_name = UiCopyType.text(
		_accessibility_key, _accessibility_fallback,
	)
	_skip.text = UiCopyType.text(&"ui.onboarding.command.skip", "SKIP")
	var step := _current_step()
	_step_label.text = UiCopyType.text(step["step_key"], step["step_fallback"])
	_title.text = UiCopyType.text(step["title_key"], step["title_fallback"])
	_body.text = UiCopyType.text(step["body_key"], step["body_fallback"])
	_primary.text = UiCopyType.text(step["action_key"], step["action_fallback"])
	_card.reset_size()


func relayout() -> void:
	if _card == null or _current_target() == null:
		return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var target_rect := _current_target().get_global_rect().grow(TARGET_GROW)
	_target_ring.position = target_rect.position
	_target_ring.size = target_rect.size

	var card_width := minf(CARD_MAX_WIDTH, viewport_size.x - VIEWPORT_MARGIN * 2.0)
	var card_height := minf(
		maxf(CARD_MIN_HEIGHT, _card.get_combined_minimum_size().y),
		viewport_size.y - VIEWPORT_MARGIN * 2.0,
	)
	_card.size = Vector2(card_width, card_height)
	_card.pivot_offset = _card.size * 0.5
	var position := (viewport_size - Vector2(card_width, card_height)) * 0.5
	if bool(_current_step().get("avoid_target", false)):
		position.y = (
			VIEWPORT_MARGIN
			if target_rect.get_center().y >= viewport_size.y * 0.5
			else viewport_size.y - card_height - VIEWPORT_MARGIN
		)
	position.x = clampf(position.x, VIEWPORT_MARGIN, viewport_size.x - card_width - VIEWPORT_MARGIN)
	position.y = clampf(position.y, VIEWPORT_MARGIN, viewport_size.y - card_height - VIEWPORT_MARGIN)
	_card.position = position

	var card_rect := _card.get_global_rect()
	var card_center := card_rect.get_center()
	var target_center := target_rect.get_center()
	var card_edge := Vector2(
		clampf(target_center.x, card_rect.position.x, card_rect.end.x),
		clampf(target_center.y, card_rect.position.y, card_rect.end.y),
	)
	if target_rect.has_point(card_edge):
		card_edge = card_center
	var target_edge := Vector2(
		clampf(card_center.x, target_rect.position.x, target_rect.end.x),
		clampf(card_center.y, target_rect.position.y, target_rect.end.y),
	)
	if card_rect.has_point(target_edge):
		target_edge = target_center
	var safe_end := viewport_size - Vector2.ONE * VIEWPORT_MARGIN
	target_edge.x = clampf(target_edge.x, VIEWPORT_MARGIN, safe_end.x)
	target_edge.y = clampf(target_edge.y, VIEWPORT_MARGIN, safe_end.y)
	_connector.points = PackedVector2Array([card_edge, target_edge])
	_layout_arrow_head(card_edge, target_edge)

	var narrow := viewport_size.x <= 560.0
	StagingSkinType.apply_display_type(
		_step_label,
		GameTypographyType.raised_small_text(16 if narrow else 18),
		GOLD,
		560,
	)
	StagingSkinType.apply_display_type(_title, 24 if narrow else 28, IVORY, 600)
	StagingSkinType.apply_body_type(_body, 20 if narrow else 22, MUTED)
	_skip.custom_minimum_size = Vector2(132.0 if narrow else 164.0, 54.0)
	_primary.custom_minimum_size = Vector2(132.0 if narrow else 164.0, 54.0)


func _layout_arrow_head(start: Vector2, tip: Vector2) -> void:
	if _arrow_head == null:
		return
	var direction := start.direction_to(tip)
	if direction.is_zero_approx():
		_arrow_head.visible = false
		return
	var base_center := tip - direction * ARROW_HEAD_LENGTH
	var perpendicular := Vector2(-direction.y, direction.x) * ARROW_HEAD_HALF_WIDTH
	_arrow_head.polygon = PackedVector2Array([
		tip,
		base_center + perpendicular,
		base_center - perpendicular,
	])
	_arrow_head.visible = true


func _animate_card() -> void:
	if _card == null:
		return
	if _entry_tween != null and _entry_tween.is_valid():
		_entry_tween.kill()
	if _reduced_motion:
		_card.modulate = Color.WHITE
		_card.scale = Vector2.ONE
		return
	_card.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_card.scale = Vector2(0.98, 0.98)
	_entry_tween = create_tween().set_parallel(true)
	_entry_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_entry_tween.tween_property(_card, ^"modulate:a", 1.0, 0.18)
	_entry_tween.tween_property(_card, ^"scale", Vector2.ONE, 0.18)


func _current_target() -> Control:
	if _step_index < 0 or _step_index >= _targets.size():
		return null
	return _targets[_step_index]


func _current_step() -> Dictionary:
	if _step_index < 0 or _step_index >= _steps.size():
		return {}
	return _steps[_step_index]


func _ensure_current_target_visible() -> void:
	var target := _current_target()
	if target == null or not target.is_inside_tree():
		return
	var ancestor := target.get_parent()
	while ancestor != null and ancestor != self:
		if ancestor is ScrollContainer:
			(ancestor as ScrollContainer).ensure_control_visible(target)
		ancestor = ancestor.get_parent()
	relayout.call_deferred()


func _valid_step(step: Dictionary) -> bool:
	for key: String in [
		"id", "step_key", "step_fallback", "title_key", "title_fallback",
		"body_key", "body_fallback", "action_key", "action_fallback",
	]:
		if not step.has(key):
			return false
	return not String(step["id"]).is_empty()


func _on_primary_pressed() -> void:
	Sfx.play("ui_click")
	if _step_index + 1 < _steps.size():
		_set_step(_step_index + 1)
	else:
		_finish(false)


func _on_skip_pressed() -> void:
	Sfx.play("ui_click")
	_finish(true)


func _finish(skipped: bool) -> void:
	if _finished:
		return
	_finished = true
	var persisted := ViewPreferencesType.mark_tutorial_seen(
		_completion_key, _preferences_path,
	)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	finished.emit(skipped, persisted)
	queue_free()


func _on_locale_changed(_locale_id: StringName) -> void:
	_refresh_copy()
	relayout.call_deferred()
