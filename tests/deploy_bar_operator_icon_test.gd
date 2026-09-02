extends SceneTree

const OperatorVisualCatalogType := preload(
	"res://data/presentation/operator_visual_catalog.gd"
)

const FIXED_EXPECTED := {
	&"recruit": &"op_anim_recruit_female_idle_nw",
	&"sniper_1": &"op_anim_sniper_1_idle_nw",
	&"guard_1": &"op_anim_guard_1_idle_nw",
	&"caster_1": &"op_anim_caster_1_idle_nw",
}

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	await process_frame
	var game := root.get_node_or_null("Game")
	_check(game != null, "Game autoload is missing")
	if game == null:
		_finish()
		return
	game.call("set_run_seed", 3302)
	_check(bool(game.call("start_campaign", false, true)), "battle icon fixture failed")
	game.call("start_battle", &"s1", true)
	for _frame: int in range(12):
		await process_frame
	var battle := game.get("content") as Node
	_check(
		battle != null and bool(battle.get("startup_succeeded")),
		"battle icon fixture did not start",
	)
	if battle != null:
		for operator_id: StringName in FIXED_EXPECTED:
			var slot := battle.find_child("Slot_%s" % operator_id, true, false) as Button
			var definition := load(
				"res://data/operators/%s.tres" % operator_id,
			) as OperatorDef
			var expected_art_id: StringName = FIXED_EXPECTED[operator_id]
			_check(slot != null, "%s deploy card is missing" % operator_id)
			if slot == null or definition == null:
				continue
			_check(
				slot.icon == Art.texture(expected_art_id, 0),
				"%s deploy card does not show actual idle frame 0" % operator_id,
			)
			_check(
				slot.icon != Art.texture(definition.sprite_id, 0),
				"%s deploy card still shows the legacy placeholder" % operator_id,
			)
			_check(
				slot.size.x >= 288.0,
				"%s deploy card can squeeze its preview behind the label" % operator_id,
			)
			_check(
				slot.get_theme_color(&"icon_disabled_color").a >= 0.75,
				"%s disabled preview is too faint to identify" % operator_id,
			)
			if operator_id == &"caster_1":
				_check(
					slot.text.begins_with("Mage\n")
					and not slot.text.contains("Apprentice"),
					"caster deploy card is not labeled Mage",
				)

	for operator_id: StringName in FIXED_EXPECTED:
		_check_slot_art(
			operator_id,
			&"",
			&"",
			0,
			&"",
			FIXED_EXPECTED[operator_id],
		)

	_check_slot_art(
		&"sniper_1",
		&"portrait_recruit_00",
		&"hero-female",
		0,
		&"gunner",
		&"op_anim_gunner_female_idle_nw",
	)
	_check_slot_art(
		&"sniper_1",
		&"portrait_recruit_01",
		&"hero-male",
		1,
		&"gunner",
		&"op_anim_gunner_male_idle_nw",
	)
	_cleanup(game, battle)
	_finish()


func _check_slot_art(
	operator_id: StringName,
	portrait_asset_id: StringName,
	hero_id: StringName,
	unit_id: int,
	class_id: StringName,
	expected_art_id: StringName,
) -> void:
	var actual := OperatorVisualCatalogType.first_idle_art_id_for_unit(
		operator_id,
		portrait_asset_id,
		hero_id,
		unit_id,
		class_id,
	)
	_check(
		actual == expected_art_id,
		"%s card resolved %s instead of %s" % [operator_id, actual, expected_art_id],
	)
	_check(Art.texture(actual, 0) != null, "%s frame 0 did not load" % actual)
	_check(
		not bool(Art.metadata(actual).get(&"placeholder", true)),
		"%s card still resolves placeholder art" % operator_id,
	)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _cleanup(game: Node, battle: Node) -> void:
	game.set("content", null)
	if battle != null and is_instance_valid(battle):
		var parent := battle.get_parent()
		if parent != null:
			parent.remove_child(battle)
		battle.free()
	game.call("_reset_campaign_runtime")
	var music := root.get_node_or_null("Music")
	if music != null:
		music.call("stop")
	var sfx := root.get_node_or_null("Sfx")
	if sfx != null and sfx.has_method("stop_all"):
		sfx.call("stop_all")


func _finish() -> void:
	if _failures.is_empty():
		print("DEPLOY_BAR_OPERATOR_ICON_TEST_OK")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)
