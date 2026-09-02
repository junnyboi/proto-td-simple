class_name CampaignV3Economy
extends RefCounted

## Canonical campaign-resolution economy. First clears retain their authored
## rewards; successful replays grant a fixed Marks stipend once the replay
## economy is active for that save generation.

const REPLAY_CLEAR_MARKS := 20


static func resolution_rewards(
	before: Dictionary,
	stage_id: String,
	result: String,
	stars_before: int,
	context: Dictionary,
) -> Array[Dictionary]:
	if result != "clear":
		return []
	if stars_before == 0:
		return _stage_rewards(stage_id, context)
	if (
		int(before["next_resolution_index"])
		>= int(before["replay_marks_started_at_resolution"])
	):
		return [{"amount": REPLAY_CLEAR_MARKS, "id": "marks", "kind": "currency"}]
	return []


static func _stage_rewards(stage_id: String, context: Dictionary) -> Array[Dictionary]:
	for row: Dictionary in context["campaign"]["v3_stage_rewards"]:
		if row["stage_id"] == stage_id:
			return row["rewards"].duplicate(true)
	return []
