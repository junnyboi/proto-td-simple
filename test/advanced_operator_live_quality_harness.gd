extends SceneTree

const BattleTicketRuntimeScript := preload("res://sim/battle_ticket_runtime.gd")
const Catalog := preload("res://data/presentation/operator_visual_catalog.gd")
const OperatorAnimatorScript := preload("res://scripts/view/operator_animator.gd")
const UnitStateScript := preload("res://sim/unit_state.gd")

const CLASS_TO_OPERATOR := {
	"gunner": &"sniper_1",
	"mage_apprentice": &"caster_1",
	"swordmaster": &"guard_1",
}
const FACINGS: Array[int] = [
	UnitStateScript.Facing.RIGHT,
	UnitStateScript.Facing.DOWN,
	UnitStateScript.Facing.LEFT,
	UnitStateScript.Facing.UP,
]

var _battle: Node
var _output_prefix := ""
var _class_id := ""
var _portrait_gender := ""


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := _args()
	_class_id = String(args.get("class", ""))
	_output_prefix = String(args.get("output_prefix", ""))
	var width := int(args.get("width", 1920))
	var height := int(args.get("height", 1080))
	var portrait := height > width
	_portrait_gender = String(args.get("gender", ""))
	if (
		not CLASS_TO_OPERATOR.has(_class_id)
		or _output_prefix.is_empty()
		or (portrait and _portrait_gender not in ["female", "male"])
	):
		push_error("Usage: -- --class <class_id> --output-prefix <absolute-path> [--gender female|male] [--width N --height N]")
		quit(2)
		return
	root.size = Vector2i(width, height)
	var game := root.get_node("Game")
	game.set("run_seed", 404)
	game.set("campaign_active", false)
	game.set("pending_stage", load("res://data/stages/s5.tres") as StageDef)
	game.set("default_squad", [CLASS_TO_OPERATOR[_class_id]])
	_battle = (load("res://scenes/battle.tscn") as PackedScene).instantiate()
	root.add_child(_battle)
	if _battle.get("startup_succeeded") != true:
		push_error("advanced live quality harness: BattleView failed to start")
		quit(3)
		return
	_battle.set("ticks_per_frame_scale", 0.0)
	_battle.set("_enemy_anim_seconds", 0.875)
	if portrait:
		var navigator: RefCounted = _battle.get("_map_nav")
		var pan_bounds: Rect2 = navigator.get("bounds")
		navigator.set("pan", pan_bounds.position + pan_bounds.size * 0.5)
		_battle.call("_apply_map_transform")
	var model: BattleModel = _battle.get("model")
	model.units.clear()
	var unit_count := 4 if portrait else 8
	var cells := _representative_cells(unit_count)
	if cells.size() != unit_count:
		push_error("advanced live quality harness: expected %d visible cells, got %d" % [unit_count, cells.size()])
		quit(4)
		return
	var operator := _battle.get("_op_defs").get(CLASS_TO_OPERATOR[_class_id]) as OperatorDef
	if operator == null:
		push_error("advanced live quality harness: fallback operator missing")
		quit(5)
		return
	if portrait:
		for facing_index: int in FACINGS.size():
			var unit_index := facing_index
			var unit := UnitStateScript.new()
			unit.id = 1500 + unit_index
			unit.hero_id = _hero_id_for_gender(_portrait_gender, unit.id)
			unit.class_id = StringName(_class_id)
			unit.cell = cells[unit_index]
			unit.facing = FACINGS[facing_index] as UnitState.Facing
			BattleTicketRuntimeScript.copy_legacy_unit(operator, unit)
			model.units.append(unit)
	else:
		for gender_index: int in 2:
			var gender := "female" if gender_index == 0 else "male"
			for facing_index: int in FACINGS.size():
				var unit_index := gender_index * FACINGS.size() + facing_index
				var unit := UnitStateScript.new()
				unit.id = 1500 + unit_index
				unit.hero_id = _hero_id_for_gender(gender, unit.id)
				unit.class_id = StringName(_class_id)
				unit.cell = cells[unit_index]
				unit.facing = FACINGS[facing_index] as UnitState.Facing
				BattleTicketRuntimeScript.copy_legacy_unit(operator, unit)
				model.units.append(unit)
	_suppress_overlays()
	await _capture_state("idle", -1, 0)
	await _capture_state("attack", 0, 16)
	var parent := _battle.get_parent()
	if parent != null:
		parent.remove_child(_battle)
	_battle.free()
	for _frame: int in 4:
		await process_frame
	print("ADVANCED_OPERATOR_LIVE_QUALITY_OK class=%s prefix=%s" % [_class_id, _output_prefix])
	quit(0)


func _capture_state(state: String, last_attack_tick: int, model_tick: int) -> void:
	var model: BattleModel = _battle.get("model")
	model.tick = model_tick
	for unit: UnitState in model.units:
		unit.last_attack_tick = last_attack_tick
	_battle.call("_project_units")
	for _frame: int in 3:
		await process_frame
	_suppress_overlays()
	for _frame: int in 5:
		await process_frame
	_validate_projection(state)
	var image := root.get_texture().get_image()
	var output := "%s-%s.png" % [_output_prefix, state]
	var error := image.save_png(output)
	if error != OK:
		push_error("failed to save %s: %s" % [output, error_string(error)])
		quit(6)
	image = null


func _validate_projection(state: String) -> void:
	var unit_nodes: Dictionary = _battle.get("_unit_nodes")
	var expected := 4 if root.size.y > root.size.x else 8
	if unit_nodes.size() != expected:
		push_error("expected %d projected unit nodes, got %d" % [expected, unit_nodes.size()])
		quit(7)
	for unit: UnitState in (_battle.get("model") as BattleModel).units:
		var body := (unit_nodes[unit.id] as Node2D).get_node("Body") as ColorRect
		var sprite := body.get_node("Sprite") as TextureRect
		if sprite.texture == null or not bool(body.get_meta(&"operator_animation", false)):
			push_error("missing advanced sprite for unit %d" % unit.id)
			quit(8)
		if String(sprite.get_meta(&"operator_animation_state", "")) != state:
			push_error("unit %d did not project %s" % [unit.id, state])
			quit(9)
		var gender := String(Catalog.deterministic_identity_gender(unit.hero_id, unit.portrait_asset_id, unit.id))
		var expected_template := StringName("%s_%s" % [_class_id, gender])
		if StringName(body.get_meta(&"operator_template_id", &"")) != expected_template:
			push_error("unit %d projected template %s instead of %s" % [unit.id, body.get_meta(&"operator_template_id", &""), expected_template])
			quit(10)
		var animation := Catalog.get_animation(expected_template)
		var selected := OperatorAnimatorScript.selection(
			unit,
			(_battle.get("model") as BattleModel).tick,
			float(_battle.get("_enemy_anim_seconds")),
			animation,
		)
		if StringName(sprite.get_meta(&"operator_animation_direction", &"")) != StringName(selected[&"direction"]):
			push_error("unit %d projected the wrong direction" % unit.id)
			quit(11)
		if StringName(sprite.get_meta(&"operator_animation_id", &"")) != StringName(selected[&"logical_id"]):
			push_error("unit %d projected the wrong logical atlas" % unit.id)
			quit(12)
		if int(sprite.get_meta(&"operator_animation_frame", -1)) != int(selected[&"frame"]):
			push_error("unit %d projected the wrong animation frame" % unit.id)
			quit(13)


func _hero_id_for_gender(gender: String, unit_id: int) -> StringName:
	for index: int in 256:
		var candidate := StringName("quality-%s-%s-%03d" % [_class_id, gender, index])
		if String(Catalog.deterministic_identity_gender(candidate, &"", unit_id)) == gender:
			return candidate
	return &""


func _representative_cells(count: int) -> Array[Vector2i]:
	var stage := _battle.get("_stage") as StageDef
	var candidates: Array[Vector2i] = []
	var size := stage.grid_size()
	var edge_inset := 28.0 if root.size.y > root.size.x else 70.0
	var minimum_spacing := 26.0 if root.size.y > root.size.x else 78.0
	for y: int in size.y:
		for x: int in size.x:
			var cell := Vector2i(x, y)
			if stage.tile_at(cell) == StageDef.Tile.GROUND:
				var point := _battle.call("cell_center", cell) as Vector2
				if point.x >= edge_inset and point.x <= root.size.x - edge_inset and point.y >= 70.0 and point.y <= root.size.y - 70.0:
					candidates.append(cell)
	candidates.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			var pa := _battle.call("cell_center", a) as Vector2
			var pb := _battle.call("cell_center", b) as Vector2
			return pa.y < pb.y or (is_equal_approx(pa.y, pb.y) and pa.x < pb.x)
	)
	var selected: Array[Vector2i] = []
	for candidate: Vector2i in candidates:
		var point := _battle.call("cell_center", candidate) as Vector2
		var separated := true
		for existing: Vector2i in selected:
			if point.distance_to(_battle.call("cell_center", existing)) < minimum_spacing:
				separated = false
				break
		if separated:
			selected.append(candidate)
			if selected.size() == count:
				return selected
	return selected


func _suppress_overlays() -> void:
	var grid_root: Variant = _battle.get("_grid_root")
	for child: Node in _battle.get_children():
		if child == grid_root:
			continue
		if child is CanvasItem:
			(child as CanvasItem).visible = false
		elif child is CanvasLayer:
			(child as CanvasLayer).visible = false


func _args() -> Dictionary:
	var parsed := {}
	var values := OS.get_cmdline_user_args()
	var index := 0
	while index < values.size():
		var key := String(values[index])
		if key in ["--class", "--output-prefix", "--gender", "--width", "--height"] and index + 1 < values.size():
			parsed[key.trim_prefix("--").replace("-", "_")] = String(values[index + 1])
			index += 2
			continue
		index += 1
	return parsed
