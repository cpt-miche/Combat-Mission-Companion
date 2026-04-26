extends Control

@onready var play_button: Button = %PlayButton
@onready var load_button: Button = %LoadButton
@onready var display_button: Button = %DisplayButton
@onready var status_label: Label = %StatusLabel
@onready var nation_dialog: ConfirmationDialog = %NationDialog
@onready var map_dialog: ConfirmationDialog = %MapDialog
@onready var map_mode_selector: OptionButton = %MapModeSelector
@onready var saved_map_selector: OptionButton = %SavedMapSelector
@onready var map_size_label: Label = %MapSizeLabel
@onready var map_size_selector: OptionButton = %MapSizeSelector
@onready var map_selection_status_label: Label = %MapSelectionStatusLabel
@onready var display_dialog: ConfirmationDialog = %DisplayDialog
@onready var resolution_selector: OptionButton = %ResolutionSelector
@onready var window_mode_toggle: CheckBox = %WindowModeToggle
@onready var ui_scale_mode_selector: OptionButton = %UiScaleModeSelector
@onready var ui_scale_value_selector: OptionButton = %UiScaleValueSelector
@onready var revert_display_button: Button = %RevertDisplayButton
@onready var display_status_label: Label = %DisplayStatusLabel

var _pending_nation_id := "usa"
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
	display_button.pressed.connect(_on_display_pressed)
	nation_dialog.confirmed.connect(_on_play_as_usa)
	nation_dialog.canceled.connect(_on_play_as_germany)
	map_dialog.confirmed.connect(_on_map_selection_confirmed)
	map_mode_selector.item_selected.connect(_on_map_mode_selected)
	display_dialog.confirmed.connect(_on_apply_display_settings_pressed)
	display_dialog.canceled.connect(_on_display_dialog_closed)
	ui_scale_mode_selector.item_selected.connect(_on_ui_scale_mode_selected)
	revert_display_button.pressed.connect(_on_revert_display_pressed)
	_configure_display_controls()
	_refresh_display_state_from_runtime()

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
		var normalized_status := String(unit.get("status", "")).to_lower()
		if normalized_status.is_empty():
			normalized_status = "alive" if bool(unit.get("is_alive", true)) else "dead"
		unit["status"] = normalized_status
		unit["is_alive"] = bool(unit.get("is_alive", normalized_status != "dead"))
		deserialized[unit_id] = unit
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
	var undersized_count := 0
	for control in interactive_controls:
		var minimum_size := (control as Control).get_combined_minimum_size()
		if minimum_size.y < 44.0:
			undersized_count += 1
	if undersized_count == 0:
		return ""
	return "Warning: %d control(s) are below a 44px minimum hit target." % undersized_count

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
