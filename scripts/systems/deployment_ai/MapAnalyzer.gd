extends RefCounted
class_name MapAnalyzer

const TERRAIN_ROUTE_VALUES := {
	"highway": 1.0,
	"road": 0.75
}

const TERRAIN_DEFENSE_VALUES := {
	"urban": 1.0,
	"woods": 0.9,
	"heavy": 0.75,
	"medium": 0.5,
	"light": 0.2,
	"road": 0.1,
	"highway": 0.05
}

const TERRAIN_ATTACK_VALUES := {
	"highway": 1.0,
	"road": 0.85,
	"light": 0.55,
	"medium": 0.35,
	"urban": 0.25,
	"heavy": 0.15,
	"woods": 0.1
}

const OFFSETS_EVEN: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0),
	Vector2i(0, -1), Vector2i(-1, -1),
	Vector2i(0, 1), Vector2i(-1, 1)
]

const OFFSETS_ODD: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0),
	Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(0, 1)
]

static func build_sector_model(
	territory_map: Dictionary,
	terrain_map: Dictionary,
	ai_owner: int,
	player_owner: int,
	capture_hex_id: String = "",
	defend_hex_id: String = "",
	context: String = "defense"
) -> Dictionary:
	var known_hexes := _known_hexes(territory_map, terrain_map)
	var frontline_hexes := _compute_frontline_hexes(territory_map, ai_owner, player_owner, known_hexes)
	var border_hexes := _compute_border_hexes(territory_map, ai_owner, player_owner, known_hexes)
	var contested_area := _compute_contested_area(border_hexes, known_hexes)
	var rear_area := _compute_rear_area(territory_map, ai_owner, known_hexes, frontline_hexes)
	var objective_targets := _objective_targets(capture_hex_id, defend_hex_id)
	var hex_scores := _compute_hex_scores(
		territory_map,
		terrain_map,
		known_hexes,
		frontline_hexes,
		objective_targets,
		player_owner,
		context
	)

	return {
		"frontlineHexes": _to_sorted_array(frontline_hexes),
		"contestedArea": _to_sorted_array(contested_area),
		"rearArea": _to_sorted_array(rear_area),
		"hexScores": hex_scores,
		"metadata": {
			"aiOwner": ai_owner,
			"playerOwner": player_owner,
			"captureHexId": capture_hex_id,
			"defendHexId": defend_hex_id,
			"context": context
		}
	}

static func _compute_frontline_hexes(
	territory_map: Dictionary,
	ai_owner: int,
	player_owner: int,
	known_hexes: Dictionary
) -> Dictionary:
	var frontline := {}
	for hex_id in known_hexes.keys():
		if int(territory_map.get(hex_id, GameState.TerritoryOwnership.NEUTRAL)) != ai_owner:
			continue
		for neighbor_id in _neighbor_ids(hex_id):
			if not known_hexes.has(neighbor_id):
				continue
			if int(territory_map.get(neighbor_id, GameState.TerritoryOwnership.NEUTRAL)) == player_owner:
				frontline[hex_id] = true
				break
	return frontline

static func _compute_border_hexes(
	territory_map: Dictionary,
	ai_owner: int,
	player_owner: int,
	known_hexes: Dictionary
) -> Dictionary:
	var border := {}
	for hex_id in known_hexes.keys():
		var owner := int(territory_map.get(hex_id, GameState.TerritoryOwnership.NEUTRAL))
		if owner != ai_owner and owner != player_owner:
			continue
		var opposing_owner := player_owner if owner == ai_owner else ai_owner
		for neighbor_id in _neighbor_ids(hex_id):
			if not known_hexes.has(neighbor_id):
				continue
			if int(territory_map.get(neighbor_id, GameState.TerritoryOwnership.NEUTRAL)) == opposing_owner:
				border[hex_id] = true
				break
	return border

static func _compute_contested_area(border_hexes: Dictionary, known_hexes: Dictionary) -> Dictionary:
	var contested := {}
	for border_hex_id in border_hexes.keys():
		contested[border_hex_id] = true
		for neighbor_id in _neighbor_ids(border_hex_id):
			if known_hexes.has(neighbor_id):
				contested[neighbor_id] = true
	return contested

static func _compute_rear_area(
	territory_map: Dictionary,
	ai_owner: int,
	known_hexes: Dictionary,
	frontline_hexes: Dictionary
) -> Dictionary:
	var rear := {}
	var ai_owned := {}
	for hex_id in known_hexes.keys():
		if int(territory_map.get(hex_id, GameState.TerritoryOwnership.NEUTRAL)) == ai_owner:
			ai_owned[hex_id] = true

	var distances := _distance_map(frontline_hexes, ai_owned)
	for hex_id in ai_owned.keys():
		if int(distances.get(hex_id, 9999)) >= 2:
			rear[hex_id] = true
	return rear

static func _compute_hex_scores(
	territory_map: Dictionary,
	terrain_map: Dictionary,
	known_hexes: Dictionary,
	frontline_hexes: Dictionary,
	objective_targets: Array[String],
	player_owner: int,
	context: String
) -> Dictionary:
	var scores := {}
	var objective_distances := _distance_map_from_targets(objective_targets, known_hexes)
	var frontline_distances := _distance_map_from_targets(_to_sorted_array(frontline_hexes), known_hexes)

	for hex_id in known_hexes.keys():
		var adjacent_player_owned := _adjacent_owner_count(hex_id, territory_map, known_hexes, player_owner)
		var objective_proximity := _proximity_from_distance(int(objective_distances.get(hex_id, 99)))
		var approach_route_value := _approach_route_value(hex_id, terrain_map, known_hexes)
		var terrain_value := _terrain_context_value(hex_id, terrain_map, context)
		var pressure := _compute_pressure(adjacent_player_owned, objective_proximity, approach_route_value)
		var priority := _compute_priority(pressure, terrain_value, int(frontline_distances.get(hex_id, 99)))

		scores[hex_id] = {
			"pressure": pressure,
			"priority": priority,
			"inputs": {
				"adjacentPlayerOwnedCount": adjacent_player_owned,
				"objectiveProximity": objective_proximity,
				"approachRouteValue": approach_route_value,
				"terrainImportance": terrain_value
			}
		}
	return scores

static func _compute_pressure(adjacent_player_owned: int, objective_proximity: float, approach_route_value: float) -> float:
	return adjacent_player_owned * 1.5 + objective_proximity * 2.0 + approach_route_value * 1.25

static func _compute_priority(pressure: float, terrain_value: float, frontline_distance: int) -> float:
	var frontline_factor := _proximity_from_distance(frontline_distance)
	return pressure * 0.65 + terrain_value * 2.0 + frontline_factor * 1.5

static func _approach_route_value(hex_id: String, terrain_map: Dictionary, known_hexes: Dictionary) -> float:
	var terrain := TerrainCatalog.normalize_terrain_id(String(terrain_map.get(hex_id, TerrainCatalog.DEFAULT_TERRAIN_ID)))
	var base_route_value := float(TERRAIN_ROUTE_VALUES.get(terrain, 0.0))
	var road_links := 0
	for neighbor_id in _neighbor_ids(hex_id):
		if not known_hexes.has(neighbor_id):
			continue
		var neighbor_terrain := TerrainCatalog.normalize_terrain_id(String(terrain_map.get(neighbor_id, TerrainCatalog.DEFAULT_TERRAIN_ID)))
		if TERRAIN_ROUTE_VALUES.has(neighbor_terrain):
			road_links += 1

	var chokepoint_bonus := 0.0
	if road_links >= 2:
		var passable_neighbors := 0
		for neighbor_id in _neighbor_ids(hex_id):
			if known_hexes.has(neighbor_id):
				passable_neighbors += 1
		if passable_neighbors <= 3:
			chokepoint_bonus = 0.5

	return base_route_value + road_links * 0.2 + chokepoint_bonus

static func _terrain_context_value(hex_id: String, terrain_map: Dictionary, context: String) -> float:
	var terrain := TerrainCatalog.normalize_terrain_id(String(terrain_map.get(hex_id, TerrainCatalog.DEFAULT_TERRAIN_ID)))
	if context.strip_edges().to_lower() == "attack":
		return float(TERRAIN_ATTACK_VALUES.get(terrain, 0.2))
	return float(TERRAIN_DEFENSE_VALUES.get(terrain, 0.2))

static func _adjacent_owner_count(hex_id: String, territory_map: Dictionary, known_hexes: Dictionary, owner: int) -> int:
	var count := 0
	for neighbor_id in _neighbor_ids(hex_id):
		if not known_hexes.has(neighbor_id):
			continue
		if int(territory_map.get(neighbor_id, GameState.TerritoryOwnership.NEUTRAL)) == owner:
			count += 1
	return count

static func _objective_targets(capture_hex_id: String, defend_hex_id: String) -> Array[String]:
	var targets: Array[String] = []
	if _is_valid_hex_id(capture_hex_id):
		targets.append(capture_hex_id)
	if _is_valid_hex_id(defend_hex_id) and not targets.has(defend_hex_id):
		targets.append(defend_hex_id)
	return targets

static func _distance_map(frontline_hexes: Dictionary, allowed_hexes: Dictionary) -> Dictionary:
	var starts := _to_sorted_array(frontline_hexes)
	if starts.is_empty():
		return {}
	var distances := {}
	var queue: Array[String] = starts.duplicate()
	for hex_id in starts:
		distances[hex_id] = 0

	while not queue.is_empty():
		var current := String(queue.pop_front())
		var current_distance := int(distances.get(current, 0))
		for neighbor_id in _neighbor_ids(current):
			if not allowed_hexes.has(neighbor_id):
				continue
			if distances.has(neighbor_id):
				continue
			distances[neighbor_id] = current_distance + 1
			queue.append(neighbor_id)
	return distances

static func _distance_map_from_targets(targets: Array[String], known_hexes: Dictionary) -> Dictionary:
	if targets.is_empty():
		return {}
	var distances := {}
	var queue: Array[String] = []
	for target in targets:
		if not known_hexes.has(target):
			continue
		distances[target] = 0
		queue.append(target)

	while not queue.is_empty():
		var current := String(queue.pop_front())
		var current_distance := int(distances.get(current, 0))
		for neighbor_id in _neighbor_ids(current):
			if not known_hexes.has(neighbor_id):
				continue
			if distances.has(neighbor_id):
				continue
			distances[neighbor_id] = current_distance + 1
			queue.append(neighbor_id)
	return distances

static func _proximity_from_distance(distance: int) -> float:
	if distance < 0:
		return 0.0
	return 1.0 / float(distance + 1)

static func _known_hexes(territory_map: Dictionary, terrain_map: Dictionary) -> Dictionary:
	var known := {}
	for key_variant in territory_map.keys():
		var key := String(key_variant).strip_edges()
		if _is_valid_hex_id(key):
			known[key] = true
	for key_variant in terrain_map.keys():
		var key := String(key_variant).strip_edges()
		if _is_valid_hex_id(key):
			known[key] = true
	return known

static func _neighbor_ids(hex_id: String) -> Array[String]:
	var axial := _parse_hex_id(hex_id)
	if axial == null:
		return []

	var offsets := OFFSETS_ODD if int(axial.y) % 2 == 1 else OFFSETS_EVEN
	var neighbors: Array[String] = []
	for offset in offsets:
		neighbors.append(_hex_id(axial + offset))
	return neighbors

static func _to_sorted_array(hex_set: Dictionary) -> Array[String]:
	var output: Array[String] = []
	for key in hex_set.keys():
		output.append(String(key))
	output.sort()
	return output

static func _parse_hex_id(hex_id: String) -> Variant:
	var parts := hex_id.split(",")
	if parts.size() != 2:
		return null
	if not parts[0].strip_edges().is_valid_int() or not parts[1].strip_edges().is_valid_int():
		return null
	return Vector2i(int(parts[0]), int(parts[1]))

static func _is_valid_hex_id(hex_id: String) -> bool:
	return _parse_hex_id(hex_id) != null

static func _hex_id(hex: Vector2i) -> String:
	return "%d,%d" % [hex.x, hex.y]
