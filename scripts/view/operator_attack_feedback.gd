extends Node2D
## Presentation-only attack feedback. Model state and combat timing are read-only.
const VisualCatalog := preload("res://data/presentation/operator_visual_catalog.gd")
const Animator := preload("res://scripts/view/operator_animator.gd")
const MAX_BURSTS := 32
const PROFILES := {
	&"gunner_female": {"cue": &"attack_gunner_female", "kind": &"carbine", "color": Color("ffbd5b"), "life": 0.24},
	&"gunner_male": {"cue": &"attack_gunner_male", "kind": &"rifle", "color": Color("bce8ff"), "life": 0.32},
	&"swordmaster_female": {"cue": &"attack_swordmaster_female", "kind": &"twin", "color": Color("ff869d"), "life": 0.30},
	&"swordmaster_male": {"cue": &"attack_swordmaster_male", "kind": &"saber", "color": Color("8de1ce"), "life": 0.36},
	&"mage_apprentice_female": {"cue": &"attack_mage_apprentice_female", "kind": &"ember", "color": Color("ffae58"), "life": 0.44},
	&"mage_apprentice_male": {"cue": &"attack_mage_apprentice_male", "kind": &"frost", "color": Color("80e5ff"), "life": 0.48},
}
var _view_ref: WeakRef
var _seen: Dictionary = {}
var _bursts: Array[Dictionary] = []
var _trigger_count := 0
var _culled_count := 0

func configure(view: Node2D) -> void:
	_view_ref = weakref(view)
	name = "OperatorAttackFeedback"
	z_index = 63 # Above world, below all UI/HUD; never captures input.
	var cues: Array[StringName] = []
	for profile: Dictionary in PROFILES.values():
		cues.append(profile["cue"])
	get_node("/root/Sfx").prepare_cues(cues)

func _view() -> Node2D:
	return _view_ref.get_ref() as Node2D if _view_ref != null else null

static func profile_for_unit(unit: UnitState) -> StringName:
	var identity := VisualCatalog.template_for_unit(unit.op_id, unit.portrait_asset_id, unit.hero_id, unit.id, unit.class_id)
	return identity if PROFILES.has(identity) else &""

func _active(view: Node2D, model: BattleModel) -> bool:
	return model != null and model.result == BattleModel.Result.RUNNING and float(view.get("ticks_per_frame_scale")) > 0.0 and not bool(view.call("battle_confirmation_active")) and not bool(view.call("_tutorial_holding_battle"))

func sync_attacks(model: BattleModel) -> void:
	var view := _view()
	if view == null or model == null:
		return
	var active := _active(view, model)
	var live: Dictionary = {}
	for unit: UnitState in model.units:
		if not unit.alive:
			continue
		live[unit.id] = true
		var tick := unit.last_attack_tick
		if tick < 0 or tick == int(_seen.get(unit.id, -1)):
			continue
		_seen[unit.id] = tick # Consume even culled/paused events; never replay later.
		var identity := profile_for_unit(unit)
		if not active or identity.is_empty() or model.tick - tick > maxi(2, int(model.config.ticks_per_second / 5)):
			continue
		var origin := _source_point(view, unit)
		var target := _target_point(view, unit)
		var source_visible := _visible(origin)
		var target_visible := _visible(target)
		if not source_visible and not target_visible:
			_culled_count += 1
			continue
		var profile: Dictionary = PROFILES[identity]
		var direction := IsoProjection.project(Vector2(unit.last_attack_cell - unit.cell)).normalized()
		if direction.length_squared() < 0.01:
			var axes := [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]
			direction = IsoProjection.project(axes[posmod(unit.facing, 4)]).normalized()
		var body_scale := float(get_node("/root/TweakControls").value(&"player.visual_scale", 1.0))
		if _bursts.size() >= MAX_BURSTS:
			_bursts.pop_front()
		_bursts.append({"unit_id": unit.id, "identity": identity, "source": origin, "target": target, "direction": direction, "age": 0.0, "life": float(profile["life"]), "body_scale": body_scale, "source_visible": source_visible, "target_visible": target_visible})
		_trigger_count += 1
		# UI/global cues stay in the existing nonspatial API. World attacks are
		# camera-culled before dedupe/voice allocation and retain live anchors.
		if source_visible:
			get_node("/root/Sfx").play_world(String(profile["cue"]), self, origin)
	for id: Variant in _seen.keys():
		if not live.has(id):
			_seen.erase(id)
	if not active:
		clear_transients()
	queue_redraw()

func _source_point(view: Node2D, unit: UnitState) -> Vector2:
	var nodes: Dictionary = view.get("_unit_nodes")
	var node := nodes.get(unit.id) as Node2D
	if node != null:
		var animation := VisualCatalog.get_animation(profile_for_unit(unit))
		var foot := Animator.ground_offset(animation)
		var body_height := float(animation.display_height_px) * float(get_node("/root/TweakControls").value(&"player.visual_scale", 1.0))
		return node.position + Vector2(0, foot - body_height * 0.57)
	return IsoProjection.face_center(unit.cell) + Vector2(0, -31)

func _target_point(view: Node2D, unit: UnitState) -> Vector2:
	var stage := view.get("_stage") as StageDef
	var target := IsoProjection.face_center(unit.last_attack_cell, stage.is_elevated_platform(unit.last_attack_cell))
	var enemy_rects: Dictionary = view.get("_enemy_rects")
	var model := view.get("model") as BattleModel
	for enemy: EnemyState in model.enemies:
		if not enemy.alive and enemy.died_at_tick != unit.last_attack_tick:
			continue
		if Pathing.cell_of(model.path_for(enemy.path_idx), enemy.progress_units) != unit.last_attack_cell:
			continue
		var target_body := enemy_rects.get(enemy.id) as Control
		if target_body != null:
			return target_body.position + Vector2(target_body.size.x * 0.5, target_body.size.y * 0.60)
	return target + Vector2(0, -16)

func _visible(local_point: Vector2) -> bool:
	return get_viewport_rect().has_point(to_global(local_point))

func world_audio_visible(local_point: Vector2) -> bool:
	var view := _view()
	return view != null and _active(view, view.get("model") as BattleModel) and _visible(local_point)

func _process(delta: float) -> void:
	var view := _view()
	if view == null:
		return
	var model := view.get("model") as BattleModel
	if not _active(view, model):
		clear_transients()
		return
	if _bursts.is_empty():
		return
	for index: int in range(_bursts.size() - 1, -1, -1):
		var burst := _bursts[index]
		burst["age"] = float(burst["age"]) + delta
		burst["source_visible"] = _visible(burst["source"])
		burst["target_visible"] = _visible(burst["target"])
		var unit := model.unit_by_id(int(burst["unit_id"]))
		if float(burst["age"]) >= float(burst["life"]) or (not burst["source_visible"] and not burst["target_visible"]) or unit == null or not unit.alive:
			_bursts.remove_at(index)
	queue_redraw()

func clear_transients() -> void:
	if not _bursts.is_empty():
		_bursts.clear()
		queue_redraw()
	get_node("/root/Sfx").stop_world_owner(self)

func _exit_tree() -> void:
	get_node("/root/Sfx").stop_world_owner(self)
	_bursts.clear()
	_seen.clear()

func _draw() -> void:
	var reduced := bool(ProjectSettings.get_setting("accessibility/reduced_motion", false))
	var opacity := float(get_node("/root/TweakControls").value(&"environment.vfx_opacity", 1.0))
	for burst: Dictionary in _bursts:
		var profile: Dictionary = PROFILES[burst["identity"]]
		var t := clampf(float(burst["age"]) / float(burst["life"]), 0.0, 1.0)
		var color: Color = profile["color"]
		color.a = (1.0 - t) * opacity
		var source: Vector2 = burst["source"]
		var target: Vector2 = burst["target"]
		var direction: Vector2 = burst["direction"]
		var scale_factor := float(burst["body_scale"])
		var origin := source + direction * 21.0 * scale_factor
		var kind: StringName = profile["kind"]
		if bool(burst["source_visible"]):
			if reduced:
				draw_circle(origin, 3.0 * scale_factor, color)
			elif kind in [&"carbine", &"rifle"]:
				_draw_gun(origin, target, direction, t, color, kind == &"rifle", scale_factor)
			elif kind in [&"twin", &"saber"]:
				_draw_blade(source, direction, t, color, kind == &"twin", scale_factor)
			else:
				_draw_magic(origin, target, direction, t, color, kind == &"frost", scale_factor)
		if bool(burst["target_visible"]) and t < 0.7:
			_draw_impact(target, t, color, kind, scale_factor, reduced)

func _draw_gun(origin: Vector2, target: Vector2, direction: Vector2, t: float, color: Color, rifle: bool, s: float) -> void:
	var flash := (1.0 - t) * (6.5 if rifle else 4.5) * s
	if t < 0.38:
		draw_line(origin, origin + direction * flash * 1.7, Color(1, 0.97, 0.82, color.a), 2.5 * s, true)
		for ray: int in 6:
			var angle := direction.angle() + TAU * float(ray) / 6.0
			draw_line(origin, origin + Vector2.from_angle(angle) * flash, color, 1.3 * s, true)
		var end := origin.lerp(target, 0.8)
		draw_line(origin, end, Color(color, color.a * 0.45), (1.4 if rifle else 0.85) * s, true)
	if rifle:
		draw_arc(origin - direction * 2, (3 + t * 12) * s, 0, TAU, 20, Color(color, color.a * 0.45), 1.0 * s, true)
	for index: int in (5 if rifle else 8):
		var angle := direction.angle() + float(index - 3) * 0.22
		var pos := origin + Vector2.from_angle(angle) * (5 + t * (15 + index * 2)) * s + Vector2(0, t * t * 12 * s)
		draw_circle(pos, (1.3 if rifle else 0.9) * s, Color(color, color.a * 0.8))
	var casing := origin - direction * 12 * s + direction.orthogonal() * (4 + t * 13) * s + Vector2(0, t * t * 22 * s)
	draw_line(casing, casing + Vector2(2, -1) * s, Color(0.9, 0.7, 0.36, color.a), 1.5 * s, true)

func _draw_blade(origin: Vector2, direction: Vector2, t: float, color: Color, twin: bool, s: float) -> void:
	var center_angle := direction.angle()
	var radius := (25.0 if twin else 32.0) * s
	var sweep := center_angle - 0.9 + t * 1.8
	for blade: int in (2 if twin else 1):
		var r := radius - float(blade) * 7.0 * s
		draw_arc(origin, r, sweep - 0.75, sweep + 0.35, 18, Color(color, color.a * 0.42), 4.0 * s, true)
		draw_arc(origin, r, sweep - 0.6, sweep + 0.3, 18, Color(0.94, 0.99, 1, color.a), 1.25 * s, true)
	for index: int in 7:
		var angle := center_angle - 0.8 + float(index) * 0.26
		var pos := origin + Vector2.from_angle(angle) * (radius + t * 15 * s)
		draw_line(pos, pos + Vector2.from_angle(angle) * (3 if twin else 5) * s, color, 1.1 * s, true)

func _draw_magic(origin: Vector2, target: Vector2, direction: Vector2, t: float, color: Color, frost: bool, s: float) -> void:
	draw_arc(origin, (3 + t * 10) * s, 0, TAU, 22, Color(color, color.a * 0.8), 1.3 * s, true)
	var travel := origin.lerp(target, minf(t * 2.8, 1.0))
	if t < 0.5:
		draw_line(origin, travel, Color(color, color.a * 0.32), (1.0 if frost else 2.0) * s, true)
	for index: int in 9:
		var angle := float(index) * 2.39996
		var center := travel if index < 3 else origin + direction * t * 18 * s
		var pos := center + Vector2.from_angle(angle) * (3 + t * (10 + index)) * s
		if frost:
			var r := (2.1 - t) * s
			draw_colored_polygon(PackedVector2Array([pos + Vector2(0, -r), pos + Vector2(r * 0.6, 0), pos + Vector2(0, r), pos + Vector2(-r * 0.6, 0)]), color)
		else:
			draw_circle(pos + Vector2(0, -t * 9 * s), (2.0 - t) * s, color)
			draw_circle(pos, 0.7 * s, Color(1, 0.96, 0.66, color.a))

func _draw_impact(target: Vector2, t: float, color: Color, kind: StringName, s: float, reduced: bool) -> void:
	if reduced:
		draw_circle(target, 2 * s, color)
		return
	var radius := (2 + t * 13) * s
	for index: int in (4 if kind in [&"carbine", &"rifle"] else 6):
		var direction := Vector2.from_angle(float(index) * TAU / 6.0 + 0.3)
		draw_line(target + direction * radius, target + direction * (radius + 3 * s), color, 1.1 * s, true)

func active_burst_count() -> int:
	return _bursts.size()

func trigger_count() -> int:
	return _trigger_count

func culled_count() -> int:
	return _culled_count

func bursts_for_test() -> Array[Dictionary]:
	return _bursts.duplicate(true)
