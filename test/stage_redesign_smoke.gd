extends SceneTree

var EXPECTED_ROWS := {
	&"s1": PackedStringArray(["........", "SGGG....", "..EGE...", "...GGGGB", "........"]),
	&"s2": PackedStringArray(["..E.......", "SGGGG.....", "...XGXE...", "....GGGGGB", ".........."]),
	&"s3": PackedStringArray(["..........", "SGGG......", "..XGXE....", "...GGGGGGB", "..XGX.....", "SGGG......"]),
	&"s4": PackedStringArray(["...........", "SGGGGGGGGGB", "..E.XEX.E..", ".....GGGGGB", "SGGGGG.....", "..........."]),
	&"s5": PackedStringArray(["............", "SGGGGG......", "...E.GX.....", ".....GX.E...", ".....GGGGGGB", "............"]),
	&"s6": PackedStringArray(["............", "SGGGG.......", "...EGX.E....", "....GGGGGGGB", "...EGX......", "SGGGG......."]),
	&"s7": PackedStringArray(["SGGGGGG.....", "SGGGG.G.....", "...EGXGE....", "....GGGGGGGB", "...EGX..E...", "SGGGG.......", "............"]),
	&"s8": PackedStringArray([".............", "SGGGG...E....", "....GEXX.X...", "SGGGGGGGGGGGB", "......GXX.E..", "SGGGGGG......", "............."]),
	&"s9": PackedStringArray(["............", "SGGGG.......", "..EXG.XE....", "....GGGGGGGB", "...XG..X.E..", "SGGGG.......", "............"]),
	&"s10": PackedStringArray([".............", "SGGGGG.......", "..E.XG.EX....", "...GGGGGGGGGB", "...GX...XE...", "SGGG.E.......", "............."]),
	&"s11": PackedStringArray(["SGGGGGGGGGGGB", "..E..X..E....", "SGGGGGG......", "......GX..E..", "....GGGGGGGGB", "..EXG..XE....", "....G........", "SGGGG........"]),
	&"s12": PackedStringArray(["..............", "SGGGGG........", "..E.XGX.E.....", ".....G.....E..", "SGGGGGGGGGGGGB", "...EX.XGX.....", ".......G.E....", "SGGGGGGG......"]),
	&"s13": PackedStringArray(["..............", "SGGGGGGGGG....", "..E.X.E.XG....", ".........GE...", "......GGGGGGGB", "...E.XGX...E..", "......G..EX...", "SGGGGGG......."]),
	&"s14": PackedStringArray(["SGGGGGGGGGGGGB", "..E.X..E......", "........X.E...", "SGGGGGGGG.....", "..E.X.EXG.....", ".....GGGGGGGGB", "...EXG..X.E...", ".....G........", "SGGGGG........"]),
	&"s15": PackedStringArray(["SGGGGGG........", "..E..XG.E......", "SGGGG.GX...E...", "...XG.G..X.....", "..E.GGGGGGGGGGB", ".....X..GXG.E..", "SGGGGGGGG.GX...", "...E...E..G....", "SGGGGGGGGGG...."]),
	&"s16": PackedStringArray(["SGGGGGGG........", "..E.X..G.E......", "SGGGGG.GX...E...", "....XG.G..X.....", "..E..GGGGGGGGGGB", "......X..GXG.E..", "SGGGGGGGGG.GX...", "...E....E..G....", "SGGGGGGGGGGG...."]),
}
var EXPECTED_PATH_COUNTS := {
	&"s1": 1, &"s2": 1, &"s3": 2, &"s4": 2,
	&"s5": 1, &"s6": 2, &"s7": 3, &"s8": 3,
	&"s9": 2, &"s10": 2, &"s11": 3, &"s12": 3,
	&"s13": 2, &"s14": 3, &"s15": 4, &"s16": 4,
}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures := PackedStringArray()
	var topology_owners := {}
	var stages := {}
	for stage_number: int in range(1, 17):
		var stage_id := StringName("s%d" % stage_number)
		var stage := load("res://data/stages/%s.tres" % stage_id) as StageDef
		if stage == null:
			failures.append("failed to load %s" % stage_id)
			continue
		stages[stage_id] = stage
		_validate_stage(stage, failures)
		var signature := _topology_signature(stage)
		if topology_owners.has(signature):
			failures.append(
				"duplicate topology: %s and %s" % [topology_owners[signature], stage_id]
			)
		else:
			topology_owners[signature] = stage_id
	_validate_design_contracts(stages, failures)
	if failures.is_empty():
		print("STAGE_REDESIGN_SMOKE_OK")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _validate_stage(stage: StageDef, failures: PackedStringArray) -> void:
	if not EXPECTED_ROWS.has(stage.id) or stage.grid_rows != EXPECTED_ROWS[stage.id]:
		failures.append("unexpected grid rows: %s" % stage.id)
	if stage.paths.size() != int(EXPECTED_PATH_COUNTS.get(stage.id, -1)):
		failures.append("unexpected path count: %s" % stage.id)
	var size := stage.grid_size()
	if size == Vector2i.ZERO:
		failures.append("empty grid: %s" % stage.id)
	for row: String in stage.grid_rows:
		if row.length() != size.x:
			failures.append("non-rectangular grid: %s" % stage.id)
	for path_index: int in stage.paths.size():
		var path := stage.path_cells(path_index)
		if path.size() < 2:
			failures.append("path too short: %s:%d" % [stage.id, path_index])
			continue
		if stage.tile_at(path.front()) != StageDef.Tile.SPAWN:
			failures.append("path does not start on SPAWN: %s:%d" % [stage.id, path_index])
		if stage.tile_at(path.back()) != StageDef.Tile.BASE:
			failures.append("path does not end on BASE: %s:%d" % [stage.id, path_index])
		for point_index: int in path.size():
			if not stage.is_enemy_walkable(path[point_index]):
				failures.append("path crosses non-walkable cell: %s:%d" % [stage.id, path_index])
			if point_index > 0:
				var step := path[point_index] - path[point_index - 1]
				if absi(step.x) + absi(step.y) != 1:
					failures.append("path step is not adjacent: %s:%d" % [stage.id, path_index])
	var previous_tick := -1
	for wave: Dictionary in stage.waves:
		var tick := int(wave.get("tick", -1))
		var path_idx := int(wave.get("path_idx", -1))
		if tick < previous_tick:
			failures.append("waves are not authored in chronological order: %s" % stage.id)
		previous_tick = tick
		if path_idx < 0 or path_idx >= stage.paths.size():
			failures.append("wave path index is invalid: %s" % stage.id)
		var enemy_id := StringName(wave.get("enemy_id", &""))
		if not ResourceLoader.exists("res://data/enemies/%s.tres" % enemy_id):
			failures.append("wave enemy is missing: %s:%s" % [stage.id, enemy_id])
	if stage.wave_starts.is_empty() or stage.wave_starts[0] != 0:
		failures.append("wave starts must begin at zero: %s" % stage.id)
	for index: int in range(1, stage.wave_starts.size()):
		if stage.wave_starts[index] <= stage.wave_starts[index - 1]:
			failures.append("wave starts are not ascending: %s" % stage.id)
	for error: String in stage.restoration_contract_errors():
		failures.append("restoration contract invalid %s: %s" % [stage.id, error])
	for error: String in stage.high_threat_contract_errors():
		failures.append("high-threat contract invalid %s: %s" % [stage.id, error])
	if stage.id in [&"s1", &"s2", &"s3"]:
		var theme := load("res://data/presentation/%s_world_theme.tres" % stage.id) as StageArtTheme
		if theme == null:
			failures.append("required theme missing: %s" % stage.id)
		else:
			for error: String in theme.validation_errors(stage):
				failures.append("theme invalid %s: %s" % [stage.id, error])


func _validate_design_contracts(stages: Dictionary, failures: PackedStringArray) -> void:
	var s1 := stages.get(&"s1") as StageDef
	var s3 := stages.get(&"s3") as StageDef
	var s5 := stages.get(&"s5") as StageDef
	var s6 := stages.get(&"s6") as StageDef
	var s7 := stages.get(&"s7") as StageDef
	var s8 := stages.get(&"s8") as StageDef
	if s1 != null:
		var ranged := load("res://data/operators/sniper_1.tres") as OperatorDef
		var elevated_cells: Array[Vector2i] = [Vector2i(2, 2), Vector2i(4, 2)]
		if _tile_count(s1, StageDef.Tile.ELEVATED) != elevated_cells.size():
			failures.append("S1 must expose both raised platforms for elevated deployment")
		if ranged == null or ranged.placement != OperatorDef.Placement.ELEVATED:
			failures.append("S1 ranged deployment fixture is not elevated")
		else:
			var ranged_model := BattleModel.create(
				s1,
				[&"sniper_1"],
				3302,
				load("res://data/config/game.tres") as GameConfig,
				{},
				{&"sniper_1": ranged},
			)
			if ranged_model == null:
				failures.append("S1 ranged BattleModel fixture failed to initialize")
			else:
				ranged_model.dp = ranged_model.config.dp_cap
			for cell: Vector2i in elevated_cells:
				if not s1.operator_cell_in_domain(ranged, cell):
					failures.append("S1 raised platform rejects ranged deployment: %s" % cell)
				if ranged_model != null and not ranged_model.can_deploy_at(&"sniper_1", cell):
					failures.append("S1 BattleModel rejects ranged deployment: %s" % cell)
	if s3 != null and _shared_path_cells(s3).size() < 2:
		failures.append("S3 must contain a true multi-path choke")
	if s5 != null:
		var spellcaster_ticks := _enemy_ticks(s5, &"spellcaster")
		if spellcaster_ticks.is_empty() or spellcaster_ticks.max() - spellcaster_ticks.min() < 900:
			failures.append("S5 Channeler waves must remain distributed across the encounter")
	if s6 != null:
		var heavy_ticks := _enemy_ticks(s6, &"heavy")
		if heavy_ticks.size() != 2:
			failures.append("S6 must have two heavy-led escort columns")
		for heavy_tick: int in heavy_ticks:
			if not _has_same_path_escort(s6, heavy_tick, 120):
				failures.append("S6 heavy lacks a same-path escort column at %d" % heavy_tick)
	if s7 != null:
		if s7.paths.size() != 3 or _enemy_ids(s7).size() < 5:
			failures.append("S7 must exercise three fronts and at least five enemy types")
		if _shared_path_cells(s7).is_empty():
			failures.append("S7 must converge into a contested corridor")
	if s8 != null:
		if s8.paths.size() != 3 or _enemy_ticks(s8, &"mini_boss").size() != 1:
			failures.append("S8 must contain three approaches and one Gatecrasher")
		var boss_tick := int(_enemy_ticks(s8, &"mini_boss")[0])
		if not _has_same_path_escort(s8, boss_tick, 180):
			failures.append("S8 boss must have a same-path escort")


func _tile_count(stage: StageDef, tile: StageDef.Tile) -> int:
	var count := 0
	var size := stage.grid_size()
	for y: int in size.y:
		for x: int in size.x:
			if stage.tile_at(Vector2i(x, y)) == tile:
				count += 1
	return count


func _shared_path_cells(stage: StageDef) -> Array[Vector2i]:
	var owners := {}
	for path_index: int in stage.paths.size():
		for cell: Vector2i in stage.path_cells(path_index):
			owners[cell] = int(owners.get(cell, 0)) + 1
	var shared: Array[Vector2i] = []
	for cell: Vector2i in owners:
		if int(owners[cell]) > 1:
			shared.append(cell)
	return shared


func _enemy_ticks(stage: StageDef, enemy_id: StringName) -> Array[int]:
	var ticks: Array[int] = []
	for wave: Dictionary in stage.waves:
		if StringName(wave["enemy_id"]) == enemy_id:
			ticks.append(int(wave["tick"]))
	return ticks


func _enemy_ids(stage: StageDef) -> Dictionary:
	var ids := {}
	for wave: Dictionary in stage.waves:
		ids[StringName(wave["enemy_id"])] = true
	return ids


func _has_same_path_escort(stage: StageDef, leader_tick: int, max_gap: int) -> bool:
	var leader_path := -1
	for wave: Dictionary in stage.waves:
		if int(wave["tick"]) == leader_tick:
			leader_path = int(wave["path_idx"])
			break
	for wave: Dictionary in stage.waves:
		var tick := int(wave["tick"])
		if (
			tick > leader_tick
			and tick - leader_tick <= max_gap
			and int(wave["path_idx"]) == leader_path
			and StringName(wave["enemy_id"]) != &"heavy"
			and StringName(wave["enemy_id"]) != &"mini_boss"
		):
			return true
	return false


func _topology_signature(stage: StageDef) -> String:
	var path_rows: Array = []
	for path_index: int in stage.paths.size():
		var cells: Array = []
		for cell: Vector2i in stage.path_cells(path_index):
			cells.append([cell.x, cell.y])
		path_rows.append(cells)
	return JSON.stringify({"grid": Array(stage.grid_rows), "paths": path_rows})
