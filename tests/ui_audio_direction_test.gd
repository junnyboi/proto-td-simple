extends SceneTree

const MUTED_UI_IDS := [
	&"ui_hover",
	&"ui_back",
	&"ui_confirm",
	&"menu_open",
	&"menu_close",
]
const BATTLE_SEMANTIC_ALIASES := {
	&"kill": &"operator_select",
	&"wave": &"placement_ready",
	&"conflagration": &"ability_ready",
	&"deadeye": &"ability_ready",
	&"flurry": &"ability_ready",
}

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var sfx := root.get_node_or_null("Sfx")
	_check(sfx != null, "Sfx autoload is available")
	if sfx != null:
		_check(bool(sfx.call("reload_catalog")), "SFX catalog loads")
		_check(int(sfx.call("catalog_entry_count")) >= 16, "expanded catalog contains hover UI suite")
		var routine_starts_before := int(sfx.call("audible_start_count"))
		var previous_resolved_id: StringName = sfx.call("last_resolved_id")
		for id: StringName in MUTED_UI_IDS:
			_check(sfx.call("resolved_id_for", id) == id, "%s resolves directly" % id)
			var stream := load("res://assets/sfx/ui/%s.wav" % id) as AudioStream
			_check(stream != null, "%s stream loads" % id)
			if stream != null:
				_check(stream.get_length() >= 0.1, "%s retains its authored source" % id)
				_check(stream.get_length() <= 3.05, "%s stays within the three-second SFX budget" % id)
			stream = null
			_check(not bool(sfx.call("play", String(id))), "%s aura cue remains silent" % id)
			await process_frame
			_check(sfx.call("resolved_id_for", &"ui_accept") == &"ui_confirm", "accept alias resolves")
			_check(sfx.call("resolved_id_for", &"ui_select") == &"ui_click", "select alias resolves")
			_check(not bool(sfx.call("play", "ui_accept")), "accept alias cannot replay the aura cue")
			_check(
				int(sfx.call("audible_start_count")) == routine_starts_before,
			"silent navigation cues do not consume audio voices",
		)
		_check(
			sfx.call("last_resolved_id") == previous_resolved_id,
			"silent navigation cues do not replace the last audible semantic cue",
		)
		for semantic_id: StringName in BATTLE_SEMANTIC_ALIASES:
			var resolved_id: StringName = BATTLE_SEMANTIC_ALIASES[semantic_id]
			_check(
				sfx.call("resolved_id_for", semantic_id) == resolved_id,
				"%s semantic SFX does not resolve to %s" % [semantic_id, resolved_id],
			)
			_check(
				bool(sfx.call("play", String(semantic_id))),
				"%s semantic SFX does not start a voice" % semantic_id,
			)
			await process_frame
		var button := Button.new()
		button.name = "HoverAudioTestButton"
		button.text = "Hover"
		var custom_control := Control.new()
		custom_control.focus_mode = Control.FOCUS_ALL
		custom_control.mouse_filter = Control.MOUSE_FILTER_STOP
		var hover_controls: Array[Control] = [
			button,
			HSlider.new(),
			LineEdit.new(),
			TextEdit.new(),
			OptionButton.new(),
			SpinBox.new(),
			VScrollBar.new(),
			ItemList.new(),
			TabBar.new(),
			MenuBar.new(),
			custom_control,
		]
		for control: Control in hover_controls:
			# Keep the live headless pointer from emitting incidental mouse-entered
			# signals while this test drives the signal contract explicitly.
			control.position = Vector2(4096.0, 4096.0)
			root.add_child(control)
		var ephemeral_control := Control.new()
		root.add_child(ephemeral_control)
		ephemeral_control.queue_free()
		await process_frame
		await create_timer(0.15).timeout
		for bound_control: Control in hover_controls:
			_check(
				bool(sfx.call("hover_is_bound", bound_control)),
				"%s receives global hover binding" % bound_control.get_class(),
			)
		var click_stream := load("res://assets/sfx/ui/ui_click.wav") as AudioStream
		_check(click_stream != null, "global button click stream loads")
		if click_stream != null:
			_check(click_stream.get_length() >= 1.0, "global click retains its authored body")
			_check(click_stream.get_length() <= 3.05, "global click stays within the SFX budget")
		var click_starts_before := int(sfx.call("audible_start_count"))
		var feedback := root.get_node_or_null("UiFeedback")
		var feedback_clicks_before := int(feedback.call("click_play_count")) if feedback != null else -1
		button.pressed.emit()
		await process_frame
		_check(
			int(sfx.call("audible_start_count")) == click_starts_before + 1,
			"enabled button activation did not start exactly one click voice",
		)
		_check(sfx.call("last_resolved_id") == &"ui_click", "button activation did not resolve to ui_click")
		_check(
			feedback != null and int(feedback.call("click_play_count")) == feedback_clicks_before + 1,
			"UiFeedback did not own the global button click",
		)
		_check(bool(sfx.call("hover_target_eligible", button)), "enabled button is hover eligible")
		var hover_plays_before := int(sfx.call("hover_play_count"))
		var aura_starts_before := int(sfx.call("audible_start_count"))
		button.mouse_entered.emit()
		await process_frame
		_check(
			int(sfx.call("hover_play_count")) == hover_plays_before,
			"hovering an eligible button replayed the removed aura cue",
		)
		_check(int(sfx.call("audible_start_count")) == aura_starts_before, "button hover consumed an audio voice")
		var option_button := hover_controls[4] as OptionButton
		option_button.mouse_entered.emit()
		await process_frame
		_check(
			int(sfx.call("hover_play_count")) == hover_plays_before,
			"moving between controls replayed the removed aura cue",
		)
		await create_timer(0.08).timeout
		option_button.mouse_entered.emit()
		await process_frame
		_check(
			int(sfx.call("hover_play_count")) == hover_plays_before,
			"hover replayed after the debounce window",
		)
		button.disabled = true
		_check(not bool(sfx.call("hover_target_eligible", button)), "disabled button remains hover eligible")
		button.mouse_exited.emit()
		button.disabled = false
		button.hide()
		var hidden_parent := Control.new()
		var hidden_descendant := Button.new()
		hidden_parent.position = Vector2(4096.0, 4096.0)
		hidden_parent.add_child(hidden_descendant)
		root.add_child(hidden_parent)
		hidden_parent.hide()
		await process_frame
		await create_timer(0.15).timeout
		hidden_descendant.mouse_entered.emit()
		await process_frame
		_check(
			int(sfx.call("hover_play_count")) == hover_plays_before,
			"controls hidden by an ancestor remain silent on hover",
		)
		hidden_parent.queue_free()
		var slider := hover_controls[1] as HSlider
		slider.editable = false
		_check(not bool(sfx.call("hover_target_eligible", slider)), "non-editable slider remains hover eligible")
		slider.editable = true
		_check(bool(sfx.call("hover_target_eligible", slider)), "re-enabled slider is not hover eligible")
		custom_control.set_meta(&"sfx_hover_disabled", true)
		_check(not bool(sfx.call("hover_target_eligible", custom_control)), "hover opt-out metadata is ignored")
		var dynamic_control := Control.new()
		dynamic_control.position = Vector2(4096.0, 4096.0)
		dynamic_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dynamic_control.focus_mode = Control.FOCUS_NONE
		root.add_child(dynamic_control)
		await process_frame
		_check(bool(sfx.call("hover_is_bound", dynamic_control)), "initially inert controls bind safely")
		dynamic_control.mouse_filter = Control.MOUSE_FILTER_STOP
		dynamic_control.focus_mode = Control.FOCUS_ALL
		await create_timer(0.15).timeout
		dynamic_control.mouse_entered.emit()
		await process_frame
		_check(
			int(sfx.call("hover_play_count")) == hover_plays_before,
			"dynamically enabled control replayed the removed aura cue",
		)
		_check(int(sfx.call("audible_start_count")) == aura_starts_before, "hover silence consumed an audio voice")
		dynamic_control.queue_free()
		for control: Control in hover_controls:
			control.queue_free()
		await process_frame
		sfx.call("stop_all")
		for _frame: int in range(16):
			await process_frame
		await create_timer(0.5).timeout
	call_deferred("_finish")


func _finish() -> void:
	if _failures.is_empty():
		print("UI_AUDIO_DIRECTION_TEST_OK")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
