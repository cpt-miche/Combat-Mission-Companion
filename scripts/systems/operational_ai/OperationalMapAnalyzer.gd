extends RefCounted
class_name OperationalMapAnalyzer

static func analyze(territory_map: Dictionary, ai_owner: int, player_owner: int) -> Array[Dictionary]:
	var normalized_territory_map := _canonical_territory_map(territory_map)
	var known_hexes := _known_hexes(normalized_territory_map)
	var adjacency_map := _build_adjacency_map(known_hexes)
	var ai_owned := _owned_hexes(normalized_territory_map, known_hexes, ai_owner)
	var frontline := _compute_frontline_hexes(normalized_territory_map, ai_owned, player_owner, adjacency_map)
	var sectors := _group_connected_components(ai_owned, adjacency_map)

	var normalized: Array[Dictionary] = []
	for component in sectors:
		var component_set := _array_to_set(component)
		var component_frontline := _subset_set(frontline, component_set)
		var distances := _distance_map(_to_sorted_array(component_frontline), component_set, adjacency_map)

		var contested := {}
		var rear := {}
		if component_frontline.is_empty():
			rear = component_set.duplicate()
		else:
			for hex_id in component_set.keys():
				var distance := int(distances.get(hex_id, -1))
				if distance >= 0 and distance <= 1:
					contested[hex_id] = true
				if distance >= 2:
					rear[hex_id] = true

		normalized.append({
			"sectorId": "sector_%s" % _min_hex_id(component),
			"hexIds": _to_sorted_array(component_set),
			"frontlineHexIds": _to_sorted_array(component_frontline),
			"contestedHexIds": _to_sorted_array(contested),
			"rearHexIds": _to_sorted_array(rear)
		})

	normalized.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_ids: Array[String] = a.get("hexIds", [])
		var b_ids: Array[String] = b.get("hexIds", [])
		var a_min := a_ids[0] if not a_ids.is_empty() else ""
		var b_min := b_ids[0] if not b_ids.is_empty() else ""
		return String(a_min) < String(b_min)
	)

	return normalized

static func _known_hexes(territory_map: Dictionary) -> Dictionary:
	var known := {}
	for key_variant in territory_map.keys():
		var parsed_hex: Variant = _parse_hex_id(String(key_variant))
		if parsed_hex is Vector2i:
			known[_hex_id(parsed_hex as Vector2i)] = true
	return known

static func _canonical_territory_map(territory_map: Dictionary) -> Dictionary:
	var normalized := {}
	for key_variant in territory_map.keys():
		var parsed_hex: Variant = _parse_hex_id(String(key_variant))
		if parsed_hex is Vector2i:
			normalized[_hex_id(parsed_hex as Vector2i)] = territory_map[key_variant]
	return normalized

static func _owned_hexes(territory_map: Dictionary, known_hexes: Dictionary, owner: int) -> Dictionary:
	var owned := {}
	for hex_id in known_hexes.keys():
		if int(territory_map.get(hex_id, GameState.TerritoryOwnership.NEUTRAL)) == owner:
			owned[hex_id] = true
	return owned

static func _compute_frontline_hexes(territory_map: Dictionary, ai_owned: Dictionary, player_owner: int, adjacency_map: Dictionary) -> Dictionary:
	var frontline := {}
	for hex_id in ai_owned.keys():
		for neighbor_id in _neighbors_for(hex_id, adjacency_map):
			if int(territory_map.get(neighbor_id, GameState.TerritoryOwnership.NEUTRAL)) == player_owner:
				frontline[hex_id] = true
				break
	return frontline

static func _group_connected_components(ai_owned: Dictionary, adjacency_map: Dictionary) -> Array:
	var components: Array = []
	var visited := {}
	for hex_id in _to_sorted_array(ai_owned):
		if visited.has(hex_id):
			continue

		var component: Array[String] = []
		var queue: Array[String] = [hex_id]
		visited[hex_id] = true

		while not queue.is_empty():
			var current := String(queue.pop_front())
			component.append(current)
			for neighbor_id in _neighbors_for(current, adjacency_map):
				if not ai_owned.has(neighbor_id):
					continue
				if visited.has(neighbor_id):
					continue
				visited[neighbor_id] = true
				queue.append(neighbor_id)

		component.sort()
		components.append(component)

	return components

static func _distance_map(starts: Array[String], allowed_hexes: Dictionary, adjacency_map: Dictionary) -> Dictionary:
	if starts.is_empty():
		return {}
	var distances := {}
	var queue: Array[String] = starts.duplicate()
	for hex_id in starts:
		distances[hex_id] = 0

	while not queue.is_empty():
		var current := String(queue.pop_front())
		var current_distance := int(distances.get(current, 0))
		for neighbor_id in _neighbors_for(current, adjacency_map):
			if not allowed_hexes.has(neighbor_id):
				continue
			if distances.has(neighbor_id):
				continue
			distances[neighbor_id] = current_distance + 1
			queue.append(neighbor_id)
	return distances

static func _build_adjacency_map(known_hexes: Dictionary) -> Dictionary:
	var adjacency := {}
	for key_variant in known_hexes.keys():
		adjacency[String(key_variant)] = []

	for key_variant in known_hexes.keys():
		var hex_id := String(key_variant)
		var parsed_hex: Variant = _parse_hex_id(hex_id)
		if not (parsed_hex is Vector2i):
			continue
		for offset in DeploymentDataConverter.HEX_NEIGHBOR_OFFSETS:
			var neighbor_id := _hex_id((parsed_hex as Vector2i) + offset)
			if not known_hexes.has(neighbor_id):
				continue
			(adjacency[hex_id] as Array).append(neighbor_id)

	for hex_id in adjacency.keys():
		(adjacency[hex_id] as Array).sort()
	return adjacency

static func _neighbors_for(hex_id: String, adjacency_map: Dictionary) -> Array[String]:
	if not adjacency_map.has(hex_id):
		return []
	return adjacency_map[hex_id] as Array[String]

static func _subset_set(source: Dictionary, include: Dictionary) -> Dictionary:
	var subset := {}
	for key in source.keys():
		if include.has(key):
			subset[key] = true
	return subset

static func _array_to_set(values: Array[String]) -> Dictionary:
	var output := {}
	for value in values:
		output[value] = true
	return output

static func _min_hex_id(values: Array[String]) -> String:
	if values.is_empty():
		return ""
	var ordered := values.duplicate()
	ordered.sort()
	return String(ordered[0])

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
