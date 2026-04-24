extends Control
class_name HexMapView

class BaseCacheLayer extends Control:
	var owner_view: HexMapView
	var cache_origin := Vector2.ZERO

	func _draw() -> void:
		if owner_view == null:
			return
		owner_view._draw_base_cache_into(self, cache_origin)

signal painted(axial: Vector2i, terrain: String)
signal territory_painted(axial: Vector2i, owner: int)

const SQRT3 := 1.7320508075688772
const MIN_ZOOM := 0.2
const MAX_ZOOM := 4.0
const ZOOM_STEP := 1.1
const DEFAULT_TERRAIN := TerrainCatalog.DEFAULT_TERRAIN_ID
const ERASE_BRUSH_ID := "__erase__"
var GRID_COLUMNS: int = MapGridConfig.default_columns()
var GRID_ROWS: int = MapGridConfig.default_rows()
const MAP_PADDING := Vector2(40.0, 40.0)

var hex_size: float = 24.0
var map_texture: Texture2D
var map_offset: Vector2 = Vector2.ZERO
var zoom: float = 1.0
var pan_offset: Vector2 = Vector2.ZERO
var selected_terrain: String = TerrainCatalog.default_terrain_id()

var hexes: Dictionary[Vector2i, HexCellData] = {}

var _is_painting := false
var _is_erasing := false
var _is_panning := false
var _is_painting_territory := false
var _is_erasing_territory := false
var _last_mouse_position := Vector2.ZERO
var _has_last_brush_axial := false
var _last_brush_axial := Vector2i.ZERO
var _territory_mode_enabled := false
var _territory_brush_owner: int = GameState.TerritoryOwnership.NEUTRAL
var _territory_map: Dictionary = {}
var _geometry_dirty := true
var _base_cache_dirty := true
var _base_cache_origin := Vector2.ZERO
var _base_cache_size := Vector2i.ZERO
var _map_axials: Array[Vector2i] = []
var _map_axials_packed := PackedVector2Array()
var _hex_geometry_cache: Dictionary[Vector2i, Dictionary] = {}
var _painted_overlay_cache: Dictionary[Vector2i, Dictionary] = {}
var _territory_overlay_cache: Dictionary[Vector2i, Dictionary] = {}
var _base_viewport: SubViewport
var _base_layer: BaseCacheLayer
var _last_geometry_signature := ""

@onready var file_dialog: FileDialog = FileDialog.new()

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(file_dialog)
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.filters = PackedStringArray(["*.png ; PNG Images"])
	file_dialog.file_selected.connect(_on_file_selected)
	_setup_base_cache_viewport()
	_mark_geometry_dirty()
	_populate_default_hexes()

func open_map_dialog() -> void:
	file_dialog.popup_centered_ratio(0.75)

func set_selected_terrain(terrain: String) -> void:
	selected_terrain = TerrainCatalog.normalize_terrain_id(terrain)

func clear_all() -> void:
	_populate_default_hexes()
	_has_last_brush_axial = false
	queue_redraw()

func set_territory_paint_mode(enabled: bool, owner: int, territory_map: Dictionary) -> void:
	_territory_mode_enabled = enabled
	_territory_brush_owner = owner
	_territory_map = territory_map.duplicate(true)
	if not enabled:
		_is_painting_territory = false
		_is_erasing_territory = false
		_has_last_brush_axial = false
	_rebuild_territory_overlay_cache()
	queue_redraw()

func export_terrain_map() -> Dictionary:
	_ensure_geometry_cache()
	var terrain_map := {}
	for packed_axial in _map_axials_packed:
		var axial := Vector2i(int(packed_axial.x), int(packed_axial.y))
		var cell: HexCellData = hexes.get(axial)
		var terrain_id := DEFAULT_TERRAIN
		if cell != null:
			terrain_id = TerrainCatalog.normalize_terrain_id(cell.terrain)
		terrain_map["%d,%d" % [axial.x, axial.y]] = terrain_id
	return terrain_map

func import_terrain_map(serialized_map: Dictionary) -> void:
	_populate_default_hexes(false)
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
		hexes[axial] = HexCellData.new(terrain_id)
	_rebuild_painted_overlay_cache()
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
			if mouse_button.pressed:
				_is_painting = false
				_is_erasing = false
				_is_painting_territory = false
				_is_erasing_territory = false
				_has_last_brush_axial = false
			accept_event()
			return

		if mouse_button.button_index == MOUSE_BUTTON_LEFT:
			if mouse_button.pressed:
				if _territory_mode_enabled:
					_is_painting_territory = false
					_is_erasing_territory = false
					_is_painting = false
					_is_erasing = false
					_has_last_brush_axial = false
					if _is_screen_position_on_map_hex(mouse_button.position):
						_is_painting_territory = true
						_is_panning = false
						_paint_territory_at(mouse_button.position)
					else:
						_is_panning = true
					accept_event()
					return
				_is_erasing = false
				_has_last_brush_axial = false
				if _is_screen_position_on_map_hex(mouse_button.position):
					_is_painting = true
					_is_panning = false
					_paint_at(mouse_button.position, selected_terrain)
				else:
					_is_painting = false
					_is_panning = true
			else:
				_is_painting_territory = false
				_is_erasing_territory = false
				_is_painting = false
				_is_panning = false
				_has_last_brush_axial = false
			accept_event()
			return

		if mouse_button.button_index == MOUSE_BUTTON_RIGHT:
			if _territory_mode_enabled:
				_is_erasing = false
				if mouse_button.pressed:
					_is_painting_territory = false
					_is_erasing_territory = false
					_is_painting = false
					_is_panning = false
					_has_last_brush_axial = false
					if _is_screen_position_on_map_hex(mouse_button.position):
						_is_erasing_territory = true
						_paint_territory_at(mouse_button.position, GameState.TerritoryOwnership.NEUTRAL)
				else:
					_is_erasing_territory = false
					_has_last_brush_axial = false
				accept_event()
				return
			# QA expectation: RMB acts as an eraser by applying DEFAULT_TERRAIN, including drag erase.
			_is_erasing = mouse_button.pressed
			if mouse_button.pressed:
				_is_painting = false
				_is_panning = false
				_has_last_brush_axial = false
			else:
				_has_last_brush_axial = false
			if mouse_button.pressed:
				_paint_at(mouse_button.position, ERASE_BRUSH_ID)
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

		if _is_painting_territory:
			_paint_territory_at(mouse_motion.position)
			accept_event()
			return

		if _is_erasing_territory:
			_paint_territory_at(mouse_motion.position, GameState.TerritoryOwnership.NEUTRAL)
			accept_event()
			return

		if _is_erasing:
			_paint_at(mouse_motion.position, ERASE_BRUSH_ID)
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
	_sync_geometry_state()
	_ensure_geometry_cache()
	_ensure_base_cache()
	var xform := _view_transform()
	draw_set_transform(xform.origin, 0.0, xform.get_scale())

	if map_texture != null:
		draw_texture(map_texture, map_offset)

	if _base_viewport != null and _base_cache_size.x > 0 and _base_cache_size.y > 0:
		draw_texture(_base_viewport.get_texture(), _base_cache_origin)
	_draw_painted_hexes()
	_draw_territory_overlay()

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_painted_hexes() -> void:
	for entry in _painted_overlay_cache.values():
		var corners: PackedVector2Array = entry.get("corners", PackedVector2Array())
		if corners.is_empty():
			continue
		var color: Color = entry.get("color", TerrainCatalog.editor_color(DEFAULT_TERRAIN, 0.5))
		draw_colored_polygon(corners, color)
		draw_polyline(corners, Color(0, 0, 0, 0.2), 1.0, true)

func _paint_at(screen_position: Vector2, terrain: String) -> void:
	var is_erasing := terrain == ERASE_BRUSH_ID
	var terrain_id := TerrainCatalog.normalize_terrain_id(terrain)
	var world_position := _screen_to_world(screen_position)
	var axial := _world_to_axial(world_position)
	if not _is_axial_on_map(axial):
		return
	if _has_last_brush_axial and _last_brush_axial == axial:
		return

	var has_existing_cell := hexes.has(axial)
	var current_terrain := DEFAULT_TERRAIN
	if has_existing_cell:
		var current_cell: HexCellData = hexes[axial]
		if current_cell != null:
			current_terrain = TerrainCatalog.normalize_terrain_id(current_cell.terrain)
	if not is_erasing and has_existing_cell and current_terrain == terrain_id:
		_has_last_brush_axial = true
		_last_brush_axial = axial
		return

	if is_erasing:
		hexes[axial] = HexCellData.new(DEFAULT_TERRAIN)
	else:
		hexes[axial] = HexCellData.new(terrain_id)
	_update_painted_overlay_for(axial)

	_has_last_brush_axial = true
	_last_brush_axial = axial
	painted.emit(axial, DEFAULT_TERRAIN if is_erasing else terrain_id)
	queue_redraw()


func _populate_default_hexes(rebuild_overlay_cache: bool = true) -> void:
	_ensure_geometry_cache()
	hexes.clear()
	for packed_axial in _map_axials_packed:
		var axial := Vector2i(int(packed_axial.x), int(packed_axial.y))
		hexes[axial] = HexCellData.new(DEFAULT_TERRAIN)
	if rebuild_overlay_cache:
		_rebuild_painted_overlay_cache()

func _paint_territory_at(screen_position: Vector2, owner_override: int = -1) -> void:
	if not _territory_mode_enabled:
		return
	var target_owner := _territory_brush_owner if owner_override < 0 else owner_override
	var world_position := _screen_to_world(screen_position)
	var axial := _world_to_axial(world_position)
	if not _is_axial_on_map(axial):
		return
	if _has_last_brush_axial and _last_brush_axial == axial:
		return
	var key := _coordinate_key(axial)
	var owner := int(_territory_map.get(key, GameState.TerritoryOwnership.NEUTRAL))
	if owner == target_owner:
		_has_last_brush_axial = true
		_last_brush_axial = axial
		return
	if target_owner == GameState.TerritoryOwnership.NEUTRAL:
		_territory_map.erase(key)
	else:
		_territory_map[key] = target_owner
	_update_territory_overlay_for(axial)
	_has_last_brush_axial = true
	_last_brush_axial = axial
	territory_painted.emit(axial, target_owner)
	queue_redraw()

func _draw_territory_overlay() -> void:
	if not _territory_mode_enabled:
		return
	for entry in _territory_overlay_cache.values():
		var corners: PackedVector2Array = entry.get("corners", PackedVector2Array())
		if corners.is_empty():
			continue
		var color: Color = entry.get("color", Color.TRANSPARENT)
		draw_colored_polygon(corners, color)

func _color_for_owner(owner: int) -> Color:
	if owner == GameState.TerritoryOwnership.PLAYER_1:
		return Color(0.24, 0.43, 0.92, 0.45)
	if owner == GameState.TerritoryOwnership.PLAYER_2:
		return Color(0.89, 0.29, 0.27, 0.45)
	return Color(0.58, 0.58, 0.58, 0.3)

func _coordinate_key(axial: Vector2i) -> String:
	return "%d,%d" % [axial.x, axial.y]

func _on_file_selected(path: String) -> void:
	var loaded: Resource = load(path)
	if loaded is Texture2D:
		map_texture = loaded
		map_offset = Vector2.ZERO
		_populate_default_hexes()
		_mark_base_cache_dirty()
		queue_redraw()

func _setup_base_cache_viewport() -> void:
	_base_viewport = SubViewport.new()
	_base_viewport.disable_3d = true
	_base_viewport.transparent_bg = true
	_base_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_base_viewport)

	_base_layer = BaseCacheLayer.new()
	_base_layer.owner_view = self
	_base_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_base_viewport.add_child(_base_layer)

func _sync_geometry_state() -> void:
	var signature := "%d|%d|%.4f" % [GRID_COLUMNS, GRID_ROWS, hex_size]
	if signature == _last_geometry_signature:
		return
	_last_geometry_signature = signature
	_mark_geometry_dirty()

func _mark_geometry_dirty() -> void:
	_geometry_dirty = true
	_mark_base_cache_dirty()

func _mark_base_cache_dirty() -> void:
	_base_cache_dirty = true

func _ensure_geometry_cache() -> void:
	if not _geometry_dirty:
		return
	_geometry_dirty = false
	_map_axials.clear()
	_map_axials_packed = PackedVector2Array()
	_hex_geometry_cache.clear()

	var min_bound := Vector2(INF, INF)
	var max_bound := Vector2(-INF, -INF)
	for q in range(GRID_COLUMNS):
		for r in range(GRID_ROWS):
			var axial := Vector2i(q, r)
			var center := _axial_center_world_fast(q, r)
			var corners := _hex_corners_world(center)
			_map_axials.append(axial)
			_map_axials_packed.append(Vector2(q, r))
			_hex_geometry_cache[axial] = {
				"center": center,
				"corners": corners
			}
			for corner in corners:
				min_bound.x = min(min_bound.x, corner.x)
				min_bound.y = min(min_bound.y, corner.y)
				max_bound.x = max(max_bound.x, corner.x)
				max_bound.y = max(max_bound.y, corner.y)

	if _map_axials.is_empty():
		min_bound = Vector2.ZERO
		max_bound = Vector2.ZERO
	_base_cache_origin = min_bound.floor()
	var bounds_size := (max_bound - min_bound).ceil() + Vector2.ONE * 2.0
	_base_cache_size = Vector2i(max(1, int(bounds_size.x)), max(1, int(bounds_size.y)))
	_rebuild_painted_overlay_cache()
	_rebuild_territory_overlay_cache()
	_mark_base_cache_dirty()

func _ensure_base_cache() -> void:
	if not _base_cache_dirty or _base_viewport == null or _base_layer == null:
		return
	_base_cache_dirty = false
	_base_viewport.size = _base_cache_size
	_base_layer.position = Vector2.ZERO
	_base_layer.size = Vector2(_base_cache_size)
	_base_layer.cache_origin = _base_cache_origin
	_base_layer.queue_redraw()
	_base_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func _draw_base_cache_into(canvas: Control, cache_origin: Vector2) -> void:
	var default_color := TerrainCatalog.editor_color(DEFAULT_TERRAIN, 0.5)
	for packed_axial in _map_axials_packed:
		var axial := Vector2i(int(packed_axial.x), int(packed_axial.y))
		var corners := _corners_for_axial(axial)
		if corners.is_empty():
			continue
		var local := PackedVector2Array()
		local.resize(corners.size())
		for i in range(corners.size()):
			local[i] = corners[i] - cache_origin
		canvas.draw_colored_polygon(local, default_color)
		canvas.draw_polyline(local, Color(1, 1, 1, 0.25), 1.0, true)

func _rebuild_painted_overlay_cache() -> void:
	_painted_overlay_cache.clear()
	for axial in hexes.keys():
		_update_painted_overlay_for(axial)

func _update_painted_overlay_for(axial: Vector2i) -> void:
	var cell: HexCellData = hexes.get(axial)
	if cell == null:
		_painted_overlay_cache.erase(axial)
		return
	var terrain := TerrainCatalog.normalize_terrain_id(cell.terrain)
	if terrain == DEFAULT_TERRAIN:
		_painted_overlay_cache.erase(axial)
		return
	var corners: PackedVector2Array = _corners_for_axial(axial)
	if corners.is_empty():
		return
	_painted_overlay_cache[axial] = {
		"corners": corners,
		"color": TerrainCatalog.editor_color(terrain, 0.5)
	}

func _rebuild_territory_overlay_cache() -> void:
	_territory_overlay_cache.clear()
	for key in _territory_map.keys():
		var parts := String(key).split(",")
		if parts.size() != 2:
			continue
		_update_territory_overlay_for(Vector2i(int(parts[0]), int(parts[1])))

func _update_territory_overlay_for(axial: Vector2i) -> void:
	var owner := int(_territory_map.get(_coordinate_key(axial), GameState.TerritoryOwnership.NEUTRAL))
	if owner == GameState.TerritoryOwnership.NEUTRAL:
		_territory_overlay_cache.erase(axial)
		return
	var corners: PackedVector2Array = _corners_for_axial(axial)
	if corners.is_empty():
		return
	_territory_overlay_cache[axial] = {
		"corners": corners,
		"color": _color_for_owner(owner)
	}

func _is_axial_on_map(axial: Vector2i) -> bool:
	return axial.x >= 0 and axial.y >= 0 and axial.x < GRID_COLUMNS and axial.y < GRID_ROWS

func _is_screen_position_on_map_hex(screen_pos: Vector2) -> bool:
	var world_position := _screen_to_world(screen_pos)
	var axial := _world_to_axial(world_position)
	return _is_axial_on_map(axial)

func _axial_to_world(axial: Vector2i) -> Vector2:
	var center := _center_for_axial(axial)
	if center == Vector2.INF:
		return _axial_center_world_fast(axial.x, axial.y)
	return center

func _axial_center_world_fast(q: int, r: int) -> Vector2:
	var horizontal_spacing := hex_size * SQRT3
	var vertical_spacing := hex_size * 1.5
	var x := horizontal_spacing * (q + 0.5 * float(r & 1))
	var y := vertical_spacing * r
	return map_offset + MAP_PADDING + Vector2(x, y)

func _world_to_axial(world: Vector2) -> Vector2i:
	_ensure_geometry_cache()
	var hex_size_squared := hex_size * hex_size
	var local := world - map_offset - MAP_PADDING
	var axial_q := (SQRT3 / 3.0 * local.x - 1.0 / 3.0 * local.y) / hex_size
	var axial_r := (2.0 / 3.0 * local.y) / hex_size
	var rounded_axial := _hex_round(axial_q, axial_r)
	var candidate := _axial_from_cube(rounded_axial)

	if _is_candidate_precise_hit(world, candidate, hex_size_squared):
		return candidate

	var fallback := _nearest_in_local_neighborhood(world, candidate, hex_size_squared)
	if fallback != Vector2i(-1, -1):
		return fallback

	return Vector2i(-1, -1)

func _is_candidate_precise_hit(world: Vector2, candidate: Vector2i, max_hit_distance_squared: float) -> bool:
	if not _is_axial_on_map(candidate):
		return false
	return _center_for_axial(candidate).distance_squared_to(world) <= max_hit_distance_squared

func _nearest_in_local_neighborhood(world: Vector2, candidate: Vector2i, max_hit_distance_squared: float) -> Vector2i:
	var best_axial := Vector2i(-1, -1)
	var best_distance_squared := INF
	var neighborhood := [candidate]
	neighborhood.append_array(_adjacent_axials(candidate))

	for axial in neighborhood:
		if not _is_axial_on_map(axial):
			continue
		var distance_squared := _center_for_axial(axial).distance_squared_to(world)
		if distance_squared < best_distance_squared:
			best_distance_squared = distance_squared
			best_axial = axial

	if best_distance_squared <= max_hit_distance_squared:
		return best_axial

	return Vector2i(-1, -1)

func _adjacent_axials(axial: Vector2i) -> Array[Vector2i]:
	var center_cube := _cube_from_axial(axial)
	var cube_directions := [
		Vector2i(1, 0),
		Vector2i(1, -1),
		Vector2i(0, -1),
		Vector2i(-1, 0),
		Vector2i(-1, 1),
		Vector2i(0, 1)
	]
	var neighbors: Array[Vector2i] = []
	for direction in cube_directions:
		neighbors.append(_axial_from_cube(center_cube + direction))
	return neighbors

func _cube_from_axial(axial: Vector2i) -> Vector2i:
	var cube_q := axial.x - ((axial.y - (axial.y & 1)) / 2)
	return Vector2i(cube_q, axial.y)

func _axial_from_cube(cube: Vector2i) -> Vector2i:
	var offset_q := cube.x + ((cube.y - (cube.y & 1)) / 2)
	return Vector2i(offset_q, cube.y)

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
		var angle := deg_to_rad(60.0 * i + 30.0)
		points.append(center + Vector2(cos(angle), sin(angle)) * hex_size)
	return points

func _center_for_axial(axial: Vector2i) -> Vector2:
	var entry: Dictionary = _hex_geometry_cache.get(axial, {})
	if entry.is_empty():
		return Vector2.INF
	return entry.get("center", Vector2.INF)

func _corners_for_axial(axial: Vector2i) -> PackedVector2Array:
	var entry: Dictionary = _hex_geometry_cache.get(axial, {})
	if entry.is_empty():
		return PackedVector2Array()
	return entry.get("corners", PackedVector2Array())

func _view_transform() -> Transform2D:
	return Transform2D(0.0, Vector2.ONE * zoom, 0.0, pan_offset)

func _screen_to_world(screen_pos: Vector2, sample_zoom: float = -1.0) -> Vector2:
	var active_zoom := zoom if sample_zoom < 0.0 else sample_zoom
	return (screen_pos - pan_offset) / active_zoom
