class_name CampaignV3PromotionRules
extends RefCounted


static func validate_choice(
	data: Dictionary,
	context: Dictionary,
	choice: Dictionary,
) -> Dictionary:
	var hero := _hero_by_id(data["heroes"], choice["hero_id"])
	if hero.is_empty():
		return _reject(&"unknown_hero")
	if hero["life_status"] != "ready":
		return _reject(&"dead_hero")
	if hero["current_class_id"] == choice["to_class_id"]:
		return _reject(&"already_promoted_class")
	var current: Dictionary = context["class_by_id"].get(hero["current_class_id"], {})
	var target: Dictionary = context["class_by_id"].get(choice["to_class_id"], {})
	if current.is_empty() or target.is_empty():
		return _reject(&"missing_catalog")
	if not (current["promotion_to_class_ids"] as Array).has(choice["to_class_id"]):
		return _reject(&"illegal_class_edge")
	if int(hero["xp"]) < int(current["promotion_xp_required"]):
		return _reject(&"insufficient_xp")
	var entitlement := String(target["entitlement_id"])
	if not entitlement.is_empty() and not (data["class_entitlements"] as Array).has(entitlement):
		return _reject(&"locked_class")
	var operator_id := String(target["operator_def_id"])
	if not context["operator_ticket_by_id"].has(operator_id):
		return _reject(&"missing_catalog")
	return _accept(
		{
			"hero_id": String(hero["hero_id"]),
			"from_class_id": String(hero["current_class_id"]),
			"to_class_id": String(choice["to_class_id"]),
			"operator_def_id": operator_id,
		}
	)


static func _hero_by_id(heroes: Array, hero_id: String) -> Dictionary:
	for hero: Dictionary in heroes:
		if hero["hero_id"] == hero_id:
			return hero
	return {}


static func _accept(value: Variant) -> Dictionary:
	return {"accepted": true, "error_code": &"", "value": value}


static func _reject(code: StringName) -> Dictionary:
	return {"accepted": false, "error_code": code}
