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
	emit_signal("phase_changed", current_phase)

func apply_map_payload(payload: Dictionary) -> void:
	terrain_map = (payload.get("terrain", {}) as Dictionary).duplicate(true)
	territory_map = (payload.get("territory", {}) as Dictionary).duplicate(true)
