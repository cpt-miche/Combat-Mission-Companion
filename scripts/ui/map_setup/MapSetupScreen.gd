extends Control

# Terrain paint/erase QA checklist (manual):
# - Select any terrain from TerrainList, then LMB click a hex => one hex changes to that terrain.
# - Hold LMB and drag across hexes => each traversed hex paints with selected terrain.
# - Hold RMB and drag across painted hexes => traversed hexes return to default terrain.
# - Press Clear All => every hex returns to default terrain (hex_map_view.clear_all()).
# Behavioral touchpoints:
# - HexMapView input/painting logic lives in scripts/ui/map_setup/HexMapView.gd.
# - Clear All wiring lives in _ready() where ClearAllButton is connected to hex_map_view.clear_all.

@onready var terrain_list: VBoxContainer = %TerrainList
@onready var terrain_legend_list: VBoxContainer = %TerrainLegendList
@onready var current_terrain_value: Label = %CurrentTerrainValue
@onready var hex_map_view: HexMapView = %HexMapView
@onready var clear_all_button: Button = %ClearAllButton
@onready var clear_all_palette_button: Button = %ClearAllPaletteButton
@onready var confirm_button: Button = %ConfirmButton
@onready var load_png_button: Button = %LoadPngButton
@onready var mode_prompt_label: Label = %ModePromptLabel
@onready var terrain_mode_button: Button = %TerrainModeButton
@onready var select_p1_button: Button = %SelectP1TerritoryButton
@onready var switch_to_p2_button: Button = %SwitchToP2Button
@onready var primary_objective_button: Button = %PrimaryObjectiveButton
@onready var secondary_objective_button: Button = %SecondaryObjectiveButton
@onready var clear_objectives_button: Button = %ClearObjectivesButton
@onready var confirm_territories_button: Button = %ConfirmTerritoriesButton
@onready var map_name_input: LineEdit = %MapNameInput
@onready var map_selector: OptionButton = %MapSelector
@onready var save_map_button: Button = %SaveMapButton
@onready var load_map_button: Button = %LoadMapButton
@onready var delete_map_button: Button = %DeleteMapButton
@onready var map_status_label: Label = %MapStatusLabel
@onready var doctrine_selector: OptionButton = get_node_or_null("%DoctrineSelector")
@onready var difficulty_selector: OptionButton = get_node_or_null("%DifficultySelector")
@onready var setup_summary_label: Label = get_node_or_null("%SetupSummaryLabel")
@onready var root_margin: MarginContainer = $RootMargin
@onready var scenario_editor_chrome: Control = %ScenarioEditorChrome

var _terrain_group := ButtonGroup.new()
var _mode_group := ButtonGroup.new()
var _terrain_buttons: Dictionary[String, BaseButton] = {}
var _selected_terrain_id: String = TerrainCatalog.default_terrain_id()

func _ready() -> void:
	_apply_selected_grid_dimensions()
	_build_palette()
	_build_terrain_legend()
	clear_all_button.pressed.connect(hex_map_view.clear_all)
	clear_all_button.pressed.connect(_on_clear_all_pressed)
	clear_all_palette_button.pressed.connect(hex_map_view.clear_all)
	clear_all_palette_button.pressed.connect(_on_clear_all_pressed)
	confirm_button.pressed.connect(_on_confirm_pressed)
	load_png_button.pressed.connect(hex_map_view.open_map_dialog)
	terrain_mode_button.pressed.connect(_on_select_terrain_mode_pressed)
	select_p1_button.pressed.connect(_on_select_p1_territory_pressed)
	switch_to_p2_button.pressed.connect(_on_switch_to_p2_pressed)
	primary_objective_button.pressed.connect(_on_primary_objective_pressed)
	secondary_objective_button.pressed.connect(_on_secondary_objective_pressed)
	clear_objectives_button.pressed.connect(_on_clear_objectives_pressed)
	confirm_territories_button.pressed.connect(_on_confirm_territories_pressed)
	save_map_button.pressed.connect(_on_save_map_pressed)
	load_map_button.pressed.connect(_on_load_map_pressed)
	delete_map_button.pressed.connect(_on_delete_map_pressed)
	hex_map_view.territory_painted.connect(_on_hex_territory_painted)
	hex_map_view.objective_painted.connect(_on_hex_objective_painted)
	_load_existing_map_data()
	_refresh_saved_maps()
	_configure_mode_buttons()
	_build_doctrine_selector()
	_build_difficulty_selector()
	_refresh_ui()
	_configure_scenario_editor_mode()

func _configure_scenario_editor_mode() -> void:
	if not ScenarioEditorState.active:
		return
	root_margin.offset_top = 56.0
	ScenarioEditorState.set_step(ScenarioEditorState.Step.MAP)
	scenario_editor_chrome.configure()
	scenario_editor_chrome.back_requested.connect(_on_scenario_editor_back)
	scenario_editor_chrome.before_draft_save.connect(_sync_scenario_editor_document)
	for path in [
		"RootMargin/RootVBox/MainSplit/PalettePanel/PaletteMargin/PaletteScroll/PaletteVBox/MapSaveHeader",
		"RootMargin/RootVBox/MainSplit/PalettePanel/PaletteMargin/PaletteScroll/PaletteVBox/MapNameInput",
		"RootMargin/RootVBox/MainSplit/PalettePanel/PaletteMargin/PaletteScroll/PaletteVBox/MapSaveButtons",
		"RootMargin/RootVBox/MainSplit/PalettePanel/PaletteMargin/PaletteScroll/PaletteVBox/MapSelector",
		"RootMargin/RootVBox/MainSplit/PalettePanel/PaletteMargin/PaletteScroll/PaletteVBox/MapLoadButtons"
	]:
		var node := get_node_or_null(path) as CanvasItem
		if node != null:
			node.visible = false
	confirm_button.text = "Continue to Player 1 Forces"
	confirm_territories_button.text = "Continue to Player 1 Forces"

func _apply_selected_grid_dimensions() -> void:
	GRID_COLUMNS = maxi(GameState.map_columns, 1)
	GRID_ROWS = maxi(GameState.map_rows, 1)
	hex_map_view.GRID_COLUMNS = GRID_COLUMNS
	hex_map_view.GRID_ROWS = GRID_ROWS

func _build_palette() -> void:
	_terrain_buttons.clear()
	for terrain_id in TerrainCatalog.all_ids():
		var button := CheckButton.new()
		button.text = TerrainCatalog.display_name(terrain_id)
		button.toggle_mode = true
		button.button_group = _terrain_group
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggled.connect(_on_terrain_toggled.bind(terrain_id))
		terrain_list.add_child(button)
		_terrain_buttons[terrain_id] = button

	_set_selected_terrain(_selected_terrain_id, true)

func _on_terrain_toggled(is_toggled: bool, terrain_id: String) -> void:
	if not is_toggled:
		return
	_set_selected_terrain(terrain_id, false)

func _set_selected_terrain(terrain_id: String, sync_button_state: bool = true) -> void:
	_selected_terrain_id = TerrainCatalog.normalize_terrain_id(terrain_id)
	hex_map_view.set_selected_terrain(_selected_terrain_id)
	current_terrain_value.text = "Brush: %s" % TerrainCatalog.display_name(_selected_terrain_id)

	if not sync_button_state:
		return

	for id in _terrain_buttons.keys():
		var button: BaseButton = _terrain_buttons[id]
		if button == null:
			continue
		button.button_pressed = id == _selected_terrain_id

func _on_clear_all_pressed() -> void:
	_sync_game_state_terrain_data()

func _on_confirm_pressed() -> void:
	_sync_game_state_map_data()
	if not _validate_territory_submission():
		return
	if ScenarioEditorState.active:
		_complete_scenario_editor_map()
		return
	map_status_label.text = "Submitted unsaved map. Starting deployment."
	GameState.set_phase(GameState.Phase.DEPLOYMENT_P1)

enum Mode {
	TERRAIN_EDIT,
	TERRITORY_P1,
	TERRITORY_P2,
	OBJECTIVE_PRIMARY,
	OBJECTIVE_SECONDARY
}

var GRID_COLUMNS: int = MapGridConfig.default_columns()
var GRID_ROWS: int = MapGridConfig.default_rows()
const HEX_RADIUS := 32.0
const HEX_HORIZONTAL_SPACING := HEX_RADIUS * 1.7320508
const HEX_VERTICAL_SPACING := HEX_RADIUS * 1.5

var _mode: Mode = Mode.TERRAIN_EDIT
var _territory_map: Dictionary = {}
var _objective_map: Dictionary = {}

func _configure_mode_buttons() -> void:
	terrain_mode_button.toggle_mode = true
	select_p1_button.toggle_mode = true
	switch_to_p2_button.toggle_mode = true
	primary_objective_button.toggle_mode = true
	secondary_objective_button.toggle_mode = true
	terrain_mode_button.button_group = _mode_group
	select_p1_button.button_group = _mode_group
	switch_to_p2_button.button_group = _mode_group
	primary_objective_button.button_group = _mode_group
	secondary_objective_button.button_group = _mode_group

func _build_terrain_legend() -> void:
	for child in terrain_legend_list.get_children():
		child.queue_free()

	for terrain_id in TerrainCatalog.all_ids():
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(18.0, 18.0)
		swatch.color = TerrainCatalog.editor_color(terrain_id, 0.8)
		row.add_child(swatch)

		var label := Label.new()
		label.text = TerrainCatalog.display_name(terrain_id)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)

		terrain_legend_list.add_child(row)

func _on_select_terrain_mode_pressed() -> void:
	_mode = Mode.TERRAIN_EDIT
	_refresh_ui()

func _on_select_p1_territory_pressed() -> void:
	_mode = Mode.TERRITORY_P1
	_refresh_ui()

func _on_switch_to_p2_pressed() -> void:
	_mode = Mode.TERRITORY_P2
	_refresh_ui()

func _on_primary_objective_pressed() -> void:
	_mode = Mode.OBJECTIVE_PRIMARY
	_refresh_ui()

func _on_secondary_objective_pressed() -> void:
	_mode = Mode.OBJECTIVE_SECONDARY
	_refresh_ui()

func _on_clear_objectives_pressed() -> void:
	_objective_map.clear()
	GameState.key_objectives.clear()
	hex_map_view.set_objective_paint_mode(_is_objective_mode(), _objective_priority_for_mode(), _objective_map)
	map_status_label.text = "Cleared all key objectives."

func _on_confirm_territories_pressed() -> void:
	_persist_territory_map()
	_sync_game_state_map_data()
	if not _validate_territory_submission():
		return
	if ScenarioEditorState.active:
		_complete_scenario_editor_map()
		return
	GameState.set_phase(GameState.Phase.DEPLOYMENT_P1)

func _complete_scenario_editor_map() -> void:
	_sync_scenario_editor_document()
	ScenarioEditorState.set_step(ScenarioEditorState.Step.PLAYER_1_FORCES, 0)
	GameState.set_phase(GameState.Phase.DIVISION_BUILDER)

func _sync_scenario_editor_document() -> void:
	_sync_game_state_map_data()
	ScenarioEditorState.capture_from_game_state()

func _on_scenario_editor_back() -> void:
	_sync_scenario_editor_document()
	ScenarioEditorState.set_step(ScenarioEditorState.Step.DETAILS)
	GameState.set_phase(GameState.Phase.SCENARIO_EDITOR)

func _validate_territory_submission() -> bool:
	if _territory_owner_count(GameState.TerritoryOwnership.PLAYER_2) <= 0:
		map_status_label.text = "Assign at least one hex to Player 2 before starting deployment."
		return false
	return true

func _territory_owner_count(owner: int) -> int:
	var count := 0
	for territory_owner in _territory_map.values():
		if int(territory_owner) == owner:
			count += 1
	return count

func _refresh_ui() -> void:
	mode_prompt_label.text = _mode_prompt_text()
	terrain_mode_button.button_pressed = _mode == Mode.TERRAIN_EDIT
	select_p1_button.button_pressed = _mode == Mode.TERRITORY_P1
	switch_to_p2_button.button_pressed = _mode == Mode.TERRITORY_P2
	primary_objective_button.button_pressed = _mode == Mode.OBJECTIVE_PRIMARY
	secondary_objective_button.button_pressed = _mode == Mode.OBJECTIVE_SECONDARY
	switch_to_p2_button.disabled = false
	confirm_territories_button.disabled = _mode != Mode.TERRITORY_P2
	hex_map_view.mouse_filter = Control.MOUSE_FILTER_STOP
	hex_map_view.set_territory_paint_mode(_is_territory_mode(), int(_ownership_for_mode()), _territory_map)
	hex_map_view.set_objective_paint_mode(_is_objective_mode(), _objective_priority_for_mode(), _objective_map)
	_refresh_setup_summary()

func _build_doctrine_selector() -> void:
	if doctrine_selector == null:
		return
	doctrine_selector.clear()
	for doctrine in MatchSetupTypes.AI_DOCTRINES:
		doctrine_selector.add_item(_doctrine_display_name(doctrine))
	doctrine_selector.item_selected.connect(_on_doctrine_selected)
	_sync_doctrine_selector_from_state()

func _sync_doctrine_selector_from_state() -> void:
	if doctrine_selector == null:
		return
	var state_doctrine := _sanitize_doctrine(GameState.selected_ai_doctrine)
	GameState.selected_ai_doctrine = state_doctrine
	var target_index := MatchSetupTypes.AI_DOCTRINES.find(state_doctrine)
	if target_index < 0:
		target_index = 0
	doctrine_selector.select(target_index)

func _on_doctrine_selected(index: int) -> void:
	if index < 0 or index >= MatchSetupTypes.AI_DOCTRINES.size():
		return
	GameState.selected_ai_doctrine = MatchSetupTypes.AI_DOCTRINES[index]
	_refresh_setup_summary()

func _doctrine_display_name(doctrine: String) -> String:
	return MatchSetupTypes.display_name(doctrine)

func _sanitize_doctrine(raw_doctrine: Variant) -> String:
	return MatchSetupTypes.sanitize_ai_doctrine(raw_doctrine)

func _build_difficulty_selector() -> void:
	if difficulty_selector == null:
		return
	difficulty_selector.clear()
	for difficulty in MatchSetupTypes.DIFFICULTIES:
		difficulty_selector.add_item(MatchSetupTypes.display_name(difficulty))
	difficulty_selector.item_selected.connect(_on_difficulty_selected)
	_sync_difficulty_selector_from_state()

func _sync_difficulty_selector_from_state() -> void:
	if difficulty_selector == null:
		return
	var state_difficulty := MatchSetupTypes.sanitize_difficulty(GameState.selected_difficulty)
	GameState.selected_difficulty = state_difficulty
	var target_index := MatchSetupTypes.DIFFICULTIES.find(state_difficulty)
	if target_index < 0:
		target_index = 0
	difficulty_selector.select(target_index)

func _on_difficulty_selected(index: int) -> void:
	if index < 0 or index >= MatchSetupTypes.DIFFICULTIES.size():
		return
	GameState.selected_difficulty = MatchSetupTypes.DIFFICULTIES[index]
	_refresh_setup_summary()

func _refresh_setup_summary() -> void:
	if setup_summary_label == null:
		return
	setup_summary_label.text = "Setup Summary: Doctrine %s | Difficulty %s" % [_doctrine_display_name(_sanitize_doctrine(GameState.selected_ai_doctrine)), MatchSetupTypes.display_name(MatchSetupTypes.sanitize_difficulty(GameState.selected_difficulty))]

func _mode_prompt_text() -> String:
	match _mode:
		Mode.TERRAIN_EDIT:
			return "Mode: Terrain Edit"
		Mode.TERRITORY_P1:
			return "Mode: Assign Player 1 Territory"
		Mode.TERRITORY_P2:
			return "Mode: Assign Player 2 Territory"
		Mode.OBJECTIVE_PRIMARY:
			return "Mode: Paint Primary Key Objectives"
		Mode.OBJECTIVE_SECONDARY:
			return "Mode: Paint Secondary Key Objectives"
		_:
			return "Mode: Unknown"

func _is_territory_mode() -> bool:
	return _mode == Mode.TERRITORY_P1 or _mode == Mode.TERRITORY_P2

func _is_objective_mode() -> bool:
	return _mode == Mode.OBJECTIVE_PRIMARY or _mode == Mode.OBJECTIVE_SECONDARY

func _objective_priority_for_mode() -> String:
	return "primary" if _mode == Mode.OBJECTIVE_PRIMARY else "secondary"

func _ownership_for_mode() -> GameState.TerritoryOwnership:
	if _mode == Mode.TERRITORY_P1:
		return GameState.TerritoryOwnership.PLAYER_1
	if _mode == Mode.TERRITORY_P2:
		return GameState.TerritoryOwnership.PLAYER_2
	return GameState.TerritoryOwnership.NEUTRAL

func _load_existing_map_data() -> void:
	hex_map_view.import_terrain_map(GameState.terrain_map.duplicate(true))
	_territory_map = GameState.territory_map.duplicate(true)
	_objective_map = GameState.key_objectives.duplicate(true)
	hex_map_view.set_objective_paint_mode(false, "secondary", _objective_map)

func _persist_territory_map() -> void:
	GameState.territory_map = _territory_map.duplicate(true)
	GameState.key_objectives = _objective_map.duplicate(true)

func _sync_game_state_map_data() -> void:
	GameState.terrain_map = hex_map_view.export_terrain_map()
	GameState.territory_map = _territory_map.duplicate(true)
	GameState.key_objectives = _objective_map.duplicate(true)
	GameState.selected_ai_doctrine = _sanitize_doctrine(GameState.selected_ai_doctrine)
	GameState.selected_difficulty = MatchSetupTypes.sanitize_difficulty(GameState.selected_difficulty)

func _sync_game_state_terrain_data() -> void:
	GameState.terrain_map = hex_map_view.export_terrain_map()

func _build_map_payload(map_name: String) -> Dictionary:
	_apply_selected_grid_dimensions()
	return {
		"version": GameState.MAP_PAYLOAD_VERSION_CURRENT,
		"name": map_name,
		"grid": {
			"rows": GRID_ROWS,
			"columns": GRID_COLUMNS,
			"hex_radius": HEX_RADIUS,
			"hex_horizontal_spacing": HEX_HORIZONTAL_SPACING,
			"hex_vertical_spacing": HEX_VERTICAL_SPACING
		},
		"terrain": hex_map_view.export_terrain_map(),
		"territory": _territory_map.duplicate(true),
		"objectives": _objective_map.duplicate(true),
		"ai_doctrine": _sanitize_doctrine(GameState.selected_ai_doctrine),
		"difficulty": MatchSetupTypes.sanitize_difficulty(GameState.selected_difficulty)
	}

func _on_save_map_pressed() -> void:
	var map_name := map_name_input.text.strip_edges()
	if map_name.is_empty():
		map_status_label.text = "Enter a map name before saving."
		return
	var payload := _build_map_payload(map_name)
	if SaveManager.save_map(map_name, payload):
		map_status_label.text = "Saved map '%s'." % map_name
		_refresh_saved_maps(map_name)
		return
	map_status_label.text = "Failed to save map '%s'." % map_name

func _on_load_map_pressed() -> void:
	if map_selector.get_item_count() == 0:
		map_status_label.text = "No saved maps to load."
		return
	var selected_index := maxi(map_selector.get_selected(), 0)
	var selected_name := map_selector.get_item_text(selected_index)
	var payload := SaveManager.load_map(selected_name)
	if payload.is_empty():
		map_status_label.text = SaveManager.get_last_load_error()
		return
	_apply_map_payload(payload)
	map_name_input.text = String(payload.get("name", selected_name))
	map_status_label.text = "Loaded map '%s'." % selected_name

func _on_delete_map_pressed() -> void:
	if map_selector.get_item_count() == 0:
		map_status_label.text = "No saved maps to delete."
		return
	var selected_index := maxi(map_selector.get_selected(), 0)
	var selected_name := map_selector.get_item_text(selected_index)
	if SaveManager.delete_map(selected_name):
		map_status_label.text = "Deleted map '%s'." % selected_name
		_refresh_saved_maps()
		return
	map_status_label.text = "Failed to delete map '%s'." % selected_name

func _apply_map_payload(payload: Dictionary) -> void:
	GameState.apply_map_payload(payload)
	_apply_selected_grid_dimensions()
	hex_map_view.clear_all()
	hex_map_view.import_terrain_map(GameState.terrain_map.duplicate(true))
	_territory_map = GameState.territory_map.duplicate(true)
	_objective_map = GameState.key_objectives.duplicate(true)
	hex_map_view.set_territory_paint_mode(_is_territory_mode(), int(_ownership_for_mode()), _territory_map)
	hex_map_view.set_objective_paint_mode(_is_objective_mode(), _objective_priority_for_mode(), _objective_map)
	_sync_doctrine_selector_from_state()
	_sync_difficulty_selector_from_state()
	_refresh_setup_summary()

func _refresh_saved_maps(preferred_name: String = "") -> void:
	map_selector.clear()
	var maps := SaveManager.list_maps()
	for map_name in maps:
		map_selector.add_item(map_name)
	if map_selector.get_item_count() == 0:
		load_map_button.disabled = true
		delete_map_button.disabled = true
		return
	load_map_button.disabled = false
	delete_map_button.disabled = false
	var selected_index := 0
	if not preferred_name.is_empty():
		var preferred_safe_name := SaveManager.sanitize_name(preferred_name)
		for index in range(map_selector.get_item_count()):
			if map_selector.get_item_text(index) == preferred_safe_name:
				selected_index = index
				break
	map_selector.select(selected_index)

func _key_for_coordinate(column: int, row: int) -> String:
	return "%d,%d" % [column, row]

func _on_hex_territory_painted(axial: Vector2i, owner: int) -> void:
	var key := _key_for_coordinate(axial.x, axial.y)
	if owner == GameState.TerritoryOwnership.NEUTRAL:
		_territory_map.erase(key)
	else:
		_territory_map[key] = owner
	_persist_territory_map()

func _on_hex_objective_painted(axial: Vector2i, priority: String) -> void:
	var key := _key_for_coordinate(axial.x, axial.y)
	if priority.is_empty():
		_objective_map.erase(key)
	else:
		_objective_map[key] = {"priority": priority}
	GameState.key_objectives = _objective_map.duplicate(true)
