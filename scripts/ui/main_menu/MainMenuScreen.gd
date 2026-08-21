extends Control

const OrderSystem = preload("res://scripts/systems/OrderSystem.gd")

@onready var play_button: Button = %PlayButton
@onready var load_button: Button = %LoadButton
@onready var scenario_editor_button: Button = %ScenarioEditorButton
@onready var display_button: Button = %DisplayButton
@onready var status_label: Label = %StatusLabel
@onready var nation_dialog: Window = %NationDialog
@onready var play_as_us_button: Button = %PlayAsUsButton
@onready var play_as_germany_button: Button = %PlayAsGermanyButton
@onready var cancel_nation_button: Button = %CancelNationButton
@onready var map_dialog: ConfirmationDialog = %MapDialog
@onready var map_mode_selector: OptionButton = %MapModeSelector
@onready var saved_map_label: Label = %SavedMapLabel
@onready var saved_map_selector: OptionButton = %SavedMapSelector
@onready var delete_scenario_button: Button = %DeleteScenarioButton
@onready var map_size_label: Label = %MapSizeLabel
@onready var map_size_selector: OptionButton = %MapSizeSelector
@onready var map_selection_status_label: Label = %MapSelectionStatusLabel
@onready var delete_scenario_dialog: ConfirmationDialog = %DeleteScenarioDialog
@onready var display_dialog: ConfirmationDialog = %DisplayDialog
@onready var resolution_selector: OptionButton = %ResolutionSelector
@onready var window_mode_toggle: CheckBox = %WindowModeToggle
@onready var ui_scale_mode_selector: OptionButton = %UiScaleModeSelector
@onready var ui_scale_value_selector: OptionButton = %UiScaleValueSelector
@onready var revert_display_button: Button = %RevertDisplayButton
@onready var display_status_label: Label = %DisplayStatusLabel

var _pending_nation_id := "usa"
var _pending_delete_scenario_name := ""
var _last_applied_display_settings := {
	"preset_id": DisplaySettings.DEFAULT_PRESET_ID,
	"window_mode": DisplaySettings.DEFAULT_WINDOW_MODE,
	"ui_scale_mode": DisplaySettings.DEFAULT_UI_SCALE_MODE,
	"ui_scale_value": DisplaySettings.DEFAULT_UI_SCALE_VALUE
}
var _pre_apply_display_settings := {
	"preset_id": DisplaySettings.DEFAULT_PRESET_ID,
	"window_mode": DisplaySettings.DEFAULT_WINDOW_MODE,
	"ui_scale_mode": DisplaySettings.DEFAULT_UI_SCALE_MODE,
	"ui_scale_value": DisplaySettings.DEFAULT_UI_SCALE_VALUE
}
var _has_pending_display_revert := false

func _ready() -> void:
	play_button.pressed.connect(_on_play_pressed)
	load_button.pressed.connect(_on_load_pressed)
	scenario_editor_button.pressed.connect(_on_scenario_editor_pressed)
	display_button.pressed.connect(_on_display_pressed)
	play_as_us_button.pressed.connect(_on_play_as_usa)
	play_as_germany_button.pressed.connect(_on_play_as_germany)
	cancel_nation_button.pressed.connect(_on_nation_dialog_closed)
	nation_dialog.close_requested.connect(_on_nation_dialog_closed)
	map_dialog.confirmed.connect(_on_map_selection_confirmed)
	map_mode_selector.item_selected.connect(_on_map_mode_selected)
	delete_scenario_button.pressed.connect(_on_delete_scenario_pressed)
	delete_scenario_dialog.confirmed.connect(_on_delete_scenario_confirmed)
	display_dialog.confirmed.connect(_on_apply_display_settings_pressed)
	display_dialog.canceled.connect(_on_display_dialog_closed)
	ui_scale_mode_selector.item_selected.connect(_on_ui_scale_mode_selected)
	revert_display_button.pressed.connect(_on_revert_display_pressed)
	_configure_display_controls()
	_refresh_display_state_from_runtime()

func _on_play_pressed() -> void:
	nation_dialog.popup_centered()

func _on_scenario_editor_pressed() -> void:
	ScenarioEditorState.clear()
	GameState.set_phase(GameState.Phase.SCENARIO_EDITOR)

func _on_play_as_usa() -> void:
	nation_dialog.hide()
	_open_map_selection_for("usa")

func _on_play_as_germany() -> void:
	nation_dialog.hide()
	_open_map_selection_for("germany")

func _on_nation_dialog_closed() -> void:
	nation_dialog.hide()

func _open_map_selection_for(nation_id: String) -> void:
	_pending_nation_id = nation_id
	_configure_map_mode_selector()
	_configure_map_size_selector()
	_refresh_saved_selector_for_mode()
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
		status_label.text = SaveManager.get_last_load_error()
		return
	GameState.selected_map_name = map_name
	if not GameState.apply_map_payload(payload):
		status_label.text = "Saved map '%s' has invalid map data." % map_name
		GameState.reset()
		return
	GameState.set_phase(GameState.Phase.DIVISION_BUILDER)

func _on_load_pressed() -> void:
	var payload := SaveManager.load_current_game()
	if payload.is_empty():
		status_label.text = SaveManager.get_last_load_error()
		return

	_apply_loaded_payload(payload)
	var loaded_phase := _loaded_game_phase()
	status_label.text = "Loaded save. Resuming battle resolution..." if loaded_phase == GameState.Phase.CASUALTY_ENTRY else "Loaded save. Entering gameplay..."
	GameState.set_phase(loaded_phase)

func _loaded_game_phase() -> GameState.Phase:
	if not GameState.pending_casualties.is_empty():
		return GameState.Phase.CASUALTY_ENTRY
	return GameState.Phase.GAMEPLAY

func _apply_loaded_payload(payload: Dictionary) -> void:
	GameState.current_turn = int(payload.get("turn_number", 1))
	# Preserve whose turn was in progress when the autosave was created.
	var loaded_active_player := int(payload.get("active_player", GameState.active_player))
	GameState.active_player = clampi(loaded_active_player, 0, 1)
	var raw_players := payload.get("players", []) as Array
	if not raw_players.is_empty():
		var loaded_players: Array[Dictionary] = []
		for player_variant in raw_players:
			if player_variant is Dictionary:
				loaded_players.append((player_variant as Dictionary).duplicate(true))
		GameState.players = loaded_players
	if not GameState.apply_map_payload(payload):
		push_error("Validated current-game save failed map application.")
		GameState.reset()
		return
	GameState.pending_casualties = (payload.get("casualties", {}) as Dictionary).duplicate(true)
	GameState.gameplay_units = _deserialize_units(payload.get("units", {}) as Dictionary)
	GameState.gameplay_orders = _deserialize_orders(payload.get("orders", {}) as Dictionary)
	GameState.ai_formation_state = (payload.get("ai_formation_state", {}) as Dictionary).duplicate(true)
	GameState.scout_intel_by_observer = (payload.get("scout_intel_by_observer", {}) as Dictionary).duplicate(true)
	GameState.combat_log_entries.clear()
	for entry_variant in payload.get("combat_log_entries", []) as Array:
		if entry_variant is Dictionary:
			GameState.combat_log_entries.append((entry_variant as Dictionary).duplicate(true))
	_apply_ai_debug_payload(payload.get("ai_debug", {}))

func _apply_ai_debug_payload(raw_ai_debug: Variant) -> void:
	var ai_debug_payload := raw_ai_debug as Dictionary
	if ai_debug_payload == null:
		GameState.disable_debug_mode()
		return

	var enabled := bool(ai_debug_payload.get("enabled", false))
	var level := clampi(int(ai_debug_payload.get("level", 1)), 1, 3)
	if enabled:
		GameState.enable_debug_mode(level)
		return
	GameState.disable_debug_mode()

func _configure_map_mode_selector() -> void:
	map_mode_selector.clear()
	map_mode_selector.add_item("New Map", GameState.MapFlow.NEW_MAP)
	map_mode_selector.add_item("Edit Existing Map", GameState.MapFlow.EDIT_EXISTING_MAP)
	map_mode_selector.add_item("Play Saved Map", GameState.MapFlow.PLAY_SAVED_MAP)
	map_mode_selector.add_item("Play Starting Scenario", GameState.MapFlow.STARTING_SCENARIO)
	map_mode_selector.select(0)

func _refresh_saved_map_selector() -> void:
	saved_map_selector.clear()
	for map_name in SaveManager.list_maps():
		saved_map_selector.add_item(map_name)

func _refresh_saved_scenario_selector() -> void:
	saved_map_selector.clear()
	for scenario_file_name in SaveManager.list_scenarios():
		var payload := SaveManager.load_scenario(scenario_file_name)
		if payload.is_empty():
			continue
		var display_name := String(payload.get("name", scenario_file_name)).strip_edges()
		if display_name.is_empty():
			display_name = scenario_file_name
		var players := payload.get("players", []) as Array
		for player_index in range(mini(players.size(), 2)):
			if not (players[player_index] is Dictionary):
				continue
			var player := players[player_index] as Dictionary
			if String(player.get("nation_id", "")).strip_edges().to_lower() != _pending_nation_id.strip_edges().to_lower():
				continue
			var force_name := String(player.get("name", "Player %d" % (player_index + 1)))
			saved_map_selector.add_item("%s — as %s" % [display_name, force_name])
			saved_map_selector.set_item_metadata(saved_map_selector.item_count - 1, {"scenario_id": scenario_file_name, "human_side": player_index})

func _refresh_saved_selector_for_mode() -> void:
	if _selected_map_mode() == GameState.MapFlow.STARTING_SCENARIO:
		_refresh_saved_scenario_selector()
		return
	_refresh_saved_map_selector()

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
	_refresh_saved_selector_for_mode()
	_refresh_map_dialog_ui()

func _refresh_map_dialog_ui() -> void:
	var mode := _selected_map_mode()
	var needs_saved_map := mode == GameState.MapFlow.EDIT_EXISTING_MAP or mode == GameState.MapFlow.PLAY_SAVED_MAP
	var needs_scenario := mode == GameState.MapFlow.STARTING_SCENARIO
	var needs_saved_selection := needs_saved_map or needs_scenario
	var needs_new_map_size := mode == GameState.MapFlow.NEW_MAP
	saved_map_label.text = "Starting scenario" if needs_scenario else "Saved map"
	saved_map_selector.disabled = not needs_saved_selection
	delete_scenario_button.visible = needs_scenario
	delete_scenario_button.disabled = not needs_scenario or saved_map_selector.item_count == 0
	map_size_selector.disabled = not needs_new_map_size
	map_size_label.visible = needs_new_map_size
	map_size_selector.visible = needs_new_map_size
	if needs_saved_selection and saved_map_selector.item_count == 0:
		map_dialog.get_ok_button().disabled = true
		map_selection_status_label.text = "No starting scenarios found for this side." if needs_scenario else "No saved maps found. Save one in Map Setup first."
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
	var selected_index := maxi(saved_map_selector.selected, 0)
	var metadata: Variant = saved_map_selector.get_item_metadata(selected_index)
	if metadata is Dictionary:
		return String((metadata as Dictionary).get("scenario_id", ""))
	if metadata != null and not String(metadata).is_empty():
		return String(metadata)
	return saved_map_selector.get_item_text(selected_index)

func _selected_starting_scenario_ref() -> Dictionary:
	if saved_map_selector.item_count == 0:
		return {}
	var selected_index := clampi(saved_map_selector.selected, 0, saved_map_selector.item_count - 1)
	var metadata: Variant = saved_map_selector.get_item_metadata(selected_index)
	return (metadata as Dictionary).duplicate(true) if metadata is Dictionary else {}

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
	if selected_mode == GameState.MapFlow.STARTING_SCENARIO:
		var scenario_ref := _selected_starting_scenario_ref()
		_load_starting_scenario(String(scenario_ref.get("scenario_id", "")), int(scenario_ref.get("human_side", -1)))
		return
	var selected_dimensions := _selected_map_dimensions()
	if selected_mode == GameState.MapFlow.NEW_MAP and not MapGridConfig.is_allowed_size(selected_dimensions.x):
		var fallback_size := MapGridConfig.default_columns()
		selected_dimensions = Vector2i(fallback_size, fallback_size)
		map_selection_status_label.text = "Invalid map size selected. Using %dx%d." % [fallback_size, fallback_size]
	_start_new_division_builder_for(_pending_nation_id, selected_mode, selected_dimensions)

func _load_starting_scenario(scenario_name: String, human_side: int) -> bool:
	if scenario_name.is_empty():
		status_label.text = "No starting scenario selected."
		return false
	var payload := SaveManager.load_scenario(scenario_name)
	if payload.is_empty():
		status_label.text = SaveManager.get_last_load_error()
		return false
	if not SaveManager.validate_scenario_payload(payload):
		status_label.text = "Starting scenario '%s' is incomplete or invalid." % scenario_name
		return false
	var raw_players := payload.get("players", []) as Array
	if raw_players.size() != 2 or human_side < 0 or human_side >= raw_players.size():
		status_label.text = "Starting scenario '%s' has invalid side data." % scenario_name
		return false
	var runtime_players: Array[Dictionary] = []
	for player_index in range(2):
		if not (raw_players[player_index] is Dictionary):
			status_label.text = "Starting scenario '%s' has invalid force data." % scenario_name
			return false
		var player := (raw_players[player_index] as Dictionary).duplicate(true)
		player["controller"] = "human" if player_index == human_side else "ai"
		runtime_players.append(player)

	GameState.reset(false)
	if not GameState.apply_map_payload(payload):
		status_label.text = "Starting scenario '%s' has invalid map data." % scenario_name
		GameState.reset(false)
		return false
	GameState.players = runtime_players
	GameState.selected_nation_id = String(runtime_players[human_side].get("nation_id", _pending_nation_id))
	GameState.map_flow = GameState.MapFlow.STARTING_SCENARIO
	GameState.selected_scenario_name = String(payload.get("name", scenario_name)).strip_edges()
	GameState.active_player = 0
	GameState.current_turn = 1
	ScenarioEditorState.clear()
	map_dialog.hide()
	GameState.set_phase(GameState.Phase.GAMEPLAY)
	return true

func _on_delete_scenario_pressed() -> void:
	if _selected_map_mode() != GameState.MapFlow.STARTING_SCENARIO:
		return
	_pending_delete_scenario_name = String(_selected_starting_scenario_ref().get("scenario_id", ""))
	if _pending_delete_scenario_name.is_empty():
		map_selection_status_label.text = "No starting scenario selected."
		return
	delete_scenario_dialog.dialog_text = "Delete starting scenario '%s'?" % saved_map_selector.get_item_text(maxi(saved_map_selector.selected, 0))
	delete_scenario_dialog.popup_centered()

func _on_delete_scenario_confirmed() -> void:
	if _pending_delete_scenario_name.is_empty():
		return
	var deleted_name := _pending_delete_scenario_name
	_pending_delete_scenario_name = ""
	if not SaveManager.delete_scenario(deleted_name):
		map_selection_status_label.text = "Failed to delete starting scenario '%s'." % deleted_name
		return
	_refresh_saved_scenario_selector()
	_refresh_map_dialog_ui()
	if saved_map_selector.item_count > 0:
		map_selection_status_label.text = "Deleted starting scenario '%s'." % deleted_name

func _deserialize_units(serialized_units: Dictionary) -> Dictionary:
	var deserialized := {}
	for unit_id in serialized_units.keys():
		var unit := _deserialize_unit_snapshot(serialized_units[unit_id] as Dictionary)
		deserialized[unit_id] = unit
	return deserialized

func _deserialize_unit_snapshot(serialized_unit: Dictionary) -> Dictionary:
	var unit := serialized_unit.duplicate(true)
	var hex_variant: Variant = unit.get("hex", {})
	if hex_variant is Dictionary:
		var hex_payload := hex_variant as Dictionary
		unit["hex"] = Vector2i(int(hex_payload.get("x", 0)), int(hex_payload.get("y", 0)))
	var components: Array[Dictionary] = []
	for component_variant in unit.get("combined_components", []) as Array:
		if component_variant is Dictionary:
			components.append(_deserialize_unit_snapshot(component_variant as Dictionary))
	if unit.has("combined_components"):
		unit["combined_components"] = components
	return unit

func _deserialize_orders(serialized_orders: Dictionary) -> Dictionary:
	var deserialized := {}
	for unit_id in serialized_orders.keys():
		var raw_order := serialized_orders[unit_id] as Dictionary
		if raw_order == null:
			continue
		var order := raw_order.duplicate(true)
		var path: Array[Vector2i] = []
		for waypoint in order.get("path", []):
			if typeof(waypoint) == TYPE_DICTIONARY:
				var hex_payload := waypoint as Dictionary
				path.append(Vector2i(int(hex_payload.get("x", 0)), int(hex_payload.get("y", 0))))
		order["path"] = path
		order["unit_id"] = String(order.get("unit_id", unit_id))
		order["type"] = int(order.get("type", OrderSystem.OrderType.MOVE))
		if order.has("target_unit_id"):
			order["target_unit_id"] = String(order.get("target_unit_id", ""))
		deserialized[unit_id] = order
	return deserialized

func _configure_display_controls() -> void:
	resolution_selector.clear()
	var preset_options := [
		{"label": "1280x720 (720p)", "id": DisplaySettings.PRESET_ID_720P},
		{"label": "1920x1080 (1080p)", "id": DisplaySettings.PRESET_ID_1080P},
		{"label": "2560x1440 (1440p)", "id": DisplaySettings.PRESET_ID_1440P}
	]
	for option in preset_options:
		resolution_selector.add_item(String(option["label"]))
		resolution_selector.set_item_metadata(resolution_selector.item_count - 1, String(option["id"]))

	ui_scale_mode_selector.clear()
	ui_scale_mode_selector.add_item("Auto")
	ui_scale_mode_selector.set_item_metadata(0, DisplaySettings.UI_SCALE_MODE_AUTO)
	ui_scale_mode_selector.add_item("Manual")
	ui_scale_mode_selector.set_item_metadata(1, DisplaySettings.UI_SCALE_MODE_MANUAL)

	ui_scale_value_selector.clear()
	for scale_value in DisplaySettings.get_available_manual_ui_scales():
		var as_float := float(scale_value)
		ui_scale_value_selector.add_item("%d%%" % int(round(as_float * 100.0)))
		ui_scale_value_selector.set_item_metadata(ui_scale_value_selector.item_count - 1, as_float)

func _refresh_display_state_from_runtime() -> void:
	_last_applied_display_settings = {
		"preset_id": DisplaySettings.get_selected_preset_id(),
		"window_mode": DisplaySettings.get_selected_window_mode(),
		"ui_scale_mode": DisplaySettings.get_selected_ui_scale_mode(),
		"ui_scale_value": DisplaySettings.get_selected_ui_scale_value()
	}
	if not _has_pending_display_revert:
		_pre_apply_display_settings = _last_applied_display_settings.duplicate(true)
	_select_resolution_in_ui(String(_last_applied_display_settings.get("preset_id", DisplaySettings.DEFAULT_PRESET_ID)))
	var mode := String(_last_applied_display_settings.get("window_mode", DisplaySettings.DEFAULT_WINDOW_MODE))
	window_mode_toggle.button_pressed = mode == DisplaySettings.WINDOW_MODE_FULLSCREEN
	_select_ui_scale_mode_in_ui(String(_last_applied_display_settings.get("ui_scale_mode", DisplaySettings.DEFAULT_UI_SCALE_MODE)))
	_select_ui_scale_value_in_ui(float(_last_applied_display_settings.get("ui_scale_value", DisplaySettings.DEFAULT_UI_SCALE_VALUE)))
	_refresh_ui_scale_controls_state()
	revert_display_button.disabled = not _has_pending_display_revert
	display_status_label.text = ""

func _on_display_pressed() -> void:
	if _has_pending_display_revert:
		_select_resolution_in_ui(String(_last_applied_display_settings.get("preset_id", DisplaySettings.DEFAULT_PRESET_ID)))
		var mode := String(_last_applied_display_settings.get("window_mode", DisplaySettings.DEFAULT_WINDOW_MODE))
		window_mode_toggle.button_pressed = mode == DisplaySettings.WINDOW_MODE_FULLSCREEN
		_select_ui_scale_mode_in_ui(String(_last_applied_display_settings.get("ui_scale_mode", DisplaySettings.DEFAULT_UI_SCALE_MODE)))
		_select_ui_scale_value_in_ui(float(_last_applied_display_settings.get("ui_scale_value", DisplaySettings.DEFAULT_UI_SCALE_VALUE)))
		_refresh_ui_scale_controls_state()
		revert_display_button.disabled = false
	else:
		_refresh_display_state_from_runtime()
	display_dialog.popup_centered()

func _on_apply_display_settings_pressed() -> void:
	var requested_preset_id := _selected_resolution_preset_id()
	var requested_mode := _selected_window_mode_from_ui()
	var requested_ui_scale_mode := _selected_ui_scale_mode_from_ui()
	var requested_ui_scale_value := _selected_ui_scale_value_from_ui()
	_pre_apply_display_settings = _last_applied_display_settings.duplicate(true)
	var applied := DisplaySettings.set_display_settings(requested_preset_id, requested_mode, requested_ui_scale_mode, requested_ui_scale_value, true)
	var applied_preset_id := String(applied.get("preset_id", DisplaySettings.DEFAULT_PRESET_ID))
	var applied_mode := String(applied.get("window_mode", DisplaySettings.DEFAULT_WINDOW_MODE))
	var applied_ui_scale_mode := String(applied.get("ui_scale_mode", DisplaySettings.DEFAULT_UI_SCALE_MODE))
	var applied_ui_scale_value := float(applied.get("ui_scale_value", DisplaySettings.DEFAULT_UI_SCALE_VALUE))
	var fallback_used := applied_preset_id != requested_preset_id or applied_mode != requested_mode or applied_ui_scale_mode != requested_ui_scale_mode or not is_equal_approx(applied_ui_scale_value, requested_ui_scale_value)
	_last_applied_display_settings = {
		"preset_id": applied_preset_id,
		"window_mode": applied_mode,
		"ui_scale_mode": applied_ui_scale_mode,
		"ui_scale_value": applied_ui_scale_value
	}
	_select_resolution_in_ui(applied_preset_id)
	window_mode_toggle.button_pressed = applied_mode == DisplaySettings.WINDOW_MODE_FULLSCREEN
	_select_ui_scale_mode_in_ui(applied_ui_scale_mode)
	_select_ui_scale_value_in_ui(applied_ui_scale_value)
	_refresh_ui_scale_controls_state()
	_has_pending_display_revert = true
	revert_display_button.disabled = false
	var usability_warning := _validate_hit_targets_for_scene()
	if fallback_used:
		display_status_label.text = "Applied with fallback: %s, %s mode, UI scale %.0f%%." % [applied_preset_id.to_upper(), applied_mode, DisplaySettings.get_effective_ui_scale() * 100.0]
	elif usability_warning.is_empty():
		display_status_label.text = "Display settings applied. Hit targets validated."
	else:
		display_status_label.text = usability_warning

func _on_revert_display_pressed() -> void:
	var previous_preset := String(_pre_apply_display_settings.get("preset_id", DisplaySettings.DEFAULT_PRESET_ID))
	var previous_mode := String(_pre_apply_display_settings.get("window_mode", DisplaySettings.DEFAULT_WINDOW_MODE))
	var previous_ui_scale_mode := String(_pre_apply_display_settings.get("ui_scale_mode", DisplaySettings.DEFAULT_UI_SCALE_MODE))
	var previous_ui_scale_value := float(_pre_apply_display_settings.get("ui_scale_value", DisplaySettings.DEFAULT_UI_SCALE_VALUE))
	var applied := DisplaySettings.set_display_settings(previous_preset, previous_mode, previous_ui_scale_mode, previous_ui_scale_value, true)
	_last_applied_display_settings = {
		"preset_id": String(applied.get("preset_id", DisplaySettings.DEFAULT_PRESET_ID)),
		"window_mode": String(applied.get("window_mode", DisplaySettings.DEFAULT_WINDOW_MODE)),
		"ui_scale_mode": String(applied.get("ui_scale_mode", DisplaySettings.DEFAULT_UI_SCALE_MODE)),
		"ui_scale_value": float(applied.get("ui_scale_value", DisplaySettings.DEFAULT_UI_SCALE_VALUE))
	}
	_select_resolution_in_ui(String(applied.get("preset_id", DisplaySettings.DEFAULT_PRESET_ID)))
	window_mode_toggle.button_pressed = String(applied.get("window_mode", DisplaySettings.DEFAULT_WINDOW_MODE)) == DisplaySettings.WINDOW_MODE_FULLSCREEN
	_select_ui_scale_mode_in_ui(String(applied.get("ui_scale_mode", DisplaySettings.DEFAULT_UI_SCALE_MODE)))
	_select_ui_scale_value_in_ui(float(applied.get("ui_scale_value", DisplaySettings.DEFAULT_UI_SCALE_VALUE)))
	_refresh_ui_scale_controls_state()
	_has_pending_display_revert = false
	display_status_label.text = "Reverted to last applied settings."
	revert_display_button.disabled = true

func _on_ui_scale_mode_selected(_index: int) -> void:
	_refresh_ui_scale_controls_state()

func _on_display_dialog_closed() -> void:
	display_status_label.text = ""
	revert_display_button.disabled = not _has_pending_display_revert

func _selected_resolution_preset_id() -> String:
	if resolution_selector.item_count == 0:
		return DisplaySettings.DEFAULT_PRESET_ID
	var selected_index := clampi(resolution_selector.selected, 0, resolution_selector.item_count - 1)
	return String(resolution_selector.get_item_metadata(selected_index))


func _select_ui_scale_mode_in_ui(ui_scale_mode: String) -> void:
	for item_index in ui_scale_mode_selector.item_count:
		if String(ui_scale_mode_selector.get_item_metadata(item_index)) == ui_scale_mode:
			ui_scale_mode_selector.select(item_index)
			return
	ui_scale_mode_selector.select(0)

func _select_ui_scale_value_in_ui(ui_scale_value: float) -> void:
	for item_index in ui_scale_value_selector.item_count:
		if is_equal_approx(float(ui_scale_value_selector.get_item_metadata(item_index)), ui_scale_value):
			ui_scale_value_selector.select(item_index)
			return
	ui_scale_value_selector.select(0)

func _selected_ui_scale_mode_from_ui() -> String:
	if ui_scale_mode_selector.item_count == 0:
		return DisplaySettings.DEFAULT_UI_SCALE_MODE
	var selected_index := clampi(ui_scale_mode_selector.selected, 0, ui_scale_mode_selector.item_count - 1)
	return String(ui_scale_mode_selector.get_item_metadata(selected_index))

func _selected_ui_scale_value_from_ui() -> float:
	if ui_scale_value_selector.item_count == 0:
		return DisplaySettings.DEFAULT_UI_SCALE_VALUE
	var selected_index := clampi(ui_scale_value_selector.selected, 0, ui_scale_value_selector.item_count - 1)
	return float(ui_scale_value_selector.get_item_metadata(selected_index))

func _refresh_ui_scale_controls_state() -> void:
	ui_scale_value_selector.disabled = _selected_ui_scale_mode_from_ui() != DisplaySettings.UI_SCALE_MODE_MANUAL

func _validate_hit_targets_for_scene() -> String:
	var interactive_controls: Array = []
	_collect_interactive_controls(get_tree().root, interactive_controls)
	var effective_ui_scale := DisplaySettings.get_effective_ui_scale()
	var undersized_count := 0
	for control in interactive_controls:
		var minimum_size := (control as Control).get_combined_minimum_size()
		var rendered_height := minimum_size.y * effective_ui_scale
		if rendered_height < 44.0:
			undersized_count += 1
	if undersized_count == 0:
		return ""
	return "Warning: %d control(s) are below a 44px minimum hit target at %.0f%% UI scale." % [undersized_count, effective_ui_scale * 100.0]

func _collect_interactive_controls(node: Node, output: Array) -> void:
	if node is BaseButton or node is OptionButton:
		output.append(node)
	for child in node.get_children():
		_collect_interactive_controls(child, output)

func _selected_window_mode_from_ui() -> String:
	if window_mode_toggle.button_pressed:
		return DisplaySettings.WINDOW_MODE_FULLSCREEN
	return DisplaySettings.WINDOW_MODE_WINDOWED

func _select_resolution_in_ui(preset_id: String) -> void:
	for idx in resolution_selector.item_count:
		if String(resolution_selector.get_item_metadata(idx)) == preset_id:
			resolution_selector.select(idx)
			return
	if resolution_selector.item_count > 0:
		resolution_selector.select(0)
