extends SceneTree

const FilterType := preload("res://scripts/ui/components/roster_filter.gd")

var _failures: Array[String] = []


func _init() -> void:
	_test_default_active_filter()
	_test_fallen_and_faction_filters()
	_test_faction_derivation()
	if _failures.is_empty():
		print("FACTION_ROSTER_FILTER_TEST_OK")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)


func _test_default_active_filter() -> void:
	var rows := _fixture_rows()
	var active := FilterType.filter_rows(rows)
	_check(active.size() == 2, "default filter did not return exactly the active soldiers")
	for row: Dictionary in active:
		_check(not bool(row["fallen"]), "default active filter exposed a fallen soldier")
	_check(FilterType.count(rows, FilterType.STATUS_ACTIVE) == 2, "active count mismatch")
	_check(FilterType.count(rows, FilterType.STATUS_FALLEN) == 2, "fallen count mismatch")
	var all_operators := FilterType.filter_rows(rows, FilterType.STATUS_ALL)
	_check(all_operators.size() == 4, "all status did not include active and fallen operators")
	_check(FilterType.count(rows, FilterType.STATUS_ALL) == 4, "all status count mismatch")


func _test_fallen_and_faction_filters() -> void:
	var rows := _fixture_rows()
	var fallen := FilterType.filter_rows(rows, FilterType.STATUS_FALLEN)
	_check(fallen.size() == 2, "fallen tab did not return exactly terminally dead soldiers")
	for row: Dictionary in fallen:
		_check(bool(row["fallen"]), "fallen tab exposed a ready soldier")
	var vesper := FilterType.filter_rows(
		rows, FilterType.STATUS_FALLEN, &"vesper_circuit",
	)
	_check(vesper.size() == 1, "Vesper fallen symbol filter count mismatch")
	_check(String(vesper[0]["hero_id"]) == "vesper_dead", "Vesper filter returned wrong soldier")
	var crimson := FilterType.filter_rows(
		rows, FilterType.STATUS_ACTIVE, &"crimson_aegis",
	)
	_check(crimson.size() == 1, "Crimson active symbol filter count mismatch")


func _test_faction_derivation() -> void:
	_check(
		FilterType.faction_id({"source_id": "solcrest_contract_1"}) == &"solcrest_accord",
		"Solcrest source prefix did not derive canonical faction",
	)
	_check(
		FilterType.faction_id({"faction_id": &"vesper_circuit"}) == &"vesper_circuit",
		"explicit canonical faction projection did not win",
	)
	_check(
		FilterType.faction_id({"faction_id": &"unknown"}) == &"lunaris_reliquary",
		"unknown faction did not fall back safely to current campaign identity",
	)


func _fixture_rows() -> Array[Dictionary]:
	return [
		{
			"hero_id": "lunaris_ready",
			"life_status": "ready",
			"death": null,
			"faction_id": &"lunaris_reliquary",
			"can_promote": true,
		},
		{
			"hero_id": "crimson_ready",
			"life_status": "ready",
			"death": null,
			"faction_id": &"crimson_aegis",
			"can_promote": false,
		},
		{
			"hero_id": "vesper_dead",
			"life_status": "dead",
			"death": {"stage_id": "s3"},
			"faction_id": &"vesper_circuit",
			"can_promote": true,
		},
		{
			"hero_id": "solcrest_dead",
			"life_status": "dead",
			"death": {"stage_id": "s5"},
			"source_id": "solcrest_contract_1",
		},
	]


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
