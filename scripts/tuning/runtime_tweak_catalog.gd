class_name RuntimeTweakCatalog
extends RefCounted

## Typed runtime-tuning catalog. Every entry names its application boundary so
## the panel can be honest about when a value becomes effective.

const CATEGORY_ORDER: Array[StringName] = [
	&"UI", &"GAMEPLAY", &"AUDIO", &"PLAYER", &"ENEMIES", &"ENVIRONMENT",
]
const APPLY_MODES: Array[StringName] = [
	&"LIVE", &"NEXT_BATTLE", &"NEXT_DEPLOY", &"NEXT_SPAWN",
]
const VALUE_TYPES: Array[StringName] = [&"bool", &"int", &"float", &"color"]


static func descriptors() -> Array[Dictionary]:
	return [
		# UI
		_float(&"ui.text_scale_multiplier", &"UI", "Text scale", "Multiplies the current accessibility text scale.", 1.0, 0.8, 1.5, 0.05, &"LIVE", "×"),
		_float(&"ui.hud_scale", &"UI", "Battle HUD scale", "Scales the battle status panel without changing gameplay space.", 1.0, 0.75, 1.5, 0.05, &"LIVE", "×"),
		_float(&"ui.hud_opacity", &"UI", "Battle HUD opacity", "Changes the transparency of the battle status panel.", 1.0, 0.35, 1.0, 0.05, &"LIVE", "×"),
		_float(&"ui.health_bar_width_scale", &"UI", "Health-bar width", "Scales operator and enemy health-bar widths.", 1.0, 0.5, 2.0, 0.05, &"LIVE", "×"),
		_float(&"ui.health_bar_height_scale", &"UI", "Health-bar height", "Scales operator and enemy health-bar heights.", 1.0, 0.5, 2.0, 0.05, &"LIVE", "×"),
		_bool(&"ui.tutorial_hints_enabled", &"UI", "Tutorial hints", "Enables guided first-mission and map-navigation hints.", true, &"NEXT_BATTLE"),
		_float(&"ui.map_hint_opacity", &"UI", "Map-hint opacity", "Changes the visibility of the map navigation hint.", 1.0, 0.0, 1.0, 0.05, &"LIVE", "×"),
		_float(&"ui.panel_opacity", &"UI", "Tweak-panel opacity", "Changes the tuning panel surface opacity.", 0.96, 0.65, 1.0, 0.01, &"LIVE", ""),

		# Gameplay
		_int(&"gameplay.base_hp", &"GAMEPLAY", "Core health", "Sets starting core health for newly opened battles.", 10, 1, 100, 1, &"NEXT_BATTLE"),
		_int(&"gameplay.starting_dp", &"GAMEPLAY", "Starting DP", "Sets deployment points available at battle start.", 10, 0, 99, 1, &"NEXT_BATTLE"),
		_int(&"gameplay.dp_cap", &"GAMEPLAY", "DP cap", "Sets the maximum deployment-point pool.", 99, 10, 999, 1, &"NEXT_BATTLE"),
		_float(&"gameplay.dp_regen_seconds", &"GAMEPLAY", "DP regeneration", "Seconds between passive deployment-point gains.", 1.0, 0.1, 5.0, 0.1, &"NEXT_BATTLE", "s", &"GAMEPLAY"),
		_int(&"gameplay.retreat_refund_percent", &"GAMEPLAY", "Retreat refund", "Percentage of deployment cost returned on retreat.", 50, 0, 100, 5, &"NEXT_BATTLE", "%"),
		_float(&"gameplay.sp_regen_seconds", &"GAMEPLAY", "SP regeneration", "Seconds required for one passive skill point.", 1.0, 0.1, 5.0, 0.1, &"NEXT_BATTLE", "s", &"GAMEPLAY"),
		_int(&"gameplay.damage_stagger_ticks", &"GAMEPLAY", "Damage stagger", "Simulation ticks an enemy pauses after taking damage.", 8, 0, 30, 1, &"NEXT_BATTLE", " ticks"),
		_float(&"gameplay.spawn_timing_multiplier", &"GAMEPLAY", "Spawn timing", "Scales every authored enemy and wave start time.", 1.0, 0.25, 3.0, 0.05, &"NEXT_BATTLE", "×", &"GAMEPLAY"),
		_int(&"gameplay.spawn_count_multiplier", &"GAMEPLAY", "Enemy quantity", "Duplicates each authored spawn while preserving deterministic order.", 1, 1, 4, 1, &"NEXT_BATTLE", "×"),
		_int(&"gameplay.leak_limit_bonus", &"GAMEPLAY", "Leak-limit bonus", "Adds to the stage leak allowance before defeat.", 0, -2, 20, 1, &"NEXT_BATTLE"),
		_float(&"gameplay.simulation_rate", &"GAMEPLAY", "Simulation rate", "Multiplies the active 1×/2×/4× battle speed.", 1.0, 0.25, 3.0, 0.05, &"LIVE", "×", &"GAMEPLAY"),

		# Audio
		_float(&"audio.master_gain", &"AUDIO", "Master gain", "Multiplies the current master output level.", 1.0, 0.0, 1.5, 0.05, &"LIVE", "×"),
		_float(&"audio.music_gain", &"AUDIO", "Music gain", "Multiplies the current music-bus level.", 1.0, 0.0, 1.5, 0.05, &"LIVE", "×"),
		_float(&"audio.sfx_gain", &"AUDIO", "SFX gain", "Multiplies the current effects-bus level.", 1.0, 0.0, 1.5, 0.05, &"LIVE", "×"),
		_bool(&"audio.music_enabled", &"AUDIO", "Music enabled", "Mutes or restores the music bus without stopping playback.", true, &"LIVE"),
		_bool(&"audio.sfx_enabled", &"AUDIO", "SFX enabled", "Mutes or restores the sound-effects bus.", true, &"LIVE"),
		_bool(&"audio.dynamic_music_enabled", &"AUDIO", "Dynamic battle music", "Allows threat and health state to change battle music.", true, &"LIVE"),
		_float(&"audio.music_pitch_multiplier", &"AUDIO", "Music pitch", "Scales music playback pitch for newly started cues.", 1.0, 0.75, 1.25, 0.01, &"LIVE", "×"),
		_float(&"audio.transition_duration_multiplier", &"AUDIO", "Music crossfade time", "Scales future music transition durations.", 1.0, 0.0, 2.0, 0.05, &"LIVE", "×"),

		# Player
		_float(&"player.health_multiplier", &"PLAYER", "Operator health", "Scales health for the next deployed operator.", 1.0, 0.25, 5.0, 0.05, &"NEXT_DEPLOY", "×", &"GAMEPLAY"),
		_float(&"player.attack_multiplier", &"PLAYER", "Operator attack", "Scales attack for the next deployed operator.", 1.0, 0.25, 5.0, 0.05, &"NEXT_DEPLOY", "×", &"GAMEPLAY"),
		_float(&"player.defense_multiplier", &"PLAYER", "Operator defense", "Scales defense for the next deployed operator.", 1.0, 0.0, 5.0, 0.05, &"NEXT_DEPLOY", "×", &"GAMEPLAY"),
		_int(&"player.resistance_bonus_permille", &"PLAYER", "Operator resistance", "Adds arts resistance to the next deployed operator.", 0, -500, 1000, 25, &"NEXT_DEPLOY", "‰", &"GAMEPLAY"),
		_float(&"player.attack_speed_multiplier", &"PLAYER", "Operator attack speed", "Scales attack cadence for the next deployed operator.", 1.0, 0.25, 4.0, 0.05, &"NEXT_DEPLOY", "×", &"GAMEPLAY"),
		_float(&"player.deployment_cost_multiplier", &"PLAYER", "Deployment cost", "Scales DP cost for the next deployment.", 1.0, 0.25, 3.0, 0.05, &"NEXT_DEPLOY", "×", &"GAMEPLAY"),
		_int(&"player.block_bonus", &"PLAYER", "Block bonus", "Adds block capacity to the next deployed operator.", 0, -3, 8, 1, &"NEXT_DEPLOY", "", &"GAMEPLAY"),
		_float(&"player.skill_cost_multiplier", &"PLAYER", "Skill SP cost", "Scales SP cost for the next deployed operator.", 1.0, 0.25, 3.0, 0.05, &"NEXT_DEPLOY", "×", &"GAMEPLAY"),
		_float(&"player.visual_scale", &"PLAYER", "Operator visual scale", "Scales operator artwork only; hit logic is unchanged.", 1.0, 0.5, 2.0, 0.05, &"LIVE", "×"),
		_color(&"player.visual_tint", &"PLAYER", "Operator visual tint", "Tints operator artwork without changing team identity.", Color.WHITE, &"LIVE"),
		_float(&"player.animation_speed", &"PLAYER", "Operator animation speed", "Scales operator presentation animation time.", 1.0, 0.0, 3.0, 0.05, &"LIVE", "×"),

		# Enemies
		_float(&"enemies.health_multiplier", &"ENEMIES", "Enemy health", "Scales health for enemies spawned after the change.", 1.0, 0.25, 5.0, 0.05, &"NEXT_SPAWN", "×", &"GAMEPLAY"),
		_float(&"enemies.attack_multiplier", &"ENEMIES", "Enemy attack", "Scales attack for enemies spawned after the change.", 1.0, 0.0, 5.0, 0.05, &"NEXT_SPAWN", "×", &"GAMEPLAY"),
		_float(&"enemies.defense_multiplier", &"ENEMIES", "Enemy defense", "Scales defense for enemies spawned after the change.", 1.0, 0.0, 5.0, 0.05, &"NEXT_SPAWN", "×", &"GAMEPLAY"),
		_int(&"enemies.resistance_bonus_permille", &"ENEMIES", "Enemy resistance", "Adds arts resistance to enemies spawned after the change.", 0, -500, 1000, 25, &"NEXT_SPAWN", "‰", &"GAMEPLAY"),
		_float(&"enemies.attack_speed_multiplier", &"ENEMIES", "Enemy attack speed", "Scales attack cadence for enemies spawned after the change.", 1.0, 0.25, 4.0, 0.05, &"NEXT_SPAWN", "×", &"GAMEPLAY"),
		_float(&"enemies.movement_speed_multiplier", &"ENEMIES", "Enemy movement speed", "Scales movement for enemies spawned after the change.", 1.0, 0.25, 4.0, 0.05, &"NEXT_SPAWN", "×", &"GAMEPLAY"),
		_float(&"enemies.leak_damage_multiplier", &"ENEMIES", "Enemy leak damage", "Scales core damage for enemies spawned after the change.", 1.0, 0.0, 5.0, 0.25, &"NEXT_SPAWN", "×", &"GAMEPLAY"),
		_float(&"enemies.visual_scale", &"ENEMIES", "Enemy visual scale", "Scales enemy artwork only; collision and blocking are unchanged.", 1.0, 0.5, 2.0, 0.05, &"LIVE", "×"),
		_color(&"enemies.visual_tint", &"ENEMIES", "Enemy visual tint", "Tints enemy artwork without changing threat rules.", Color.WHITE, &"LIVE"),
		_float(&"enemies.animation_speed", &"ENEMIES", "Enemy animation speed", "Scales enemy presentation animation time.", 1.0, 0.0, 3.0, 0.05, &"LIVE", "×"),

		# Environment
		_color(&"environment.backdrop_color", &"ENVIRONMENT", "Backdrop color", "Changes the battle background color.", Color("11131f"), &"LIVE"),
		_float(&"environment.backdrop_brightness", &"ENVIRONMENT", "Backdrop brightness", "Scales battle background brightness.", 1.0, 0.25, 2.0, 0.05, &"LIVE", "×"),
		_color(&"environment.terrain_tint", &"ENVIRONMENT", "Terrain tint", "Tints terrain and environmental landmarks.", Color.WHITE, &"LIVE"),
		_float(&"environment.terrain_opacity", &"ENVIRONMENT", "Terrain opacity", "Changes terrain and environmental landmark opacity.", 1.0, 0.25, 1.0, 0.05, &"LIVE", "×"),
		_float(&"environment.shadow_opacity", &"ENVIRONMENT", "Shadow opacity", "Scales operator and enemy ground shadows.", 1.0, 0.0, 2.0, 0.05, &"LIVE", "×"),
		_float(&"environment.vfx_opacity", &"ENVIRONMENT", "VFX opacity", "Changes combat effect-layer opacity.", 1.0, 0.0, 2.0, 0.05, &"LIVE", "×"),
		_float(&"environment.screen_shake_multiplier", &"ENVIRONMENT", "Screen shake", "Scales battle camera shake amplitude.", 1.0, 0.0, 3.0, 0.05, &"LIVE", "×"),
		_float(&"environment.pan_sensitivity", &"ENVIRONMENT", "Map pan sensitivity", "Scales mouse, touch, trackpad, and wheel map movement.", 1.0, 0.25, 3.0, 0.05, &"LIVE", "×"),
		_float(&"environment.landmark_scale", &"ENVIRONMENT", "Endpoint landmark scale", "Scales spawn and core landmark artwork.", 1.0, 0.5, 2.0, 0.05, &"LIVE", "×"),
		_float(&"environment.restoration_opacity", &"ENVIRONMENT", "Restoration-seal opacity", "Changes Act II restoration-lattice visibility.", 0.88, 0.0, 1.0, 0.05, &"LIVE", ""),
	]


static func categories() -> Array[StringName]:
	return CATEGORY_ORDER.duplicate()


static func descriptor(identifier: StringName) -> Dictionary:
	for entry: Dictionary in descriptors():
		if entry[&"id"] == identifier:
			return entry
	return {}


static func descriptors_for_category(category: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in descriptors():
		if entry[&"category"] == category:
			result.append(entry)
	return result


static func baseline_values() -> Dictionary:
	var result := {}
	for entry: Dictionary in descriptors():
		result[entry[&"id"]] = entry[&"default"]
	return result


static func sanitize(entry: Dictionary, candidate: Variant) -> Dictionary:
	var value_type := StringName(entry.get(&"type", &""))
	match value_type:
		&"bool":
			return {&"ok": candidate is bool, &"value": candidate if candidate is bool else entry[&"default"]}
		&"color":
			var parsed: Color
			if candidate is Color:
				parsed = candidate
			elif candidate is String and Color.html_is_valid(candidate):
				parsed = Color.from_string(candidate, entry[&"default"])
			else:
				return {&"ok": false, &"value": entry[&"default"]}
			return {&"ok": true, &"value": parsed}
		&"int", &"float":
			if typeof(candidate) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(candidate)):
				return {&"ok": false, &"value": entry[&"default"]}
			var minimum := float(entry[&"minimum"])
			var maximum := float(entry[&"maximum"])
			var step := float(entry[&"step"])
			var quantized := clampf(snappedf(float(candidate) - minimum, step) + minimum, minimum, maximum)
			return {
				&"ok": true,
				&"value": roundi(quantized) if value_type == &"int" else quantized,
			}
	return {&"ok": false, &"value": entry.get(&"default")}


static func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	var seen := {}
	for entry: Dictionary in descriptors():
		var identifier := StringName(entry.get(&"id", &""))
		if identifier.is_empty() or seen.has(identifier):
			errors.append("missing or duplicate tweak id: %s" % identifier)
		seen[identifier] = true
		if entry.get(&"category", &"") not in CATEGORY_ORDER:
			errors.append("invalid category for %s" % identifier)
		if entry.get(&"type", &"") not in VALUE_TYPES:
			errors.append("invalid type for %s" % identifier)
		if entry.get(&"apply_mode", &"") not in APPLY_MODES:
			errors.append("invalid apply mode for %s" % identifier)
		if not bool(sanitize(entry, entry.get(&"default")).get(&"ok", false)):
			errors.append("invalid default for %s" % identifier)
	return errors


static func _float(
	id: StringName,
	category: StringName,
	label: String,
	description: String,
	default_value: float,
	minimum: float,
	maximum: float,
	step: float,
	apply_mode: StringName,
	unit: String = "",
	integrity: StringName = &"COSMETIC",
) -> Dictionary:
	return _entry(id, category, label, description, &"float", default_value, minimum, maximum, step, apply_mode, unit, integrity)


static func _int(
	id: StringName,
	category: StringName,
	label: String,
	description: String,
	default_value: int,
	minimum: int,
	maximum: int,
	step: int,
	apply_mode: StringName,
	unit: String = "",
	integrity: StringName = &"GAMEPLAY",
) -> Dictionary:
	return _entry(id, category, label, description, &"int", default_value, minimum, maximum, step, apply_mode, unit, integrity)


static func _bool(
	id: StringName,
	category: StringName,
	label: String,
	description: String,
	default_value: bool,
	apply_mode: StringName,
	integrity: StringName = &"COSMETIC",
) -> Dictionary:
	return _entry(id, category, label, description, &"bool", default_value, 0.0, 1.0, 1.0, apply_mode, "", integrity)


static func _color(
	id: StringName,
	category: StringName,
	label: String,
	description: String,
	default_value: Color,
	apply_mode: StringName,
) -> Dictionary:
	return _entry(id, category, label, description, &"color", default_value, 0.0, 1.0, 1.0, apply_mode, "", &"COSMETIC")


static func _entry(
	id: StringName,
	category: StringName,
	label: String,
	description: String,
	value_type: StringName,
	default_value: Variant,
	minimum: float,
	maximum: float,
	step: float,
	apply_mode: StringName,
	unit: String,
	integrity: StringName,
) -> Dictionary:
	return {
		&"id": id,
		&"category": category,
		&"label": label,
		&"description": description,
		&"type": value_type,
		&"default": default_value,
		&"minimum": minimum,
		&"maximum": maximum,
		&"step": step,
		&"apply_mode": apply_mode,
		&"unit": unit,
		&"integrity": integrity,
	}
