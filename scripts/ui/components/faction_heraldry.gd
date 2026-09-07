class_name FactionHeraldry
extends RefCounted

const ORDER: Array[StringName] = [
	&"solcrest_accord",
	&"vesper_circuit",
	&"lunaris_reliquary",
	&"crimson_aegis",
]
const ACTIVE_FACTION: StringName = &"lunaris_reliquary"

const SYMBOLS := {
	&"solcrest_accord": preload("res://assets/template/ui/factions/solcrest_accord_symbol.webp"),
	&"vesper_circuit": preload("res://assets/template/ui/factions/vesper_circuit_symbol.webp"),
	&"lunaris_reliquary": preload("res://assets/template/ui/factions/lunaris_reliquary_symbol.png"),
	&"crimson_aegis": preload("res://assets/template/ui/factions/crimson_aegis_symbol.webp"),
}
const BANNERS := {
	&"solcrest_accord": preload("res://assets/template/ui/factions/solcrest_accord_banner.webp"),
	&"vesper_circuit": preload("res://assets/template/ui/factions/vesper_circuit_banner.webp"),
	&"lunaris_reliquary": preload("res://assets/template/ui/factions/lunaris_reliquary_banner.webp"),
	&"crimson_aegis": preload("res://assets/template/ui/factions/crimson_aegis_banner.webp"),
}
const NAMES := {
	&"solcrest_accord": "SOLCREST ACCORD",
	&"vesper_circuit": "VESPER CIRCUIT",
	&"lunaris_reliquary": "LUNARIS RELIQUARY",
	&"crimson_aegis": "CRIMSON AEGIS",
}
const SHORT_NAMES := {
	&"solcrest_accord": "SOLCREST",
	&"vesper_circuit": "VESPER",
	&"lunaris_reliquary": "LUNARIS",
	&"crimson_aegis": "CRIMSON",
}
const SUBTITLES := {
	&"solcrest_accord": "CIVIL DEFENSE COMMAND",
	&"vesper_circuit": "FREE SIGNAL NETWORK",
	&"lunaris_reliquary": "SOUL RECOVERY ORDER",
	&"crimson_aegis": "FARM-BREAKER COLUMN",
}
const SPECIALIZATIONS := {
	&"solcrest_accord": (
		"Shield formations, civilian corridors, interception, and coordinated counterattacks."
	),
	&"vesper_circuit": (
		"Stealth deployment, decoys, signal breaks, rerouting, traps, and precision strikes."
	),
	&"lunaris_reliquary": (
		"Soul recovery, gravity control, protective geometry, elite casters, and duelists."
	),
	&"crimson_aegis": (
		"Mobile assaults, displacement, armor breaks, demolition, and forward deployment."
	),
}
const ACCENTS := {
	&"solcrest_accord": Color("d8b978"),
	&"vesper_circuit": Color("5dd6e8"),
	&"lunaris_reliquary": Color("86cbd4"),
	&"crimson_aegis": Color("d9584d"),
}


class FactionSymbolLocaleBinding:
	extends Node

	var mark: TextureRect = null
	var faction_id: StringName = &""
	var i18n: Node = null

	func configure(target: TextureRect, target_faction_id: StringName) -> void:
		mark = target
		faction_id = target_faction_id

	func _ready() -> void:
		i18n = get_node_or_null("/root/I18n")
		if i18n != null and not i18n.is_connected("locale_changed", _on_locale_changed):
			i18n.connect("locale_changed", _on_locale_changed)

	func _exit_tree() -> void:
		if is_instance_valid(i18n) and i18n.is_connected("locale_changed", _on_locale_changed):
			i18n.disconnect("locale_changed", _on_locale_changed)

	func _on_locale_changed(_locale_id: StringName) -> void:
		if is_instance_valid(mark):
			FactionHeraldry._refresh_symbol_tooltip(mark, faction_id)

static func symbol(faction_id: StringName) -> Texture2D:
	return SYMBOLS.get(faction_id, SYMBOLS[ACTIVE_FACTION]) as Texture2D


static func banner(faction_id: StringName) -> Texture2D:
	return BANNERS.get(faction_id, BANNERS[ACTIVE_FACTION]) as Texture2D


static func display_name(faction_id: StringName) -> String:
	var resolved := _resolved_id(faction_id)
	return _text(_key(resolved, &"name"), String(NAMES[resolved]))


static func short_name(faction_id: StringName) -> String:
	var resolved := _resolved_id(faction_id)
	return _text(_key(resolved, &"short_name"), String(SHORT_NAMES[resolved]))


static func subtitle(faction_id: StringName) -> String:
	var resolved := _resolved_id(faction_id)
	return _text(_key(resolved, &"subtitle"), String(SUBTITLES[resolved]))


static func specialization(faction_id: StringName) -> String:
	var resolved := _resolved_id(faction_id)
	return _text(_key(resolved, &"specialization"), String(SPECIALIZATIONS[resolved]))


static func company_name() -> String:
	return _text(&"data.company.33.name", "COMPANY MANUS")


static func accent(faction_id: StringName) -> Color:
	return ACCENTS.get(faction_id, ACCENTS[ACTIVE_FACTION]) as Color


static func make_symbol(faction_id: StringName, edge: float = 44.0) -> TextureRect:
	var mark := TextureRect.new()
	mark.name = "%sSymbol" % String(faction_id).to_pascal_case()
	mark.texture = symbol(faction_id)
	mark.custom_minimum_size = Vector2(edge, edge)
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_refresh_symbol_tooltip(mark, faction_id)
	var binding := FactionSymbolLocaleBinding.new()
	binding.configure(mark, faction_id)
	mark.add_child(binding)
	return mark


static func _i18n() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("I18n") if tree != null else null


static func _text(key: StringName, fallback: String) -> String:
	var i18n := _i18n()
	return String(i18n.call("t", key, fallback)) if i18n != null else fallback


static func _resolved_id(faction_id: StringName) -> StringName:
	return faction_id if NAMES.has(faction_id) else ACTIVE_FACTION


static func _key(faction_id: StringName, field: StringName) -> StringName:
	return StringName("data.faction.%s.%s" % [faction_id, field])


static func _refresh_symbol_tooltip(mark: TextureRect, faction_id: StringName) -> void:
	var copy := "%s — %s" % [display_name(faction_id), specialization(faction_id)]
	mark.tooltip_text = copy
	mark.accessibility_name = display_name(faction_id)
	mark.accessibility_description = specialization(faction_id)
