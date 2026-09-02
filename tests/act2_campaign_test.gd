extends SceneTree

const PRE_ACT2_ENVIRONMENT := "36abb05ea24ba5be2d406f4a748c5ab947276b697147dc5d32fdfe930cd95fa3"

var _failures := PackedStringArray()


func _init() -> void:
	_test_catalog_and_balance()
	_test_progression_and_save_compatibility()
	if _failures.is_empty():
		print("ACT2_CAMPAIGN_TEST_OK")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)


func _test_catalog_and_balance() -> void:
	var context := CampaignRuntimeContext.build()
	_check(not context.is_empty(), "sixteen-stage campaign context failed to build")
	if context.is_empty():
		return
	var stage_order: Array = context["stage_order"]
	_check(stage_order.size() == 16, "campaign stage order is not sixteen operations")
	for index: int in 16:
		_check(stage_order[index] == "s%d" % (index + 1), "campaign stage order is noncanonical")
	var reward_rows: Array = context["campaign"]["v3_stage_rewards"]
	_check(reward_rows.size() == 16, "V3 reward projection is not one row per operation")
	for index: int in range(8, 16):
		var rewards: Array = reward_rows[index]["rewards"]
		_check(
			rewards == [{"amount": 40, "id": "marks", "kind": "currency"}],
			"Act II first-clear reward drifted for s%d" % (index + 1),
		)

	var prior_enemy_count := 17
	for stage_index: int in range(9, 17):
		var stage := load("res://data/stages/s%d.tres" % stage_index) as StageDef
		_check(stage != null, "Act II stage s%d failed to load" % stage_index)
		if stage == null:
			continue
		_check(stage.campaign_index == stage_index, "Act II campaign index drifted")
		_check(stage.paths.size() >= 2 and stage.paths.size() <= 4, "Act II path-count envelope drifted")
		_check(stage.waves.size() >= 18 and stage.waves.size() <= 32, "Act II enemy-count envelope drifted")
		_check(stage.waves.size() >= prior_enemy_count, "Act II enemy count regressed between operations")
		prior_enemy_count = stage.waves.size()
		_check(stage.wave_starts.size() >= 3, "Act II stage lacks three wave windows")
		_check(stage.squad_size == 6, "Act II squad size drifted")
		_check(stage.leak_limit >= 1 and stage.leak_limit <= 3, "Act II leak limit left the design envelope")
		_check(stage.restoration_contract_errors().is_empty(), "Act II restoration contract is invalid")
		_check(not stage.restoration_cells.is_empty(), "Act II stage omitted its signature mechanic")
		for spawn: Dictionary in stage.waves:
			_check(
				load("res://data/enemies/%s.tres" % String(spawn["enemy_id"])) is EnemyDef,
				"Act II wave references an unknown enemy",
			)
		if stage_index == 16:
			var boss_ticks := PackedInt32Array()
			for spawn: Dictionary in stage.waves:
				if StringName(spawn["enemy_id"]) == &"mini_boss":
					boss_ticks.append(int(spawn["tick"]))
			_check(boss_ticks.size() == 2, "S16 no longer has two Gatecrasher-class boss windows")
			_check(
				boss_ticks.size() == 2 and boss_ticks[0] != boss_ticks[1],
				"S16 Gatecrasher-class bosses no longer arrive in separate windows",
			)
		_test_terminal_schedule(stage)


func _test_terminal_schedule(source: StageDef) -> void:
	var stage := source.duplicate(true) as StageDef
	stage.leak_limit = 1000
	var enemy_defs := {}
	for spawn: Dictionary in stage.waves:
		var enemy_id := StringName(spawn["enemy_id"])
		if not enemy_defs.has(enemy_id):
			enemy_defs[enemy_id] = load("res://data/enemies/%s.tres" % String(enemy_id)) as EnemyDef
	var config := GameConfig.new()
	config.base_hp_start = 1000
	var model := BattleModel.create(stage, [], 2000 + stage.campaign_index, config, enemy_defs)
	_check(model != null, "%s terminal fixture failed to create" % stage.id)
	if model == null:
		return
	var bounded_ticks := 6000
	while model.result == BattleModel.Result.RUNNING and model.tick < bounded_ticks:
		model.step()
	_check(model.result == BattleModel.Result.CLEAR, "%s schedule did not terminate deterministically" % stage.id)
	_check(model.tick < bounded_ticks, "%s exceeded the bounded terminal window" % stage.id)


func _test_progression_and_save_compatibility() -> void:
	var context := CampaignRuntimeContext.build()
	if context.is_empty():
		return
	var created: Dictionary = CampaignStateV3.create(2216, 1, context)
	_check(created.get("accepted", false), "fresh Act II campaign failed to create")
	if not created.get("accepted", false):
		return
	var state = created["value"]
	var data: Dictionary = state.data_copy()
	_check(
		not CampaignV3Attempts._validate_stage(data, context, "s9")["accepted"],
		"S9 unlocked before S8 cleared",
	)
	for stage_index: int in range(1, 9):
		data["stage_stars"].append({"stage_id": "s%d" % stage_index, "stars": 1})
	_check(
		CampaignV3Attempts._validate_stage(data, context, "s9")["accepted"],
		"S9 remained locked after an ordered S1–S8 clear prefix",
	)

	var previous_context: Dictionary = context.duplicate(true)
	previous_context["stage_order"] = (previous_context["stage_order"] as Array).slice(0, 8)
	var previous_sizes := {}
	for stage_id: String in previous_context["stage_order"]:
		previous_sizes[stage_id] = context["stage_squad_sizes"][stage_id]
	previous_context["stage_squad_sizes"] = previous_sizes
	previous_context["campaign"]["v3_stage_rewards"] = (
		(previous_context["campaign"]["v3_stage_rewards"] as Array).slice(0, 8)
	)
	previous_context["environment_sha256"] = PRE_ACT2_ENVIRONMENT
	var previous: Dictionary = CampaignStateV3.create(2217, 1, previous_context)
	_check(previous.get("accepted", false), "Act I-only historical fixture failed to create")
	if not previous.get("accepted", false):
		return
	var encoded: Dictionary = previous["value"].encode_save()
	var restored: Dictionary = CampaignStateV3.restore_source(encoded.get("text", ""), context)
	_check(restored.get("accepted", false), "Act I-only V3 save did not restore into Act II context")
	if restored.get("accepted", false):
		var projection: Dictionary = restored["value"].runtime_projection()
		_check(projection["marks"] == 120, "Act II restore changed historical Marks")
		_check((projection["stage_stars"] as Dictionary).is_empty(), "Act II restore invented stage clears")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
