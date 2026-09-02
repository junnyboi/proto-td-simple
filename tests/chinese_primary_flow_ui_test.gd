extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var required_by_file := {
		"res://scripts/ui/stage_select.gd": [
			"ui.campaign.eyebrow", "ui.campaign.progress", "ui.campaign.route_heading",
			"ui.campaign.facts", "ui.campaign.row_locked",
		],
		"res://scripts/view/battle_view.gd": ["ui.battle.wave", "ui.battle.stamp_clear", "ui.battle.stamp_defeat"],
		"res://scripts/ui/battle_controls.gd": ["ui.battle.withdraw_rejected", "ui.battle.confirm_defeat_description", "ui.battle.return_description"],
		"res://scripts/ui/components/lunaris_dialog_sheet.gd": ["ui.dialog.scrollable_details", "ui.dialog.close_without_confirming"],
	}
	for path: String in required_by_file:
		var text := FileAccess.get_file_as_string(path)
		for key: String in required_by_file[path]:
			_check(text.contains(key), "%s does not consume %s" % [path, key])
	var campaign_source := FileAccess.get_file_as_string("res://scripts/ui/stage_select.gd")
	for forbidden: String in ["FIRST STAND · OPERATION ROUTE", "SELECTED OPERATION", "WAVE WINDOWS", "LEAK LIMIT"]:
		_check(not campaign_source.contains(forbidden), "Campaign retained English literal: %s" % forbidden)
	var map_source := FileAccess.get_file_as_string("res://scripts/ui/map_navigation_overlay.gd")
	_check(not map_source.contains("↔") and not map_source.contains("↕"), "Map navigation still depends on text arrow glyphs")
	_finish()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("CHINESE_PRIMARY_FLOW_UI_TEST_OK")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)
