class_name ReplayCodec
extends RefCounted

const SCHEMA := "prototype_td_replay"
const VERSION := 1
const VERSION_2 := 2
const ROOT_KEYS := ["schema", "version", "stage_id", "seed", "squad", "actions"]
const ROOT_KEYS_V2 := ["schema", "version", "ticket", "actions"]
const BattleTicketRuntimeScript := preload("res://sim/battle_ticket_runtime.gd")


static func load_file(path: String, context: Dictionary) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _reject(&"replay_open_failed")
	var source := file.get_as_text()
	file.close()
	if not source.ends_with("\n") or source.ends_with("\n\n") or source.contains("\r"):
		return _reject(&"noncanonical_replay")
	var parser := JSON.new()
	if parser.parse(source) != OK:
		return _reject(&"malformed_replay_json")
	var coerced := CanonicalJson.restore_exact_integers(source, parser.data)
	if not coerced["accepted"]:
		return coerced
	var decoded := decode_document(coerced["value"], context)
	if not decoded["accepted"]:
		return decoded
	var encoded := (
		encode_document(
			decoded["stage_id"],
			decoded["squad"],
			decoded["seed"],
			decoded["timeline"],
			context,
		)
		if decoded["version"] == VERSION
		else encode_document_v2(decoded["ticket"], decoded["timeline"], context)
	)
	if not encoded["accepted"] or encoded["text"] != source:
		return _reject(&"noncanonical_replay")
	decoded["text"] = source
	decoded["sha256"] = encoded["sha256"]
	return decoded


static func decode_document(document: Variant, context: Dictionary) -> Dictionary:
	if not _valid_context(context):
		return _reject(&"missing_replay_context")
	if (
		typeof(document) == TYPE_DICTIONARY
		and document.get("schema") == SCHEMA
		and document.get("version") == VERSION_2
	):
		return _decode_v2(document, context)
	if typeof(document) != TYPE_DICTIONARY or not _exact_keys(document, ROOT_KEYS):
		return _reject(&"invalid_replay_schema")
	if document["schema"] != SCHEMA or not _is_integer(document["version"]):
		return _reject(&"unsupported_replay")
	if int(document["version"]) != VERSION:
		return _reject(&"unsupported_replay")
	if not _nonempty_string(document["stage_id"]) or not _in_i64(document["seed"]):
		return _reject(&"invalid_replay_header")
	var squad_result := _decode_squad(document["squad"])
	if not squad_result["accepted"]:
		return squad_result
	if typeof(document["actions"]) != TYPE_ARRAY:
		return _reject(&"invalid_actions")
	var timeline: Array = []
	var previous_tick := -1
	for row: Variant in document["actions"]:
		var decoded := _decode_action(row)
		if not decoded["accepted"]:
			return decoded
		var tick := int(decoded["tick"])
		if tick < previous_tick:
			return _reject(&"actions_out_of_order")
		previous_tick = tick
		timeline.append(decoded["timeline_row"])
	var contextual := _validate_contextual(
		String(document["stage_id"]),
		squad_result["value"],
		timeline,
		context,
	)
	if not contextual["accepted"]:
		return contextual
	return {
		"accepted": true,
		"error_code": &"",
		"version": VERSION,
		"stage_id": StringName(document["stage_id"]),
		"seed": int(document["seed"]),
		"squad": squad_result["value"],
		"timeline": timeline,
	}


static func _decode_v2(document: Dictionary, context: Dictionary) -> Dictionary:
	if not _exact_keys(document, ROOT_KEYS_V2):
		return _reject(&"invalid_replay_schema")
	var ticket_result := BattleTicket.normalize(document["ticket"])
	if not ticket_result["accepted"]:
		return ticket_result
	if typeof(document["actions"]) != TYPE_ARRAY:
		return _reject(&"invalid_actions")
	var timeline: Array = []
	var previous_tick := -1
	for row: Variant in document["actions"]:
		var decoded := _decode_action(row, VERSION_2)
		if not decoded["accepted"]:
			return decoded
		var tick := int(decoded["tick"])
		if tick < previous_tick:
			return _reject(&"actions_out_of_order")
		previous_tick = tick
		timeline.append(decoded["timeline_row"])
	var ticket: Dictionary = ticket_result["value"]
	var contextual := _validate_contextual_v2(ticket, timeline, context)
	if not contextual["accepted"]:
		return contextual
	var squad: Array[StringName] = []
	for frozen: Dictionary in ticket["squad"]:
		squad.append(StringName(frozen["battle_id"]))
	return {
		"accepted": true,
		"error_code": &"",
		"version": VERSION_2,
		"stage_id": StringName(ticket["stage_id"]),
		"seed": int(ticket["seed"]),
		"squad": squad,
		"ticket": ticket,
		"timeline": timeline,
	}


static func encode_document(
	stage_id: StringName,
	squad: Array[StringName],
	seed_value: int,
	timeline: Array,
	context: Dictionary,
) -> Dictionary:
	var actions: Array = []
	var previous_tick := -1
	for timeline_row: Variant in timeline:
		var encoded := _encode_action(timeline_row)
		if not encoded["accepted"]:
			return encoded
		var tick := int(encoded["value"]["tick"])
		if tick < previous_tick:
			return _reject(&"actions_out_of_order")
		previous_tick = tick
		actions.append(encoded["value"])
	var squad_values: Array[String] = []
	for operator_id: StringName in squad:
		if String(operator_id).is_empty() or squad_values.has(String(operator_id)):
			return _reject(&"invalid_squad")
		squad_values.append(String(operator_id))
	var root := {}
	root["schema"] = SCHEMA
	root["version"] = VERSION
	root["stage_id"] = String(stage_id)
	root["seed"] = seed_value
	root["squad"] = squad_values
	root["actions"] = actions
	var validated := decode_document(root, context)
	if not validated["accepted"]:
		return validated
	var source := CanonicalJson.text(root)
	return {
		"accepted": true,
		"error_code": &"",
		"value": root,
		"text": source,
		"sha256": CanonicalJson.sha256_text(source),
	}


static func encode_document_v2(
	ticket_value: Variant,
	timeline: Array,
	context: Dictionary,
) -> Dictionary:
	var ticket_result := BattleTicket.normalize(ticket_value)
	if not ticket_result["accepted"]:
		return ticket_result
	var actions: Array = []
	var previous_tick := -1
	for timeline_row: Variant in timeline:
		var encoded := _encode_action(timeline_row, VERSION_2)
		if not encoded["accepted"]:
			return encoded
		var tick := int(encoded["value"]["tick"])
		if tick < previous_tick:
			return _reject(&"actions_out_of_order")
		previous_tick = tick
		actions.append(encoded["value"])
	var root := {}
	root["schema"] = SCHEMA
	root["version"] = VERSION_2
	root["ticket"] = ticket_result["value"]
	root["actions"] = actions
	var validated := decode_document(root, context)
	if not validated["accepted"]:
		return validated
	var source := CanonicalJson.text(root)
	return {
		"accepted": true,
		"error_code": &"",
		"value": root,
		"text": source,
		"sha256": CanonicalJson.sha256_text(source),
	}


static func _decode_squad(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_ARRAY or (value as Array).is_empty():
		return _reject(&"invalid_squad")
	var out: Array[StringName] = []
	for operator_id: Variant in value:
		if not _nonempty_string(operator_id) or out.has(StringName(operator_id)):
			return _reject(&"invalid_squad")
		out.append(StringName(operator_id))
	return _accept(out)


static func _decode_action(row: Variant, version: int = VERSION) -> Dictionary:
	if typeof(row) != TYPE_DICTIONARY or not _exact_keys(row, ["tick", "verb", "args"]):
		return _reject(&"invalid_action_schema")
	if not _in_u32(row["tick"]):
		return _reject(&"invalid_action_tick")
	if not _nonempty_string(row["verb"]) or typeof(row["args"]) != TYPE_DICTIONARY:
		return _reject(&"invalid_action")
	var verb := String(row["verb"])
	var args: Dictionary = row["args"]
	var action: Array = [StringName(verb)]
	match verb:
		"deploy":
			var identity_key := "operator_id" if version == VERSION else "battle_id"
			if not _exact_keys(args, [identity_key, "cell", "facing"]):
				return _reject(&"invalid_action_args")
			var cell := _decode_cell(args["cell"])
			if not cell["accepted"] or not _nonempty_string(args[identity_key]):
				return _reject(&"invalid_action_args")
			if not _is_integer(args["facing"]) or int(args["facing"]) not in [0, 1, 2, 3]:
				return _reject(&"invalid_action_args")
			action.append_array(
				[StringName(args[identity_key]), cell["value"], int(args["facing"])]
			)
		"retreat", "trigger_skill":
			if not _exact_keys(args, ["unit_id"]) or not _in_nonnegative_i32(args["unit_id"]):
				return _reject(&"invalid_action_args")
			action.append(int(args["unit_id"]))
		"mend":
			if not _exact_keys(args, ["healer_unit_id", "target_unit_id"]):
				return _reject(&"invalid_action_args")
			if (
				not _in_nonnegative_i32(args["healer_unit_id"])
				or not _in_nonnegative_i32(args["target_unit_id"])
			):
				return _reject(&"invalid_action_args")
			(
				action
				. append_array(
					[
						int(args["healer_unit_id"]),
						int(args["target_unit_id"]),
					]
				)
			)
		"place_trap":
			if not _exact_keys(args, ["trap_id", "cell"]):
				return _reject(&"invalid_action_args")
			var cell := _decode_cell(args["cell"])
			if not cell["accepted"] or not _nonempty_string(args["trap_id"]):
				return _reject(&"invalid_action_args")
			action.append_array([StringName(args["trap_id"]), cell["value"]])
		"resign":
			if not args.is_empty():
				return _reject(&"invalid_action_args")
		_:
			return _reject(&"unknown_action_verb")
	return {
		"accepted": true,
		"error_code": &"",
		"tick": int(row["tick"]),
		"timeline_row": [int(row["tick"])] + action,
	}


static func _encode_action(row: Variant, version: int = VERSION) -> Dictionary:
	if typeof(row) != TYPE_ARRAY or (row as Array).size() < 2:
		return _reject(&"invalid_timeline_row")
	if not _in_u32(row[0]):
		return _reject(&"invalid_action_tick")
	var verb := String(row[1])
	var args := {}
	match verb:
		"deploy":
			if row.size() != 5 or typeof(row[3]) != TYPE_VECTOR2I or typeof(row[4]) != TYPE_INT:
				return _reject(&"invalid_timeline_row")
			if not _in_i32(row[3].x) or not _in_i32(row[3].y):
				return _reject(&"invalid_timeline_row")
			if int(row[4]) not in [0, 1, 2, 3]:
				return _reject(&"invalid_timeline_row")
			args["operator_id" if version == VERSION else "battle_id"] = String(row[2])
			args["cell"] = [row[3].x, row[3].y]
			args["facing"] = int(row[4])
		"retreat", "trigger_skill":
			if row.size() != 3 or not _in_nonnegative_i32(row[2]):
				return _reject(&"invalid_timeline_row")
			args["unit_id"] = int(row[2])
		"mend":
			if (
				row.size() != 4
				or not _in_nonnegative_i32(row[2])
				or not _in_nonnegative_i32(row[3])
			):
				return _reject(&"invalid_timeline_row")
			args["healer_unit_id"] = int(row[2])
			args["target_unit_id"] = int(row[3])
		"place_trap":
			if row.size() != 4 or typeof(row[3]) != TYPE_VECTOR2I:
				return _reject(&"invalid_timeline_row")
			if not _in_i32(row[3].x) or not _in_i32(row[3].y):
				return _reject(&"invalid_timeline_row")
			args["trap_id"] = String(row[2])
			args["cell"] = [row[3].x, row[3].y]
		"resign":
			if row.size() != 2:
				return _reject(&"invalid_timeline_row")
		_:
			return _reject(&"unknown_action_verb")
	var action := {}
	action["tick"] = int(row[0])
	action["verb"] = verb
	action["args"] = args
	return _accept(action)


static func _decode_cell(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_ARRAY or (value as Array).size() != 2:
		return _reject(&"invalid_cell")
	if not _in_i32(value[0]) or not _in_i32(value[1]):
		return _reject(&"invalid_cell")
	return _accept(Vector2i(int(value[0]), int(value[1])))


static func build_context(
	operators: Dictionary,
	traps: Dictionary,
	stages: Dictionary,
	config: GameConfig,
	trusted_ticket_hashes: Array = [],
) -> Dictionary:
	var trusted: Array[String] = []
	for value: Variant in trusted_ticket_hashes:
		var ticket_hash := String(value)
		if not trusted.has(ticket_hash):
			trusted.append(ticket_hash)
	trusted.sort()
	return {
		"operators": operators,
		"traps": traps,
		"stages": stages,
		"config": config,
		"trusted_ticket_hashes": trusted,
	}


static func _validate_contextual(
	stage_id: String,
	squad: Array[StringName],
	timeline: Array,
	context: Dictionary,
) -> Dictionary:
	if not context["stages"].has(StringName(stage_id)):
		return _reject(&"unknown_replay_stage")
	var stage: StageDef = context["stages"][StringName(stage_id)]
	if squad.is_empty() or squad.size() > stage.squad_size:
		return _reject(&"invalid_squad_capacity")
	for operator_id: StringName in squad:
		if not context["operators"].has(operator_id):
			return _reject(&"unknown_squad_operator")
	for row: Array in timeline:
		var action_check := _validate_action_context(row, squad, stage, context)
		if not action_check["accepted"]:
			return action_check
	return _accept(true)


static func _validate_contextual_v2(
	ticket: Dictionary,
	timeline: Array,
	context: Dictionary,
) -> Dictionary:
	var stage_id := StringName(ticket["stage_id"])
	if not context["stages"].has(stage_id):
		return _reject(&"unknown_replay_stage")
	var stage: StageDef = context["stages"][stage_id]
	var prepared := BattleTicketRuntimeScript.prepare(ticket, stage)
	if not prepared["accepted"]:
		return prepared
	if not context["trusted_ticket_hashes"].has(ticket["ticket_hash"]):
		return _reject(&"untrusted_ticket_hash")
	var rows := {}
	for frozen: Dictionary in prepared["rows"]:
		rows[StringName(frozen["battle_id"])] = frozen
	var empty_squad: Array[StringName] = []
	for row: Array in timeline:
		if row[1] == &"deploy":
			if (
				not rows.has(row[2])
				or not BattleTicketRuntimeScript.cell_in_domain(rows[row[2]], stage, row[3])
			):
				return _reject(&"invalid_deploy_context")
			continue
		var action_check := _validate_action_context(row, empty_squad, stage, context)
		if not action_check["accepted"]:
			return action_check
	return _accept(true)


static func _validate_action_context(
	row: Array,
	squad: Array[StringName],
	stage: StageDef,
	context: Dictionary,
) -> Dictionary:
	var verb := String(row[1])
	match verb:
		"deploy":
			if not squad.has(row[2]) or not context["operators"].has(row[2]):
				return _reject(&"invalid_deploy_context")
			var operator_def: OperatorDef = context["operators"][row[2]]
			if not stage.operator_cell_in_domain(operator_def, row[3]):
				return _reject(&"invalid_deploy_context")
		"place_trap":
			if not context["traps"].has(row[2]) or not stage.trap_cell_in_domain(row[3]):
				return _reject(&"invalid_trap_context")
	return _accept(true)


static func _valid_context(context: Dictionary) -> bool:
	if not _exact_keys(
		context,
		["operators", "traps", "stages", "config", "trusted_ticket_hashes"],
	):
		return false
	if typeof(context["trusted_ticket_hashes"]) != TYPE_ARRAY:
		return false
	for value: Variant in context["trusted_ticket_hashes"]:
		if not _is_hex(String(value), 64):
			return false
	return true


static func _exact_keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size():
		return false
	var actual: Array = value.keys()
	for index: int in expected.size():
		if actual[index] != expected[index]:
			return false
	return true


static func _nonempty_string(value: Variant) -> bool:
	return typeof(value) in [TYPE_STRING, TYPE_STRING_NAME] and not String(value).is_empty()


static func _is_integer(value: Variant) -> bool:
	return typeof(value) == TYPE_INT


static func _in_u32(value: Variant) -> bool:
	return _is_integer(value) and int(value) >= 0 and int(value) <= 4_294_967_295


static func _in_i32(value: Variant) -> bool:
	return _is_integer(value) and int(value) >= -2_147_483_648 and int(value) <= 2_147_483_647


static func _in_nonnegative_i32(value: Variant) -> bool:
	return _is_integer(value) and int(value) >= 0 and int(value) <= 2_147_483_647


static func _in_i64(value: Variant) -> bool:
	return _is_integer(value)


static func _is_hex(value: String, length: int) -> bool:
	if value.length() != length:
		return false
	for character: String in value:
		if character not in "0123456789abcdef":
			return false
	return true


static func _accept(value: Variant) -> Dictionary:
	return {"accepted": true, "error_code": &"", "value": value}


static func _reject(error_code: StringName) -> Dictionary:
	return {"accepted": false, "error_code": error_code}
