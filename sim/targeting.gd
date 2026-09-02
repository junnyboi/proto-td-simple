class_name Targeting
extends RefCounted

## Pure range math and closed target-policy evaluation. Candidate and decision
## payloads contain primitives only, are canonical by entity ID, and never
## mutate BattleModel. BattleModel is the sole owner of candidate construction.

const FACING_RIGHT := 0
const FACING_DOWN := 1
const FACING_LEFT := 2
const FACING_UP := 3
const FACING_NORTHWEST := FACING_LEFT
const FACING_NORTHEAST := FACING_UP

const NO_TARGET := -1
const RELATION_NONE := ""
const RELATION_BLOCKED := "blocked"
const RELATION_CURRENT_BLOCKER := "current_blocker"
const RELATION_DEPLOYED_UNIT := "deployed_unit"
const FACTION_ENEMY := "enemy"
const FACTION_OPERATOR := "operator"

const TargetPolicyDefScript := preload("res://data/target_policy_def.gd")

const _POLICY_SHAPES := {
	"no_automatic_target": [
		TargetPolicyDefScript.OwnerKind.OPERATOR,
		TargetPolicyDefScript.CandidateDomain.NONE,
		TargetPolicyDefScript.AerialRule.ANY,
		TargetPolicyDefScript.RankKey.ENTITY_ID_ASC,
	],
	"operator_blocked_assignment_order": [
		TargetPolicyDefScript.OwnerKind.OPERATOR,
		TargetPolicyDefScript.CandidateDomain.BLOCKED_ENEMY,
		TargetPolicyDefScript.AerialRule.ANY,
		TargetPolicyDefScript.RankKey.ENGAGEMENT_ORDER_ASC,
	],
	"operator_aerial_first_frontmost": [
		TargetPolicyDefScript.OwnerKind.OPERATOR,
		TargetPolicyDefScript.CandidateDomain.ENEMY_IN_OPERATOR_RANGE,
		TargetPolicyDefScript.AerialRule.PREFER,
		TargetPolicyDefScript.RankKey.PROGRESS_DESC,
	],
	"operator_ground_only_frontmost": [
		TargetPolicyDefScript.OwnerKind.OPERATOR,
		TargetPolicyDefScript.CandidateDomain.ENEMY_IN_OPERATOR_RANGE,
		TargetPolicyDefScript.AerialRule.EXCLUDE,
		TargetPolicyDefScript.RankKey.PROGRESS_DESC,
	],
	"enemy_blocker_only": [
		TargetPolicyDefScript.OwnerKind.ENEMY,
		TargetPolicyDefScript.CandidateDomain.CURRENT_BLOCKER,
		TargetPolicyDefScript.AerialRule.ANY,
		TargetPolicyDefScript.RankKey.ENTITY_ID_ASC,
	],
	"enemy_blocker_then_nearest": [
		TargetPolicyDefScript.OwnerKind.ENEMY,
		TargetPolicyDefScript.CandidateDomain.BLOCKER_THEN_DEPLOYED_UNIT,
		TargetPolicyDefScript.AerialRule.ANY,
		TargetPolicyDefScript.RankKey.DISTANCE_ASC,
	],
}


static func rotate_offset(offset: Vector2i, facing: int) -> Vector2i:
	match facing:
		FACING_DOWN:
			return Vector2i(-offset.y, offset.x)
		FACING_LEFT:
			return Vector2i(-offset.x, -offset.y)
		FACING_UP:
			return Vector2i(offset.y, -offset.x)
		_:
			return offset


## Absolute cells covered by a range pattern at origin with facing.
static func range_cells(origin: Vector2i, offsets: Array[Vector2i], facing: int) -> Dictionary:
	var cells: Dictionary = {}
	for offset: Vector2i in offsets:
		cells[origin + rotate_offset(offset, facing)] = true
	return cells


## Operators acquire targets across the union of every rotation of their
## authored range. The original offsets remain the single data-owned shape;
## facing is now a presentation response rather than an acquisition gate.
static func omni_range_cells(origin: Vector2i, offsets: Array[Vector2i]) -> Dictionary:
	var cells: Dictionary = {}
	for facing: int in range(4):
		for offset: Vector2i in offsets:
			cells[origin + rotate_offset(offset, facing)] = true
	return cells


## Only the two north-facing operator views are admitted. Projecting grid
## positions to isometric screen space reduces the choice to the enemy's
## horizontal side: right is NE, left is NW. Exact center ties keep the last
## north-facing direction to avoid visual jitter.
static func north_facing_toward(
	origin: Vector2i,
	target: Vector2i,
	fallback: int = FACING_NORTHWEST,
) -> int:
	var screen_x_delta := (target.x - origin.x) - (target.y - origin.y)
	if screen_x_delta > 0:
		return FACING_NORTHEAST
	if screen_x_delta < 0:
		return FACING_NORTHWEST
	return fallback if fallback in [FACING_NORTHWEST, FACING_NORTHEAST] else FACING_NORTHWEST


## Compile a Resource into a primitive-only immutable-by-convention snapshot.
## Null, unknown, contradictory, owner-incompatible, or unstable policies fail
## closed. The evaluator accepts the invalid snapshot and returns invalid_policy.
static func compile(policy: TargetPolicyDefScript, expected_owner_kind: int) -> Dictionary:
	var reason := validation_reason(policy, expected_owner_kind)
	if reason != "":
		return {
			"valid": false,
			"invalid_reason": reason,
			"policy_id": "" if policy == null else String(policy.id),
			"owner_kind": expected_owner_kind,
			"candidate_domain": -1,
			"aerial_rule": -1,
			"primary_rank": -1,
		}
	return {
		"valid": true,
		"invalid_reason": "",
		"policy_id": String(policy.id),
		"owner_kind": int(policy.owner_kind),
		"candidate_domain": int(policy.candidate_domain),
		"aerial_rule": int(policy.aerial_rule),
		"primary_rank": int(policy.primary_rank),
	}


static func validation_reason(policy: TargetPolicyDefScript, expected_owner_kind: int) -> String:
	if policy == null:
		return "null_policy"
	var policy_id := String(policy.id)
	if policy_id == "":
		return "missing_policy_id"
	if not _POLICY_SHAPES.has(policy_id):
		return "unknown_policy_id"
	if not _enum_in_range(int(policy.owner_kind), TargetPolicyDefScript.OwnerKind.size()):
		return "unknown_owner_kind"
	if not _enum_in_range(
		int(policy.candidate_domain), TargetPolicyDefScript.CandidateDomain.size()
	):
		return "unknown_candidate_domain"
	if not _enum_in_range(int(policy.aerial_rule), TargetPolicyDefScript.AerialRule.size()):
		return "unknown_aerial_rule"
	if not _enum_in_range(int(policy.primary_rank), TargetPolicyDefScript.RankKey.size()):
		return "unsupported_rank_key"
	if int(policy.owner_kind) != expected_owner_kind:
		return "owner_kind_mismatch"
	if not policy.stable_entity_id_tie_break:
		return "missing_stable_tie_break"
	var expected: Array = _POLICY_SHAPES[policy_id]
	var actual := [
		int(policy.owner_kind),
		int(policy.candidate_domain),
		int(policy.aerial_rule),
		int(policy.primary_rank),
	]
	if actual != expected:
		return "contradictory_policy_shape"
	return ""


## Returns a canonical primitive diagnostic. Input order cannot affect either
## the selected entity or the considered rows.
static func decide(
	policy: Dictionary,
	attacker_kind: String,
	attacker_id: int,
	candidates: Array,
) -> Dictionary:
	var rows := _canonical_rows(candidates)
	if not bool(policy.get("valid", false)):
		_reject_all(rows, "invalid_policy")
		return _decision(
			policy, attacker_kind, attacker_id, rows, NO_TARGET, "invalid_policy", ""
		)
	var domain := int(policy["candidate_domain"])
	if domain == TargetPolicyDefScript.CandidateDomain.NONE:
		_reject_all(rows, "automatic_target_disabled")
		return _decision(
			policy,
			attacker_kind,
			attacker_id,
			rows,
			NO_TARGET,
			"automatic_target_disabled",
			"",
		)
	var has_blocker := _has_current_blocker(rows)
	var eligible: Array[Dictionary] = []
	for row: Dictionary in rows:
		var reason := _eligibility_reason(policy, row, has_blocker)
		row["eligible"] = reason == ""
		row["rejection_reason"] = reason
		row["rank_key"] = _rank_key(policy, row, has_blocker)
		if reason == "":
			eligible.append(row)
	if eligible.is_empty():
		var reason := "no_candidates" if rows.is_empty() else "no_eligible_candidates"
		return _decision(policy, attacker_kind, attacker_id, rows, NO_TARGET, reason, "")
	eligible.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _rank_less(a["rank_key"], b["rank_key"]))
	var selected: Dictionary = eligible[0]
	selected["rejection_reason"] = "selected"
	var tie_reason := _tie_break_reason(policy, eligible)
	for row: Dictionary in eligible.slice(1):
		row["rejection_reason"] = _loser_reason(policy, selected, row)
	return _decision(
		policy,
		attacker_kind,
		attacker_id,
		rows,
		int(selected["id"]),
		"selected",
		tie_reason,
	)


## Cells of a dim x dim square centered on a cell (dim odd: 3 -> 3x3).
static func splash_cells(center: Vector2i, dim: int) -> Dictionary:
	var cells: Dictionary = {}
	@warning_ignore("integer_division")
	var radius := dim / 2
	for dy: int in range(-radius, radius + 1):
		for dx: int in range(-radius, radius + 1):
			cells[center + Vector2i(dx, dy)] = true
	return cells


static func _canonical_rows(candidates: Array) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for value: Variant in candidates:
		var candidate := value as Dictionary
		rows.append({
			"id": int(candidate.get("id", NO_TARGET)),
			"alive": bool(candidate.get("alive", false)),
			"faction": String(candidate.get("faction", "")),
			"relation": String(candidate.get("relation", RELATION_NONE)),
			"in_range": bool(candidate.get("in_range", false)),
			"aerial": bool(candidate.get("aerial", false)),
			"progress_units": int(candidate.get("progress_units", 0)),
			"distance": int(candidate.get("distance", -1)),
			"engagement_order": int(candidate.get("engagement_order", -1)),
			"eligible": false,
			"rejection_reason": "",
			"rank_key": [],
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["id"]) < int(b["id"]))
	return rows


static func _eligibility_reason(policy: Dictionary, row: Dictionary, has_blocker: bool) -> String:
	if int(row["id"]) < 0:
		return "invalid_candidate"
	if not bool(row["alive"]):
		return "not_alive"
	var domain := int(policy["candidate_domain"])
	match domain:
		TargetPolicyDefScript.CandidateDomain.BLOCKED_ENEMY:
			if row["faction"] != FACTION_ENEMY:
				return "wrong_faction"
			if row["relation"] != RELATION_BLOCKED:
				return "not_blocked"
		TargetPolicyDefScript.CandidateDomain.ENEMY_IN_OPERATOR_RANGE:
			if row["faction"] != FACTION_ENEMY:
				return "wrong_faction"
			if not bool(row["in_range"]):
				return "out_of_range"
			if (
				int(policy["aerial_rule"]) == TargetPolicyDefScript.AerialRule.EXCLUDE
				and bool(row["aerial"])
			):
				return "aerial_excluded"
		TargetPolicyDefScript.CandidateDomain.CURRENT_BLOCKER:
			if row["faction"] != FACTION_OPERATOR:
				return "wrong_faction"
			if row["relation"] != RELATION_CURRENT_BLOCKER:
				return "not_current_blocker"
		TargetPolicyDefScript.CandidateDomain.BLOCKER_THEN_DEPLOYED_UNIT:
			if row["faction"] != FACTION_OPERATOR:
				return "wrong_faction"
			if has_blocker and row["relation"] != RELATION_CURRENT_BLOCKER:
				return "blocker_preferred"
			if not has_blocker and row["relation"] != RELATION_DEPLOYED_UNIT:
				return "not_deployed_unit"
			if not has_blocker and not bool(row["in_range"]):
				return "out_of_range"
		_:
			return "invalid_policy"
	return ""


static func _rank_key(policy: Dictionary, row: Dictionary, has_blocker: bool) -> Array:
	var rank := int(policy["primary_rank"])
	match rank:
		TargetPolicyDefScript.RankKey.PROGRESS_DESC:
			var bucket := 0
			if (
				int(policy["aerial_rule"]) == TargetPolicyDefScript.AerialRule.PREFER
				and not bool(row["aerial"])
			):
				bucket = 1
			return [bucket, -int(row["progress_units"]), int(row["id"])]
		TargetPolicyDefScript.RankKey.DISTANCE_ASC:
			var relation_bucket := 0
			if not has_blocker and row["relation"] != RELATION_DEPLOYED_UNIT:
				relation_bucket = 1
			return [relation_bucket, int(row["distance"]), int(row["id"])]
		TargetPolicyDefScript.RankKey.ENGAGEMENT_ORDER_ASC:
			return [int(row["engagement_order"]), int(row["id"])]
		_:
			return [int(row["id"])]


static func _rank_less(a: Array, b: Array) -> bool:
	for index: int in mini(a.size(), b.size()):
		if int(a[index]) != int(b[index]):
			return int(a[index]) < int(b[index])
	return a.size() < b.size()


static func _tie_break_reason(policy: Dictionary, eligible: Array[Dictionary]) -> String:
	if eligible.size() < 2:
		return ""
	var rank := int(policy["primary_rank"])
	var first: Dictionary = eligible[0]
	var second: Dictionary = eligible[1]
	if rank == TargetPolicyDefScript.RankKey.ENTITY_ID_ASC:
		return "entity_id_tie_break"
	if rank == TargetPolicyDefScript.RankKey.PROGRESS_DESC:
		var same_progress := int(first["progress_units"]) == int(second["progress_units"])
		var same_bucket := bool(first["aerial"]) == bool(second["aerial"])
		return "entity_id_tie_break" if same_progress and same_bucket else ""
	if rank == TargetPolicyDefScript.RankKey.DISTANCE_ASC:
		return (
			"entity_id_tie_break"
			if int(first["distance"]) == int(second["distance"])
			else ""
		)
	if rank == TargetPolicyDefScript.RankKey.ENGAGEMENT_ORDER_ASC:
		return (
			"entity_id_tie_break"
			if int(first["engagement_order"]) == int(second["engagement_order"])
			else ""
		)
	return ""


static func _loser_reason(policy: Dictionary, selected: Dictionary, loser: Dictionary) -> String:
	var rank := int(policy["primary_rank"])
	if rank == TargetPolicyDefScript.RankKey.PROGRESS_DESC:
		if bool(selected["aerial"]) and not bool(loser["aerial"]):
			return "aerial_bucket_lost"
		if int(loser["progress_units"]) < int(selected["progress_units"]):
			return "lower_progress"
		return "entity_id_tie_break"
	if rank == TargetPolicyDefScript.RankKey.DISTANCE_ASC:
		if int(loser["distance"]) > int(selected["distance"]):
			return "farther_distance"
		return "entity_id_tie_break"
	if rank == TargetPolicyDefScript.RankKey.ENGAGEMENT_ORDER_ASC:
		if int(loser["engagement_order"]) > int(selected["engagement_order"]):
			return "later_engagement"
		return "entity_id_tie_break"
	return "entity_id_tie_break"


static func _has_current_blocker(rows: Array[Dictionary]) -> bool:
	for row: Dictionary in rows:
		if (
			bool(row["alive"])
			and row["faction"] == FACTION_OPERATOR
			and row["relation"] == RELATION_CURRENT_BLOCKER
		):
			return true
	return false


static func _decision(
	policy: Dictionary,
	attacker_kind: String,
	attacker_id: int,
	rows: Array[Dictionary],
	selected_id: int,
	selection_reason: String,
	tie_break_reason: String,
) -> Dictionary:
	return {
		"policy_id": String(policy.get("policy_id", "")),
		"attacker_kind": attacker_kind,
		"attacker_id": attacker_id,
		"considered": rows,
		"selected_id": selected_id,
		"selection_reason": selection_reason,
		"tie_break_reason": tie_break_reason,
	}


static func _reject_all(rows: Array[Dictionary], reason: String) -> void:
	for row: Dictionary in rows:
		row["eligible"] = false
		row["rejection_reason"] = reason
		row["rank_key"] = []


static func _enum_in_range(value: int, size: int) -> bool:
	return value >= 0 and value < size
