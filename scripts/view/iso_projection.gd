class_name IsoProjection
extends RefCounted

## functions are static and operate in GRID-LOCAL space: cell (0,0)'s top
## diamond corner sits at the local origin and the view adds
## _grid_root.position. A cell's diamond top face in screen space is exactly
## its unit square in cell space, so one map serves cell centers
## (p = cell + (0.5, 0.5)) and continuous interpolated enemy positions.
## Elevation is view-only: ELEVATED faces draw ELEV_LIFT_PX higher; the
## model never sees any of this (architecture rule 1).

const TILE_W := 64.0
const TILE_H := 32.0
const ELEV_LIFT_PX := 16.0
const DEPTH_STRIDE := 3
const ENEMY_Z_OFFSET := 1
const OPERATOR_Z_OFFSET := 2
## Sprite bottom-center sits this far below its cell's face center.
const FEET_OFFSET := 6.0
const SPAWN_LANDMARK_SIZE := Vector2(64.0, 64.0)
const CORE_LANDMARK_SIZE := Vector2(64.0, 80.0)


## Continuous cell space -> grid-local screen point.
static func project(p: Vector2) -> Vector2:
	return Vector2((p.x - p.y) * TILE_W * 0.5, (p.x + p.y) * TILE_H * 0.5)


## Grid-local screen point -> continuous flat cell space (exact algebraic
## inverse of project; ignores elevation).
static func unproject(local: Vector2) -> Vector2:
	var u := local.x / (TILE_W * 0.5)
	var v := local.y / (TILE_H * 0.5)
	return Vector2((u + v) * 0.5, (v - u) * 0.5)


## face inverts to p' = p_flat - (0.5, 0.5), and lifted faces tile flat cell
## space disjointly, so the unique lifted-face owner is
## floor(p' + (0.5, 0.5)). Wall-band clicks fall through to the naive cell
## a lifted diamond's TOP corner coincides exactly with the face center of
## its NW flat neighbor — the tie breaks to the flat cell so
## cell_at(cell_center(c)) == c holds for EVERY cell.
static func pick(local: Vector2, is_lifted: Callable) -> Vector2i:
	var p := unproject(local)
	# grid-scale division roundoff can push seam-generated lattice points
	# (face centers, corners) off by an ulp — floor() then jumps a whole
	# cell. Snap to the half-cell lattice within 1e-4 before flooring.
	var snapped := (p * 2.0).round() * 0.5
	if absf(p.x - snapped.x) < 0.0001 and absf(p.y - snapped.y) < 0.0001:
		p = snapped
	var p_lift := p + Vector2(0.5, 0.5)
	var lifted_cell := Vector2i(p_lift.floor())
	var exact_corner := (
		p_lift.x == float(lifted_cell.x) and p_lift.y == float(lifted_cell.y)
	)
	if not exact_corner and bool(is_lifted.call(lifted_cell)):
		return lifted_cell
	return Vector2i(p.floor())


static func face_center(cell: Vector2i, lifted: bool = false) -> Vector2:
	var center := project(Vector2(cell) + Vector2(0.5, 0.5))
	if lifted:
		center.y -= ELEV_LIFT_PX
	return center


## An origin-centered face diamond (top, right, bottom, left) at the given
## uniform scale — one shape serves every screen-space footprint overlay
## (hover cursor, valid-cell highlights, area footprint = scale * span).
static func face_polygon(scale: float = 1.0) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0.0, -TILE_H * 0.5 * scale),
		Vector2(TILE_W * 0.5 * scale, 0.0),
		Vector2(0.0, TILE_H * 0.5 * scale),
		Vector2(-TILE_W * 0.5 * scale, 0.0),
	])


## The four projected corners of a cell's top face (top, right, bottom,
## left), for diamond footprint overlays and tile polys.
static func cell_polygon(cell: Vector2i, lifted: bool = false) -> PackedVector2Array:
	var lift := -ELEV_LIFT_PX if lifted else 0.0
	var off := Vector2(0.0, lift)
	var c := Vector2(cell)
	return PackedVector2Array([
		project(c) + off,
		project(c + Vector2(1.0, 0.0)) + off,
		project(c + Vector2(1.0, 1.0)) + off,
		project(c + Vector2(0.0, 1.0)) + off,
	])


## Painter's depth over continuous cell space.
static func depth(p: Vector2) -> int:
	return int(floorf(p.x) + floorf(p.y))


## Each painter depth reserves explicit terrain, enemy, and operator slots.
## Ground effects use tile_z + 1 and share the enemy slot; operators occupy
## the final slot so their sprites always win same-depth enemy overlaps.
static func tile_z(cell: Vector2i) -> int:
	return DEPTH_STRIDE * (cell.x + cell.y)


static func entity_z(p: Vector2) -> int:
	return DEPTH_STRIDE * depth(p) + ENEMY_Z_OFFSET


static func operator_z(p: Vector2) -> int:
	return DEPTH_STRIDE * depth(p) + OPERATOR_Z_OFFSET


## = the diamond's exact span; vertical from -ELEV_LIFT_PX - 64 (sprite
## headroom, top-padded only) to span * TILE_H / 2 + 8.
static func content_box(grid_size: Vector2i) -> Rect2:
	var span := float(grid_size.x + grid_size.y)
	var left := -float(grid_size.y) * TILE_W * 0.5
	var top := -ELEV_LIFT_PX - 64.0
	var width := span * TILE_W * 0.5
	var height := span * TILE_H * 0.5 + 8.0 - top
	return Rect2(left, top, width, height)


## Exact union of the stage's rendered tile rectangles. Ground art is one
## 64x32 face; elevated art starts 16px higher and includes its 16px wall.
## This measures actual terrain instead of reserving lift above every stage.
static func terrain_box(stage: StageDef) -> Rect2:
	var result := Rect2()
	var first := true
	var grid_size := stage.grid_size()
	for y: int in grid_size.y:
		for x: int in grid_size.x:
			var cell := Vector2i(x, y)
			var lifted := stage.is_elevated_platform(cell)
			var top := cell_polygon(cell, lifted)[0]
			var height := TILE_H + (ELEV_LIFT_PX if lifted else 0.0)
			var tile_box := Rect2(top.x - TILE_W * 0.5, top.y, TILE_W, height)
			result = tile_box if first else result.merge(tile_box)
			first = false
	return result


## Uniform scale whose transformed terrain height equals the live viewport
## height exactly. Width is allowed to overflow and is recovered by panning.
static func height_fill_scale(stage: StageDef, viewport: Vector2) -> float:
	return viewport.y / terrain_box(stage).size.y


## Grid-root origin that centers the scaled terrain rectangle in the viewport.
static func terrain_origin_for(stage: StageDef, viewport: Vector2, scale: float) -> Vector2:
	return viewport * 0.5 - terrain_box(stage).get_center() * scale


## Union of terrain and the generated bottom-centered endpoint frames. This is
## intentionally narrower than content_box(): it reserves only real landmark
## pixels instead of generic entity headroom, preserving useful battle scale.
static func visual_box(stage: StageDef) -> Rect2:
	var result := terrain_box(stage)
	var grid_size := stage.grid_size()
	for y: int in grid_size.y:
		for x: int in grid_size.x:
			var cell := Vector2i(x, y)
			var tile := stage.tile_at(cell)
			if tile != StageDef.Tile.SPAWN and tile != StageDef.Tile.BASE:
				continue
			var landmark_size := (
				SPAWN_LANDMARK_SIZE if tile == StageDef.Tile.SPAWN else CORE_LANDMARK_SIZE
			)
			var center := face_center(cell)
			var landmark_box := Rect2(
				center - Vector2(landmark_size.x * 0.5, landmark_size.y),
				landmark_size,
			)
			result = result.merge(landmark_box)
	return result


static func visual_height_fill_scale(stage: StageDef, viewport: Vector2) -> float:
	return viewport.y / visual_box(stage).size.y


static func visual_origin_for(stage: StageDef, viewport: Vector2, scale: float) -> Vector2:
	return viewport * 0.5 - visual_box(stage).get_center() * scale


## Screen-space visual-content rectangle after applying a pan offset to the
## terrain-centered root. Kept pure so both the view and GUT share one truth.
static func content_screen_rect(
	stage: StageDef, viewport: Vector2, scale: float, pan: Vector2 = Vector2.ZERO
) -> Rect2:
	var box := content_box(stage.grid_size())
	var origin := terrain_origin_for(stage, viewport, scale) + pan
	return Rect2(origin + box.position * scale, box.size * scale)


## Legal pan interval encoded as Rect2(position=min, end=max). An axis whose
## visual content already fits is locked at zero; an overflowing axis can move
## until either content edge meets the corresponding viewport edge exactly.
static func pan_bounds(stage: StageDef, viewport: Vector2, scale: float) -> Rect2:
	var screen := content_screen_rect(stage, viewport, scale)
	var min_pan := Vector2.ZERO
	var max_pan := Vector2.ZERO
	if screen.size.x > viewport.x:
		min_pan.x = viewport.x - screen.end.x
		max_pan.x = -screen.position.x
	if screen.size.y > viewport.y:
		min_pan.y = viewport.y - screen.end.y
		max_pan.y = -screen.position.y
	return Rect2(min_pan, max_pan - min_pan)


static func clamp_pan(pan: Vector2, bounds: Rect2) -> Vector2:
	return Vector2(
		clampf(pan.x, bounds.position.x, bounds.end.x),
		clampf(pan.y, bounds.position.y, bounds.end.y),
	)


## Uniform grid scale that fills the available canvas box, snapped DOWN to
## 0.25 steps (uneven pixel-art scaling stays tolerable), clamped [1, 3].
static func fit_scale(grid_size: Vector2i, avail: Vector2) -> float:
	var box := content_box(grid_size)
	var s := minf(avail.x / box.size.x, avail.y / box.size.y)
	return clampf(floorf(s * 4.0) * 0.25, 1.0, 3.0)


## Grid-root position centering the scaled content box in the viewport.
static func origin_for(grid_size: Vector2i, viewport: Vector2, scale: float = 1.0) -> Vector2:
	var box := content_box(grid_size)
	return viewport * 0.5 - box.get_center() * scale
