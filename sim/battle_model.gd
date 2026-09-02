class_name BattleModel
extends RefCounted

## Authoritative battle state is engine-independent integer data advanced one
## deterministic tick at a time. Runtime nodes only project this state.
##
## Each tick advances existing enemies and resolves leaks, spawns scheduled
## enemies, resolves combat and abilities, and then evaluates terminal state.
## Mutable state that affects battle outcomes must be included in state_hash().

enum Result { RUNNING, CLEAR, DEFEAT }

const STANDARD_RETREAT_COOLDOWN_SECONDS := 10
const VANGUARD_RETREAT_COOLDOWN_SECONDS := 3

const HealingRulesScript := preload("res://sim/healing_rules.gd")
const EnemyDamageScript := preload("res://sim/enemy_damage.gd")
const DamageRulesScript := preload("res://sim/damage_rules.gd")
const TargetDecisionProjectionScript := preload("res://sim/target_decision_projection.gd")
const TargetPolicyDefScript := preload("res://data/target_policy_def.gd")
const BattleTicketRuntimeScript := preload("res://sim/battle_ticket_runtime.gd")
const BattleOutcomeBuilderScript := preload("res://sim/battle_outcome_builder.gd")

var stage: StageDef = null
var squad: Array[StringName] = []
var run_seed: int = 0
var config: GameConfig = null
var battle_squad: Array[StringName] = []
var terminal_reason: StringName = &""

var tick: int = 0
var base_hp: int = 0
var result: Result = Result.RUNNING
var stars: int = 0
var spawned: int = 0
var leaked: int = 0
var killed: int = 0
var enemies: Array[EnemyState] = []
var timeline: WaveTimeline = null

var dp: int = 0
var dp_regen_counter: int = 0
var dp_regen_accrued: int = 0
var dp_vanguard_generated: int = 0
var dp_refunded: int = 0
var dp_spent: int = 0
var dp_lost_to_cap: int = 0
var dp_skill_granted: int = 0
var retreated: int = 0
var redeploy_ready_tick_by_id: Dictionary = {}
var fixed_operator_roster: Array[StringName] = []
var skills_fired: int = 0
var units: Array[UnitState] = []
var traps: Array[TrapState] = []
var traps_triggered: int = 0

var _defs: Dictionary = {}
var _op_defs: Dictionary = {}
var _trap_defs: Dictionary = {}
var _paths: Array = []
var _path_lengths: Array[int] = []
var _next_enemy_id: int = 0
var _next_unit_id: int = 0
var _next_trap_id: int = 0
var _ticket: Dictionary = {}
var _ticket_rows: Dictionary = {}
var _battle_records: Array[Dictionary] = []
var _outcome: Dictionary = {}


static func create(
	stage_def: StageDef,
	battle_input: Variant,
	seed_value: int,
	game_config: GameConfig,
	enemy_defs: Dictionary,
	operator_defs: Dictionary = {},
	trap_defs: Dictionary = {},
	trusted_ticket_hashes: Array = [],
	fixed_operator_ids: Array = [],
) -> BattleModel:
	var model := BattleModel.new()
	model.stage = stage_def
	model._op_defs = operator_defs
	if not BattleTicketRuntimeScript.configure(
		model, battle_input, stage_def, seed_value, trusted_ticket_hashes,
	):
		return null
	if not model._configure_fixed_operator_roster(fixed_operator_ids):
		return null
	model.config = game_config
	model.base_hp = game_config.base_hp_start
	model.dp = game_config.dp_start
	model._defs = enemy_defs
	model._trap_defs = trap_defs
	model.timeline = WaveTimeline.from_waves(stage_def.waves)
	for i: int in stage_def.paths.size():
		var cells := stage_def.path_cells(i)
		model._paths.append(cells)
		model._path_lengths.append(Pathing.length_units(cells))
	return model


func _configure_fixed_operator_roster(operator_ids: Array) -> bool:
	if operator_ids.is_empty():
		return true
	var seen := {}
	for raw_id: Variant in operator_ids:
		if typeof(raw_id) not in [TYPE_STRING, TYPE_STRING_NAME]:
			return false
		var operator_id := StringName(raw_id)
		if seen.has(operator_id) or not _op_defs.has(operator_id):
			return false
		seen[operator_id] = true
		fixed_operator_roster.append(operator_id)
	if fixed_operator_roster.is_empty():
		return false
	battle_squad = fixed_operator_roster.duplicate()
	squad = fixed_operator_roster.duplicate()
	return true


func _uses_fixed_operator_roster() -> bool:
	return not fixed_operator_roster.is_empty()


func _is_ticketed() -> bool:
	return not _ticket.is_empty()


func step(n: int = 1) -> void:
	for _i: int in n:
		_step_one()


## Preserves authored same-tick order; rows stay [tick, verb, args...] (P14).
func run_timeline(actions: Array, until_tick: int) -> void:
	var sorted: Array = []
	for i: int in actions.size():
		sorted.append([int((actions[i] as Array)[0]), i, actions[i]])
	var by_tick_then_index := func(a: Array, b: Array) -> bool:
		return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1])
	sorted.sort_custom(by_tick_then_index)
	var idx := 0
	while tick < until_tick and result == Result.RUNNING:
		while idx < sorted.size() and int(sorted[idx][0]) == tick:
			var entry: Array = sorted[idx][2]
			apply_action(entry.slice(1))
			idx += 1
		step()


func run_to_terminal(max_ticks: int) -> void:
	while result == Result.RUNNING and tick < max_ticks:
		step()


## Verb dispatcher (architecture rule 3). Every rejection path returns false
## before any mutation; any verb after a terminal state or with the wrong
## arity rejects.
func apply_action(action: Array) -> bool:
	if action.is_empty() or result != Result.RUNNING:
		return false
	if typeof(action[0]) != TYPE_STRING_NAME:
		return false
	var verb: StringName = action[0]
	var n := action.size()
	var ok := false
	match verb:
		&"deploy":
			ok = n == 4 and _apply_deploy(action[1], action[2], int(action[3]))
		&"retreat":
			ok = n == 2 and _apply_retreat(int(action[1]))
		&"trigger_skill":
			ok = n == 2 and _apply_trigger_skill(int(action[1]))
		&"mend":
			if (
				n == 3
				and HealingRulesScript.is_valid_id(action[1])
				and HealingRulesScript.is_valid_id(action[2])
			):
				ok = HealingRulesScript.apply(self, int(action[1]), int(action[2]))
		&"place_trap":
			ok = n == 3 and _apply_place_trap(action[1], action[2])
		&"resign":
			ok = n == 1 and _apply_resign()
		_:
			push_warning("apply_action: unknown verb '%s'" % [verb])
	return ok


## An operator can be deployed iff it is in the squad, has a def, is not
## already on the field, the battle is running, and DP covers its cost.
## The deploy bar's enabled state reads exactly this (single source of truth).
func is_deployable(op_id: StringName) -> bool:
	if result != Result.RUNNING:
		return false
	if _uses_fixed_operator_roster():
		if not fixed_operator_roster.has(op_id) or not _op_defs.has(op_id):
			return false
		if deployed_count() >= stage.squad_size:
			return false
		var fixed_definition: OperatorDef = _op_defs[op_id]
		return dp >= fixed_definition.dp_cost
	if is_redeploy_cooling_down(op_id):
		return false
	if _is_ticketed() and not _uses_fixed_operator_roster():
		return BattleTicketRuntimeScript.is_deployable(self, op_id)
	if not squad.has(op_id) or not _op_defs.has(op_id):
		return false
	for u: UnitState in units:
		if u.alive and u.op_id == op_id:
			return false
	var def: OperatorDef = _op_defs[op_id]
	return dp >= def.dp_cost


func redeploy_cooldown_ticks_remaining(deployment_id: StringName) -> int:
	return maxi(0, int(redeploy_ready_tick_by_id.get(deployment_id, tick)) - tick)


func redeploy_cooldown_seconds_remaining(deployment_id: StringName) -> int:
	if config == null or config.ticks_per_second <= 0:
		return 0
	var remaining := redeploy_cooldown_ticks_remaining(deployment_id)
	return ceili(float(remaining) / float(config.ticks_per_second))


func is_redeploy_cooling_down(deployment_id: StringName) -> bool:
	return redeploy_cooldown_ticks_remaining(deployment_id) > 0


func retreat_cooldown_ticks_for_class(op_class: OperatorDef.OpClass) -> int:
	if config == null:
		return 0
	var seconds := (
		VANGUARD_RETREAT_COOLDOWN_SECONDS
		if op_class == OperatorDef.OpClass.VANGUARD
		else STANDARD_RETREAT_COOLDOWN_SECONDS
	)
	return seconds * config.ticks_per_second


## Full deploy validation (the highlight query IS the verb's validation —
## never a copy). GROUND ops deploy on GROUND only, ELEVATED on ELEVATED;
## SPAWN/BASE/VOID/BLOCKED are never deployable; one alive unit per cell.
func can_deploy_at(op_id: StringName, cell: Vector2i) -> bool:
	if not is_deployable(op_id):
		return false
	if _uses_fixed_operator_roster():
		var fixed_definition: OperatorDef = _op_defs[op_id]
		return stage.operator_cell_in_domain(fixed_definition, cell) and alive_unit_at(cell) == null
	if _is_ticketed():
		return (
			BattleTicketRuntimeScript.cell_in_domain(_ticket_rows[op_id], stage, cell)
			and alive_unit_at(cell) == null
		)
	var def: OperatorDef = _op_defs[op_id]
	if not stage.operator_cell_in_domain(def, cell):
		return false
	return alive_unit_at(cell) == null


func unit_by_id(unit_id: int) -> UnitState:
	for u: UnitState in units:
		if u.id == unit_id:
			return u
	return null


func alive_unit_at(cell: Vector2i) -> UnitState:
	for u: UnitState in units:
		if u.alive and u.cell == cell:
			return u
	return null


func deployed_count() -> int:
	var n := 0
	for u: UnitState in units:
		if u.alive:
			n += 1
	return n


func _apply_deploy(op_id: StringName, cell: Vector2i, requested_facing: int) -> bool:
	# Retain the four-value action field so historical replays still decode,
	# but normalize every new unit to the canonical NW presentation state.
	if requested_facing < UnitState.Facing.RIGHT or requested_facing > UnitState.Facing.UP:
		return false
	if not can_deploy_at(op_id, cell):
		return false
	var u := UnitState.new()
	u.id = _next_unit_id
	_next_unit_id += 1
	u.cell = cell
	u.facing = UnitState.DEFAULT_FACING
	if _uses_fixed_operator_roster():
		var fixed_definition: OperatorDef = _op_defs[op_id]
		BattleTicketRuntimeScript.copy_legacy_unit(fixed_definition, u)
	elif _is_ticketed():
		BattleTicketRuntimeScript.copy_unit(_ticket_rows[op_id], u)
		var record := BattleTicketRuntimeScript.record_for(_battle_records, op_id)
		record["deployments"] += 1
	else:
		var def: OperatorDef = _op_defs[op_id]
		BattleTicketRuntimeScript.copy_legacy_unit(def, u)
	units.append(u)
	dp -= u.dp_cost
	dp_spent += u.dp_cost
	return true


## has a skill, and SP is exactly full; any rejection is zero state change.
## Instant effects (DP_BURST through the ledger, STUN_IN_RANGE on non-aerial
## enemies in the square around the unit) apply now; timed effects join
## active_effects until tick + duration_ticks.
func _apply_trigger_skill(unit_id: int) -> bool:
	var u := unit_by_id(unit_id)
	if u == null or not u.is_skill_ready() or u.skill_effect == SkillDef.Effect.HEAL_TARGET:
		return false
	u.sp = 0
	u.skill_triggered_tick = tick
	u.skill_target_unit_id = -1
	skills_fired += 1
	match u.skill_effect:
		SkillDef.Effect.DP_BURST:
			var amount := int(u.skill_params["amount"])
			dp_skill_granted += amount
			_grant_dp(amount)
		SkillDef.Effect.STUN_IN_RANGE:
			var cells := Targeting.splash_cells(u.cell, int(u.skill_params["dim"]))
			for e: EnemyState in enemies:
				if not e.alive or e.aerial:
					continue
				if cells.has(Pathing.cell_of(path_for(e.path_idx), e.progress_units)):
					e.stunned_until_tick = tick + int(u.skill_params["stun_ticks"])
		_:
			(
				u
				. active_effects
				. append(
					{
						"effect": u.skill_effect,
						"params": u.skill_params,
						"expires_tick": tick + u.skill_duration_ticks,
					}
				)
			)
	return true


func _apply_retreat(unit_id: int) -> bool:
	var u := unit_by_id(unit_id)
	if u == null or not u.alive:
		return false
	var deployment_id := u.battle_id if not u.battle_id.is_empty() else u.op_id
	u.alive = false
	_release_all_blocked(u)
	if _is_ticketed() and not _uses_fixed_operator_roster():
		var record := BattleTicketRuntimeScript.record_for(_battle_records, u.battle_id)
		record["retreats"] += 1
	retreated += 1
	if not _uses_fixed_operator_roster():
		redeploy_ready_tick_by_id[deployment_id] = tick + retreat_cooldown_ticks_for_class(u.op_class)
	var refund := floori(u.dp_cost * config.retreat_refund_percent / 100.0)
	dp_refunded += refund
	_grant_dp(refund)
	return true


## A trap is placeable iff its def exists, the battle is running, and DP
## covers its cost. Trap slots in the deploy bar read exactly this.
func is_trap_placeable(trap_id: StringName) -> bool:
	if result != Result.RUNNING or not _trap_defs.has(trap_id):
		return false
	var def: TrapDef = _trap_defs[trap_id]
	return dp >= def.dp_cost


## Full placement validation (the highlight query IS the verb's validation):
## GROUND tile, member of >= 1 stage path, no living trap on the cell.
## Trap/unit occupancy is independent — the two classes never contend.
func can_place_trap_at(trap_id: StringName, cell: Vector2i) -> bool:
	if not is_trap_placeable(trap_id):
		return false
	if not stage.trap_cell_in_domain(cell):
		return false
	return alive_trap_at(cell) == null


func alive_trap_at(cell: Vector2i) -> TrapState:
	for t: TrapState in traps:
		if t.cell == cell:
			return t
	return null


func _apply_place_trap(trap_id: StringName, cell: Vector2i) -> bool:
	if not can_place_trap_at(trap_id, cell):
		return false
	var def: TrapDef = _trap_defs[trap_id]
	var t := TrapState.new()
	t.id = _next_trap_id
	_next_trap_id += 1
	t.def_id = def.id
	t.cell = cell
	t.charges_left = def.charges
	t.trigger = def.trigger
	t.effect = def.effect
	t.damage = def.damage
	t.damage_kind = def.damage_kind
	t.slow_permille = def.slow_permille
	t.dp_cost = def.dp_cost
	traps.append(t)
	dp -= def.dp_cost
	dp_spent += def.dp_cost
	return true

## One authoritative EnemyState damage seam. Positive damage stamps the
## presentation event and extends an integer-tick movement stagger before the
## existing death path resolves. Attack cadence is unchanged.
func _damage_enemy(e: EnemyState, raw_damage: int, damage_kind: int) -> void:
	var damage := DamageRulesScript.resolve(
		raw_damage, damage_kind, e.defense, e.resistance_permille,
	)
	if EnemyDamageScript.apply(e, damage, tick, config.damage_stagger_ticks):
		_kill_enemy(e)


func _damage_unit(u: UnitState, raw_damage: int, damage_kind: int) -> void:
	var damage := DamageRulesScript.resolve(
		raw_damage, damage_kind, u.defense, u.resistance_permille,
	)
	if not u.alive or damage <= 0:
		return
	u.hp -= damage
	if u.hp <= 0:
		_kill_unit(u)

## observable at the current tick and the next step() no-ops via the
## terminal early-return. Writes only already-hashed fields (result), so
## BattleHash needs no extension; stars stays 0 like any defeat.
func _apply_resign() -> bool:
	result = Result.DEFEAT
	if _is_ticketed():
		terminal_reason = &"resign"
		_outcome = BattleOutcomeBuilderScript.seal(self)
	return true


func alive_count() -> int:
	var n := 0
	for e: EnemyState in enemies:
		if e.alive:
			n += 1
	return n


func alive_enemy_count() -> int:
	var n := 0
	for e: EnemyState in enemies:
		if e.alive:
			n += 1
	return n


func path_for(path_idx: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = _paths[path_idx]
	return cells


## Full-state FNV-1a 64-bit digest; field enumeration lives in
## sim/battle_hash.gd (append-only order, every mutable field).
func state_hash() -> int:
	return BattleHash.of(self)


## field map lives in sim/battle_snapshot.gd (P14 file-size seam).
func snapshot() -> Dictionary:
	return BattleSnapshot.of(self)


## Return the immutable result document already sealed by the terminal tick.
## Campaign persistence must not build a full tactical snapshot merely to read
## this small strategic handoff.
func terminal_outcome() -> Dictionary:
	if result == Result.RUNNING or not _is_ticketed() or _outcome.is_empty():
		return {}
	return _outcome.duplicate(true)


## this sub-step), (2) advance unblocked enemies + block assignment + leaks,
## (3) authored restoration lattices repair eligible hostile ground enemies,
## (4) combat — units strike first, then enemies;
## deaths resolve immediately,
## (5) spawn, (6) terminal check. Later phases append sub-steps, never reorder.
## Expiry runs before combat so a timed effect is active for exactly
## duration_ticks ticks (exclusive end at expires_tick); enemies a lapsed
## BLOCK_PLUS can no longer hold resume walking in this same tick's sub-step 2.
func _step_one() -> void:
	if result != Result.RUNNING:
		return
	_expire_effects()
	_tick_dp()
	var entrants := _advance_enemies()
	_resolve_trap_triggers(entrants)
	_apply_restoration_lattices()
	_tick_combat()
	for entry: Dictionary in timeline.due(tick):
		_spawn(entry)
	_check_terminal()
	tick += 1
	if _is_ticketed() and result != Result.RUNNING:
		_outcome = BattleOutcomeBuilderScript.seal(self)


## D12: blocked enemies skip; the block check runs after the advance, in spawn
## order. An enemy that finds no spare capacity keeps walking (overflow rule);
## a blocked enemy can never leak. Aerial enemies bypass block assignment
## never occupy capacity, and only leak or die to ranged damage — and they
## ignore traps (no ON_ENTER, no aura slow). For ground enemies the
## start-of-tick cell is sampled once, before advancing: it decides this
## tick's aura slow AND anchors the entry transition for ON_ENTER recording.
## Returns the entrant list ({trap, enemy}) for _resolve_trap_triggers.
func _advance_enemies() -> Array[Dictionary]:
	var entrants: Array[Dictionary] = []
	for e: EnemyState in enemies:
		if not e.alive:
			continue
		if tick < e.damage_stagger_until_tick:
			continue
		if e.blocked_by >= 0 or tick < e.stunned_until_tick:
			continue
		if e.aerial:
			e.progress_units += e.step_units
		else:
			var path := path_for(e.path_idx)
			var start_cell := Pathing.cell_of(path, e.progress_units)
			e.progress_units += _effective_step(e, start_cell)
			var cell := Pathing.cell_of(path, e.progress_units)
			if cell != start_cell:
				var trap := alive_trap_at(cell)
				if trap != null and trap.trigger == TrapDef.Trigger.ON_ENTER:
					entrants.append({"trap": trap, "enemy": e})
			var unit := alive_unit_at(cell)
			if unit != null and _block_capacity_left(unit) >= e.block_weight:
				e.blocked_by = unit.id
				unit.blocked_ids.append(e.id)
				continue
		if e.progress_units >= _path_lengths[e.path_idx]:
			e.alive = false
			leaked += 1
			base_hp -= e.leak_damage
	return entrants


## effective step = step_units * (1000 - slow) / 1000, floored once per tick.
func _effective_step(e: EnemyState, start_cell: Vector2i) -> int:
	var slow := _slow_permille_at(start_cell)
	if slow <= 0:
		return e.step_units
	@warning_ignore("integer_division")
	var stepped := e.step_units * (1000 - slow) / 1000
	return stepped


func _slow_permille_at(cell: Vector2i) -> int:
	var strongest := 0
	for t: TrapState in traps:
		if t.cell == cell and t.trigger == TrapDef.Trigger.CELL_AURA:
			strongest = maxi(strongest, t.slow_permille)
	return strongest


func _apply_restoration_lattices() -> void:
	if (
		stage.restoration_cells.is_empty()
		or stage.restoration_heal_amount <= 0
		or stage.restoration_interval_ticks <= 0
		or tick <= 0
		or tick % stage.restoration_interval_ticks != 0
	):
		return
	var lattice_cells := {}
	for point: Vector2 in stage.restoration_cells:
		lattice_cells[Vector2i(point)] = true
	if lattice_cells.is_empty():
		return
	for enemy: EnemyState in enemies:
		if (
			not enemy.alive
			or enemy.aerial
			or enemy.hp >= enemy.hp_max
		):
			continue
		var cell := Pathing.cell_of(path_for(enemy.path_idx), enemy.progress_units)
		if lattice_cells.has(cell):
			enemy.hp = mini(enemy.hp_max, enemy.hp + stage.restoration_heal_amount)

## ON_ENTER resolution (M2): after the advance pass, before combat — a
## trap-killed enemy never attacks its entry tick. Entrants resolve in
## path-progress-descending order (tie: lower id); each trigger costs one
## charge; an exhausted trap is removed, so a same-tick second entrant
## crosses unharmed and the cell is placeable again.
func _resolve_trap_triggers(entrants: Array[Dictionary]) -> void:
	if entrants.is_empty():
		return
	entrants.sort_custom(_entrant_order)
	for entry: Dictionary in entrants:
		var trap: TrapState = entry["trap"]
		var e: EnemyState = entry["enemy"]
		if not e.alive or trap.charges_left == 0:
			continue
		traps_triggered += 1
		trap.last_trigger_tick = tick
		if trap.effect == TrapDef.Effect.DAMAGE:
			_damage_enemy(e, trap.damage, trap.damage_kind)
		if trap.charges_left > 0:
			trap.charges_left -= 1
			if trap.charges_left == 0:
				traps.erase(trap)


static func _entrant_order(a: Dictionary, b: Dictionary) -> bool:
	var ea: EnemyState = a["enemy"]
	var eb: EnemyState = b["enemy"]
	if ea.progress_units != eb.progress_units:
		return ea.progress_units > eb.progress_units
	return ea.id < eb.id

## counter is 0 and a target exists (counter then resets to interval - 1 so
## shots land exactly atk_interval_ticks apart); otherwise the counter ticks
## down and holds at 0. Units strike before enemies, so an enemy killed on its
## ready-tick never lands that hit. Every automatic selection consumes the
## actor's explicit compiled TargetPolicyDef; Caster splash remains data-owned
## by splash_dim.
func _tick_combat() -> void:
	for u: UnitState in units:
		if not u.alive:
			continue
		var decision := TargetDecisionProjectionScript.unit_target_decision(self, u.id)
		var target_id := int(decision["selected_id"])
		if target_id >= 0:
			_face_unit_toward_enemy(u, enemies[target_id])
		if u.atk_counter > 0:
			u.atk_counter -= 1
			continue
		if u.atk <= 0:
			continue
		if target_id >= 0:
			_fire_unit(u, enemies[target_id])
	for e: EnemyState in enemies:
		if not e.alive:
			continue
		if tick < e.stunned_until_tick:
			continue
		if e.atk_counter > 0:
			e.atk_counter -= 1
			continue
		var decision := TargetDecisionProjectionScript.enemy_target_decision(self, e.id)
		var victim := unit_by_id(int(decision["selected_id"]))
		if e.atk > 0 and victim != null and victim.alive:
			_damage_unit(victim, e.atk, e.attack_damage_kind)
			e.atk_counter = e.atk_interval_ticks - 1


func _face_unit_toward_enemy(u: UnitState, enemy: EnemyState) -> void:
	var path := path_for(enemy.path_idx)
	var target_cell := Pathing.cell_of(path, enemy.progress_units)
	# A blocked enemy shares the operator's cell. Use the preceding path cell
	# so the operator continues to face the side the enemy approached from.
	if target_cell == u.cell and not path.is_empty():
		@warning_ignore("integer_division")
		var segment := clampi(
			enemy.progress_units, 0, Pathing.length_units(path) - 1,
		) / Pathing.PROGRESS_SCALE
		if segment > 0:
			target_cell = path[segment - 1]
	u.facing = Targeting.north_facing_toward(u.cell, target_cell, int(u.facing)) as UnitState.Facing


## Automatic unit attacks consume the public decision query. Caster splash is
## selected by data (splash_dim > 0), not by an operator-class branch.
func _fire_unit(u: UnitState, primary: EnemyState) -> void:
	var primary_cell := Pathing.cell_of(path_for(primary.path_idx), primary.progress_units)
	if u.splash_dim() > 0:
		u.atk_counter = u.effective_interval() - 1
		u.last_attack_tick = tick
		u.last_attack_cell = primary_cell
		var cells := Targeting.splash_cells(primary_cell, u.splash_dim())
		var damage := u.effective_atk()
		for e: EnemyState in enemies:
			if not e.alive or e.aerial:
				continue
			if cells.has(Pathing.cell_of(path_for(e.path_idx), e.progress_units)):
				_damage_enemy(e, damage, u.attack_damage_kind)
	else:
		_strike_enemy(u, primary)


func _strike_enemy(u: UnitState, target: EnemyState) -> void:
	_damage_enemy(target, u.effective_atk(), u.attack_damage_kind)
	u.atk_counter = u.effective_interval() - 1
	u.last_attack_tick = tick
	u.last_attack_cell = Pathing.cell_of(path_for(target.path_idx), target.progress_units)


func _block_capacity_left(u: UnitState) -> int:
	var held := 0
	for enemy_id: int in u.blocked_ids:
		held += enemies[enemy_id].block_weight
	return u.effective_block() - held


func _kill_enemy(e: EnemyState) -> void:
	e.alive = false
	e.died_at_tick = tick
	killed += 1
	if e.blocked_by >= 0:
		var blocker := unit_by_id(e.blocked_by)
		if blocker != null:
			blocker.blocked_ids.erase(e.id)
		e.blocked_by = -1


## D13/D16: death releases every held enemy (each resumes from its frozen
## progress on the next tick's advance); no DP refund on death.
func _kill_unit(u: UnitState) -> void:
	u.alive = false
	if _is_ticketed() and not _uses_fixed_operator_roster():
		var record := BattleTicketRuntimeScript.record_for(_battle_records, u.battle_id)
		if not bool(record["fell"]):
			record["fell"] = true
			record["first_fall_tick"] = tick
	_release_all_blocked(u)


func _release_all_blocked(u: UnitState) -> void:
	for enemy_id: int in u.blocked_ids:
		enemies[enemy_id].blocked_by = -1
	u.blocked_ids.clear()


func _tick_dp() -> void:
	dp_regen_counter += 1
	if dp_regen_counter >= config.dp_regen_interval_ticks:
		dp_regen_counter = 0
		dp_regen_accrued += 1
		_grant_dp(1)
	for u: UnitState in units:
		if not u.alive:
			continue
		if u.dp_generation_interval_ticks > 0:
			u.dp_generation_counter += 1
			if u.dp_generation_counter >= u.dp_generation_interval_ticks:
				u.dp_generation_counter = 0
				dp_vanguard_generated += 1
				_grant_dp(1)
		if u.sp_cost > 0 and u.sp < u.sp_cost:
			u.sp_progress += 1
			if u.sp_progress >= config.sp_progress_interval_ticks:
				u.sp_progress = 0
				u.sp += 1


## Timed effects lapse when tick reaches their expires_tick — derived stats
## fall back to base by construction. A lapsed BLOCK_PLUS may leave a unit
## over capacity: release most-recently-blocked first until the held weight
func _expire_effects() -> void:
	for u: UnitState in units:
		if not u.alive or u.active_effects.is_empty():
			continue
		var had_block_plus := false
		var kept: Array[Dictionary] = []
		for fx: Dictionary in u.active_effects:
			if int(fx["expires_tick"]) <= tick:
				if int(fx["effect"]) == SkillDef.Effect.BLOCK_PLUS:
					had_block_plus = true
			else:
				kept.append(fx)
		u.active_effects = kept
		if had_block_plus:
			_release_block_overflow(u)


func _release_block_overflow(u: UnitState) -> void:
	while not u.blocked_ids.is_empty() and _block_capacity_left(u) < 0:
		var last_idx := u.blocked_ids.size() - 1
		enemies[u.blocked_ids[last_idx]].blocked_by = -1
		u.blocked_ids.remove_at(last_idx)


## Single cap-clamp point (D4): callers bump their gross ledger bucket, then
## grant through here; the overage lands in dp_lost_to_cap.
func _grant_dp(amount: int) -> void:
	var granted := mini(amount, config.dp_cap - dp)
	dp += granted
	dp_lost_to_cap += amount - granted


func _spawn(entry: Dictionary) -> void:
	var def: EnemyDef = _defs[entry["enemy_id"]]
	var e := EnemyState.new()
	e.id = _next_enemy_id
	_next_enemy_id += 1
	e.def_id = def.id
	e.hp = def.hp
	e.hp_max = def.hp
	e.path_idx = int(entry["path_idx"])
	e.progress_units = 0
	e.step_units = Pathing.step_units_for(def.speed_tiles_per_s, config.ticks_per_second)
	e.leak_damage = def.leak_damage
	e.block_weight = def.block_weight
	e.atk = def.atk
	e.defense = def.defense
	e.resistance_permille = def.resistance_permille
	e.attack_damage_kind = def.attack_damage_kind
	e.atk_interval_ticks = def.atk_interval_ticks
	e.aerial = def.aerial
	e.atk_range_cells = def.atk_range_cells
	e.target_policy = Targeting.compile(def.target_policy, TargetPolicyDefScript.OwnerKind.ENEMY)
	enemies.append(e)
	spawned += 1


func _check_terminal() -> void:
	if leaked > stage.leak_limit or base_hp <= 0:
		result = Result.DEFEAT
		stars = 0
		if _is_ticketed():
			terminal_reason = &"base_defeat" if base_hp <= 0 else &"leak_defeat"
		return
	if timeline.exhausted() and alive_enemy_count() == 0:
		result = Result.CLEAR
		stars = StarCalc.star_for(leaked, stage.leak_limit)
		if _is_ticketed():
			terminal_reason = &"clear"
