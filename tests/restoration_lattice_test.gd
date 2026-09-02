extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_stage_contract_and_rotation()
	_test_restoration_cycles()
	_test_runtime_asset_and_projection()
	_test_campaign_context_capacity()
	if _failures.is_empty():
		print("RESTORATION_LATTICE_TEST_OK")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)


func _test_stage_contract_and_rotation() -> void:
	for stage_index: int in range(9, 11):
		var authored := load("res://data/stages/s%d.tres" % stage_index) as StageDef
		_check(authored != null, "Act II stage failed to load: s%d" % stage_index)
	var stage := _stage_fixture()
	_check(stage.restoration_contract_errors().is_empty(), "valid lattice contract was rejected")
	var portrait := stage.clockwise_rotated_copy()
	_check(
		portrait.restoration_cells == PackedVector2Array([Vector2(0, 1)]),
		"portrait copy did not rotate the restoration cell with the stage",
	)
	_check(
		portrait.restoration_heal_amount == stage.restoration_heal_amount
		and portrait.restoration_interval_ticks == stage.restoration_interval_ticks,
		"portrait copy changed restoration tuning",
	)
	_check(portrait.restoration_contract_errors().is_empty(), "rotated lattice contract is invalid")

	var invalid := _stage_fixture()
	invalid.restoration_cells = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 0)])
	var errors := invalid.restoration_contract_errors()
	_check(errors.size() == 2, "invalid spawn and duplicate lattice cells were not both rejected")


func _test_restoration_cycles() -> void:
	var stage := _stage_fixture()
	var model := _model_fixture(stage)
	_check(model != null, "restoration fixture model failed to create")
	if model == null:
		return
	model.step()
	_check(model.enemies.size() == 3, "restoration fixture enemies did not spawn")
	if model.enemies.size() != 3:
		return
	var hostile := model.enemies[0] as EnemyState
	var aerial := model.enemies[1] as EnemyState
	var full := model.enemies[2] as EnemyState
	for enemy: EnemyState in model.enemies:
		enemy.progress_units = Pathing.PROGRESS_SCALE
		enemy.hp = 50
	full.hp = full.hp_max
	var before_due_hash := model.state_hash()
	_step_through_tick(model, stage.restoration_interval_ticks)
	_check(hostile.hp == 58, "due lattice cycle did not repair hostile ground enemy by 8 HP")
	_check(aerial.hp == 50, "lattice incorrectly repaired an aerial enemy")
	_check(full.hp == full.hp_max, "lattice exceeded the full-health clamp")
	_check(model.state_hash() != before_due_hash, "restoration HP mutation was absent from battle hash")

	hostile.hp = 97
	_step_through_tick(model, stage.restoration_interval_ticks * 2)
	_check(hostile.hp == hostile.hp_max, "restoration did not clamp to enemy maximum HP")

	var replay := _model_fixture(stage)
	replay.step()
	for enemy: EnemyState in replay.enemies:
		enemy.progress_units = Pathing.PROGRESS_SCALE
		enemy.hp = 50
	(replay.enemies[2] as EnemyState).hp = (replay.enemies[2] as EnemyState).hp_max
	_step_through_tick(replay, stage.restoration_interval_ticks)
	_check((replay.enemies[0] as EnemyState).hp == 58, "deterministic replay restoration diverged")


func _test_runtime_asset_and_projection() -> void:
	var texture := load("res://assets/world/act2/restoration_lattice_seal.webp") as Texture2D
	_check(texture != null, "restoration lattice runtime texture failed to load")
	if texture != null:
		_check(
			Vector2i(texture.get_width(), texture.get_height()) == Vector2i(600, 556),
			"restoration runtime source is not the approved 600×556 derivative",
		)
	var grid_root := Node2D.new()
	root.add_child(grid_root)
	var built := IsoGridBuilder.build_stage(grid_root, _stage_fixture())
	_check(built, "isometric renderer rejected a valid restoration stage")
	var seal := grid_root.get_node_or_null("RestorationLattice_1_0") as TextureRect
	_check(seal != null, "renderer omitted the authored restoration seal")
	if seal != null:
		_check(seal.size == Vector2(72.0, 40.0), "restoration seal display footprint drifted")
		_check(
			seal.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS,
			"restoration seal lost mipmapped linear filtering",
		)
		_check(seal.mouse_filter == Control.MOUSE_FILTER_IGNORE, "restoration seal intercepts input")
	root.remove_child(grid_root)
	grid_root.free()


func _test_campaign_context_capacity() -> void:
	var context := CampaignRuntimeContext.build()
	_check(not context.is_empty(), "campaign context rejected the generalized stage catalog")
	if context.is_empty():
		return
	var authored_count := 0
	var directory := DirAccess.open("res://data/stages")
	if directory != null:
		for filename: String in directory.get_files():
			var source := filename.trim_suffix(".remap")
			if not source.ends_with(".tres"):
				continue
			var stage := load("res://data/stages/%s" % source) as StageDef
			if stage != null and stage.campaign_index >= 1:
				authored_count += 1
	_check(
		(context["stage_order"] as Array).size() == authored_count,
		"V3 context omitted authored campaign stages",
	)
	var legacy_context: Dictionary = context["legacy_context"]
	_check(
		(legacy_context.get("stage_order", []) as Array).size() == 8,
		"legacy context expanded beyond the immutable Act I boundary",
	)


func _stage_fixture() -> StageDef:
	var stage := StageDef.new()
	stage.id = &"restoration_fixture"
	stage.grid_rows = PackedStringArray(["SGB"])
	stage.paths = [PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(2, 0)])]
	stage.waves = [
		{"tick": 0, "enemy_id": &"hostile", "path_idx": 0},
		{"tick": 0, "enemy_id": &"aerial", "path_idx": 0},
		{"tick": 0, "enemy_id": &"full", "path_idx": 0},
	]
	stage.wave_starts = PackedInt32Array([0])
	stage.leak_limit = 10
	stage.restoration_cells = PackedVector2Array([Vector2(1, 0)])
	stage.restoration_heal_amount = 8
	stage.restoration_interval_ticks = 3
	return stage


func _model_fixture(stage: StageDef) -> BattleModel:
	var enemy_defs := {}
	for enemy_id: StringName in [&"hostile", &"aerial", &"full"]:
		var definition := EnemyDef.new()
		definition.id = enemy_id
		definition.hp = 100
		definition.speed_tiles_per_s = 0.0
		definition.aerial = enemy_id == &"aerial"
		definition.sprite_id = &"drone" if definition.aerial else &"grunt"
		enemy_defs[enemy_id] = definition
	return BattleModel.create(stage, [], 3309, GameConfig.new(), enemy_defs)


func _step_through_tick(model: BattleModel, due_tick: int) -> void:
	while model.tick <= due_tick and model.result == BattleModel.Result.RUNNING:
		model.step()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
