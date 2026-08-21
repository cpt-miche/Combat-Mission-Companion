extends Node

enum Step {
	DETAILS,
	MAP,
	PLAYER_1_FORCES,
	PLAYER_2_FORCES,
	PLAYER_1_DEPLOYMENT,
	PLAYER_2_DEPLOYMENT,
	REVIEW
}

var active := false
var current_step: Step = Step.DETAILS
var editor_side := 0
var scenario_ref: Dictionary = {}
var document: Dictionary = {}
var dirty := false

func start_new(details: Dictionary) -> void:
	var preserved_phase := GameState.current_phase
	GameState.reset(false)
	GameState.current_phase = preserved_phase
	active = true
	current_step = Step.MAP
	editor_side = 0
	scenario_ref = {"id": SaveManager.sanitize_name(String(details.get("name", "Untitled Scenario")))}
	document = {
		"scenario_version": SaveManager.SCENARIO_VERSION_CURRENT,
		"version": GameState.MAP_PAYLOAD_VERSION_CURRENT,
		"name": String(details.get("name", "Untitled Scenario")).strip_edges(),
		"briefing": String(details.get("briefing", "")).strip_edges(),
		"grid": {
			"columns": int(details.get("columns", MapGridConfig.default_columns())),
			"rows": int(details.get("rows", MapGridConfig.default_rows()))
		},
		"terrain": {},
		"territory": {},
		"objectives": {},
		"ai_doctrine": MatchSetupTypes.DEFAULT_AI_DOCTRINE,
		"difficulty": MatchSetupTypes.DEFAULT_DIFFICULTY,
		"players": [
			_player_document(0, String(details.get("player_1_name", "Player 1")), String(details.get("player_1_nation", "usa"))),
			_player_document(1, String(details.get("player_2_name", "Player 2")), String(details.get("player_2_nation", "germany")))
		]
	}
	dirty = true
	apply_to_game_state()

func begin_edit(payload: Dictionary, scenario_reference: Dictionary) -> void:
	var preserved_phase := GameState.current_phase
	GameState.reset(false)
	GameState.current_phase = preserved_phase
	active = true
	current_step = Step.DETAILS
	editor_side = 0
	scenario_ref = scenario_reference.duplicate(true)
	document = payload.duplicate(true)
	dirty = false
	apply_to_game_state()

func resume_draft(draft_payload: Dictionary, draft_id: String) -> bool:
	var scenario_variant: Variant = draft_payload.get("scenario", null)
	if not (scenario_variant is Dictionary):
		return false
	var preserved_phase := GameState.current_phase
	GameState.reset(false)
	GameState.current_phase = preserved_phase
	active = true
	current_step = clampi(int(draft_payload.get("current_step", Step.DETAILS)), Step.DETAILS, Step.REVIEW)
	editor_side = clampi(int(draft_payload.get("editor_side", 0)), 0, 1)
	scenario_ref = (draft_payload.get("scenario_ref", {"id": draft_id}) as Dictionary).duplicate(true)
	document = (scenario_variant as Dictionary).duplicate(true)
	dirty = false
	apply_to_game_state()
	return true

func clear() -> void:
	active = false
	current_step = Step.DETAILS
	editor_side = 0
	scenario_ref.clear()
	document.clear()
	dirty = false

func apply_to_game_state() -> void:
	if document.is_empty():
		return
	GameState.apply_map_payload(document)
	var raw_players := document.get("players", []) as Array
	var players: Array[Dictionary] = []
	for index in range(mini(raw_players.size(), 2)):
		if not (raw_players[index] is Dictionary):
			continue
		var player := (raw_players[index] as Dictionary).duplicate(true)
		player["controller"] = "human"
		players.append(player)
	GameState.players = players
	if not players.is_empty():
		GameState.selected_nation_id = String(players[0].get("nation_id", "usa"))
	GameState.map_flow = GameState.MapFlow.STARTING_SCENARIO
	GameState.selected_scenario_name = String(document.get("name", ""))
	GameState.gameplay_units.clear()
	GameState.gameplay_orders.clear()
	GameState.combat_log_entries.clear()
	GameState.pending_casualties.clear()

func capture_from_game_state() -> void:
	if not active:
		return
	document["scenario_version"] = SaveManager.SCENARIO_VERSION_CURRENT
	document["version"] = GameState.MAP_PAYLOAD_VERSION_CURRENT
	document["grid"] = {"columns": GameState.map_columns, "rows": GameState.map_rows}
	document["terrain"] = GameState.terrain_map.duplicate(true)
	document["territory"] = GameState.territory_map.duplicate(true)
	document["objectives"] = GameState.key_objectives.duplicate(true)
	document["ai_doctrine"] = String(GameState.selected_ai_doctrine)
	document["difficulty"] = String(GameState.selected_difficulty)
	var captured_players: Array[Dictionary] = []
	for index in range(mini(GameState.players.size(), 2)):
		var player := (GameState.players[index] as Dictionary).duplicate(true)
		player.erase("controller")
		if not player.has("nation_id"):
			player["nation_id"] = _nation_from_tree(player.get("division_tree", {}) as Dictionary, "usa" if index == 0 else "germany")
		captured_players.append(player)
	document["players"] = captured_players
	dirty = true

func update_details(details: Dictionary) -> void:
	document["name"] = String(details.get("name", document.get("name", "Untitled Scenario"))).strip_edges()
	document["briefing"] = String(details.get("briefing", document.get("briefing", ""))).strip_edges()
	var players := document.get("players", []) as Array
	for index in range(mini(players.size(), 2)):
		var player := players[index] as Dictionary
		player["name"] = String(details.get("player_%d_name" % (index + 1), player.get("name", "Player %d" % (index + 1)))).strip_edges()
		players[index] = player
	document["players"] = players
	GameState.selected_scenario_name = String(document.get("name", ""))
	dirty = true

func set_step(step: Step, side: int = -1) -> void:
	current_step = step
	if side >= 0:
		editor_side = clampi(side, 0, 1)
	dirty = true

func draft_id() -> String:
	var scenario_id := String(scenario_ref.get("id", ""))
	if not scenario_id.is_empty():
		return scenario_id
	return SaveManager.sanitize_name(String(document.get("name", "scenario_draft")))

func save_draft() -> bool:
	capture_from_game_state()
	var payload := {
		"draft_version": SaveManager.SCENARIO_DRAFT_VERSION_CURRENT,
		"current_step": int(current_step),
		"editor_side": editor_side,
		"scenario_ref": scenario_ref.duplicate(true),
		"scenario": document.duplicate(true)
	}
	var saved := SaveManager.save_scenario_draft(draft_id(), payload)
	if saved:
		dirty = false
	return saved

func reconcile_deployments(player_index: int) -> void:
	if player_index < 0 or player_index >= GameState.players.size():
		return
	var player := GameState.players[player_index] as Dictionary
	var unit_lookup := {}
	_collect_tree_units(player.get("division_tree", {}) as Dictionary, unit_lookup)
	var deployments := player.get("deployments", {}) as Dictionary
	var reconciled := {}
	for coordinate_variant in deployments.keys():
		var coordinate := String(coordinate_variant)
		var next_units: Array[Dictionary] = []
		for snapshot in _deployment_units(deployments[coordinate_variant]):
			var unit_id := String(snapshot.get("id", ""))
			if not unit_lookup.has(unit_id):
				continue
			var refreshed := snapshot.duplicate(true)
			var tree_unit := unit_lookup[unit_id] as Dictionary
			for field in ["template_id", "display_name", "short_name", "designation", "type", "role", "equipment_weight", "size", "is_attached", "status", "vehicles"]:
				if tree_unit.has(field):
					refreshed[field] = tree_unit[field]
			next_units.append(refreshed)
		if next_units.size() == 1:
			reconciled[coordinate] = next_units[0]
		elif next_units.size() > 1:
			reconciled[coordinate] = next_units
	player["deployments"] = reconciled
	GameState.players[player_index] = player
	dirty = true

func step_label() -> String:
	match current_step:
		Step.DETAILS: return "1/7  Scenario Details"
		Step.MAP: return "2/7  Map"
		Step.PLAYER_1_FORCES: return "3/7  Player 1 Forces"
		Step.PLAYER_2_FORCES: return "4/7  Player 2 Forces"
		Step.PLAYER_1_DEPLOYMENT: return "5/7  Player 1 Deployment"
		Step.PLAYER_2_DEPLOYMENT: return "6/7  Player 2 Deployment"
		Step.REVIEW: return "7/7  Review"
	return "Scenario Editor"

func _player_document(index: int, player_name: String, nation_id: String) -> Dictionary:
	return {
		"name": player_name if not player_name.strip_edges().is_empty() else "Player %d" % (index + 1),
		"nation_id": nation_id.strip_edges().to_lower(),
		"division_tree": {},
		"deployments": {}
	}

func _nation_from_tree(root: Dictionary, fallback: String) -> String:
	if root.has("nation"):
		return String(root.get("nation", fallback))
	return fallback

func _collect_tree_units(node: Dictionary, lookup: Dictionary) -> void:
	if node.is_empty():
		return
	var unit_id := String(node.get("id", ""))
	if not unit_id.is_empty():
		lookup[unit_id] = node
	for child_variant in node.get("children", []) as Array:
		if child_variant is Dictionary:
			_collect_tree_units(child_variant as Dictionary, lookup)

func _deployment_units(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if value is Dictionary:
		result.append(value as Dictionary)
	elif value is Array:
		for item in value as Array:
			if item is Dictionary:
				result.append(item as Dictionary)
	return result
