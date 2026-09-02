extends SceneTree

var EXPECTED := {
	&"s9": {
		"waves": PackedInt32Array([1, 2]),
		"warning_id": &"green_cage",
		"warning_asset": &"vfx_high_threat_s9_warning",
		"particle_asset": &"vfx_high_threat_s9_particles",
	},
}

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_stage_contracts()
	_test_asset_contracts()
	await _test_juice_presentation(false)
	await _test_juice_presentation(true)
	for failure: String in _failures:
		push_error(failure)
	if _failures.is_empty():
		print("HIGH_THREAT_WAVE_WARNING_TEST_OK")
		quit(0)
		return
	quit(1)


func _test_stage_contracts() -> void:
	for stage_number: int in range(1, 11):
		var stage_id := StringName("s%d" % stage_number)
		var stage := load("res://data/stages/%s.tres" % stage_id) as StageDef
		_check(stage != null, "%s failed to load" % stage_id)
		if stage == null:
			continue
		_check(
			stage.high_threat_contract_errors().is_empty(),
			"%s high-threat contract rejected: %s" % [stage_id, stage.high_threat_contract_errors()],
		)
		if not EXPECTED.has(stage_id):
			_check(stage.high_threat_wave_indices.is_empty(), "%s gained an unauthored warning" % stage_id)
			_check(stage.high_threat_warning_id.is_empty(), "%s gained an unauthored warning id" % stage_id)
			continue
		var expected: Dictionary = EXPECTED[stage_id]
		_check(
			stage.high_threat_wave_indices == expected["waves"],
			"%s high-threat wave boundaries changed" % stage_id,
		)
		_check(
			stage.high_threat_warning_id == expected["warning_id"],
			"%s warning identity changed" % stage_id,
		)
		for wave_index: int in stage.wave_starts.size():
			_check(
				stage.is_high_threat_wave(wave_index) == stage.high_threat_wave_indices.has(wave_index),
				"%s high-threat lookup disagrees at wave %d" % [stage_id, wave_index],
			)
		var portrait := stage.clockwise_rotated_copy()
		_check(
			portrait.high_threat_wave_indices == stage.high_threat_wave_indices,
			"%s portrait copy changed warning boundaries" % stage_id,
		)
		_check(
			portrait.high_threat_warning_id == stage.high_threat_warning_id,
			"%s portrait copy changed warning identity" % stage_id,
		)


func _test_asset_contracts() -> void:
	for stage_id: StringName in EXPECTED:
		var expected: Dictionary = EXPECTED[stage_id]
		for key: String in ["warning_asset", "particle_asset"]:
			var asset_id := expected[key] as StringName
			_check(Art.size(asset_id) == Vector2i(600, 600), "%s must retain 600px source art" % asset_id)
			var texture := Art.texture(asset_id)
			_check(texture != null, "%s did not resolve through Art" % asset_id)
			if texture != null:
				_check(
					texture.get_width() == 600 and texture.get_height() == 600,
					"%s runtime texture dimensions changed" % asset_id,
				)


func _test_juice_presentation(reduced_motion: bool) -> void:
	var host := Node2D.new()
	host.name = "HighThreatWarningFixture"
	root.add_child(host)
	var grid := Node2D.new()
	grid.name = "Grid"
	grid.scale = Vector2.ONE * 1.5
	host.add_child(grid)
	var juice := JuiceLayer.new()
	juice.name = "Juice"
	host.add_child(juice)
	var config := load("res://data/juice_config.tres") as JuiceConfig
	juice.setup(config, grid)
	var centers: Array[Vector2] = [Vector2(128, 160), Vector2(384, 208)]
	juice.high_threat_warning(
		&"green_cage",
		"CONTAINMENT SURGE",
		"Wave 3 • Restoration pressure rising",
		centers,
		reduced_motion,
	)
	await process_frame
	_check(juice.high_threat_warning_visible(), "warning panel was not visible")
	_check(juice.high_threat_warning_id() == &"green_cage", "warning identity was not retained")
	var panel := juice.get_node_or_null("HighThreatWarning") as Control
	_check(panel != null, "high-threat panel node is missing")
	if panel != null:
		var panel_style := panel.get_theme_stylebox(&"panel")
		_check(panel_style.content_margin_left >= 24.0 and panel_style.content_margin_top >= 24.0 and panel_style.content_margin_right >= 24.0 and panel_style.content_margin_bottom >= 24.0, "high-threat custom frame padding is below 24px")
		var icon := panel.get_node_or_null("Content/ThreatIcon") as TextureRect
		var heading := panel.get_node_or_null("Content/Copy/Heading") as Label
		var detail := panel.get_node_or_null("Content/Copy/Detail") as Label
		_check(icon != null and icon.texture != null, "warning icon is missing")
		_check(
			icon != null and icon.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS,
			"warning icon must use mipmapped linear filtering",
		)
		_check(heading != null and heading.text == "CONTAINMENT SURGE", "warning heading changed")
		_check(detail != null and detail.text.contains("Wave 3"), "warning detail changed")
	var expected_count := centers.size()
	if not reduced_motion:
		expected_count *= 1 + config.high_threat_particles_per_spawn
	_check(
		juice.high_threat_transient_count() == expected_count,
		"%s motion emitted %d warning transients, expected %d"
		% ["reduced" if reduced_motion else "normal", juice.high_threat_transient_count(), expected_count],
	)
	juice.update_high_threat_copy("BLACKOUT CRITICAL", "Wave 3 • Localized refresh")
	if panel != null:
		var refreshed_heading := panel.get_node_or_null("Content/Copy/Heading") as Label
		var refreshed_detail := panel.get_node_or_null("Content/Copy/Detail") as Label
		_check(
			refreshed_heading != null and refreshed_heading.text == "BLACKOUT CRITICAL",
			"warning heading did not refresh in place",
		)
		_check(
			refreshed_detail != null and refreshed_detail.text.contains("Localized refresh"),
			"warning detail did not refresh in place",
		)
	juice.stamp("VICTORY", 0)
	_check(not juice.high_threat_warning_visible(), "result stamp did not clear the warning panel")
	host.queue_free()
	await process_frame
	await process_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
