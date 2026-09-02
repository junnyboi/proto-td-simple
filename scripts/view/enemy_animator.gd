class_name EnemyAnimator
extends RefCounted

## Presentation-only enemy adapter. The Grunt is the sole frame-animated enemy;
## every other production enemy uses one core-resident static texture with
## deterministic transform animation. No method mutates authoritative battle state.

const UiCopyType := preload("res://scripts/ui/components/ui_copy.gd")
const EnemyDeathParticlesType := preload("res://scripts/view/enemy_death_particles.gd")

const FRAME_COUNT := 25
const LOOP_FRAME_COUNT := FRAME_COUNT - 1
const WALK_FPS := 12.0
const BLEND_FRAMES := 6
const BODY_PX := 64.0
const LEGACY_ENEMY_PX := 40.0
const LEGACY_AERIAL_PX := 24.0
const LEGACY_SPRITE_SCALE := 2
const LEGACY_BOB_FRAMES := 24
const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.35)
const SHADOW_FACE_SCALE := 0.3125
const AERIAL_SHADOW_DROP := 10.0
const FALLBACK_COLOR := Color("ef7d57")
const STATIC_PREFIX := "enemy_static_"
const STATIC_ENEMIES: Array[StringName] = [
	&"runner",
	&"shieldbearer",
	&"breacher",
	&"heavy",
	&"drone",
	&"interceptor",
	&"spellcaster",
	&"mini_boss",
]
const STATIC_BODY_PX := {
	&"runner": 58.0,
	&"shieldbearer": 72.0,
	&"breacher": 80.0,
	&"heavy": 74.0,
	&"drone": 56.0,
	&"interceptor": 66.0,
	&"spellcaster": 68.0,
	&"mini_boss": 88.0,
}
const STATIC_MOTION_PROFILES := {
	&"runner": {&"frequency": 2.8, &"bob": 1.2, &"roll": 0.030, &"squash": 0.020, &"lunge": 3.0},
	&"shieldbearer": {&"frequency": 1.35, &"bob": 1.4, &"roll": 0.013, &"squash": 0.012, &"lunge": 3.0},
	&"breacher": {&"frequency": 1.15, &"bob": 1.3, &"roll": 0.014, &"squash": 0.014, &"lunge": 4.0},
	&"heavy": {&"frequency": 0.82, &"bob": 1.0, &"roll": 0.012, &"squash": 0.015, &"lunge": 2.5},
	&"drone": {&"frequency": 1.70, &"bob": 2.2, &"roll": 0.035, &"squash": 0.008, &"lunge": 1.0},
	&"interceptor": {&"frequency": 1.25, &"bob": 1.7, &"roll": 0.040, &"squash": 0.010, &"lunge": 2.0},
	&"spellcaster": {&"frequency": 1.10, &"bob": 1.4, &"roll": 0.020, &"squash": 0.012, &"lunge": 2.0},
	&"mini_boss": {&"frequency": 0.72, &"bob": 1.0, &"roll": 0.011, &"squash": 0.012, &"lunge": 3.0},
}
const STATIC_EFFECT_PROFILES := {
	&"runner": {
		&"flash_primary": Color("fff1c7"), &"flash_secondary": Color("d96adf"),
		&"flash_seconds": 0.10, &"dissolve_seconds": 0.42, &"dissolve_mode": 0.0,
		&"edge_color": Color("d96adf"), &"particle_style": &"runner_trail",
		&"particle_count": 16, &"particle_lifetime": 0.50, &"particle_origin_y": 0.62,
		&"particle_colors": [Color("f4d35e"), Color("f2e9d8"), Color("17151c"), Color("c964cf"), Color("73eff7")],
	},
	&"shieldbearer": {
		&"flash_primary": Color("fff0cf"), &"flash_secondary": Color("d85bce"),
		&"flash_seconds": 0.12, &"dissolve_seconds": 0.48, &"dissolve_mode": 1.0,
		&"edge_color": Color("d9b56b"), &"particle_style": &"shield_fan",
		&"particle_count": 18, &"particle_lifetime": 0.56, &"particle_origin_y": 0.56,
		&"particle_colors": [Color("f4e6c8"), Color("d9b56b"), Color("17151c"), Color("b83fae"), Color("73eff7")],
	},
	&"breacher": {
		&"flash_primary": Color("fff1d0"), &"flash_secondary": Color("d94cff"),
		&"flash_seconds": 0.12, &"dissolve_seconds": 0.48, &"dissolve_mode": 2.0,
		&"edge_color": Color("d94cff"), &"particle_style": &"ram_fan",
		&"particle_count": 18, &"particle_lifetime": 0.42, &"particle_origin_y": 0.68,
		&"particle_colors": [Color("f4e9d8"), Color("c9a227"), Color("17151a"), Color("d94cff"), Color("73e6f2")],
	},
	&"heavy": {
		&"flash_primary": Color("fff4d6"), &"flash_secondary": Color("c43dff"),
		&"flash_seconds": 0.14, &"dissolve_seconds": 0.52, &"dissolve_mode": 3.0,
		&"edge_color": Color("c43dff"), &"particle_style": &"bars",
		&"particle_count": 18, &"particle_lifetime": 0.58, &"particle_origin_y": 0.58,
		&"particle_colors": [Color("fff4d6"), Color("e8d7b0"), Color("c9a45b"), Color("17151c"), Color("c43dff"), Color("73e6f2")],
	},
	&"drone": {
		&"flash_primary": Color("bdf7ff"), &"flash_secondary": Color("c04cff"),
		&"flash_seconds": 0.12, &"dissolve_seconds": 0.48, &"dissolve_mode": 4.0,
		&"edge_color": Color("bdf7ff"), &"particle_style": &"relay",
		&"particle_count": 18, &"particle_lifetime": 0.55, &"particle_origin_y": 0.50,
		&"particle_colors": [Color("c04cff"), Color("f06bda"), Color("bdf7ff"), Color("fff4d6"), Color("d8a84e"), Color("11131a")],
	},
	&"interceptor": {
		&"flash_primary": Color("e9c7f2"), &"flash_secondary": Color("73eff7"),
		&"flash_seconds": 0.12, &"dissolve_seconds": 0.46, &"dissolve_mode": 5.0,
		&"edge_color": Color("c94bdb"), &"particle_style": &"spear",
		&"particle_count": 18, &"particle_lifetime": 0.42, &"particle_origin_y": 0.50,
		&"particle_colors": [Color("c94bdb"), Color("e9c7f2"), Color("d6b36a"), Color("f4ebd0"), Color("73eff7"), Color("14151a")],
	},
	&"spellcaster": {
		&"flash_primary": Color("f08cff"), &"flash_secondary": Color("fff4d6"),
		&"flash_seconds": 0.12, &"dissolve_seconds": 0.46, &"dissolve_mode": 6.0,
		&"edge_color": Color("f08cff"), &"particle_style": &"fork",
		&"particle_count": 18, &"particle_lifetime": 0.52, &"particle_origin_y": 0.54,
		&"particle_colors": [Color("c964cf"), Color("94216a"), Color("f4d35e"), Color("fff4d6"), Color("11131a")],
	},
	&"mini_boss": {
		&"flash_primary": Color("fff1b8"), &"flash_secondary": Color("d94bc2"),
		&"flash_seconds": 0.12, &"dissolve_seconds": 0.52, &"dissolve_mode": 7.0,
		&"edge_color": Color("d6a84f"), &"particle_style": &"key_burst",
		&"particle_count": 20, &"particle_lifetime": 0.48, &"particle_origin_y": 0.52,
		&"particle_colors": [Color("f4e9d0"), Color("d6a84f"), Color("17151d"), Color("b83fae"), Color("73eff7")],
	},
}
const DAMAGE_FLASH_SHADER_SOURCE := """
shader_type canvas_item;
uniform vec4 flash_color : source_color = vec4(1.0);
uniform float flash_strength : hint_range(0.0, 1.0) = 0.0;
uniform float dissolve_progress : hint_range(0.0, 1.0) = 0.0;
uniform float dissolve_mode : hint_range(0.0, 7.0) = 0.0;
uniform float dissolve_seed = 0.0;
uniform vec4 dissolve_edge_color : source_color = vec4(0.8, 0.3, 1.0, 1.0);

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32 + dissolve_seed);
	return fract(p.x * p.y);
}

float dissolve_metric(vec2 uv) {
	float mode = floor(dissolve_mode + 0.5);
	if (mode < 0.5) return uv.x;
	if (mode < 1.5) return 1.0 - clamp(distance(uv, vec2(0.48, 0.56)) * 1.42, 0.0, 1.0);
	if (mode < 2.5) return 1.0 - uv.y;
	if (mode < 3.5) return clamp((1.0 - uv.y) * 0.78 + (1.0 - abs(uv.x - 0.5) * 2.0) * 0.22, 0.0, 1.0);
	if (mode < 4.5) return 1.0 - uv.y;
	if (mode < 5.5) return clamp((1.0 - uv.y) * 0.72 + abs(uv.x - 0.5) * 0.56, 0.0, 1.0);
	if (mode < 6.5) return clamp((1.0 - uv.y) * 0.76 + uv.x * 0.24, 0.0, 1.0);
	return clamp(distance(uv, vec2(0.5, 0.58)) * 1.16 + (1.0 - uv.y) * 0.22, 0.0, 1.0);
}

void fragment() {
	vec4 pixel = COLOR;
	float metric = dissolve_metric(UV) + (hash21(floor(UV * 96.0)) - 0.5) * 0.16;
	float active = step(0.0005, dissolve_progress);
	float survive = mix(1.0, smoothstep(dissolve_progress - 0.055, dissolve_progress + 0.055, metric), active);
	float edge = (1.0 - smoothstep(0.0, 0.075, abs(metric - dissolve_progress))) * active;
	float terminal_visible = 1.0 - step(0.9995, dissolve_progress);
	survive *= terminal_visible;
	edge *= terminal_visible;
	pixel.rgb = mix(pixel.rgb, flash_color.rgb, flash_strength);
	pixel.rgb = mix(pixel.rgb, dissolve_edge_color.rgb, edge * 0.82);
	pixel.a *= survive;
	COLOR = pixel;
}
"""
const TYPE_COLORS := {
	&"grunt": Color("ef7d57"),
	&"runner": Color("f4d35e"),
	&"shieldbearer": Color("c98f65"),
	&"breacher": Color("c66b5d"),
	&"heavy": Color("b13e53"),
	&"drone": Color("73eff7"),
	&"interceptor": Color("69b9d0"),
	&"spellcaster": Color("c964cf"),
	&"mini_boss": Color("94216a"),
}

static var _damage_flash_shader: Shader = null
static var _missing_static_ids: Dictionary = {}


static func uses_grunt(def_id: StringName) -> bool:
	return def_id == &"grunt"


static func uses_static_sprite(def_id: StringName) -> bool:
	return STATIC_ENEMIES.has(def_id)


static func uses_directional_animation(def_id: StringName) -> bool:
	return uses_grunt(def_id)


static func static_sprite_id(def_id: StringName) -> StringName:
	return StringName("%s%s" % [STATIC_PREFIX, def_id])


static func static_body_px(def_id: StringName, aerial := false) -> float:
	return float(STATIC_BODY_PX.get(def_id, LEGACY_AERIAL_PX if aerial else LEGACY_ENEMY_PX))


static func static_effect_profile(def_id: StringName) -> Dictionary:
	return (STATIC_EFFECT_PROFILES.get(def_id, {}) as Dictionary).duplicate(true)


static func static_effect_duration(def_id: StringName) -> float:
	var profile: Dictionary = STATIC_EFFECT_PROFILES.get(def_id, {})
	return maxf(
		float(profile.get(&"dissolve_seconds", 0.0)),
		float(profile.get(&"particle_lifetime", 0.0)),
	)


static func damage_flash_frames_for(def_id: StringName, fallback_frames: int) -> int:
	var profile: Dictionary = STATIC_EFFECT_PROFILES.get(def_id, {})
	if profile.is_empty():
		return fallback_frames
	return maxi(1, roundi(float(profile.get(&"flash_seconds", 0.10)) * 60.0))


static func direction_from_tangent(tangent: Vector2i) -> StringName:
	if tangent == Vector2i.ZERO:
		return &"se"
	var screen := IsoProjection.project(Vector2(tangent))
	if screen.y < 0.0:
		return &"ne" if screen.x >= 0.0 else &"nw"
	return &"se" if screen.x >= 0.0 else &"sw"


static func direction_for_path(path: Array[Vector2i], progress_units: int) -> StringName:
	if path.size() < 2:
		return &"se"
	var clamped_progress := clampi(progress_units, 0, Pathing.length_units(path) - 1)
	@warning_ignore("integer_division")
	var segment := clamped_progress / Pathing.PROGRESS_SCALE
	segment = mini(segment, path.size() - 2)
	return direction_from_tangent(path[segment + 1] - path[segment])


static func walk_frame(
	animation_seconds: float,
	fps := WALK_FPS,
	frame_count := FRAME_COUNT,
	phase_offset := 0,
) -> int:
	var cycle_frames := maxi(1, frame_count - 1)
	var elapsed_frames := floori(maxf(animation_seconds, 0.0) * fps) + phase_offset
	return posmod(elapsed_frames, cycle_frames)


static func attack_frame(
	atk_counter: int, atk_interval_ticks: int, frame_count := FRAME_COUNT
) -> int:
	if atk_interval_ticks <= 1 or frame_count <= 1:
		return 0
	var last_counter := atk_interval_ticks - 1
	var elapsed := last_counter - clampi(atk_counter, 0, last_counter)
	return roundi(float(elapsed) * float(frame_count - 1) / float(last_counter))


static func timed_attack_frame(
	atk_counter: int,
	atk_interval_ticks: int,
	frame_count: int,
	fps: float,
	ticks_per_second := 30.0,
) -> int:
	if atk_interval_ticks <= 1 or frame_count <= 1 or fps <= 0.0 or ticks_per_second <= 0.0:
		return 0
	var last_counter := atk_interval_ticks - 1
	var elapsed_ticks := last_counter - clampi(atk_counter, 0, last_counter)
	return clampi(floori(float(elapsed_ticks) * fps / ticks_per_second), 0, frame_count - 1)


static func animation_id(state: StringName, direction: StringName) -> StringName:
	return StringName("grunt_anim_%s_%s" % [state, direction])


static func blend_alpha(frames_left: int, total_frames := BLEND_FRAMES) -> Vector2:
	if total_frames <= 0:
		return Vector2(0.0, 1.0)
	var left := clampi(frames_left, 0, total_frames)
	var old_alpha := float(left) / float(total_frames)
	return Vector2(old_alpha, 1.0 - old_alpha)


static func damage_flash_color(
	frames_left: int, total_frames: int, white: Color, red: Color
) -> Color:
	if frames_left <= 0 or total_frames <= 0:
		return Color.WHITE
	return white if frames_left * 2 > total_frames else red


static func apply_damage_flash(
	body: ColorRect,
	frames_left: int,
	total_frames: int,
	white: Color,
	red: Color,
	def_id: StringName = &"",
) -> void:
	var profile: Dictionary = STATIC_EFFECT_PROFILES.get(def_id, {})
	var primary: Color = profile.get(&"flash_primary", white)
	var secondary: Color = profile.get(&"flash_secondary", red)
	var color := damage_flash_color(frames_left, total_frames, primary, secondary)
	for layer_name: String in ["Sprite", "BlendSprite"]:
		var layer := body.get_node_or_null(layer_name) as TextureRect
		if layer != null:
			var shader_material := layer.material as ShaderMaterial
			if shader_material != null:
				shader_material.set_shader_parameter("flash_color", color)
				shader_material.set_shader_parameter(
					"flash_strength", 1.0 if frames_left > 0 else 0.0
				)


static func begin_death_effect(
	body: ColorRect,
	def_id: StringName,
	enemy_id: int,
	reduced_motion: bool,
) -> bool:
	if not uses_static_sprite(def_id) or bool(body.get_meta(&"enemy_death_started", false)):
		return false
	var profile := static_effect_profile(def_id)
	if profile.is_empty():
		return false
	body.set_meta(&"enemy_death_started", true)
	body.set_meta(&"enemy_death_elapsed", 0.0)
	body.set_meta(&"enemy_death_duration", static_effect_duration(def_id))
	body.set_meta(&"enemy_death_def_id", def_id)
	var sprite := body.get_node_or_null("Sprite") as TextureRect
	if sprite != null:
		var material := sprite.material as ShaderMaterial
		if material != null:
			material.set_shader_parameter("dissolve_progress", 0.001)
			material.set_shader_parameter("dissolve_mode", float(profile.get(&"dissolve_mode", 0.0)))
			material.set_shader_parameter("dissolve_seed", float(enemy_id) * 0.173)
			material.set_shader_parameter("dissolve_edge_color", profile.get(&"edge_color", Color("c964cf")))
	var particles := EnemyDeathParticlesType.new() as EnemyDeathParticles
	particles.name = "DeathParticles"
	particles.setup(profile, body.size, enemy_id, reduced_motion)
	body.add_child(particles)
	return true


static func advance_death_effect(body: ColorRect, delta: float) -> bool:
	if not bool(body.get_meta(&"enemy_death_started", false)):
		return true
	var elapsed := float(body.get_meta(&"enemy_death_elapsed", 0.0)) + maxf(delta, 0.0)
	var duration := maxf(float(body.get_meta(&"enemy_death_duration", 0.0)), 0.001)
	body.set_meta(&"enemy_death_elapsed", elapsed)
	var def_id := StringName(body.get_meta(&"enemy_death_def_id", &""))
	var profile: Dictionary = STATIC_EFFECT_PROFILES.get(def_id, {})
	var dissolve_seconds := maxf(float(profile.get(&"dissolve_seconds", duration)), 0.001)
	var dissolve_progress := clampf(elapsed / dissolve_seconds, 0.001, 1.0)
	var sprite := body.get_node_or_null("Sprite") as TextureRect
	if sprite != null:
		var material := sprite.material as ShaderMaterial
		if material != null:
			material.set_shader_parameter("dissolve_progress", dissolve_progress)
	var shadow := body.get_node_or_null("Shadow") as Polygon2D
	if shadow != null:
		shadow.modulate.a = 1.0 - clampf(elapsed / duration, 0.0, 1.0)
	var particles := body.get_node_or_null("DeathParticles") as EnemyDeathParticles
	if particles != null:
		particles.advance(delta)
	return elapsed >= duration


static func death_effect_progress(body: ColorRect) -> float:
	if not bool(body.get_meta(&"enemy_death_started", false)):
		return 0.0
	var duration := maxf(float(body.get_meta(&"enemy_death_duration", 0.0)), 0.001)
	return clampf(float(body.get_meta(&"enemy_death_elapsed", 0.0)) / duration, 0.0, 1.0)


static func _shared_damage_flash_shader() -> Shader:
	if _damage_flash_shader == null:
		_damage_flash_shader = Shader.new()
		_damage_flash_shader.code = DAMAGE_FLASH_SHADER_SOURCE
	return _damage_flash_shader


static func animation_id_for(enemy: EnemyState, battle: BattleModel) -> StringName:
	if uses_static_sprite(enemy.def_id):
		return static_sprite_id(enemy.def_id)
	var direction := direction_for_path(
		battle.path_for(enemy.path_idx), enemy.progress_units
	)
	var state := &"attack" if is_attacking(enemy) else &"walk"
	return animation_id(state, direction)


static func legacy_sprite_id(enemy: EnemyState, definitions: Dictionary) -> StringName:
	var definition: EnemyDef = definitions.get(enemy.def_id)
	var sprite_id := definition.sprite_id if definition != null else enemy.def_id
	return sprite_id


static func make_body(enemy: EnemyState, battle: BattleModel, definitions: Dictionary) -> ColorRect:
	var body := ColorRect.new()
	body.name = "Enemy%d" % enemy.id
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.accessibility_name = UiCopyType.enemy_name(enemy.def_id)
	var animated_grunt := uses_grunt(enemy.def_id)
	var static_enemy := uses_static_sprite(enemy.def_id)
	var sprite_id := (
		animation_id_for(enemy, battle)
		if animated_grunt or static_enemy
		else legacy_sprite_id(enemy, definitions)
	)
	var texture := Art.texture(sprite_id, 0)
	var body_px := static_body_px(enemy.def_id, enemy.aerial)
	body.set_meta(&"enemy_def_id", enemy.def_id)
	body.set_meta(&"enemy_static", static_enemy)
	body.set_meta(&"enemy_texture_missing", texture == null)
	if texture != null:
		body.color = Color.TRANSPARENT
		if animated_grunt:
			body_px = BODY_PX
		elif not static_enemy:
			body_px = float(texture.get_width() * LEGACY_SPRITE_SCALE)
		body.size = Vector2.ONE * body_px
		var sprite := _texture_rect("Sprite", texture, body.size, static_enemy)
		sprite.pivot_offset = (
			body.size * 0.5 if enemy.aerial else Vector2(body.size.x * 0.5, body.size.y)
		)
		body.add_child(sprite)
		if animated_grunt:
			var blend := _texture_rect("BlendSprite", null, body.size, false)
			blend.pivot_offset = Vector2(body.size.x * 0.5, body.size.y)
			blend.visible = false
			body.add_child(blend)
	else:
		body.color = TYPE_COLORS.get(enemy.def_id, FALLBACK_COLOR)
		body.size = Vector2.ONE * body_px
		if static_enemy and not _missing_static_ids.has(enemy.def_id):
			_missing_static_ids[enemy.def_id] = true
			push_error(
				"EnemyAnimator: required core static texture is missing for %s (%s)"
				% [enemy.def_id, sprite_id]
			)
	add_shadow(body, enemy.aerial)
	return body


static func _texture_rect(
	sprite_name: String, sprite_texture: Texture2D, sprite_size: Vector2, smooth := false
) -> TextureRect:
	var sprite := TextureRect.new()
	sprite.name = sprite_name
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sprite.texture = sprite_texture
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = (
		TextureRect.STRETCH_KEEP_ASPECT_CENTERED if smooth else TextureRect.STRETCH_SCALE
	)
	sprite.texture_filter = (
		CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		if smooth
		else CanvasItem.TEXTURE_FILTER_NEAREST
	)
	sprite.size = sprite_size
	var shader_material := ShaderMaterial.new()
	shader_material.shader = _shared_damage_flash_shader()
	sprite.material = shader_material
	return sprite


static func add_shadow(body: ColorRect, aerial: bool) -> void:
	var shadow := Polygon2D.new()
	shadow.name = "Shadow"
	shadow.color = SHADOW_COLOR
	shadow.polygon = IsoProjection.face_polygon(SHADOW_FACE_SCALE)
	shadow.position = Vector2(
		body.size.x * 0.5, body.size.y + (AERIAL_SHADOW_DROP if aerial else 0.0)
	)
	shadow.show_behind_parent = true
	body.add_child(shadow)


static func is_attacking(enemy: EnemyState) -> bool:
	if enemy.atk_counter <= 0:
		return false
	return enemy.blocked_by >= 0 or enemy.atk_range_cells > 0


static func attack_progress(enemy: EnemyState) -> float:
	if not is_attacking(enemy) or enemy.atk_interval_ticks <= 1:
		return 0.0
	return 1.0 - clampf(
		float(enemy.atk_counter) / float(enemy.atk_interval_ticks - 1), 0.0, 1.0
	)


static func static_motion_state(
	def_id: StringName,
	enemy_id: int,
	seconds: float,
	attacking: bool,
	attack_phase: float,
	blocked: bool,
	aerial: bool,
	reduced_motion: bool,
) -> Dictionary:
	var profile: Dictionary = STATIC_MOTION_PROFILES.get(def_id, {})
	var frequency := float(profile.get(&"frequency", 1.0))
	var phase := maxf(seconds, 0.0) * TAU * frequency + float(enemy_id) * 0.731
	var wave := sin(phase)
	var bob := float(profile.get(&"bob", 1.0))
	var roll := float(profile.get(&"roll", 0.0))
	var squash := float(profile.get(&"squash", 0.0))
	var lateral := 0.45 * sin(phase * 0.5 + 0.7) if aerial else 0.0
	if blocked:
		bob *= 0.22
		roll *= 0.22
		lateral *= 0.22
	if reduced_motion:
		bob = minf(1.0, bob * 0.35)
		roll = 0.0
		squash = 0.0
		lateral = 0.0
	var offset := Vector2(lateral, wave * bob)
	var rotation := wave * roll
	var scale := Vector2(1.0 + absf(wave) * squash, 1.0 - absf(wave) * squash)
	var telegraph := 0.0
	if attacking:
		var progress := clampf(attack_phase, 0.0, 1.0)
		var windup := minf(1.0, progress / 0.72)
		var impact := sin(clampf((progress - 0.72) / 0.28, 0.0, 1.0) * PI)
		var lunge := float(profile.get(&"lunge", 2.0))
		if reduced_motion:
			lunge = minf(1.0, lunge)
		offset.x += -windup * lunge * 0.35 + impact * lunge
		offset.y += windup * 0.75
		if not reduced_motion:
			rotation += (windup * -0.025 + impact * 0.045)
			scale *= Vector2(1.0 + windup * 0.025, 1.0 - windup * 0.025)
		telegraph = clampf(windup * 0.55 + impact * 0.45, 0.0, 1.0)
	return {
		&"offset": offset,
		&"rotation": rotation,
		&"scale": scale,
		&"telegraph": telegraph,
	}


static func frame_for(enemy: EnemyState, sprite_id: StringName, seconds: float) -> int:
	if uses_static_sprite(enemy.def_id):
		return 0
	var frame_count := Art.frame_count(sprite_id)
	if String(sprite_id).contains("_attack_"):
		return attack_frame(enemy.atk_counter, enemy.atk_interval_ticks, frame_count)
	var animation_fps := Art.fps(sprite_id)
	if animation_fps <= 0.0:
		animation_fps = WALK_FPS
	return walk_frame(seconds, animation_fps, frame_count, enemy.id)


static func refresh(
	enemy: EnemyState,
	battle: BattleModel,
	body: ColorRect,
	seconds: float,
	keys: Dictionary,
	blend_frames: Dictionary,
	definitions: Dictionary,
) -> void:
	var sprite := body.get_node_or_null("Sprite") as TextureRect
	if uses_static_sprite(enemy.def_id):
		_refresh_static(enemy, battle, body, sprite, seconds)
		return
	if sprite == null:
		var deferred_id := animation_id_for(enemy, battle)
		var deferred_texture := Art.texture(
			deferred_id, frame_for(enemy, deferred_id, seconds)
		)
		if deferred_texture != null:
			_activate_grunt_body(body, deferred_texture, enemy.aerial)
			sprite = body.get_node_or_null("Sprite") as TextureRect
		if sprite == null:
			return
	if not uses_grunt(enemy.def_id):
		var legacy_id := legacy_sprite_id(enemy, definitions)
		var legacy_frame := 0
		if Art.frame_count(legacy_id) > 1:
			@warning_ignore("integer_division")
			legacy_frame = (Engine.get_process_frames() / LEGACY_BOB_FRAMES + enemy.id) % 2
		var legacy_texture := Art.texture(legacy_id, legacy_frame)
		if legacy_texture != null and sprite.texture != legacy_texture:
			sprite.texture = legacy_texture
		return
	var sprite_id := animation_id_for(enemy, battle)
	var texture := Art.texture(sprite_id, frame_for(enemy, sprite_id, seconds))
	if texture == null:
		return
	var old_key: StringName = keys.get(enemy.id, &"")
	if old_key != sprite_id:
		var blend := body.get_node_or_null("BlendSprite") as TextureRect
		if old_key != &"" and blend != null and sprite.texture != null:
			blend.texture = sprite.texture
			blend.visible = true
			blend_frames[enemy.id] = BLEND_FRAMES
			apply_blend(body, BLEND_FRAMES)
		keys[enemy.id] = sprite_id
	if sprite.texture != texture:
		sprite.texture = texture


static func _refresh_static(
	enemy: EnemyState,
	battle: BattleModel,
	body: ColorRect,
	sprite: TextureRect,
	seconds: float,
) -> void:
	if sprite == null:
		var texture := Art.texture(static_sprite_id(enemy.def_id), 0)
		if texture == null:
			return
		body.color = Color.TRANSPARENT
		sprite = _texture_rect("Sprite", texture, body.size, true)
		sprite.pivot_offset = (
			body.size * 0.5 if enemy.aerial else Vector2(body.size.x * 0.5, body.size.y)
		)
		body.add_child(sprite)
		body.set_meta(&"enemy_texture_missing", false)
	var direction := direction_for_path(
		battle.path_for(enemy.path_idx),
		enemy.progress_units,
	)
	var reduced_motion := bool(ProjectSettings.get_setting("accessibility/reduced_motion", false))
	var motion := static_motion_state(
		enemy.def_id,
		enemy.id,
		seconds,
		is_attacking(enemy),
		attack_progress(enemy),
		enemy.blocked_by >= 0,
		enemy.aerial,
		reduced_motion,
	)
	var scale: Vector2 = motion[&"scale"]
	if direction in [&"nw", &"sw"]:
		scale.x *= -1.0
	sprite.position = motion[&"offset"]
	sprite.rotation = float(motion[&"rotation"])
	sprite.scale = scale
	sprite.modulate = Color.WHITE


static func _activate_grunt_body(body: ColorRect, texture: Texture2D, aerial: bool) -> void:
	body.color = Color.TRANSPARENT
	body.size = Vector2.ONE * BODY_PX
	var sprite := _texture_rect("Sprite", texture, body.size, false)
	sprite.pivot_offset = Vector2(body.size.x * 0.5, body.size.y)
	body.add_child(sprite)
	var blend := _texture_rect("BlendSprite", null, body.size, false)
	blend.pivot_offset = Vector2(body.size.x * 0.5, body.size.y)
	blend.visible = false
	body.add_child(blend)
	var shadow := body.get_node_or_null("Shadow") as Polygon2D
	if shadow != null:
		shadow.position = Vector2(
			body.size.x * 0.5, body.size.y + (AERIAL_SHADOW_DROP if aerial else 0.0)
		)
	# BattleView owns health-bar geometry and refreshes it immediately after
	# animation-body changes.


static func apply_blend(body: ColorRect, frames_left: int) -> void:
	var sprite := body.get_node_or_null("Sprite") as TextureRect
	var blend := body.get_node_or_null("BlendSprite") as TextureRect
	if sprite == null or blend == null:
		return
	var alpha := blend_alpha(frames_left)
	blend.modulate = Color(blend.modulate.r, blend.modulate.g, blend.modulate.b, alpha.x)
	sprite.modulate = Color(sprite.modulate.r, sprite.modulate.g, sprite.modulate.b, alpha.y)
	if frames_left <= 0:
		blend.visible = false
		blend.texture = null
