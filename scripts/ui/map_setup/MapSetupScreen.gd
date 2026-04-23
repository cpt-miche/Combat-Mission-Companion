extends Control

@onready var terrain_list: VBoxContainer = %TerrainList
@onready var terrain_legend_list: VBoxContainer = %TerrainLegendList
@onready var current_terrain_value: Label = %CurrentTerrainValue
@onready var hex_map_view: HexMapView = %HexMapView
@onready var clear_all_button: Button = %ClearAllButton
@onready var confirm_button: Button = %ConfirmButton
@onready var load_png_button: Button = %LoadPngButton
@onready var mode_prompt_label: Label = %ModePromptLabel
@onready var terrain_mode_button: Button = %TerrainModeButton
@onready var select_p1_button: Button = %SelectP1TerritoryButton
@onready var switch_to_p2_button: Button = %SwitchToP2Button
@onready var confirm_territories_button: Button = %ConfirmTerritoriesButton
@onready var map_name_input: LineEdit = %MapNameInput
@onready var map_selector: OptionButton = %MapSelector
@onready var save_map_button: Button = %SaveMapButton
@onready var load_map_button: Button = %LoadMapButton
@onready var delete_map_button: Button = %DeleteMapButton
@onready var map_status_label: Label = %MapStatusLabel

var _terrain_group := ButtonGroup.new()
var _mode_group := ButtonGroup.new()

func _ready() -> void:
	_build_palette()
	_build_terrain_legend()
	clear_all_button.pressed.connect(_on_clear_all_pressed)
	confirm_button.pressed.connect(_on_confirm_pressed)
	load_png_button.pressed.connect(hex_map_view.open_map_dialog)
	terrain_mode_button.pressed.connect(_on_select_terrain_mode_pressed)
	select_p1_button.pressed.connect(_on_select_p1_territory_pressed)
	switch_to_p2_button.pressed.connect(_on_switch_to_p2_pressed)
	confirm_territories_button.pressed.connect(_on_confirm_territories_pressed)
	save_map_button.pressed.connect(_on_save_map_pressed)
	load_map_button.pressed.connect(_on_load_map_pressed)
	delete_map_button.pressed.connect(_on_delete_map_pressed)
	_load_existing_territory_map()
	_refresh_saved_maps()
	_configure_mode_buttons()
	_refresh_ui()

func _build_palette() -> void:
	for terrain_id in TerrainCatalog.all_ids():
		var button := CheckButton.new()
		button.text = TerrainCatalog.display_name(terrain_id)
		button.toggle_mode = true
		button.button_group = _terrain_group
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggled.connect(_on_terrain_toggled.bind(terrain_id))
		terrain_list.add_child(button)
		if terrain_id == TerrainCatalog.default_terrain_id():
			button.button_pressed = true
			hex_map_view.set_selected_terrain(terrain_id)
			current_terrain_value.text = TerrainCatalog.display_name(terrain_id)

func _on_terrain_toggled(is_toggled: bool, terrain_id: String) -> void:
	if not is_toggled:
		return
	hex_map_view.set_selected_terrain(terrain_id)
	current_terrain_value.text = TerrainCatalog.display_name(terrain_id)

func _on_clear_all_pressed() -> void:
	hex_map_view.clear_all()

func _on_confirm_pressed() -> void:
	_sync_game_state_map_data()
	print("Map setup confirmed: %d customized hexes" % hex_map_view.hexes.size())

enum Mode {
	TERRAIN_EDIT,
	TERRITORY_P1,
	TERRITORY_P2
}

const GRID_COLUMNS := 8
const GRID_ROWS := 6
const HEX_RADIUS := 32.0
const HEX_HORIZONTAL_SPACING := HEX_RADIUS * 1.7320508
const HEX_VERTICAL_SPACING := HEX_RADIUS * 1.5
const HEX_ORIGIN := Vector2(120.0, 170.0)

var _mode: Mode = Mode.TERRAIN_EDIT
var _territory_map: Dictionary = {}

func _configure_mode_buttons() -> void:
	terrain_mode_button.toggle_mode = true
	select_p1_button.toggle_mode = true
	switch_to_p2_button.toggle_mode = true
	terrain_mode_button.button_group = _mode_group
	select_p1_button.button_group = _mode_group
	switch_to_p2_button.button_group = _mode_group

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

func _draw() -> void:
	if not _is_territory_mode():
		return
	for row in range(GRID_ROWS):
		for column in range(GRID_COLUMNS):
			var center := _hex_center(column, row)
			var owner := _ownership_for(column, row)
			var fill_color := _color_for_owner(owner)
			var points := _hex_points(center)
			draw_colored_polygon(points, fill_color)
			draw_polyline(points + PackedVector2Array([points[0]]), Color(0.13, 0.13, 0.13, 0.95), 2.0)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var clicked_coordinate := _find_hex(event.position)
		if clicked_coordinate.is_empty() or not _is_territory_mode():
			return
		var key := _key_for_coordinate(clicked_coordinate["q"], clicked_coordinate["r"])
		_territory_map[key] = _ownership_for_mode()
		_persist_territory_map()
		queue_redraw()

func _on_select_p1_territory_pressed() -> void:
	_mode = Mode.TERRITORY_P1
	_refresh_ui()

func _on_switch_to_p2_pressed() -> void:
	_mode = Mode.TERRITORY_P2
	_refresh_ui()

func _on_confirm_territories_pressed() -> void:
	_persist_territory_map()
	_sync_game_state_map_data()
	GameState.set_phase(GameState.Phase.DEPLOYMENT_P1)

func _refresh_ui() -> void:
	mode_prompt_label.text = _mode_prompt_text()
	terrain_mode_button.button_pressed = _mode == Mode.TERRAIN_EDIT
	select_p1_button.button_pressed = _mode == Mode.TERRITORY_P1
	switch_to_p2_button.button_pressed = _mode == Mode.TERRITORY_P2
	switch_to_p2_button.disabled = false
	confirm_territories_button.disabled = _mode != Mode.TERRITORY_P2
	hex_map_view.mouse_filter = Control.MOUSE_FILTER_STOP if _mode == Mode.TERRAIN_EDIT else Control.MOUSE_FILTER_IGNORE
	queue_redraw()

func _mode_prompt_text() -> String:
	match _mode:
		Mode.TERRAIN_EDIT:
			return "Mode: Terrain Edit"
		Mode.TERRITORY_P1:
			return "Mode: Assign Player 1 Territory"
		Mode.TERRITORY_P2:
			return "Mode: Assign Player 2 Territory"
		_:
			return "Mode: Unknown"

func _is_territory_mode() -> bool:
	return _mode == Mode.TERRITORY_P1 or _mode == Mode.TERRITORY_P2

func _ownership_for_mode() -> GameState.TerritoryOwnership:
	return GameState.TerritoryOwnership.PLAYER_1 if _mode == Mode.TERRITORY_P1 else GameState.TerritoryOwnership.PLAYER_2

func _load_existing_territory_map() -> void:
	_territory_map = GameState.territory_map.duplicate(true)

func _persist_territory_map() -> void:
	GameState.territory_map = _territory_map.duplicate(true)

func _sync_game_state_map_data() -> void:
	GameState.terrain_map = hex_map_view.export_terrain_map()
	GameState.territory_map = _territory_map.duplicate(true)

func _build_map_payload(map_name: String) -> Dictionary:
	return {
		"version": 1,
		"name": map_name,
		"grid": {
			"rows": GRID_ROWS,
			"columns": GRID_COLUMNS,
			"hex_radius": HEX_RADIUS,
			"hex_horizontal_spacing": HEX_HORIZONTAL_SPACING,
			"hex_vertical_spacing": HEX_VERTICAL_SPACING
		},
		"terrain": hex_map_view.export_terrain_map(),
		"territory": _territory_map.duplicate(true)
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
		map_status_label.text = "Could not load map '%s'." % selected_name
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
	var terrain_payload := (payload.get("terrain", {}) as Dictionary).duplicate(true)
	var territory_payload := (payload.get("territory", {}) as Dictionary).duplicate(true)
	hex_map_view.import_terrain_map(terrain_payload)
	_territory_map = territory_payload
	_sync_game_state_map_data()
	queue_redraw()

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

func _ownership_for(column: int, row: int) -> GameState.TerritoryOwnership:
	var key := _key_for_coordinate(column, row)
	return _territory_map.get(key, GameState.TerritoryOwnership.NEUTRAL)

func _color_for_owner(owner: GameState.TerritoryOwnership) -> Color:
	if owner == GameState.TerritoryOwnership.PLAYER_1:
		return Color(0.24, 0.43, 0.92, 0.85)
	if owner == GameState.TerritoryOwnership.PLAYER_2:
		return Color(0.89, 0.29, 0.27, 0.85)
	return Color(0.58, 0.58, 0.58, 0.55)

func _key_for_coordinate(column: int, row: int) -> String:
	return "%d,%d" % [column, row]

func _hex_center(column: int, row: int) -> Vector2:
	var x := HEX_ORIGIN.x + (float(column) * HEX_HORIZONTAL_SPACING) + (HEX_HORIZONTAL_SPACING * 0.5 if row % 2 == 1 else 0.0)
	var y := HEX_ORIGIN.y + (float(row) * HEX_VERTICAL_SPACING)
	return Vector2(x, y)

func _hex_points(center: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(6):
		var angle := deg_to_rad(60.0 * i - 30.0)
		points.append(center + Vector2(cos(angle), sin(angle)) * HEX_RADIUS)
	return points

func _find_hex(position: Vector2) -> Dictionary:
	for row in range(GRID_ROWS):
		for column in range(GRID_COLUMNS):
			if Geometry2D.is_point_in_polygon(position, _hex_points(_hex_center(column, row))):
				return {"q": column, "r": row}
	return {}
