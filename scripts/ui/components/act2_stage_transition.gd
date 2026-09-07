class_name Act2StageTransition
extends CanvasLayer

signal entry_finished
signal exit_finished

const SEAL_TEXTURE := preload("res://assets/template/world/act2/restoration_lattice_seal.webp")
const CYAN := Color("88e8e4")
const GOLD := Color("d6b96c")
const INK := Color("070b16")
const ENTRY_HOLD_SECONDS := 0.48
const ENTRY_REVEAL_SECONDS := 0.28
const ENTRY_EXIT_SECONDS := 0.62
const EXIT_SECONDS := 0.42

var _root: Control = null
var _veil: ColorRect = null
var _content: VBoxContainer = null
var _tween: Tween = null
var _generation := 0


func _ready() -> void:
	layer = 120


func play_entry(stage_index: int, stage_title: String, reduced_motion: bool) -> void:
	_generation += 1
	var generation := _generation
	_build(stage_index, stage_title, true)
	if reduced_motion:
		_veil.color.a = 0.76
		_content.modulate = Color.WHITE
		await get_tree().create_timer(0.18, true, false, true).timeout
		if generation == _generation:
			_finish_entry()
		return
	_content.modulate = Color.WHITE
	_content.pivot_offset = _content.custom_minimum_size * 0.5
	_content.scale = Vector2(0.97, 0.97)
	_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_content, "scale", Vector2.ONE, ENTRY_REVEAL_SECONDS)
	_tween.tween_interval(ENTRY_HOLD_SECONDS)
	_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(_veil, "color", Color(INK, 0.0), ENTRY_EXIT_SECONDS)
	_tween.parallel().tween_property(_content, "scale", Vector2(1.015, 1.015), ENTRY_EXIT_SECONDS)
	_tween.tween_callback(func() -> void:
		if generation == _generation:
			_finish_entry()
	)


func play_exit(stage_index: int, stage_title: String, reduced_motion: bool) -> void:
	_generation += 1
	var generation := _generation
	_build(stage_index, stage_title, false)
	_content.modulate = Color.WHITE
	_veil.color = Color(INK, 0.0)
	if reduced_motion:
		_veil.color.a = 1.0
		_finish_exit()
		return
	_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(_veil, "color", Color(INK, 1.0), EXIT_SECONDS)
	_content.pivot_offset = _content.custom_minimum_size * 0.5
	_tween.parallel().tween_property(_content, "scale", Vector2(0.98, 0.98), EXIT_SECONDS)
	_tween.tween_callback(func() -> void:
		if generation == _generation:
			_finish_exit()
	)


func cancel() -> void:
	_generation += 1
	if _tween != null and is_instance_valid(_tween):
		_tween.kill()
	_tween = null
	queue_free()


func transition_duration(entry: bool, reduced_motion: bool) -> float:
	if reduced_motion:
		return 0.18 if entry else 0.0
	return (
		ENTRY_REVEAL_SECONDS + ENTRY_HOLD_SECONDS + ENTRY_EXIT_SECONDS
		if entry
		else EXIT_SECONDS
	)


func _build(stage_index: int, stage_title: String, entry: bool) -> void:
	if _tween != null and is_instance_valid(_tween):
		_tween.kill()
	for child: Node in get_children():
		child.queue_free()
	_root = Control.new()
	_root.name = "ActIITransitionRoot"
	_root.position = Vector2.ZERO
	_root.size = get_viewport().get_visible_rect().size
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_veil = ColorRect.new()
	_veil.name = "TransitionVeil"
	_veil.color = Color(INK, 0.94 if entry else 1.0)
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_veil)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	_content = VBoxContainer.new()
	_content.name = "ActIITransitionContent"
	_content.alignment = BoxContainer.ALIGNMENT_CENTER
	_content.add_theme_constant_override(&"separation", 14)
	_content.custom_minimum_size = Vector2(460.0, 330.0)
	center.add_child(_content)
	var seal := TextureRect.new()
	seal.name = "RestorationSeal"
	seal.texture = SEAL_TEXTURE
	seal.custom_minimum_size = Vector2(176.0, 164.0)
	seal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	seal.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	seal.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	seal.modulate = Color(CYAN, 0.88)
	seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(seal)
	var act_label := _label("ACT II  //  OPERATION %02d" % stage_index, 24, GOLD)
	act_label.name = "ActLabel"
	_content.add_child(act_label)
	var rule := ColorRect.new()
	rule.name = "TransitionRule"
	rule.color = Color(CYAN, 0.72)
	rule.custom_minimum_size = Vector2(320.0, 2.0)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(rule)
	var title := _label(stage_title.to_upper(), 48, Color.WHITE)
	title.name = "StageTitle"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size = Vector2(460.0, 62.0)
	_content.add_child(title)


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", color)
	label.add_theme_color_override(&"font_shadow_color", Color(0.0, 0.0, 0.0, 0.75))
	label.add_theme_constant_override(&"shadow_offset_x", 2)
	label.add_theme_constant_override(&"shadow_offset_y", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _finish_entry() -> void:
	entry_finished.emit()
	queue_free()


func _finish_exit() -> void:
	exit_finished.emit()
