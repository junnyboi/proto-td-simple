extends Control

## Campaign stage select. Locked cards remain disabled controls; stage stars,
## sequential unlocks, selection, and routing remain projections of Game.

const SHELL_SCENE := preload("res://scenes/ui/components/aetheria_screen_shell.tscn")
const AetheriaButtonType := preload("res://scripts/ui/components/aetheria_button.gd")
const AetheriaLabelType := preload("res://scripts/ui/components/aetheria_label.gd")
const AetheriaScreenShellType := preload("res://scripts/ui/components/aetheria_screen_shell.gd")
const GameTypographyType := preload("res://scripts/ui/game_typography.gd")
const FactionHeraldryType := preload("res://scripts/ui/components/faction_heraldry.gd")
const UiCopyType := preload("res://scripts/ui/components/ui_copy.gd")
const CampaignStarType := preload("res://scripts/ui/components/campaign_star.gd")
const StagingSkinType := preload("res://scripts/ui/components/staging_skin.gd")
const Style := preload("res://scripts/ui/components/lunaris_ops_style.gd")
const CampaignNextSparklesType := preload("res://scripts/ui/components/campaign_next_sparkles.gd")
const ViewPreferencesType := preload("res://scripts/view/view_preferences.gd")
const COMMAND_BACKDROP := preload("res://assets/loading/command_backdrop.png")
const ROUTE_CONTENT_INSET := 36
const MISSION_CARD_SIZE := Vector2(288.0, 192.0)
const MISSION_CARD_GAP := 12
const MISSION_CARD_PADDING := 30.0
const MISSION_CARD_FONT_SIZE := 45
const MISSION_CARD_STAR_SIZE := 60.0
const MISSION_CARD_STAR_SEPARATION := 12
const UTILITY_BUTTON_CORNER_RADIUS := 12
const ROUTE_HOVER_BACKGROUND := Color("2f7f9188")
const ROUTE_FOCUS_BACKGROUND := Color("22455355")
const ROUTE_HOVER_SCALE := Vector2(1.025, 1.025)
const ROUTE_FOCUS_SCALE := Vector2(1.01, 1.01)
const ROUTE_HOVER_SECONDS := 0.16
const MASTER_BUS := &"Master"
const MUSIC_BUS := &"Music"
const SFX_BUS := &"SFX"
var _rows: HFlowContainer = null
var _header: GridContainer = null
var _body: GridContainer = null
var _shell: AetheriaScreenShellType = null
var _stage_by_id: Dictionary = {}
var _next_stage_id: StringName = &""
var _eyebrow: AetheriaLabelType = null
var _progress: AetheriaLabelType = null
var _route_heading: AetheriaLabelType = null
var _route_note: AetheriaLabelType = null
var _back: AetheriaButtonType = null
var _settings_button: AetheriaButtonType = null
var _enabled_rows: Array[Button] = []
var _mission_route_committed := false
var _preferences_path := ViewPreferencesType.DEFAULT_PATH
var _preferences_path_explicit := false
var _settings_snapshot: Dictionary = {}
var _settings_open := false
var _settings_committing := false
var _music_enabled := true
var _master_volume := 1.0
var _master_muted := false
var _music_volume := 1.0
var _sfx_volume := 1.0
var _frame_limit := 0
var _reduced_motion := false
var _text_scale := 1.0
var _background_downloads_enabled := true
var _player_data_clear_pending := false

@onready var _settings_state: TitleSettings = $TitleSettings


func _ready() -> void:
	if not _preferences_path_explicit:
		_preferences_path = Game.view_preferences_path()
	_load_preferences()
	I18n.set_locale(ViewPreferencesType.locale(_preferences_path))
	_apply_audio_settings()
	_apply_graphics_settings()
	_apply_background_download_policy()
	Music.set_enabled(_music_enabled)
	Game.content = self
	Style.add_backdrop(self, COMMAND_BACKDROP)
	_shell = SHELL_SCENE.instantiate() as AetheriaScreenShellType
	_shell.name = "CampaignShell"
	_shell.full_safe_area = true
	add_child(_shell)
	_shell.layout_mode_changed.connect(_on_layout_mode_changed)
	resized.connect(_on_viewport_size_changed)

	var column := VBoxContainer.new()
	column.name = "CampaignColumn"
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override(&"separation", 14)
	_shell.content_host().add_child(column)

	_build_header(column)
	_build_body(column)
	_populate_route()
	_on_layout_mode_changed(_shell.layout_mode())
	move_child(_settings_state, get_child_count() - 1)
	_settings_state.cancel_requested.connect(_cancel_settings)
	_settings_state.apply_requested.connect(_apply_settings)
	_settings_state.preview_requested.connect(_preview_settings)
	_settings_state.clear_player_data_requested.connect(_clear_player_data)
	_settings_state.close_completed.connect(_on_settings_close_completed)
	if not I18n.locale_changed.is_connected(_on_locale_changed):
		I18n.locale_changed.connect(_on_locale_changed)


func set_preferences_path(path: String) -> void:
	_preferences_path = path if not path.is_empty() else ViewPreferencesType.DEFAULT_PATH
	_preferences_path_explicit = true
	Game.set_view_preferences_path(_preferences_path)


func _build_header(column: VBoxContainer) -> void:
	_header = GridContainer.new()
	_header.name = "CampaignHeader"
	_header.columns = 3
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.add_theme_constant_override(&"h_separation", 16)
	_header.add_theme_constant_override(&"v_separation", 10)
	column.add_child(_header)

	var identity := HBoxContainer.new()
	identity.name = "CampaignIdentity"
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_theme_constant_override(&"separation", 12)
	identity.add_child(FactionHeraldryType.make_symbol(FactionHeraldryType.ACTIVE_FACTION, 48.0))
	var headings := VBoxContainer.new()
	headings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_eyebrow = AetheriaLabelType.new()
	_eyebrow.name = "CampaignEyebrow"
	_eyebrow.apply_role(&"dense_detail")
	_eyebrow.text = UiCopyType.text(&"ui.campaign.eyebrow", "Lunaris Expedition Archive")
	headings.add_child(_eyebrow)
	var heading := AetheriaLabelType.new()
	heading.name = "CampaignHeading"
	heading.apply_role(&"title")
	heading.text = UiCopyType.text(&"ui.campaign.heading", "Campaign").to_upper()
	headings.add_child(heading)
	identity.add_child(headings)
	_header.add_child(identity)

	_progress = AetheriaLabelType.new()
	_progress.name = "CampaignProgress"
	_progress.apply_role(&"dense_heading")
	_progress.custom_minimum_size.x = 190.0
	_progress.autowrap_mode = TextServer.AUTOWRAP_OFF
	_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_header.add_child(_progress)

	var utilities := GridContainer.new()
	utilities.name = "CampaignUtilities"
	utilities.columns = 2
	utilities.size_flags_horizontal = Control.SIZE_SHRINK_END
	utilities.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	utilities.add_theme_constant_override(&"h_separation", 12)
	_header.add_child(utilities)

	_back = AetheriaButtonType.new()
	_back.name = "CampaignBack"
	_back.custom_minimum_size = Vector2(156.0, 64.0)
	_back.apply_role(&"secondary")
	_back.apply_compact_action_layout()
	_back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_apply_utility_button_style(_back)
	_back.pressed.connect(_on_back)
	utilities.add_child(_back)

	_settings_button = AetheriaButtonType.new()
	_settings_button.name = "CampaignSettingsButton"
	_settings_button.custom_minimum_size = Vector2(196.0, 64.0)
	_settings_button.apply_role(&"secondary")
	_settings_button.apply_compact_action_layout()
	_settings_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_apply_utility_button_style(_settings_button)
	_settings_button.pressed.connect(_open_settings)
	utilities.add_child(_settings_button)
	_refresh_header_copy()


func _apply_utility_button_style(button: Button) -> void:
	Style.apply_simple_gold_button(
		button, false, 16.0, UTILITY_BUTTON_CORNER_RADIUS, 10.0,
	)


func _build_body(column: VBoxContainer) -> void:
	var rule := ColorRect.new()
	rule.name = "CampaignRule"
	rule.custom_minimum_size = Vector2(0, 2)
	rule.color = Color(Style.CYAN, 0.52)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(rule)

	_body = GridContainer.new()
	_body.name = "CampaignBody"
	_body.columns = 1
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override(&"h_separation", 16)
	_body.add_theme_constant_override(&"v_separation", 12)
	column.add_child(_body)

	var route_panel := PanelContainer.new()
	route_panel.name = "CampaignRoutePanel"
	route_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	route_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	Style.apply_panel(route_panel, &"quiet")
	_body.add_child(route_panel)
	var route_content_inset := MarginContainer.new()
	route_content_inset.name = "RouteContentInset"
	for side: StringName in [&"margin_left", &"margin_top", &"margin_right", &"margin_bottom"]:
		route_content_inset.add_theme_constant_override(side, ROUTE_CONTENT_INSET)
	route_content_inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	route_content_inset.size_flags_vertical = Control.SIZE_EXPAND_FILL
	route_panel.add_child(route_content_inset)
	var route_stack := VBoxContainer.new()
	route_stack.name = "RouteContent"
	route_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	route_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	route_stack.add_theme_constant_override(&"separation", 10)
	route_content_inset.add_child(route_stack)
	var route_header := VBoxContainer.new()
	route_header.name = "RouteHeader"
	route_header.add_theme_constant_override(&"separation", 10)
	route_stack.add_child(route_header)
	_route_heading = AetheriaLabelType.new()
	_route_heading.name = "RouteHeading"
	_route_heading.apply_role(&"heading")
	_route_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_route_heading.text = UiCopyType.text(&"ui.campaign.mission_list", "Mission List")
	route_header.add_child(_route_heading)
	_route_note = AetheriaLabelType.new()
	_route_note.name = "RouteNote"
	_route_note.apply_role(&"detail")
	_route_note.text = UiCopyType.text(
		&"ui.campaign.route_note",
		"Select an available operation, or replay a cleared one.",
	)
	_route_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	route_header.add_child(_route_note)
	var scroll := ScrollContainer.new()
	scroll.name = "CampaignScroll"
	scroll.custom_minimum_size.y = 112.0
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	route_stack.add_child(scroll)
	_rows = HFlowContainer.new()
	_rows.name = "StageRows"
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.alignment = FlowContainer.ALIGNMENT_BEGIN
	_rows.add_theme_constant_override(&"h_separation", MISSION_CARD_GAP)
	_rows.add_theme_constant_override(&"v_separation", MISSION_CARD_GAP)
	scroll.add_child(_rows)


func _populate_route() -> void:
	var stage_stars: Dictionary = Game.campaign_projection().get("stage_stars", {})
	var enabled_rows: Array[Button] = []
	for stage_id: StringName in Game.campaign_stage_ids():
		var stage := load("res://data/stages/%s.tres" % stage_id) as StageDef
		_stage_by_id[stage_id] = stage
		var unlocked: bool = Game.is_stage_unlocked(stage_id)
		if unlocked and not stage_stars.has(stage_id) and _next_stage_id.is_empty():
			_next_stage_id = stage_id
		var row := AetheriaButtonType.new()
		row.name = "Stage_%s" % stage_id
		row.custom_minimum_size = MISSION_CARD_SIZE
		row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.disabled = not unlocked
		var is_next := unlocked and not stage_stars.has(stage_id) and _next_stage_id == stage_id
		row.apply_role(&"selected" if is_next else (&"secondary" if unlocked else &"disabled"))
		_apply_mission_card_button_style(row, unlocked, is_next)
		_apply_route_row_presentation(row, stage, unlocked, is_next)
		if is_next:
			var sparkles := CampaignNextSparklesType.new()
			sparkles.name = "NextOperationSparkles"
			row.add_child(sparkles)
			sparkles.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.tooltip_text = row.text
		row.accessibility_name = row.text
		if is_next:
			row.accessibility_description = UiCopyType.text(
				&"ui.campaign.next_highlight_description",
				"Recommended next operation, highlighted with a glow and sparkles.",
			)
		if not unlocked:
			row.focus_mode = Control.FOCUS_NONE
		else:
			enabled_rows.append(row)
			_wire_route_card_feedback(row)
			row.pressed.connect(_on_stage_pressed.bind(stage_id))
		_rows.add_child(row)

	_enabled_rows = enabled_rows
	_refresh_focus_chain(true)


func _apply_mission_card_button_style(row: Button, unlocked: bool, selected: bool) -> void:
	var normal_tint := Color("b9f8fb") if selected else Color.WHITE
	var hover_tint := Color.WHITE if selected else Color("b9f8fb")
	var pressed_tint := Style.CYAN
	if not unlocked:
		normal_tint = Color(0.42, 0.48, 0.55, 0.56)
		hover_tint = normal_tint
		pressed_tint = normal_tint
	row.add_theme_stylebox_override(
		&"normal", StagingSkinType.operation_tile_style(normal_tint),
	)
	row.add_theme_stylebox_override(
		&"hover", StagingSkinType.operation_tile_style(hover_tint),
	)
	var pressed := StagingSkinType.operation_tile_style(pressed_tint)
	row.add_theme_stylebox_override(&"pressed", pressed)
	row.add_theme_stylebox_override(&"hover_pressed", pressed.duplicate())
	row.add_theme_stylebox_override(
		&"disabled", StagingSkinType.operation_tile_style(Color(0.42, 0.48, 0.55, 0.56)),
	)
	row.add_theme_stylebox_override(
		&"focus", StagingSkinType.golden_focus_tint_style(12),
	)


func _unhandled_input(event: InputEvent) -> void:
	if _mission_route_committed:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _settings_open and not _settings_committing:
			_cancel_settings()
		elif not _settings_open:
			_on_back()


func _row_text(stage: StageDef, unlocked: bool) -> String:
	var is_next := unlocked and int(Game.campaign_projection().get("stage_stars", {}).get(stage.id, 0)) == 0 and _next_stage_id == stage.id
	return _row_presentation_text(stage, unlocked, is_next)


func _row_presentation_text(stage: StageDef, unlocked: bool, is_next: bool) -> String:
	var stars := int(Game.campaign_projection().get("stage_stars", {}).get(stage.id, 0))
	var state := UiCopyType.text(&"ui.campaign.row_locked", "Locked")
	if stars > 0:
		state = UiCopyType.format_text(
			&"ui.campaign.row_star" if stars == 1 else &"ui.campaign.row_stars",
			"{count} star" if stars == 1 else "{count} stars",
			{&"count": stars},
		)
	elif unlocked:
		state = UiCopyType.text(
			&"ui.campaign.row_next" if is_next else &"ui.campaign.row_available",
			"Next" if is_next else "Available",
		)
	return "%s  %02d  %s  ·  %s" % [
		_act_short(stage), stage.campaign_index, UiCopyType.stage_title(stage), state,
	]


func _mission_card_title(stage: StageDef) -> String:
	return UiCopyType.format_text(
		&"ui.campaign.act_card", "Act {index}", {&"index": stage.campaign_index},
	)


func _apply_route_row_presentation(
	row: AetheriaButtonType,
	stage: StageDef,
	unlocked: bool,
	is_next: bool,
) -> void:
	if row == null or stage == null:
		return
	var stars := int(Game.campaign_projection().get("stage_stars", {}).get(stage.id, 0))
	var logical_text := _row_presentation_text(stage, unlocked, is_next)
	var card_title := _mission_card_title(stage)
	row.set_presentation_text(logical_text, card_title)
	row.tooltip_text = logical_text
	row.accessibility_name = logical_text
	var presentation := row.get_node_or_null("PresentationLabel") as Label
	if presentation != null:
		presentation.visible = false
	var content := row.get_node_or_null("MissionCardContent") as VBoxContainer
	if content == null:
		content = VBoxContainer.new()
		content.name = "MissionCardContent"
		content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		content.offset_left = MISSION_CARD_PADDING
		content.offset_top = MISSION_CARD_PADDING
		content.offset_right = -MISSION_CARD_PADDING
		content.offset_bottom = -MISSION_CARD_PADDING
		content.alignment = BoxContainer.ALIGNMENT_CENTER
		content.add_theme_constant_override(&"separation", 4)
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(content)
		var title := AetheriaLabelType.new()
		title.name = "MissionCardTitle"
		title.apply_role(&"body")
		title.autowrap_mode = TextServer.AUTOWRAP_OFF
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		title.add_theme_font_size_override(&"font_size", MISSION_CARD_FONT_SIZE)
		content.add_child(title)
		var star_row := HBoxContainer.new()
		star_row.name = "MissionCardStars"
		star_row.alignment = BoxContainer.ALIGNMENT_CENTER
		star_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		star_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		star_row.add_theme_constant_override(&"separation", MISSION_CARD_STAR_SEPARATION)
		star_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(star_row)
	var title_label := content.get_node_or_null("MissionCardTitle") as Label
	if title_label != null:
		title_label.text = card_title
		var title_color := Color(Style.MUTED, 0.64) if not unlocked else Style.IVORY
		title_label.add_theme_color_override(&"font_color", title_color)
		title_label.add_theme_color_override(&"font_disabled_color", title_color)
	var star_row := content.get_node_or_null("MissionCardStars") as HBoxContainer
	if star_row == null:
		return
	star_row.visible = stars > 0
	for child: Node in star_row.get_children():
		star_row.remove_child(child)
		child.queue_free()
	for index: int in stars:
		var star := CampaignStarType.new()
		star.name = "MissionCardStar_%d" % (index + 1)
		star.custom_minimum_size = Vector2.ONE * MISSION_CARD_STAR_SIZE
		star.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		star.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		star.set_state(Style.GOLD, true)
		star_row.add_child(star)


func _act_short(stage: StageDef) -> String:
	return UiCopyType.text(
		&"ui.campaign.act_2_short" if stage.campaign_index >= 9 else &"ui.campaign.act_1_short",
		"ACT II" if stage.campaign_index >= 9 else "ACT I",
	)


func _wire_focus(enabled_rows: Array[Button], back: Button, grab_initial := false) -> void:
	var focusable := enabled_rows.duplicate()
	focusable.append(back)
	if _settings_button != null:
		focusable.append(_settings_button)
	for index: int in focusable.size():
		var current: Button = focusable[index]
		var previous: Button = focusable[(index - 1 + focusable.size()) % focusable.size()]
		var next: Button = focusable[(index + 1) % focusable.size()]
		current.focus_neighbor_top = current.get_path_to(previous)
		current.focus_previous = current.get_path_to(previous)
		current.focus_neighbor_bottom = current.get_path_to(next)
		current.focus_next = current.get_path_to(next)
	if grab_initial and not enabled_rows.is_empty():
		enabled_rows[0].grab_focus.call_deferred()
	elif grab_initial:
		back.grab_focus.call_deferred()


func _refresh_focus_chain(grab_initial := false) -> void:
	if _back != null:
		_wire_focus(_enabled_rows, _back, grab_initial)


func _load_preferences() -> void:
	_reduced_motion = ViewPreferencesType.reduced_motion(_preferences_path)
	_music_enabled = ViewPreferencesType.title_music_enabled(_preferences_path)
	_master_volume = ViewPreferencesType.master_volume(_preferences_path)
	_master_muted = ViewPreferencesType.master_muted(_preferences_path)
	_music_volume = ViewPreferencesType.music_volume(_preferences_path)
	_sfx_volume = ViewPreferencesType.sfx_volume(_preferences_path)
	_frame_limit = ViewPreferencesType.frame_limit(_preferences_path)
	_text_scale = ViewPreferencesType.text_scale(_preferences_path)
	_background_downloads_enabled = ViewPreferencesType.background_downloads_enabled(
		_preferences_path,
	)


func _open_settings() -> void:
	if _settings_open or _mission_route_committed:
		return
	_settings_snapshot = _current_preferences()
	_settings_snapshot[&"return_focus"] = _settings_button
	_settings_open = true
	_settings_committing = false
	Sfx.play("menu_open")
	_set_route_input_enabled(false)
	_settings_state.open(_settings_snapshot)


func _cancel_settings() -> void:
	if (
		not _settings_open
		or _settings_committing
		or _settings_state.transition_state_name() != &"ACTIVE"
	):
		return
	var snapshot := _settings_snapshot.duplicate(true)
	_settings_snapshot[&"closing_return_focus"] = snapshot.get(&"return_focus") as Control
	if not _settings_state.close():
		return
	_apply_preference_values(snapshot)
	Sfx.play("menu_close")


func _apply_settings(draft: Dictionary) -> void:
	if not _settings_open:
		return
	_settings_committing = true
	_settings_state.set_committing(true)
	if not ViewPreferencesType.save_batch(draft, _preferences_path):
		_settings_committing = false
		_settings_state.show_save_failure()
		return
	_apply_preference_values(draft)
	Sfx.play("ui_confirm")
	_settings_snapshot[&"closing_return_focus"] = (
		_settings_snapshot.get(&"return_focus") as Control
	)
	_settings_committing = false
	_settings_state.close()


func _preview_settings(draft: Dictionary) -> void:
	if _settings_open and not _settings_committing:
		_apply_preference_values(draft, false)


func _clear_player_data() -> void:
	if not _settings_open or _settings_committing:
		return
	_player_data_clear_pending = true
	var result: Dictionary = Game.clear_player_data()
	if bool(result.get(&"accepted", false)):
		Sfx.play("ui_confirm")
		return
	_player_data_clear_pending = false
	_settings_state.show_player_data_clear_failure()


func _on_settings_close_completed() -> void:
	if not _settings_open:
		return
	var return_focus := _settings_snapshot.get(&"closing_return_focus") as Control
	_settings_snapshot = {}
	_settings_open = false
	_settings_committing = false
	_set_route_input_enabled(true)
	var target := return_focus
	if target == null or not is_instance_valid(target) or not target.is_visible_in_tree():
		target = _settings_button
	if target != null:
		target.grab_focus()


func _current_preferences() -> Dictionary:
	return {
		&"locale": I18n.locale(),
		&"title_music_enabled": _music_enabled,
		&"master_volume": _master_volume,
		&"master_muted": _master_muted,
		&"music_volume": _music_volume,
		&"sfx_volume": _sfx_volume,
		&"frame_limit": _frame_limit,
		&"reduced_motion": _reduced_motion,
		&"text_scale": _text_scale,
		&"background_downloads_enabled": _background_downloads_enabled,
	}


func _apply_preference_values(values: Dictionary, apply_background_policy := true) -> void:
	var locale_id := StringName(values.get(&"locale", I18n.locale()))
	if I18n.locale() != locale_id:
		I18n.set_locale(locale_id)
	_reduced_motion = bool(values.get(&"reduced_motion", _reduced_motion))
	_frame_limit = int(values.get(&"frame_limit", _frame_limit))
	_master_volume = float(values.get(&"master_volume", _master_volume))
	_master_muted = bool(values.get(&"master_muted", _master_muted))
	_music_volume = float(values.get(&"music_volume", _music_volume))
	_sfx_volume = float(values.get(&"sfx_volume", _sfx_volume))
	_text_scale = float(values.get(&"text_scale", _text_scale))
	if apply_background_policy:
		_background_downloads_enabled = bool(values.get(
			&"background_downloads_enabled", _background_downloads_enabled,
		))
	var previous_music_enabled := _music_enabled
	_music_enabled = bool(values.get(&"title_music_enabled", _music_enabled))
	_apply_audio_settings()
	_apply_graphics_settings()
	_settings_state.set_reduced_motion(_reduced_motion)
	if apply_background_policy:
		_apply_background_download_policy()
	Music.set_enabled(_music_enabled)
	if _music_enabled and (not previous_music_enabled or Music.current_id().is_empty()):
		Music.play_staging(&"lunaris")
	_refresh_header_copy()
	if _shell != null:
		_shell.relayout.call_deferred(Vector2i(get_viewport_rect().size))
	_settings_state.call_deferred("_apply_responsive_layout")


func _apply_audio_settings() -> void:
	_set_bus_volume(MASTER_BUS, _master_volume, _master_muted)
	_set_bus_volume(MUSIC_BUS, _music_volume)
	_set_bus_volume(SFX_BUS, _sfx_volume)


func _set_bus_volume(bus_name: StringName, value: float, force_mute := false) -> void:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index < 0:
		return
	AudioServer.set_bus_mute(bus_index, force_mute or value <= 0.001)
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(maxf(value, 0.001)))


func _apply_graphics_settings() -> void:
	Engine.max_fps = _frame_limit
	ProjectSettings.set_setting("accessibility/reduced_motion", _reduced_motion)
	TextScale.set_scale(_text_scale)


func _apply_background_download_policy() -> void:
	var content_packs := get_node_or_null("/root/ContentPacks")
	if content_packs != null and content_packs.has_method("set_background_downloads_enabled"):
		content_packs.call(
			"set_background_downloads_enabled", _background_downloads_enabled,
		)


func _on_stage_pressed(stage_id: StringName) -> void:
	if _mission_route_committed or not Game.is_stage_unlocked(stage_id):
		return
	Sfx.play("ui_click")
	_mission_route_committed = true
	_set_route_input_enabled(false)
	if not Game.start_campaign_stage(stage_id):
		_mission_route_committed = false
		_set_route_input_enabled(true)


func _set_route_input_enabled(enabled: bool) -> void:
	for row: Button in _enabled_rows:
		row.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
		row.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
	if _back != null:
		_back.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
		_back.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
	if _settings_button != null:
		_settings_button.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
		_settings_button.mouse_filter = (
			Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
		)


func _on_layout_mode_changed(mode: StringName) -> void:
	if _header != null:
		_header.columns = 1 if mode == &"portrait" else 3
	if _body != null:
		_body.columns = 1
		var route_panel := _body.get_node_or_null("CampaignRoutePanel") as Control
		if route_panel != null:
			route_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			route_panel.custom_minimum_size = Vector2.ZERO
	# A full-safe-area shell computes its available plate before this callback.
	# Refit once after descendant column minima settle so landscape widths cannot
	# survive a live rotation into portrait.
	if _shell != null:
		_shell.relayout.call_deferred(Vector2i(get_viewport_rect().size))


func _on_viewport_size_changed() -> void:
	if _shell == null or not is_instance_valid(_shell):
		return
	if _rows != null:
		_rows.queue_sort()


func _on_locale_changed(_locale_id: StringName) -> void:
	_refresh_header_copy()
	if _route_heading != null:
		_route_heading.text = UiCopyType.text(&"ui.campaign.mission_list", "Mission List")
	if _route_note != null:
		_route_note.text = UiCopyType.text(
			&"ui.campaign.route_note",
			"Select an available operation, or replay a cleared one.",
		)
	for stage_id: StringName in _stage_by_id:
		var stage: StageDef = _stage_by_id[stage_id]
		var row := _rows.get_node_or_null("Stage_%s" % stage_id) as AetheriaButtonType
		if row == null:
			continue
		var unlocked := Game.is_stage_unlocked(stage_id)
		var is_next := unlocked and _next_stage_id == stage_id
		_apply_route_row_presentation(row, stage, unlocked, is_next)


func _refresh_header_copy() -> void:
	if _eyebrow != null:
		_eyebrow.text = UiCopyType.text(&"ui.campaign.eyebrow", "Lunaris Expedition Archive")
	if _progress != null:
		var stars: Dictionary = Game.campaign_projection().get("stage_stars", {})
		_progress.text = _format_copy(
			&"ui.campaign.progress", "{cleared} / {total} cleared",
			{&"cleared": stars.size(), &"total": Game.campaign_stage_ids().size()},
		)
	if _back != null:
		_back.text = UiCopyType.text(&"ui.common.back", "Back")
		_back.set_presentation_text(_back.text, UiCopyType.text(&"ui.common.back", "Back"))
		_back.tooltip_text = _back.text
		_back.accessibility_name = _back.text
	if _settings_button != null:
		_settings_button.text = UiCopyType.text(&"ui.title.settings", "Settings")
		_settings_button.set_presentation_text(_settings_button.text, _settings_button.text)
		_settings_button.tooltip_text = _settings_button.text
		_settings_button.accessibility_name = _settings_button.text


func _wire_route_card_feedback(row: Button) -> void:
	var background := ColorRect.new()
	background.name = "RouteHoverBackground"
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.offset_left = 10.0
	background.offset_top = 7.0
	background.offset_right = -10.0
	background.offset_bottom = -7.0
	background.color = Color.TRANSPARENT
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(background)
	row.move_child(background, 0)
	row.set_meta(&"route_hovered", false)
	row.set_meta(&"route_focused", row.has_focus())
	row.resized.connect(_center_route_card_pivot.bind(row))
	row.mouse_entered.connect(_set_route_card_hovered.bind(row, background, true))
	row.mouse_exited.connect(_set_route_card_hovered.bind(row, background, false))
	row.focus_entered.connect(_set_route_card_focused.bind(row, background, true))
	row.focus_exited.connect(_set_route_card_focused.bind(row, background, false))
	_center_route_card_pivot.call_deferred(row)


func _center_route_card_pivot(row: Button) -> void:
	if row != null and is_instance_valid(row):
		row.pivot_offset = row.size * 0.5


func _set_route_card_hovered(row: Button, background: ColorRect, highlighted: bool) -> void:
	if row == null or not is_instance_valid(row):
		return
	row.set_meta(&"route_hovered", highlighted)
	_refresh_route_card_feedback(row, background)


func _set_route_card_focused(row: Button, background: ColorRect, highlighted: bool) -> void:
	if row == null or not is_instance_valid(row):
		return
	row.set_meta(&"route_focused", highlighted)
	_refresh_route_card_feedback(row, background)


func _refresh_route_card_feedback(row: Button, background: ColorRect) -> void:
	if row == null or background == null or not is_instance_valid(row) or not is_instance_valid(background):
		return
	var hovered := bool(row.get_meta(&"route_hovered", false))
	var focused := bool(row.get_meta(&"route_focused", false))
	var target_scale := ROUTE_HOVER_SCALE if hovered else (ROUTE_FOCUS_SCALE if focused else Vector2.ONE)
	var target_color := ROUTE_HOVER_BACKGROUND if hovered else (ROUTE_FOCUS_BACKGROUND if focused else Color.TRANSPARENT)
	if bool(ProjectSettings.get_setting("accessibility/reduced_motion", false)):
		target_scale = Vector2.ONE
	if row.has_meta(&"route_hover_tween"):
		var tween_value: Variant = row.get_meta(&"route_hover_tween")
		if tween_value is Tween and (tween_value as Tween).is_valid():
			(tween_value as Tween).kill()
		row.remove_meta(&"route_hover_tween")
	if not row.is_inside_tree() or bool(ProjectSettings.get_setting("accessibility/reduced_motion", false)):
		row.scale = target_scale
		background.color = target_color
		return
	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(row, "scale", target_scale, ROUTE_HOVER_SECONDS)
	tween.tween_property(background, "color", target_color, ROUTE_HOVER_SECONDS)
	row.set_meta(&"route_hover_tween", tween)


func _format_copy(key: StringName, fallback: String, args: Dictionary) -> String:
	var value := UiCopyType.text(key, fallback)
	for name: StringName in args:
		value = value.replace("{%s}" % name, str(args[name]))
	return value


func _on_back() -> void:
	Sfx.play("ui_back")
	Game.open_title()
