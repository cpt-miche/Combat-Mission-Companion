extends RefCounted
class_name GameplayAIService

const OrderSystem = preload("res://scripts/systems/OrderSystem.gd")
const Pathfinding = preload("res://scripts/systems/Pathfinding.gd")
const Rules = preload("res://scripts/core/Rules.gd")

const THREAT_DISTANCE := 2

static func generate_orders(units: Dictionary, active_player: int, terrain_map: Dictionary = {}, operational_ai_state: Dictionary = {}, trace_context: Dictionary = {}) -> Dictionary:
	var orders: Dictionary = {}
	var operational_state_for_orders := _operational_state_for_player(operational_ai_state, active_player)
	var friendly_ids := _sorted_unit_ids(units, active_player)
	var enemy_ids := _sorted_enemy_ids(units, active_player, trace_context)
	var reserved_destinations: Dictionary = {}

	for unit_id in friendly_ids:
		var unit := units[unit_id] as Dictionary
		if not _is_unit_alive(unit):
			continue
		var unit_hex := unit.get("hex", Vector2i.ZERO) as Vector2i
		var adjacent_enemy_id := _first_adjacent_enemy_id(unit_hex, enemy_ids, units)
		if not adjacent_enemy_id.is_empty():
			orders = OrderSystem.upsert_order(orders, OrderSystem.create_attack_order(unit_id, [unit_hex], adjacent_enemy_id, _trace_context_for_order(trace_context, unit_id, "attack")))
			continue

		if _is_threatened(unit_hex, enemy_ids, units):
			orders = OrderSystem.upsert_order(orders, OrderSystem.create_dig_in_order(unit_id, _trace_context_for_order(trace_context, unit_id, "dig_in")))
			continue

		var move_order := _build_move_order(unit_id, unit, units, active_player, enemy_ids, terrain_map, operational_state_for_orders, reserved_destinations, trace_context)
		if not move_order.is_empty():
			orders = OrderSystem.upsert_order(orders, move_order)
			var path := move_order.get("path", []) as Array
			if path.size() > 0:
				reserved_destinations[_hex_key(path[path.size() - 1] as Vector2i)] = true

	return orders

static func _operational_state_for_player(operational_ai_state: Dictionary, active_player: int) -> Dictionary:
	if int(operational_ai_state.get("playerIndex", -1)) != active_player:
		return {}
	return operational_ai_state

static func _build_move_order(unit_id: String, unit: Dictionary, units: Dictionary, active_player: int, enemy_ids: Array[String], terrain_map: Dictionary, operational_ai_state: Dictionary, reserved_destinations: Dictionary, trace_context: Dictionary) -> Dictionary:
	var start_hex := unit.get("hex", Vector2i.ZERO) as Vector2i
	var blocked := _blocked_cells(units, active_player, unit_id)
	var target_candidates := _movement_targets(start_hex, units, active_player, enemy_ids, operational_ai_state, trace_context)
	for target_hex in target_candidates:
		if target_hex == start_hex:
			continue
		if blocked.get(_hex_key(target_hex), false):
			continue
		if reserved_destinations.get(_hex_key(target_hex), false):
			continue
		if not _can_enter_destination(units, unit_id, unit, target_hex):
			continue
		var path := Pathfinding.find_path(start_hex, target_hex, terrain_map, blocked)
		if path.size() < 2:
			continue
		return OrderSystem.create_move_order(unit_id, path, _trace_context_for_order(trace_context, unit_id, "move"))
	return {}

static func _movement_targets(start_hex: Vector2i, units: Dictionary, active_player: int, enemy_ids: Array[String], operational_ai_state: Dictionary, trace_context: Dictionary) -> Array[Vector2i]:
	var targets: Array[Vector2i] = []
	var dimensions := _map_dimensions(trace_context)
	for enemy_id in enemy_ids:
		var enemy := units[enemy_id] as Dictionary
		var enemy_hex := enemy.get("hex", Vector2i.ZERO) as Vector2i
		for neighbor in _sorted_neighbors(enemy_hex, dimensions):
			if neighbor == start_hex:
				continue
			if _has_enemy_at(units, active_player, neighbor):
				continue
			_append_unique_hex(targets, neighbor)

	for objective_hex in _operational_target_hexes(operational_ai_state):
		_append_unique_hex(targets, objective_hex)

	if targets.is_empty():
		var fallback := Vector2i(clampi(dimensions.x / 2, 0, maxi(dimensions.x - 1, 0)), clampi(dimensions.y / 2, 0, maxi(dimensions.y - 1, 0)))
		_append_unique_hex(targets, fallback)

	targets.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var distance_a := _hex_distance(start_hex, a)
		var distance_b := _hex_distance(start_hex, b)
		if distance_a == distance_b:
			return _hex_key(a) < _hex_key(b)
		return distance_a < distance_b
	)
	return targets

static func _operational_target_hexes(operational_ai_state: Dictionary) -> Array[Vector2i]:
	var targets: Array[Vector2i] = []
	var snapshot := operational_ai_state.get("snapshot", {}) as Dictionary
	if snapshot == null:
		snapshot = {}

	for entry_variant in snapshot.get("enemyAdjacentHexes", []) as Array:
		var entry := entry_variant as Dictionary
		if entry == null:
			continue
		_append_hex_id_if_valid(targets, String(entry.get("hexId", "")))

	for sector_variant in snapshot.get("sectors", []) as Array:
		var sector := sector_variant as Dictionary
		if sector == null:
			continue
		for key in ["objectiveHexIds", "frontlineHexIds", "contestedHexIds"]:
			for hex_id_variant in sector.get(key, []) as Array:
				_append_hex_id_if_valid(targets, String(hex_id_variant))

	for key in ["objectiveHexIds", "frontlineHexIds"]:
		for hex_id_variant in operational_ai_state.get(key, []) as Array:
			_append_hex_id_if_valid(targets, String(hex_id_variant))

	return targets

static func _sorted_unit_ids(units: Dictionary, owner: int) -> Array[String]:
	var ids: Array[String] = []
	for unit_id_variant in units.keys():
		var unit := units[unit_id_variant] as Dictionary
		if int(unit.get("owner", -1)) == owner and _is_unit_alive(unit):
			ids.append(String(unit_id_variant))
	ids.sort()
	return ids

static func _sorted_enemy_ids(units: Dictionary, active_player: int, trace_context: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	var ignore_visibility := bool(trace_context.get("ignore_visibility", false))
	var scout_intel := trace_context.get("scout_intel", {}) as Dictionary
	if scout_intel == null:
		scout_intel = {}
	for unit_id_variant in units.keys():
		var unit := units[unit_id_variant] as Dictionary
		if int(unit.get("owner", -1)) == active_player or not _is_unit_alive(unit):
			continue
		var unit_id := String(unit_id_variant)
		if ignore_visibility or _is_enemy_visible_or_scouted(unit_id, unit, units, active_player, scout_intel):
			ids.append(unit_id)
	ids.sort()
	return ids

static func _is_enemy_visible_or_scouted(unit_id: String, enemy_unit: Dictionary, units: Dictionary, active_player: int, scout_intel: Dictionary) -> bool:
	var enemy_hex := enemy_unit.get("hex", Vector2i.ZERO) as Vector2i
	if _is_hex_visible_to_player(units, active_player, enemy_hex):
		return true
	return _scout_intel_mentions_unit_or_hex(scout_intel, unit_id, _hex_key(enemy_hex))

static func _is_hex_visible_to_player(units: Dictionary, active_player: int, hex: Vector2i) -> bool:
	for unit in units.values():
		if not (unit is Dictionary):
			continue
		var unit_dict := unit as Dictionary
		if int(unit_dict.get("owner", -1)) != active_player or not _is_unit_alive(unit_dict):
			continue
		var friendly_hex := unit_dict.get("hex", Vector2i.ZERO) as Vector2i
		if friendly_hex == hex or Pathfinding.are_adjacent(friendly_hex, hex):
			return true
	return false

static func _scout_intel_mentions_unit_or_hex(scout_intel: Dictionary, unit_id: String, hex_key: String) -> bool:
	var unit_intel: Variant = scout_intel.get("__unitIntelById", {})
	if unit_intel is Dictionary and (unit_intel as Dictionary).has(unit_id):
		var known: Variant = (unit_intel as Dictionary).get(unit_id, {})
		if known is Dictionary and bool((known as Dictionary).get("presenceKnown", true)):
			return true
	if not scout_intel.has(hex_key) or not (scout_intel[hex_key] is Dictionary):
		return false
	var hex_intel := scout_intel[hex_key] as Dictionary
	var known_units: Variant = hex_intel.get("knownEnemyUnits", [])
	if not (known_units is Array):
		return false
	for known_variant in known_units as Array:
		if not (known_variant is Dictionary):
			continue
		var known_unit := known_variant as Dictionary
		var known_id := String(known_unit.get("unitId", known_unit.get("id", "")))
		if known_id == unit_id or known_id.is_empty():
			return true
	return false

static func _first_adjacent_enemy_id(unit_hex: Vector2i, enemy_ids: Array[String], units: Dictionary) -> String:
	for enemy_id in enemy_ids:
		var enemy := units[enemy_id] as Dictionary
		if Pathfinding.are_adjacent(unit_hex, enemy.get("hex", Vector2i.ZERO) as Vector2i):
			return enemy_id
	return ""

static func _is_threatened(unit_hex: Vector2i, enemy_ids: Array[String], units: Dictionary) -> bool:
	for enemy_id in enemy_ids:
		var enemy := units[enemy_id] as Dictionary
		if _hex_distance(unit_hex, enemy.get("hex", Vector2i.ZERO) as Vector2i) <= THREAT_DISTANCE:
			return true
	return false

static func _blocked_cells(units: Dictionary, active_player: int, moving_unit_id: String) -> Dictionary:
	var blocked := {}
	for unit_id_variant in units.keys():
		if String(unit_id_variant) == moving_unit_id:
			continue
		var unit := units[unit_id_variant] as Dictionary
		if not _is_unit_alive(unit):
			continue
		if int(unit.get("owner", -1)) == active_player:
			continue
		var hex := unit.get("hex", Vector2i.ZERO) as Vector2i
		blocked[_hex_key(hex)] = true
	return blocked

static func _can_enter_destination(units: Dictionary, moving_unit_id: String, moving_unit: Dictionary, target_hex: Vector2i) -> bool:
	var occupants: Array[Dictionary] = []
	for unit_id_variant in units.keys():
		if String(unit_id_variant) == moving_unit_id:
			continue
		var unit := units[unit_id_variant] as Dictionary
		if not _is_unit_alive(unit):
			continue
		if int(unit.get("owner", -1)) != int(moving_unit.get("owner", -1)):
			continue
		if (unit.get("hex", Vector2i.ZERO) as Vector2i) != target_hex:
			continue
		occupants.append(unit)
	return bool(Rules.can_enter_stack(moving_unit, occupants).get("ok", false))

static func _has_enemy_at(units: Dictionary, active_player: int, hex: Vector2i) -> bool:
	for unit in units.values():
		if not (unit is Dictionary):
			continue
		var unit_dict := unit as Dictionary
		if not _is_unit_alive(unit_dict):
			continue
		if int(unit_dict.get("owner", -1)) == active_player:
			continue
		if (unit_dict.get("hex", Vector2i.ZERO) as Vector2i) == hex:
			return true
	return false

static func _sorted_neighbors(hex: Vector2i, dimensions: Vector2i) -> Array[Vector2i]:
	var candidates: Array[Vector2i] = []
	for q in range(maxi(0, hex.x - 1), mini(maxi(dimensions.x, 1), hex.x + 2)):
		for r in range(maxi(0, hex.y - 1), mini(maxi(dimensions.y, 1), hex.y + 2)):
			var candidate := Vector2i(q, r)
			if candidate == hex:
				continue
			if Pathfinding.are_adjacent(hex, candidate):
				candidates.append(candidate)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return _hex_key(a) < _hex_key(b))
	return candidates

static func _append_hex_id_if_valid(targets: Array[Vector2i], hex_id: String) -> void:
	var hex := _parse_hex_id(hex_id)
	if hex == Vector2i(-9999, -9999):
		return
	_append_unique_hex(targets, hex)

static func _append_unique_hex(targets: Array[Vector2i], hex: Vector2i) -> void:
	if targets.has(hex):
		return
	targets.append(hex)

static func _parse_hex_id(hex_id: String) -> Vector2i:
	var parts := hex_id.strip_edges().split(",")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return Vector2i(-9999, -9999)
	return Vector2i(int(parts[0]), int(parts[1]))

static func _hex_distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(abs(a.x - b.x), abs(a.y - b.y))

static func _hex_key(hex: Vector2i) -> String:
	return "%d,%d" % [hex.x, hex.y]

static func _is_unit_alive(unit: Dictionary) -> bool:
	var status := String(unit.get("status", "")).strip_edges().to_lower()
	if not status.is_empty():
		return status != "dead"
	return bool(unit.get("is_alive", true))

static func _map_dimensions(trace_context: Dictionary) -> Vector2i:
	var dimensions_variant: Variant = trace_context.get("map_dimensions", Vector2i(1, 1))
	if dimensions_variant is Vector2i:
		var dimensions := dimensions_variant as Vector2i
		return Vector2i(maxi(dimensions.x, 1), maxi(dimensions.y, 1))
	return Vector2i(1, 1)

static func _trace_context_for_order(trace_context: Dictionary, unit_id: String, action: String) -> Dictionary:
	var context := trace_context.duplicate(true)
	var base_trace_id := String(context.get("trace_id", "gameplay_ai"))
	context["trace_id"] = "%s_%s_%s" % [base_trace_id, unit_id, action]
	if not context.has("session_id"):
		context["session_id"] = base_trace_id
	return context
