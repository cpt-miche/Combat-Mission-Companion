extends Node
enum Phase {
	MAIN_MENU,
	DIVISION_BUILDER,
	MAP_SETUP,
	DEPLOYMENT_P1,
	DEPLOYMENT_P2,
	GAMEPLAY,
	CASUALTY_ENTRY,
	SCENARIO_EDITOR,
	SCENARIO_REVIEW
}

enum TerritoryOwnership {
	NEUTRAL,
	PLAYER_1,
	PLAYER_2
}

enum MapFlow {
	NEW_MAP,
	EDIT_EXISTING_MAP,
	PLAY_SAVED_MAP,
	STARTING_SCENARIO
}

signal phase_changed(new_phase: Phase)
signal debug_mode_changed(enabled: bool, level: int)
const MAP_PAYLOAD_VERSION_CURRENT := 2
const AIDebugTypes = preload("res://scripts/systems/ai_debug/AIDebugTypes.gd")

var current_phase: Phase = Phase.MAIN_MENU
var players: Array[Dictionary] = []
var current_turn: int = 1
var territory_map: Dictionary = {}
var terrain_map: Dictionary = {}
var key_objectives: Dictionary = {}
var gameplay_units: Dictionary = {}
var gameplay_orders: Dictionary = {}
var combat_log_entries: Array[Dictionary] = []
var pending_casualties: Dictionary = {}
var selected_nation_id: String = "usa"
var active_player: int = 0
var map_flow: MapFlow = MapFlow.NEW_MAP
var selected_map_name: String = ""
var selected_scenario_name: String = ""
var selected_map_dimensions: Vector2i = Vector2i(MapGridConfig.default_columns(), MapGridConfig.default_rows())
var map_columns: int = MapGridConfig.default_columns()
var map_rows: int = MapGridConfig.default_rows()
var selected_ai_doctrine: String = MatchSetupTypes.DEFAULT_AI_DOCTRINE
var selected_difficulty: String = MatchSetupTypes.DEFAULT_DIFFICULTY
var deployment_ai_debug: Dictionary = {}
var operational_ai_debug: Dictionary = {}
var operational_ai_state: Dictionary = {}
var ai_formation_state: Dictionary = {}
var scout_intel_by_observer: Dictionary = {}
var operational_ai_enabled: bool = false
var ai_debug_enabled: bool = false
var ai_debug_level: int = AIDebugTypes.DebugLevel.OFF
var debug_mode_enabled: bool = false
var debug_mode_level: int = 0

func set_phase(phase: Phase) -> void:
	if current_phase == phase:
		return
	current_phase = phase
	emit_signal("phase_changed", current_phase)

func reset(emit_phase_change: bool = true) -> void:
	current_phase = Phase.MAIN_MENU
	players.clear()
	current_turn = 1
	territory_map.clear()
	terrain_map.clear()
	key_objectives.clear()
	gameplay_units.clear()
	gameplay_orders.clear()
	combat_log_entries.clear()
	pending_casualties.clear()
	selected_nation_id = "usa"
	active_player = 0
	map_flow = MapFlow.NEW_MAP
	selected_map_name = ""
	selected_scenario_name = ""
	selected_map_dimensions = Vector2i(MapGridConfig.default_columns(), MapGridConfig.default_rows())
	map_columns = MapGridConfig.default_columns()
	map_rows = MapGridConfig.default_rows()
	selected_ai_doctrine = MatchSetupTypes.DEFAULT_AI_DOCTRINE
	selected_difficulty = MatchSetupTypes.DEFAULT_DIFFICULTY
	deployment_ai_debug.clear()
	operational_ai_debug.clear()
	operational_ai_state.clear()
	ai_formation_state.clear()
	scout_intel_by_observer.clear()
	operational_ai_enabled = false
	ai_debug_enabled = false
	ai_debug_level = AIDebugTypes.DebugLevel.OFF
	disable_debug_mode()
	if emit_phase_change:
		emit_signal("phase_changed", current_phase)


func enable_debug_mode(level: int) -> void:
	debug_mode_level = clampi(level, 1, 3)
	debug_mode_enabled = true
	ai_debug_enabled = true
	ai_debug_level = AIDebugTypes.gameplay_debug_to_ai_level(debug_mode_level)
	emit_signal("debug_mode_changed", debug_mode_enabled, debug_mode_level)

func disable_debug_mode() -> void:
	debug_mode_enabled = false
	debug_mode_level = 0
	ai_debug_enabled = false
	ai_debug_level = AIDebugTypes.DebugLevel.OFF
	deployment_ai_debug.clear()
	operational_ai_debug.clear()
	operational_ai_state.clear()
	emit_signal("debug_mode_changed", debug_mode_enabled, debug_mode_level)

func toggle_debug_mode_with_level(level: int) -> void:
	if debug_mode_enabled:
		disable_debug_mode()
		return
	enable_debug_mode(level)

func get_debug_mode_label() -> String:
	if not debug_mode_enabled:
		return "OFF"
	return "L%d" % debug_mode_level

func get_ai_debug_config() -> Dictionary:
	return {
		"enabled": ai_debug_enabled,
		"level": ai_debug_level
	}

func is_ai_debug_active(required_level: int = AIDebugTypes.DebugLevel.L1) -> bool:
	if not ai_debug_enabled:
		return false
	return ai_debug_level >= required_level

func apply_map_payload(payload: Dictionary) -> bool:
	var map_payload := _extract_map_payload(payload)
	if not validate_map_payload(map_payload):
		push_warning("Map payload uses an unsupported or incomplete schema.")
		return false
	_apply_grid_payload(map_payload.get("grid"))
	terrain_map = (map_payload.get("terrain") as Dictionary).duplicate(true)
	territory_map = (map_payload.get("territory") as Dictionary).duplicate(true)
	key_objectives = (map_payload.get("objectives") as Dictionary).duplicate(true)
	selected_ai_doctrine = String(map_payload.get("ai_doctrine"))
	selected_difficulty = String(map_payload.get("difficulty"))
	return true

func set_runtime_map_dimensions(columns: int, rows: int) -> void:
	map_columns = maxi(columns, 1)
	map_rows = maxi(rows, 1)
	selected_map_dimensions = Vector2i(map_columns, map_rows)

func validate_map_payload(payload: Dictionary) -> bool:
	if int(payload.get("version", -1)) != MAP_PAYLOAD_VERSION_CURRENT:
		return false
	if not (payload.get("name") is String):
		return false
	for field_name in ["grid", "terrain", "territory", "objectives"]:
		if not (payload.get(field_name) is Dictionary):
			return false
	var grid := payload.get("grid") as Dictionary
	if not _is_whole_json_number(grid.get("columns")) or not _is_whole_json_number(grid.get("rows")):
		return false
	var columns := int(grid.get("columns"))
	var rows := int(grid.get("rows"))
	if not MapGridConfig.is_allowed_size(columns) or not MapGridConfig.is_allowed_size(rows):
		return false
	if String(payload.get("ai_doctrine", "")) not in MatchSetupTypes.AI_DOCTRINES:
		return false
	if String(payload.get("difficulty", "")) not in MatchSetupTypes.DIFFICULTIES:
		return false
	for coordinate_key_variant in (payload.get("terrain") as Dictionary).keys():
		var coordinate_key := String(coordinate_key_variant)
		if not _is_hex_key_in_bounds(coordinate_key, columns, rows) or String((payload.get("terrain") as Dictionary)[coordinate_key_variant]) not in TerrainCatalog.TERRAIN_IDS:
			return false
	for coordinate_key_variant in (payload.get("territory") as Dictionary).keys():
		var coordinate_key := String(coordinate_key_variant)
		var owner := int((payload.get("territory") as Dictionary)[coordinate_key_variant])
		if not _is_hex_key_in_bounds(coordinate_key, columns, rows) or owner < TerritoryOwnership.NEUTRAL or owner > TerritoryOwnership.PLAYER_2:
			return false
	for coordinate_key_variant in (payload.get("objectives") as Dictionary).keys():
		var coordinate_key := String(coordinate_key_variant)
		var objective_variant: Variant = (payload.get("objectives") as Dictionary)[coordinate_key_variant]
		if not _is_hex_key_in_bounds(coordinate_key, columns, rows) or not (objective_variant is Dictionary):
			return false
		if String((objective_variant as Dictionary).get("priority", "")) not in ["primary", "secondary"]:
			return false
	return true

func _extract_map_payload(payload: Dictionary) -> Dictionary:
	var map_container: Variant = payload.get("map", null)
	if map_container is Dictionary:
		return (map_container as Dictionary).duplicate(true)
	return payload.duplicate(true)

func _apply_grid_payload(raw_grid: Variant) -> void:
	var grid := raw_grid as Dictionary
	set_runtime_map_dimensions(int(grid.get("columns")), int(grid.get("rows")))

func _is_valid_hex_key(coordinate_key: String) -> bool:
	var parts := coordinate_key.split(",")
	if parts.size() != 2:
		return false
	return parts[0].is_valid_int() and parts[1].is_valid_int()

func _is_hex_key_in_bounds(coordinate_key: String, columns: int, rows: int) -> bool:
	if not _is_valid_hex_key(coordinate_key):
		return false
	var parts := coordinate_key.split(",")
	var column := int(parts[0])
	var row := int(parts[1])
	return column >= 0 and row >= 0 and column < columns and row < rows

func _is_whole_json_number(value: Variant) -> bool:
	if value is int:
		return true
	return value is float and is_equal_approx(float(value), floorf(float(value)))

func is_unit_alive(unit: Dictionary) -> bool:
	return String(unit.get("status", "")).to_lower() == "alive"

func mark_unit_status(unit_id: String, status: String, owner_hint: int = -1) -> bool:
	if unit_id.is_empty():
		return false
	var normalized_status := status.to_lower()
	var updated := false

	if _update_gameplay_unit_status(unit_id, normalized_status):
		updated = true

	for player_index in range(players.size()):
		if owner_hint >= 0 and player_index != owner_hint:
			continue
		if _update_player_unit_status(player_index, unit_id, normalized_status):
			updated = true

	return updated

func mark_vehicle_status(unit_id: String, vehicle_id: String, status: String, owner_hint: int = -1) -> bool:
	if unit_id.is_empty() or vehicle_id.is_empty():
		return false
	var normalized_status := status.to_lower()
	var updated := false
	if _update_gameplay_vehicle_status(unit_id, vehicle_id, normalized_status):
		updated = true
	for player_index in range(players.size()):
		if owner_hint >= 0 and player_index != owner_hint:
			continue
		var player := players[player_index] as Dictionary
		var division_tree := player.get("division_tree", {}) as Dictionary
		if _update_vehicle_status_recursive(division_tree, unit_id, vehicle_id, normalized_status):
			player["division_tree"] = division_tree
			updated = true
		var deployments := player.get("deployments", {}) as Dictionary
		if _update_deployment_vehicle_status(deployments, unit_id, vehicle_id, normalized_status):
			player["deployments"] = deployments
			updated = true
		players[player_index] = player
	return updated

func mark_unit_subtree_status(unit_id: String, status: String, owner_hint: int = -1) -> Array[String]:
	var changed_ids: Array[String] = []
	if unit_id.is_empty():
		return changed_ids
	var normalized_status := status.to_lower()
	for player_index in range(players.size()):
		if owner_hint >= 0 and player_index != owner_hint:
			continue
		var player := players[player_index] as Dictionary
		var division_tree := player.get("division_tree", {}) as Dictionary
		var target := _find_unit_node_recursive(division_tree, unit_id)
		if target.is_empty():
			continue
		_mark_subtree_status_recursive(target, normalized_status, changed_ids)
		player["division_tree"] = division_tree
		var deployments := player.get("deployments", {}) as Dictionary
		for changed_id in changed_ids:
			_update_deployment_unit_status(deployments, changed_id, normalized_status)
			_update_gameplay_unit_status(changed_id, normalized_status, true)
		player["deployments"] = deployments
		players[player_index] = player
	changed_ids.sort()
	return changed_ids

func reconcile_formation_statuses(owner_hint: int = -1) -> Array[String]:
	var changed_ids: Array[String] = []
	for player_index in range(players.size()):
		if owner_hint >= 0 and player_index != owner_hint:
			continue
		var player := players[player_index] as Dictionary
		var division_tree := player.get("division_tree", {}) as Dictionary
		if division_tree.is_empty():
			continue
		var player_changed_ids: Array[String] = []
		_reconcile_dead_parent_statuses_recursive(division_tree, player_changed_ids)
		if player_changed_ids.is_empty():
			continue
		player["division_tree"] = division_tree
		var deployments := player.get("deployments", {}) as Dictionary
		for unit_id in player_changed_ids:
			_update_deployment_unit_status(deployments, unit_id, "dead")
			_update_gameplay_unit_status(unit_id, "dead")
			if not changed_ids.has(unit_id):
				changed_ids.append(unit_id)
		player["deployments"] = deployments
		players[player_index] = player
	changed_ids.sort()
	return changed_ids

func _reconcile_dead_parent_statuses_recursive(node: Dictionary, changed_ids: Array[String]) -> void:
	var children_variant: Variant = node.get("children", [])
	var children := children_variant as Array if children_variant is Array else []
	var has_combat_children := false
	var all_combat_children_dead := true
	for i in range(children.size()):
		if typeof(children[i]) != TYPE_DICTIONARY:
			continue
		var child := children[i] as Dictionary
		_reconcile_dead_parent_statuses_recursive(child, changed_ids)
		children[i] = child
		if _is_headquarters_unit_node(child):
			continue
		has_combat_children = true
		if is_unit_alive(child):
			all_combat_children_dead = false
	node["children"] = children
	var vehicles := node.get("vehicles", []) as Array
	var has_vehicles := not vehicles.is_empty()
	var all_vehicles_dead := true
	for vehicle_variant in vehicles:
		if vehicle_variant is Dictionary and is_unit_alive(vehicle_variant as Dictionary):
			all_vehicles_dead = false
	_refresh_vehicle_strength_fields(node)
	var has_combat_components := has_combat_children or has_vehicles
	var all_combat_components_dead := (not has_combat_children or all_combat_children_dead) and (not has_vehicles or all_vehicles_dead)
	if not has_combat_components or not all_combat_components_dead or not is_unit_alive(node):
		return
	node["status"] = "dead"
	var unit_id := String(node.get("id", ""))
	if not unit_id.is_empty() and not changed_ids.has(unit_id):
		changed_ids.append(unit_id)

func _is_headquarters_unit_node(node: Dictionary) -> bool:
	if String(node.get("role", "")).strip_edges().to_lower() == "headquarters":
		return true
	var raw_type: Variant = node.get("type", "")
	if typeof(raw_type) == TYPE_INT:
		return int(raw_type) == UnitType.Value.HEADQUARTERS
	return String(raw_type).strip_edges().to_lower() == "headquarters"

func _update_vehicle_status_recursive(node: Dictionary, unit_id: String, vehicle_id: String, status: String) -> bool:
	if node.is_empty():
		return false
	if String(node.get("id", "")) == unit_id and _update_vehicle_status_on_unit(node, vehicle_id, status):
		return true
	var children := node.get("children", []) as Array
	for index in range(children.size()):
		if not (children[index] is Dictionary):
			continue
		var child := children[index] as Dictionary
		if _update_vehicle_status_recursive(child, unit_id, vehicle_id, status):
			children[index] = child
			node["children"] = children
			return true
	return false

func _update_gameplay_unit_status(unit_id: String, status: String, include_vehicles: bool = false) -> bool:
	for gameplay_id_variant in gameplay_units.keys():
		var gameplay_id := String(gameplay_id_variant)
		var gameplay_unit := gameplay_units[gameplay_id] as Dictionary
		if _update_runtime_unit_status_recursive(gameplay_unit, unit_id, status, include_vehicles):
			gameplay_units[gameplay_id] = gameplay_unit
			return true
	return false

func _update_runtime_unit_status_recursive(unit: Dictionary, unit_id: String, status: String, include_vehicles: bool) -> bool:
	if String(unit.get("id", "")) == unit_id:
		if include_vehicles:
			_set_unit_and_vehicle_status(unit, status)
		else:
			unit["status"] = status
		return true
	var components := unit.get("combined_components", []) as Array
	for index in range(components.size()):
		if not (components[index] is Dictionary):
			continue
		var component := components[index] as Dictionary
		if _update_runtime_unit_status_recursive(component, unit_id, status, include_vehicles):
			components[index] = component
			unit["combined_components"] = components
			return true
	return false

func _update_gameplay_vehicle_status(unit_id: String, vehicle_id: String, status: String) -> bool:
	for gameplay_id_variant in gameplay_units.keys():
		var gameplay_id := String(gameplay_id_variant)
		var gameplay_unit := gameplay_units[gameplay_id] as Dictionary
		if _update_runtime_vehicle_status_recursive(gameplay_unit, unit_id, vehicle_id, status):
			gameplay_units[gameplay_id] = gameplay_unit
			return true
	return false

func _update_runtime_vehicle_status_recursive(unit: Dictionary, unit_id: String, vehicle_id: String, status: String) -> bool:
	if String(unit.get("id", "")) == unit_id and _update_vehicle_status_on_unit(unit, vehicle_id, status):
		return true
	var components := unit.get("combined_components", []) as Array
	for index in range(components.size()):
		if not (components[index] is Dictionary):
			continue
		var component := components[index] as Dictionary
		if _update_runtime_vehicle_status_recursive(component, unit_id, vehicle_id, status):
			components[index] = component
			unit["combined_components"] = components
			return true
	return false

func _update_vehicle_status_on_unit(unit: Dictionary, vehicle_id: String, status: String) -> bool:
	var vehicles := unit.get("vehicles", []) as Array
	for index in range(vehicles.size()):
		if not (vehicles[index] is Dictionary):
			continue
		var vehicle := vehicles[index] as Dictionary
		if String(vehicle.get("id", "")) != vehicle_id:
			continue
		vehicle["status"] = status
		vehicles[index] = vehicle
		unit["vehicles"] = vehicles
		_refresh_vehicle_strength_fields(unit)
		return true
	return false

func _update_deployment_vehicle_status(deployments: Dictionary, unit_id: String, vehicle_id: String, status: String) -> bool:
	var updated := false
	for key in deployments.keys():
		var units: Array = [deployments[key]] if deployments[key] is Dictionary else (deployments[key] as Array if deployments[key] is Array else [])
		var key_updated := false
		for index in range(units.size()):
			if not (units[index] is Dictionary):
				continue
			var unit := units[index] as Dictionary
			if String(unit.get("id", "")) != unit_id:
				continue
			if _update_vehicle_status_on_unit(unit, vehicle_id, status):
				units[index] = unit
				updated = true
				key_updated = true
		if key_updated:
			deployments[key] = units[0] if deployments[key] is Dictionary and units.size() == 1 else units
	return updated

func _refresh_vehicle_strength_fields(unit: Dictionary) -> void:
	var vehicles := unit.get("vehicles", []) as Array
	if vehicles.is_empty():
		unit.erase("live_sub_units")
		unit.erase("max_sub_units")
		return
	var living := 0
	for vehicle_variant in vehicles:
		if vehicle_variant is Dictionary and is_unit_alive(vehicle_variant as Dictionary):
			living += 1
	unit["live_sub_units"] = living
	unit["max_sub_units"] = vehicles.size()

func _find_unit_node_recursive(node: Dictionary, unit_id: String) -> Dictionary:
	if node.is_empty():
		return {}
	if String(node.get("id", "")) == unit_id:
		return node
	for child_variant in node.get("children", []) as Array:
		if child_variant is Dictionary:
			var found := _find_unit_node_recursive(child_variant as Dictionary, unit_id)
			if not found.is_empty():
				return found
	return {}

func _mark_subtree_status_recursive(node: Dictionary, status: String, changed_ids: Array[String]) -> void:
	_set_unit_and_vehicle_status(node, status)
	var unit_id := String(node.get("id", ""))
	if not unit_id.is_empty() and not changed_ids.has(unit_id):
		changed_ids.append(unit_id)
	var children := node.get("children", []) as Array
	for index in range(children.size()):
		if children[index] is Dictionary:
			var child := children[index] as Dictionary
			_mark_subtree_status_recursive(child, status, changed_ids)
			children[index] = child
	node["children"] = children

func _set_unit_and_vehicle_status(unit: Dictionary, status: String) -> void:
	unit["status"] = status
	var vehicles := unit.get("vehicles", []) as Array
	for index in range(vehicles.size()):
		if vehicles[index] is Dictionary:
			var vehicle := vehicles[index] as Dictionary
			vehicle["status"] = status
			vehicles[index] = vehicle
	unit["vehicles"] = vehicles
	_refresh_vehicle_strength_fields(unit)

func _update_player_unit_status(player_index: int, unit_id: String, normalized_status: String) -> bool:
	if player_index < 0 or player_index >= players.size():
		return false
	var player := players[player_index] as Dictionary
	var updated := false

	var division_tree := player.get("division_tree", {}) as Dictionary
	if not division_tree.is_empty() and _update_division_tree_unit_status_recursive(division_tree, unit_id, normalized_status):
		player["division_tree"] = division_tree
		updated = true

	var deployments := player.get("deployments", {}) as Dictionary
	if _update_deployment_unit_status(deployments, unit_id, normalized_status):
		player["deployments"] = deployments
		updated = true

	if updated:
		players[player_index] = player
	return updated

func _update_division_tree_unit_status_recursive(node: Dictionary, unit_id: String, normalized_status: String) -> bool:
	var updated := false
	if String(node.get("id", "")) == unit_id:
		node["status"] = normalized_status
		updated = true

	var children := node.get("children", []) as Array
	for i in range(children.size()):
		if typeof(children[i]) != TYPE_DICTIONARY:
			continue
		var child := children[i] as Dictionary
		if _update_division_tree_unit_status_recursive(child, unit_id, normalized_status):
			children[i] = child
			updated = true
	if updated:
		node["children"] = children
	return updated

func _update_deployment_unit_status(deployments: Dictionary, unit_id: String, normalized_status: String) -> bool:
	var updated := false
	for key in deployments.keys():
		var unit_variant: Variant = deployments[key]
		if typeof(unit_variant) == TYPE_DICTIONARY:
			var unit := unit_variant as Dictionary
			if String(unit.get("id", "")) != unit_id:
				continue
			unit["status"] = normalized_status
			deployments[key] = unit
			updated = true
			continue
		if typeof(unit_variant) != TYPE_ARRAY:
			continue
		var units := unit_variant as Array
		var units_updated := false
		for i in range(units.size()):
			if typeof(units[i]) != TYPE_DICTIONARY:
				continue
			var unit := units[i] as Dictionary
			if String(unit.get("id", "")) != unit_id:
				continue
			unit["status"] = normalized_status
			units[i] = unit
			units_updated = true
		if units_updated:
			deployments[key] = units
			updated = true
	return updated
