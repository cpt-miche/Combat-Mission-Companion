extends Control
class_name DeploymentHexMapView

signal hex_selected(column: int, row: int)

const GRID_COLUMNS := 8
const GRID_ROWS := 6
const HEX_RADIUS := 30.0
const HEX_HORIZONTAL_SPACING := HEX_RADIUS * 1.7320508
const HEX_VERTICAL_SPACING := HEX_RADIUS * 1.5
const HEX_ORIGIN := Vector2(80.0, 120.0)

var territory_map: Dictionary = {}
var placements_by_player: Dictionary = {}
var visible_player_index := 0
var deploy_mode := true
var pan_offset := Vector2.ZERO
var _is_panning := false
var _drag_distance := 0.0
const PAN_DRAG_THRESHOLD := 8.0

func configure(new_territory_map: Dictionary, new_placements: Dictionary, player_index: int, is_deploy_mode: bool = true) -> void:
	territory_map = new_territory_map.duplicate(true)
	placements_by_player = new_placements.duplicate(true)
	visible_player_index = player_index
	deploy_mode = is_deploy_mode
	queue_redraw()

func _draw() -> void:
	draw_set_transform(pan_offset, 0.0, Vector2.ONE)

	for row in range(GRID_ROWS):
		for column in range(GRID_COLUMNS):
			var center := _hex_center(column, row)
			var owner := _owner_for(column, row)
			var points := _hex_points(center)
			draw_colored_polygon(points, _color_for_owner(owner))
			draw_polyline(points + PackedVector2Array([points[0]]), Color(0.12, 0.12, 0.12, 0.95), 2.0)

	_draw_visible_placements()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _gui_input(event: InputEvent) -> void:
	if not deploy_mode:
		return
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_LEFT and mouse_button.pressed:
			_is_panning = true
			_drag_distance = 0.0
			accept_event()
			return
		if mouse_button.button_index == MOUSE_BUTTON_LEFT and not mouse_button.pressed:
			if _is_panning and _drag_distance < PAN_DRAG_THRESHOLD:
				var coordinate := _find_hex(_to_world(mouse_button.position))
				if coordinate.is_empty():
					_is_panning = false
					accept_event()
					return
				emit_signal("hex_selected", int(coordinate["q"]), int(coordinate["r"]))
			_is_panning = false
			accept_event()
			return
	if event is InputEventMouseMotion and _is_panning:
		var mouse_motion := event as InputEventMouseMotion
		_drag_distance += mouse_motion.relative.length()
		pan_offset += mouse_motion.relative
		queue_redraw()
		accept_event()

func _draw_visible_placements() -> void:
	var placements: Dictionary = placements_by_player.get(visible_player_index, {}) as Dictionary
	for key in placements.keys():
		var key_string: String = String(key)
		var parts: PackedStringArray = key_string.split(",")
		if parts.size() != 2:
			continue
		var center := _hex_center(int(parts[0]), int(parts[1]))
		draw_circle(center, 10.0, _placement_color(visible_player_index))
		draw_string(get_theme_default_font(), center + Vector2(-16.0, 4.0), String(placements[key].get("label", "U")), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, Color.WHITE)

func _placement_color(player_index: int) -> Color:
	if player_index == 0:
		return Color(0.18, 0.34, 0.86, 0.95)
	return Color(0.83, 0.24, 0.2, 0.95)

func _owner_for(column: int, row: int) -> int:
	return int(territory_map.get("%d,%d" % [column, row], GameState.TerritoryOwnership.NEUTRAL))

func _color_for_owner(owner: int) -> Color:
	if owner == GameState.TerritoryOwnership.PLAYER_1:
		return Color(0.24, 0.43, 0.92, 0.45)
	if owner == GameState.TerritoryOwnership.PLAYER_2:
		return Color(0.89, 0.29, 0.27, 0.45)
	return Color(0.58, 0.58, 0.58, 0.35)

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

func _to_world(screen_position: Vector2) -> Vector2:
	return screen_position - pan_offset
