extends SceneTree

const RuntimeContext := preload("res://sim/campaign_runtime_context.gd")
const CampaignStateV3 := preload("res://sim/campaign_state_v3.gd")
const BattleOutcomeV3 := preload("res://sim/battle_outcome_v3.gd")

var _failures: Array[String] = []


func _init() -> void:
	var context := RuntimeContext.build()
	var created: Dictionary = CampaignStateV3.create(9127, 1, context)
	_check(
		bool(created.get("accepted", false)),
		"campaign fixture creation failed: %s" % created.get("error_code", &"unknown"),
	)
	if not bool(created.get("accepted", false)):
		_finish()
		return
	var state: Variant = created["value"]
	var projection: Dictionary = state.runtime_projection()
	var hero_id := String(projection.get("ready_heroes", [])[0].get("hero_id", ""))
	var begin: Dictionary = state.begin_attempt(
		"test:no-permadeath:begin", "s1", [hero_id], 551, state.save_revision(),
	)
	_check(bool(begin.get("accepted", false)), "initial attempt was rejected")
	state = _restore_mutation(begin, context)
	if state == null:
		_finish()
		return
	var ticket: Dictionary = state.data_copy()["tickets"][-1]
	var frozen: Dictionary = ticket["squad"][0]
	var sealed: Dictionary = BattleOutcomeV3.seal({
		"schema_version": BattleOutcomeV3.SCHEMA_VERSION,
		"attempt_id": ticket["attempt_id"],
		"ticket_hash": ticket["ticket_hash"],
		"result": "defeat",
		"terminal_reason": "resign",
		"terminal_tick": 20,
		"stars": 0,
		"leaks": 0,
		"kills": 0,
		"rows": [{
			"slot_index": frozen["slot_index"],
			"battle_id": frozen["battle_id"],
			"hero_id": frozen["hero_id"],
			"class_id": frozen["class_id"],
			"operator_def_id": frozen["operator_def_id"],
			"deployments": 1,
			"retreats": 0,
			"fell": true,
			"first_fall_tick": 10,
		}],
	}, ticket)
	_check(bool(sealed.get("accepted", false)), "fallen outcome was rejected")
	if not bool(sealed.get("accepted", false)):
		_finish()
		return
	var resolved: Dictionary = state.resolve_attempt(
		"test:no-permadeath:resolve",
		ticket["attempt_id"],
		sealed["value"],
		state.save_revision(),
	)
	_check(bool(resolved.get("accepted", false)), "attempt resolution was rejected")
	state = _restore_mutation(resolved, context)
	if state == null:
		_finish()
		return
	var data: Dictionary = state.data_copy()
	var hero := _hero(data["heroes"], hero_id)
	_check(String(hero.get("life_status", "")) == "ready", "battle fall changed persistent life status")
	_check(hero.get("death") == null, "battle fall created a persistent death record")
	_check((data.get("memorial", []) as Array).is_empty(), "battle fall created a memorial record")
	_check((data["last_resolution"].get("dead_hero_ids", []) as Array).is_empty(), "resolution recorded a dead operator")
	projection = state.runtime_projection()
	_check((projection.get("fallen_heroes", []) as Array).is_empty(), "runtime projection exposed a fallen roster")
	_check(not _hero(projection.get("ready_heroes", []), hero_id).is_empty(), "operator was unavailable after falling")
	var replay: Dictionary = state.begin_attempt(
		"test:no-permadeath:replay", "s1", [hero_id], 552, state.save_revision(),
	)
	_check(bool(replay.get("accepted", false)), "operator could not deploy in the next mission")
	_finish()


func _restore_mutation(command: Dictionary, context: Dictionary) -> Variant:
	var mutation: Variant = command.get("payload", {}).get("mutation")
	if mutation == null:
		_check(false, "accepted command did not contain a mutation")
		return null
	var restored: Dictionary = CampaignStateV3.restore_source(
		mutation.prospective_save_text(), context,
	)
	_check(bool(restored.get("accepted", false)), "prospective save did not restore")
	return restored.get("value") if bool(restored.get("accepted", false)) else null


func _hero(rows: Array, hero_id: String) -> Dictionary:
	for row: Dictionary in rows:
		if String(row.get("hero_id", "")) == hero_id:
			return row
	return {}


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("NO_PERMADEATH_TEST_OK")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)
