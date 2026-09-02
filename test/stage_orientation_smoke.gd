extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures := PackedStringArray()
	for stage_number: int in range(1, 11):
		var stage_id := "s%d" % stage_number
		var source := load("res://data/stages/%s.tres" % stage_id) as StageDef
		if source == null:
			failures.append("failed to load %s" % stage_id)
			continue
		var landscape := source.copy_for_viewport(Vector2(1280, 720))
		var portrait := source.copy_for_viewport(Vector2(720, 1280))
		if landscape != source:
			failures.append("landscape must use authored resource: %s" % stage_id)
		if portrait == source:
			failures.append("portrait must use an isolated copy: %s" % stage_id)
		_validate_rotated_stage(source, portrait, failures)
		_validate_round_trip(source, failures)
		if stage_number <= 3:
			_validate_rotated_theme(source, portrait, failures)
	if failures.is_empty():
		print("STAGE_ORIENTATION_SMOKE_OK")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _validate_rotated_stage(
	source: StageDef,
	portrait: StageDef,
	failures: PackedStringArray,
) -> void:
	var source_size := source.grid_size()
	var expected_size := Vector2i(source_size.y, source_size.x)
	if portrait.grid_size() != expected_size:
		failures.append("rotated size mismatch: %s" % source.id)
	for y: int in source_size.y:
		for x: int in source_size.x:
			var source_cell := Vector2i(x, y)
			var rotated_cell := StageDef.rotate_cell_clockwise(source_cell, source_size)
			if portrait.tile_at(rotated_cell) != source.tile_at(source_cell):
				failures.append("rotated tile mismatch: %s %s" % [source.id, source_cell])
	if portrait.paths.size() != source.paths.size():
		failures.append("rotated path count mismatch: %s" % source.id)
	else:
		for path_index: int in source.paths.size():
			var source_path := source.path_cells(path_index)
			var rotated_path := portrait.path_cells(path_index)
			if source_path.size() != rotated_path.size():
				failures.append("rotated path size mismatch: %s:%d" % [source.id, path_index])
				continue
			for point_index: int in source_path.size():
				var expected := StageDef.rotate_cell_clockwise(source_path[point_index], source_size)
				if rotated_path[point_index] != expected:
					failures.append(
						"rotated path point mismatch: %s:%d:%d" % [
							source.id, path_index, point_index
						]
					)
			for point_index: int in range(1, rotated_path.size()):
				var step := rotated_path[point_index] - rotated_path[point_index - 1]
				if absi(step.x) + absi(step.y) != 1:
					failures.append("rotated path is not adjacent: %s:%d" % [source.id, path_index])
				if not rotated_path.is_empty():
					if portrait.tile_at(rotated_path.front()) != StageDef.Tile.SPAWN:
						failures.append("rotated path does not start at SPAWN: %s" % source.id)
					if portrait.tile_at(rotated_path.back()) != StageDef.Tile.BASE:
						failures.append("rotated path does not end at BASE: %s" % source.id)
	if portrait.restoration_cells.size() != source.restoration_cells.size():
		failures.append("rotated restoration-cell count mismatch: %s" % source.id)
	else:
		for point_index: int in source.restoration_cells.size():
			var expected := StageDef.rotate_cell_clockwise(
				Vector2i(source.restoration_cells[point_index]), source_size,
			)
			if Vector2i(portrait.restoration_cells[point_index]) != expected:
				failures.append("rotated restoration cell mismatch: %s:%d" % [source.id, point_index])
	_validate_metadata(source, portrait, failures)


func _validate_metadata(
	source: StageDef,
	portrait: StageDef,
	failures: PackedStringArray,
) -> void:
	var fields := [
		"id", "title", "waves", "wave_starts", "leak_limit", "squad_size",
		"recovery_roster", "rewards", "campaign_index", "requires",
		"restoration_heal_amount", "restoration_interval_ticks",
	]
	for field: String in fields:
		if source.get(field) != portrait.get(field):
			failures.append("portrait metadata changed: %s.%s" % [source.id, field])


func _validate_round_trip(source: StageDef, failures: PackedStringArray) -> void:
	var rotated := source
	for _rotation: int in 4:
		rotated = rotated.clockwise_rotated_copy()
	if (
		rotated.grid_rows != source.grid_rows
		or rotated.paths != source.paths
		or rotated.restoration_cells != source.restoration_cells
	):
		failures.append("four-rotation round trip mismatch: %s" % source.id)


func _validate_rotated_theme(
	source: StageDef,
	portrait: StageDef,
	failures: PackedStringArray,
) -> void:
	var theme := load("res://data/presentation/%s_world_theme.tres" % source.id) as StageArtTheme
	if theme == null:
		failures.append("theme missing: %s" % source.id)
		return
	var rotated := theme.clockwise_rotated_copy(source.grid_size())
	for error: String in rotated.validation_errors(portrait):
		failures.append("rotated theme invalid %s: %s" % [source.id, error])
	var expected_spawn := StageDef.rotate_cell_clockwise(theme.spawn_cell, source.grid_size())
	var expected_core := StageDef.rotate_cell_clockwise(theme.core_cell, source.grid_size())
	if rotated.spawn_cell != expected_spawn or portrait.tile_at(rotated.spawn_cell) != StageDef.Tile.SPAWN:
		failures.append("rotated spawn landmark mismatch: %s" % source.id)
	if rotated.core_cell != expected_core or portrait.tile_at(rotated.core_cell) != StageDef.Tile.BASE:
		failures.append("rotated core landmark mismatch: %s" % source.id)
	for cell: Vector2i in rotated.elevated_cells:
		if portrait.tile_at(cell) != StageDef.Tile.ELEVATED:
			failures.append("rotated elevated theme cell mismatch: %s %s" % [source.id, cell])
	for cell: Vector2i in rotated.blocked_cells:
		if portrait.tile_at(cell) != StageDef.Tile.BLOCKED:
			failures.append("rotated blocked theme cell mismatch: %s %s" % [source.id, cell])
