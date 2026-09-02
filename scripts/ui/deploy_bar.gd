class_name DeployBar
extends Control

const UI_COPY := preload("res://scripts/ui/components/ui_copy.gd")

signal placement_started(deployment_id: StringName)
signal placement_rejected(deployment_id: StringName, cell: Vector2i)
signal deployment_committed(deployment_id: StringName, cell: Vector2i, facing: int)

## Raw-input adapter for the deploy/retreat/place_trap/mend verbs (architecture
## rule 3: a thin adapter over apply_action, validated once per verb by
## deploy_flow.gd / trap_flow.gd).
## highlights -> release on a cell -> deploy verb fires with the canonical NW
## facing. Trap slots share the drag and place on release under AMBER
## highlights, distinct from the ui_cancel/right-click cancels. Clicking an
## alive unit selects it and opens
## an explicit action panel whose Skill and Recall buttons remain visible in
## every SP state. Enabled state of every slot reads model.is_deployable /
## model.is_trap_placeable (single source of truth); highlight queries read
## model.can_deploy_at / model.can_place_trap_at (the verb's own validation,
## never a copy).

const HealingRulesScript := preload("res://sim/healing_rules.gd")
const SELECTION_RING_SCRIPT := preload("res://scripts/view/selection_ring.gd")
const OPERATOR_VISUAL_CATALOG_SCRIPT := preload(
	"res://data/presentation/operator_visual_catalog.gd"
)
const GameTypographyType := preload("res://scripts/ui/game_typography.gd")
const Style := preload("res://scripts/ui/components/lunaris_ops_style.gd")

const FONT_SIZE := GameTypographyType.DETAIL
const BAR_HEIGHT := 124.0
const SAFE_MARGIN := 16.0
const DECK_PADDING := 24.0
const DECK_VERTICAL_PADDING := DECK_PADDING + 8.0
const SLOT_GAP := 12.0
const SLOT_TARGET_WIDTH := 288.0
const SLOT_TARGET_HEIGHT := 76.0
const OPERATOR_SLOT_CONTENT_PADDING := 6.0
const LANDSCAPE_DECK_MAX_WIDTH := 1360.0
const SHORT_LANDSCAPE_DECK_MAX_WIDTH := 1240.0
const FIRST_SLOT_CONTENT_INSET := 12.0
const VALID_COLOR := Color(0.2, 0.9, 0.4, 0.4)
const INVALID_COLOR := Color(0.9, 0.2, 0.2, 0.5)
const TRAP_VALID_COLOR := Color(0.95, 0.71, 0.2, 0.45)
const HEAL_VALID_COLOR := Color(0.65, 0.94, 0.44, 0.5)
const DEFAULT_OPERATOR_FACING := UnitState.Facing.LEFT
const OPERATOR_ACTION_PANEL_WIDTH := 600.0
const OPERATOR_ACTION_PANEL_NARROW_BREAKPOINT := 640.0
const OPERATOR_ACTION_PANEL_MARGIN := 16.0
const OPERATOR_ACTION_PANEL_UNIT_GAP := 88.0
const OPERATOR_ACTION_PANEL_DECK_GAP := 12.0
const OPERATOR_ACTION_SKILL_WIDTH := 360.0
const OPERATOR_ACTION_RECALL_WIDTH := 180.0
const OPERATOR_ACTION_BUTTON_HEIGHT := 64.0
const OPERATOR_ACTION_Z := 30

var model: BattleModel = null
var view: Node2D = null

var _slots: Dictionary = {}
var _trap_slots: Dictionary = {}
var _op_defs: Dictionary = {}
var _trap_defs: Dictionary = {}
var _ticket_rows: Dictionary = {}
var _slot_cooldown_seconds: Dictionary = {}
var _slot_deck: PanelContainer = null
var _slot_scroll: ScrollContainer = null
var _slot_box: GridContainer = null
var _placement_op: StringName = &""
var _placement_trap: StringName = &""
var _pointer := Vector2.ZERO
var _highlight_root: Control = null
var _cursor_rect: Polygon2D = null
var _operator_action_panel: PanelContainer = null
var _operator_action_name: Label = null
var _operator_action_state: Label = null
var _operator_action_progress: ProgressBar = null
var _operator_action_detail: Label = null
var _operator_action_buttons: GridContainer = null
var _skill_action_button: Button = null
var _recall_action_button: Button = null
var _operator_action_signature := ""
var _heal_source_unit_id: int = -1
var _heal_cursor: Polygon2D = null
var _selected_unit_id: int = -1
var _selection_ring: Node2D = null
var _operator_interaction_enabled := true
var _interaction_enabled := true


## Call after add_child: the bar sizes itself from the viewport (a Control
## under a Node2D parent gets no anchor-based layout).
func setup(
	battle_model: BattleModel,
	battle_view: Node2D,
	op_defs: Dictionary,
	trap_defs: Dictionary = {},
) -> void:
	model = battle_model
	view = battle_view
	_op_defs = op_defs
	_trap_defs = trap_defs
	var ticket: Dictionary = battle_model.snapshot().get("ticket", {})
	for row: Dictionary in ticket.get("squad", []):
		_ticket_rows[StringName(row["battle_id"])] = row.duplicate(true)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = Vector2.ZERO
	size = get_viewport().get_visible_rect().size
	_build_slots(_op_defs)
	_build_overlays()
	if not I18n.locale_changed.is_connected(_on_locale_changed):
		I18n.locale_changed.connect(_on_locale_changed)


func is_mend_targeting() -> bool:
	return _heal_source_unit_id >= 0


func set_operator_interaction_enabled(enabled: bool) -> void:
	_operator_interaction_enabled = enabled
	if not enabled:
		cancel_transient_intent()


func operator_interaction_enabled() -> bool:
	return _operator_interaction_enabled


func set_interaction_enabled(enabled: bool) -> void:
	_interaction_enabled = enabled
	if not enabled:
		cancel_transient_intent()


func interaction_enabled() -> bool:
	return _interaction_enabled


func transient_intent_active() -> bool:
	return (
		_placement_op != &""
		or _placement_trap != &""
		or _heal_source_unit_id >= 0
		or _selected_unit_id >= 0
	)


func cancel_transient_intent() -> void:
	if _placement_op != &"" or _placement_trap != &"":
		_cancel_placement()
	_cancel_heal_targeting()
	_select_unit(-1)


func first_deployment_id() -> StringName:
	var ids := _deployment_ids()
	return ids[0] if not ids.is_empty() else &""


func slot_screen_rect(deployment_id: StringName) -> Rect2:
	var slot := _slots.get(deployment_id) as Button
	return slot.get_global_rect() if slot != null else Rect2()


func command_deck_rect() -> Rect2:
	return _slot_deck.get_global_rect() if _slot_deck != null else Rect2()


## Dynamic canvas fit: CALLED BY battle_view._relayout() after the grid
## scale recomputes (P14 — a self-owned size_changed listener raced the
## view's recompute and re-derived footprints from the STALE scale).
## Mid-placement overlays re-derive from the live grid scale.
func relayout() -> void:
	size = get_viewport().get_visible_rect().size
	if _slot_box != null:
		_layout_slot_box()
	if _cursor_rect != null:
		_cursor_rect.polygon = IsoProjection.face_polygon(view.call("grid_scale"))
		if _cursor_rect.visible:
			_update_placement_hover()
	if _heal_cursor != null:
		_heal_cursor.polygon = IsoProjection.face_polygon(view.call("grid_scale"))
		if _heal_cursor.visible:
			_update_heal_hover()
	if _placement_op != &"" or _placement_trap != &"":
		for child: Node in _highlight_root.get_children():
			child.queue_free()
		_show_valid_highlights()
	if _heal_source_unit_id >= 0:
		_show_heal_highlights()
	_update_selection_ring()
	_layout_operator_action_panel()


func _process(_delta: float) -> void:
	if model == null:
		return
	# changes so granted operators get slots
	if _slots.size() != _deployment_ids().size():
		_rebuild_slots()
	_update_selection_ring()
	for op_id: StringName in _slots:
		var slot: Button = _slots[op_id]
		_refresh_operator_slot(op_id, slot)
		slot.disabled = not _interaction_enabled or not _operator_interaction_enabled or not model.is_deployable(op_id)
	for trap_id: StringName in _trap_slots:
		var slot: Button = _trap_slots[trap_id]
		slot.disabled = not _interaction_enabled or not _operator_interaction_enabled or not model.is_trap_placeable(trap_id)
	_refresh_operator_actions()
	_layout_operator_action_panel()


func _input(event: InputEvent) -> void:
	if not _interaction_enabled:
		return
	if event.is_action_pressed("ui_cancel"):
		if _heal_source_unit_id >= 0:
			_cancel_heal_targeting()
			_refresh_operator_actions(true)
		elif _placement_op != &"" or _placement_trap != &"":
			_cancel_placement()
		elif _selected_unit_id >= 0:
			_select_unit(-1)
		return
	if event is InputEventMouseButton:
		var cancel_button := event as InputEventMouseButton
		if cancel_button.button_index == MOUSE_BUTTON_RIGHT and not cancel_button.pressed:
			if _heal_source_unit_id >= 0:
				_cancel_heal_targeting()
				_refresh_operator_actions(true)
			elif _placement_op != &"" or _placement_trap != &"":
				_cancel_placement()
			elif _selected_unit_id >= 0:
				_select_unit(-1)
			return
	if _heal_source_unit_id >= 0:
		if event is InputEventMouseMotion:
			_pointer = (event as InputEventMouseMotion).position
			_update_heal_hover()
		return
	# Placement drag: track the pointer from motion events (injected motion
	# never moves get_mouse_position) and end placement on left release.
	if _placement_op == &"" and _placement_trap == &"":
		return
	if event is InputEventMouseMotion:
		_pointer = (event as InputEventMouseMotion).position
		_update_placement_hover()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_pointer = mb.position
			_end_placement_drag()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and not mb.pressed:
			_cancel_placement()


func _unhandled_input(event: InputEvent) -> void:
	if not _interaction_enabled:
		return
	# Idle-state grid clicks select an alive unit and expose explicit actions.
	if (
		_placement_op != &""
		or _placement_trap != &""
		or model == null
		or not _operator_interaction_enabled
	):
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			if bool(view.call("consume_map_primary_click_suppression")):
				return
			_handle_grid_click(mb.position)


func _rebuild_slots() -> void:
	if _slot_deck != null:
		_slot_deck.queue_free()
	_slot_deck = null
	_slot_scroll = null
	_slot_box = null
	_slots.clear()
	_slot_cooldown_seconds.clear()
	_trap_slots.clear()
	_build_slots(_op_defs)


func _build_slots(op_defs: Dictionary) -> void:
	var deck := PanelContainer.new()
	deck.name = "DeploymentCommandDeck"
	deck.mouse_filter = Control.MOUSE_FILTER_PASS
	var deck_style := Style.panel_style(&"hud").duplicate() as StyleBox
	deck_style.content_margin_left = DECK_PADDING
	deck_style.content_margin_top = DECK_VERTICAL_PADDING
	deck_style.content_margin_right = DECK_PADDING
	deck_style.content_margin_bottom = DECK_VERTICAL_PADDING
	deck.add_theme_stylebox_override(&"panel", deck_style)
	add_child(deck)
	_slot_deck = deck
	var scroll := ScrollContainer.new()
	scroll.name = "DeploymentRosterScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	deck.add_child(scroll)
	_slot_scroll = scroll
	var center := CenterContainer.new()
	center.name = "DeploymentRosterCenter"
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var box := GridContainer.new()
	box.name = "SlotBox"
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_theme_constant_override("h_separation", SLOT_GAP)
	box.add_theme_constant_override("v_separation", SLOT_GAP)
	center.add_child(box)
	_slot_box = box
	for deployment_id: StringName in _deployment_ids():
		var row: Dictionary = _ticket_rows.get(deployment_id, {})
		var op_id := StringName(row.get("operator_def_id", deployment_id))
		if not op_defs.has(op_id):
			continue
		var def: OperatorDef = op_defs[op_id]
		var slot := Button.new()
		slot.name = "Slot_%s" % deployment_id
		var dp_cost := def.dp_cost
		var identity_suffix := ""
		if not row.is_empty():
			dp_cost = int(row["combat_spec"]["dp_cost"])
			identity_suffix = " %d" % (int(row["slot_index"]) + 1)
		slot.text = _operator_card_text(def, identity_suffix, dp_cost)
		slot.custom_minimum_size = Vector2(SLOT_TARGET_WIDTH, SLOT_TARGET_HEIGHT)
		slot.icon = _operator_slot_icon(deployment_id, def, row)
		slot.expand_icon = true
		slot.add_theme_constant_override(&"icon_max_width", 52)
		Style.apply_compact_rounded_button(
			slot, &"secondary", OPERATOR_SLOT_CONTENT_PADDING, 12,
		)
		slot.add_theme_color_override(&"icon_disabled_color", Color(1.0, 1.0, 1.0, 0.76))
		slot.add_theme_font_size_override(&"font_size", FONT_SIZE)
		if _slots.is_empty():
			_add_first_slot_content_inset(slot)
		slot.tooltip_text = slot.text.replace("\n", " — ")
		slot.focus_mode = Control.FOCUS_ALL
		slot.focus_entered.connect(_reveal_slot.bind(slot))
		slot.button_down.connect(_start_placement.bind(deployment_id))
		box.add_child(slot)
		_slots[deployment_id] = slot
		_slot_cooldown_seconds[deployment_id] = -1
	# String-copy sort (P14): StringName sort is interning-ordered — slot
	# order would vary across launches
	var trap_names: Array = []
	for key: StringName in _trap_defs:
		trap_names.append(String(key))
	trap_names.sort()
	for trap_name: String in trap_names:
		var trap_id := StringName(trap_name)
		var def: TrapDef = _trap_defs[trap_id]
		var slot := Button.new()
		slot.name = "Slot_%s" % trap_id
		slot.text = _trap_card_text(def)
		slot.custom_minimum_size = Vector2(SLOT_TARGET_WIDTH, SLOT_TARGET_HEIGHT)
		slot.icon = Art.texture(
			&"trap_tar" if def.trigger == TrapDef.Trigger.CELL_AURA else &"trap_spike_armed"
		)
		slot.expand_icon = true
		slot.add_theme_constant_override(&"icon_max_width", 52)
		Style.apply_compact_rounded_button(slot, &"gold", 12.0, 12)
		slot.add_theme_font_size_override(&"font_size", FONT_SIZE)
		slot.tooltip_text = slot.text.replace("\n", " — ")
		slot.focus_mode = Control.FOCUS_ALL
		slot.focus_entered.connect(_reveal_slot.bind(slot))
		slot.button_down.connect(_start_trap_placement.bind(trap_id))
		box.add_child(slot)
		_trap_slots[trap_id] = slot
	_layout_slot_box()


static func _operator_slot_icon(
	deployment_id: StringName,
	definition: OperatorDef,
	row: Dictionary,
) -> Texture2D:
	var art_id := operator_slot_art_id(deployment_id, definition, row)
	var texture := Art.texture(art_id, 0) if not art_id.is_empty() else null
	if texture != null:
		return texture
	var fallback_id := definition.sprite_id
	if not row.is_empty():
		fallback_id = StringName(row["visual_spec"]["sprite_id"])
	return Art.texture(fallback_id, 0)


## Deployment cards use the same identity-aware idle family as battlefield
## operators. The fixed roster has no persistent identity, so its card previews
## the first unit it can deploy (unit id 0).
static func operator_slot_art_id(
	deployment_id: StringName,
	definition: OperatorDef,
	row: Dictionary,
) -> StringName:
	var operator_id := definition.id if row.is_empty() else StringName(row["operator_def_id"])
	if operator_id.is_empty():
		operator_id = deployment_id
	var portrait_asset_id := &""
	var hero_id := &""
	var class_id := &""
	var unit_id := 0
	if not row.is_empty():
		portrait_asset_id = StringName(row["visual_spec"]["portrait_asset_id"])
		hero_id = StringName(row["hero_id"])
		class_id = StringName(row["class_id"])
		unit_id = int(row["slot_index"])
	return OPERATOR_VISUAL_CATALOG_SCRIPT.first_idle_art_id_for_unit(
		operator_id,
		portrait_asset_id,
		hero_id,
		unit_id,
		class_id,
	)


func _deployment_ids() -> Array[StringName]:
	if not model.battle_squad.is_empty():
		return model.battle_squad.duplicate()
	return model.squad.duplicate()


func _layout_slot_box() -> void:
	if _slot_box == null or _slot_deck == null or _slot_scroll == null:
		return
	var short_landscape := size.x > size.y and size.y < 480.0
	var deck_width := (
		minf(size.x - SAFE_MARGIN * 2.0, SHORT_LANDSCAPE_DECK_MAX_WIDTH)
		if short_landscape
		else size.x - SAFE_MARGIN * 2.0
		if size.y > size.x
		else minf(size.x - SAFE_MARGIN * 2.0, LANDSCAPE_DECK_MAX_WIDTH)
	)
	deck_width = maxf(deck_width, 328.0)
	var inner_width := maxf(SLOT_TARGET_WIDTH, deck_width - DECK_PADDING * 2.0)
	_slot_box.columns = clampi(
		floori((inner_width + SLOT_GAP) / (SLOT_TARGET_WIDTH + SLOT_GAP)), 1, 4,
	)
	for child: Node in _slot_box.get_children():
		(child as Control).custom_minimum_size.x = SLOT_TARGET_WIDTH
	_slot_box.reset_size()
	var content_height := (
		_slot_box.get_combined_minimum_size().y + DECK_VERTICAL_PADDING * 2.0
	)
	# The global 1.5× type scale increases each two-line slot's rendered
	# minimum height. Standard landscape must expose both rows without relying
	# on clipping; short landscape retains local scrolling by design.
	var height_ratio := 0.46 if short_landscape else 0.56
	var deck_height := minf(content_height, maxf(BAR_HEIGHT, size.y * height_ratio))
	_slot_deck.position = Vector2(SAFE_MARGIN, size.y - deck_height - SAFE_MARGIN)
	_slot_deck.size = Vector2(deck_width, deck_height)


func _add_first_slot_content_inset(slot: Button) -> void:
	for state: StringName in [&"normal", &"hover", &"pressed", &"disabled"]:
		var style := slot.get_theme_stylebox(state)
		if style == null:
			continue
		var inset_style := style.duplicate() as StyleBox
		inset_style.content_margin_left += FIRST_SLOT_CONTENT_INSET
		slot.add_theme_stylebox_override(state, inset_style)


func _reveal_slot(slot: Control) -> void:
	if _slot_scroll != null and slot != null:
		_slot_scroll.ensure_control_visible(slot)


func _build_overlays() -> void:
	_highlight_root = Control.new()
	_highlight_root.name = "Highlights"
	_highlight_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_highlight_root)
	_cursor_rect = _make_overlay_rect(INVALID_COLOR)
	_cursor_rect.name = "CursorRect"
	add_child(_cursor_rect)
	_heal_cursor = _make_overlay_rect(HEAL_VALID_COLOR)
	_heal_cursor.name = "HealTargetCursor"
	add_child(_heal_cursor)
	_build_operator_action_panel()
	_selection_ring = SELECTION_RING_SCRIPT.new()
	_selection_ring.name = "SelectionRing"
	_selection_ring.visible = false
	_selection_ring.z_index = -1
	add_child(_selection_ring)


func _build_operator_action_panel() -> void:
	_operator_action_panel = PanelContainer.new()
	_operator_action_panel.name = "OperatorActionPanel"
	_operator_action_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_operator_action_panel.z_index = OPERATOR_ACTION_Z
	_operator_action_panel.visible = false
	Style.apply_panel(_operator_action_panel, &"selected")
	var panel_style := _operator_action_panel.get_theme_stylebox(&"panel").duplicate() as StyleBox
	panel_style.content_margin_left = 16.0
	panel_style.content_margin_top = 14.0
	panel_style.content_margin_right = 16.0
	panel_style.content_margin_bottom = 16.0
	_operator_action_panel.add_theme_stylebox_override(&"panel", panel_style)
	add_child(_operator_action_panel)

	var content := VBoxContainer.new()
	content.name = "OperatorActionContent"
	content.add_theme_constant_override(&"separation", 10)
	_operator_action_panel.add_child(content)

	var header := HBoxContainer.new()
	header.name = "OperatorActionHeader"
	header.add_theme_constant_override(&"separation", 12)
	content.add_child(header)
	_operator_action_name = Label.new()
	_operator_action_name.name = "OperatorActionName"
	_operator_action_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_operator_action_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	Style.apply_label(_operator_action_name, &"heading")
	header.add_child(_operator_action_name)
	_operator_action_state = Label.new()
	_operator_action_state.name = "OperatorActionState"
	_operator_action_state.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_operator_action_state.accessibility_live = AccessibilityServer.LIVE_POLITE
	Style.apply_label(_operator_action_state, &"eyebrow")
	header.add_child(_operator_action_state)

	_operator_action_detail = Label.new()
	_operator_action_detail.name = "OperatorActionDetail"
	_operator_action_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	Style.apply_label(_operator_action_detail, &"detail")
	content.add_child(_operator_action_detail)

	_operator_action_progress = ProgressBar.new()
	_operator_action_progress.name = "OperatorSkillProgress"
	_operator_action_progress.custom_minimum_size.y = 8.0
	_operator_action_progress.show_percentage = false
	_operator_action_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Style.apply_progress(_operator_action_progress)
	content.add_child(_operator_action_progress)

	_operator_action_buttons = GridContainer.new()
	_operator_action_buttons.name = "OperatorActionButtons"
	_operator_action_buttons.columns = 2
	_operator_action_buttons.add_theme_constant_override(&"h_separation", 12)
	_operator_action_buttons.add_theme_constant_override(&"v_separation", 10)
	content.add_child(_operator_action_buttons)

	_skill_action_button = Button.new()
	_skill_action_button.name = "ActivateOperatorSkill"
	_skill_action_button.custom_minimum_size = Vector2(
		OPERATOR_ACTION_SKILL_WIDTH, OPERATOR_ACTION_BUTTON_HEIGHT,
	)
	_skill_action_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skill_action_button.focus_mode = Control.FOCUS_ALL
	_skill_action_button.pressed.connect(_on_skill_action_pressed)
	_operator_action_buttons.add_child(_skill_action_button)

	_recall_action_button = Button.new()
	_recall_action_button.name = "RecallOperator"
	_recall_action_button.custom_minimum_size = Vector2(
		OPERATOR_ACTION_RECALL_WIDTH, OPERATOR_ACTION_BUTTON_HEIGHT,
	)
	_recall_action_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_recall_action_button.focus_mode = Control.FOCUS_ALL
	Style.apply_button(_recall_action_button, &"danger")
	_recall_action_button.pressed.connect(_confirm_retreat)
	_operator_action_buttons.add_child(_recall_action_button)
	_configure_operator_action_focus()
	_operator_action_panel.accessibility_labeled_by_nodes = [
		_operator_action_panel.get_path_to(_operator_action_name),
	]
	_operator_action_panel.accessibility_described_by_nodes = [
		_operator_action_panel.get_path_to(_operator_action_detail),
		_operator_action_panel.get_path_to(_operator_action_state),
	]


func _on_locale_changed(_locale_id: StringName) -> void:
	for deployment_id: StringName in _slots:
		var slot := _slots[deployment_id] as Button
		_slot_cooldown_seconds[deployment_id] = -1
		_refresh_operator_slot(deployment_id, slot)
	for trap_id: StringName in _trap_slots:
		var definition := _trap_defs.get(trap_id) as TrapDef
		var slot := _trap_slots[trap_id] as Button
		if definition == null or slot == null:
			continue
		slot.text = _trap_card_text(definition)
		slot.tooltip_text = slot.text.replace("\n", " — ")
	_operator_action_signature = ""
	_refresh_operator_actions(true)
func _operator_card_text(definition: OperatorDef, identity_suffix: String, cost: int) -> String:
	return UI_COPY.format_text(
		&"ui.battle.deploy_operator_card",
		"{name}{slot}\n{cost} DP",
		{&"name": UI_COPY.operator_name(definition), &"slot": identity_suffix, &"cost": cost},
	)


func _operator_cooldown_card_text(
	definition: OperatorDef,
	identity_suffix: String,
	seconds: int,
) -> String:
	return UI_COPY.format_text(
		&"ui.battle.deploy_operator_cooldown",
		"{name}{slot}\nCOOLDOWN {seconds}s",
		{
			&"name": UI_COPY.operator_name(definition),
			&"slot": identity_suffix,
			&"seconds": seconds,
		},
	)


func _refresh_operator_slot(deployment_id: StringName, slot: Button) -> void:
	if slot == null or model == null:
		return
	var seconds := model.redeploy_cooldown_seconds_remaining(deployment_id)
	if int(_slot_cooldown_seconds.get(deployment_id, -1)) == seconds:
		return
	_slot_cooldown_seconds[deployment_id] = seconds
	var row: Dictionary = _ticket_rows.get(deployment_id, {})
	var operator_id := StringName(row.get("operator_def_id", deployment_id))
	var definition := _op_defs.get(operator_id) as OperatorDef
	if definition == null:
		return
	var dp_cost := definition.dp_cost
	var identity_suffix := ""
	if not row.is_empty():
		dp_cost = int(row["combat_spec"]["dp_cost"])
		identity_suffix = " %d" % (int(row["slot_index"]) + 1)
	slot.text = (
		_operator_cooldown_card_text(definition, identity_suffix, seconds)
		if seconds > 0
		else _operator_card_text(definition, identity_suffix, dp_cost)
	)
	slot.tooltip_text = slot.text.replace("\n", " — ")
	slot.accessibility_description = slot.tooltip_text


func _trap_card_text(definition: TrapDef) -> String:
	return UI_COPY.format_text(
		&"ui.battle.deploy_trap_card",
		"{name}\n{cost} DP",
		{&"name": UI_COPY.trap_name(definition), &"cost": definition.dp_cost},
	)


## Footprints are origin-centered face diamonds (P12.2) sized by the live
## grid scale (dynamic canvas fit); position them at cell_center directly.
func _make_overlay_rect(color: Color) -> Polygon2D:
	var poly := Polygon2D.new()
	poly.color = color
	poly.polygon = IsoProjection.face_polygon(view.call("grid_scale"))
	poly.visible = false
	return poly


func _start_placement(op_id: StringName) -> void:
	if not _interaction_enabled or not _operator_interaction_enabled:
		return
	_cancel_heal_targeting()
	_select_unit(-1)
	_placement_op = op_id
	Sfx.play("operator_select")
	_show_valid_highlights()
	view.call("deploy_drag_started")
	placement_started.emit(op_id)


func _start_trap_placement(trap_id: StringName) -> void:
	if not _interaction_enabled or not _operator_interaction_enabled:
		return
	_cancel_heal_targeting()
	_select_unit(-1)
	_placement_trap = trap_id
	_show_valid_highlights()
	view.call("deploy_drag_started")


## One highlight pass for both placement modes; the query is the verb's own
## validation (can_deploy_at / can_place_trap_at), never a copy.
func _show_valid_highlights() -> void:
	var grid_size: Vector2i = model.stage.grid_size()
	for y: int in grid_size.y:
		for x: int in grid_size.x:
			var cell := Vector2i(x, y)
			if _placement_valid_at(cell):
				var rect := _make_overlay_rect(_valid_color())
				rect.visible = true
				rect.position = view.call("cell_center", cell)
				_highlight_root.add_child(rect)


func _placement_valid_at(cell: Vector2i) -> bool:
	if _placement_trap != &"":
		return model.can_place_trap_at(_placement_trap, cell)
	return model.can_deploy_at(_placement_op, cell)


func _valid_color() -> Color:
	return TRAP_VALID_COLOR if _placement_trap != &"" else VALID_COLOR


func _update_placement_hover() -> void:
	var cell: Vector2i = view.call("cell_at", _pointer)
	_cursor_rect.color = _valid_color() if _placement_valid_at(cell) else INVALID_COLOR
	_cursor_rect.position = view.call("cell_center", cell)
	_cursor_rect.visible = true


func _end_placement_drag() -> void:
	var cell: Vector2i = view.call("cell_at", _pointer)
	if not _placement_valid_at(cell):
		Sfx.play("action_reject")
		if _placement_op != &"":
			placement_rejected.emit(_placement_op, cell)
		_cancel_placement()
		return
	if _placement_trap != &"":
		# Traps place directly on release.
		if not model.apply_action([&"place_trap", _placement_trap, cell]):
			Sfx.play("action_reject")
		_cancel_placement()
		return
	var deployment_id := _placement_op
	if model.apply_action([&"deploy", deployment_id, cell, int(DEFAULT_OPERATOR_FACING)]):
		Sfx.play("placement_ready")
		deployment_committed.emit(deployment_id, cell, int(DEFAULT_OPERATOR_FACING))
	else:
		Sfx.play("action_reject")
		placement_rejected.emit(deployment_id, cell)
	_cancel_placement()


func _cancel_placement() -> void:
	view.call("deploy_drag_ended")
	_placement_op = &""
	_placement_trap = &""
	_cursor_rect.visible = false
	for child: Node in _highlight_root.get_children():
		child.queue_free()


func _handle_grid_click(screen_pos: Vector2) -> void:
	var cell: Vector2i = view.call("cell_at", screen_pos)
	var unit: UnitState = model.alive_unit_at(cell)
	if _heal_source_unit_id >= 0:
		if unit == null or not HealingRulesScript.is_valid(model, _heal_source_unit_id, unit.id):
			return
		if model.apply_action([&"mend", _heal_source_unit_id, unit.id]):
			_cancel_heal_targeting()
			_select_unit(-1)
		return
	if unit == null:
		_select_unit(-1)
		return
	_select_unit(unit.id)


func _on_skill_action_pressed() -> void:
	if not _interaction_enabled or not _operator_interaction_enabled:
		return
	if _heal_source_unit_id >= 0:
		_cancel_heal_targeting()
		_refresh_operator_actions(true)
		return
	var unit := model.unit_by_id(_selected_unit_id) if model != null else null
	if unit == null or not unit.alive or not unit.is_skill_ready():
		_refresh_operator_actions(true)
		return
	if unit.skill_effect == SkillDef.Effect.HEAL_TARGET:
		_begin_heal_targeting(unit)
		_refresh_operator_actions(true)
		return
	if model.apply_action([&"trigger_skill", unit.id]):
		_select_unit(-1)
	else:
		_refresh_operator_actions(true)


func _confirm_retreat() -> void:
	if not _interaction_enabled or not _operator_interaction_enabled:
		return
	if _selected_unit_id >= 0 and model.apply_action([&"retreat", _selected_unit_id]):
		_select_unit(-1)
	else:
		_refresh_operator_actions(true)


func _select_unit(unit_id: int) -> void:
	if _selected_unit_id == unit_id:
		if unit_id >= 0:
			_show_operator_actions()
		return
	if _heal_source_unit_id >= 0:
		_cancel_heal_targeting()
	_selected_unit_id = unit_id
	if view != null and view.has_method("operator_selection_changed"):
		view.call("operator_selection_changed", unit_id >= 0)
	if unit_id >= 0:
		_show_operator_actions()
	else:
		_hide_operator_actions()
	_update_selection_ring()


func _update_selection_ring() -> void:
	if _selection_ring == null or model == null or view == null:
		return
	if _selected_unit_id < 0:
		_selection_ring.visible = false
		return
	var unit := model.unit_by_id(_selected_unit_id)
	if unit == null or not unit.alive:
		_select_unit(-1)
		return
	_selection_ring.position = view.call("cell_center", unit.cell)
	_selection_ring.scale = Vector2.ONE * float(view.call("grid_scale"))
	_selection_ring.visible = true


func _show_operator_actions() -> void:
	if _operator_action_panel == null or _selected_unit_id < 0:
		return
	_operator_action_panel.visible = true
	_operator_action_signature = ""
	_refresh_operator_actions(true)
	_layout_operator_action_panel()
	_focus_operator_actions.call_deferred()


func _hide_operator_actions() -> void:
	_operator_action_signature = ""
	if _operator_action_panel != null:
		_operator_action_panel.visible = false
	if _skill_action_button != null:
		_skill_action_button.release_focus()
	if _recall_action_button != null:
		_recall_action_button.release_focus()


func _focus_operator_actions() -> void:
	if _operator_action_panel == null or not _operator_action_panel.visible:
		return
	if _skill_action_button != null and not _skill_action_button.disabled:
		_skill_action_button.grab_focus()
	elif _recall_action_button != null and not _recall_action_button.disabled:
		_recall_action_button.grab_focus()


func _refresh_operator_actions(force: bool = false) -> void:
	if (
		_operator_action_panel == null
		or not _operator_action_panel.visible
		or model == null
		or _selected_unit_id < 0
	):
		return
	var unit := model.unit_by_id(_selected_unit_id)
	if unit == null or not unit.alive:
		_select_unit(-1)
		return
	var targeting := _heal_source_unit_id == unit.id
	var signature := "%d:%d:%d:%s:%s" % [
		unit.id, unit.sp, unit.sp_cost, str(targeting), String(I18n.locale()),
	]
	if not force and signature == _operator_action_signature:
		return
	_operator_action_signature = signature
	var definition := _op_defs.get(unit.op_id) as OperatorDef
	var operator_name := (
		UI_COPY.operator_name(definition)
		if definition != null
		else String(unit.op_id).replace("_", " ").capitalize()
	)
	var has_skill := unit.sp_cost > 0 and not unit.skill_id.is_empty()
	var skill_name := (
		UI_COPY.skill_name(unit.skill_id)
		if has_skill
		else UI_COPY.text(&"ui.battle.skill_none", "NO ACTIVE SKILL")
	)
	_set_label_text(_operator_action_name, operator_name.to_upper())
	_operator_action_progress.max_value = maxf(1.0, float(unit.sp_cost))
	_operator_action_progress.value = float(unit.sp)
	_recall_action_button.text = UI_COPY.text(&"ui.battle.recall", "RECALL")
	_recall_action_button.accessibility_name = _recall_action_button.text
	_recall_action_button.accessibility_description = UI_COPY.format_text(
		&"ui.battle.recall_description",
		"Recall {operator} and begin their redeployment cooldown.",
		{&"operator": operator_name},
	)
	_recall_action_button.tooltip_text = _recall_action_button.accessibility_description
	_recall_action_button.disabled = targeting
	if targeting:
		_set_label_text(
			_operator_action_state,
			UI_COPY.text(&"ui.battle.skill_state_targeting", "SELECT TARGET"),
		)
		_set_label_text(
			_operator_action_detail,
			UI_COPY.text(
				&"ui.battle.skill_targeting_instruction",
				"Select a wounded ally in range. Right-click or press Escape to cancel.",
			),
		)
		_skill_action_button.text = UI_COPY.text(
			&"ui.battle.skill_cancel_targeting", "CANCEL TARGETING",
		)
		_skill_action_button.disabled = false
		_skill_action_button.accessibility_name = _skill_action_button.text
		_skill_action_button.accessibility_description = UI_COPY.format_text(
			&"ui.battle.skill_targeting_description",
			"Choose a wounded ally in range for {skill}.",
			{&"skill": skill_name},
		)
		Style.apply_button(_skill_action_button, &"selected")
	elif not has_skill:
		_set_label_text(
			_operator_action_state,
			UI_COPY.text(&"ui.battle.skill_state_none", "NO SKILL"),
		)
		_set_label_text(_operator_action_detail, skill_name)
		_skill_action_button.text = skill_name
		_skill_action_button.disabled = true
		_skill_action_button.accessibility_name = skill_name
		_skill_action_button.accessibility_description = skill_name
		Style.apply_button(_skill_action_button, &"disabled")
	elif unit.is_skill_ready():
		_set_label_text(
			_operator_action_state,
			UI_COPY.text(&"ui.battle.skill_state_ready", "SKILL READY"),
		)
		_set_label_text(
			_operator_action_detail,
			UI_COPY.format_text(
				&"ui.battle.skill_progress",
				"{skill}  //  SP {current} / {cost}",
				{&"skill": skill_name, &"current": unit.sp, &"cost": unit.sp_cost},
			),
		)
		_skill_action_button.text = UI_COPY.format_text(
			&"ui.battle.skill_activate",
			"ACTIVATE — {skill}",
			{&"skill": skill_name},
		)
		_skill_action_button.disabled = false
		_skill_action_button.accessibility_name = _skill_action_button.text
		_skill_action_button.accessibility_description = UI_COPY.format_text(
			&"ui.battle.skill_activate_description",
			"Activate {skill}.",
			{&"skill": skill_name},
		)
		Style.apply_button(_skill_action_button, &"gold")
	else:
		_set_label_text(
			_operator_action_state,
			UI_COPY.text(&"ui.battle.skill_state_charging", "CHARGING"),
		)
		_set_label_text(
			_operator_action_detail,
			UI_COPY.format_text(
				&"ui.battle.skill_progress",
				"{skill}  //  SP {current} / {cost}",
				{&"skill": skill_name, &"current": unit.sp, &"cost": unit.sp_cost},
			),
		)
		_skill_action_button.text = UI_COPY.format_text(
			&"ui.battle.skill_charging",
			"CHARGING {current} / {cost}",
			{&"current": unit.sp, &"cost": unit.sp_cost},
		)
		_skill_action_button.disabled = true
		_skill_action_button.accessibility_name = _skill_action_button.text
		_skill_action_button.accessibility_description = UI_COPY.format_text(
			&"ui.battle.skill_charging_description",
			"{skill} is charging: {current} of {cost} SP.",
			{&"skill": skill_name, &"current": unit.sp, &"cost": unit.sp_cost},
		)
		Style.apply_button(_skill_action_button, &"disabled")
	_skill_action_button.tooltip_text = _skill_action_button.accessibility_description
	_operator_action_panel.accessibility_name = UI_COPY.text(
		&"ui.battle.operator_actions", "Operator actions",
	)
	_operator_action_panel.accessibility_description = UI_COPY.format_text(
		&"ui.battle.operator_actions_description",
		"{operator}. {skill}. {current} of {cost} SP.",
		{
			&"operator": operator_name,
			&"skill": skill_name,
			&"current": unit.sp,
			&"cost": unit.sp_cost,
		},
	)
	_configure_operator_action_focus()


func _set_label_text(label: Label, value: String) -> void:
	if label != null and label.text != value:
		label.text = value


func _configure_operator_action_focus() -> void:
	if _skill_action_button == null or _recall_action_button == null:
		return
	var stacked := _operator_action_buttons != null and _operator_action_buttons.columns == 1
	_skill_action_button.focus_neighbor_left = _skill_action_button.get_path_to(
		_skill_action_button,
	)
	_skill_action_button.focus_neighbor_right = _skill_action_button.get_path_to(
		_recall_action_button if not stacked else _skill_action_button,
	)
	_skill_action_button.focus_neighbor_top = _skill_action_button.get_path_to(
		_skill_action_button,
	)
	_skill_action_button.focus_neighbor_bottom = _skill_action_button.get_path_to(
		_recall_action_button if stacked else _skill_action_button,
	)
	_skill_action_button.focus_next = _skill_action_button.get_path_to(_recall_action_button)
	_recall_action_button.focus_neighbor_left = _recall_action_button.get_path_to(
		_skill_action_button if not stacked else _recall_action_button,
	)
	_recall_action_button.focus_neighbor_right = _recall_action_button.get_path_to(
		_recall_action_button,
	)
	_recall_action_button.focus_neighbor_top = _recall_action_button.get_path_to(
		_skill_action_button if stacked else _recall_action_button,
	)
	_recall_action_button.focus_neighbor_bottom = _recall_action_button.get_path_to(
		_recall_action_button,
	)
	_recall_action_button.focus_previous = _recall_action_button.get_path_to(
		_skill_action_button,
	)


func _layout_operator_action_panel() -> void:
	if (
		_operator_action_panel == null
		or not _operator_action_panel.visible
		or model == null
		or view == null
		or _selected_unit_id < 0
	):
		return
	var unit := model.unit_by_id(_selected_unit_id)
	if unit == null or not unit.alive:
		return
	var stacked := size.x < OPERATOR_ACTION_PANEL_NARROW_BREAKPOINT
	_operator_action_buttons.columns = 1 if stacked else 2
	_skill_action_button.custom_minimum_size.x = 0.0 if stacked else OPERATOR_ACTION_SKILL_WIDTH
	_recall_action_button.custom_minimum_size.x = 0.0 if stacked else OPERATOR_ACTION_RECALL_WIDTH
	_configure_operator_action_focus()
	var panel_width := minf(
		OPERATOR_ACTION_PANEL_WIDTH,
		maxf(280.0, size.x - OPERATOR_ACTION_PANEL_MARGIN * 2.0),
	)
	_operator_action_panel.custom_minimum_size.x = panel_width
	_operator_action_panel.reset_size()
	var panel_size := _operator_action_panel.get_combined_minimum_size()
	_operator_action_panel.size = Vector2(panel_width, panel_size.y)
	var center: Vector2 = view.call("cell_center", unit.cell)
	var safe_bottom := size.y - OPERATOR_ACTION_PANEL_MARGIN
	if _slot_deck != null:
		safe_bottom = minf(
			safe_bottom,
			_slot_deck.position.y - OPERATOR_ACTION_PANEL_DECK_GAP,
		)
	var max_x := maxf(
		OPERATOR_ACTION_PANEL_MARGIN,
		size.x - panel_size.x - OPERATOR_ACTION_PANEL_MARGIN,
	)
	var x := clampf(
		center.x - panel_size.x * 0.5,
		OPERATOR_ACTION_PANEL_MARGIN,
		max_x,
	)
	var max_y := maxf(OPERATOR_ACTION_PANEL_MARGIN, safe_bottom - panel_size.y)
	var y := center.y - panel_size.y - OPERATOR_ACTION_PANEL_UNIT_GAP
	if y < OPERATOR_ACTION_PANEL_MARGIN:
		var below := center.y + OPERATOR_ACTION_PANEL_UNIT_GAP
		y = below if below <= max_y else max_y
	_operator_action_panel.position = Vector2(
		x,
		clampf(y, OPERATOR_ACTION_PANEL_MARGIN, max_y),
	)
	_avoid_operator_action_blockers(safe_bottom)


func _avoid_operator_action_blockers(safe_bottom: float) -> bool:
	var blockers: Array[Rect2] = []
	for node_name: String in [
		"BattleHud", "BattleDialogue", "BattleCommandDeck",
	]:
		var blocker := view.find_child(node_name, true, false) as Control
		if blocker != null and blocker.visible:
			var blocker_rect := blocker.get_global_rect()
			if blocker_rect.has_area():
				blockers.append(blocker_rect)
	var own_rect := _operator_action_panel.get_global_rect()
	if not _intersects_any_operator_blocker(own_rect, blockers):
		return true
	var safe_rect := Rect2(
		global_position + Vector2.ONE * OPERATOR_ACTION_PANEL_MARGIN,
		Vector2(
			size.x - OPERATOR_ACTION_PANEL_MARGIN * 2.0,
			safe_bottom - OPERATOR_ACTION_PANEL_MARGIN,
		),
	)
	var x_candidates: Array[float] = [
		own_rect.position.x,
		safe_rect.position.x,
		safe_rect.end.x - own_rect.size.x,
	]
	var y_candidates: Array[float] = [
		own_rect.position.y,
		safe_rect.position.y,
		safe_rect.end.y - own_rect.size.y,
	]
	for blocker_rect: Rect2 in blockers:
		x_candidates.append(
			blocker_rect.position.x - own_rect.size.x - OPERATOR_ACTION_PANEL_DECK_GAP,
		)
		x_candidates.append(blocker_rect.end.x + OPERATOR_ACTION_PANEL_DECK_GAP)
		y_candidates.append(
			blocker_rect.position.y - own_rect.size.y - OPERATOR_ACTION_PANEL_DECK_GAP,
		)
		y_candidates.append(blocker_rect.end.y + OPERATOR_ACTION_PANEL_DECK_GAP)
	var candidates: Array[Vector2] = []
	for candidate_x: float in x_candidates:
		for candidate_y: float in y_candidates:
			candidates.append(Vector2(candidate_x, candidate_y))
	candidates.sort_custom(
		func(a: Vector2, b: Vector2) -> bool:
			return (
				a.distance_squared_to(own_rect.position)
				< b.distance_squared_to(own_rect.position)
			)
	)
	for candidate: Vector2 in candidates:
		var candidate_rect := Rect2(candidate, own_rect.size)
		if (
			safe_rect.encloses(candidate_rect)
			and not _intersects_any_operator_blocker(candidate_rect, blockers)
		):
			_operator_action_panel.global_position = candidate
			return true
	return false


func _intersects_any_operator_blocker(candidate: Rect2, blockers: Array[Rect2]) -> bool:
	for blocker: Rect2 in blockers:
		if candidate.intersects(blocker):
			return true
	return false


func _begin_heal_targeting(healer: UnitState) -> void:
	if (
		healer == null
		or not healer.is_skill_ready()
		or healer.skill_effect != SkillDef.Effect.HEAL_TARGET
	):
		return
	_heal_source_unit_id = healer.id
	_pointer = view.call("cell_center", healer.cell)
	_heal_cursor.position = _pointer
	_heal_cursor.color = HEAL_VALID_COLOR
	_heal_cursor.visible = true
	_show_heal_highlights()
	_refresh_operator_actions(true)
	_layout_operator_action_panel()


func _show_heal_highlights() -> void:
	for child: Node in _highlight_root.get_children():
		child.queue_free()
	for target: UnitState in model.units:
		if not HealingRulesScript.is_valid(model, _heal_source_unit_id, target.id):
			continue
		var rect := _make_overlay_rect(HEAL_VALID_COLOR)
		rect.name = "HealTarget_%d" % target.id
		rect.visible = true
		rect.position = view.call("cell_center", target.cell)
		_highlight_root.add_child(rect)


func _update_heal_hover() -> void:
	var cell: Vector2i = view.call("cell_at", _pointer)
	var target := model.alive_unit_at(cell)
	var valid := (
		target != null and HealingRulesScript.is_valid(model, _heal_source_unit_id, target.id)
	)
	_heal_cursor.color = HEAL_VALID_COLOR if valid else INVALID_COLOR
	_heal_cursor.position = view.call("cell_center", cell)


func _cancel_heal_targeting() -> void:
	if _heal_source_unit_id < 0:
		return
	_heal_source_unit_id = -1
	if _heal_cursor != null:
		_heal_cursor.visible = false
	for child: Node in _highlight_root.get_children():
		child.queue_free()
