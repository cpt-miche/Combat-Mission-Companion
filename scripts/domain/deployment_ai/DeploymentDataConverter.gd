class_name DeploymentDataConverter
extends RefCounted

const HEX_NEIGHBOR_OFFSETS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(1, -1),
	Vector2i(0, -1),
	Vector2i(-1, 0),
	Vector2i(-1, 1),
	Vector2i(0, 1)
]

static func planner_terrain_for(raw_terrain: Variant) -> String:
	var normalized := String(raw_terrain).strip_edges().to_lower()
	if normalized.is_empty():
		return DeploymentTypes.TERRAIN_OPEN
	if TerrainCatalog.TERRAIN_IDS.has(normalized):
		return String(DeploymentTypes.TERRAIN_COMPATIBILITY.get(normalized, DeploymentTypes.TERRAIN_OPEN))
	return String(DeploymentTypes.TERRAIN_COMPATIBILITY.get(normalized, DeploymentTypes.TERRAIN_OPEN))

static func planner_role_for(raw_unit_type: Variant) -> String:
	var normalized := _normalized_unit_type_key(raw_unit_type)
	if normalized.is_empty():
		return DeploymentTypes.ROLE_INFANTRY
	return String(DeploymentTypes.UNIT_ROLE_COMPATIBILITY.get(normalized, DeploymentTypes.ROLE_INFANTRY))

static func _normalized_unit_type_key(raw_unit_type: Variant) -> String:
	if typeof(raw_unit_type) == TYPE_INT:
		return _unit_type_name_from_enum_value(int(raw_unit_type))
	return String(raw_unit_type).strip_edges().to_lower()

static func _unit_type_name_from_enum_value(unit_type_value: int) -> String:
	match unit_type_value:
		UnitType.Value.INFANTRY:
			return "infantry"
		UnitType.Value.TANK:
			return "tank"
		UnitType.Value.ENGINEER:
			return "engineer"
		UnitType.Value.ARTILLERY:
			return "artillery"
		UnitType.Value.RECON:
			return "recon"
		UnitType.Value.AIRBORNE:
			return "airborne"
		UnitType.Value.MECHANIZED:
			return "mechanized"
		UnitType.Value.MOTORIZED:
			return "motorized"
		UnitType.Value.ANTI_TANK:
			return "anti_tank"
		UnitType.Value.AIR_DEFENSE:
			return "air_defense"
		UnitType.Value.HEADQUARTERS:
			return "headquarters"
		_:
			return str(unit_type_value).strip_edges().to_lower()

static func map_payload_to_hexes(terrain_map: Dictionary, territory_map: Dictionary) -> Array[Dictionary]:
	var known_hexes := {}
	for key_variant in terrain_map.keys():
		known_hexes[String(key_variant).strip_edges()] = true
	for key_variant in territory_map.keys():
		known_hexes[String(key_variant).strip_edges()] = true

	var hexes: Array[Dictionary] = []
	var ordered_keys := known_hexes.keys()
	ordered_keys.sort_custom(func(a: Variant, b: Variant) -> bool:
		return String(a) < String(b)
	)

	for key_variant in ordered_keys:
		var key := String(key_variant)
		var coords: Variant = _parse_hex_key(key)
		if coords == null:
			continue

		var axial: Vector2i = coords
		var neighbor_ids: Array[String] = []
		for offset in HEX_NEIGHBOR_OFFSETS:
			var neighbor := axial + offset
			var neighbor_id := _hex_id(neighbor)
			if known_hexes.has(neighbor_id):
				neighbor_ids.append(neighbor_id)

		hexes.append(DeploymentTypes.make_hex(
			key,
			axial.x,
			axial.y,
			planner_terrain_for(terrain_map.get(key, TerrainCatalog.DEFAULT_TERRAIN_ID)),
			int(territory_map.get(key, 0)),
			neighbor_ids
		))

	return hexes

static func players_to_formations(players: Array[Dictionary]) -> Array[Dictionary]:
	var formations: Array[Dictionary] = []
	for player_index in players.size():
		var player: Dictionary = players[player_index]
		if typeof(player) != TYPE_DICTIONARY:
			continue
		var root: Variant = player.get("division_tree", {})
		_flatten_formation_tree(root, formations, "")
	return formations

static func players_to_deployable_elements(players: Array[Dictionary]) -> Array[Dictionary]:
	var elements: Array[Dictionary] = []
	for player_index in players.size():
		var player: Dictionary = players[player_index]
		if typeof(player) != TYPE_DICTIONARY:
			continue

		var deployments := player.get("deployments", {}) as Dictionary
		var deployment_index := _deployment_index_by_unit_id(deployments)
		var root: Variant = player.get("division_tree", {})
		_flatten_deployable_elements(root, player_index, "", deployment_index, elements)
	return elements

static func elements_grouped_by_hex(elements: Array[Dictionary]) -> Dictionary:
	var grouped := {}
	for element in elements:
		var hex_id := String(element.get("hexId", ""))
		if hex_id.is_empty():
			continue
		if not grouped.has(hex_id):
			grouped[hex_id] = []
		(grouped[hex_id] as Array).append(String(element.get("id", "")))
	return grouped

static func _flatten_formation_tree(node: Variant, output: Array[Dictionary], parent_id: String) -> void:
	if typeof(node) != TYPE_DICTIONARY:
		return

	var unit := node as Dictionary
	if unit.is_empty():
		return

	var formation_id := String(unit.get("id", ""))
	if formation_id.is_empty():
		return

	var child_ids: Array[String] = []
	for child_variant in unit.get("children", []):
		if typeof(child_variant) != TYPE_DICTIONARY:
			continue
		var child := child_variant as Dictionary
		var child_id := String(child.get("id", ""))
		if child_id.is_empty():
			continue
		child_ids.append(child_id)

	output.append(DeploymentTypes.make_formation(
		formation_id,
		String(unit.get("name", formation_id)),
		String(unit.get("type", "infantry")),
		String(unit.get("size", "company")),
		parent_id,
		child_ids,
		String(unit.get("status", "alive")).to_lower(),
		bool(unit.get("is_alive", String(unit.get("status", "alive")).to_lower() != "dead"))
	))

	for child_variant in unit.get("children", []):
		_flatten_formation_tree(child_variant, output, formation_id)

static func _flatten_deployable_elements(
	node: Variant,
	player_index: int,
	parent_id: String,
	deployment_index: Dictionary,
	output: Array[Dictionary]
) -> void:
	if typeof(node) != TYPE_DICTIONARY:
		return
	var unit := node as Dictionary
	if unit.is_empty():
		return

	var unit_id := String(unit.get("id", ""))
	if unit_id.is_empty():
		return

	var unit_type := _normalized_unit_type_key(unit.get("type", "infantry"))
	if unit_type == "headquarters":
		for child_variant in unit.get("children", []):
			_flatten_deployable_elements(child_variant, player_index, unit_id, deployment_index, output)
		return

	var deployed_hex_id := String(deployment_index.get(unit_id, ""))
	output.append(DeploymentTypes.make_deployable_element(
		unit_id,
		player_index,
		String(unit.get("name", unit_id)),
		planner_role_for(unit_type),
		String(unit.get("size", "company")),
		parent_id,
		deployed_hex_id,
		String(unit.get("status", "alive")).to_lower(),
		bool(unit.get("is_alive", String(unit.get("status", "alive")).to_lower() != "dead"))
	))

	for child_variant in unit.get("children", []):
		_flatten_deployable_elements(child_variant, player_index, unit_id, deployment_index, output)

static func _deployment_index_by_unit_id(deployments: Dictionary) -> Dictionary:
	var index := {}
	for key_variant in deployments.keys():
		var hex_id := String(key_variant)
		var deployed_unit: Variant = deployments[key_variant]
		if typeof(deployed_unit) != TYPE_DICTIONARY:
			continue
		var deployed := deployed_unit as Dictionary
		var unit_id := String(deployed.get("id", ""))
		if unit_id.is_empty():
			continue
		index[unit_id] = hex_id
	return index

static func _parse_hex_key(key: String) -> Variant:
	var parts := key.split(",")
	if parts.size() != 2:
		return null
	var q_text := parts[0].strip_edges()
	var r_text := parts[1].strip_edges()
	if not q_text.is_valid_int() or not r_text.is_valid_int():
		return null
	return Vector2i(int(q_text), int(r_text))

static func _hex_id(hex: Vector2i) -> String:
	return "%d,%d" % [hex.x, hex.y]
