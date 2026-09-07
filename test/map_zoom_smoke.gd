extends SceneTree

const NAV := preload("res://scripts/view/map_navigator.gd")
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var source := load("res://data/stages/s8.tres") as StageDef
	for viewport: Vector2 in [Vector2(1280, 720), Vector2(720, 1280)]:
		var nav: RefCounted = NAV.new()
		var stage := source.copy_for_viewport(viewport)
		nav.relayout(stage, viewport)
		var initial: float = nav.scale
		var wheel := InputEventMouseButton.new()
		wheel.position = viewport * 0.5
		wheel.button_index = MOUSE_BUTTON_WHEEL_UP
		wheel.pressed = true
		_check(nav.handle_input(wheel), "wheel zoom was not consumed")
		_check(nav.scale > initial, "wheel up did not zoom in")
		wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
		nav.handle_input(wheel)
		_check(is_equal_approx(nav.scale, initial), "wheel down did not reverse zoom")
		wheel.shift_pressed = true
		nav.handle_input(wheel)
		_check(is_equal_approx(nav.scale, initial), "Shift-wheel changed zoom")
		var magnify := InputEventMagnifyGesture.new()
		magnify.position = viewport * 0.5
		magnify.factor = 2.0
		_check(nav.handle_input(magnify), "trackpad spread was not consumed")
		_check(is_equal_approx(nav.scale, initial * 2.0), "trackpad spread did not zoom in")
		nav.pan = nav.bounds.position + nav.bounds.size * 0.5
		var anchor: Vector2 = (magnify.position - nav.root_position()) / nav.scale
		magnify.factor = 1.1
		nav.handle_input(magnify)
		_check((nav.root_position() + anchor * nav.scale).distance_to(magnify.position) < 0.01, "pointer anchor drifted away from bounds")
		nav.zoom_at(magnify.position, 100.0)
		_check(is_equal_approx(nav.zoom, NAV.MAX_ZOOM), "upper zoom bound failed")
		nav.zoom_at(magnify.position, 0.001)
		_check(is_equal_approx(nav.zoom, NAV.MIN_ZOOM), "lower zoom bound failed")
		nav.zoom_at(magnify.position, NAN)
		_check(is_finite(nav.scale), "invalid gesture poisoned map scale")
		nav.relayout(stage, viewport * 0.8)
		_check(is_equal_approx(nav.zoom, NAV.MIN_ZOOM), "resize reset zoom")
		_check(not nav.is_out_of_bounds(), "resize left pan outside bounds")
	await _battle_check()
	for failure: String in failures:
		push_error(failure)
	if failures.is_empty():
		print("MAP_ZOOM_SMOKE_OK")
	quit(0 if failures.is_empty() else 1)


func _battle_check() -> void:
	root.size = Vector2i(1280, 720)
	var game := root.get_node("Game")
	root.get_node("Music").set_enabled(false)
	game.start_battle(&"s8", true)
	for frame: int in 12:
		await process_frame
	var battle: Node = game.content
	_check(battle != null and battle.startup_succeeded, "live battle failed to start")
	if battle == null or not battle.startup_succeeded:
		return
	battle.set_physics_process(false)
	var hud := battle.find_child("BattleHud", true, false) as Control
	var deck := battle.find_child("DeploymentCommandDeck", true, false) as Control
	var hud_rect := hud.get_global_rect()
	var deck_rect := deck.get_global_rect()
	var grid := battle.get_node("GridRoot") as Node2D
	var initial_scale := grid.scale
	var ui_pinch := InputEventMagnifyGesture.new()
	ui_pinch.position = deck_rect.get_center()
	ui_pinch.factor = 1.2
	Input.parse_input_event(ui_pinch)
	await process_frame
	_check(grid.scale == initial_scale, "pinch over deployment UI leaked to battlefield")
	var wheel := InputEventMouseButton.new()
	wheel.position = Vector2(640, 360)
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	battle._unhandled_input(wheel)
	_check(grid.scale.x > initial_scale.x, "battle did not apply wheel zoom")
	_check(hud.get_global_rect() == hud_rect and deck.get_global_rect() == deck_rect, "zoom changed HUD/deck geometry")
	var cell := Vector2i(3, 3)
	_check(battle.cell_at(battle.cell_center(cell)) == cell, "tile picking diverged after zoom")
	for factor: float in [0.5, 2.5]:
		battle._map_nav.zoom_at(wheel.position, factor / battle._map_nav.zoom)
		battle._apply_map_transform()
		_check(hud.get_global_rect() == hud_rect and deck.get_global_rect() == deck_rect, "zoom extreme changed HUD geometry")
		if DisplayServer.get_name() != "headless":
			await process_frame
			RenderingServer.force_draw()
			var path := OS.get_environment("PROTO_TD_TEST_ARTIFACT_DIR").path_join("zoom-%s.png" % factor)
			_check(root.get_texture().get_image().save_png(path) == OK, "zoom capture failed")


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
