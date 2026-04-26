extends Node
enum Phase {
	MAIN_MENU,
	DIVISION_BUILDER,
	MAP_SETUP,
	DEPLOYMENT_P1,
	DEPLOYMENT_P2,
	GAMEPLAY,
	CASUALTY_ENTRY
}

enum TerritoryOwnership {
	NEUTRAL,
	PLAYER_1,
	PLAYER_2
}

enum MapFlow {
	NEW_MAP,
	EDIT_EXISTING_MAP,
	PLAY_SAVED_MAP
}

signal phase_changed(new_phase: Phase)
const MAP_PAYLOAD_VERSION_CURRENT := 1
const AIDebugTypes = preload("res://scripts/systems/ai_debug/AIDebugTypes.gd")

var current_phase: Phase = Phase.MAIN_MENU
var players: Array[Dictionary] = []
var current_turn: int = 1
var territory_map: Dictionary = {}
var terrain_map: Dictionary = {}
var gameplay_units: Dictionary = {}
var combat_log_entries: Array[Dictionary] = []
var pending_casualties: Dictionary = {}
var selected_nation_id: String = "usa"
var active_player: int = 0
var map_flow: MapFlow = MapFlow.NEW_MAP
var selected_map_name: String = ""
var selected_map_dimensions: Vector2i = Vector2i(MapGridConfig.default_columns(), MapGridConfig.default_rows())
var map_columns: int = MapGridConfig.default_columns()
var map_rows: int = MapGridConfig.default_rows()
var deployment_ai_debug: Dictionary = {}
var operational_ai_debug: Dictionary = {}
var operational_ai_state: Dictionary = {}
var operational_ai_enabled: bool = false
var ai_debug_enabled: bool = false
var ai_debug_level: int = AIDebugTypes.DebugLevel.OFF

func set_phase(phase: Phase) -> void:
	if current_phase == phase:
		return
	current_phase = phase
	emit_signal("phase_changed", current_phase)

func reset() -> void:
	current_phase = Phase.MAIN_MENU
	players.clear()
	current_turn = 1
	territory_map.clear()
	terrain_map.clear()
	gameplay_units.clear()
	combat_log_entries.clear()
	pending_casualties.clear()
	selected_nation_id = "usa"
	active_player = 0
	map_flow = MapFlow.NEW_MAP
	selected_map_name = ""
	selected_map_dimensions = Vector2i(MapGridConfig.default_columns(), MapGridConfig.default_rows())
	map_columns = MapGridConfig.default_columns()
	map_rows = MapGridConfig.default_rows()
	deployment_ai_debug.clear()
	operational_ai_debug.clear()
	operational_ai_state.clear()
	operational_ai_enabled = false
	ai_debug_enabled = false
	ai_debug_level = AIDebugTypes.DebugLevel.OFF
	emit_signal("phase_changed", current_phase)

func get_ai_debug_config() -> Dictionary:
	return {
		"enabled": ai_debug_enabled,
		"level": ai_debug_level
	}

func is_ai_debug_active(required_level: int = AIDebugTypes.DebugLevel.ERROR) -> bool:
	if not ai_debug_enabled:
		return false
	return ai_debug_level >= required_level

func apply_map_payload(payload: Dictionary) -> void:
	var map_payload := _extract_map_payload(payload)
	if not validate_map_payload(map_payload):
		push_warning("Map payload failed validation. Falling back to defaults.")
	var migrated_payload := _migrate_map_payload(map_payload)
	_apply_grid_payload(migrated_payload.get("grid", null))
	terrain_map = _sanitize_terrain_map(migrated_payload.get("terrain", {}))
	territory_map = _sanitize_territory_map(migrated_payload.get("territory", {}))

func set_runtime_map_dimensions(columns: int, rows: int) -> void:
	map_columns = maxi(columns, 1)
	map_rows = maxi(rows, 1)
	selected_map_dimensions = Vector2i(map_columns, map_rows)

func validate_map_payload(payload: Dictionary) -> bool:
	if payload.is_empty():
		return false
	if payload.has("grid") and not (payload.get("grid") is Dictionary):
		return false
	if payload.has("terrain") and not (payload.get("terrain") is Dictionary):
		return false
	if payload.has("territory") and not (payload.get("territory") is Dictionary):
		return false
	return true

func _extract_map_payload(payload: Dictionary) -> Dictionary:
	var map_container: Variant = payload.get("map", null)
	if map_container is Dictionary:
		var extracted := (map_container as Dictionary).duplicate(true)
		if not extracted.has("grid") and payload.get("grid") is Dictionary:
			extracted["grid"] = (payload.get("grid", {}) as Dictionary).duplicate(true)
		if not extracted.has("terrain") and payload.get("terrain") is Dictionary:
			extracted["terrain"] = (payload.get("terrain", {}) as Dictionary).duplicate(true)
		if not extracted.has("territory") and payload.get("territory") is Dictionary:
			extracted["territory"] = (payload.get("territory", {}) as Dictionary).duplicate(true)
		return extracted
	return payload.duplicate(true)

func _migrate_map_payload(payload: Dictionary) -> Dictionary:
	var working := payload.duplicate(true)
	var payload_version := int(working.get("version", 0))
	if payload_version > MAP_PAYLOAD_VERSION_CURRENT:
		push_warning("Map payload version %d is newer than supported %d. Attempting best-effort load." % [payload_version, MAP_PAYLOAD_VERSION_CURRENT])
		return working

	while payload_version < MAP_PAYLOAD_VERSION_CURRENT:
		working = _run_map_migration(payload_version, working)
		payload_version += 1

	working["version"] = MAP_PAYLOAD_VERSION_CURRENT
	return working

func _run_map_migration(from_version: int, payload: Dictionary) -> Dictionary:
	match from_version:
		0:
			return payload.duplicate(true)
		_:
			return payload.duplicate(true)

func _apply_grid_payload(raw_grid: Variant) -> void:
	var grid := raw_grid as Dictionary
	var default_columns := MapGridConfig.default_columns()
	var default_rows := MapGridConfig.default_rows()
	if grid == null or grid.is_empty():
		set_runtime_map_dimensions(default_columns, default_rows)
		return
	var raw_columns := int(grid.get("columns", default_columns))
	var raw_rows := int(grid.get("rows", default_rows))
	var columns := MapGridConfig.normalize_size(raw_columns, default_columns)
	var rows := MapGridConfig.normalize_size(raw_rows, default_rows)
	if columns != raw_columns or rows != raw_rows:
		push_warning("Map payload grid dimensions are missing/invalid (%s x %s). Falling back to %d x %d." % [str(raw_columns), str(raw_rows), columns, rows])
	set_runtime_map_dimensions(columns, rows)

func _sanitize_terrain_map(raw_terrain: Variant) -> Dictionary:
	var sanitized := {}
	var terrain_payload := raw_terrain as Dictionary
	if terrain_payload == null:
		return sanitized

	for key_variant in terrain_payload.keys():
		var coordinate_key := str(key_variant).strip_edges()
		if not _is_valid_hex_key(coordinate_key):
			continue
		var normalized_terrain := TerrainCatalog.normalize_terrain_id(str(terrain_payload[key_variant]))
		sanitized[coordinate_key] = normalized_terrain
	return sanitized

func _sanitize_territory_map(raw_territory: Variant) -> Dictionary:
	var sanitized := {}
	var territory_payload := raw_territory as Dictionary
	if territory_payload == null:
		return sanitized

	for key_variant in territory_payload.keys():
		var coordinate_key := str(key_variant).strip_edges()
		if not _is_valid_hex_key(coordinate_key):
			continue
		var value := int(territory_payload[key_variant])
		if value < TerritoryOwnership.NEUTRAL or value > TerritoryOwnership.PLAYER_2:
			value = TerritoryOwnership.NEUTRAL
		sanitized[coordinate_key] = value
	return sanitized

func _is_valid_hex_key(coordinate_key: String) -> bool:
	var parts := coordinate_key.split(",")
	if parts.size() != 2:
		return false
	return parts[0].is_valid_int() and parts[1].is_valid_int()
