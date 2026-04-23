extends Control
class_name HexMapView

signal painted(axial: Vector2i, terrain: String)

const SQRT3 := 1.7320508075688772
const MIN_ZOOM := 0.2
const MAX_ZOOM := 4.0
const ZOOM_STEP := 1.1
const DEFAULT_TERRAIN := TerrainCatalog.DEFAULT_TERRAIN_ID
const GRID_COLUMNS := 8
const GRID_ROWS := 6
const MAP_PADDING := Vector2(40.0, 40.0)

var hex_size: float = 24.0
var map_texture: Texture2D
var map_offset: Vector2 = Vector2.ZERO
var zoom: float = 1.0
var pan_offset: Vector2 = Vector2.ZERO
var selected_terrain: String = DEFAULT_TERRAIN

var hexes: Dictionary[Vector2i, HexCellData] = {}

var _is_painting := false
var _is_erasing := false
var _is_panning := false
var _last_mouse_position := Vector2.ZERO
var _has_last_brush_axial := false
var _last_brush_axial := Vector2i.ZERO

@onready var file_dialog: FileDialog = FileDialog.new()

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(file_dialog)
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.filters = PackedStringArray(["*.png ; PNG Images"])
	file_dialog.file_selected.connect(_on_file_selected)

func open_map_dialog() -> void:
	file_dialog.popup_centered_ratio(0.75)

func set_selected_terrain(terrain: String) -> void:
	selected_terrain = TerrainCatalog.normalize_terrain_id(terrain)

func clear_all() -> void:
	hexes.clear()
	queue_redraw()

func export_terrain_map() -> Dictionary:
	var terrain_map := {}
	for axial in hexes.keys():
		var cell: HexCellData = hexes[axial]
		if cell == null:
			continue
		var terrain_id := TerrainCatalog.normalize_terrain_id(cell.terrain)
		if terrain_id == DEFAULT_TERRAIN:
			continue
		terrain_map["%d,%d" % [axial.x, axial.y]] = terrain_id
	return terrain_map

func import_terrain_map(serialized_map: Dictionary) -> void:
	hexes.clear()
	for coordinate in serialized_map.keys():
		var coordinate_text := String(coordinate)
		var parts := coordinate_text.split(",")
		if parts.size() != 2:
			continue
		var q := int(parts[0])
		var r := int(parts[1])
		var axial := Vector2i(q, r)
		if not _is_axial_on_map(axial):
			continue
		var terrain_id := TerrainCatalog.normalize_terrain_id(String(serialized_map.get(coordinate, DEFAULT_TERRAIN)))
		if terrain_id == DEFAULT_TERRAIN:
			continue
		hexes[axial] = HexCellData.new(terrain_id)
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		_last_mouse_position = mouse_button.position

		if mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_button.pressed:
			_apply_zoom(ZOOM_STEP, mouse_button.position)
			return
		if mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_button.pressed:
			_apply_zoom(1.0 / ZOOM_STEP, mouse_button.position)
			return

		if mouse_button.button_index == MOUSE_BUTTON_MIDDLE:
			_is_panning = mouse_button.pressed
			accept_event()
			return

		if mouse_button.button_index == MOUSE_BUTTON_LEFT:
			_is_painting = mouse_button.pressed
			if mouse_button.pressed:
				_is_erasing = false
				_has_last_brush_axial = false
			else:
				_has_last_brush_axial = false
			if mouse_button.pressed:
				_paint_at(mouse_button.position, selected_terrain)
			accept_event()
			return

		if mouse_button.button_index == MOUSE_BUTTON_RIGHT:
			_is_erasing = mouse_button.pressed
			if mouse_button.pressed:
				_is_painting = false
				_has_last_brush_axial = false
			else:
				if mouse_button.button_mask & MOUSE_BUTTON_MASK_LEFT:
					_is_painting = true
				_has_last_brush_axial = false
			if mouse_button.pressed:
				_paint_at(mouse_button.position, DEFAULT_TERRAIN)
			accept_event()
			return

	if event is InputEventMouseMotion:
		var mouse_motion := event as InputEventMouseMotion
		if _is_panning:
			pan_offset += mouse_motion.relative
			queue_redraw()
			accept_event()
			return

		if _is_painting:
			_paint_at(mouse_motion.position, selected_terrain)
			accept_event()
			return

		if _is_erasing:
			_paint_at(mouse_motion.position, DEFAULT_TERRAIN)
			accept_event()
			return

func _apply_zoom(scale_multiplier: float, pivot: Vector2) -> void:
	var old_zoom := zoom
	zoom = clamp(zoom * scale_multiplier, MIN_ZOOM, MAX_ZOOM)
	if is_equal_approx(old_zoom, zoom):
		return
	var before := _screen_to_world(pivot, old_zoom)
	var after := _screen_to_world(pivot, zoom)
	pan_offset += (after - before) * zoom
	queue_redraw()

func _draw() -> void:
	var xform := _view_transform()
	draw_set_transform(xform.origin, 0.0, xform.get_scale())

	if map_texture != null:
		draw_texture(map_texture, map_offset)

	_draw_hex_grid()
	_draw_painted_hexes()

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_hex_grid() -> void:
	for axial in _generate_axial_coordinates():
		var corners := _hex_corners_world(_axial_to_world(axial))
		draw_polyline(corners, Color(1, 1, 1, 0.25), 1.0, true)

func _draw_painted_hexes() -> void:
	for axial in hexes.keys():
		var cell: HexCellData = hexes[axial]
		var terrain := TerrainCatalog.normalize_terrain_id(cell.terrain if cell != null else DEFAULT_TERRAIN)
		if terrain == DEFAULT_TERRAIN:
			continue
		var corners := _hex_corners_world(_axial_to_world(axial))
		var color := TerrainCatalog.editor_color(terrain, 0.5)
		draw_colored_polygon(corners, color)
		draw_polyline(corners, Color(0, 0, 0, 0.2), 1.0, true)

func _paint_at(screen_position: Vector2, terrain: String) -> void:
	var terrain_id := TerrainCatalog.normalize_terrain_id(terrain)
	var world_position := _screen_to_world(screen_position)
	var axial := _world_to_axial(world_position)
	if not _is_axial_on_map(axial):
		return
	if _has_last_brush_axial and _last_brush_axial == axial:
		return

	var current_terrain := DEFAULT_TERRAIN
	if hexes.has(axial):
		var current_cell: HexCellData = hexes[axial]
		if current_cell != null:
			current_terrain = TerrainCatalog.normalize_terrain_id(current_cell.terrain)
	if current_terrain == terrain_id:
		_has_last_brush_axial = true
		_last_brush_axial = axial
		return

	if terrain_id == DEFAULT_TERRAIN:
		hexes.erase(axial)
	else:
		hexes[axial] = HexCellData.new(terrain_id)

	_has_last_brush_axial = true
	_last_brush_axial = axial
	painted.emit(axial, terrain_id)
	queue_redraw()

func _on_file_selected(path: String) -> void:
	var loaded: Resource = load(path)
	if loaded is Texture2D:
		map_texture = loaded
		map_offset = Vector2.ZERO
		hexes.clear()
		queue_redraw()

func _generate_axial_coordinates() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for q in range(GRID_COLUMNS):
		for r in range(GRID_ROWS):
			result.append(Vector2i(q, r))

	return result

func _is_axial_on_map(axial: Vector2i) -> bool:
	return axial.x >= 0 and axial.y >= 0 and axial.x < GRID_COLUMNS and axial.y < GRID_ROWS

func _axial_to_world(axial: Vector2i) -> Vector2:
	var x := hex_size * (1.5 * axial.x)
	var y := hex_size * (SQRT3 * (axial.y + axial.x * 0.5))
	return map_offset + MAP_PADDING + Vector2(x, y)

func _world_to_axial(world: Vector2) -> Vector2i:
	var local := world - map_offset - MAP_PADDING
	var q := (2.0 / 3.0 * local.x) / hex_size
	var r := (-1.0 / 3.0 * local.x + SQRT3 / 3.0 * local.y) / hex_size
	return _hex_round(q, r)

func _hex_round(q: float, r: float) -> Vector2i:
	var s: float = -q - r
	var rq: float = round(q)
	var rr: float = round(r)
	var rs: float = round(s)

	var q_diff: float = absf(rq - q)
	var r_diff: float = absf(rr - r)
	var s_diff: float = absf(rs - s)

	if q_diff > r_diff and q_diff > s_diff:
		rq = -rr - rs
	elif r_diff > s_diff:
		rr = -rq - rs

	return Vector2i(int(rq), int(rr))

func _hex_corners_world(center: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(6):
		var angle := deg_to_rad(60.0 * i)
		points.append(center + Vector2(cos(angle), sin(angle)) * hex_size)
	return points

func _view_transform() -> Transform2D:
	return Transform2D(0.0, Vector2.ONE * zoom, 0.0, pan_offset)

func _screen_to_world(screen_pos: Vector2, sample_zoom: float = -1.0) -> Vector2:
	var active_zoom := zoom if sample_zoom < 0.0 else sample_zoom
	return (screen_pos - pan_offset) / active_zoom
