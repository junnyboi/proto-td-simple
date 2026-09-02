class_name BattleObservation
extends RefCounted

## Read-only, primitive-only projection of BattleModel. The model remains the
## database; consumers receive deep copies and can never retain model objects.

const SCHEMA_ID := "prototype_td_battle_observation"
const VERSION := 3
const UPCOMING_SECONDS := 10

var _value: Dictionary = {}


static func from_model(model: BattleModel) -> BattleObservation:
	var observation := BattleObservation.new()
	observation._value = observation._project(model)
	return observation


func to_dictionary() -> Dictionary:
	return _value.duplicate(true)


func sha256() -> String:
	return CanonicalJson.sha256_hex(_value)


func progress_signature() -> String:
	var value := to_dictionary()
	value.erase("tick")
	return CanonicalJson.sha256_hex(value)


func _project(model: BattleModel) -> Dictionary:
	var paths := _project_paths(model)
	return {
		"schema_id": SCHEMA_ID,
		"version": VERSION,
		"tick": model.tick,
		"ticks_per_second": model.config.ticks_per_second,
		"dp": model.dp,
		"base_hp": model.base_hp,
		"result": _result_text(model.result),
		"terminal_cause": _terminal_cause(model),
		"timeline": _project_timeline(model),
		"deployability": _project_deployability(model),
		"operators": _project_operators(model),
		"trap_readiness": _project_trap_readiness(model),
		"traps": _project_traps(model),
		"traps_placed_total": model._next_trap_id,
		"enemies": _project_enemies(model),
		"paths": paths,
	}


func _project_timeline(model: BattleModel) -> Dictionary:
	var next_tick := -1
	if model.timeline.next_index < model.timeline.entries.size():
		next_tick = int(model.timeline.entries[model.timeline.next_index]["tick"])
	return {
		"next_index": model.timeline.next_index,
		"entry_count": model.timeline.entries.size(),
		"remaining_count": model.timeline.entries.size() - model.timeline.next_index,
		"next_spawn_tick": next_tick,
		"wave_index": model.stage.wave_index_at(model.tick),
		"exhausted": model.timeline.exhausted(),
	}


func _project_deployability(model: BattleModel) -> Array:
	var ids: Array[String] = []
	for op_id: StringName in model.squad:
		ids.append(String(op_id))
	ids.sort()
	var rows: Array = []
	for text_id: String in ids:
		var op_id := StringName(text_id)
		var cost := -1
		if model._op_defs.has(op_id):
			cost = (model._op_defs[op_id] as OperatorDef).dp_cost
		rows.append({
			"op_id": text_id,
			"dp_cost": cost,
			"ready": model.is_deployable(op_id),
		})
	return rows


func _project_operators(model: BattleModel) -> Array:
	var source: Array = model.units.duplicate()
	source.sort_custom(func(a: UnitState, b: UnitState) -> bool: return a.id < b.id)
	var rows: Array = []
	for unit: UnitState in source:
		var blocked_weight := 0
		for enemy_id: int in unit.blocked_ids:
			var blocked_enemy := _enemy_by_id(model, enemy_id)
			if blocked_enemy != null:
				blocked_weight += blocked_enemy.block_weight
		var row := {
			"id": unit.id,
			"op_id": String(unit.op_id),
			"alive": unit.alive,
			"cell": _cell(unit.cell),
			"path_idx": _path_index_for_cell(model, unit.cell),
			"facing": int(unit.facing),
			"hp": unit.hp,
			"hp_max": unit.hp_max,
			"block": unit.block,
			"effective_block": unit.effective_block(),
			"blocked_weight": blocked_weight,
			"sp": unit.sp,
			"sp_cost": unit.sp_cost,
			"skill_id": String(unit.skill_id),
			"skill_ready": unit.is_skill_ready(),
		}
		if not unit.battle_id.is_empty():
			row["battle_id"] = String(unit.battle_id)
			row["hero_id"] = String(unit.hero_id)
			row["class_id"] = String(unit.class_id)
		rows.append(row)
	return rows

func _project_trap_readiness(model: BattleModel) -> Array:
	var ids: Array[String] = []
	for trap_id: StringName in model._trap_defs:
		ids.append(String(trap_id))
	ids.sort()
	var rows: Array = []
	for text_id: String in ids:
		var trap_id := StringName(text_id)
		var definition := model._trap_defs[trap_id] as TrapDef
		rows.append({
			"trap_id": text_id,
			"dp_cost": definition.dp_cost,
			"ready": model.is_trap_placeable(trap_id),
		})
	return rows


func _project_traps(model: BattleModel) -> Array:
	var source: Array = model.traps.duplicate()
	source.sort_custom(func(a: TrapState, b: TrapState) -> bool: return a.id < b.id)
	var rows: Array = []
	for trap: TrapState in source:
		rows.append({
			"id": trap.id,
			"trap_id": String(trap.def_id),
			"cell": _cell(trap.cell),
			"path_idx": _path_index_for_cell(model, trap.cell),
			"charges_left": trap.charges_left,
		})
	return rows


func _project_enemies(model: BattleModel) -> Array:
	var source: Array = model.enemies.duplicate()
	source.sort_custom(func(a: EnemyState, b: EnemyState) -> bool: return a.id < b.id)
	var rows: Array = []
	for enemy: EnemyState in source:
		if not enemy.alive:
			continue
		rows.append({
			"id": enemy.id,
			"enemy_id": String(enemy.def_id),
			"hp": enemy.hp,
			"hp_max": enemy.hp_max,
			"path_idx": enemy.path_idx,
			"progress_units": enemy.progress_units,
			"step_units": enemy.step_units,
			"aerial": enemy.aerial,
			"block_weight": enemy.block_weight,
			"leak_damage": enemy.leak_damage,
			"blocked_by": enemy.blocked_by,
			"threat": enemy.leak_damage * 1000 + enemy.block_weight * 100 + enemy.hp,
		})
	return rows


func _project_paths(model: BattleModel) -> Array:
	var rows: Array = []
	for path_idx: int in model._paths.size():
		rows.append(_project_path(model, path_idx))
	return rows


func _project_path(model: BattleModel, path_idx: int) -> Dictionary:
	var active_count := 0
	var leak_damage := 0
	var block_weight := 0
	var ground_block_weight := 0
	var ground_count := 0
	var aerial_count := 0
	var blocked_weight := 0
	var base_eta := -1
	for enemy: EnemyState in model.enemies:
		if not _is_active_enemy(enemy, path_idx):
			continue
		active_count += 1
		leak_damage += enemy.leak_damage
		block_weight += enemy.block_weight
		if enemy.aerial:
			aerial_count += 1
		else:
			ground_count += 1
			ground_block_weight += enemy.block_weight
		if enemy.blocked_by >= 0:
			blocked_weight += enemy.block_weight
		base_eta = _minimum_eta(
			base_eta,
			model._path_lengths[path_idx] - enemy.progress_units,
			enemy.step_units,
		)
	var capacity := _path_capacity(model, path_idx)
	var saturation := 0
	if capacity > 0:
		@warning_ignore("integer_division")
		saturation = blocked_weight * 1000 / capacity
	var overflow := maxi(0, ground_block_weight - capacity)
	var upcoming := _upcoming(model, path_idx)
	var contact_eta := _nearest_contact_eta(model, path_idx)
	var uncountered := aerial_count > 0 and not _has_alive_sniper(model)
	var pressure := leak_damage * 100 + block_weight * 50 + active_count * 10
	pressure += overflow * 100 + aerial_count * 75
	return {
		"path_idx": path_idx,
		"active_count": active_count,
		"leak_damage": leak_damage,
		"block_weight": block_weight,
		"ground_count": ground_count,
		"aerial_count": aerial_count,
		"blocked_weight": blocked_weight,
		"effective_block_capacity": capacity,
		"saturation_permille": saturation,
		"overflow_weight": overflow,
		"nearest_blocker_contact_eta": contact_eta,
		"minimum_unopposed_base_eta": base_eta,
		"upcoming_count": upcoming["count"],
		"upcoming_leak_damage": upcoming["leak_damage"],
		"upcoming_block_weight": upcoming["block_weight"],
		"upcoming_aerial_count": upcoming["aerial_count"],
		"upcoming_mass": (
			int(upcoming["count"])
			+ int(upcoming["leak_damage"])
			+ int(upcoming["block_weight"])
		),
		"uncountered_aerial": uncountered,
		"pressure": pressure,
	}


func _upcoming(model: BattleModel, path_idx: int) -> Dictionary:
	var out := {"count": 0, "leak_damage": 0, "block_weight": 0, "aerial_count": 0}
	var exclusive_end := model.tick + UPCOMING_SECONDS * model.config.ticks_per_second
	for index: int in range(model.timeline.next_index, model.timeline.entries.size()):
		var entry: Dictionary = model.timeline.entries[index]
		var spawn_tick := int(entry["tick"])
		if spawn_tick >= exclusive_end:
			break
		if spawn_tick < model.tick or int(entry["path_idx"]) != path_idx:
			continue
		var definition := model._defs[entry["enemy_id"]] as EnemyDef
		out["count"] = int(out["count"]) + 1
		out["leak_damage"] = int(out["leak_damage"]) + definition.leak_damage
		out["block_weight"] = int(out["block_weight"]) + definition.block_weight
		if definition.aerial:
			out["aerial_count"] = int(out["aerial_count"]) + 1
	return out


func _path_capacity(model: BattleModel, path_idx: int) -> int:
	var capacity := 0
	for unit: UnitState in model.units:
		if unit.alive and _cell_on_path(model, path_idx, unit.cell):
			capacity += unit.effective_block()
	return capacity


func _nearest_contact_eta(model: BattleModel, path_idx: int) -> int:
	var blocker_progresses: Array[int] = []
	var path: Array[Vector2i] = model.path_for(path_idx)
	for unit: UnitState in model.units:
		if not unit.alive or unit.effective_block() <= 0:
			continue
		var cell_index := path.find(unit.cell)
		if cell_index >= 0:
			blocker_progresses.append(cell_index * Pathing.PROGRESS_SCALE)
	var nearest := -1
	for enemy: EnemyState in model.enemies:
		if not _is_active_enemy(enemy, path_idx) or enemy.aerial or enemy.blocked_by >= 0:
			continue
		for blocker_progress: int in blocker_progresses:
			if blocker_progress < enemy.progress_units:
				continue
			nearest = _minimum_eta(
				nearest, blocker_progress - enemy.progress_units, enemy.step_units
			)
	return nearest


func _minimum_eta(current: int, distance: int, step_units: int) -> int:
	if step_units <= 0:
		return current
	var eta := _ceil_div(maxi(0, distance), step_units)
	return eta if current < 0 else mini(current, eta)


func _ceil_div(numerator: int, denominator: int) -> int:
	if numerator <= 0:
		return 0
	@warning_ignore("integer_division")
	return (numerator + denominator - 1) / denominator


func _path_index_for_cell(model: BattleModel, cell: Vector2i) -> int:
	for path_idx: int in model._paths.size():
		if _cell_on_path(model, path_idx, cell):
			return path_idx
	return -1


func _cell_on_path(model: BattleModel, path_idx: int, cell: Vector2i) -> bool:
	return model.path_for(path_idx).has(cell)


func _has_alive_sniper(model: BattleModel) -> bool:
	for unit: UnitState in model.units:
		if unit.alive and unit.op_class == OperatorDef.OpClass.SNIPER:
			return true
	return false


func _enemy_by_id(model: BattleModel, enemy_id: int) -> EnemyState:
	for enemy: EnemyState in model.enemies:
		if enemy.id == enemy_id:
			return enemy
	return null


func _is_active_enemy(enemy: EnemyState, path_idx: int) -> bool:
	return (
		enemy.alive
		and enemy.path_idx == path_idx
	)


func _terminal_cause(model: BattleModel) -> String:
	if model.result == BattleModel.Result.CLEAR:
		return "clear"
	if model.result != BattleModel.Result.DEFEAT:
		return ""
	if model.leaked > model.stage.leak_limit:
		return "leak_defeat"
	if model.base_hp <= 0:
		return "base_defeat"
	return "resign"


func _result_text(result: int) -> String:
	match result:
		BattleModel.Result.CLEAR:
			return "clear"
		BattleModel.Result.DEFEAT:
			return "defeat"
		_:
			return "running"


func _cell(value: Vector2i) -> Dictionary:
	return {"x": value.x, "y": value.y}


static func recursive_primitive_only(value: Variant) -> bool:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return true
		TYPE_ARRAY:
			for item: Variant in value:
				if not recursive_primitive_only(item):
					return false
			return true
		TYPE_DICTIONARY:
			for key: Variant in value:
				if typeof(key) != TYPE_STRING or not recursive_primitive_only(value[key]):
					return false
			return true
		_:
			return false
