class_name BattleSnapshot
extends RefCounted

## hash does not). Extracted from battle_model.gd at the P14 file-size

const DamageRulesScript := preload("res://sim/damage_rules.gd")


static func of(m: BattleModel) -> Dictionary:
	var snapshot := {
		"tick": m.tick,
		"base_hp": m.base_hp,
		"result": m.result,
		"stars": m.stars,
		"spawned": m.spawned,
		"leaked": m.leaked,
		"leak_limit": m.stage.leak_limit,
		"killed": m.killed,
		"alive": m.alive_enemy_count(),
		"dp": m.dp,
		"deployed": m.deployed_count(),
		"deploys": m.units.size(),
		"retreated": m.retreated,
		"redeploy_cooldowns": _redeploy_cooldowns(m),
		"dp_spent": m.dp_spent,
		"skills_fired": m.skills_fired,
		"traps_placed": m._next_trap_id,
		"trap_triggers": m.traps_triggered,
		"damage_rules_version": DamageRulesScript.VERSION,
		"mitigation": _mitigation(m),
	}
	if m._is_ticketed():
		snapshot["ticket_hash"] = String(m._ticket["ticket_hash"])
		snapshot["ticket"] = m._ticket.duplicate(true)
		snapshot["battle_rows"] = m._battle_records.duplicate(true)
		snapshot["outcome"] = m._outcome.duplicate(true)
	return snapshot


static func _redeploy_cooldowns(m: BattleModel) -> Dictionary:
	var result: Dictionary = {}
	var ids: Array[String] = []
	for raw_id: Variant in m.redeploy_ready_tick_by_id:
		ids.append(String(raw_id))
	ids.sort()
	for deployment_id: String in ids:
		var id := StringName(deployment_id)
		result[deployment_id] = {
			"ready_tick": int(m.redeploy_ready_tick_by_id[id]),
			"ticks_remaining": m.redeploy_cooldown_ticks_remaining(id),
			"seconds_remaining": m.redeploy_cooldown_seconds_remaining(id),
		}
	return result


static func _mitigation(m: BattleModel) -> Dictionary:
	var units: Array[Dictionary] = []
	for u: UnitState in m.units:
		var row := {
			"id": u.id,
			"defense": u.defense,
			"resistance_permille": u.resistance_permille,
			"attack_damage_kind": u.attack_damage_kind,
		}
		if not u.battle_id.is_empty():
			row["battle_id"] = String(u.battle_id)
			row["hero_id"] = String(u.hero_id)
		units.append(row)
	var enemies: Array[Dictionary] = []
	for e: EnemyState in m.enemies:
		enemies.append({
			"id": e.id,
			"defense": e.defense,
			"resistance_permille": e.resistance_permille,
			"attack_damage_kind": e.attack_damage_kind,
		})
	var traps: Array[Dictionary] = []
	for t: TrapState in m.traps:
		traps.append({"id": t.id, "damage_kind": t.damage_kind})
	return {
		"units": units,
		"enemies": enemies,
		"traps": traps,
	}
