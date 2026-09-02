extends SceneTree

const DamageRulesScript := preload("res://sim/damage_rules.gd")
const CampaignRuntimeContextScript := preload("res://sim/campaign_runtime_context.gd")

var _failures := PackedStringArray()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_validate_enemy_definitions()
	_validate_caster_arts_counterplay()
	_validate_stage_schedules()
	_validate_interceptor_attack_authority()
	_validate_campaign_context()
	if _failures.is_empty():
		print("EARLY_ENEMY_VARIETY_OK")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)


func _validate_enemy_definitions() -> void:
	var shieldbearer := _enemy(&"shieldbearer")
	_check(shieldbearer != null, "Shieldbearer resource must load")
	if shieldbearer != null:
		_check(shieldbearer.hp == 60, "Shieldbearer HP must remain 60")
		_check(shieldbearer.atk == 6, "Shieldbearer ATK must remain 6")
		_check(shieldbearer.defense == 7, "Shieldbearer Defense must remain 7")
		_check(shieldbearer.resistance_permille == 0, "Shieldbearer must not resist Arts")
		_check(is_equal_approx(shieldbearer.speed_tiles_per_s, 0.75), "Shieldbearer speed must remain 0.75")
		_check(shieldbearer.block_weight == 1 and not shieldbearer.aerial, "Shieldbearer must be a one-block ground enemy")

	var breacher := _enemy(&"breacher")
	_check(breacher != null, "Breacher resource must load")
	if breacher != null:
		_check(breacher.hp == 90, "Breacher HP must remain 90")
		_check(breacher.atk == 10, "Breacher ATK must remain 10")
		_check(breacher.defense == 2, "Breacher Defense must remain 2")
		_check(is_equal_approx(breacher.speed_tiles_per_s, 0.65), "Breacher speed must remain 0.65")
		_check(breacher.block_weight == 2 and not breacher.aerial, "Breacher must consume two block capacity")

	var interceptor := _enemy(&"interceptor")
	_check(interceptor != null, "Interceptor resource must load")
	if interceptor != null:
		_check(interceptor.hp == 50, "Interceptor HP must remain 50")
		_check(interceptor.atk == 5, "Interceptor ATK must remain 5")
		_check(is_equal_approx(interceptor.speed_tiles_per_s, 0.9), "Interceptor speed must remain 0.9")
		_check(interceptor.aerial and interceptor.block_weight == 0, "Interceptor must bypass ground blocking")
		_check(interceptor.atk_range_cells == 2, "Interceptor must retain its short two-cell attack range")
		_check(interceptor.target_policy.id == &"enemy_blocker_then_nearest", "Interceptor must target nearby deployed units")


func _validate_caster_arts_counterplay() -> void:
	var caster_1 := load("res://data/operators/caster_1.tres") as OperatorDef
	var guard := load("res://data/operators/guard_1.tres") as OperatorDef
	var shieldbearer := _enemy(&"shieldbearer")
	_check(caster_1 != null and guard != null, "Mage Apprentice and Swordmaster fixtures must load")
	if caster_1 == null or guard == null or shieldbearer == null:
		return
	_check(caster_1.attack_damage_kind == DamageRulesScript.Kind.ARTS, "Mage Apprentice basic attacks must be Arts")
	_check(guard.attack_damage_kind == DamageRulesScript.Kind.PHYSICAL, "Swordmaster must remain Physical")
	var caster_hit := DamageRulesScript.resolve(
		caster_1.atk,
		caster_1.attack_damage_kind,
		shieldbearer.defense,
		shieldbearer.resistance_permille,
	)
	var guard_hit := DamageRulesScript.resolve(
		guard.atk,
		guard.attack_damage_kind,
		shieldbearer.defense,
		shieldbearer.resistance_permille,
	)
	_check(caster_hit == 9, "Mage Apprentice must deal 9 Arts damage through Shieldbearer armor")
	_check(guard_hit == 3, "Swordmaster must deal 3 Physical damage after Shieldbearer armor")
	_check(caster_hit == guard_hit * 3, "Shieldbearer must teach a clear three-to-one Caster damage advantage")


func _validate_stage_schedules() -> void:
	var s2 := _stage(&"s2")
	var s3 := _stage(&"s3")
	var s4 := _stage(&"s4")
	_check(s2 != null and s3 != null and s4 != null, "S2-S4 fixtures must load")
	if s2 == null or s3 == null or s4 == null:
		return
	_check(s2.waves.size() == 10, "S2 must preserve ten total spawns")
	_check(_enemy_count(s2, &"shieldbearer") == 1, "S2 must contain exactly one Shieldbearer")
	_check(_enemy_count(s2, &"grunt") == 3 and _enemy_count(s2, &"runner") == 6, "S2 one-for-one composition must remain 3/6/1")
	_check(_has_spawn(s2, &"shieldbearer", 0, 420), "S2 Shieldbearer must open wave two at tick 420 on path zero")
	_check(s2.wave_starts == PackedInt32Array([0, 390]), "S2 wave boundaries must remain unchanged")

	_check(s3.waves.size() == 9, "S3 must preserve nine total spawns")
	_check(_enemy_count(s3, &"breacher") == 2, "S3 must contain exactly two Breachers")
	_check(_enemy_count(s3, &"grunt") == 1 and _enemy_count(s3, &"runner") == 6, "S3 one-for-one composition must remain 1/6/2")
	_check(_has_spawn(s3, &"breacher", 0, 450), "S3 first Breacher must arrive at tick 450 on path zero")
	_check(_has_spawn(s3, &"breacher", 1, 570), "S3 second Breacher must alternate to path one at tick 570")
	_check(s3.wave_starts == PackedInt32Array([0, 390]), "S3 wave boundaries must remain unchanged")

	_check(s4.waves.size() == 11, "S4 must preserve eleven total spawns")
	_check(_enemy_count(s4, &"interceptor") == 2, "S4 must contain exactly two Interceptors")
	_check(_enemy_count(s4, &"drone") == 3 and _enemy_count(s4, &"grunt") == 4 and _enemy_count(s4, &"runner") == 2, "S4 one-for-one composition must remain 4/2/3/2")
	_check(_has_spawn(s4, &"interceptor", 0, 510), "S4 first Interceptor must lead the first mixed air pair at tick 510")
	_check(_has_spawn(s4, &"drone", 0, 540), "S4 first Interceptor must retain a Drone escort at tick 540")
	_check(_has_spawn(s4, &"interceptor", 0, 750), "S4 second Interceptor must lead the closing air pair at tick 750")
	_check(_has_spawn(s4, &"drone", 0, 810), "S4 closing Interceptor must retain a Drone escort at tick 810")
	_check(s4.wave_starts == PackedInt32Array([0, 390]), "S4 wave boundaries must remain unchanged")


func _validate_campaign_context() -> void:
	var context := CampaignRuntimeContextScript.build()
	_check(not context.is_empty(), "Early enemy variety must preserve a valid production campaign context")
	if not context.is_empty():
		_check(
			String(context.get("environment_sha256", "")) == CampaignDef.P16_V3_ENVIRONMENT_SHA256,
			"Early enemy variety environment hash must remain pinned to the production campaign",
		)


func _validate_interceptor_attack_authority() -> void:
	var stage := (load("res://data/stages/s4.tres") as StageDef).duplicate(true) as StageDef
	stage.waves = []
	stage.wave_starts = PackedInt32Array()
	var config := (load("res://data/config/game.tres") as GameConfig).duplicate(true) as GameConfig
	var enemy_defs := _load_catalog("res://data/enemies")
	var operator_defs := _load_catalog("res://data/operators")
	var model := BattleModel.create(stage, stage.recovery_roster, 4404, config, enemy_defs, operator_defs)
	_check(model != null, "Interceptor authority fixture must create")
	if model == null:
		return
	model.dp = config.dp_cap
	var deployed := model.apply_action([&"deploy", &"guard_1", Vector2i(8, 1), UnitState.Facing.LEFT])
	_check(deployed, "Interceptor authority fixture must deploy a target")
	if not deployed:
		return
	model._spawn({"enemy_id": &"interceptor", "path_idx": 0})
	var interceptor := model.enemies[-1] as EnemyState
	var path := model.path_for(0)
	var closest_index := 0
	var closest_distance := 999
	for index: int in range(path.size()):
		var distance := maxi(absi(path[index].x - 8), absi(path[index].y - 1))
		if distance < closest_distance:
			closest_distance = distance
			closest_index = index
	interceptor.progress_units = closest_index * Pathing.PROGRESS_SCALE
	var decision := TargetDecisionProjection.enemy_target_decision(model, interceptor.id)
	_check(int(decision.get("selected_id", -1)) >= 0, "Interceptor must acquire a nearby deployed operator")
	var defender := model.units[0] as UnitState
	var hp_before := defender.hp
	model._tick_combat()
	_check(defender.hp < hp_before, "Interceptor authoritative attack must damage its selected operator")
	_check(interceptor.atk_counter == interceptor.atk_interval_ticks - 1, "Interceptor attack must start its authoritative cooldown")
func _enemy(enemy_id: StringName) -> EnemyDef:
	return load("res://data/enemies/%s.tres" % enemy_id) as EnemyDef


func _stage(stage_id: StringName) -> StageDef:
	return load("res://data/stages/%s.tres" % stage_id) as StageDef


func _load_catalog(path: String) -> Dictionary:
	var result: Dictionary = {}
	for filename: String in DirAccess.get_files_at(path):
		if not filename.ends_with(".tres"):
			continue
		var resource := load("%s/%s" % [path, filename])
		if resource != null and "id" in resource:
			result[resource.id] = resource
	return result


func _enemy_count(stage: StageDef, enemy_id: StringName) -> int:
	var count := 0
	for spawn: Dictionary in stage.waves:
		if StringName(spawn.get("enemy_id", &"")) == enemy_id:
			count += 1
	return count


func _has_spawn(stage: StageDef, enemy_id: StringName, path_idx: int, tick: int) -> bool:
	for spawn: Dictionary in stage.waves:
		if (
			StringName(spawn.get("enemy_id", &"")) == enemy_id
			and int(spawn.get("path_idx", -1)) == path_idx
			and int(spawn.get("tick", -1)) == tick
		):
			return true
	return false


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
