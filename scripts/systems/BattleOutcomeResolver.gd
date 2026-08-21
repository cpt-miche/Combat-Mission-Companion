class_name BattleOutcomeResolver
extends RefCounted

const RulesService = preload("res://scripts/core/Rules.gd")
const HexPathfinding = preload("res://scripts/systems/Pathfinding.gd")

const OUTCOME_MAJOR_ATTACKER_VICTORY := "major_attacker_victory"
const OUTCOME_ATTACKER_VICTORY := "attacker_victory"
const OUTCOME_ATTACKER_DEFEAT := "attacker_defeat"

static func resolve(units: Dictionary, battle: Dictionary, outcome: String, context: Dictionary = {}) -> Dictionary:
	var resolved_units := units.duplicate(true)
	var movement_events: Array[Dictionary] = []
	var forced_destroyed_ids: Array[String] = []
	var territory_updates := {}
	if outcome == OUTCOME_ATTACKER_DEFEAT:
		return _result(resolved_units, movement_events, forced_destroyed_ids, territory_updates)

	var retreat_distance := 2 if outcome == OUTCOME_MAJOR_ATTACKER_VICTORY else 1
	var rng := RandomNumberGenerator.new()
	rng.seed = int(context.get("rng_seed", 1))
	var moved_unit_ids := {}
	for tile in _battle_tiles(battle):
		var tile_engagements := _engagements_for_tile(battle, tile)
		var attacker_ids := _battle_participant_ids(battle, tile_engagements, "attacker_unit_ids", "attacker_unit_id")
		var defender_ids := _battle_participant_ids(battle, tile_engagements, "defender_unit_ids", "defender_unit_id")
		var attacker_origins := _attacker_origins(tile_engagements, resolved_units)
		for defender_id in defender_ids:
			if moved_unit_ids.has(defender_id) or not _is_living_unit(resolved_units, defender_id):
				continue
			var defender := resolved_units[defender_id] as Dictionary
			var destination: Variant = _retreat_destination(defender_id, defender, tile, retreat_distance, attacker_origins, resolved_units, context, rng)
			if destination == null:
				defender["status"] = "dead"
				resolved_units[defender_id] = defender
				forced_destroyed_ids.append(defender_id)
				movement_events.append({"type": "destroyed_no_retreat", "unit_id": defender_id, "from": tile})
			else:
				var to_hex := destination as Vector2i
				defender["hex"] = to_hex
				defender["dug_in"] = false
				resolved_units[defender_id] = defender
				movement_events.append({"type": "scatter" if retreat_distance == 2 else "retreat", "unit_id": defender_id, "from": tile, "to": to_hex})
			moved_unit_ids[defender_id] = true

		var advanced_any := false
		attacker_ids.sort_custom(func(a: String, b: String) -> bool:
			var a_rank := _unit_size_rank(resolved_units.get(a, {}) as Dictionary)
			var b_rank := _unit_size_rank(resolved_units.get(b, {}) as Dictionary)
			return a < b if a_rank == b_rank else a_rank > b_rank
		)
		for attacker_id in attacker_ids:
			if moved_unit_ids.has(attacker_id) or not _is_living_unit(resolved_units, attacker_id):
				continue
			var attacker := resolved_units[attacker_id] as Dictionary
			if not _can_enter_hex(attacker_id, attacker, tile, resolved_units):
				continue
			var from_hex := attacker.get("hex", Vector2i.ZERO) as Vector2i
			attacker["hex"] = tile
			attacker["dug_in"] = false
			resolved_units[attacker_id] = attacker
			movement_events.append({"type": "advance", "unit_id": attacker_id, "from": from_hex, "to": tile})
			moved_unit_ids[attacker_id] = true
			advanced_any = true
		if advanced_any and not attacker_ids.is_empty():
			var lead_attacker := resolved_units.get(attacker_ids[0], {}) as Dictionary
			territory_updates[_hex_key(tile)] = int(lead_attacker.get("owner", 0)) + 1

	return _result(resolved_units, movement_events, forced_destroyed_ids, territory_updates)

static func _result(units: Dictionary, movements: Array[Dictionary], destroyed: Array[String], territory_updates: Dictionary) -> Dictionary:
	destroyed.sort()
	return {"units": units, "movement_events": movements, "forced_destroyed_unit_ids": destroyed, "territory_updates": territory_updates}

static func _battle_tiles(battle: Dictionary) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	if battle.get("hex", {}) is Dictionary:
		var hex_data := battle.get("hex", {}) as Dictionary
		tiles.append(Vector2i(int(hex_data.get("q", 0)), int(hex_data.get("r", 0))))
	return tiles

static func _engagements_for_tile(battle: Dictionary, tile: Vector2i) -> Array[Dictionary]:
	var matches: Array[Dictionary] = []
	for engagement_variant in battle.get("engagements", []) as Array:
		if not (engagement_variant is Dictionary):
			continue
		var engagement := engagement_variant as Dictionary
		var raw_hex := engagement.get("defender_hex", {}) as Dictionary
		var engagement_hex := Vector2i(int(raw_hex.get("q", 0)), int(raw_hex.get("r", 0)))
		if engagement_hex == tile:
			matches.append(engagement)
	return matches

static func _participant_ids(engagements: Array[Dictionary], field: String) -> Array[String]:
	var ids: Array[String] = []
	for engagement in engagements:
		var unit_id := String(engagement.get(field, ""))
		if not unit_id.is_empty() and not ids.has(unit_id):
			ids.append(unit_id)
	ids.sort()
	return ids

static func _battle_participant_ids(battle: Dictionary, engagements: Array[Dictionary], battle_field: String, engagement_field: String) -> Array[String]:
	var ids: Array[String] = []
	for id_variant in battle.get(battle_field, []) as Array:
		var unit_id := String(id_variant)
		if not unit_id.is_empty() and not ids.has(unit_id):
			ids.append(unit_id)
	if ids.is_empty():
		return _participant_ids(engagements, engagement_field)
	ids.sort()
	return ids

static func _attacker_origins(engagements: Array[Dictionary], units: Dictionary) -> Array[Vector2i]:
	var origins: Array[Vector2i] = []
	for engagement in engagements:
		var raw_hex := engagement.get("attacker_hex", {}) as Dictionary
		var origin := Vector2i(int(raw_hex.get("q", 0)), int(raw_hex.get("r", 0)))
		var attacker_id := String(engagement.get("attacker_unit_id", ""))
		if raw_hex.is_empty() and units.has(attacker_id):
			origin = (units[attacker_id] as Dictionary).get("hex", Vector2i.ZERO) as Vector2i
		if not origins.has(origin):
			origins.append(origin)
	return origins

static func _retreat_destination(unit_id: String, unit: Dictionary, origin: Vector2i, distance: int, attacker_origins: Array[Vector2i], units: Dictionary, context: Dictionary, rng: RandomNumberGenerator) -> Variant:
	var paths: Array = [[origin]]
	for _step in range(distance):
		var next_paths: Array = []
		for path in paths:
			var current := path[path.size() - 1] as Vector2i
			for candidate in _neighbors(current, context):
				if path.has(candidate) or not _is_retreat_hex_legal(unit_id, unit, candidate, units, context, false):
					continue
				var next_path: Array = path.duplicate()
				next_path.append(candidate)
				next_paths.append(next_path)
		paths = next_paths
	if paths.is_empty():
		return null
	var candidates: Array[Vector2i] = []
	var current_threat_distance := _minimum_distance(origin, attacker_origins)
	for path in paths:
		var endpoint := path[path.size() - 1] as Vector2i
		if HexPathfinding.hex_distance(origin, endpoint) != distance:
			continue
		if _minimum_distance(endpoint, attacker_origins) <= current_threat_distance:
			continue
		if not _is_retreat_hex_legal(unit_id, unit, endpoint, units, context, true):
			continue
		if not candidates.has(endpoint):
			candidates.append(endpoint)
	if candidates.is_empty():
		return null
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	if distance == 1:
		var best_distance := -1
		for candidate in candidates:
			best_distance = maxi(best_distance, _minimum_distance(candidate, attacker_origins))
		candidates = candidates.filter(func(candidate: Vector2i) -> bool: return _minimum_distance(candidate, attacker_origins) == best_distance)
	return candidates[rng.randi_range(0, candidates.size() - 1)]

static func _is_retreat_hex_legal(unit_id: String, unit: Dictionary, hex: Vector2i, units: Dictionary, context: Dictionary, check_stack: bool) -> bool:
	var owner := int(unit.get("owner", 0))
	var territory := context.get("territory_map", {}) as Dictionary
	var territory_owner := int(territory.get(_hex_key(hex), GameState.TerritoryOwnership.NEUTRAL))
	if territory_owner not in [GameState.TerritoryOwnership.NEUTRAL, owner + 1]:
		return false
	for other_id_variant in units.keys():
		var other_id := String(other_id_variant)
		if other_id == unit_id or not _is_living_unit(units, other_id):
			continue
		var other := units[other_id] as Dictionary
		if (other.get("hex", Vector2i.ZERO) as Vector2i) == hex and int(other.get("owner", owner)) != owner:
			return false
	return not check_stack or _can_enter_hex(unit_id, unit, hex, units)

static func _can_enter_hex(unit_id: String, unit: Dictionary, hex: Vector2i, units: Dictionary) -> bool:
	var occupants: Array[Dictionary] = []
	for other_id_variant in units.keys():
		var other_id := String(other_id_variant)
		if other_id == unit_id or not _is_living_unit(units, other_id):
			continue
		var other := units[other_id] as Dictionary
		if (other.get("hex", Vector2i.ZERO) as Vector2i) != hex:
			continue
		if int(other.get("owner", -1)) != int(unit.get("owner", -2)):
			return false
		occupants.append(other)
	return bool(RulesService.can_enter_stack(unit, occupants).get("ok", false))

static func _neighbors(hex: Vector2i, context: Dictionary) -> Array[Vector2i]:
	var results: Array[Vector2i] = []
	var dimensions := context.get("map_dimensions", GameState.selected_map_dimensions) as Vector2i
	var even_offsets: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1), Vector2i(0, 1), Vector2i(-1, 1)]
	var odd_offsets: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(1, -1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(0, 1)]
	for offset in (odd_offsets if hex.y % 2 == 1 else even_offsets):
		var candidate: Vector2i = hex + offset
		if candidate.x >= 0 and candidate.y >= 0 and candidate.x < dimensions.x and candidate.y < dimensions.y:
			results.append(candidate)
	return results

static func _minimum_distance(hex: Vector2i, threats: Array[Vector2i]) -> int:
	if threats.is_empty():
		return 999
	var distance := 999
	for threat in threats:
		distance = mini(distance, HexPathfinding.hex_distance(hex, threat))
	return distance

static func _is_living_unit(units: Dictionary, unit_id: String) -> bool:
	return units.has(unit_id) and GameState.is_unit_alive(units[unit_id] as Dictionary)

static func _unit_size_rank(unit: Dictionary) -> int:
	var size_name := String(unit.get("size", "company")).to_lower()
	return ["squad", "section", "platoon", "company", "battalion", "regiment", "division", "army"].find(size_name)

static func _hex_key(hex: Vector2i) -> String:
	return "%d,%d" % [hex.x, hex.y]
