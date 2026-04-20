extends Node
class_name GameState

enum Phase {
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

signal phase_changed(new_phase: Phase)

var current_phase: Phase = Phase.DIVISION_BUILDER
var players: Array[Dictionary] = []
var current_turn: int = 1
var territory_map: Dictionary = {}

func set_phase(phase: Phase) -> void:
	if current_phase == phase:
		return
	current_phase = phase
	emit_signal("phase_changed", current_phase)

func reset() -> void:
	current_phase = Phase.DIVISION_BUILDER
	players.clear()
	current_turn = 1
	territory_map.clear()
	emit_signal("phase_changed", current_phase)
