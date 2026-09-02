extends SceneTree

const LANDSCAPE := Vector2i(1280, 720)
const ANNOTATED_WIDE := Vector2i(1912, 761)
const PORTRAIT := Vector2i(720, 1280)
const NARROW := Vector2i(540, 960)
const SHORT := Vector2i(960, 420)
var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = LANDSCAPE
	await process_frame
	var i18n := root.get_node_or_null("I18n")
	_check(i18n != null, "I18n autoload missing")
	if i18n == null:
		_finish()
		return
	_check(bool(i18n.call("reload_catalogs")), "localization catalogs failed canonical validation")
	_check(bool(i18n.call("set_locale", &"en-US")), "English locale activation failed")
	var game := root.get_node_or_null("Game")
	_check(game != null, "Game autoload missing")
	if game == null:
		_finish()
		return
	game.call("set_run_seed", 3302)
	_check(bool(game.call("start_campaign", false, true)), "battle UI campaign fixture failed")
	game.call("start_battle", &"s1", true)
	for _frame: int in range(12):
		await process_frame
	var battle := game.get("content") as Node
	_check(battle != null and bool(battle.get("startup_succeeded")), "battle view did not start")
	if battle == null:
		_finish()
		return
	var model := game.get("current_battle") as BattleModel
	var hud := battle.find_child("BattleHud", true, false) as Label
	var deploy_bar := battle.find_child("DeployBar", true, false) as Node
	var deployment_deck := battle.find_child("DeploymentCommandDeck", true, false) as PanelContainer
	var deployment_scroll := battle.find_child("DeploymentRosterScroll", true, false) as ScrollContainer
	var slot_box := battle.find_child("SlotBox", true, false) as GridContainer
	var controls := battle.find_child("BattleControls", true, false) as Node
	var confirmation_trace: Array[StringName] = []
	controls.connect(
		"confirmation_state_changed",
		func(state: StringName) -> void: confirmation_trace.append(state),
	)
	var controls_deck := battle.find_child("BattleCommandDeck", true, false) as PanelContainer
	var pause := battle.find_child("PauseButton", true, false) as Button
	var speed := battle.find_child("SpeedButton", true, false) as Button
	var resign := battle.find_child("ResignButton", true, false) as Button
	var tutorial := battle.find_child("FirstStandTutorial", true, false) as Node
	var tutorial_card := battle.find_child("TutorialCard", true, false) as PanelContainer
	var tutorial_title := battle.find_child("TutorialTitle", true, false) as Label
	var tutorial_body := battle.find_child("TutorialBody", true, false) as Label
	var skip := battle.find_child("SkipTutorial", true, false) as Button
	var tutorial_primary := battle.find_child("TutorialPrimary", true, false) as Button
	_check(hud != null and hud.get_theme_stylebox(&"normal") is StyleBoxTexture, "battle HUD does not use the Lunaris command frame")
	if hud != null:
		var hud_style := hud.get_theme_stylebox(&"normal")
		_check(hud.size.y >= 100.0, "battle HUD did not receive doubled container height")
		_check(hud.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER and hud.vertical_alignment == VERTICAL_ALIGNMENT_CENTER, "battle HUD text is not centered")
		_check(hud_style.content_margin_left >= 48.0 and hud_style.content_margin_top >= 24.0 and hud_style.content_margin_right >= 24.0 and hud_style.content_margin_bottom >= 24.0, "battle HUD violates the 24px custom-frame padding floor")
	_check(deployment_deck != null and deployment_deck.get_theme_stylebox(&"panel") is StyleBoxTexture, "deployment deck is not textured")
	if deployment_deck != null:
		var deployment_style := deployment_deck.get_theme_stylebox(&"panel")
		_check(
			is_equal_approx(deployment_style.content_margin_left, 24.0)
			and is_equal_approx(deployment_style.content_margin_top, 32.0)
			and is_equal_approx(deployment_style.content_margin_right, 24.0)
			and is_equal_approx(deployment_style.content_margin_bottom, 32.0),
			"deployment deck does not use 24px horizontal and 32px vertical padding",
		)
		_check(deployment_deck.size.x >= 1240.0, "landscape recruit selector did not expand to the available near-double width")
	_check(deployment_scroll != null and deployment_scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO, "deployment roster is not locally scrollable")
	_check(deployment_scroll != null and deployment_scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "deployment roster permits horizontal scrolling")
	_check(slot_box != null and slot_box.get_child_count() >= 3, "deployment slots are missing")
	if slot_box != null:
		for child: Node in slot_box.get_children():
			var slot := child as Button
			var slot_style := slot.get_theme_stylebox(&"normal") as StyleBoxFlat
			_check(slot != null and is_equal_approx(slot.custom_minimum_size.y, 76.0) and slot.size.x >= 120.0 and slot.size.y >= 48.0, "deployment slot did not receive compact usable geometry")
			_check(slot != null and slot.get_theme_font_size(&"font_size") == 24, "deployment slot copy did not receive 24px compact typography")
			_check(slot_style != null and slot_style.get_corner_radius(CORNER_TOP_LEFT) >= 8, "deployment slot lacks rounded borders")
			_check(deployment_deck.get_global_rect().encloses((child as Button).get_global_rect()), "deployment deck does not contain a Recruit control")
		var first_slot := slot_box.get_child(0) as Button
		_check(first_slot.get_theme_stylebox(&"normal").content_margin_left >= 24.0, "first Recruit lacks the requested left content inset")
	_check(controls_deck != null and controls_deck.get_theme_stylebox(&"panel") is StyleBoxTexture, "battle command deck is not textured")
	if controls_deck != null:
		var controls_style := controls_deck.get_theme_stylebox(&"panel")
		_check(
			is_equal_approx(controls_style.content_margin_left, 24.0)
			and is_equal_approx(controls_style.content_margin_top, 32.0)
			and is_equal_approx(controls_style.content_margin_right, 24.0)
			and is_equal_approx(controls_style.content_margin_bottom, 32.0),
			"battle command deck does not use 24px horizontal and 32px vertical padding",
		)
	_check(pause != null and speed != null and resign != null and pause.focus_mode == Control.FOCUS_ALL, "battle commands are not controller focusable")
	_check(speed.tooltip_text.contains("Q: LOWER SPEED") and speed.tooltip_text.contains("E: RAISE SPEED"), "speed control does not disclose Q/E shortcuts")
	_check(speed.accessibility_description == speed.tooltip_text, "speed shortcut help is not exposed to assistive technology")
	for button: Button in [pause, speed, resign]:
		var button_style := button.get_theme_stylebox(&"normal") as StyleBoxFlat
		_check(button.custom_minimum_size.is_equal_approx(Vector2(112.0, 48.0)), "%s did not receive the compact 112×48 target" % button.name)
		_check(is_equal_approx(button.size.y, 48.0), "%s did not render at the compact 48px height" % button.name)
		_check(button.get_theme_font_size(&"font_size") == 24, "%s did not receive 24px compact typography" % button.name)
		_check(button_style != null and button_style.get_corner_radius(CORNER_TOP_LEFT) >= 8, "%s lacks rounded borders" % button.name)
		_check(controls_deck.get_global_rect().encloses(button.get_global_rect()), "%s overflows the battle command deck" % button.name)
	_check(battle.find_child("FirstActionInset", true, false) == null, "obsolete one-off Pause inset survived the 24px parent padding")
	_check(battle.find_child("RecenterMap", true, false) == null, "removed CENTER feature is still present")
	_check(battle.find_child("BattleDialogue", true, false) == null, "removed battle transmission presenter is still mounted")
	_check(tutorial_card != null and tutorial_card.get_theme_stylebox(&"panel") is StyleBoxTexture, "tutorial card did not inherit the Lunaris modal frame")
	if tutorial_card != null:
		var tutorial_rect := tutorial_card.get_global_rect()
		var tutorial_style := tutorial_card.get_theme_stylebox(&"panel")
		_check(tutorial_rect.size.x >= 900.0 and tutorial_rect.size.y >= 400.0, "tutorial card did not receive the 3× width / 2× height treatment")
		_check(absf(tutorial_rect.position.x - 24.0) <= 2.0, "tutorial card is not left-aligned to the 24px viewport margin")
		_check(tutorial_style.content_margin_top == 48.0 and tutorial_style.content_margin_bottom == 48.0, "tutorial card lacks exact 48px vertical content padding")
		_check(tutorial_style.content_margin_left == 24.0 and tutorial_style.content_margin_right == 24.0, "tutorial card lacks exact 24px horizontal content padding")
	_check(tutorial_title != null and tutorial_title.get_theme_font_size(&"font_size") == 54, "tutorial title did not receive the reduced 54px landscape typography")
	_check(tutorial_body != null and tutorial_body.get_theme_font_size(&"font_size") == 38, "tutorial body did not receive the reduced 38px landscape typography")
	_check(tutorial_body != null and tutorial_body.text == "Enemies start from the portal and follow the lit path to your base crystal. This mission allows 3 leaks, the 4th leak will end the mission.", "tutorial route copy does not match the approved wording")
	_check(skip != null and tutorial_primary != null, "tutorial actions are missing")
	if skip != null and tutorial_primary != null:
		for button: Button in [skip, tutorial_primary]:
			var normal_style := button.get_theme_stylebox(&"normal")
			_check(button.get_theme_font_size(&"font_size") == 27, "%s tutorial copy is not 27px" % button.name)
			_check(normal_style.content_margin_left >= 12.0 and normal_style.content_margin_top >= 12.0 and normal_style.content_margin_right >= 12.0 and normal_style.content_margin_bottom >= 12.0, "%s lacks 12px internal padding" % button.name)
			_check(tutorial_card.get_global_rect().encloses(button.get_global_rect()), "%s overflows the tutorial card" % button.name)
		_check(skip.custom_minimum_size.is_equal_approx(Vector2(440.0, 64.0)), "Skip Tutorial did not double to a 440×64 action target")
		_check(tutorial_primary.custom_minimum_size.is_equal_approx(Vector2(220.0, 64.0)), "NEXT did not retain its 220×64 action target")
		_check(tutorial_primary.get_theme_stylebox(&"normal") is StyleBoxFlat, "NEXT still uses a textured frame that can cross its label")
		_check(tutorial_primary.get_theme_color(&"font_color").is_equal_approx(Color("07111c")), "NEXT does not use readable dark ink on solid gold")
		_check(tutorial_primary.text == "NEXT", "tutorial route action was not renamed to NEXT")
	_check(bool(i18n.call("set_locale", &"zh-CN")), "Chinese locale activation failed")
	await process_frame
	_check(tutorial_body.text == "敌人从传送门出发，沿发光路径前往你的基地水晶。本任务最多允许3名敌人漏过；第4名敌人漏过时，任务失败。", "Chinese tutorial route copy does not match the approved meaning")
	_check(tutorial_primary.text == "下一步", "Chinese tutorial route action was not renamed to 下一步")
	_check(hud.text.contains("核心") and hud.text.contains("歼灭"), "battle HUD did not refresh to Chinese")
	_check(pause.text == "暂停" and resign.text == "撤出行动", "battle commands did not refresh to distinct Chinese actions")
	_check(speed.tooltip_text.contains("Q：降低速度") and speed.tooltip_text.contains("E：提高速度"), "Chinese speed shortcut help did not refresh")
	if slot_box != null:
		for child: Node in slot_box.get_children():
			var slot := child as Button
			_check(slot.get_theme_font(&"font").has_char("兵".unicode_at(0)), "%s lacks bundled Chinese glyph coverage" % slot.name)
	_check(
		battle.find_child("FacingRight", true, false) == null
		and battle.find_child("FacingDown", true, false) == null
		and battle.find_child("FacingLeft", true, false) == null
		and battle.find_child("FacingUp", true, false) == null,
		"obsolete deployment-facing controls are still present",
	)
	_check(bool(i18n.call("set_locale", &"en-US")), "English locale restoration failed")
	await process_frame
	if controls == null or deploy_bar == null or model == null:
		_check(false, "battle controls, deployment bar, or model missing")
		_cleanup(game, battle)
		_finish()
		return
	_check(tutorial != null and bool(tutorial.call("is_holding_battle")), "First Stand tutorial is not holding the initial battle")
	_check(not bool(deploy_bar.call("operator_interaction_enabled")), "tutorial route step did not block operator cards")
	controls.call("set_interaction_enabled", true)
	_check(bool(controls.call("request_resign_confirmation")), "resign confirmation did not open under composed tutorial fixture")
	await _wait_for_confirmation_state(controls, &"active")
	_check(bool(battle.call("battle_confirmation_active")), "battle confirmation blocker was not published")
	_check(not bool(deploy_bar.call("interaction_enabled")), "confirmation did not gate deployment interaction")
	_check(not bool(deploy_bar.call("operator_interaction_enabled")), "confirmation overwrote tutorial operator blocker")
	_check(bool(controls.call("cancel_resign_confirmation")), "composed confirmation did not cancel")
	_check(StringName(controls.call("confirmation_state_name")) == &"exiting" and bool(battle.call("battle_confirmation_active")), "Cancel released the gate before exit")
	await _wait_for_confirmation_state(controls, &"closed")
	_check(bool(deploy_bar.call("interaction_enabled")) and not bool(deploy_bar.call("operator_interaction_enabled")), "Cancel did not preserve the composed tutorial gate")
	controls.call("set_interaction_enabled", false)
	if skip != null:
		skip.pressed.emit()
	for _frame: int in range(3):
		await process_frame
	_check(bool(controls.call("interaction_enabled")) and bool(deploy_bar.call("operator_interaction_enabled")), "tutorial completion did not restore controls")
	root.size = ANNOTATED_WIDE
	await process_frame
	_check(absf(deployment_deck.size.x - 1360.0) <= 2.0, "annotated-width recruit selector is not exactly double the former 680px fixed width")
	root.size = NARROW
	for _frame: int in range(3):
		await process_frame
	root.size = SHORT
	for _frame: int in range(3):
		await process_frame
	root.size = LANDSCAPE
	for _frame: int in range(3):
		await process_frame
	speed.grab_focus()
	await process_frame
	controls.call("_input", _space_key_event())
	_check(is_equal_approx(float(battle.get("ticks_per_frame_scale")), 0.0), "Space did not pause while a battle command held focus")
	_check(speed.has_focus(), "Space pause changed the focused battle command")
	controls.call("_input", _space_key_event())
	_check(is_equal_approx(float(battle.get("ticks_per_frame_scale")), 1.0), "Space did not resume the prior battle speed")
	controls.call("_input", _key_event(KEY_Q))
	_check(is_equal_approx(float(battle.get("ticks_per_frame_scale")), 0.0), "Q did not reduce 1× to paused")
	controls.call("_input", _key_event(KEY_Q))
	_check(is_equal_approx(float(battle.get("ticks_per_frame_scale")), 0.0), "Q reduced speed below paused")
	controls.call("_input", _key_event(KEY_E))
	_check(is_equal_approx(float(battle.get("ticks_per_frame_scale")), 1.0), "E did not increase paused to 1×")
	controls.call("_input", _key_event(KEY_E))
	_check(is_equal_approx(float(battle.get("ticks_per_frame_scale")), 2.0), "E did not increase 1× to 2×")
	controls.call("_input", _key_event(KEY_E))
	_check(is_equal_approx(float(battle.get("ticks_per_frame_scale")), 4.0), "E did not increase 2× to 4×")
	controls.call("_input", _key_event(KEY_E))
	_check(is_equal_approx(float(battle.get("ticks_per_frame_scale")), 4.0), "E increased speed above the 4× maximum")
	controls.call("_input", _key_event(KEY_Q))
	_check(is_equal_approx(float(battle.get("ticks_per_frame_scale")), 2.0), "Q did not reduce 4× to 2×")
	controls.call("_input", _key_event(KEY_Q))
	_check(is_equal_approx(float(battle.get("ticks_per_frame_scale")), 1.0), "Q did not reduce 2× to 1×")

	controls.call("_on_speed_pressed")
	_check(is_equal_approx(float(battle.get("ticks_per_frame_scale")), 2.0), "speed selector did not cycle 1× → 2×")
	controls.call("_on_speed_pressed")
	_check(is_equal_approx(float(battle.get("ticks_per_frame_scale")), 4.0), "speed selector did not cycle 2× → 4×")
	controls.call("_on_speed_pressed")
	controls.call("_process", 0.0)
	_check(is_equal_approx(float(battle.get("ticks_per_frame_scale")), 0.0), "speed selector did not cycle 4× → paused")
	_check(speed.text == "0×" and pause.text == "RESUME", "paused speed-selector state is not visible")
	await process_frame
	for button: Button in [pause, speed, resign]:
		_check(
			is_equal_approx(button.size.y, 48.0),
			"%s grew to %.1fpx in the paused state" % [button.name, button.size.y],
		)
	controls.call("_on_speed_pressed")
	controls.call("_process", 0.0)
	_check(is_equal_approx(float(battle.get("ticks_per_frame_scale")), 1.0), "speed selector did not cycle paused → 1×")
	_check(speed.text == "1×" and pause.text == "PAUSE", "resumed speed-selector state is not visible")
	battle.set("ticks_per_frame_scale", 0.0)
	controls.call("_process", 0.0)
	_check(bool(controls.call("request_resign_confirmation")), "paused resign confirmation did not open")
	await _wait_for_confirmation_state(controls, &"active")
	_check(bool(controls.call("cancel_resign_confirmation")), "paused resign confirmation did not cancel")
	_check(is_equal_approx(float(battle.get("ticks_per_frame_scale")), 0.0) and bool(battle.call("battle_confirmation_active")), "paused Cancel restored gates before exit")
	await _wait_for_confirmation_state(controls, &"closed")
	_check(is_equal_approx(float(battle.get("ticks_per_frame_scale")), 0.0), "Cancel did not restore an exact zero-speed snapshot")

	var exact_scale := 2.375
	battle.set("ticks_per_frame_scale", exact_scale)
	controls.call("_process", 0.0)
	_check(bool(controls.call("_step_speed", -1)), "Q-step rejected a nonstandard running speed")
	_check(is_equal_approx(float(battle.get("ticks_per_frame_scale")), 2.0), "Q did not floor a nonstandard running speed to 2×")
	battle.set("ticks_per_frame_scale", exact_scale)
	_check(bool(controls.call("_step_speed", 1)), "E-step rejected a nonstandard running speed")
	_check(is_equal_approx(float(battle.get("ticks_per_frame_scale")), 4.0), "E did not ceil a nonstandard running speed to 4×")
	battle.set("ticks_per_frame_scale", exact_scale)
	_check(StringName(controls.call("confirmation_state_name")) == &"closed", "initial confirmation state is not CLOSED")
	_check(bool(controls.call("request_resign_confirmation")), "resign confirmation did not open")
	_check(StringName(controls.call("confirmation_state_name")) == &"entering", "confirmation did not publish ENTERING immediately")
	_check(is_equal_approx(float(battle.get("ticks_per_frame_scale")), 0.0) and bool(battle.call("battle_confirmation_active")), "entry did not immediately pause and gate battle")
	await _wait_for_confirmation_state(controls, &"active")
	var layer := battle.find_child("ResignConfirmLayer", true, false) as Control
	var safe := layer.find_child("SafeFrame", true, false) as MarginContainer
	var frame := layer.find_child("StateFrame", true, false) as Control
	var panel := layer.find_child("ResignConfirm", true, false) as PanelContainer
	var cancel := layer.find_child("CancelResign", true, false) as Button
	var confirm := layer.find_child("ConfirmResign", true, false) as Button
	var status := layer.find_child("Status", true, false) as Label
	_check(layer.visible and StringName(controls.call("confirmation_state_name")) == &"active", "confirmation did not enter ACTIVE")
	_check(status != null and status.get_parent().get_parent().name == "ActionDock", "withdraw status is not visible in the action dock")
	_check(panel.accessibility_labeled_by_nodes.has(panel.get_path_to(layer.find_child("Title", true, false))), "withdraw panel is not labeled by Title")
	_check(panel.accessibility_described_by_nodes.has(panel.get_path_to(status)), "withdraw panel is not described by Status")
	_check(confirm.accessibility_name != cancel.accessibility_name and not confirm.accessibility_description.is_empty(), "withdraw actions lack distinct accessibility semantics")
	_check(is_equal_approx(float(battle.get("ticks_per_frame_scale")), 0.0), "confirmation did not pause battle")
	_check(cancel.has_focus(), "Cancel is not safe default focus")
	_check(layer.mouse_filter == Control.MOUSE_FILTER_STOP and _rect_matches(layer.get_global_rect(), Rect2(Vector2.ZERO, Vector2(LANDSCAPE))), "confirmation is not a full input-exclusive viewport")
	_check(_rect_matches(panel.get_global_rect(), frame.get_global_rect()), "confirmation panel does not fill the safe content frame")
	_check(not bool(battle.call("map_dragging")) and not bool(battle.call("map_inertia_active")), "confirmation did not cancel map motion")
	_check(pause.disabled and speed.disabled and resign.disabled, "confirmation did not disable underlying battle commands")
	var blocked_pan := battle.call("map_pan") as Vector2
	var blocked_wheel := InputEventMouseButton.new()
	blocked_wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	blocked_wheel.pressed = true
	battle.call("_unhandled_input", blocked_wheel)
	controls.call("_on_pause_pressed")
	controls.call("_on_speed_pressed")
	controls.call("_input", _key_event(KEY_E))
	deploy_bar.call("_start_placement", StringName(deploy_bar.call("first_deployment_id")))
	_check((battle.call("map_pan") as Vector2).is_equal_approx(blocked_pan), "confirmation allowed map wheel input")
	_check(is_equal_approx(float(battle.get("ticks_per_frame_scale")), 0.0), "confirmation allowed pause/speed input")
	_check(not bool(deploy_bar.call("transient_intent_active")), "confirmation allowed new deployment input")
	_check(bool(controls.call("cancel_resign_confirmation")), "confirmation did not cancel")
	_check(is_equal_approx(float(battle.get("ticks_per_frame_scale")), 0.0) and bool(battle.call("battle_confirmation_active")), "Cancel restored speed or gate before exit finalizer")
	controls.call("_unhandled_input", _action_event(&"ui_cancel"))
	_check(root.is_input_handled() and StringName(controls.call("confirmation_state_name")) == &"exiting" and bool(battle.call("battle_confirmation_active")), "ui_cancel was not consumed throughout EXITING")
	await _wait_for_confirmation_state(controls, &"closed")
	_check(is_equal_approx(float(battle.get("ticks_per_frame_scale")), exact_scale), "Cancel did not exactly restore speed snapshot")
	_check(resign.has_focus() and model.result == BattleModel.Result.RUNNING, "Cancel failed focus/result invariance")

	var deployment_id := StringName(deploy_bar.call("first_deployment_id"))
	deploy_bar.call("_start_placement", deployment_id)
	_check(bool(deploy_bar.call("transient_intent_active")), "deployment intent did not start")
	bool(controls.call("request_resign_confirmation"))
	await _wait_for_confirmation_state(controls, &"active")
	_check(not bool(deploy_bar.call("transient_intent_active")), "confirmation did not cancel deployment/facing intent")
	bool(controls.call("cancel_resign_confirmation"))
	await _wait_for_confirmation_state(controls, &"closed")
	bool(controls.call("request_resign_confirmation"))
	await _wait_for_confirmation_state(controls, &"active")
	_check(not bool(deploy_bar.call("interaction_enabled")), "confirmation did not retain the deployment gate")
	bool(controls.call("cancel_resign_confirmation"))
	await _wait_for_confirmation_state(controls, &"closed")
	model.dp = model.config.dp_cap
	var deploy_cell := _first_valid_deploy_cell(model, deployment_id)
	_check(deploy_cell.x >= 0 and model.apply_action([&"deploy", deployment_id, deploy_cell, int(UnitState.Facing.RIGHT)]), "retreat fixture could not deploy")
	if deploy_cell.x >= 0:
		var deployed_unit := model.alive_unit_at(deploy_cell)
		deployed_unit.skill_id = &"rally"
		deployed_unit.sp_cost = 15
		deployed_unit.sp = 7
		deployed_unit.skill_effect = SkillDef.Effect.DP_BURST
		deployed_unit.skill_params = {"amount": 3}
		var skills_before_selection := model.skills_fired
		deploy_bar.call("_handle_grid_click", battle.call("cell_center", deploy_cell))
		await process_frame
		var action_panel := battle.find_child("OperatorActionPanel", true, false) as PanelContainer
		var action_state := battle.find_child("OperatorActionState", true, false) as Label
		var action_detail := battle.find_child("OperatorActionDetail", true, false) as Label
		var action_buttons := battle.find_child("OperatorActionButtons", true, false) as GridContainer
		var skill_action := battle.find_child("ActivateOperatorSkill", true, false) as Button
		var recall_action := battle.find_child("RecallOperator", true, false) as Button
		var skill_progress := battle.find_child("OperatorSkillProgress", true, false) as ProgressBar
		_check(bool(deploy_bar.call("transient_intent_active")), "operator selection intent did not start")
		_check(is_equal_approx(Engine.time_scale, 0.75), "selected field operator did not slow battle time by 25%")
		_check(action_panel != null and action_panel.visible, "selected operator did not expose the action panel")
		_check(skill_action != null and skill_action.disabled and skill_action.text == "CHARGING 7 / 15", "unready skill does not expose explicit charging state")
		_check(recall_action != null and not recall_action.disabled and recall_action.text == "RECALL", "Recall is not independently available while a skill charges")
		_check(skill_progress != null and is_equal_approx(skill_progress.value, 7.0) and is_equal_approx(skill_progress.max_value, 15.0), "operator action panel does not project authoritative SP")
		_check(model.skills_fired == skills_before_selection and deployed_unit.sp == 7, "selecting an operator implicitly fired its skill")
		_check(recall_action.has_focus(), "disabled Skill did not choose Recall as the safe focus target")
		_check(action_panel.accessibility_labeled_by_nodes.has(action_panel.get_path_to(battle.find_child("OperatorActionName", true, false))), "operator action panel is not labeled by the operator name")
		_check(not skill_action.accessibility_description.is_empty() and not recall_action.accessibility_description.is_empty(), "operator actions lack accessibility descriptions")

		_check(bool(i18n.call("set_locale", &"zh-CN")), "operator action fixture could not switch to Chinese")
		await process_frame
		_check(recall_action.text == "撤回" and action_state.text == "充能中", "operator actions did not refresh to Chinese")
		_check(action_detail.text.contains("集结") and action_detail.text.contains("技力"), "Chinese skill name or SP state is missing")
		_check(bool(i18n.call("set_locale", &"en-US")), "operator action fixture could not restore English")
		await process_frame

		root.size = NARROW
		for _frame: int in range(3):
			await process_frame
		_check(action_buttons.columns == 1, "narrow operator actions did not stack")
		_check(Rect2(Vector2.ZERO, Vector2(NARROW)).encloses(action_panel.get_global_rect()), "narrow operator action panel escaped the viewport")
		_check(not action_panel.get_global_rect().intersects(deployment_deck.get_global_rect()), "narrow operator action panel overlaps the deployment deck")
		root.size = LANDSCAPE
		for _frame: int in range(3):
			await process_frame
		_check(action_buttons.columns == 2, "landscape operator actions did not restore the two-action row")
		_check(not action_panel.get_global_rect().intersects(hud.get_global_rect()), "operator actions overlap the battle HUD when a clear landscape lane exists")

		deployed_unit.sp = deployed_unit.sp_cost
		deploy_bar.call("_process", 0.0)
		_check(not skill_action.disabled and skill_action.text.contains("ACTIVATE") and skill_action.text.to_upper().contains("RALLY"), "ready skill did not expose an explicit activation action")
		_check(not recall_action.disabled, "Recall disappeared when the selected skill became ready")
		await _capture_operator_actions_if_requested()
		var skills_before_activation := model.skills_fired
		skill_action.pressed.emit()
		await process_frame
		_check(model.skills_fired == skills_before_activation + 1 and deployed_unit.sp == 0, "Skill action did not route through the authoritative trigger_skill verb")
		_check(not action_panel.visible and not bool(deploy_bar.call("transient_intent_active")), "successful skill activation did not clear selection")
		_check(is_equal_approx(Engine.time_scale, 1.0), "successful skill activation left tactical slowdown active")

		deploy_bar.call("_handle_grid_click", battle.call("cell_center", deploy_cell))
		await process_frame
		bool(controls.call("request_resign_confirmation"))
		await _wait_for_confirmation_state(controls, &"active")
		_check(not bool(deploy_bar.call("transient_intent_active")), "confirmation did not cancel operator actions")
		_check(is_equal_approx(Engine.time_scale, 1.0), "selection slowdown survived selection cancellation")
		bool(controls.call("cancel_resign_confirmation"))
		await _wait_for_confirmation_state(controls, &"closed")

		deployed_unit.skill_id = &"mend"
		deployed_unit.sp_cost = 10
		deployed_unit.sp = 10
		deployed_unit.skill_effect = SkillDef.Effect.HEAL_TARGET
		deployed_unit.skill_params = {"amount": 20, "range_cells": 99}
		deploy_bar.call("_handle_grid_click", battle.call("cell_center", deploy_cell))
		await process_frame
		skill_action.pressed.emit()
		await process_frame
		_check(bool(deploy_bar.call("is_mend_targeting")), "Mend action did not enter ally targeting")
		_check(skill_action.text == "CANCEL TARGETING" and recall_action.disabled, "Mend targeting does not expose a clear cancellable state")
		deploy_bar.call("_input", _action_event(&"ui_cancel"))
		await process_frame
		_check(not bool(deploy_bar.call("is_mend_targeting")) and action_panel.visible, "first Escape did not return Mend targeting to operator actions")
		_check(not skill_action.disabled and not recall_action.disabled, "cancelling Mend targeting did not restore actions")
		deploy_bar.call("_input", _action_event(&"ui_cancel"))
		await process_frame
		_check(not action_panel.visible and is_equal_approx(Engine.time_scale, 1.0), "second Escape did not dismiss operator actions and restore time")

		var target_deployment_id := _other_deployment_id(model, deployment_id)
		model.dp = model.config.dp_cap
		var target_cell := _first_valid_deploy_cell(model, target_deployment_id)
		_check(target_deployment_id != &"" and target_cell.x >= 0 and model.apply_action([&"deploy", target_deployment_id, target_cell, int(UnitState.Facing.RIGHT)]), "Mend target fixture could not deploy")
		var heal_target := model.alive_unit_at(target_cell)
		if heal_target != null:
			heal_target.hp = maxi(1, heal_target.hp_max - 30)
		var hp_before_mend := heal_target.hp if heal_target != null else -1
		deploy_bar.call("_handle_grid_click", battle.call("cell_center", deploy_cell))
		await process_frame
		skill_action.pressed.emit()
		await process_frame
		deploy_bar.call("_handle_grid_click", battle.call("cell_center", target_cell))
		await process_frame
		_check(heal_target != null and heal_target.hp > hp_before_mend and deployed_unit.sp == 0, "valid Mend target did not receive healing through the mend verb")
		_check(not action_panel.visible and is_equal_approx(Engine.time_scale, 1.0), "successful Mend did not clear selection and slowdown")

		deploy_bar.call("_handle_grid_click", battle.call("cell_center", deploy_cell))
		await process_frame
		_check(not recall_action.disabled, "Recall is unavailable after skill use")
		recall_action.pressed.emit()
		deploy_bar.call("_process", 0.0)
		var cooldown_slot := battle.find_child("Slot_%s" % deployment_id, true, false) as Button
		_check(deployed_unit != null and not deployed_unit.alive, "Recall action did not remove the selected operator")
		_check(model.is_redeploy_cooling_down(deployment_id), "Recall did not start an authoritative redeploy cooldown")
		_check(cooldown_slot != null and cooldown_slot.text.contains("COOLDOWN"), "deploy card does not expose the Recall cooldown")
		_check(cooldown_slot != null and cooldown_slot.disabled, "cooling-down deploy card remains actionable")
		_check(is_equal_approx(Engine.time_scale, 1.0), "Recall did not clear tactical selection slowdown")

	bool(controls.call("request_resign_confirmation"))
	await _wait_for_confirmation_state(controls, &"active")
	for viewport_size: Vector2i in [PORTRAIT, NARROW, SHORT]:
		root.size = viewport_size
		await process_frame
		_check(_rect_matches(layer.get_global_rect(), Rect2(Vector2.ZERO, Vector2(viewport_size))), "confirmation root missed viewport %s" % viewport_size)
		_check(_rect_matches(panel.get_global_rect(), frame.get_global_rect()), "confirmation panel missed safe content frame at %s" % viewport_size)
		var actions := layer.find_child("Actions", true, false) as GridContainer
		var body_scroll := layer.find_child("BodyScroll", true, false) as ScrollContainer
		var dock := layer.find_child("ActionDock", true, false) as PanelContainer
		_check(actions.columns == (2 if viewport_size == SHORT else 1), "actions did not reflow at %s" % viewport_size)
		_check(cancel.size.y >= 44.0 and confirm.size.y >= 44.0, "actions lost touch size at %s" % viewport_size)
		_check(body_scroll.get_global_rect().end.y <= dock.get_global_rect().position.y + 1.0, "body overlapped fixed dock at %s" % viewport_size)
	confirm.grab_focus()
	await process_frame
	var forward_target := confirm.get_node_or_null(confirm.focus_next) as Control
	_check(
		confirm.has_focus() and forward_target != null and layer.is_ancestor_of(forward_target),
		"focus trap failed on responsive sheet",
	)
	_send_action(&"ui_left")
	await process_frame
	_check(cancel.has_focus(), "wide ui_left did not swap confirmation actions")
	_send_action(&"ui_down")
	await process_frame
	_check(cancel.has_focus(), "wide ui_down should keep the action focused")
	root.size = LANDSCAPE
	await process_frame
	bool(controls.call("cancel_resign_confirmation"))
	await _wait_for_confirmation_state(controls, &"closed")
	_check(is_equal_approx(float(battle.get("ticks_per_frame_scale")), exact_scale), "responsive Cancel did not restore exact speed")

	confirmation_trace.clear()
	var committing_cancel_consumed := [false]
	var committing_cancel_probe := func(state: StringName) -> void:
		if state != &"committing":
			return
		controls.call("_unhandled_input", _action_event(&"ui_cancel"))
		committing_cancel_consumed[0] = (
			root.is_input_handled()
			and StringName(controls.call("confirmation_state_name")) == &"committing"
			and bool(battle.call("battle_confirmation_active"))
		)
	controls.connect("confirmation_state_changed", committing_cancel_probe)
	bool(controls.call("request_resign_confirmation"))
	await _wait_for_confirmation_state(controls, &"active")
	_check(bool(controls.call("commit_resign_confirmation")), "Confirm did not accept resign")
	controls.disconnect("confirmation_state_changed", committing_cancel_probe)
	var dispatch_count := int(controls.call("resign_dispatch_count"))
	_check(confirmation_trace == [&"entering", &"active", &"committing", &"exiting"], "resign state did not expose ENTERING → ACTIVE → COMMITTING → EXITING")
	_check(committing_cancel_consumed[0], "ui_cancel was not consumed throughout COMMITTING")
	_check(dispatch_count == 1 and StringName(controls.call("confirmation_state_name")) == &"exiting", "resign did not dispatch once and retain EXITING")
	_check(bool(battle.call("battle_confirmation_active")) and layer.visible, "terminal confirmation released its gate before exit")
	_check(not bool(controls.call("commit_resign_confirmation")) and int(controls.call("resign_dispatch_count")) == dispatch_count, "terminal confirmation dispatched twice")
	battle.call("_detect_result_stamp")
	var continue_during_exit := battle.find_child("ContinueButton", true, false) as Button
	var immediate_stamp := battle.find_child("ResultStampLabel", true, false) as Label
	_check(continue_during_exit != null and not continue_during_exit.has_focus(), "terminal Continue focused before confirmation exit closed")
	_check(immediate_stamp != null, "terminal feedback waited for campaign persistence")
	_check(continue_during_exit != null and continue_during_exit.disabled, "terminal debrief was actionable before campaign persistence")
	await process_frame
	_check(continue_during_exit != null and continue_during_exit.disabled, "result preparation and durable commit were not split across frames")
	await _wait_for_confirmation_state(controls, &"closed")
	_check(confirmation_trace == [&"entering", &"active", &"committing", &"exiting", &"closed"], "terminal exit did not finalize CLOSED")
	await process_frame
	var continue_button := battle.find_child("ContinueButton", true, false) as Button
	var defeat_stamp := battle.find_child("ResultStampLabel", true, false) as Label
	var defeat_ambient := battle.find_child("DefeatAmbient", true, false) as Control
	var pan_hint := battle.find_child("MapPanHint", true, false) as Control
	_check(model.result == BattleModel.Result.DEFEAT and not layer.visible, "terminal defeat retained confirmation")
	_check(pause.disabled and speed.disabled and resign.disabled, "terminal battle controls remain actionable")
	_check(not bool(deploy_bar.call("interaction_enabled")), "terminal deployment controls remain actionable")
	_check(pan_hint == null or not pan_hint.visible, "terminal map hint remains visible")
	_check(continue_button != null and continue_button.has_focus(), "terminal Continue did not own focus")
	_check(defeat_stamp != null and defeat_stamp.get_theme_font_size(&"font_size") >= 162, "DEFEAT stamp is not three times the prior 54px result size")
	_check(defeat_ambient != null and defeat_ambient.mouse_filter == Control.MOUSE_FILTER_IGNORE, "terminal defeat ambience is missing or intercepts input")
	_check(defeat_ambient != null and defeat_ambient.z_index == 67, "terminal defeat ambience is not staged below the result stamp")
	_check(defeat_ambient != null and int(defeat_ambient.call("particle_count")) >= 18, "terminal defeat ambience lacks its ember field")
	if continue_button != null:
		var continue_style := continue_button.get_theme_stylebox(&"normal")
		_check(continue_button.custom_minimum_size.x >= 600.0, "Continue to Debrief is not wide enough for its copy")
		_check(continue_button.get_theme_font_size(&"font_size") >= 42, "Continue to Debrief typography was not enlarged")
		_check(continue_button.get_theme_color(&"font_color") == Color.WHITE, "Continue to Debrief copy is not white")
		_check(continue_style.content_margin_top >= 24.0 and continue_style.content_margin_bottom >= 24.0, "Continue to Debrief lacks 24px vertical padding")
		_check(continue_button.get_combined_minimum_size().x <= continue_button.size.x + 1.0, "Continue to Debrief text overflows its action width")
		_check(bool(continue_button.get_meta(&"action_hover_feedback_wired", false)), "Continue to Debrief lacks shared hover feedback")
		var continue_idle_tint := continue_button.modulate
		continue_button.emit_signal(&"mouse_entered")
		await create_timer(0.22).timeout
		_check(continue_button.scale.x >= 1.035 and continue_button.scale.y >= 1.035, "Continue to Debrief does not lift on hover")
		_check(not continue_button.modulate.is_equal_approx(continue_idle_tint), "Continue to Debrief lacks hover luminance feedback")
		continue_button.emit_signal(&"mouse_exited")
		await create_timer(0.22).timeout
		_check(continue_button.scale.x < 1.03 and continue_button.scale.y < 1.03, "Continue to Debrief did not settle after hover")
	var terminal_pan := battle.call("map_pan") as Vector2
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	battle.call("_unhandled_input", wheel)
	_check((battle.call("map_pan") as Vector2).is_equal_approx(terminal_pan), "terminal map accepted wheel input")
	_cleanup(game, battle)
	await create_timer(0.25).timeout
	_finish()

func _wait_for_confirmation_state(controls: Node, expected: StringName, timeout_seconds := 0.8) -> void:
	var timeout := create_timer(timeout_seconds, true, false, true)
	while StringName(controls.call("confirmation_state_name")) != expected and timeout.time_left > 0.0:
		await process_frame


func _send_action(action: StringName) -> void:
	Input.parse_input_event(_action_event(action))


func _action_event(action: StringName) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


func _space_key_event() -> InputEventKey:
	return _key_event(KEY_SPACE)


func _key_event(key: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = true
	return event


func _first_valid_deploy_cell(model: BattleModel, deployment_id: StringName) -> Vector2i:
	for y: int in model.stage.grid_size().y:
		for x: int in model.stage.grid_size().x:
			var cell := Vector2i(x, y)
			if model.can_deploy_at(deployment_id, cell):
				return cell
	return Vector2i(-1, -1)


func _other_deployment_id(model: BattleModel, excluded: StringName) -> StringName:
	var deployment_ids: Array[StringName] = (
		model.battle_squad if not model.battle_squad.is_empty() else model.squad
	)
	for deployment_id: StringName in deployment_ids:
		if deployment_id != excluded and model.is_deployable(deployment_id):
			return deployment_id
	return &""


func _capture_operator_actions_if_requested() -> void:
	var output_path := OS.get_environment("PROTO_TD_OPERATOR_ACTION_CAPTURE")
	if output_path.is_empty():
		return
	await RenderingServer.frame_post_draw
	var image := root.get_viewport().get_texture().get_image()
	var error := image.save_png(output_path)
	_check(error == OK, "operator action visual capture could not be saved")
	if error == OK:
		print("OPERATOR_ACTION_VISUAL_OK path=%s" % output_path)


func _rect_matches(actual: Rect2, expected: Rect2, tolerance := 1.5) -> bool:
	return actual.position.distance_to(expected.position) <= tolerance and actual.size.distance_to(expected.size) <= tolerance

func _cleanup(game: Node, battle: Node) -> void:
	game.set("content", null)
	game.set("current_battle", null)
	game.set("pending_stage", null)
	if battle != null and is_instance_valid(battle):
		var parent := battle.get_parent()
		if parent != null:
			parent.remove_child(battle)
		battle.free()
	game.set("campaign_active", false)
	game.set("campaign", null)
	game.set("campaign_store", null)
	var music := root.get_node_or_null("Music")
	if music != null and music.has_method("stop"):
		music.call("stop")
	var sfx := root.get_node_or_null("Sfx")
	if sfx != null and sfx.has_method("stop_all"):
		sfx.call("stop_all")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("BATTLE_UI_LAYOUT_TEST_OK")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)
