extends SceneTree

const JUICE_LAYER_SCRIPT := preload("res://scripts/view/juice_layer.gd")
const SFX_SCRIPT := preload("res://autoloads/sfx.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures := PackedStringArray()
	_validate_audio(failures)
	_validate_emitters(failures)
	_validate_battle_view_routing(failures)
	if failures.is_empty():
		print("PLACEMENT_FEEDBACK_SMOKE_OK")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _validate_audio(failures: PackedStringArray) -> void:
	var sfx := SFX_SCRIPT.new()
	root.add_child(sfx)
	if not sfx.reload_catalog():
		failures.append("SFX catalog failed to reload")
		sfx.free()
		return
	if sfx.resolved_id_for(&"deploy") != &"deploy_ground":
		failures.append("legacy deploy alias must resolve to deploy_ground")
	for cue_id: StringName in [&"deploy_ground", &"deploy_elevated"]:
		if sfx.resolved_id_for(cue_id) != cue_id:
			failures.append("cue failed to resolve: %s" % cue_id)
			continue
		var path := "res://assets/template/bundled/sfx/combat/%s.wav" % cue_id
		var stream := load(path) as AudioStream
		if stream == null:
			failures.append("cue failed to load: %s" % path)
		elif stream.get_length() < 0.7 or stream.get_length() > 1.3:
			failures.append("cue length out of placement range: %s %.3f" % [cue_id, stream.get_length()])
	var ground := load("res://assets/template/bundled/sfx/combat/deploy_ground.wav") as AudioStream
	var elevated := load("res://assets/template/bundled/sfx/combat/deploy_elevated.wav") as AudioStream
	if ground != null and elevated != null and elevated.get_length() <= ground.get_length():
		failures.append("elevated cue must retain a longer crystalline tail")
	sfx.free()


func _validate_emitters(failures: PackedStringArray) -> void:
	var cfg := load("res://data/juice_config.tres") as JuiceConfig
	if cfg == null:
		failures.append("juice config failed to load")
		return
	var grid := Node2D.new()
	grid.name = "PlacementFeedbackGrid"
	root.add_child(grid)
	var ground_layer := JUICE_LAYER_SCRIPT.new()
	root.add_child(ground_layer)
	ground_layer.setup(cfg, grid)
	ground_layer.placement_ground(Vector2(64, 64))
	if ground_layer.last_placement_profile() != &"ground":
		failures.append("ground profile was not recorded")
	if ground_layer.placement_emitter_count() != cfg.deploy_ground_particles:
		failures.append("ground emitter count mismatch")
	var elevated_layer := JUICE_LAYER_SCRIPT.new()
	root.add_child(elevated_layer)
	elevated_layer.setup(cfg, grid)
	elevated_layer.placement_elevated(Vector2(96, 64))
	if elevated_layer.last_placement_profile() != &"elevated":
		failures.append("elevated profile was not recorded")
	if elevated_layer.placement_emitter_count() != cfg.deploy_elevated_shards + 2:
		failures.append("elevated emitter count must include shards, ring, and beam")
	var transient_root := elevated_layer.get_node_or_null("MapTransientRoot")
	if transient_root == null:
		failures.append("elevated transient root missing")
	else:
		if transient_root.get_node_or_null("PlacementElevatedRing") == null:
			failures.append("elevated ring emitter missing")
		if transient_root.get_node_or_null("PlacementElevatedBeam") == null:
			failures.append("elevated beam emitter missing")
	ground_layer.free()
	elevated_layer.free()
	grid.free()


func _validate_battle_view_routing(failures: PackedStringArray) -> void:
	var script_text := FileAccess.get_file_as_string("res://scripts/view/battle_view.gd")
	for required: String in [
		"_juice.placement_ground(local_center)",
		"Sfx.play(\"deploy_ground\")",
		"_juice.placement_elevated(local_center)",
		"Sfx.play(\"deploy_elevated\")",
	]:
		if required not in script_text:
			failures.append("BattleView placement routing missing: %s" % required)
