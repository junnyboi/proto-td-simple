class_name BattleHash
extends RefCounted

## FNV-1a 64-bit over BattleModel's canonical field order (ints only).
## EVERY mutable model field appears here — adding model state without
## and stay out. TD-MITIGATION is the explicit exception: copied mitigation
## constants use a sparse append-only extension, preserving every all-default
## legacy hash while any non-default mutation flips it. Extracted from the
## file-size budget; the field order is append-only.
## Float channel (P14 doc): skill-effect params are the ONE non-integer
## input — quantized x1000 at hash time in _append_unit; params must stay
## within that resolution or the hash under-reads them (covered by the
## paranoia table in test_hash_paranoia.gd).

const CanonicalJsonScript := preload("res://sim/canonical_json.gd")


static func of(m: BattleModel) -> int:
	var bytes := PackedByteArray()
	_append_int(bytes, m.tick)
	_append_int(bytes, m.base_hp)
	_append_int(bytes, m.result)
	_append_int(bytes, m.stars)
	_append_int(bytes, m.spawned)
	_append_int(bytes, m.leaked)
	_append_int(bytes, m.killed)
	_append_int(bytes, m.timeline.next_index)
	_append_int(bytes, m.dp)
	_append_int(bytes, m.dp_regen_counter)
	_append_int(bytes, m.dp_regen_accrued)
	_append_int(bytes, m.dp_vanguard_generated)
	_append_int(bytes, m.dp_refunded)
	_append_int(bytes, m.dp_spent)
	_append_int(bytes, m.dp_lost_to_cap)
	_append_int(bytes, m.dp_skill_granted)
	_append_int(bytes, m.retreated)
	_append_int(bytes, m.skills_fired)
	for u: UnitState in m.units:
		_append_unit(bytes, u)
	for e: EnemyState in m.enemies:
		_append_int(bytes, e.id)
		_append_int(bytes, e.def_id.hash())
		_append_int(bytes, e.path_idx)
		_append_int(bytes, e.progress_units)
		_append_int(bytes, e.hp)
		_append_int(bytes, e.atk_counter)
		_append_int(bytes, e.blocked_by)
		_append_int(bytes, e.stunned_until_tick)
		_append_int(bytes, 1 if e.alive else 0)
	_append_int(bytes, m.traps_triggered)
	_append_int(bytes, m._next_trap_id)
	for t: TrapState in m.traps:
		_append_int(bytes, t.id)
		_append_int(bytes, t.def_id.hash())
		_append_int(bytes, t.cell.x)
		_append_int(bytes, t.cell.y)
		_append_int(bytes, t.charges_left)
	_append_int(bytes, m.squad.size())
	for op_id: StringName in m.squad:
		_append_int(bytes, op_id.hash())
	# Presentation-facing simulation records.
	for e: EnemyState in m.enemies:
		_append_int(bytes, e.died_at_tick)
	for t: TrapState in m.traps:
		_append_int(bytes, t.last_trigger_tick)
	for e: EnemyState in m.enemies:
		_append_int(bytes, e.damage_stagger_until_tick)
		_append_int(bytes, e.last_damage_tick)
	# TD-MITIGATION sparse append-only extension. Category + entity id make
	# variable-length rows unambiguous; defaults append no bytes by design.
	for u: UnitState in m.units:
		if u.defense != 0 or u.resistance_permille != 0 or u.attack_damage_kind != 0:
			_append_int(bytes, 1)
			_append_int(bytes, u.id)
			_append_int(bytes, u.defense)
			_append_int(bytes, u.resistance_permille)
			_append_int(bytes, u.attack_damage_kind)
	for e: EnemyState in m.enemies:
		if e.defense != 0 or e.resistance_permille != 0 or e.attack_damage_kind != 0:
			_append_int(bytes, 2)
			_append_int(bytes, e.id)
			_append_int(bytes, e.defense)
			_append_int(bytes, e.resistance_permille)
			_append_int(bytes, e.attack_damage_kind)
	for t: TrapState in m.traps:
		if t.damage_kind != 0:
			_append_int(bytes, 3)
			_append_int(bytes, t.id)
			_append_int(bytes, t.damage_kind)
	# A normalized ticket hash binds every frozen combat, targeting, skill,
	# visual, class, hero, and battle identity field. Mutable per-identity
	# outcome counters are then appended in canonical ticket order.
	if m._is_ticketed():
		_append_int(bytes, 5)
		_append_ascii(bytes, String(m._ticket["ticket_hash"]))
		_append_ascii(bytes, CanonicalJsonScript.sha256_hex(m._ticket))
		_append_ascii(bytes, String(m.terminal_reason))
		for record: Dictionary in m._battle_records:
			_append_ascii(bytes, String(record["battle_id"]))
			_append_ascii(bytes, String(record["hero_id"]))
			_append_int(bytes, int(record["deployments"]))
			_append_int(bytes, int(record["retreats"]))
			_append_int(bytes, 1 if bool(record["fell"]) else 0)
			_append_int(bytes, -1 if record["first_fall_tick"] == null else int(record["first_fall_tick"]))
		_append_ascii(bytes, CanonicalJsonScript.sha256_hex(m._battle_records))
		_append_ascii(bytes, CanonicalJsonScript.sha256_hex(m._outcome))
	# RETREAT_COOLDOWN sparse append-only extension. A battle with no retreat
	# preserves its legacy digest; sorted deployment identities make the
	# cooldown ledger independent of Dictionary insertion order.
	if not m.redeploy_ready_tick_by_id.is_empty():
		_append_int(bytes, 7)
		var cooldown_ids: Array[String] = []
		for raw_id: Variant in m.redeploy_ready_tick_by_id:
			cooldown_ids.append(String(raw_id))
		cooldown_ids.sort()
		_append_int(bytes, cooldown_ids.size())
		for cooldown_id: String in cooldown_ids:
			_append_ascii(bytes, cooldown_id)
			_append_int(bytes, int(m.redeploy_ready_tick_by_id[StringName(cooldown_id)]))
	return _fnv1a64(bytes)


static func _append_unit(bytes: PackedByteArray, u: UnitState) -> void:
	_append_int(bytes, u.id)
	_append_int(bytes, u.op_id.hash())
	_append_int(bytes, u.cell.x)
	_append_int(bytes, u.cell.y)
	_append_int(bytes, u.facing)
	_append_int(bytes, u.hp)
	_append_int(bytes, 1 if u.alive else 0)
	_append_int(bytes, u.atk_counter)
	_append_int(bytes, u.dp_generation_counter)
	_append_int(bytes, u.last_attack_tick)
	_append_int(bytes, u.last_attack_cell.x)
	_append_int(bytes, u.last_attack_cell.y)
	_append_int(bytes, u.sp)
	_append_int(bytes, u.sp_progress)
	_append_int(bytes, u.skill_triggered_tick)
	_append_int(bytes, u.active_effects.size())
	for fx: Dictionary in u.active_effects:
		_append_int(bytes, int(fx["effect"]))
		_append_int(bytes, int(fx["expires_tick"]))
		var keys: Array = (fx["params"] as Dictionary).keys()
		keys.sort()
		for key: String in keys:
			_append_int(bytes, key.hash())
			_append_int(bytes, int(round(float(fx["params"][key]) * 1000.0)))
	_append_int(bytes, u.blocked_ids.size())
	for bid: int in u.blocked_ids:
		_append_int(bytes, bid)
	# TD-021 append-only healer presentation/replay record.
	_append_int(bytes, u.skill_target_unit_id)
	if not u.battle_id.is_empty():
		_append_ascii(bytes, String(u.battle_id))
		_append_ascii(bytes, String(u.hero_id))
		_append_ascii(bytes, String(u.class_id))


static func _append_int(bytes: PackedByteArray, v: int) -> void:
	for i: int in 8:
		bytes.append((v >> (i * 8)) & 0xFF)


static func _append_ascii(bytes: PackedByteArray, value: String) -> void:
	_append_int(bytes, value.length())
	for character: String in value:
		bytes.append(character.unicode_at(0))


static func _fnv1a64(bytes: PackedByteArray) -> int:
	# FNV-1a 64-bit; offset basis 14695981039346656037 as a signed literal.
	var h := -3750763034362895579
	for b: int in bytes:
		h ^= b
		h *= 1099511628211
	return h
