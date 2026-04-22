extends Node

@onready var screen_container: Control = $ScreenContainer

const PHASE_SCENES := {
	GameState.Phase.MAIN_MENU: preload("res://scenes/main_menu/MainMenuScreen.tscn"),
	GameState.Phase.DIVISION_BUILDER: preload("res://scenes/division_builder/DivisionBuilderScreen.tscn"),
	GameState.Phase.MAP_SETUP: preload("res://scenes/map_setup/MapSetupScreen.tscn"),
	GameState.Phase.DEPLOYMENT_P1: preload("res://scenes/screens/DeploymentP1Screen.tscn"),
	GameState.Phase.DEPLOYMENT_P2: preload("res://scenes/screens/DeploymentP2Screen.tscn"),
	GameState.Phase.GAMEPLAY: preload("res://scenes/screens/GameplayScreen.tscn"),
	GameState.Phase.CASUALTY_ENTRY: preload("res://scenes/screens/CasualtyEntryScreen.tscn")
}

var current_screen: Control

func _ready() -> void:
	GameState.phase_changed.connect(_on_phase_changed)
	_swap_to_phase(GameState.current_phase)

func _on_phase_changed(phase: GameState.Phase) -> void:
	_swap_to_phase(phase)

func _swap_to_phase(phase: GameState.Phase) -> void:
	var scene_resource: PackedScene = PHASE_SCENES.get(phase)
	if scene_resource == null:
		push_warning("No screen scene configured for phase: %s" % str(phase))
		return

	if is_instance_valid(current_screen):
		current_screen.queue_free()

	current_screen = scene_resource.instantiate() as Control
	screen_container.add_child(current_screen)
