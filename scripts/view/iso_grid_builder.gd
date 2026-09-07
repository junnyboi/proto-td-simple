class_name IsoGridBuilder
extends RefCounted

## Builds proto-td's static terrain through the custom, textured isometric
## renderer transplanted from proto-isometric. BattleView continues to own
## projection, input, dynamic entities, and relayout.

const StageArtThemeType := preload("res://data/presentation/stage_art_theme.gd")
const ProtoIsometricTerrainScript := preload("res://scripts/view/proto_isometric_terrain.gd")
const EndpointLandmarkScript := preload("res://scripts/view/battle_endpoint_landmark.gd")
const SPAWN_LANDMARK_ID := &"world.act1.spawn"
const CORE_LANDMARK_ID := &"world.act1.core"
const RESTORATION_SEAL := preload("res://assets/template/world/act2/restoration_lattice_seal.webp")
const RESTORATION_DISPLAY_SIZE := Vector2(72.0, 40.0)


static func build_stage(
	grid_root: Node2D,
	stage: StageDef,
	theme_resolver: Callable = Callable(),
	report_error: bool = true,
) -> bool:
	var result := StageArtThemeType.resolve_for(stage, theme_resolver)
	var error := String(result["error"])
	if not error.is_empty():
		if report_error:
			push_error("iso_grid_builder: %s" % error)
		return false
	return build_stage_with_theme(
		grid_root,
		stage,
		result["theme"] as StageArtThemeType,
		report_error,
	)


## Presentation-only seam for callers that already completed theme preflight.
static func build_stage_with_theme(
	grid_root: Node2D,
	stage: StageDef,
	theme: StageArtThemeType,
	report_error: bool = true,
) -> bool:
	var errors := PackedStringArray()
	if grid_root == null:
		errors.append("grid root is null")
	if stage == null:
		errors.append("stage is null")
	elif StageArtThemeType.expects_theme(stage) and theme == null:
		errors.append("required stage art theme was not provided for %s" % stage.id)
	if stage != null and theme != null:
		errors.append_array(theme.validation_errors(stage))
	for path: String in ProtoIsometricTerrainScript.required_texture_paths():
		if not ResourceLoader.exists(path):
			errors.append("proto-isometric terrain asset missing: %s" % path)
	if not errors.is_empty():
		if report_error:
			push_error("iso_grid_builder: invalid isometric terrain setup: %s" % "; ".join(errors))
		return false

	var terrain := ProtoIsometricTerrainScript.new() as Node2D
	terrain.name = "ProtoIsometricTerrain"
	if not bool(terrain.call("configure", stage)):
		if report_error:
			push_error("iso_grid_builder: proto-isometric terrain configuration failed")
		terrain.queue_free()
		return false
	grid_root.add_child(terrain)
	if not _add_restoration_lattices(grid_root, stage):
		if report_error:
			push_error("iso_grid_builder: restoration lattice setup failed")
		return false
	if not _add_endpoint_landmarks(grid_root, stage):
		if report_error:
			push_error("iso_grid_builder: generated endpoint landmark setup failed")
		return false
	return true


static func _add_restoration_lattices(grid_root: Node2D, stage: StageDef) -> bool:
	if stage.restoration_cells.is_empty():
		return true
	if RESTORATION_SEAL == null or not stage.restoration_contract_errors().is_empty():
		return false
	for point: Vector2 in stage.restoration_cells:
		var cell := Vector2i(point)
		var rect := TextureRect.new()
		rect.name = "RestorationLattice_%d_%d" % [cell.x, cell.y]
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		rect.texture = RESTORATION_SEAL
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_SCALE
		rect.size = RESTORATION_DISPLAY_SIZE
		rect.position = IsoProjection.face_center(cell) - rect.size * 0.5
		rect.modulate = Color(0.92, 1.0, 0.92, 0.88)
		rect.z_index = IsoProjection.tile_z(cell) + 1
		grid_root.add_child(rect)
	return true


static func _add_endpoint_landmarks(
	grid_root: Node2D,
	stage: StageDef,
) -> bool:
	var count := 0
	var grid_size := stage.grid_size()
	for y: int in grid_size.y:
		for x: int in grid_size.x:
			var cell := Vector2i(x, y)
			var tile := stage.tile_at(cell)
			if tile != StageDef.Tile.SPAWN and tile != StageDef.Tile.BASE:
				continue
			var prefix := "SpawnLandmark" if tile == StageDef.Tile.SPAWN else "CoreLandmark"
			var art_id := SPAWN_LANDMARK_ID if tile == StageDef.Tile.SPAWN else CORE_LANDMARK_ID
			if not _add_landmark(
				grid_root,
				cell,
				art_id,
				"%s_%d_%d" % [prefix, x, y],
				stage.is_elevated_platform(cell),
			):
				return false
			count += 1
	return count > 0


static func _add_landmark(
	grid_root: Node2D,
	cell: Vector2i,
	art_id: StringName,
	node_name: String,
	lifted: bool = false,
) -> bool:
	var sprite := EndpointLandmarkScript.new() as BattleEndpointLandmark
	sprite.name = node_name
	if not sprite.setup(art_id):
		sprite.free()
		return false
	sprite.position = IsoProjection.endpoint_anchor(cell, lifted) + IsoProjection.endpoint_rect(art_id).position
	sprite.pivot_offset = -IsoProjection.endpoint_rect(art_id).position
	sprite.z_index = IsoProjection.tile_z(cell) + 1
	grid_root.add_child(sprite)
	return true
