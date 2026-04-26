extends RefCounted
class_name ReconSystem
const Pathfinding = preload("res://scripts/systems/Pathfinding.gd")

const SCOUT_LEVEL_MIN := 0
const SCOUT_LEVEL_MAX := 4

const COMBAT_TYPES := {"infantry": true, "tank": true, "mechanized": true, "motorized": true}
const SUPPORT_TYPES := {"recon": true, "antiTank": true, "weapons": true, "artillery": true}

const FLOOR_BY_TYPE := {
	"infantry": 1,
	"tank": 1,
	"mechanized": 1,
	"motorized": 1,
	"recon": 3
}

const ROLL_DENOMINATOR_BY_TYPE := {
	"recon": 2,
	"infantry": 4,
	"tank": 4,
	"mechanized": 4,
	"motorized": 4
}

const SIZE_ORDER := ["platoon", "company", "battalion", "regiment"]

static func resolve_turn_start_intel(units: Dictionary, observer_owner: int, prior_hex_intel: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var next_hex_intel := prior_hex_intel.duplicate(true)
	var enemy_hex_to_units := _collect_enemy_units_by_hex(units, observer_owner)
	var adjacent_enemy_hexes := _collect_adjacent_enemy_hexes(units, observer_owner, enemy_hex_to_units)

	for enemy_hex_id in adjacent_enemy_hexes.keys():
		var intel := _ensure_hex_intel(next_hex_intel, enemy_hex_id)
		var adjacent_friendlies: Array = adjacent_enemy_hexes[enemy_hex_id]
		intel["scoutLevel"] = _apply_automatic_floor(int(intel.get("scoutLevel", SCOUT_LEVEL_MIN)), adjacent_friendlies)
		var level_gain := _roll_scout_progression(adjacent_friendlies, rng)
		intel["scoutLevel"] = int(clamp(int(intel.get("scoutLevel", SCOUT_LEVEL_MIN)) + level_gain, SCOUT_LEVEL_MIN, SCOUT_LEVEL_MAX))
		var enemy_units: Array = enemy_hex_to_units.get(enemy_hex_id, [])
		_resolve_visible_intel(intel, enemy_units, rng)
		next_hex_intel[enemy_hex_id] = intel

	for enemy_hex_id in next_hex_intel.keys():
		if adjacent_enemy_hexes.has(enemy_hex_id):
			continue
		var stale_intel: Dictionary = next_hex_intel[enemy_hex_id]
		stale_intel["knownEnemyUnits"] = []
		stale_intel["scoutLevel"] = SCOUT_LEVEL_MIN
		next_hex_intel[enemy_hex_id] = stale_intel

	return next_hex_intel

static func resolve_recon(attacker: Dictionary, defender: Dictionary, modifier: int = 0, rng: RandomNumberGenerator = null) -> Dictionary:
	var resolved_rng := rng
	if resolved_rng == null:
		resolved_rng = RandomNumberGenerator.new()
		resolved_rng.randomize()
	var base_roll := resolved_rng.randi_range(0, 100)
	var attacker_bonus := int(attacker.get("recon_bonus", 0))
	var defender_penalty := int(defender.get("concealment", 0))
	var total: int = int(clamp(base_roll + attacker_bonus + modifier - defender_penalty, 0, 100))
	return {"roll": base_roll, "total": total, "band": _band_for(total)}

static func expected_adjacent_scout_floor(unit_type: String) -> int:
	return int(FLOOR_BY_TYPE.get(unit_type, 0))

static func _collect_enemy_units_by_hex(units: Dictionary, observer_owner: int) -> Dictionary:
	var result := {}
	for unit in units.values():
		if not (unit is Dictionary):
			continue
		var unit_dict := unit as Dictionary
		if int(unit_dict.get("owner", observer_owner)) == observer_owner:
			continue
		var hex_id := _hex_to_id(unit_dict.get("hex", Vector2i.ZERO))
		if not result.has(hex_id):
			result[hex_id] = []
		(result[hex_id] as Array).append(unit_dict)
	return result

static func _collect_adjacent_enemy_hexes(units: Dictionary, observer_owner: int, enemy_hex_to_units: Dictionary) -> Dictionary:
	var adjacent_enemy_hexes := {}
	for unit in units.values():
		if not (unit is Dictionary):
			continue
		var friendly := unit as Dictionary
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
		var existing := intel_store[enemy_hex_id] as Dictionary
		if not existing.has("hexId"):
			existing["hexId"] = enemy_hex_id
		if not existing.has("knownEnemyUnits"):
			existing["knownEnemyUnits"] = []
		if not existing.has("scoutLevel"):
			existing["scoutLevel"] = SCOUT_LEVEL_MIN
		return existing
	return {"hexId": enemy_hex_id, "scoutLevel": SCOUT_LEVEL_MIN, "knownEnemyUnits": []}

static func _apply_automatic_floor(current_level: int, adjacent_friendlies: Array) -> int:
	var level := current_level
	for unit in adjacent_friendlies:
		if not (unit is Dictionary):
			continue
		var floor := expected_adjacent_scout_floor(_normalized_type(unit as Dictionary))
		level = maxi(level, floor)
	return int(clamp(level, SCOUT_LEVEL_MIN, SCOUT_LEVEL_MAX))

static func _roll_scout_progression(adjacent_friendlies: Array, rng: RandomNumberGenerator) -> int:
	var gain := 0
	for unit in adjacent_friendlies:
		if not (unit is Dictionary):
			continue
		var denominator := int(ROLL_DENOMINATOR_BY_TYPE.get(_normalized_type(unit as Dictionary), 0))
		if denominator <= 0:
			continue
		if rng.randi_range(1, denominator) == 1:
			gain += 1
	return gain

static func _resolve_visible_intel(hex_intel: Dictionary, enemy_units: Array, rng: RandomNumberGenerator) -> void:
	var level := int(hex_intel.get("scoutLevel", SCOUT_LEVEL_MIN))
	var known_by_unit_id := _known_enemy_lookup(hex_intel.get("knownEnemyUnits", []))
	var next_known: Array[Dictionary] = []
	for enemy in enemy_units:
		if not (enemy is Dictionary):
			continue
		var enemy_unit := enemy as Dictionary
		var unit_id := String(enemy_unit.get("id", ""))
		if unit_id.is_empty():
			continue
		var known := known_by_unit_id.get(unit_id, _new_known_enemy(unit_id))
		_apply_level_type_visibility(level, known, enemy_unit, rng)
		_apply_level_size_visibility(level, known, enemy_unit, rng)
		next_known.append(known)
	hex_intel["knownEnemyUnits"] = next_known

static func _apply_level_type_visibility(level: int, known: Dictionary, enemy_unit: Dictionary, rng: RandomNumberGenerator) -> void:
	var unit_type := _normalized_type(enemy_unit)
	if level <= 0:
		return
	if level == 1:
		if not bool(known.get("typeKnown", false)) and rng.randi_range(1, 4) == 1:
			known["reportedUnitType"] = unit_type
			known["typeKnown"] = true
		return
	if level == 2:
		if COMBAT_TYPES.has(unit_type):
			known["reportedUnitType"] = unit_type
			known["typeKnown"] = true
		elif unit_type in ["recon", "antiTank", "weapons"] and not bool(known.get("typeKnown", false)) and rng.randi_range(1, 4) == 1:
			known["reportedUnitType"] = unit_type
			known["typeKnown"] = true
		return
	known["reportedUnitType"] = unit_type
	known["typeKnown"] = true

static func _apply_level_size_visibility(level: int, known: Dictionary, enemy_unit: Dictionary, rng: RandomNumberGenerator) -> void:
	if bool(known.get("sizeReportLocked", false)):
		return
	if level < 3:
		return
	var unit_type := _normalized_type(enemy_unit)
	var true_size := _normalized_size(enemy_unit)
	if level == 3:
		if not COMBAT_TYPES.has(unit_type):
			return
		if rng.randi_range(1, 4) != 1:
			return
		var drift_roll := rng.randi_range(1, 4)
		var drift := -1 if drift_roll == 1 else (1 if drift_roll == 4 else 0)
		known["reportedSize"] = _shift_size(true_size, drift)
	elif level >= 4:
		if rng.randi_range(1, 8) == 1:
			var direction := -1 if rng.randi_range(1, 2) == 1 else 1
			known["reportedSize"] = _shift_size(true_size, direction)
		else:
			known["reportedSize"] = true_size
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
	var by_id := {}
	var known_units := raw_known_units as Array
	if known_units == null:
		return by_id
	for entry in known_units:
		if not (entry is Dictionary):
			continue
		var known := entry as Dictionary
		var unit_id := String(known.get("unitId", ""))
		if unit_id.is_empty():
			continue
		by_id[unit_id] = known.duplicate(true)
	return by_id

static func _new_known_enemy(unit_id: String) -> Dictionary:
	return {
		"unitId": unit_id,
		"typeKnown": false,
		"sizeKnown": false,
		"sizeReportLocked": false
	}

static func _normalized_type(unit: Dictionary) -> String:
	var direct := String(unit.get("unit_type", unit.get("type", ""))).strip_edges()
	if not direct.is_empty():
		return _canonical_type(direct)
	var is_tank := bool(unit.get("is_tank", false))
	return "tank" if is_tank else "infantry"

static func _canonical_type(raw_type: String) -> String:
	var normalized := raw_type.strip_edges().to_lower()
	match normalized:
		"anti_tank", "antitank":
			return "antiTank"
		_:
			return normalized

static func _normalized_size(unit: Dictionary) -> String:
	var size := String(unit.get("formation_size", unit.get("size", "company"))).strip_edges().to_lower()
	if size in SIZE_ORDER:
		return size
	return "company"

static func _shift_size(size: String, delta: int) -> String:
	var index := SIZE_ORDER.find(size)
	if index < 0:
		index = SIZE_ORDER.find("company")
	var shifted := clamp(index + delta, 0, SIZE_ORDER.size() - 1)
	return String(SIZE_ORDER[int(shifted)])

static func _hex_to_id(hex: Variant) -> String:
	var as_hex := hex as Vector2i
	if as_hex == null:
		return "0,0"
	return "%d,%d" % [as_hex.x, as_hex.y]

static func _id_to_hex(hex_id: String) -> Vector2i:
	var split := hex_id.split(",")
	if split.size() != 2:
		return Vector2i.ZERO
	return Vector2i(int(split[0]), int(split[1]))
