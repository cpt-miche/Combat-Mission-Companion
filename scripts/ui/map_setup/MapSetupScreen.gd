extends Control


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

@onready var mode_prompt_label: Label = %ModePromptLabel
@onready var select_p1_button: Button = %SelectP1TerritoryButton
@onready var switch_to_p2_button: Button = %SwitchToP2Button
@onready var confirm_territories_button: Button = %ConfirmTerritoriesButton

var _mode: Mode = Mode.TERRAIN_EDIT
var _territory_map: Dictionary = {}

func _ready() -> void:
	select_p1_button.pressed.connect(_on_select_p1_territory_pressed)
	switch_to_p2_button.pressed.connect(_on_switch_to_p2_pressed)
	confirm_territories_button.pressed.connect(_on_confirm_territories_pressed)
	_load_existing_territory_map()
	_refresh_ui()

func _draw() -> void:
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
	GameState.set_phase(GameState.Phase.DEPLOYMENT_P1)

func _refresh_ui() -> void:
	mode_prompt_label.text = _mode_prompt_text()
	select_p1_button.disabled = _mode == Mode.TERRITORY_P1
	switch_to_p2_button.disabled = _mode != Mode.TERRITORY_P1
	confirm_territories_button.disabled = _mode != Mode.TERRITORY_P2
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
