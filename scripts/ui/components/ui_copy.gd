class_name UiCopy
extends RefCounted

const GeneratedLocalizationSchemaType := preload("res://scripts/ui/components/generated_localization_schema.gd")

const STATIC_FALLBACKS := {
	&"ui.game_title": "Game template - TD",
	&"ui.hero.fallback_recruit": "Recruit #{index}",
	&"ui.title.full_title": "Game template - TD",
	&"ui.title.synopsis": "Humans discovered anima—the real human soul—and connected its power to PROTOS. The AI became corrupted, built human farms, and used stolen souls to create a robot empire. Command Company Manus to rescue the captives and break the harvesting network.",
	&"ui.title.start": "Start",
	&"ui.title.start_retry": "Retry Start",
	&"ui.title.a11y.start_failed_description": "Campaign startup failed. Activate Start again to retry.",
	&"ui.title.a11y.quick_language_to_chinese": "Switch language to Simplified Chinese",
	&"ui.title.a11y.quick_language_to_english": "Switch language to English",
	&"ui.title.quick_language": "EN / 中文",
	&"ui.title.settings": "Settings",
	&"ui.title.footer_settings_a11y": "Open Settings",
	&"ui.title.settings_save_failed": "Settings could not be saved. Review the draft and try again.",
	&"ui.title.audio": "Audio",
	&"ui.title.accessibility": "Accessibility",
	&"ui.title.graphics": "Graphics",
	&"ui.title.master_volume": "Master Volume  //  {value}%",
	&"ui.title.mute": "Mute",
	&"ui.title.mute_master": "Mute Master",
	&"ui.title.unmute": "Unmute",
	&"ui.title.unmute_master": "Unmute Master",
	&"ui.title.a11y.master_mute_description": "Mute or restore all game audio without changing the Master volume slider.",
	&"ui.title.music_volume": "Music Volume  //  {value}%",
	&"ui.title.sfx_volume": "SFX Volume  //  {value}%",
	&"ui.title.music_state": "Music  //  {state}",
	&"ui.title.frame_limit": "Frame Limit",
	&"ui.title.frame_unlimited": "Unlimited",
	&"ui.title.frame_value": "{value} FPS",
	&"ui.title.motion_state": "Reduced Motion  //  {state}",
	&"ui.title.text_scale": "Text Scale  //  {value}%",
	&"ui.title.seed": "seed {seed}",
	&"ui.common.on": "On",
	&"ui.common.off": "Off",
	&"ui.common.cancel": "Cancel",
	&"ui.common.apply": "Apply",
	&"ui.battle.pause": "PAUSE",
	&"ui.battle.pause_menu_body": "The operation is suspended. Press Escape to return to battle.",
	&"ui.battle.pause_menu_resign_description": "Open the confirmation to resign from this operation.",
	&"ui.battle.pause_menu_settings_description": "Open game settings while the operation remains paused.",
	&"ui.battle.resume": "RESUME",
	&"ui.battle.paused": "PAUSED",
	&"ui.battle.speed_shortcuts": "Q: LOWER SPEED  •  E: RAISE SPEED",
	&"ui.battle.resign": "RESIGN",
	&"ui.battle.withdraw_title": "WITHDRAW FROM OPERATION?",
	&"ui.battle.withdraw_body": "Withdrawal immediately seals this attempt as a defeat. Current deployment progress is not preserved.",
	&"ui.battle.confirm_defeat": "CONFIRM DEFEAT",
	&"ui.battle.return": "RETURN TO BATTLE",
	&"ui.battle.withdrawing": "WITHDRAWING…",
	&"ui.battle.state_active": "ACTIVE",
	&"ui.battle.state_clear": "CLEAR",
	&"ui.battle.state_defeat": "DEFEAT",
	&"ui.battle.hud_compact": "LEAKS {leaks} / {leak_threshold}   DP {dp}\nELIMS {eliminations}   {state}",
	&"ui.battle.hud_wide": "LEAKS  {leaks} / {leak_threshold}    DP  {dp}    ELIMINATIONS  {eliminations}    {state}",
	&"ui.battle.continue_debrief": "CONTINUE",
	&"ui.battle.finalizing_debrief": "FINALIZING DEBRIEF…",
	&"ui.battle.operator_actions": "Operator actions",
	&"ui.battle.operator_actions_description": "{operator}. {skill}. {current} of {cost} SP.",
	&"ui.battle.recall": "RECALL",
	&"ui.battle.recall_description": "Recall {operator} and begin their redeployment cooldown.",
	&"ui.battle.retry_finalization": "RETRY FINALIZATION",
	&"ui.battle.retreat": "Retreat",
	&"ui.battle.skill_activate": "ACTIVATE — {skill}",
	&"ui.battle.skill_activate_description": "Activate {skill}.",
	&"ui.battle.skill_cancel_targeting": "CANCEL TARGETING",
	&"ui.battle.skill_charging": "CHARGING {current} / {cost}",
	&"ui.battle.skill_charging_description": "{skill} is charging: {current} of {cost} SP.",
	&"ui.battle.skill_none": "NO ACTIVE SKILL",
	&"ui.battle.skill_progress": "{skill}  //  SP {current} / {cost}",
	&"ui.battle.skill_state_charging": "CHARGING",
	&"ui.battle.skill_state_none": "NO SKILL",
	&"ui.battle.skill_state_ready": "SKILL READY",
	&"ui.battle.skill_state_targeting": "SELECT TARGET",
	&"ui.battle.skill_targeting_description": "Choose a wounded ally in range for {skill}.",
	&"ui.battle.skill_targeting_instruction": "Select a wounded ally in range. Right-click or press Escape to cancel.",
	&"ui.tutorial.block.action": "Start battle",
	&"ui.tutorial.block.body": (
		"A Recruit blocks 1 ground enemy and loses HP while fighting. "
		+ "Deploy another when DP refills."
	),
	&"ui.tutorial.block.step": "3 / 3  BLOCK",
	&"ui.tutorial.block.title": "Hold the line",
	&"ui.tutorial.deploy.body": (
		"DP pays for units. Drag a Recruit card onto any green path tile; "
		+ "the gold marker is a safe starting position."
	),
	&"ui.tutorial.deploy.cancelled": (
		"Placement cancelled. Drag a Recruit onto a green path tile when ready."
	),
	&"ui.tutorial.deploy.dragging": (
		"Green tiles are valid. Release on the gold marker or any green path tile."
	),
	&"ui.tutorial.deploy.invalid": (
		"That cell cannot hold this Recruit. Use a green path tile."
	),
	&"ui.tutorial.deploy.step": "2 / 3  DEPLOY",
	&"ui.tutorial.deploy.title": "Deploy a Recruit",
	&"ui.tutorial.dismiss": "Dismiss",
	&"ui.tutorial.facing.body": (
		"Facing rotates attack coverage. Aim toward the incoming route; "
		+ "any arrow deploys the unit."
	),
	&"ui.tutorial.facing.step": "3 / 4  FACING",
	&"ui.tutorial.facing.title": "Choose facing",
	&"ui.tutorial.live.body": (
		"Spend refilling DP, reinforce the route, and stop the 4th leak."
	),
	&"ui.tutorial.live.step": "FIELD REMINDER",
	&"ui.tutorial.live.title": "Defend the base",
	&"ui.tutorial.route.action": "NEXT",
	&"ui.tutorial.route.body": (
		"Enemies start from the portal and follow the lit path to your base crystal. "
		+ "This mission allows 3 leaks, the 4th leak will end the mission."
	),
	&"ui.tutorial.route.step": "1 / 3  ROUTE",
	&"ui.tutorial.route.title": "Read the route",
	&"ui.tutorial.skip": "Skip tutorial",
	&"ui.map_navigation.hint_title": "DRAG TO PAN",
	&"ui.map_navigation.hint_body": "Explore the full battlefield on every open axis.",
	&"ui.onboarding.command.a11y": "Command Center tutorial",
	&"ui.onboarding.command.skip": "SKIP",
	&"ui.onboarding.command.mission.step": "1 / 2  MISSION CONTROL",
	&"ui.onboarding.command.mission.title": "Choose an operation",
	&"ui.onboarding.command.mission.body": "Mission Control lists every available operation. Select one to begin the mission immediately.",
	&"ui.onboarding.command.next": "NEXT",
	&"ui.onboarding.command.done": "DONE",
	&"ui.onboarding.post_mission.a11y": "Post-mission tutorial",
	&"ui.locale.label": "Language",
	&"ui.locale.en_us": "EN",
	&"ui.locale.zh_cn": "中文",
	&"ui.staging.heading": "STAGING",
	&"ui.staging.command_heading": "COMMAND CENTER",
	&"ui.staging.command_body": (
		"PROTOS drains living captives in human farms and uses their souls to power "
		+ "a robot empire. Company Manus defends Hearthcross, rescues people and souls, "
		+ "and breaks the harvesting network."
	),
	&"ui.staging.difficulty": "DIFFICULTY — {rank}/5",
	&"ui.staging.mission_brief": "MISSION BRIEF",
	&"ui.staging.mission_facts": (
		"SQUAD {squad} · WAVE WINDOWS {waves} · LEAK LIMIT {leak_limit}"
	),
	&"ui.staging.next_operation_title": "NEXT {index}: {title}",
	&"ui.staging.next_operation_action": "Review {stage} in Mission Control",
	&"ui.staging.next_operation_description": "Open Mission Control with this operation ready for selection.",
	&"ui.staging.campaign_summary": "{cleared}/{total} CLEARED",
	&"ui.staging.next_none": "NEXT: No active campaign",
	&"ui.staging.next_label": "NEXT OPERATION",
	&"ui.staging.next_detail": "NEXT: {index}. {title}",
	&"ui.staging.next_complete": "NEXT: Campaign complete",
	&"ui.staging.operation_status": "OPERATIONS — UNAVAILABLE",
	&"ui.staging.operations": "OPERATIONS",
	&"ui.staging.mission_control": "Mission Control",
	&"ui.staging.mission_control_display": "MISSION\nCONTROL",
	&"ui.staging.mission_control_short": "Control",
	&"ui.staging.resource_aether": "Aether",
	&"ui.staging.resource_sigils": "Astral Sigils",
	&"ui.staging.resource_stamina": "Stamina",
	&"ui.roster.tab.active": "Active",
	&"ui.roster.filter.all": "All",
	&"ui.roster.filter.all_factions": "All factions",
	&"ui.roster.empty": "No soldiers match the selected roster filters.",
	&"ui.rename.current_identity": "CURRENT IDENTITY",
	&"ui.rename.new_identity": "NEW IDENTITY",
	&"ui.rename.reversible_note": "This cosmetic identity can be changed again outside active operations.",
	&"ui.rename.selected_operator": "SELECTED OPERATOR",
	&"ui.rename.close_editor": "Close Editor",
	&"ui.rename.close_short": "Close",
	&"ui.rename.edit_identity": "Edit Identity",
	&"ui.rename.edit_identity_description": "Show or hide the selected operator identity editor.",
	&"ui.rename.edit_short": "Edit",
	&"ui.rename.no_title": "NO TITLE ASSIGNED",
	&"ui.rename.committing": "RENAMING…",
	&"ui.common.exit": "Exit",
	&"ui.common.back": "Back",
	&"ui.campaign.heading": "Campaign",
	&"ui.campaign.row": "{index}. {title}{status}",
	&"ui.campaign.locked_suffix": "  LOCKED",
	&"ui.campaign.cleared_suffix": "  {stars}",
	&"ui.campaign.next_highlight_description": "Recommended next operation, highlighted with a glow and sparkles.",
	&"ui.campaign.route_note": "Select an available operation, or replay a cleared one.",
	&"ui.campaign.row_star": "{count} star",
	&"ui.campaign.row_stars": "{count} stars",
	&"ui.campaign.first_clear_reward": "FIRST CLEAR — {rewards}",
	&"ui.campaign.record_only": "RECORD ONLY",
	&"ui.campaign.start_mission": "Start Mission",
	&"ui.identity_sort.cost_asc": "Cost low–high",
	&"ui.identity_sort.cost_desc": "Cost high–low",
	&"ui.identity_sort.label": "Sort operators",
	&"ui.identity_sort.level_asc": "Level low–high",
	&"ui.identity_sort.level_desc": "Level high–low",
	&"ui.identity_sort.rarity_asc": "Rarity low–high",
	&"ui.identity_sort.rarity_desc": "Rarity high–low",
	&"ui.battle.deploy_operator_cooldown": "{name}{slot}\nCOOLDOWN {seconds}s",
	&"ui.results.clear": "CLEAR",
	&"ui.results.defeat": "DEFEAT",
	&"ui.results.eyebrow": "AFTER-ACTION RELIQUARY",
	&"ui.results.yield": "MISSION YIELD",
	&"ui.results.no_rewards": "NO NEW MATERIAL REWARDS",
	&"ui.results.record_preserved": "Operation record preserved.",
	&"ui.results.marks_reward": "+{count}",
	&"ui.results.unlocked_kind": "UNLOCKED · {kind}",
	&"ui.results.tally": "kills {kills}   leaks {leaks}",
	&"ui.results.reward": "Unlocked: {name}",
	&"ui.results.stage_cleared": "STAGE {stage} CLEARED",
	&"ui.results.stage_defeated": "STAGE {stage} DEFEATED",
	&"ui.results.retry": "Retry",
	&"ui.results.next_mission": "Next Mission",
	&"ui.results.return_to_staging": "Return to Staging",
	&"ui.save.write_failed": "The campaign could not be saved.",
	&"ui.error.unknown": "The request failed. Try again.",
}

const PLACEHOLDER_TYPES := {
	&"ui.campaign.row_star": {&"count": &"int"},
	&"ui.campaign.row_stars": {&"count": &"int"},
	&"ui.battle.hud_compact": {&"leaks": &"int", &"leak_threshold": &"int", &"dp": &"int", &"eliminations": &"int", &"state": &"String"},
	&"ui.battle.hud_wide": {&"leaks": &"int", &"leak_threshold": &"int", &"dp": &"int", &"eliminations": &"int", &"state": &"String"},
	&"ui.battle.operator_actions_description": {
		&"operator": &"String", &"skill": &"String", &"current": &"int", &"cost": &"int",
	},
	&"ui.battle.recall_description": {&"operator": &"String"},
	&"ui.battle.skill_activate": {&"skill": &"String"},
	&"ui.battle.skill_activate_description": {&"skill": &"String"},
	&"ui.battle.skill_charging": {&"current": &"int", &"cost": &"int"},
	&"ui.battle.skill_charging_description": {
		&"skill": &"String", &"current": &"int", &"cost": &"int",
	},
	&"ui.battle.skill_progress": {
		&"skill": &"String", &"current": &"int", &"cost": &"int",
	},
	&"ui.battle.skill_targeting_description": {&"skill": &"String"},
	&"ui.battle.deploy_operator_cooldown": {
		&"name": &"String", &"slot": &"String", &"seconds": &"int",
	},
	&"ui.battle.high_threat.green_cage.detail": {&"wave": &"int"},
	&"ui.results.marks_reward": {&"count": &"int"},
	&"ui.results.unlocked_kind": {&"kind": &"String"},
	&"ui.hero.fallback_recruit": {&"index": &"int"},
	&"ui.title.music_state": {&"state": &"String"},
	&"ui.title.motion_state": {&"state": &"String"},
	&"ui.title.master_volume": {&"value": &"int"},
	&"ui.title.music_volume": {&"value": &"int"},
	&"ui.title.sfx_volume": {&"value": &"int"},
	&"ui.title.text_scale": {&"value": &"int"},
	&"ui.title.frame_value": {&"value": &"int"},
	&"ui.staging.campaign_summary": {&"cleared": &"int", &"total": &"int"},
	&"ui.staging.difficulty": {&"rank": &"int"},
	&"ui.staging.mission_facts": {
		&"leak_limit": &"int", &"squad": &"int", &"waves": &"int",
	},
	&"ui.staging.next_detail": {&"index": &"int", &"title": &"String"},
	&"ui.staging.next_operation_title": {&"index": &"int", &"title": &"String"},
	&"ui.staging.next_operation_action": {&"stage": &"String"},
	&"ui.campaign.first_clear_reward": {&"rewards": &"String"},
	&"ui.campaign.row": {&"index": &"int", &"title": &"String", &"status": &"String"},
	&"ui.campaign.cleared_suffix": {&"stars": &"String"},
	&"ui.results.tally": {&"kills": &"int", &"leaks": &"int"},
	&"ui.results.reward": {&"name": &"String"},
	&"ui.results.stage_cleared": {&"stage": &"String"},
	&"ui.results.stage_defeated": {&"stage": &"String"},
	&"ui.identity_filter.summary": {&"shown": &"int", &"total": &"int"},
	&"ui.rename.confirm_body": {&"current": &"String", &"next": &"String"},
}


static func text(key: StringName, fallback: String) -> String:
	var i18n := _i18n()
	return String(i18n.call("t", key, fallback)) if i18n != null else fallback


static func format_text(key: StringName, fallback: String, args: Dictionary) -> String:
	var i18n := _i18n()
	return String(i18n.call("format_text", key, fallback, args)) if i18n != null else fallback.format(args)


static func _i18n() -> Node:
	var main_loop := Engine.get_main_loop()
	if main_loop is SceneTree:
		return (main_loop as SceneTree).root.get_node_or_null("I18n")
	return null


static func stage_title(stage: StageDef) -> String:
	if stage == null:
		push_error("UiCopy.stage_title: null stage")
		return ""
	return text(StringName("data.stage.%s.title" % stage.id), stage.title)


static func operator_name(definition: OperatorDef) -> String:
	if definition == null:
		push_error("UiCopy.operator_name: null definition")
		return ""
	return text(
		StringName("data.operator.%s.name" % definition.id), definition.display_name,
	)


static func skill_name(skill_id: StringName) -> String:
	var fallbacks := {
		&"conflagration": "Conflagration",
		&"deadeye": "Deadeye",
		&"flurry": "Flurry",
	}
	var fallback := String(
		fallbacks.get(skill_id, String(skill_id).replace("_", " ").capitalize()),
	)
	return text(StringName("ui.skill_name.%s" % skill_id), fallback)


static func trap_name(definition: TrapDef) -> String:
	if definition == null:
		push_error("UiCopy.trap_name: null definition")
		return ""
	return text(StringName("data.trap.%s.name" % definition.id), definition.display_name)

static func enemy_name(enemy_id: StringName) -> String:
	var fallback_names := {
		&"grunt": "Collector",
		&"runner": "Tagger",
		&"drone": "Hunter Drone",
		&"shieldbearer": "Shieldbearer",
		&"breacher": "Breacher",
		&"spellcaster": "Channeler",
		&"heavy": "Farm Warden",
		&"interceptor": "Interceptor Drone",
		&"mini_boss": "Gatecrasher",
	}
	var fallback := String(fallback_names.get(enemy_id, "Robot"))
	return text(StringName("data.enemy.%s.name" % enemy_id), fallback)


static func static_fallbacks() -> Dictionary:
	return STATIC_FALLBACKS.duplicate(true)


static func placeholder_types() -> Dictionary:
	var merged := PLACEHOLDER_TYPES.duplicate(true)
	for raw_key: Variant in GeneratedLocalizationSchemaType.PLACEHOLDER_TYPES:
		var key := StringName(raw_key)
		var generated := (
			GeneratedLocalizationSchemaType.PLACEHOLDER_TYPES[raw_key] as Dictionary
		).duplicate(true)
		if merged.has(key):
			assert(
				(merged[key] as Dictionary) == generated,
				"Generated localization schema conflicts with UiCopy schema for %s" % key,
			)
		merged[key] = generated
	return merged
