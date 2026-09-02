extends SceneTree

const AetheriaThemeType := preload("res://scripts/ui/components/aetheria_theme.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var host := Control.new()
	host.theme = AetheriaThemeType.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(host)

	var target := Control.new()
	target.name = "TutorialStyleTarget"
	target.position = Vector2(72.0, 96.0)
	target.size = Vector2(240.0, 120.0)
	host.add_child(target)

	var tutorial_script := load("res://scripts/ui/components/command_center_tutorial.gd")
	_check(tutorial_script != null, "command tutorial script failed to load")
	if tutorial_script == null:
		host.queue_free()
		await process_frame
		_finish()
		return
	var tutorial := tutorial_script.new() as Control
	host.add_child(tutorial)
	var targets: Array[Control] = [target]
	var steps: Array[Dictionary] = [
		{
			"id": &"surface",
			"step_key": &"ui.onboarding.command.mission.step",
			"step_fallback": "1 / 1  SURFACE",
			"title_key": &"ui.onboarding.command.mission.title",
			"title_fallback": "Tutorial surface",
			"body_key": &"ui.onboarding.command.mission.body",
			"body_fallback": "Tutorial surface style probe.",
			"action_key": &"ui.onboarding.command.done",
			"action_fallback": "DONE",
		},
	]
	_check(
		bool(tutorial.call(
			"setup_custom",
			"TutorialSurfaceStyleProbe",
			targets,
			steps,
			&"command_tutorial_completed",
			&"ui.onboarding.command.a11y",
			"Tutorial surface style probe",
			"user://tutorial_surface_style_test.cfg",
			true,
		)),
		"command tutorial style fixture failed to initialize",
	)
	for _frame: int in range(3):
		await process_frame

	var card := tutorial.find_child("TutorialCallout", true, false) as PanelContainer
	_check(card != null, "tutorial callout is missing")
	if card != null:
		_check_surface(card.get_theme_stylebox(&"panel"), "tutorial callout", 12)

	for button_name: String in ["TutorialSkip", "TutorialPrimary"]:
		var button := tutorial.find_child(button_name, true, false) as Button
		_check(button != null, "%s is missing" % button_name)
		if button == null:
			continue
		for style_name: StringName in [
			&"normal", &"hover", &"pressed", &"hover_pressed", &"focus", &"disabled",
		]:
			_check_surface(
				button.get_theme_stylebox(style_name),
				"%s %s" % [button_name, style_name],
				8,
				style_name != &"focus",
			)
		_check(
			button.get_theme_color(&"font_color").is_equal_approx(Color("f5efe1")),
			"%s does not use ivory text" % button_name,
		)

	host.queue_free()
	await process_frame
	_finish()


func _check_surface(
	raw_style: StyleBox,
	context: String,
	minimum_radius: int,
	require_gold_border: bool = true,
) -> void:
	var surface := raw_style as StyleBoxFlat
	_check(surface != null, "%s still uses a stylized frame" % context)
	if surface == null:
		return
	_check(
		surface.bg_color.a > 0.0 and surface.bg_color.a < 1.0,
		"%s background is not translucent" % context,
	)
	if require_gold_border:
		_check(
			surface.border_color.r > surface.border_color.b
			and surface.border_color.g > surface.border_color.b,
			"%s border is not gold (%s)" % [context, surface.border_color.to_html(true)],
		)
	_check(
		surface.get_corner_radius(CORNER_TOP_LEFT) >= minimum_radius,
		"%s border is not rounded" % context,
	)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("TUTORIAL_SURFACE_STYLE_TEST_OK")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)
