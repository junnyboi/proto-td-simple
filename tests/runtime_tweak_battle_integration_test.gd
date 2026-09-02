extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var tweaks := root.get_node_or_null("TweakControls")
	var game := root.get_node_or_null("Game")
	_check(tweaks != null and game != null, "required autoloads are unavailable")
	if tweaks == null or game == null:
		_finish()
		return
	tweaks.call("reset_all")
	tweaks.call("set_value", &"gameplay.base_hp", 18)
	tweaks.call("set_value", &"player.attack_multiplier", 2.0)
	tweaks.call("set_value", &"enemies.health_multiplier", 2.0)
	tweaks.call("set_value", &"environment.backdrop_color", Color("203050"))
	tweaks.call("set_value", &"ui.hud_opacity", 0.75)
	game.call("start_battle", &"s2", true)
	for _frame: int in range(16):
		await process_frame
	var battle := game.get("content") as Node
	_check(battle != null and bool(battle.get("startup_succeeded")), "tuned battle did not start")
	if battle != null:
		var model := battle.get("model") as BattleModel
		var operators: Dictionary = battle.get("_op_defs")
		var enemies: Dictionary = battle.get("_enemy_defs")
		var backdrop := battle.find_child("Backdrop", true, false) as ColorRect
		var hud := battle.find_child("BattleHud", true, false) as Label
		_check(model != null and model.base_hp == 18, "next-battle core health did not reach BattleModel")
		_check((operators[&"recruit"] as OperatorDef).atk == 8, "next-deploy attack tuning did not reach the runtime catalog")
		_check((enemies[&"grunt"] as EnemyDef).hp == 80, "next-spawn health tuning did not reach the runtime catalog")
		_check(backdrop != null and backdrop.color.is_equal_approx(Color("203050")), "live environment color did not reach BattleView")
		_check(hud != null and is_equal_approx(hud.modulate.a, 0.75), "live HUD opacity did not reach BattleView")
		_check(hud != null and hud.text.contains("[TWEAKED]"), "battle integrity marker is missing")
		_check((tweaks.get("launcher_button") as Button).visible, "global launcher disappeared in battle")
		battle.queue_free()
		game.set("content", null)
		game.set("current_battle", null)
		game.set("pending_stage", null)
	var music := root.get_node_or_null("Music")
	if music != null:
		music.call("stop")
	var sfx := root.get_node_or_null("Sfx")
	if sfx != null:
		sfx.call("stop_all")
	for _frame: int in range(16):
		await process_frame
	tweaks.call("reset_all")
	tweaks.call("flush_now")
	_finish()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("RUNTIME_TWEAK_BATTLE_INTEGRATION_TEST_OK")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)
