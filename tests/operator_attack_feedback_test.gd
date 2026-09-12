extends SceneTree
const Feedback := preload("res://scripts/view/operator_attack_feedback.gd")
const Unit := preload("res://sim/unit_state.gd")

class FixtureView extends Node2D:
	var model: BattleModel
	var ticks_per_frame_scale := 1.0
	var _unit_nodes: Dictionary = {}
	var _enemy_rects: Dictionary = {}
	var _stage := StageDef.new()
	func battle_confirmation_active() -> bool:
		return false
	func _tutorial_holding_battle() -> bool:
		return false

var failures: Array[String] = []
func _init() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1280, 720)
	var sfx := root.get_node("Sfx")
	var view := FixtureView.new()
	view.model = BattleModel.new()
	view.model.config = GameConfig.new()
	view.model.tick = 20
	root.add_child(view)
	var fx := Feedback.new()
	view.add_child(fx)
	fx.configure(view)
	fx.set_process(false)
	var cues: Dictionary = {}
	var id := 0
	for identity: StringName in Feedback.PROFILES:
		var unit := Unit.new()
		unit.id = id
		unit.op_id = &"recruit"
		unit.class_id = StringName(String(identity).trim_suffix("_female").trim_suffix("_male"))
		# Explicit portrait variants share the same catalog resolver as the art.
		unit.portrait_asset_id = identity
		unit.hero_id = &"female" if String(identity).ends_with("_female") else &"male"
		for attempt: int in 2:
			if Feedback.profile_for_unit(unit) == identity:
				break
			unit.hero_id = StringName(String(unit.hero_id) + "a")
		unit.cell = Vector2i(2, 2)
		unit.last_attack_cell = Vector2i(3, 2)
		unit.last_attack_tick = 20
		view.model.units.append(unit)
		var anchor := Node2D.new()
		anchor.position = Vector2(320 + id * 40, 300)
		view.add_child(anchor)
		view._unit_nodes[id] = anchor
		check(Feedback.profile_for_unit(unit) == identity, "resolved identity " + String(identity))
		var cue: StringName = Feedback.PROFILES[identity]["cue"]
		check(not cues.has(cue), "unique cue " + String(cue))
		cues[cue] = true
		check(sfx.resolved_id_for(cue) == cue, "registered cue " + String(cue))
		id += 1
	var recruit := Unit.new()
	recruit.op_id = &"recruit"
	check(Feedback.profile_for_unit(recruit).is_empty(), "recruits have no new attack profile")
	var before := int(sfx.audible_start_count())
	var state := [view.model.tick, view.model.units[0].hp, view.model.units[0].facing]
	fx.sync_attacks(view.model)
	check(fx.trigger_count() == 6 and fx.active_burst_count() == 6, "six distinct attacks emit")
	check(sfx.audible_start_count() == before + 6, "six cues routed once")
	fx.sync_attacks(view.model)
	check(fx.trigger_count() == 6 and sfx.audible_start_count() == before + 6, "same tick deduped")
	check(state == [view.model.tick, view.model.units[0].hp, view.model.units[0].facing], "no simulation mutation")
	check(not sfx.play_world("attack_gunner_female", null, Vector2.ZERO), "missing world owner fails closed")
	fx._process(1.0)
	check(fx.active_burst_count() == 0, "expired particles cleaned")
	view.position = Vector2(-10000, -10000)
	view.model.tick += 1
	for unit: UnitState in view.model.units:
		unit.last_attack_tick = view.model.tick
	fx.sync_attacks(view.model)
	check(fx.culled_count() == 6 and fx.active_burst_count() == 0, "offscreen attacks culled")
	view.position = Vector2.ZERO
	fx.sync_attacks(view.model)
	check(fx.active_burst_count() == 0, "no replay on camera reentry")
	for wave: int in 10:
		view.model.tick += 1
		for unit: UnitState in view.model.units:
			unit.last_attack_tick = view.model.tick
		fx.sync_attacks(view.model)
	check(fx.active_burst_count() == Feedback.MAX_BURSTS, "bounded burst budget")
	view.ticks_per_frame_scale = 0.0
	fx._process(0.01)
	check(fx.active_burst_count() == 0, "pause clears particles")
	check(sfx.player_count() == 8, "original voice budget retained")
	root.remove_child(view)
	view.free()
	sfx.stop_all()
	if failures.is_empty():
		print("OPERATOR_ATTACK_FEEDBACK_TEST_OK")
		quit(0)
	else:
		for failure: String in failures:
			push_error(failure)
		quit(1)

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
