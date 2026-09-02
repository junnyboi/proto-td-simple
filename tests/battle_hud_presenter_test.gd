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
