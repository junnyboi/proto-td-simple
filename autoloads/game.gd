extends Node

## Scene flow and crash-safe campaign state management.

const TITLE_SCENE_PATH := "res://scenes/title.tscn"
const BATTLE_SCENE_PATH := "res://scenes/battle.tscn"
const STAGE_SELECT_SCENE_PATH := "res://scenes/stage_select.tscn"
const RESULTS_SCENE_PATH := "res://scenes/results.tscn"
const DEFAULT_VIEW_PREFERENCES_PATH := "user://view_preferences.cfg"
const CAMPAIGN_RUNTIME_CONTEXT_SCRIPT := preload("res://sim/campaign_runtime_context.gd")
const CAMPAIGN_RUNTIME_AUTHORITY_SCRIPT := preload("res://sim/campaign_runtime_authority.gd")
const CANONICAL_JSON_SCRIPT := preload("res://sim/canonical_json.gd")
const PLAYER_DATA_RESET_SCRIPT := preload("res://scripts/player_data_reset.gd")

const BATTLE_OPERATOR_IDS: Array[StringName] = [
	&"recruit", &"sniper_1", &"guard_1", &"caster_1",
]

var run_seed: int = 42
var default_stage_id: StringName = &"s1"
var default_squad: Array[StringName] = BATTLE_OPERATOR_IDS.duplicate()
var pending_stage: StageDef = null
var current_battle: BattleModel = null
var content: Node = null

# Direct battles cannot submit outcomes to an active campaign.
var campaign: Variant = null
var campaign_store: Variant = null
var campaign_active: bool = false
var selected_stage_id: StringName = &""
var selected_squad: Array[StringName] = []
var last_result: Dictionary = {}
var last_campaign_error: StringName = &""
var _campaign_context: Dictionary = {}
var _pending_battle_ticket: Dictionary = {}
var _pending_campaign_mutation: Variant = null
var _pending_launch_mutation: Variant = null
var _pending_launch_open_battle := true
var _campaign_battle_active := false
var _prepared_battle_result: Dictionary = {}
var _command_tutorial_requested := false
var _post_mission_tutorial_requested := false
var _view_preferences_path := DEFAULT_VIEW_PREFERENCES_PATH


func set_run_seed(value: int) -> void:
	run_seed = value
	seed(value)


## Resume a valid durable campaign by default. Explicit fresh starts first
## restore/migrate the prior slot, then replace it through expected-preimage CAS.
func start_campaign(open_campaign_ui: bool = true, fresh: bool = false) -> bool:
	_campaign_context = CAMPAIGN_RUNTIME_CONTEXT_SCRIPT.build()
	var started: Dictionary = (
		CAMPAIGN_RUNTIME_AUTHORITY_SCRIPT.start_new(run_seed, _campaign_context)
		if fresh
		else CAMPAIGN_RUNTIME_AUTHORITY_SCRIPT.load_or_create(run_seed, _campaign_context)
	)
	if not started["accepted"]:
		last_campaign_error = StringName(started["error_code"])
		push_error("Game.start_campaign: %s" % last_campaign_error)
		return false
	campaign = started["state"]
	campaign_store = started["store"]
	campaign_active = true
	pending_stage = null
	current_battle = null
	selected_stage_id = &""
	selected_squad = []
	last_result = {}
	last_campaign_error = &""
	_pending_battle_ticket = {}
	_pending_campaign_mutation = null
	_pending_launch_mutation = null
	_pending_launch_open_battle = true
	_campaign_battle_active = false
	_prepared_battle_result = {}
	_post_mission_tutorial_requested = false
	_restore_pending_attempt()
	_prefetch_campaign_operator_packs()
	if open_campaign_ui:
		if _campaign_battle_active:
			_queue_battle(selected_stage_id)
		else:
			open_stage_select()
	return true


func _restore_pending_attempt() -> void:
	var data: Dictionary = campaign.data_copy()
	if int(data["next_attempt_id"]) != int(data["next_resolution_index"]) + 1:
		return
	var tickets: Array = data["tickets"]
	if tickets.is_empty():
		return
	var ticket: Dictionary = tickets[-1]
	if int(ticket["attempt_id"]) != int(data["next_resolution_index"]):
		return
	selected_stage_id = StringName(ticket["stage_id"])
	selected_squad = []
	for row: Dictionary in ticket["squad"]:
		selected_squad.append(StringName(row["hero_id"]))
	_pending_battle_ticket = ticket.duplicate(true)
	_campaign_battle_active = true


## Player campaign launch is an authoritative strategic command. Selection and
## scene state publish only after the BattleTicket is durably committed.
func start_stage(
	stage_id: StringName,
	squad: Array[StringName],
	open_battle: bool = true,
) -> Dictionary:
	if not campaign_active or campaign == null or campaign_store == null:
		selected_stage_id = stage_id
		selected_squad = squad.duplicate()
		start_battle(stage_id, open_battle)
		return {"accepted": true, "error_code": &"", "ticket": {}}
	if _pending_campaign_mutation != null:
		return {"accepted": false, "error_code": &"strategic_mutation_pending"}
	var committed: Dictionary
	if _pending_launch_mutation != null:
		committed = CAMPAIGN_RUNTIME_AUTHORITY_SCRIPT.retry(
			_pending_launch_mutation, campaign_store,
		)
	else:
		_pending_launch_open_battle = open_battle
		var command_id := "runtime:begin:%s:%d" % [
			campaign.campaign_uid(), campaign.next_attempt_id(),
		]
		var command: Dictionary = campaign.begin_attempt(
			command_id, stage_id, squad, run_seed, campaign.save_revision(),
		)
		committed = CAMPAIGN_RUNTIME_AUTHORITY_SCRIPT.commit(
			command, campaign_store,
		)
	if not committed["accepted"]:
		_pending_launch_mutation = (
			committed.get("mutation") if committed.get("retryable", false) else null
		)
		return committed
	_pending_launch_mutation = null
	campaign = committed["state"]
	var ticket: Dictionary = committed["result"]["ticket"].duplicate(true)
	selected_stage_id = StringName(ticket["stage_id"])
	selected_squad = []
	for row: Dictionary in ticket["squad"]:
		selected_squad.append(StringName(row["hero_id"]))
	_pending_battle_ticket = ticket
	_campaign_battle_active = true
	if _pending_launch_open_battle:
		_queue_battle(selected_stage_id)
	_pending_launch_open_battle = true
	return {"accepted": true, "error_code": &"", "ticket": ticket.duplicate(true)}


func mission_launch_retry_pending() -> bool:
	return _pending_launch_mutation != null


func cancel_mission_launch_retry() -> bool:
	var discarded := _pending_launch_mutation != null
	_pending_launch_mutation = null
	_pending_launch_open_battle = true
	return discarded


## Direct battles retain explicit input for replay compatibility. Campaign
## battles use a signed witness ticket while tactical choices use the fixed
## operator roster published by battle_launch().
func _battle_squad() -> Array[StringName]:
	if not selected_squad.is_empty():
		return selected_squad.duplicate()
	return default_squad


func battle_launch() -> Dictionary:
	return {
		"input": (
			_pending_battle_ticket.duplicate(true)
			if _campaign_battle_active
			else _battle_squad()
		),
		"trusted_ticket_hashes": (
			[String(_pending_battle_ticket["ticket_hash"])]
			if _campaign_battle_active
			else []
		),
		"fixed_operator_ids": BATTLE_OPERATOR_IDS.duplicate(),
		"trap_ids": loadout_trap_ids() if _campaign_battle_active else _scan_ids(
			"res://data/traps"
		),
	}


func is_stage_unlocked(stage_id: StringName) -> bool:
	if campaign == null:
		return true
	var projection: Dictionary = campaign.runtime_projection()
	var position := (projection["stage_ids"] as Array).find(stage_id)
	return (
		position <= 0
		or (projection["stage_stars"] as Dictionary).has(
			projection["stage_ids"][position - 1]
		)
	)


func campaign_stage_ids() -> Array[StringName]:
	if campaign == null:
		return []
	return campaign.runtime_projection()["stage_ids"].duplicate()


func campaign_projection() -> Dictionary:
	if not campaign_active or campaign == null:
		return {}
	return campaign.runtime_projection()


func has_cleared_first_mission() -> bool:
	var projection := campaign_projection()
	var stage_order: Array = projection.get("stage_ids", [])
	if stage_order.is_empty():
		return false
	var stage_stars: Dictionary = projection.get("stage_stars", {})
	return int(stage_stars.get(stage_order[0], 0)) > 0


## Loadout sets for the UI: unlocked sets during a campaign, full catalogs
## for direct battles.
func loadout_operator_ids() -> Array[StringName]:
	return BATTLE_OPERATOR_IDS.duplicate()


func loadout_trap_ids() -> Array[StringName]:
	if campaign_active and campaign != null:
		return campaign.runtime_projection()["unlocked_traps"]
	return _scan_ids("res://data/traps")


## Commit the model-owned canonical BattleOutcome. The view supplies only the
## result edge; rewards and stars come from the resolved strategic receipt.
func record_result(result: int, stars: int) -> bool:
	return prepare_result(result, stars) and commit_prepared_result()


## Build and validate the one-command strategic transition without touching
## durable authority. BattleView schedules commit on the following frame so
## non-threaded Web never pays both phases in one render frame.
func prepare_result(result: int, stars: int) -> bool:
	if current_battle == null:
		return false
	if not _prepared_battle_result.is_empty():
		return (
			int(_prepared_battle_result.get("result", -1)) == result
			and int(_prepared_battle_result.get("stars", -1)) == stars
		)
	var stage := current_battle.stage
	if not _campaign_battle_active:
		_prepared_battle_result = {
			"direct": true,
			"stage_id": stage.id,
			"result": result,
			"stars": stars,
			"leaks": current_battle.leaked,
			"kills": current_battle.killed,
		}
		return true
	var outcome: Dictionary = current_battle.terminal_outcome()
	if outcome.is_empty():
		return false
	if _pending_campaign_mutation != null:
		_prepared_battle_result = {
			"direct": false,
			"retry": true,
			"result": result,
			"stars": stars,
		}
	else:
		var attempt_id := int(_pending_battle_ticket["attempt_id"])
		var command_id := "runtime:resolve:%s:%d" % [campaign.campaign_uid(), attempt_id]
		var command: Dictionary = campaign.resolve_attempt(
			command_id,
			attempt_id,
			outcome,
			int(_pending_battle_ticket["expected_save_revision"]),
		)
		if not command.get("accepted", false):
			last_campaign_error = command.get("error_code", &"invalid_command")
			return false
		_prepared_battle_result = {
			"direct": false,
			"retry": false,
			"command": command,
			"result": result,
			"stars": stars,
		}
	return true


func commit_prepared_result() -> bool:
	if _prepared_battle_result.is_empty():
		return false
	var prepared := _prepared_battle_result
	_prepared_battle_result = {}
	if bool(prepared.get("direct", false)):
		last_result = {
			"stage_id": prepared["stage_id"],
			"result": prepared["result"],
			"stars": prepared["stars"],
			"leaks": prepared["leaks"],
			"kills": prepared["kills"],
			"rewards_granted": [],
		}
		_record_leaderboard_result()
		return true
	var committed: Dictionary = (
		CAMPAIGN_RUNTIME_AUTHORITY_SCRIPT.retry(
			_pending_campaign_mutation, campaign_store,
		)
		if bool(prepared.get("retry", false))
		else CAMPAIGN_RUNTIME_AUTHORITY_SCRIPT.commit(prepared["command"], campaign_store)
	)
	if not committed["accepted"]:
		last_campaign_error = committed["error_code"]
		_pending_campaign_mutation = committed.get("mutation")
		return false
	last_campaign_error = &""
	_pending_campaign_mutation = null
	campaign = committed["state"]
	var resolution: Dictionary = committed["result"]["resolution"]
	var accepted_outcome: Dictionary = committed["result"]["outcome"]
	var canonical_result := (
		BattleModel.Result.CLEAR
		if String(accepted_outcome["result"]) == "clear"
		else BattleModel.Result.DEFEAT
	)
	last_result = {
		"stage_id": StringName(resolution["stage_id"]),
		"result": canonical_result,
		"stars": int(accepted_outcome["stars"]),
		"leaks": int(accepted_outcome["leaks"]),
		"kills": int(accepted_outcome["kills"]),
		"rewards_granted": resolution["rewards_granted"].duplicate(true),
		"marks_before": int(resolution["marks_before"]),
		"marks_after": int(resolution["marks_after"]),
		"dead_hero_ids": resolution["dead_hero_ids"].duplicate(),
	}
	_record_leaderboard_result()
	_arm_post_mission_tutorial(canonical_result, resolution)
	_pending_battle_ticket = {}
	_campaign_battle_active = false
	return true


func _record_leaderboard_result() -> void:
	var leaderboard := get_node_or_null("/root/Leaderboard")
	if leaderboard == null or not leaderboard.has_method("record_mission"):
		return
	var record: Dictionary = leaderboard.call("record_mission", last_result)
	if record.is_empty():
		return
	last_result["leaderboard_score"] = int(record.get("score", 0))
	last_result["leaderboard_submission_id"] = String(record.get("submission_id", ""))


func commit_campaign_command(command: Dictionary) -> Dictionary:
	if not campaign_active or campaign_store == null:
		return {"accepted": false, "error_code": &"campaign_inactive"}
	if strategic_mutation_pending():
		return {"accepted": false, "error_code": &"strategic_mutation_pending"}
	var committed: Dictionary = CAMPAIGN_RUNTIME_AUTHORITY_SCRIPT.commit(
		command, campaign_store,
	)
	if committed["accepted"]:
		campaign = committed["state"]
	return committed


func rename_hero(hero_id: String, callsign: String, title: Variant = null) -> Dictionary:
	if not campaign_active or campaign == null or campaign_store == null:
		return {"accepted": false, "error_code": &"campaign_inactive"}
	if strategic_mutation_pending():
		return {"accepted": false, "error_code": &"strategic_mutation_pending"}
	var revision: int = campaign.save_revision()
	var digest := CANONICAL_JSON_SCRIPT.sha256_hex(
		{"hero_id": hero_id, "callsign": callsign, "title": title},
	).substr(0, 16)
	var command_id := "runtime:rename:%s:%d:%s:%s" % [
		campaign.campaign_uid(), revision, hero_id, digest,
	]
	var command: Dictionary = campaign.rename_hero(
		command_id, revision, hero_id, callsign, title,
	)
	var committed: Dictionary = CAMPAIGN_RUNTIME_AUTHORITY_SCRIPT.commit(
		command, campaign_store,
	)
	if committed["accepted"]:
		campaign = committed["state"]
	return committed


func _prefetch_campaign_operator_packs() -> void:
	if not campaign_active or campaign == null:
		return
	var content_packs := get_node_or_null("/root/ContentPacks")
	if content_packs == null:
		return
	var projection: Dictionary = campaign.runtime_projection()
	content_packs.call(
		"prefetch_roster", projection.get("ready_heroes", []), selected_squad,
	)


func strategic_mutation_pending() -> bool:
	return (
		_pending_campaign_mutation != null
		or _pending_launch_mutation != null
	)


## The boot flow arms this one-shot request. Command Center consumes it so
## other routes and test fixtures do not unexpectedly mount onboarding.
func request_command_tutorial() -> void:
	_command_tutorial_requested = true


func consume_command_tutorial_request() -> bool:
	var requested := _command_tutorial_requested
	_command_tutorial_requested = false
	return requested


func request_post_mission_tutorial() -> void:
	if has_cleared_first_mission():
		_post_mission_tutorial_requested = true


func consume_post_mission_tutorial_request() -> bool:
	var requested := _post_mission_tutorial_requested
	_post_mission_tutorial_requested = false
	return requested and has_cleared_first_mission()


func _arm_post_mission_tutorial(result: int, resolution: Dictionary) -> void:
	var stage_order := campaign_stage_ids()
	if (
		result == BattleModel.Result.CLEAR
		and int(resolution.get("stars_before", 0)) == 0
		and not stage_order.is_empty()
		and StringName(resolution.get("stage_id", &"")) == stage_order[0]
	):
		request_post_mission_tutorial()


func set_view_preferences_path(path: String) -> void:
	_view_preferences_path = path if not path.is_empty() else DEFAULT_VIEW_PREFERENCES_PATH


func view_preferences_path() -> String:
	return _view_preferences_path


## Stops persistent writers, removes the complete user:// tree, clears live
## campaign authority, and returns to the start screen.
func clear_player_data() -> Dictionary:
	for service_path: NodePath in [
		NodePath("/root/ContentPacks"),
		NodePath("/root/Leaderboard"),
	]:
		var service := get_node_or_null(service_path)
		if service != null and service.has_method("prepare_for_player_data_clear"):
			service.call("prepare_for_player_data_clear")
	var cleared: Dictionary = PLAYER_DATA_RESET_SCRIPT.clear_all()
	var leaderboard := get_node_or_null("/root/Leaderboard")
	if leaderboard != null and leaderboard.has_method("finish_player_data_clear"):
		leaderboard.call(
			"finish_player_data_clear", bool(cleared.get(&"accepted", false)),
		)
	if not bool(cleared.get(&"accepted", false)):
		push_error(
			"Game.clear_player_data: %s (%s)" % [
				String(cleared.get(&"error_code", &"player_data_clear_failed")),
				cleared.get(&"failures", []),
			],
		)
		return cleared
	_view_preferences_path = DEFAULT_VIEW_PREFERENCES_PATH
	open_title()
	return cleared


func _reset_campaign_runtime() -> void:
	pending_stage = null
	current_battle = null
	campaign = null
	campaign_store = null
	campaign_active = false
	selected_stage_id = &""
	selected_squad = []
	last_result = {}
	_campaign_context = {}
	_pending_battle_ticket = {}
	_pending_campaign_mutation = null
	_pending_launch_mutation = null
	_pending_launch_open_battle = true
	_campaign_battle_active = false
	_prepared_battle_result = {}
	_command_tutorial_requested = false
	_post_mission_tutorial_requested = false


func open_title() -> void:
	_reset_campaign_runtime()
	_swap_content.call_deferred(TITLE_SCENE_PATH)


## Routes directly to Campaign, resuming durable authority when needed.
func open_campaign_home() -> bool:
	if campaign_active and campaign != null and campaign_store != null:
		open_stage_select()
		return true
	return start_campaign()


func open_stage_select() -> void:
	_swap_content.call_deferred(STAGE_SELECT_SCENE_PATH)


## Commit a campaign attempt and enter the mission immediately. The ticket keeps
## one stable campaign-personnel witness for save/replay integrity; tactical
## deployment uses the fixed repeatable four-operator roster.
func start_campaign_stage(stage_id: StringName, open_battle: bool = true) -> bool:
	if not campaign_active or campaign == null or stage_id.is_empty():
		return false
	if stage_id not in campaign_stage_ids() or not is_stage_unlocked(stage_id):
		return false
	var stage_path := "res://data/stages/%s.tres" % stage_id
	if not ResourceLoader.exists(stage_path):
		return false
	var witness_ids := _campaign_attempt_witness_ids()
	if witness_ids.is_empty():
		last_campaign_error = &"campaign_roster_empty"
		return false
	var launched := start_stage(stage_id, witness_ids, open_battle)
	if not bool(launched.get("accepted", false)):
		last_campaign_error = StringName(launched.get("error_code", &"mission_launch_failed"))
		return false
	last_campaign_error = &""
	return true


func _campaign_attempt_witness_ids() -> Array[StringName]:
	var rows: Array = campaign.data_copy().get("heroes", []) if campaign != null else []
	rows.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.get("recruitment_index", -1)) < int(b.get("recruitment_index", -1))
	)
	if rows.is_empty():
		return []
	return [StringName((rows[0] as Dictionary).get("hero_id", ""))]


func open_results() -> void:
	_swap_content.call_deferred(RESULTS_SCENE_PATH)


func _catalogs() -> Dictionary:
	return {
		"operators": _scan_ids("res://data/operators"),
		"traps": _scan_ids("res://data/traps"),
	}


func _all_stage_defs() -> Array:
	var defs: Array = []
	for stage_id: StringName in stage_ids():
		defs.append(load("res://data/stages/%s.tres" % stage_id) as StageDef)
	return defs


func _scan_ids(dir_path: String) -> Array[StringName]:
	var names: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return []
	for file: String in dir.get_files():
		# exported builds list "<name>.tres.remap" (text->binary conversion)
		var res_name := file.trim_suffix(".remap")
		if res_name.ends_with(".tres"):
			names.append(res_name.trim_suffix(".tres"))
	names.sort()
	var ids: Array[StringName] = []
	for item_name: String in names:
		ids.append(StringName(item_name))
	return ids


## list and the debug_reach sweep both read this scan, so Lane B stages
## appear in both with zero code changes.
func stage_ids() -> Array[StringName]:
	# sort as String: StringName's own ordering is interning-order, not text
	return _scan_ids("res://data/stages")


func start_battle(stage_id: StringName, open_battle: bool = true) -> void:
	_campaign_battle_active = false
	_pending_battle_ticket = {}
	if open_battle:
		_queue_battle(stage_id)


func _queue_battle(stage_id: StringName) -> void:
	var stage_path := "res://data/stages/%s.tres" % stage_id
	if not ResourceLoader.exists(stage_path):
		push_error("unknown stage: " + stage_path)
		return
	var previous_content := content
	var previous_pending := pending_stage
	var previous_battle := current_battle
	pending_stage = load(stage_path) as StageDef
	_swap_content.call_deferred(
		BATTLE_SCENE_PATH, previous_content, previous_pending, previous_battle
	)


func _swap_content(
	scene_path: String,
	previous_override: Node = null,
	previous_pending: StageDef = null,
	previous_battle: BattleModel = null,
) -> void:
	var music := get_node_or_null("/root/Music")
	# Incumbent UI scenes assign Game.content from _ready(). Capture the real
	# predecessor before add_child() runs that synchronous callback, then retire
	# exactly that node at the commit point.
	var previous := previous_override if scene_path == BATTLE_SCENE_PATH else content
	var packed: PackedScene = load(scene_path)
	var candidate: Node = packed.instantiate()
	get_tree().root.add_child(candidate)
	var accepted := _accept_content_candidate(
		candidate,
		scene_path == BATTLE_SCENE_PATH,
		previous,
		previous_pending,
		previous_battle,
	)
	if accepted:
		_route_music_before_scene(music, scene_path)
		_route_music_after_scene(music, scene_path)


## Commit point shared by the runtime swap and executable activation tests.
## Adding the candidate runs _ready synchronously, so the entire decision and
## prior-content retirement remain inside this one deferred swap call.
func _accept_content_candidate(
	candidate: Node,
	is_battle: bool,
	previous: Node = null,
	previous_pending: StageDef = null,
	previous_battle: BattleModel = null,
) -> bool:
	if candidate == null or not is_instance_valid(candidate):
		if is_battle:
			pending_stage = previous_pending
			current_battle = previous_battle
		return false
	var candidate_battle: BattleModel = null
	if is_battle:
		candidate_battle = candidate.get("model") as BattleModel
		var startup_succeeded: Variant = candidate.get("startup_succeeded")
		if startup_succeeded != true or candidate_battle == null:
			candidate.queue_free()
			pending_stage = previous_pending
			current_battle = previous_battle
			return false
	if previous != null and is_instance_valid(previous) and previous != candidate:
		var previous_parent := previous.get_parent()
		if previous_parent != null:
			previous_parent.remove_child(previous)
		previous.queue_free()
	content = candidate
	if is_battle:
		current_battle = candidate_battle
	return true


func _stop_music_node(music: Node) -> bool:
	if music == null or not music.has_method("stop"):
		return false
	music.call("stop")
	return true


func _route_music_before_scene(music: Node, scene_path: String) -> void:
	if music == null:
		return
	if scene_path == BATTLE_SCENE_PATH:
		_stop_music_node(music)
		return


func _route_music_after_scene(music: Node, scene_path: String) -> void:
	if music == null:
		return
	if _is_staging_music_scene(scene_path) and music.has_method("play_staging"):
		music.call("play_staging", &"lunaris")
		Sfx.play("menu_open")
	elif scene_path == BATTLE_SCENE_PATH and pending_stage != null and music.has_method("play_battle"):
		var initial_state := &"boss" if pending_stage.music_variant_id == &"boss" else &"low"
		music.call(
			"play_battle",
			pending_stage.music_profile_id,
			pending_stage.music_variant_id,
			initial_state,
		)


func _is_staging_music_scene(scene_path: String) -> bool:
	return scene_path == STAGE_SELECT_SCENE_PATH
