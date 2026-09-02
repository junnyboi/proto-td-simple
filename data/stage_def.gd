class_name StageDef
extends Resource

## Stage layout + schedule (all balance is data — architecture rule 4).
## grid_rows: one string per row, one char per tile (hand-authorable):
##   . VOID   G GROUND   E ELEVATED   S SPAWN   B BASE
##   X legacy raised-platform alias (enum name BLOCKED is serialization-only)
## paths: flat Vector2 lists (converted to cells via path_cells());
## squad_size activate in later phases.
## wave_starts: wave-window boundary ticks; non-empty must be strictly
## ascending and start at 0 (stage_lint).
enum Tile { VOID, GROUND, ELEVATED, SPAWN, BASE, BLOCKED }

const TILE_CHARS := {
	".": Tile.VOID,
	"G": Tile.GROUND,
	"E": Tile.ELEVATED,
	"S": Tile.SPAWN,
	"B": Tile.BASE,
	"X": Tile.BLOCKED,
}

@export var id: StringName = &""
@export var title: String = ""
@export var grid_rows: PackedStringArray = []
@export var paths: Array[PackedVector2Array] = []
@export var waves: Array[Dictionary] = []
@export var wave_starts: PackedInt32Array = []
@export var leak_limit: int = 0
@export var squad_size: int = 0
@export var recovery_roster: Array[StringName] = []
# first clear ({kind: operator|trap, id}); campaign_index -1 = not a
# campaign stage (campaign order = ascending index, never scan order);
# requires = unlockable ids this stage's lesson depends on (lint-enforced
# teach-before-use)
@export var rewards: Array[Dictionary] = []
@export var campaign_index: int = -1
@export var requires: Array[StringName] = []
# Presentation-only soundtrack routing. These ids never enter battle hashes,
# snapshots, saves, tickets, or deterministic simulation decisions.
@export var music_profile_id: StringName = &""
@export var music_variant_id: StringName = &""
## Presentation-only escalation markers. Indices are zero-based wave windows;
## they never enter battle decisions, hashes, tickets, snapshots, or saves.
@export var high_threat_wave_indices: PackedInt32Array = []
@export var high_threat_warning_id: StringName = &""
## Act II restoration infrastructure. Cells are authored on hostile ground
## routes; due cycles repair hostile ground Custodians.
@export var restoration_cells: PackedVector2Array = []
@export_range(0, 1000, 1) var restoration_heal_amount: int = 0
@export_range(0, 3600, 1) var restoration_interval_ticks: int = 0


func grid_size() -> Vector2i:
	if grid_rows.is_empty():
		return Vector2i.ZERO
	return Vector2i(grid_rows[0].length(), grid_rows.size())


## Portrait battles snapshot one clockwise-rotated stage copy at startup. The
## source resource remains the landscape authoring contract; all non-spatial
## metadata (waves, unlocks, roster, rewards) is preserved by duplicate.
func copy_for_viewport(viewport_size: Vector2) -> StageDef:
	return clockwise_rotated_copy() if viewport_size.y > viewport_size.x else self


func clockwise_rotated_copy() -> StageDef:
	var source_size := grid_size()
	var rotated := duplicate(true) as StageDef
	if source_size == Vector2i.ZERO:
		return rotated
	var rotated_rows := PackedStringArray()
	for destination_y: int in source_size.x:
		var row := ""
		for destination_x: int in source_size.y:
			var source_cell := Vector2i(destination_y, source_size.y - 1 - destination_x)
			row += grid_rows[source_cell.y][source_cell.x]
		rotated_rows.append(row)
	rotated.grid_rows = rotated_rows
	var rotated_paths: Array[PackedVector2Array] = []
	for source_path: PackedVector2Array in paths:
		var rotated_path := PackedVector2Array()
		for point: Vector2 in source_path:
			rotated_path.append(Vector2(rotate_cell_clockwise(Vector2i(point), source_size)))
		rotated_paths.append(rotated_path)
	rotated.paths = rotated_paths
	var rotated_restoration_cells := PackedVector2Array()
	for point: Vector2 in restoration_cells:
		rotated_restoration_cells.append(
			Vector2(rotate_cell_clockwise(Vector2i(point), source_size))
		)
	rotated.restoration_cells = rotated_restoration_cells
	return rotated


static func rotate_cell_clockwise(cell: Vector2i, source_size: Vector2i) -> Vector2i:
	return Vector2i(source_size.y - 1 - cell.y, cell.x)


func tile_at(cell: Vector2i) -> Tile:
	if cell.y < 0 or cell.y >= grid_rows.size():
		return Tile.VOID
	var row := grid_rows[cell.y]
	if cell.x < 0 or cell.x >= row.length():
		return Tile.VOID
	return TILE_CHARS.get(row[cell.x], Tile.VOID)


func is_enemy_walkable(cell: Vector2i) -> bool:
	return tile_at(cell) in [Tile.GROUND, Tile.SPAWN, Tile.BASE]


## Both E and the legacy X authoring glyph render as empty raised platforms.
## Keep their serialized topology stable while exposing one honest placement
## domain to simulation, ticketed battles, hit testing, and presentation.
func is_elevated_platform(cell: Vector2i) -> bool:
	return tile_at(cell) in [Tile.ELEVATED, Tile.BLOCKED]


func path_cells(idx: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if idx < 0 or idx >= paths.size():
		return out
	for v: Vector2 in paths[idx]:
		out.append(Vector2i(v))
	return out


func operator_cell_in_domain(operator_def: OperatorDef, cell: Vector2i) -> bool:
	if operator_def.placement == OperatorDef.Placement.GROUND:
		return tile_at(cell) == Tile.GROUND
	return is_elevated_platform(cell)


func trap_cell_in_domain(cell: Vector2i) -> bool:
	if tile_at(cell) != Tile.GROUND:
		return false
	for path_index: int in paths.size():
		if path_cells(path_index).has(cell):
			return true
	return false


func restoration_contract_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if restoration_cells.is_empty():
		if restoration_heal_amount != 0 or restoration_interval_ticks != 0:
			errors.append("restoration tuning requires at least one lattice cell")
		return errors
	if restoration_heal_amount <= 0:
		errors.append("restoration heal amount must be positive")
	if restoration_interval_ticks <= 0:
		errors.append("restoration interval must be positive")
	var seen := {}
	for point: Vector2 in restoration_cells:
		var cell := Vector2i(point)
		if seen.has(cell):
			errors.append("duplicate restoration lattice cell %s" % cell)
			continue
		seen[cell] = true
		if tile_at(cell) != Tile.GROUND:
			errors.append("restoration lattice must occupy GROUND at %s" % cell)
			continue
		var on_path := false
		for path_index: int in paths.size():
			if path_cells(path_index).has(cell):
				on_path = true
				break
		if not on_path:
			errors.append("restoration lattice is outside every hostile path at %s" % cell)
	return errors


func high_threat_contract_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if high_threat_wave_indices.is_empty():
		if not high_threat_warning_id.is_empty():
			errors.append("high-threat warning id requires at least one wave index")
		return errors
	if high_threat_warning_id.is_empty():
		errors.append("high-threat wave indices require a warning id")
	var previous := -1
	for wave_index: int in high_threat_wave_indices:
		if wave_index < 0 or wave_index >= wave_starts.size():
			errors.append("high-threat wave index %d is outside the authored wave windows" % wave_index)
		continue
		if wave_index <= previous:
			errors.append("high-threat wave indices must be unique and ascending")
		previous = wave_index
	return errors


func is_high_threat_wave(wave_index: int) -> bool:
	return high_threat_wave_indices.has(wave_index)


func wave_index_at(at_tick: int) -> int:
	if wave_starts.is_empty():
		return 0
	var index := -1
	for boundary: int in wave_starts:
		if boundary <= at_tick:
			index += 1
	return index
