extends Node

@onready var screen_container: Control = $ScreenContainer

const PHASE_SCENES := {
	GameState.Phase.MAIN_MENU: preload("res://scenes/main_menu/MainMenuScreen.tscn"),
	GameState.Phase.DIVISION_BUILDER: preload("res://scenes/division_builder/DivisionBuilderScreen.tscn"),
	GameState.Phase.MAP_SETUP: preload("res://scenes/map_setup/MapSetupScreen.tscn"),
	GameState.Phase.DEPLOYMENT_P1: preload("res://scenes/deployment/DeploymentScreen.tscn"),
	GameState.Phase.DEPLOYMENT_P2: preload("res://scenes/deployment/DeploymentScreen.tscn"),
	GameState.Phase.GAMEPLAY: preload("res://scenes/screens/GameplayScreen.tscn"),
	GameState.Phase.CASUALTY_ENTRY: preload("res://scenes/screens/CasualtyEntryScreen.tscn"),
	GameState.Phase.SCENARIO_EDITOR: preload("res://scenes/scenario_editor/ScenarioEditorScreen.tscn"),
	GameState.Phase.SCENARIO_REVIEW: preload("res://scenes/scenario_editor/ScenarioEditorScreen.tscn")
}
const GAMEPLAY_SCENE := preload("res://scenes/screens/GameplayScreen.tscn")
const BATTLE_RESOLUTION_SCENE := preload("res://scenes/screens/CasualtyEntryScreen.tscn")

var current_screen: Control
var battle_resolution_overlay: Control

func _ready() -> void:
	DisplaySettings.load_and_apply()
	DisplaySettings.connect_runtime_resize_notifications(get_tree().root)
	GameState.phase_changed.connect(_on_phase_changed)
	_swap_to_phase(GameState.current_phase)

func _on_phase_changed(phase: GameState.Phase) -> void:
	_swap_to_phase(phase)

func _swap_to_phase(phase: GameState.Phase) -> void:
	if phase == GameState.Phase.CASUALTY_ENTRY:
		_show_battle_resolution_overlay()
		return
	if phase == GameState.Phase.GAMEPLAY and is_instance_valid(battle_resolution_overlay):
		_hide_battle_resolution_overlay()
		DisplaySettings.reapply_runtime_settings()
		return

	_hide_battle_resolution_overlay()
	var scene_resource: PackedScene = PHASE_SCENES.get(phase)
	if scene_resource == null:
		push_warning("No screen scene configured for phase: %s" % str(phase))
		return

	_remove_current_screen()

	current_screen = scene_resource.instantiate() as Control
	screen_container.add_child(current_screen)
	DisplaySettings.reapply_runtime_settings()

func _show_battle_resolution_overlay() -> void:
	if is_instance_valid(battle_resolution_overlay):
		return
	if not is_instance_valid(current_screen) or not current_screen.has_method("set_battle_resolution_overlay_active"):
		_remove_current_screen()
		current_screen = GAMEPLAY_SCENE.instantiate() as Control
		screen_container.add_child(current_screen)
	current_screen.call("set_battle_resolution_overlay_active", true)
	battle_resolution_overlay = BATTLE_RESOLUTION_SCENE.instantiate() as Control
	if battle_resolution_overlay.has_signal("resolution_state_changed"):
		battle_resolution_overlay.connect("resolution_state_changed", _on_resolution_state_changed)
	screen_container.add_child(battle_resolution_overlay)
	DisplaySettings.reapply_runtime_settings()

func _hide_battle_resolution_overlay() -> void:
	if is_instance_valid(battle_resolution_overlay):
		battle_resolution_overlay.queue_free()
	battle_resolution_overlay = null
	if is_instance_valid(current_screen) and current_screen.has_method("set_battle_resolution_overlay_active"):
		current_screen.call("set_battle_resolution_overlay_active", false)

func _on_resolution_state_changed() -> void:
	if is_instance_valid(current_screen) and current_screen.has_method("sync_battle_resolution_context"):
		current_screen.call("sync_battle_resolution_context")
	if is_instance_valid(current_screen) and current_screen.has_method("autosave_battle_resolution_state"):
		current_screen.call("autosave_battle_resolution_state")

func _remove_current_screen() -> void:
	if not is_instance_valid(current_screen):
		return
	if current_screen.get_parent() == screen_container:
		screen_container.remove_child(current_screen)
	current_screen.queue_free()
	current_screen = null
