extends SceneTree

var failures: Array[String] = []
var checks := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func _initialize() -> void:
	call_deferred("run")

func finish() -> void:
	for failure: String in failures:
		push_error(failure)
	print("PLAYER_NAME_UNICODE ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)

func clean(path: String) -> void:
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))

const Service := preload("res://autoloads/leaderboard.gd")

func run() -> void:
	var path := "user://unicode_names_%d.json" % Time.get_ticks_usec()
	var service := Service.new()
	service.save_path = path
	root.add_child(service)
	for value: String in ["张伟", "李娜", "王昊", "王𠮷", "昊"]:
		check(service.set_player_name(value) == value, "accept " + value)
		var entry: Dictionary = service.record_mission({"stage_id": &"s1", "result": BattleModel.Result.CLEAR, "stars": 1, "kills": 1, "leaks": 0})
		check(entry.name == value, "record " + value)
		var restored := Service.new()
		restored.save_path = path
		root.add_child(restored)
		check(restored.player_name() == value, "persist " + value)
		var wire: Dictionary = JSON.parse_string(JSON.stringify(entry))
		service._on_request_completed(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify({"entries": [wire], "entry": wire}).to_utf8_buffer())
		check(service.entries.size() == 1 and service.entries[0].name == value, "retrieved row " + value)
		restored.free()
	check(Service.normalize_player_name("  commander!! jun---7  ") == "COMMANDER JUN-7", "legacy ASCII normalization")
	check(Service.normalize_player_name("王".repeat(15) + "𠮷伟") == "王".repeat(15) + "𠮷", "codepoint truncation")
	check(Service.normalize_player_name("Juń") == "JUŃ", "attached combining mark")
	check(Service.normalize_player_name("\u0301张\u200b伟<>") == "张伟", "drop orphan marks controls and markup")
	service.free()
	await process_frame
	clean(path)
	finish()
