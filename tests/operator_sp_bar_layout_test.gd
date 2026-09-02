extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var battle: Node = (load("res://scripts/view/battle_view.gd") as Script).new()
	var body := ColorRect.new()
	body.size = Vector2(64.0, 80.0)
	battle.call("_add_sp_bar", body)
	var bg := body.get_node("SpBarBg") as ColorRect
	var fill := bg.get_node("SpBarFill") as ColorRect
	_check(bg.size.is_equal_approx(Vector2(32.0, 2.5)), "SP bar is not half-sized")
	_check(bg.position.is_equal_approx(Vector2(16.0, 83.0)), "SP bar is not centered")
	_check(is_equal_approx(fill.size.y, 2.5), "SP fill height does not match its background")
	body.size = Vector2(80.0, 100.0)
	battle.call("_layout_sp_bar", body)
	_check(bg.size.is_equal_approx(Vector2(40.0, 2.5)), "resized SP bar lost half width")
	_check(bg.position.is_equal_approx(Vector2(20.0, 103.0)), "resized SP bar lost centering")
	var unit := UnitState.new()
	unit.sp_cost = 10
	unit.sp = 5
	(load("res://scripts/view/skill_ready_feedback.gd") as Script).new().call(
		"update",
		body,
		unit,
		Color("f4b41b"),
		Color.WHITE,
	)
	_check(is_equal_approx(fill.size.x, 20.0), "SP fill still uses the full body width")
	body.free()
	battle.free()
	_finish()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("OPERATOR_SP_BAR_LAYOUT_TEST_OK")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)
