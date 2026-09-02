class_name UnitState
extends RefCounted

## Per-deployed-unit authoritative state (architecture rule 1: plain data, no
## Node). Stats are copied from OperatorDef at deploy so the model never
## re-reads Resources mid-battle. The units array in BattleModel is
## append-only: retreated and dead units stay in it (alive = false) for hash
## stability and history; redeploying creates a fresh UnitState.
##
## expires_tick}); combat reads the effective_* getters, which fold active
## effects over base stats — base stats are NEVER mutated in place, so
## "expiry restores base exactly" holds by construction.

enum Facing { RIGHT, DOWN, LEFT, UP }
const DEFAULT_FACING := Facing.LEFT

var id: int = 0
var battle_id: StringName = &""
var hero_id: StringName = &""
var class_id: StringName = &""
var op_id: StringName = &""
var sprite_id: StringName = &""
var portrait_asset_id: StringName = &""
var cell: Vector2i = Vector2i.ZERO
var facing: Facing = DEFAULT_FACING
var hp: int = 1
var hp_max: int = 1
var alive: bool = true
var block: int = 0
var dp_cost: int = 0
var atk: int = 0
var defense: int = 0
var resistance_permille: int = 0
var attack_damage_kind: int = 0
var atk_interval_ticks: int = 30
var atk_counter: int = 0
var dp_generation_interval_ticks: int = 0
var dp_generation_counter: int = 0
var blocked_ids: Array[int] = []
var op_class: OperatorDef.OpClass = OperatorDef.OpClass.GUARD
var splash_dim_base: int = 0
var range_offsets: Array[Vector2i] = []
var target_policy: Dictionary = {}
var last_attack_tick: int = -1
var last_attack_cell: Vector2i = Vector2i(-1, -1)
var sp: int = 0
var sp_progress: int = 0
var active_effects: Array[Dictionary] = []
var skill_id: StringName = &""
var sp_cost: int = 0
var skill_effect: int = 0
var skill_params: Dictionary = {}
var skill_duration_ticks: int = 0
var skill_triggered_tick: int = -1
var skill_target_unit_id: int = -1


func effective_atk() -> int:
	var mult := 1.0
	for fx: Dictionary in active_effects:
		if int(fx["effect"]) == SkillDef.Effect.ATK_MULT:
			mult *= float(fx["params"]["mult"])
	return floori(atk * mult)


func effective_interval() -> int:
	var mult := 1.0
	for fx: Dictionary in active_effects:
		if int(fx["effect"]) == SkillDef.Effect.ATK_INTERVAL_MULT:
			mult *= float(fx["params"]["mult"])
	return maxi(1, floori(atk_interval_ticks * mult))


func effective_block() -> int:
	var bonus := 0
	for fx: Dictionary in active_effects:
		if int(fx["effect"]) == SkillDef.Effect.BLOCK_PLUS:
			bonus += int(fx["params"]["amount"])
	return block + bonus


## trigger_skill readiness — the verb's own guard AND the UI's query (rule
## 7, P14): adapters and the SP-flash read this, never a copy.
func is_skill_ready() -> bool:
	return alive and sp_cost > 0 and sp == sp_cost


func splash_dim() -> int:
	# base comes from data (OperatorDef.splash_dim, P14 — rule 4); effects
	# may only enlarge it
	var dim := splash_dim_base
	for fx: Dictionary in active_effects:
		if int(fx["effect"]) == SkillDef.Effect.SPLASH_RADIUS_PLUS:
			dim = maxi(dim, int(fx["params"]["dim"]))
	return dim
