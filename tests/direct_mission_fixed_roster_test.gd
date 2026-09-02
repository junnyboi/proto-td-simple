extends SceneTree

const EXPECTED_OPERATORS: Array[StringName] = [
	&"recruit", &"sniper_1", &"guard_1", &"caster_1",
]

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game := root.get_node_or_null("Game")
	_check(game != null, "Game autoload is missing")
	if game == null:
		_finish()
		return
	_check(not ResourceLoader.exists("res://scenes/squad_select.tscn"), "Field Selection scene still exists")
	_check(not ResourceLoader.exists("res://scenes/training.tscn"), "Training scene still exists")
	game.call("set_run_seed", 260901)
	_check(bool(game.call("start_campaign", false, true)), "fresh campaign could not start")
	if not bool(game.get("campaign_active")):
		_finish()
		return
	var state_before: Dictionary = game.get("campaign").data_copy()
	var xp_before := _hero_xp(state_before)
	var entitlements_before: Array = state_before["class_entitlements"].duplicate()
	_check(bool(game.call("start_campaign_stage", &"s1", false)), "campaign mission did not launch directly")
	_check(game.get("selected_stage_id") == &"s1", "direct launch selected the wrong mission")
	_check(bool(game.get("_campaign_battle_active")), "direct launch did not create an active battle ticket")
	var launch: Dictionary = game.call("battle_launch")
	_check(launch.get("fixed_operator_ids", []) == EXPECTED_OPERATORS, "battle did not expose the fixed four-operator roster")

	var stage := load("res://data/stages/s1.tres") as StageDef
	var config := (load("res://data/config/game.tres") as GameConfig).duplicate(true) as GameConfig
	config.dp_start = 999
	config.dp_cap = 999
	var operator_defs := _operator_defs()
	var model := BattleModel.create(
		stage,
		launch["input"],
		260901,
		config,
		{},
		operator_defs,
		{},
		launch["trusted_ticket_hashes"],
		launch["fixed_operator_ids"],
	)
	_check(model != null, "fixed-roster battle model could not be created")
	if model != null:
		_check(model.battle_squad == EXPECTED_OPERATORS, "deploy bar order is not Recruit, Gunner, Swordmaster, Mage Apprentice")
		var ground_cells := _valid_cells(stage, operator_defs[&"recruit"])
		_check(ground_cells.size() > stage.squad_size, "mission lacks enough ground cells for the team-limit check")
		for index: int in stage.squad_size:
			_check(
				model.apply_action([&"deploy", &"recruit", ground_cells[index], int(UnitState.Facing.RIGHT)]),
				"repeat Recruit purchase %d was rejected" % (index + 1),
			)
		_check(model.deployed_count() == stage.squad_size, "duplicate operators did not fill the team limit")
		_check(
			not model.apply_action([&"deploy", &"recruit", ground_cells[stage.squad_size], int(UnitState.Facing.RIGHT)]),
			"deployment exceeded the mission team limit",
		)
		var first_unit: UnitState = model.units[0]
		_check(model.apply_action([&"retreat", first_unit.id]), "fixed-roster retreat failed")
		model.dp = config.dp_cap
		var elevated_cells := _valid_cells(stage, operator_defs[&"sniper_1"])
		_check(not elevated_cells.is_empty(), "mission lacks an elevated Gunner cell")
		if not elevated_cells.is_empty():
			_check(
				model.apply_action([&"deploy", &"sniper_1", elevated_cells[0], int(UnitState.Facing.RIGHT)]),
				"Gunner could not be bought after a team slot reopened",
			)
		_check(model.apply_action([&"resign"]), "test battle could not reach a terminal result")
		game.set("current_battle", model)
		_check(bool(game.call("record_result", BattleModel.Result.DEFEAT, 0)), "campaign result could not commit")
		var state_after: Dictionary = game.get("campaign").data_copy()
		_check(_hero_xp(state_after) == xp_before, "mission resolution changed legacy XP state")
		_check(state_after["class_entitlements"] == entitlements_before, "mission resolution unlocked a class path")
		_check(not (game.get("last_result") as Dictionary).has("xp_awards"), "results still publish XP awards")
	_cleanup(game)
	_finish()


func _operator_defs() -> Dictionary:
	var definitions := {}
	for operator_id: StringName in EXPECTED_OPERATORS:
		var definition := load("res://data/operators/%s.tres" % operator_id) as OperatorDef
		definitions[operator_id] = definition
	return definitions


func _valid_cells(stage: StageDef, definition: OperatorDef) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y: int in stage.grid_size().y:
		for x: int in stage.grid_size().x:
			var cell := Vector2i(x, y)
			if stage.operator_cell_in_domain(definition, cell):
				cells.append(cell)
	return cells


func _hero_xp(data: Dictionary) -> Dictionary:
	var result := {}
	for hero: Dictionary in data["heroes"]:
		result[String(hero["hero_id"])] = int(hero["xp"])
	return result


func _cleanup(game: Node) -> void:
	game.call("_reset_campaign_runtime")
	var music := root.get_node_or_null("Music")
	if music != null:
		music.call("stop")
	var sfx := root.get_node_or_null("Sfx")
	if sfx != null and sfx.has_method("stop_all"):
		sfx.call("stop_all")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("DIRECT_MISSION_FIXED_ROSTER_TEST_OK")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)
