extends SceneTree

const BattleHudPresenter := preload("res://scripts/view/battle_hud_presenter.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var i18n := root.get_node_or_null("I18n")
	_check(i18n != null, "I18n autoload is unavailable")
	if i18n == null:
		_finish()
		return
	var snapshot := {
		"base_hp": 9,
		"leaked": 1,
		"leak_limit": 3,
		"dp": 10,
		"killed": 5,
		"result": 0,
	}
	_check(bool(i18n.call("set_locale", &"en-US")), "English locale activation failed")
	_check(
		BattleHudPresenter.text_for(snapshot, Vector2(1280, 720))
		== "LEAKS  1 / 4    DP  10    ELIMINATIONS  5    ACTIVE",
		"wide HUD does not show the actual four-leak defeat threshold",
	)
	_check(
		BattleHudPresenter.text_for(snapshot, Vector2(720, 1280))
		== "LEAKS 1 / 4   DP 10\nELIMS 5   ACTIVE",
		"compact HUD does not show the actual four-leak defeat threshold",
	)
	snapshot["leak_limit"] = 1
	_check(
		BattleHudPresenter.text_for(snapshot, Vector2(1280, 720)).begins_with("LEAKS  1 / 2"),
		"HUD did not adapt to a two-leak defeat threshold",
	)
	_check(bool(i18n.call("set_locale", &"zh-CN")), "Chinese locale activation failed")
	_check(
		BattleHudPresenter.text_for(snapshot, Vector2(1280, 720)).begins_with("漏敌  1 / 2"),
		"Chinese HUD does not expose the leak threshold",
	)
	await _verify_large_counters(i18n)
	_check(bool(i18n.call("set_locale", &"en-US")), "English locale restoration failed")
	_finish()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("BATTLE_HUD_PRESENTER_TEST_OK")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)


func _verify_large_counters(i18n: Node) -> void:
	var text_scale := root.get_node("TextScale")
	var previous_scale := float(text_scale.call("value"))
	var hud := BattleHudPresenter.create(30, 1, Vector2(540, 960))
	root.add_child(hud)
	await process_frame
	var snapshot := {"leaked": 999, "leak_limit": 9999, "dp": 99999999, "killed": 99999999, "result": 2}
	for locale: StringName in [&"en-US", &"zh-CN"]:
		i18n.call("set_locale", locale)
		for scale: float in [0.8, 1.0, 1.2, 1.5]:
			text_scale.call("set_scale", scale)
			await process_frame
			for viewport: Vector2 in [Vector2(540, 960), Vector2(720, 1280), Vector2(960, 420), Vector2(1280, 720)]:
				hud.text = BattleHudPresenter.text_for(snapshot, viewport) + "  [TWEAKED]"
				BattleHudPresenter.relayout(hud, viewport)
				await process_frame
				var context := "%s %.0f%% %s" % [locale, scale * 100, viewport]
				_check(hud.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART and not hud.clip_text, context + ": counters must wrap without clipping")
				_check(Rect2(Vector2.ZERO, viewport).encloses(hud.get_rect()), context + ": HUD escaped the viewport")
				_check(hud.size.x <= viewport.x - 24.0, context + ": HUD lost horizontal margins")
				_check(hud.get_minimum_size().y <= hud.size.y + 0.5, context + ": wrapped lines exceed HUD height")
				_check(hud.get_visible_line_count() == hud.get_line_count(), context + ": a counter line is hidden")
				_check(hud.get_theme_font_size(&"font_size") == roundi(30 * scale), context + ": layout changed accessibility type size")
	hud.queue_free()
	await process_frame
	text_scale.call("set_scale", previous_scale)
