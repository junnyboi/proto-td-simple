class_name OperatorRangeOverlay
extends Node2D

## Presentation-only attack coverage for one deployed operator at a time.
## It deliberately consumes Targeting.omni_range_cells(), the same range truth
## used by target_decision_projection, and lives under GridRoot so pan, zoom,
## and viewport relayout transform it exactly once with the battlefield.

const TargetingType := preload("res://sim/targeting.gd")

const RANGE_FILL := Color(0.95, 0.72, 0.22, 0.22)
const RANGE_BORDER := Color(0.36, 0.93, 0.95, 0.74)
const BORDER_WIDTH := 1.35
const OVERLAY_Z := 1

var _model: BattleModel = null
var _battle_view: Node2D = null
var _selected_unit_id := -1
var _hovered_unit_id := -1
var _active_unit_id := -1
var _painted_cells: Array[Vector2i] = []
var _cached_origin := Vector2i(-9999, -9999)
var _cached_offsets: Array[Vector2i] = []


## Attach beneath the view's existing GridRoot, never under the HUD. The grid
## root already owns map pan and uniform scale, so coordinates below remain
## unscaled IsoProjection-local values.
func setup(battle_model: BattleModel, battle_view: Node2D) -> bool:
	_model = battle_model
	_battle_view = battle_view
	if _battle_view == null:
		return false
	var world := _battle_view.get_node_or_null("GridRoot") as Node2D
	if world == null:
		return false
	name = "OperatorRangeOverlay"
	z_index = OVERLAY_Z
	world.add_child(self)
	_refresh()
	return true


func set_selected_unit_id(unit_id: int) -> void:
	if _selected_unit_id == unit_id:
		return
	_selected_unit_id = unit_id
	_refresh()


func selected_unit_id() -> int:
	return _selected_unit_id


func set_hovered_unit_id(unit_id: int) -> void:
	if _hovered_unit_id == unit_id:
		return
	_hovered_unit_id = unit_id
	_refresh()


func hovered_unit_id() -> int:
	return _hovered_unit_id


## Hover has temporary priority; moving away restores an otherwise-live
## selected operator automatically.
func active_unit_id() -> int:
	return _active_unit_id


func painted_cells() -> Array[Vector2i]:
	return _painted_cells.duplicate()


func refresh() -> void:
	_refresh()


func clear() -> void:
	_selected_unit_id = -1
	_hovered_unit_id = -1
	_active_unit_id = -1
	_painted_cells.clear()
	queue_redraw()


func _refresh() -> void:
	var next_unit_id := _live_unit_id(_hovered_unit_id)
	if next_unit_id < 0:
		next_unit_id = _live_unit_id(_selected_unit_id)
	if next_unit_id == _active_unit_id and _painted_cells_match_unit(next_unit_id):
		return
	_active_unit_id = next_unit_id
	_painted_cells.clear()
	if _active_unit_id >= 0 and _model != null:
		var unit := _model.unit_by_id(_active_unit_id)
		if unit != null:
			_painted_cells = coverage_cells(unit, _model.stage)
			_cached_origin = unit.cell
			_cached_offsets = unit.range_offsets.duplicate()
	queue_redraw()


func _painted_cells_match_unit(unit_id: int) -> bool:
	if unit_id < 0:
		return _painted_cells.is_empty()
	if _model == null:
		return false
	var unit := _model.unit_by_id(unit_id)
	return unit != null and unit.alive and unit.cell == _cached_origin and unit.range_offsets == _cached_offsets


func _live_unit_id(unit_id: int) -> int:
	if _model == null or unit_id < 0:
		return -1
	var unit := _model.unit_by_id(unit_id)
	return unit_id if unit != null and unit.alive else -1


## A deterministic, bounded cell list for tests and drawing. Only authored map
## faces are shown: coordinates outside the grid and VOID cells are skipped.
static func coverage_cells(unit: UnitState, stage: StageDef) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if unit == null or not unit.alive or stage == null:
		return result
	var covered: Dictionary = TargetingType.omni_range_cells(unit.cell, unit.range_offsets)
	for candidate: Variant in covered.keys():
		var cell := candidate as Vector2i
		if stage.tile_at(cell) != StageDef.Tile.VOID:
			result.append(cell)
	result.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			return a.x < b.x if a.y == b.y else a.y < b.y
	)
	return result


## GridRoot supplies current pan and scale. Lift enters exactly here through the
## shared face-center projection; no screen-space cell_center conversion occurs.
func local_center_for_cell(cell: Vector2i) -> Vector2:
	var lifted := _model != null and _model.stage != null and _model.stage.is_elevated_platform(cell)
	return IsoProjection.face_center(cell, lifted)


func _draw() -> void:
	for cell: Vector2i in _painted_cells:
		var center := local_center_for_cell(cell)
		var face := IsoProjection.face_polygon()
		for point_index: int in face.size():
			face[point_index] += center
		draw_colored_polygon(face, RANGE_FILL)
		var border := face.duplicate()
		border.append(face[0])
		draw_polyline(border, RANGE_BORDER, BORDER_WIDTH, true)
