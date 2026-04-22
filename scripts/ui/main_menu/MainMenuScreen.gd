extends Control

@onready var play_button: Button = %PlayButton
@onready var load_button: Button = %LoadButton
@onready var status_label: Label = %StatusLabel
@onready var nation_dialog: ConfirmationDialog = %NationDialog

func _ready() -> void:
	play_button.pressed.connect(_on_play_pressed)
	load_button.pressed.connect(_on_load_pressed)
	nation_dialog.confirmed.connect(_on_play_as_usa)
	nation_dialog.canceled.connect(_on_play_as_germany)

func _on_play_pressed() -> void:
	nation_dialog.popup_centered()

func _on_play_as_usa() -> void:
	_start_new_division_builder_for("usa")

func _on_play_as_germany() -> void:
	_start_new_division_builder_for("germany")

func _start_new_division_builder_for(nation_id: String) -> void:
	GameState.reset()
	GameState.selected_nation_id = nation_id
	GameState.set_phase(GameState.Phase.DIVISION_BUILDER)

func _on_load_pressed() -> void:
	var payload := SaveManager.load_current_game()
	if payload.is_empty():
		status_label.text = "No save file found."
		return

	_apply_loaded_payload(payload)
	status_label.text = "Loaded save. Entering gameplay..."
	GameState.set_phase(GameState.Phase.GAMEPLAY)

func _apply_loaded_payload(payload: Dictionary) -> void:
	GameState.current_turn = int(payload.get("turn_number", 1))
	GameState.terrain_map = (payload.get("terrain", {}) as Dictionary).duplicate(true)
	GameState.territory_map = (payload.get("territory", {}) as Dictionary).duplicate(true)
	GameState.pending_casualties = (payload.get("casualties", {}) as Dictionary).duplicate(true)
	GameState.gameplay_units = _deserialize_units(payload.get("units", {}) as Dictionary)

func _deserialize_units(serialized_units: Dictionary) -> Dictionary:
	var deserialized := {}
	for unit_id in serialized_units.keys():
		var unit := (serialized_units[unit_id] as Dictionary).duplicate(true)
		var hex_payload := unit.get("hex", {}) as Dictionary
		unit["hex"] = Vector2i(int(hex_payload.get("x", 0)), int(hex_payload.get("y", 0)))
		deserialized[unit_id] = unit
	return deserialized
