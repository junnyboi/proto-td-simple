extends SceneTree

const ELEVATED_OPERATOR_PATHS := [
	"res://data/operators/caster_1.tres",
	"res://data/operators/sniper_1.tres",
]
const PICK_OFFSETS := [
	Vector2.ZERO,
	Vector2(0.0, -6.0),
	Vector2(12.0, 0.0),
	Vector2(-12.0, 0.0),
	Vector2(0.0, 6.0),
]

var _failures := PackedStringArray()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var config := load("res://data/config/game.tres") as GameConfig
	var ground_definition := load("res://data/operators/guard_1.tres") as OperatorDef
	_check(config != null, "game config failed to load")
	_check(ground_definition != null, "ground operator failed to load")
	var elevated_defs: Array[OperatorDef] = []
	for path: String in ELEVATED_OPERATOR_PATHS:
		var definition := load(path) as OperatorDef
		_check(definition != null, "elevated operator failed to load: %s" % path)
		if definition == null:
			continue
		_check(
			definition.placement == OperatorDef.Placement.ELEVATED,
			"operator is not authored for elevated placement: %s" % definition.id,
		)
		elevated_defs.append(definition)
	var total_platforms := 0
	for stage_number: int in range(1, 11):
		var stage := load("res://data/stages/s%d.tres" % stage_number) as StageDef
		_check(stage != null, "stage failed to load: s%d" % stage_number)
		if stage == null:
			continue
		total_platforms += _verify_stage_variant(
			"s%d landscape" % stage_number,
			stage,
			elevated_defs,
			ground_definition,
			config,
			stage_number * 100,
		)
		var portrait := stage.clockwise_rotated_copy()
		_verify_stage_variant(
			"s%d portrait" % stage_number,
			portrait,
			elevated_defs,
			ground_definition,
			config,
			stage_number * 100 + 50,
		)
	_check(total_platforms == 54, "expected 54 raised platforms, got %d" % total_platforms)
	if _failures.is_empty():
		print("ELEVATED_PLATFORM_ACCESSIBILITY_TEST_OK platforms=%d" % total_platforms)
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)


func _verify_stage_variant(
	label: String,
	stage: StageDef,
	elevated_defs: Array[OperatorDef],
	ground_definition: OperatorDef,
	config: GameConfig,
	seed_base: int,
) -> int:
	var elevated_cells: Array[Vector2i] = []
	for y: int in stage.grid_size().y:
		for x: int in stage.grid_size().x:
			var cell := Vector2i(x, y)
			if stage.is_elevated_platform(cell):
				elevated_cells.append(cell)
	_check(not elevated_cells.is_empty(), "%s has no elevated platforms" % label)
	var is_lifted := func(candidate: Vector2i) -> bool:
		return stage.is_elevated_platform(candidate)
	for cell: Vector2i in elevated_cells:
		if ground_definition != null:
			_check(
				not stage.operator_cell_in_domain(ground_definition, cell),
				"%s allows ground operator onto raised platform %s" % [label, cell],
			)
		for offset: Vector2 in PICK_OFFSETS:
			var point := IsoProjection.face_center(cell, true) + offset
			_check(
				IsoProjection.pick(point, is_lifted) == cell,
				"%s elevated face hit-test drift at %s offset %s" % [label, cell, offset],
			)
		for definition: OperatorDef in elevated_defs:
			_check(
				stage.operator_cell_in_domain(definition, cell),
				"%s rejects %s from elevated platform %s" % [label, definition.id, cell],
			)
			_check(
				BattleTicketRuntime.cell_in_domain(
					{"combat_spec": {"placement": int(definition.placement)}},
					stage,
					cell,
				),
				"%s ticket rejects %s from elevated platform %s" % [label, definition.id, cell],
			)
			if config == null:
				continue
			var model := BattleModel.create(
				stage,
				[definition.id],
				seed_base + elevated_cells.find(cell),
				config,
				{},
				{definition.id: definition},
			)
			_check(model != null, "%s BattleModel failed for %s" % [label, definition.id])
			if model == null:
				continue
			model.dp = model.config.dp_cap
			_check(
				model.can_deploy_at(definition.id, cell),
				"%s BattleModel rejects %s from elevated platform %s" % [
					label,
					definition.id,
					cell,
				],
			)
	return elevated_cells.size()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
