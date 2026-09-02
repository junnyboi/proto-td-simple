extends "res://sim/campaign_strategic_commands.gd"

## Read-only strategic personnel projection for Training UI. Stable roster order
## and model-owned eligibility keep presentation from reconstructing rules.

func training_roster() -> Array[Dictionary]:
	var values: Array[Dictionary] = []
	for hero: HeroState in _roster().all():
		var callsign := hero.display_callsign()
		var options := _promotion_options(hero.hero_id())
		var advanced: Variant = hero.advanced_class_id()
		values.append({
			"hero_id": hero.hero_id(),
			"callsign": String(callsign.get("value", hero.hero_id())),
			"identity_portrait_id": String(hero.identity_portrait_id()),
			"first_class_id": String(hero.first_class_id()),
			"advanced_class_id": String(advanced) if advanced != null else null,
			"current_class_id": (
				String(advanced) if advanced != null else String(hero.first_class_id())
			),
			"operator_def_id": String(hero.operator_def_id()),
			"life_status": String(hero.life_status()),
			"xp": hero.xp(),
			"xp_required": int(_context["promotion_rules"].get("xp_required", 0)),
			"can_promote": bool(options["accepted"]),
			"eligibility_error": options["error_code"],
			"choices": (
				(options["choices"] as Array).duplicate(true)
				if options["accepted"] else []
			),
		})
	return values


func _promotion_options(hero_id: String) -> Dictionary:
	for hero: Dictionary in _data["heroes"]:
		if hero["hero_id"] == hero_id:
			return CampaignProgressionType.promotion_options(
				hero, _context["promotion_rules"],
			)
	return {"accepted": false, "error_code": &"unknown_hero"}
