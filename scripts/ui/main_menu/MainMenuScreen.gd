extends Control

@onready var play_button: Button = %PlayButton
@onready var load_button: Button = %LoadButton
@onready var status_label: Label = %StatusLabel
@onready var nation_dialog: ConfirmationDialog = %NationDialog
@onready var map_dialog: ConfirmationDialog = %MapDialog
@onready var map_mode_selector: OptionButton = %MapModeSelector
@onready var saved_map_selector: OptionButton = %SavedMapSelector
@onready var map_size_label: Label = %MapSizeLabel
@onready var map_size_selector: OptionButton = %MapSizeSelector
@onready var map_selection_status_label: Label = %MapSelectionStatusLabel

var _pending_nation_id := "usa"

func _ready() -> void:
	play_button.pressed.connect(_on_play_pressed)
	load_button.pressed.connect(_on_load_pressed)
	nation_dialog.confirmed.connect(_on_play_as_usa)
	nation_dialog.canceled.connect(_on_play_as_germany)
	map_dialog.confirmed.connect(_on_map_selection_confirmed)
	map_mode_selector.item_selected.connect(_on_map_mode_selected)

func _on_play_pressed() -> void:
	nation_dialog.popup_centered()

func _on_play_as_usa() -> void:
	_open_map_selection_for("usa")

func _on_play_as_germany() -> void:
	_open_map_selection_for("germany")

func _open_map_selection_for(nation_id: String) -> void:
	_pending_nation_id = nation_id
	_configure_map_mode_selector()
	_configure_map_size_selector()
	_refresh_saved_map_selector()
	_refresh_map_dialog_ui()
	map_dialog.popup_centered()

func _start_new_division_builder_for(nation_id: String, selected_mode: int, selected_dimensions: Vector2i) -> void:
	GameState.reset()
	GameState.selected_nation_id = nation_id
	GameState.map_flow = selected_mode
	GameState.selected_map_name = ""
	if selected_mode == GameState.MapFlow.NEW_MAP:
		GameState.set_runtime_map_dimensions(selected_dimensions.x, selected_dimensions.y)
		GameState.terrain_map.clear()
		GameState.territory_map.clear()
		GameState.set_phase(GameState.Phase.DIVISION_BUILDER)
		return

	var map_name := _selected_saved_map_name()
	if map_name.is_empty():
		status_label.text = "No saved map selected."
		return
	var payload := SaveManager.load_map(map_name)
	if payload.is_empty():
		status_label.text = "Could not load map '%s'." % map_name
		return
	GameState.selected_map_name = map_name
	GameState.apply_map_payload(payload)
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
	# Preserve whose turn was in progress when the autosave was created.
	var loaded_active_player := int(payload.get("active_player", GameState.active_player))
	GameState.active_player = clampi(loaded_active_player, 0, 1)
	GameState.apply_map_payload(payload)
	GameState.pending_casualties = (payload.get("casualties", {}) as Dictionary).duplicate(true)
	GameState.gameplay_units = _deserialize_units(payload.get("units", {}) as Dictionary)

func _configure_map_mode_selector() -> void:
	map_mode_selector.clear()
	map_mode_selector.add_item("New Map", GameState.MapFlow.NEW_MAP)
	map_mode_selector.add_item("Edit Existing Map", GameState.MapFlow.EDIT_EXISTING_MAP)
	map_mode_selector.add_item("Play Saved Map", GameState.MapFlow.PLAY_SAVED_MAP)
	map_mode_selector.select(0)

func _refresh_saved_map_selector() -> void:
	saved_map_selector.clear()
	for map_name in SaveManager.list_maps():
		saved_map_selector.add_item(map_name)

func _configure_map_size_selector() -> void:
	map_size_selector.clear()
	var selected_size := MapGridConfig.normalize_size(GameState.selected_map_dimensions.x)
	if GameState.selected_map_dimensions.x != GameState.selected_map_dimensions.y:
		selected_size = MapGridConfig.default_columns()
	var selected_index := 0
	var sizes := MapGridConfig.allowed_sizes()
	for option_index in sizes.size():
		var size := sizes[option_index]
		map_size_selector.add_item("%dx%d" % [size, size], size)
		if size == selected_size:
			selected_index = option_index
	map_size_selector.select(selected_index)

func _on_map_mode_selected(_index: int) -> void:
	_refresh_map_dialog_ui()

func _refresh_map_dialog_ui() -> void:
	var mode := _selected_map_mode()
	var needs_saved_map := mode == GameState.MapFlow.EDIT_EXISTING_MAP or mode == GameState.MapFlow.PLAY_SAVED_MAP
	var needs_new_map_size := mode == GameState.MapFlow.NEW_MAP
	saved_map_selector.disabled = not needs_saved_map
	map_size_selector.disabled = not needs_new_map_size
	map_size_label.visible = needs_new_map_size
	map_size_selector.visible = needs_new_map_size
	if needs_saved_map and saved_map_selector.item_count == 0:
		map_dialog.get_ok_button().disabled = true
		map_selection_status_label.text = "No saved maps found. Save one in Map Setup first."
		return
	map_dialog.get_ok_button().disabled = false
	map_selection_status_label.text = ""

func _selected_map_mode() -> int:
	if map_mode_selector.item_count == 0:
		return GameState.MapFlow.NEW_MAP
	var selected := maxi(map_mode_selector.selected, 0)
	return int(map_mode_selector.get_item_id(selected))

func _selected_saved_map_name() -> String:
	if saved_map_selector.item_count == 0:
		return ""
	return saved_map_selector.get_item_text(maxi(saved_map_selector.selected, 0))

func _selected_map_dimensions() -> Vector2i:
	if map_size_selector.item_count == 0:
		var fallback_size := MapGridConfig.default_columns()
		return Vector2i(fallback_size, fallback_size)
	var selected_index := clampi(map_size_selector.selected, 0, map_size_selector.item_count - 1)
	var selected_size := int(map_size_selector.get_item_id(selected_index))
	var normalized_size := MapGridConfig.normalize_size(selected_size)
	return Vector2i(normalized_size, normalized_size)

func _on_map_selection_confirmed() -> void:
	var selected_mode := _selected_map_mode()
	var selected_dimensions := _selected_map_dimensions()
	if selected_mode == GameState.MapFlow.NEW_MAP and not MapGridConfig.is_allowed_size(selected_dimensions.x):
		var fallback_size := MapGridConfig.default_columns()
		selected_dimensions = Vector2i(fallback_size, fallback_size)
		map_selection_status_label.text = "Invalid map size selected. Using %dx%d." % [fallback_size, fallback_size]
	_start_new_division_builder_for(_pending_nation_id, selected_mode, selected_dimensions)

func _deserialize_units(serialized_units: Dictionary) -> Dictionary:
	var deserialized := {}
	for unit_id in serialized_units.keys():
		var unit := (serialized_units[unit_id] as Dictionary).duplicate(true)
		var hex_payload := unit.get("hex", {}) as Dictionary
		unit["hex"] = Vector2i(int(hex_payload.get("x", 0)), int(hex_payload.get("y", 0)))
		deserialized[unit_id] = unit
	return deserialized
