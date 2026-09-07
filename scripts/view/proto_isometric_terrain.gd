class_name ProtoIsometricTerrain
extends Node2D

## Static terrain presentation transplanted from proto-isometric. The battle
## model and IsoProjection remain authoritative; this node only renders stage
## cells with the source project's textured, multi-pass isometric treatment.

const TEXTURE_ROOT := "res://assets/template/terrain/proto_isometric/"
const ELEVATED_PLATFORM_OCCLUDER_SCRIPT := preload(
	"res://scripts/view/elevated_platform_occluder.gd"
)
const TERRAIN_TEXTURE_PERIOD_CELLS := 4.0
const TERRAIN_UV_VARIATION := 0.035
const OUTER_RING := 3
const GRID_LINE := Color(0.18, 0.12, 0.08, 0.32)
const SPAWN_LINE := Color(0.18, 0.92, 0.86, 0.86)
const BASE_LINE := Color(1.0, 0.72, 0.20, 0.9)
const VOID_TINT := Color(0.34, 0.39, 0.46, 0.78)
const OUTER_TINT := Color(0.28, 0.27, 0.27, 0.42)

const TRANSITION_DEPTHS: Array[float] = [0.28, 0.18, 0.09]
const TRANSITION_ALPHAS: Array[float] = [0.07, 0.12, 0.20]
const TRANSITION_SEGMENTS := 6
const TRANSITION_IRREGULARITY := 0.34
const EDGE_NEIGHBORS: Array[Vector2i] = [
	Vector2i(0, -1),
	Vector2i(1, 0),
	Vector2i(0, 1),
	Vector2i(-1, 0),
]

const COLORS := {
	&"sand": Color("d79a45"),
	&"salt": Color("d8d0b5"),
	&"rock": Color("934d35"),
	&"wetland": Color("879b55"),
	&"mud": Color("2d281f"),
	&"snow": Color("dce8ed"),
	&"blue_ice": Color("36a8c8"),
	&"lava_basalt": Color("252326"),
	&"volcanic_ash": Color("8c8a86"),
	&"lava": Color("ff5a12"),
	&"ruin": Color("6f6c64"),
}

const TEXTURES: Dictionary = {
	&"sand": preload(TEXTURE_ROOT + "desert_sand.png"),
	&"salt": preload(TEXTURE_ROOT + "salt_crust.png"),
	&"rock": preload(TEXTURE_ROOT + "iron_rock.png"),
	&"wetland": preload(TEXTURE_ROOT + "oasis_wetland.png"),
	&"mud": preload(TEXTURE_ROOT + "dark_mud.png"),
	&"snow": preload(TEXTURE_ROOT + "tundra_snow.png"),
	&"blue_ice": preload(TEXTURE_ROOT + "blue_ice.png"),
	&"lava_basalt": preload(TEXTURE_ROOT + "lava_basalt.png"),
	&"volcanic_ash": preload(TEXTURE_ROOT + "volcanic_ash.png"),
	&"lava": preload(TEXTURE_ROOT + "lava_flow.png"),
	&"ruin": preload(TEXTURE_ROOT + "ancient_ruin.png"),
}

const BIOME_PROFILES := {
	&"desert": {
		&"ground": &"sand",
		&"route": &"salt",
		&"elevated": &"rock",
		&"void": &"mud",
		&"spawn": &"salt",
		&"base": &"ruin",
		&"wall_top": Color("934d35"),
		&"wall_right": Color("63341f"),
		&"wall_left": Color("482519"),
	},
	&"wetland": {
		&"ground": &"wetland",
		&"route": &"mud",
		&"elevated": &"rock",
		&"void": &"mud",
		&"spawn": &"salt",
		&"base": &"ruin",
		&"wall_top": Color("716a3a"),
		&"wall_right": Color("4f4930"),
		&"wall_left": Color("373326"),
	},
	&"frozen": {
		&"ground": &"snow",
		&"route": &"blue_ice",
		&"elevated": &"rock",
		&"void": &"mud",
		&"spawn": &"blue_ice",
		&"base": &"ruin",
		&"wall_top": Color("afbfca"),
		&"wall_right": Color("788d9a"),
		&"wall_left": Color("5c707c"),
	},
	&"lava": {
		&"ground": &"lava_basalt",
		&"route": &"volcanic_ash",
		&"elevated": &"rock",
		&"void": &"mud",
		&"spawn": &"lava",
		&"base": &"ruin",
		&"wall_top": Color("34363a"),
		&"wall_right": Color("242529"),
		&"wall_left": Color("18191d"),
	},
}

var _stage: StageDef = null
var _path_cells: Dictionary = {}
var _biome: StringName = &"desert"
var _profile: Dictionary = {}


func configure(stage: StageDef) -> bool:
	if stage == null or stage.grid_size() == Vector2i.ZERO:
		return false
	_stage = stage
	_biome = _biome_for_stage(stage.id)
	_profile = (BIOME_PROFILES[_biome] as Dictionary).duplicate(true)
	_path_cells.clear()
	for path_index: int in stage.paths.size():
		for cell: Vector2i in stage.path_cells(path_index):
			_path_cells[cell] = true
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_rebuild_elevated_platform_occluders()
	queue_redraw()
	return true


func _draw() -> void:
	if _stage == null:
		return
	var cells := _ordered_stage_cells()
	_draw_outer_field()
	for cell: Vector2i in cells:
		_draw_tile(cell)
	for cell: Vector2i in cells:
		_draw_tile_transitions(cell)
	for cell: Vector2i in cells:
		_draw_tile_details(cell)


func terrain_id_at(cell: Vector2i) -> StringName:
	if _stage == null:
		return &"sand"
	var tile := _stage.tile_at(cell)
	match tile:
		StageDef.Tile.VOID:
			return _profile[&"void"] as StringName
		StageDef.Tile.ELEVATED, StageDef.Tile.BLOCKED:
			return _profile[&"elevated"] as StringName
		StageDef.Tile.SPAWN:
			return _profile[&"spawn"] as StringName
		StageDef.Tile.BASE:
			return _profile[&"base"] as StringName
		StageDef.Tile.GROUND:
			return (
				_profile[&"route"] as StringName
				if _path_cells.has(cell)
				else _profile[&"ground"] as StringName
			)
	return _profile[&"ground"] as StringName


func biome() -> StringName:
	return _biome


static func required_texture_paths() -> PackedStringArray:
	var paths := PackedStringArray()
	for texture: Texture2D in TEXTURES.values():
		paths.append(texture.resource_path)
	paths.sort()
	return paths


func _ordered_stage_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var size := _stage.grid_size()
	for depth: int in range(size.x + size.y - 1):
		for y: int in range(size.y):
			var x := depth - y
			if x >= 0 and x < size.x:
				cells.append(Vector2i(x, y))
	return cells


func _draw_outer_field() -> void:
	var size := _stage.grid_size()
	var ground_id := _profile[&"ground"] as StringName
	for depth: int in range(
		-OUTER_RING * 2,
		size.x + size.y + OUTER_RING * 2 - 1,
	):
		for y: int in range(-OUTER_RING, size.y + OUTER_RING):
			var x := depth - y
			if x < -OUTER_RING or x >= size.x + OUTER_RING:
				continue
			if x >= 0 and x < size.x and y >= 0 and y < size.y:
				continue
			var cell := Vector2i(x, y)
			var points := IsoProjection.cell_polygon(cell)
			var color := (COLORS[ground_id] as Color) * OUTER_TINT
			draw_colored_polygon(points, color)
			var texture := TEXTURES.get(ground_id) as Texture2D
			if texture != null:
				var tints := _terrain_tints(cell, OUTER_TINT)
				draw_polygon(points, tints, _terrain_uvs(cell), texture)


func _draw_tile(cell: Vector2i) -> void:
	var tile := _stage.tile_at(cell)
	var lifted := _is_obstacle_cell(cell)
	# Raised cells render through depth-sorted occluders instead of the shared
	# background pass. This lets their front walls cover characters behind.
	if lifted:
		return
	var points := IsoProjection.cell_polygon(cell, lifted)
	var terrain_id := terrain_id_at(cell)
	var color := COLORS.get(terrain_id, Color.WHITE) as Color
	if tile == StageDef.Tile.VOID:
		color *= VOID_TINT
	draw_colored_polygon(points, color)
	var texture := TEXTURES.get(terrain_id) as Texture2D
	if texture != null:
		var tint := VOID_TINT if tile == StageDef.Tile.VOID else Color.WHITE
		draw_polygon(points, _terrain_tints(cell, tint), _terrain_uvs(cell), texture)


func _draw_tile_transitions(cell: Vector2i) -> void:
	for transition: Dictionary in _transition_descriptors_for(cell):
		var edge := int(transition[&"edge"])
		var neighbor := transition[&"neighbor"] as Vector2i
		var points := IsoProjection.cell_polygon(cell)
		var neighbor_points := IsoProjection.cell_polygon(neighbor)
		var opposite_edge := (edge + 2) % 4
		var source_color := transition[&"source_color"] as Color
		var neighbor_color := transition[&"neighbor_color"] as Color
		var seed := int(transition[&"seed"])
		for index: int in range(TRANSITION_DEPTHS.size()):
			var depth := TRANSITION_DEPTHS[index]
			var source_band := _transition_mask_points(points, edge, depth, seed, false)
			var neighbor_band := _transition_mask_points(
				neighbor_points, opposite_edge, depth, seed, true
			)
			var alpha := TRANSITION_ALPHAS[index]
			draw_colored_polygon(source_band, Color(neighbor_color, alpha))
			draw_colored_polygon(neighbor_band, Color(source_color, alpha))


func _draw_tile_details(cell: Vector2i) -> void:
	if _is_obstacle_cell(cell):
		return
	var points := IsoProjection.cell_polygon(cell, _is_obstacle_cell(cell))
	var closed := points.duplicate()
	closed.append(points[0])
	draw_polyline(closed, GRID_LINE, 1.2, true)
	var tile := _stage.tile_at(cell)
	if tile == StageDef.Tile.SPAWN:
		draw_polyline(closed, SPAWN_LINE, 2.2, true)
	elif tile == StageDef.Tile.BASE:
		draw_polyline(closed, BASE_LINE, 2.2, true)
	var terrain_id := terrain_id_at(cell)
	var center := IsoProjection.face_center(cell, _is_obstacle_cell(cell))
	if terrain_id == &"blue_ice":
		draw_line(
			center + Vector2(-18.0, 3.0),
			center + Vector2(16.0, -5.0),
			Color(0.75, 0.96, 1.0, 0.42),
			1.2,
		)
	elif terrain_id == &"lava":
		draw_polyline(closed, Color(1.0, 0.76, 0.18, 0.58), 2.0, true)


func _rebuild_elevated_platform_occluders() -> void:
	for child: Node in get_children():
		if child.get_script() == ELEVATED_PLATFORM_OCCLUDER_SCRIPT:
			child.free()
	for cell: Vector2i in _ordered_stage_cells():
		if not _is_obstacle_cell(cell):
			continue
		var terrain_id := terrain_id_at(cell)
		var occluder := ELEVATED_PLATFORM_OCCLUDER_SCRIPT.new() as Node2D
		occluder.call(
			"configure",
			cell,
			IsoProjection.cell_polygon(cell, true),
			_profile[&"wall_top"] as Color,
			_profile[&"wall_right"] as Color,
			_profile[&"wall_left"] as Color,
			TEXTURES.get(terrain_id) as Texture2D,
			_terrain_tints(cell),
			_terrain_uvs(cell),
			GRID_LINE,
		)
		add_child(occluder)


func _transition_descriptors_for(cell: Vector2i) -> Array[Dictionary]:
	var transitions: Array[Dictionary] = []
	if _is_obstacle_cell(cell) or _stage.tile_at(cell) == StageDef.Tile.VOID:
		return transitions
	var terrain_id := terrain_id_at(cell)
	for edge: int in range(EDGE_NEIGHBORS.size()):
		var neighbor := cell + EDGE_NEIGHBORS[edge]
		if not _cell_in_stage(neighbor):
			continue
		if _is_obstacle_cell(neighbor) or _stage.tile_at(neighbor) == StageDef.Tile.VOID:
			continue
		var neighbor_id := terrain_id_at(neighbor)
		if neighbor_id == terrain_id or not _cell_precedes(cell, neighbor):
			continue
		transitions.append(
			{
				&"edge": edge,
				&"neighbor": neighbor,
				&"source_color": COLORS.get(terrain_id, Color.WHITE),
				&"neighbor_color": COLORS.get(neighbor_id, Color.WHITE),
				&"seed": _shared_edge_seed(cell, neighbor),
			}
		)
	return transitions


func _terrain_uvs(cell: Vector2i) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point: Vector2 in _terrain_grid_vertices(cell):
		var warp := Vector2(
			sin(point.x * 0.31 + point.y * 0.17),
			cos(point.y * 0.27 - point.x * 0.13),
		) * TERRAIN_UV_VARIATION
		result.append(point / TERRAIN_TEXTURE_PERIOD_CELLS + warp)
	return result


func _terrain_tints(cell: Vector2i, tint: Color = Color.WHITE) -> PackedColorArray:
	var result := PackedColorArray()
	for point: Vector2 in _terrain_grid_vertices(cell):
		var wave := (
			(sin(point.x * 0.39) + cos(point.y * 0.33) + sin((point.x + point.y) * 0.16))
			/ 3.0
		)
		var brightness := 0.96 + wave * 0.055
		result.append(Color(brightness * 1.025, brightness, brightness * 0.96, 1.0) * tint)
	return result


func _terrain_grid_vertices(cell: Vector2i) -> Array[Vector2]:
	var center := Vector2(cell)
	return [
		center + Vector2(-0.5, -0.5),
		center + Vector2(0.5, -0.5),
		center + Vector2(0.5, 0.5),
		center + Vector2(-0.5, 0.5),
	]


static func _transition_mask_points(
	points: PackedVector2Array,
	edge: int,
	depth: float,
	seed: int,
	reverse_profile: bool,
) -> PackedVector2Array:
	var center := (points[0] + points[1] + points[2] + points[3]) * 0.25
	var start := points[edge]
	var finish := points[(edge + 1) % 4]
	var result := PackedVector2Array()
	var inner := PackedVector2Array()
	for index: int in range(TRANSITION_SEGMENTS + 1):
		var t := float(index) / float(TRANSITION_SEGMENTS)
		var profile_index := TRANSITION_SEGMENTS - index if reverse_profile else index
		var edge_point := start.lerp(finish, t)
		var shaped_depth := depth * _transition_depth_multiplier(seed, profile_index)
		result.append(edge_point)
		inner.append(edge_point.lerp(center, shaped_depth))
	for index: int in range(inner.size() - 1, -1, -1):
		result.append(inner[index])
	return result


static func _transition_depth_multiplier(seed: int, sample_index: int) -> float:
	var t := float(sample_index) / float(TRANSITION_SEGMENTS)
	var envelope := sin(t * PI)
	var phase_a := _seeded_unit(seed, 41) * TAU
	var phase_b := _seeded_unit(seed, 67) * TAU
	var waves := sin(t * TAU + phase_a) * 0.18
	waves += sin(t * TAU * 2.0 + phase_b) * 0.08
	var jitter := (_seeded_unit(seed, sample_index + 3) - 0.5) * TRANSITION_IRREGULARITY
	return clampf(1.0 + (waves + jitter) * envelope, 0.68, 1.36)


static func _cell_precedes(first: Vector2i, second: Vector2i) -> bool:
	return first.x < second.x or (first.x == second.x and first.y < second.y)


static func _shared_edge_seed(first: Vector2i, second: Vector2i) -> int:
	var low := first if _cell_precedes(first, second) else second
	var high := second if low == first else first
	return posmod(
		(low.x + 257) * 73856093
		+ (low.y + 257) * 19349663
		+ (high.x + 257) * 83492791
		+ (high.y + 257) * 297121507,
		2147483647,
	)


static func _seeded_unit(seed: int, channel: int) -> float:
	var value := posmod(seed + (channel + 1) * 104729, 2147483647)
	value = posmod(value * 48271, 2147483647)
	return float(value) / 2147483647.0


func _cell_in_stage(cell: Vector2i) -> bool:
	var size := _stage.grid_size()
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y


func _is_obstacle_cell(cell: Vector2i) -> bool:
	var tile := _stage.tile_at(cell)
	return tile == StageDef.Tile.ELEVATED or tile == StageDef.Tile.BLOCKED


static func _biome_for_stage(stage_id: StringName) -> StringName:
	var text := String(stage_id)
	var number := int(text.trim_prefix("s")) if text.begins_with("s") else 1
	match posmod(number - 1, 4):
		1:
			return &"wetland"
		2:
			return &"frozen"
		3:
			return &"lava"
		_:
			return &"desert"
