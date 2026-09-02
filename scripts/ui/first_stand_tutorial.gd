class_name FirstStandTutorial
extends Control

signal hold_changed(held: bool)
signal tutorial_finished(skipped: bool)

const UI_COPY := preload("res://scripts/ui/components/ui_copy.gd")
const AETHERIA_THEME := preload("res://scripts/ui/components/aetheria_theme.gd")
const AETHERIA_PANEL := preload("res://scripts/ui/components/aetheria_panel.gd")

const ROUTE_TEXTURE := preload("res://assets/tutorial/tutorial_route_marker.png")
const DEPLOY_TEXTURE := preload("res://assets/tutorial/tutorial_deploy_gesture.png")
const BLOCK_TEXTURE := preload("res://assets/tutorial/tutorial_block_shield.png")

const RECOMMENDED_CELL := Vector2i(3, 2)
const CARD_Z := 92
const GUIDE_Z := 88
const LANDSCAPE_CARD_WIDTH := 960.0
const LANDSCAPE_CARD_HEIGHT := 420.0
const PORTRAIT_CARD_HEIGHT := 620.0
const VIEWPORT_MARGIN := 24.0
const TUTORIAL_TOP_SAFE := 88.0
const DEPLOYMENT_CLEARANCE := 20.0
const ACTION_TARGET_SIZE := Vector2(220.0, 64.0)
const SKIP_ACTION_WIDTH := 440.0
const ACTION_FONT_SIZE := 27
const ACTION_CONTENT_PADDING := 12.0
const CARD_CONTENT_PADDING_HORIZONTAL := 24.0
const CARD_CONTENT_PADDING_VERTICAL := 48.0
const TITLE_FONT_SIZE_LANDSCAPE := 54
const TITLE_FONT_SIZE_PORTRAIT := 36
const BODY_FONT_SIZE_LANDSCAPE := 38
const BODY_FONT_SIZE_PORTRAIT := 27
const LIVE_SECONDS := 6.0

const ROUTE_COLOR := Color(0.36, 0.78, 0.83, 0.26)
const TARGET_COLOR := Color(0.89, 0.70, 0.25, 0.44)

enum Step { ROUTE, DEPLOY, BLOCK, LIVE, DONE }

var model: BattleModel = null
var battle_view: Node2D = null
var deploy_bar: DeployBar = null

var _step: Step = Step.ROUTE
var _holding := false
var _finished := false
var _feedback := ""
var _deployment_id: StringName = &""
var _target_cell := RECOMMENDED_CELL
var _live_serial := 0

var _card: PanelContainer = null
var _step_label: Label = null
var _icon: TextureRect = null
var _title: Label = null
var _body: Label = null
var _feedback_label: Label = null
var _actions: BoxContainer = null
var _primary_button: Button = null
var _skip_button: Button = null
var _focus_ring: PanelContainer = null
var _target_marker: Polygon2D = null
var _route_markers: Array[Polygon2D] = []


func setup(
	battle_model: BattleModel,
	owner_view: Node2D,
	owner_deploy_bar: DeployBar,
) -> void:
	model = battle_model
	battle_view = owner_view
	deploy_bar = owner_deploy_bar
	_deployment_id = deploy_bar.first_deployment_id()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = Vector2.ZERO
	size = get_viewport().get_visible_rect().size
	z_index = CARD_Z
	theme = AETHERIA_THEME.new()
	_build_guides()
	_build_card()
	deploy_bar.placement_started.connect(_on_placement_started)
	deploy_bar.placement_rejected.connect(_on_placement_rejected)
	deploy_bar.deployment_committed.connect(_on_deployment_committed)
	I18n.locale_changed.connect(_on_locale_changed)
	_set_step(Step.ROUTE)
	_set_hold(true)
	relayout()


func current_step_name() -> StringName:
	match _step:
		Step.ROUTE:
			return &"route"
		Step.DEPLOY:
			return &"deploy"
		Step.BLOCK:
			return &"block"
		Step.LIVE:
			return &"live"
		_:
			return &"done"


func is_holding_battle() -> bool:
	return _holding


func relayout() -> void:
	if _card == null or deploy_bar == null:
		return
	size = get_viewport().get_visible_rect().size
	var portrait := size.y > size.x
	var card_width := (
		minf(size.x - VIEWPORT_MARGIN * 2.0, 688.0)
		if portrait
		else minf(size.x - VIEWPORT_MARGIN * 2.0, LANDSCAPE_CARD_WIDTH)
	)
	var desired_height := PORTRAIT_CARD_HEIGHT if portrait else LANDSCAPE_CARD_HEIGHT
	var slot_top := size.y - VIEWPORT_MARGIN
	var slot_rect := deploy_bar.slot_screen_rect(_deployment_id)
	if slot_rect.size.y > 0.0:
		slot_top = slot_rect.position.y
	var available_bottom := maxf(TUTORIAL_TOP_SAFE + 260.0, slot_top - DEPLOYMENT_CLEARANCE)
	var available_height := maxf(260.0, available_bottom - TUTORIAL_TOP_SAFE)
	var card_height := minf(desired_height, available_height)
	_card.custom_minimum_size = Vector2(card_width, card_height)
	_card.reset_size()
	_card.size = Vector2(card_width, maxf(card_height, _card.get_combined_minimum_size().y))
	_card.position = Vector2(
		VIEWPORT_MARGIN,
		TUTORIAL_TOP_SAFE + maxf(0.0, (available_height - _card.size.y) * 0.5),
	)
	_step_label.add_theme_font_size_override("font_size", 27 if portrait else 39)
	_title.add_theme_font_size_override(
		"font_size", TITLE_FONT_SIZE_PORTRAIT if portrait else TITLE_FONT_SIZE_LANDSCAPE,
	)
	_body.add_theme_font_size_override(
		"font_size", BODY_FONT_SIZE_PORTRAIT if portrait else BODY_FONT_SIZE_LANDSCAPE,
	)
	_feedback_label.add_theme_font_size_override("font_size", 24 if portrait else 36)
	_icon.custom_minimum_size = Vector2.ONE * (112.0 if portrait else 192.0)
	_actions.vertical = portrait
	_relayout_guides()


func _process(_delta: float) -> void:
	if _finished or battle_view == null or deploy_bar == null:
		return
	var pulse := 0.72 + sin(float(Time.get_ticks_msec()) / 180.0) * 0.22
	_focus_ring.modulate.a = pulse if _focus_ring.visible else 1.0
	_target_marker.modulate.a = pulse if _target_marker.visible else 1.0
	for marker: Polygon2D in _route_markers:
		marker.modulate.a = pulse if marker.visible else 1.0
	_update_focus_ring()


func _build_guides() -> void:
	for cell: Vector2i in model.stage.path_cells(0):
		var marker := Polygon2D.new()
		marker.name = "Route_%d_%d" % [cell.x, cell.y]
		marker.color = ROUTE_COLOR
		marker.polygon = IsoProjection.face_polygon(battle_view.call("grid_scale"))
		marker.position = battle_view.call("cell_center", cell)
		marker.visible = false
		marker.z_index = GUIDE_Z
		add_child(marker)
		_route_markers.append(marker)
	_target_marker = Polygon2D.new()
	_target_marker.name = "RecommendedCell"
	_target_marker.color = TARGET_COLOR
	_target_marker.polygon = IsoProjection.face_polygon(battle_view.call("grid_scale"))
	_target_marker.visible = false
	_target_marker.z_index = GUIDE_Z + 1
	add_child(_target_marker)
	_focus_ring = AETHERIA_PANEL.new()
	_focus_ring.name = "TutorialFocusRing"
	_focus_ring.apply_role(&"focus_ring")
	_focus_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_focus_ring.visible = false
	_focus_ring.z_index = GUIDE_Z + 2
	add_child(_focus_ring)


func _build_card() -> void:
	_card = AETHERIA_PANEL.new()
	_card.name = "TutorialCard"
	_card.apply_role(&"modal")
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_card.z_index = CARD_Z
	add_child(_card)
	_apply_card_content_padding()
	var column := VBoxContainer.new()
	column.name = "TutorialColumn"
	column.add_theme_constant_override("separation", 20)
	_card.add_child(column)
	_step_label = Label.new()
	_step_label.name = "StepLabel"
	_step_label.theme_type_variation = &"AuiDenseDetailLabel"
	_step_label.add_theme_font_size_override("font_size", 39)
	column.add_child(_step_label)
	var content := HBoxContainer.new()
	content.name = "TutorialContent"
	content.add_theme_constant_override("separation", 28)
	column.add_child(content)
	_icon = TextureRect.new()
	_icon.name = "TutorialArt"
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.custom_minimum_size = Vector2.ONE * 192.0
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(_icon)
	var copy_column := VBoxContainer.new()
	copy_column.name = "CopyColumn"
	copy_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy_column.add_theme_constant_override("separation", 14)
	content.add_child(copy_column)
	_title = Label.new()
	_title.name = "TutorialTitle"
	_title.theme_type_variation = &"AuiDenseHeadingLabel"
	_title.add_theme_font_size_override("font_size", 60)
	copy_column.add_child(_title)
	_body = Label.new()
	_body.name = "TutorialBody"
	_body.theme_type_variation = &"AuiDenseBodyLabel"
	_body.add_theme_font_size_override("font_size", 42)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy_column.add_child(_body)
	_feedback_label = Label.new()
	_feedback_label.name = "TutorialFeedback"
	_feedback_label.theme_type_variation = &"AuiDenseDetailLabel"
	_feedback_label.add_theme_font_size_override("font_size", 36)
	_feedback_label.add_theme_color_override("font_color", Color("f0cf65"))
	_feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy_column.add_child(_feedback_label)
	_actions = BoxContainer.new()
	_actions.name = "TutorialActions"
	_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	_actions.add_theme_constant_override("separation", 24)
	column.add_child(_actions)
	_skip_button = _make_button("SkipTutorial", &"AuiSecondaryButton")
	_skip_button.custom_minimum_size.x = SKIP_ACTION_WIDTH
	_skip_button.pressed.connect(_on_skip_pressed)
	_actions.add_child(_skip_button)
	_apply_action_padding(_skip_button)
	_primary_button = _make_button("TutorialPrimary", &"AuiPrimaryButton")
	_primary_button.pressed.connect(_on_primary_pressed)
	_actions.add_child(_primary_button)
	_apply_action_padding(_primary_button)


func _apply_card_content_padding() -> void:
	var source := _card.get_theme_stylebox(&"panel")
	if source == null:
		return
	var padded := source.duplicate() as StyleBox
	padded.content_margin_left = CARD_CONTENT_PADDING_HORIZONTAL
	padded.content_margin_top = CARD_CONTENT_PADDING_VERTICAL
	padded.content_margin_right = CARD_CONTENT_PADDING_HORIZONTAL
	padded.content_margin_bottom = CARD_CONTENT_PADDING_VERTICAL
	_card.add_theme_stylebox_override(&"panel", padded)


func _make_button(button_name: String, variation: StringName) -> Button:
	var button := Button.new()
	button.name = button_name
	button.theme_type_variation = variation
	button.custom_minimum_size = ACTION_TARGET_SIZE
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", ACTION_FONT_SIZE)
	var primary := variation == &"AuiPrimaryButton"
	var action_ink := Color("07111c") if primary else Color("f5efe1")
	for state: StringName in [
		&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color",
	]:
		button.add_theme_color_override(state, action_ink)
	button.add_theme_color_override(
		&"font_outline_color", Color.TRANSPARENT if primary else Color(0.02, 0.04, 0.08, 0.96),
	)
	button.add_theme_constant_override(&"outline_size", 0 if primary else 3)
	return button


func _apply_action_padding(button: Button) -> void:
	for state: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled"]:
		var source := button.get_theme_stylebox(state)
		if source == null:
			continue
		var padded := source.duplicate() as StyleBox
		padded.content_margin_left = ACTION_CONTENT_PADDING
		padded.content_margin_top = ACTION_CONTENT_PADDING
		padded.content_margin_right = ACTION_CONTENT_PADDING
		padded.content_margin_bottom = ACTION_CONTENT_PADDING
		button.add_theme_stylebox_override(state, padded)


func _set_step(next: Step) -> void:
	_step = next
	_feedback = ""
	match _step:
		Step.ROUTE:
			deploy_bar.set_operator_interaction_enabled(false)
		Step.DEPLOY:
			deploy_bar.set_operator_interaction_enabled(true)
		Step.BLOCK:
			deploy_bar.set_operator_interaction_enabled(false)
		Step.LIVE, Step.DONE:
			deploy_bar.set_operator_interaction_enabled(true)
	_refresh_copy()
	_update_guides()
	call_deferred("relayout")


func _refresh_copy() -> void:
	if _card == null:
		return
	_skip_button.visible = true
	_primary_button.visible = false
	match _step:
		Step.ROUTE:
			_step_label.text = _copy(&"ui.tutorial.route.step", "1 / 3  ROUTE")
			_title.text = _copy(&"ui.tutorial.route.title", "Read the route")
			_body.text = _copy(
				&"ui.tutorial.route.body",
				"Enemies start from the portal and follow the lit path to your base crystal. This mission allows 3 leaks, the 4th leak will end the mission.",
			)
			_icon.texture = ROUTE_TEXTURE
			_primary_button.text = _copy(&"ui.tutorial.route.action", "NEXT")
			_primary_button.visible = true
			_skip_button.text = _copy(&"ui.tutorial.skip", "Skip tutorial")
		Step.DEPLOY:
			_step_label.text = _copy(&"ui.tutorial.deploy.step", "2 / 3  DEPLOY")
			_title.text = _copy(&"ui.tutorial.deploy.title", "Deploy a Recruit")
			_body.text = _copy(
				&"ui.tutorial.deploy.body",
				"DP pays for units. Drag a Recruit card onto any green path tile; the gold marker is a safe starting position.",
			)
			_icon.texture = DEPLOY_TEXTURE
			_skip_button.text = _copy(&"ui.tutorial.skip", "Skip tutorial")
		Step.BLOCK:
			_step_label.text = _copy(&"ui.tutorial.block.step", "3 / 3  BLOCK")
			_title.text = _copy(&"ui.tutorial.block.title", "Hold the line")
			_body.text = _copy(
				&"ui.tutorial.block.body",
				"A Recruit blocks 1 ground enemy and loses HP while fighting. Deploy another when DP refills.",
			)
			_icon.texture = BLOCK_TEXTURE
			_primary_button.text = _copy(&"ui.tutorial.block.action", "Start battle")
			_primary_button.visible = true
			_skip_button.text = _copy(&"ui.tutorial.skip", "Skip tutorial")
		Step.LIVE:
			_step_label.text = _copy(&"ui.tutorial.live.step", "FIELD REMINDER")
			_title.text = _copy(&"ui.tutorial.live.title", "Defend the base")
			_body.text = _copy(
				&"ui.tutorial.live.body",
				"Spend refilling DP, reinforce the route, and stop the 4th leak.",
			)
			_icon.texture = BLOCK_TEXTURE
			_skip_button.text = _copy(&"ui.tutorial.dismiss", "Dismiss")
		_:
			return
	_feedback_label.text = _feedback
	_feedback_label.visible = not _feedback.is_empty()
	_card.reset_size()


func _update_guides() -> void:
	var show_route := _step == Step.ROUTE
	for marker: Polygon2D in _route_markers:
		marker.visible = show_route
	_target_marker.visible = _step == Step.DEPLOY
	_focus_ring.visible = _step == Step.DEPLOY
	_relayout_guides()


func _relayout_guides() -> void:
	if battle_view == null or _target_marker == null:
		return
	var face_polygon: PackedVector2Array = IsoProjection.face_polygon(
		battle_view.call("grid_scale")
	)
	var path: Array[Vector2i] = model.stage.path_cells(0)
	for index: int in mini(path.size(), _route_markers.size()):
		var marker := _route_markers[index]
		marker.polygon = face_polygon
		marker.position = battle_view.call("cell_center", path[index])
	_target_marker.polygon = face_polygon
	_target_marker.position = battle_view.call("cell_center", _target_cell)
	_update_focus_ring()


func _update_focus_ring() -> void:
	if _focus_ring == null or deploy_bar == null:
		return
	if _step != Step.DEPLOY:
		_focus_ring.visible = false
		return
	var rect := Rect2()
	rect = deploy_bar.slot_screen_rect(_deployment_id)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		_focus_ring.visible = false
		return
	_focus_ring.visible = true
	_focus_ring.position = rect.position - Vector2.ONE * 6.0
	_focus_ring.size = rect.size + Vector2.ONE * 12.0


func _on_primary_pressed() -> void:
	Sfx.play("ui_click")
	if _step == Step.ROUTE:
		_set_step(Step.DEPLOY)
	elif _step == Step.BLOCK:
		_begin_live_reminder()


func _on_skip_pressed() -> void:
	Sfx.play("ui_click")
	_finish(_step != Step.LIVE)


func _on_placement_started(_deployment: StringName) -> void:
	if _step != Step.DEPLOY:
		return
	_feedback = _copy(
		&"ui.tutorial.deploy.dragging",
		"Green tiles are valid. Release on the gold marker or any green path tile.",
	)
	_refresh_copy()


func _on_placement_rejected(_deployment: StringName, _cell: Vector2i) -> void:
	if _step != Step.DEPLOY:
		return
	_set_step(Step.DEPLOY)
	_feedback = _copy(
		&"ui.tutorial.deploy.invalid",
		"That cell cannot hold this Recruit. Use a green path tile.",
	)
	_refresh_copy()


func _on_deployment_committed(
	_deployment: StringName,
	cell: Vector2i,
	_facing: int,
) -> void:
	if _step != Step.DEPLOY:
		return
	_target_cell = cell
	_set_step(Step.BLOCK)


func _begin_live_reminder() -> void:
	_set_step(Step.LIVE)
	_set_hold(false)
	_live_serial += 1
	var serial := _live_serial
	_dismiss_after_delay(serial)


func _dismiss_after_delay(serial: int) -> void:
	await get_tree().create_timer(LIVE_SECONDS).timeout
	if serial == _live_serial and _step == Step.LIVE and not _finished:
		_finish(false)


func _finish(skipped: bool) -> void:
	if _finished:
		return
	_finished = true
	_step = Step.DONE
	_live_serial += 1
	deploy_bar.set_operator_interaction_enabled(true)
	for marker: Polygon2D in _route_markers:
		marker.visible = false
	_target_marker.visible = false
	_focus_ring.visible = false
	_card.visible = false
	_set_hold(false)
	tutorial_finished.emit(skipped)
	queue_free()


func _set_hold(held: bool) -> void:
	if _holding == held:
		return
	_holding = held
	hold_changed.emit(held)


func _copy(key: StringName, fallback: String) -> String:
	return UI_COPY.text(key, fallback)


func _on_locale_changed(_locale_id: StringName) -> void:
	_refresh_copy()
	call_deferred("relayout")
