class_name TargetDecisionProjection
extends RefCounted

## Read-only candidate projection for Targeting. BattleModel owns the database;
## this class emits primitive dictionaries and retains no model objects.

const TargetPolicyDefScript := preload("res://data/target_policy_def.gd")


static func unit_target_decision(model: BattleModel, unit_id: int) -> Dictionary:
	var unit := model.unit_by_id(unit_id)
	if unit == null:
		return Targeting.decide(
			Targeting.compile(null, TargetPolicyDefScript.OwnerKind.OPERATOR),
			"operator",
			unit_id,
			[],
		)
	return Targeting.decide(
		unit.target_policy,
		"operator",
		unit.id,
		_unit_candidates(model, unit),
	)


static func enemy_target_decision(model: BattleModel, enemy_id: int) -> Dictionary:
	var enemy := _enemy_by_id(model, enemy_id)
	if enemy == null:
		return Targeting.decide(
			Targeting.compile(null, TargetPolicyDefScript.OwnerKind.ENEMY),
			"enemy",
			enemy_id,
			[],
		)
	return Targeting.decide(
		enemy.target_policy,
		"enemy",
		enemy.id,
		_enemy_candidates(model, enemy),
	)


static func _unit_candidates(model: BattleModel, unit: UnitState) -> Array:
	var candidates: Array = []
	var domain := int(unit.target_policy.get("candidate_domain", -1))
	var covered_cells: Dictionary = {}
	if domain == TargetPolicyDefScript.CandidateDomain.ENEMY_IN_OPERATOR_RANGE:
		covered_cells = Targeting.omni_range_cells(unit.cell, unit.range_offsets)
	for enemy: EnemyState in model.enemies:
		var cell := Pathing.cell_of(model.path_for(enemy.path_idx), enemy.progress_units)
		candidates.append({
			"id": enemy.id,
			"alive": enemy.alive,
			"faction": Targeting.FACTION_ENEMY,
			"relation": (
				Targeting.RELATION_BLOCKED
				if unit.blocked_ids.has(enemy.id)
				else Targeting.RELATION_NONE
			),
			"in_range": covered_cells.has(cell),
			"aerial": enemy.aerial,
			"progress_units": enemy.progress_units,
			"distance": -1,
			"engagement_order": unit.blocked_ids.find(enemy.id),
		})
	return candidates


static func _enemy_candidates(model: BattleModel, enemy: EnemyState) -> Array:
	var candidates: Array = []
	var enemy_cell := Pathing.cell_of(model.path_for(enemy.path_idx), enemy.progress_units)
	for unit: UnitState in model.units:
		var distance := maxi(
			absi(unit.cell.x - enemy_cell.x),
			absi(unit.cell.y - enemy_cell.y),
		)
		candidates.append({
			"id": unit.id,
			"alive": unit.alive,
			"faction": Targeting.FACTION_OPERATOR,
			"relation": (
				Targeting.RELATION_CURRENT_BLOCKER
				if enemy.blocked_by == unit.id
				else Targeting.RELATION_DEPLOYED_UNIT
			),
			"in_range": distance <= enemy.atk_range_cells,
			"aerial": false,
			"progress_units": 0,
			"distance": distance,
			"engagement_order": -1,
		})
	return candidates


static func _enemy_by_id(model: BattleModel, enemy_id: int) -> EnemyState:
	for enemy: EnemyState in model.enemies:
		if enemy.id == enemy_id:
			return enemy
	return null
