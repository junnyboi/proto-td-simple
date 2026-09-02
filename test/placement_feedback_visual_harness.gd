extends Node

const JUICE_LAYER_SCRIPT := preload("res://scripts/view/juice_layer.gd")
const VIEW_MARGIN := Vector2(120, 110)
const TRIGGER_FRAME := 38

var _juice: Node2D = null
var _profile: StringName = &"ground"
var _effect_cell := Vector2i.ZERO
var _triggered := false
var _frames := 0


func _ready() -> void:
	_profile = StringName(OS.get_environment("PLACEMENT_PROFILE"))
	if _profile not in [&"ground", &"elevated"]:
		_profile = &"ground"
	var stage := load("res://data/stages/s2.tres") as StageDef
	if stage == null:
		push_error("placement_feedback_visual_harness: S2 failed to load")
		return
	_add_backdrop()
	var grid := Node2D.new()
	grid.name = "PlacementFeedbackGrid"
	add_child(grid)
	if not IsoGridBuilder.build_stage(grid, stage):
		push_error("placement_feedback_visual_harness: grid failed to build")
		return
	var viewport: Vector2 = get_viewport().get_visible_rect().size
	var available := Vector2(
		maxf(viewport.x - VIEW_MARGIN.x * 2.0, 1.0),
		maxf(viewport.y - VIEW_MARGIN.y * 2.0, 1.0),
	)
	var grid_scale := IsoProjection.fit_scale(stage.grid_size(), available)
	grid.scale = Vector2.ONE * grid_scale
	grid.position = IsoProjection.origin_for(stage.grid_size(), viewport, grid_scale)
	_effect_cell = _nearest_tile(stage, StageDef.Tile.ELEVATED if _profile == &"elevated" else StageDef.Tile.GROUND)
	_add_tower_proxy(grid, _effect_cell, _profile == &"elevated")
	_juice = JUICE_LAYER_SCRIPT.new()
	_juice.name = "PlacementFeedbackJuice"
	_juice.z_index = 60
	add_child(_juice)
	_juice.setup(load("res://data/juice_config.tres") as JuiceConfig, grid)
	_add_caption(viewport)


func _process(_delta: float) -> void:
	_frames += 1
	if _triggered or _frames < TRIGGER_FRAME or _juice == null:
		return
	_triggered = true
	var local_center := IsoProjection.face_center(_effect_cell, _profile == &"elevated")
	if _profile == &"elevated":
		_juice.placement_elevated(local_center)
		Sfx.play("deploy_elevated")
	else:
		_juice.placement_ground(local_center)
		Sfx.play("deploy_ground")


func _nearest_tile(stage: StageDef, tile: StageDef.Tile) -> Vector2i:
	var center := Vector2(stage.grid_size()) * 0.5
	var best := Vector2i.ZERO
	var best_distance := INF
	for y: int in stage.grid_size().y:
		for x: int in stage.grid_size().x:
			var cell := Vector2i(x, y)
			if stage.tile_at(cell) != tile:
				continue
			var distance := Vector2(cell).distance_squared_to(center)
			if distance < best_distance:
				best = cell
				best_distance = distance
	return best


func _add_tower_proxy(grid: Node2D, cell: Vector2i, elevated: bool) -> void:
	var operator_path := (
		"res://data/operators/caster_1.tres"
		if elevated
		else "res://data/operators/guard_1.tres"
	)
	var definition := load(operator_path) as OperatorDef
	var tower := Node2D.new()
	tower.name = "ElevatedTower" if elevated else "GroundTower"
	tower.position = IsoProjection.face_center(cell, elevated)
	tower.z_index = IsoProjection.entity_z(Vector2(cell) + Vector2.ONE * 0.5)
	var texture := Art.texture(definition.sprite_id, 0) if definition != null else null
	if texture != null:
		var sprite := TextureRect.new()
		sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sprite.texture = texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sprite.stretch_mode = TextureRect.STRETCH_SCALE
		var height := 58.0
		var width := height * float(texture.get_width()) / float(maxi(texture.get_height(), 1))
		sprite.size = Vector2(width, height)
		sprite.position = Vector2(-width * 0.5, IsoProjection.FEET_OFFSET - height)
		tower.add_child(sprite)
	else:
		var fallback := ColorRect.new()
		fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fallback.color = Color("7be7ff") if elevated else Color("e6b95c")
		fallback.size = Vector2(28, 42)
		fallback.position = Vector2(-14, -42)
		tower.add_child(fallback)
	grid.add_child(tower)


func _add_backdrop() -> void:
	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.color = Color("080b15")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)


func _add_caption(viewport: Vector2) -> void:
	var caption := Label.new()
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.text = "ELEVATED PLATFORM PLACEMENT" if _profile == &"elevated" else "NORMAL GROUND PLACEMENT"
	caption.add_theme_font_size_override("font_size", 28)
	caption.add_theme_color_override(
		"font_color",
		Color("b9f7ff") if _profile == &"elevated" else Color("e6b95c"),
	)
	caption.position = Vector2(32, 24)
	caption.size = Vector2(viewport.x - 64, 44)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(caption)
