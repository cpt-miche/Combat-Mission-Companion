extends RefCounted
class_name ReconSystem
const Pathfinding = preload("res://scripts/systems/Pathfinding.gd")
const ReconAIConfig = preload("res://scripts/core/ReconAIConfig.gd")

const SCOUT_LEVEL_MIN := ReconAIConfig.SCOUT_LEVEL_MIN
const SCOUT_LEVEL_MAX := ReconAIConfig.SCOUT_LEVEL_MAX
const UNIT_INTEL_KEY := "__unitIntelById"

const COMBAT_TYPES := ReconAIConfig.UNIT_CATEGORIES["combat"]
const SUPPORT_TYPES := ReconAIConfig.UNIT_CATEGORIES["support"]

const FLOOR_BY_TYPE := ReconAIConfig.AUTOMATIC_SCOUT_FLOOR_BY_TYPE

const ROLL_DENOMINATOR_BY_TYPE := ReconAIConfig.SCOUT_PROGRESSION_DENOMINATOR_BY_TYPE

const SIZE_ORDER := ["platoon", "company", "battalion", "regiment"]

static func resolve_turn_start_intel(units: Dictionary, observer_owner: int, prior_hex_intel: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var prior_unit_intel: Dictionary = _extract_prior_unit_intel(prior_hex_intel)
	var next_hex_intel: Dictionary = _extract_prior_hex_intel(prior_hex_intel)
	var enemy_hex_to_units: Dictionary = _collect_enemy_units_by_hex(units, observer_owner)
	var adjacent_enemy_hexes: Dictionary = _collect_adjacent_enemy_hexes(units, observer_owner, enemy_hex_to_units)
	var contact_unit_ids: Dictionary = _collect_contact_enemy_unit_ids(adjacent_enemy_hexes, enemy_hex_to_units)
	var unit_intel_by_id: Dictionary = _reconcile_unit_intel(prior_unit_intel, contact_unit_ids)
	var resolved_levels_by_hex: Dictionary = {}

	for enemy_hex_id in adjacent_enemy_hexes.keys():
		var enemy_hex_key: String = String(enemy_hex_id)
		var intel_for_floor: Dictionary = _ensure_hex_intel(next_hex_intel, enemy_hex_key)
		var adjacent_friendlies: Array = adjacent_enemy_hexes[enemy_hex_key]
		intel_for_floor["scoutLevel"] = _apply_automatic_floor(int(intel_for_floor.get("scoutLevel", SCOUT_LEVEL_MIN)), adjacent_friendlies)
		next_hex_intel[enemy_hex_key] = intel_for_floor

	for enemy_hex_id in adjacent_enemy_hexes.keys():
		var enemy_hex_key: String = String(enemy_hex_id)
		var adjacent_friendlies: Array = adjacent_enemy_hexes[enemy_hex_key]
		var level_gain: int = _roll_scout_progression(adjacent_friendlies, rng)
		resolved_levels_by_hex[enemy_hex_key] = level_gain

	for enemy_hex_id in adjacent_enemy_hexes.keys():
		var enemy_hex_key: String = String(enemy_hex_id)
		var intel_for_gain: Dictionary = _ensure_hex_intel(next_hex_intel, enemy_hex_key)
		var prior_level: int = int(intel_for_gain.get("scoutLevel", SCOUT_LEVEL_MIN))
		var level_gain: int = int(resolved_levels_by_hex.get(enemy_hex_key, 0))
		intel_for_gain["scoutLevel"] = int(clamp(prior_level + level_gain, SCOUT_LEVEL_MIN, SCOUT_LEVEL_MAX))
		next_hex_intel[enemy_hex_key] = intel_for_gain

	for enemy_hex_id in adjacent_enemy_hexes.keys():
		var enemy_hex_key: String = String(enemy_hex_id)
		var intel: Dictionary = _ensure_hex_intel(next_hex_intel, enemy_hex_key)
		var enemy_units: Array = enemy_hex_to_units.get(enemy_hex_key, [])
		_resolve_visible_intel(intel, enemy_units, unit_intel_by_id, rng)
		next_hex_intel[enemy_hex_key] = intel

	for enemy_hex_id in next_hex_intel.keys():
		if String(enemy_hex_id) == UNIT_INTEL_KEY:
			continue
		if adjacent_enemy_hexes.has(enemy_hex_id):
			continue
		var stale_intel: Dictionary = next_hex_intel[enemy_hex_id]
		stale_intel["knownEnemyUnits"] = []
		stale_intel["scoutLevel"] = SCOUT_LEVEL_MIN
		next_hex_intel[enemy_hex_id] = stale_intel

	next_hex_intel[UNIT_INTEL_KEY] = unit_intel_by_id
	return next_hex_intel

static func resolve_recon(attacker: Dictionary, defender: Dictionary, modifier: int = 0, rng: RandomNumberGenerator = null) -> Dictionary:
	var resolved_rng: RandomNumberGenerator = rng
	if resolved_rng == null:
		resolved_rng = RandomNumberGenerator.new()
		resolved_rng.randomize()
	var base_roll: int = resolved_rng.randi_range(0, 100)
	var attacker_bonus: int = int(attacker.get("recon_bonus", 0))
	var defender_penalty: int = int(defender.get("concealment", 0))
	var total: int = int(clamp(base_roll + attacker_bonus + modifier - defender_penalty, 0, 100))
	return {"roll": base_roll, "total": total, "band": _band_for(total)}

static func expected_adjacent_scout_floor(unit_type: String) -> int:
	return int(FLOOR_BY_TYPE.get(unit_type, 0))

static func _collect_enemy_units_by_hex(units: Dictionary, observer_owner: int) -> Dictionary:
	var result: Dictionary = {}
	for unit in units.values():
		if not (unit is Dictionary):
			continue
		var unit_dict: Dictionary = unit as Dictionary
		if int(unit_dict.get("owner", observer_owner)) == observer_owner:
			continue
		var hex_id: String = _hex_to_id(unit_dict.get("hex", Vector2i.ZERO))
		if not result.has(hex_id):
			result[hex_id] = []
		(result[hex_id] as Array).append(unit_dict)
	return result

static func _collect_adjacent_enemy_hexes(units: Dictionary, observer_owner: int, enemy_hex_to_units: Dictionary) -> Dictionary:
	var adjacent_enemy_hexes: Dictionary = {}
	for unit in units.values():
		if not (unit is Dictionary):
			continue
		var friendly: Dictionary = unit as Dictionary
		if int(friendly.get("owner", -1)) != observer_owner:
			continue
		for enemy_hex_id in enemy_hex_to_units.keys():
			if not Pathfinding.are_adjacent(friendly.get("hex", Vector2i.ZERO), _id_to_hex(String(enemy_hex_id))):
				continue
			if not adjacent_enemy_hexes.has(enemy_hex_id):
				adjacent_enemy_hexes[enemy_hex_id] = []
			(adjacent_enemy_hexes[enemy_hex_id] as Array).append(friendly)
	return adjacent_enemy_hexes

static func _ensure_hex_intel(intel_store: Dictionary, enemy_hex_id: String) -> Dictionary:
	if intel_store.has(enemy_hex_id) and intel_store[enemy_hex_id] is Dictionary:
		return _normalize_hex_intel((intel_store[enemy_hex_id] as Dictionary).duplicate(true), enemy_hex_id)
	return _new_hex_intel(enemy_hex_id)

static func _extract_prior_hex_intel(prior_hex_intel: Dictionary) -> Dictionary:
	var next_hex_intel: Dictionary = {}
	for key in prior_hex_intel.keys():
		if String(key) == UNIT_INTEL_KEY:
			continue
		var value: Variant = prior_hex_intel[key]
		if not (value is Dictionary):
			continue
		next_hex_intel[key] = (value as Dictionary).duplicate(true)
	return next_hex_intel

static func _extract_prior_unit_intel(prior_hex_intel: Dictionary) -> Dictionary:
	var prior_unit_intel: Dictionary = {}
	var raw_unit_intel: Variant = prior_hex_intel.get(UNIT_INTEL_KEY, null)
	if raw_unit_intel is Dictionary:
		for unit_id in (raw_unit_intel as Dictionary).keys():
			var known: Variant = (raw_unit_intel as Dictionary).get(unit_id, null)
			if not (known is Dictionary):
				continue
			prior_unit_intel[String(unit_id)] = (known as Dictionary).duplicate(true)
		return prior_unit_intel
	for hex_id in prior_hex_intel.keys():
		var intel: Variant = prior_hex_intel.get(hex_id, null)
		if not (intel is Dictionary):
			continue
		var known_lookup: Dictionary = _known_enemy_lookup((intel as Dictionary).get("knownEnemyUnits", []))
		for unit_id in known_lookup.keys():
			prior_unit_intel[String(unit_id)] = (known_lookup[unit_id] as Dictionary).duplicate(true)
	return prior_unit_intel

static func _collect_contact_enemy_unit_ids(adjacent_enemy_hexes: Dictionary, enemy_hex_to_units: Dictionary) -> Dictionary:
	var contact_unit_ids: Dictionary = {}
	for enemy_hex_id in adjacent_enemy_hexes.keys():
		var enemy_units: Array = enemy_hex_to_units.get(enemy_hex_id, [])
		for enemy in enemy_units:
			if not (enemy is Dictionary):
				continue
			var enemy_unit: Dictionary = enemy as Dictionary
			var unit_id: String = String(enemy_unit.get("id", ""))
			if unit_id.is_empty():
				continue
			contact_unit_ids[unit_id] = true
	return contact_unit_ids

static func _reconcile_unit_intel(prior_unit_intel: Dictionary, contact_unit_ids: Dictionary) -> Dictionary:
	var unit_intel_by_id: Dictionary = {}
	for unit_id in contact_unit_ids.keys():
		var key: String = String(unit_id)
		var existing: Variant = prior_unit_intel.get(key, null)
		if existing is Dictionary:
			unit_intel_by_id[key] = (existing as Dictionary).duplicate(true)
		else:
			unit_intel_by_id[key] = _new_known_enemy(key)
	return unit_intel_by_id

static func _apply_automatic_floor(current_level: int, adjacent_friendlies: Array) -> int:
	var level: int = current_level
	for unit in adjacent_friendlies:
		if not (unit is Dictionary):
			continue
		var floor: int = expected_adjacent_scout_floor(_normalized_type(unit as Dictionary))
		level = maxi(level, floor)
	return int(clamp(level, SCOUT_LEVEL_MIN, SCOUT_LEVEL_MAX))

static func _roll_scout_progression(adjacent_friendlies: Array, rng: RandomNumberGenerator) -> int:
	var gain: int = 0
	for unit in adjacent_friendlies:
		if not (unit is Dictionary):
			continue
		var denominator: int = int(ROLL_DENOMINATOR_BY_TYPE.get(_normalized_type(unit as Dictionary), 0))
		if denominator <= 0:
			continue
		if rng.randi_range(1, denominator) == 1:
			gain += 1
	return gain

static func _resolve_visible_intel(hex_intel: Dictionary, enemy_units: Array, unit_intel_by_id: Dictionary, rng: RandomNumberGenerator) -> void:
	var level: int = int(hex_intel.get("scoutLevel", SCOUT_LEVEL_MIN))
	var next_known: Array[Dictionary] = []
	for enemy in enemy_units:
		if not (enemy is Dictionary):
			continue
		var enemy_unit: Dictionary = enemy as Dictionary
		var unit_id: String = String(enemy_unit.get("id", ""))
		if unit_id.is_empty():
			continue
		var known: Dictionary = _known_for_unit(unit_id, unit_intel_by_id)
		_apply_level_type_visibility(level, known, enemy_unit, rng)
		_apply_level_size_visibility(level, known, enemy_unit, rng)
		unit_intel_by_id[unit_id] = known.duplicate(true)
		next_known.append(known)
	hex_intel["knownEnemyUnits"] = next_known

static func _known_for_unit(unit_id: String, unit_intel_by_id: Dictionary) -> Dictionary:
	var existing: Variant = unit_intel_by_id.get(unit_id, null)
	if existing is Dictionary:
		return (existing as Dictionary).duplicate(true)
	return _new_known_enemy(unit_id)

static func _apply_level_type_visibility(level: int, known: Dictionary, enemy_unit: Dictionary, rng: RandomNumberGenerator) -> void:
	var unit_type: String = _normalized_type(enemy_unit)
	if level <= 0:
		return
	if level == 1:
		if not bool(known.get("typeKnown", false)) and rng.randi_range(1, int(ReconAIConfig.DISCOVERY_ODDS["level_1_type_known_denominator"])) == 1:
			_set_reported_type(known, unit_type)
			known["typeKnown"] = true
		return
	if level == 2:
		if COMBAT_TYPES.has(unit_type):
			_set_reported_type(known, unit_type)
			known["typeKnown"] = true
		elif unit_type in ["recon", "antiTank", "weapons", "artillery"] and not bool(known.get("typeKnown", false)) and rng.randi_range(1, int(ReconAIConfig.DISCOVERY_ODDS["level_2_support_type_known_denominator"])) == 1:
			_set_reported_type(known, unit_type)
			known["typeKnown"] = true
		return
	_set_reported_type(known, unit_type)
	known["typeKnown"] = true

static func _apply_level_size_visibility(level: int, known: Dictionary, enemy_unit: Dictionary, rng: RandomNumberGenerator) -> void:
	if bool(known.get("sizeReportLocked", false)):
		return
	if level < 3:
		return
	var unit_type: String = _normalized_type(enemy_unit)
	var true_size: String = _normalized_size(enemy_unit)
	if level == 3:
		if not COMBAT_TYPES.has(unit_type):
			return
		if rng.randi_range(1, int(ReconAIConfig.DISCOVERY_ODDS["level_3_combat_size_known_denominator"])) != 1:
			return
		var drift_roll: int = rng.randi_range(1, int(ReconAIConfig.DISCOVERY_ODDS["level_3_size_drift_roll_denominator"]))
		var drift_max: int = int(ReconAIConfig.DISCOVERY_ODDS["level_3_size_drift_roll_denominator"])
		var drift: int = -1 if drift_roll == 1 else (1 if drift_roll == drift_max else 0)
		_set_reported_size(known, _shift_size(true_size, drift))
	elif level >= 4:
		if rng.randi_range(1, int(ReconAIConfig.DISCOVERY_ODDS["level_4_size_drift_denominator"])) == 1:
			var direction: int = -1 if rng.randi_range(1, int(ReconAIConfig.DISCOVERY_ODDS["level_4_size_drift_direction_denominator"])) == 1 else 1
			_set_reported_size(known, _shift_size(true_size, direction))
		else:
			_set_reported_size(known, true_size)
	known["sizeKnown"] = true
	known["sizeReportLocked"] = true

static func _band_for(score: int) -> String:
	if score < 20:
		return "No Contact"
	if score < 45:
		return "Suspected"
	if score < 70:
		return "Partial Identification"
	if score < 90:
		return "Clear Identification"
	return "Full Intelligence"

static func _known_enemy_lookup(raw_known_units: Variant) -> Dictionary:
	var by_id: Dictionary = {}
	var known_units: Array = raw_known_units as Array
	if known_units == null:
		return by_id
	for entry in known_units:
		if not (entry is Dictionary):
			continue
		var known: Dictionary = entry as Dictionary
		var unit_id: String = String(known.get("unitId", ""))
		if unit_id.is_empty():
			continue
		by_id[unit_id] = known.duplicate(true)
	return by_id

static func _new_known_enemy(unit_id: String) -> Dictionary:
	return {
		"unitId": unit_id,
		"reportedType": "",
		"typeKnown": false,
		"reportedSize": "",
		"sizeKnown": false,
		"sizeReportLocked": false
	}

static func _new_hex_intel(hex_id: String) -> Dictionary:
	return {
		"hexId": hex_id,
		"scoutLevel": SCOUT_LEVEL_MIN,
		"knownEnemyUnits": []
	}

static func _normalize_hex_intel(intel: Dictionary, hex_id: String) -> Dictionary:
	if not intel.has("hexId"):
		intel["hexId"] = hex_id
	if not intel.has("knownEnemyUnits"):
		intel["knownEnemyUnits"] = []
	if not intel.has("scoutLevel"):
		intel["scoutLevel"] = SCOUT_LEVEL_MIN
	return intel

static func _set_reported_type(known: Dictionary, unit_type: String) -> void:
	known["reportedUnitType"] = unit_type
	known["reportedType"] = unit_type

static func _set_reported_size(known: Dictionary, unit_size: String) -> void:
	known["reportedSize"] = unit_size

static func _normalized_type(unit: Dictionary) -> String:
	var direct: String = String(unit.get("unit_type", unit.get("type", ""))).strip_edges()
	if not direct.is_empty():
		return _canonical_type(direct)
	var is_tank: bool = bool(unit.get("is_tank", false))
	return "tank" if is_tank else "infantry"

static func _canonical_type(raw_type: String) -> String:
	var normalized: String = raw_type.strip_edges().to_lower()
	match normalized:
		"anti_tank", "antitank":
			return "antiTank"
		_:
			return normalized

static func _normalized_size(unit: Dictionary) -> String:
	var size: String = String(unit.get("formation_size", unit.get("size", "company"))).strip_edges().to_lower()
	if size in SIZE_ORDER:
		return size
	return "company"

static func _shift_size(size: String, delta: int) -> String:
	var index: int = SIZE_ORDER.find(size)
	if index < 0:
		index = SIZE_ORDER.find("company")
	var shifted: float = clamp(index + delta, 0, SIZE_ORDER.size() - 1)
	return String(SIZE_ORDER[int(shifted)])

static func _hex_to_id(hex: Variant) -> String:
	var as_hex: Vector2i = hex as Vector2i
	if as_hex == null:
		return "0,0"
	return "%d,%d" % [as_hex.x, as_hex.y]

static func _id_to_hex(hex_id: String) -> Vector2i:
	var split: PackedStringArray = hex_id.split(",")
	if split.size() != 2:
		return Vector2i.ZERO
	return Vector2i(int(split[0]), int(split[1]))
