class_name CampaignContextValidator
extends RefCounted

const KEYS := [
	"operator_ids", "trap_ids", "stage_order", "stage_rewards",
	"stage_recovery_rosters", "offers", "starting_traps",
	"promotion_rules", "combat_rules_sha256",
]


static func valid(context: Dictionary) -> bool:
	if not _exact_keys(context):
		return false
	return (
		context["promotion_rules"] is Dictionary
		and (context["promotion_rules"] as Dictionary).is_empty()
		and _is_hex_sha256(String(context["combat_rules_sha256"]))
	)


static func _exact_keys(value: Dictionary) -> bool:
	if value.size() != KEYS.size():
		return false
	for key: String in KEYS:
		if not value.has(key):
			return false
	return true


static func _is_hex_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for character: String in value:
		if character not in "0123456789abcdef":
			return false
	return true
