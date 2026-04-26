extends Control
class_name DeploymentHexMapView

class BaseCacheLayer extends Control:
	var owner_view: DeploymentHexMapView
	var cache_origin := Vector2.ZERO

	func _draw() -> void:
		if owner_view == null:
			return
		owner_view._draw_base_cache_into(self, cache_origin)

signal hex_selected(column: int, row: int)

const SQRT3 := 1.7320508075688772
var GRID_COLUMNS: int = MapGridConfig.default_columns()
var GRID_ROWS: int = MapGridConfig.default_rows()
const HEX_RADIUS := 30.0
const HEX_HORIZONTAL_SPACING := HEX_RADIUS * SQRT3
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

var _geometry_dirty := true
var _base_cache_dirty := true
var _base_cache_origin := Vector2.ZERO
var _base_cache_size := Vector2i.ZERO
var _last_geometry_signature := ""
var _hex_geometry_cache: Dictionary[Vector2i, Dictionary] = {}
var _map_axials_packed := PackedVector2Array()
var _base_viewport: SubViewport
var _base_layer: BaseCacheLayer

func _ready() -> void:
	var dimensions := GameState.selected_map_dimensions
	GRID_COLUMNS = maxi(dimensions.x, 1)
	GRID_ROWS = maxi(dimensions.y, 1)
	clip_contents = true
	_setup_base_cache_viewport()
	_mark_geometry_dirty()

func configure(new_territory_map: Dictionary, new_placements: Dictionary, player_index: int, is_deploy_mode: bool = true) -> void:
	territory_map = new_territory_map.duplicate(true)
	placements_by_player = new_placements.duplicate(true)
	visible_player_index = player_index
	deploy_mode = is_deploy_mode
	_mark_base_cache_dirty()
	queue_redraw()

func _draw() -> void:
	_sync_geometry_state()
	_ensure_geometry_cache()
	_ensure_base_cache()

	draw_set_transform(pan_offset, 0.0, Vector2.ONE)
	if _base_viewport != null and _base_cache_size.x > 0 and _base_cache_size.y > 0:
		draw_texture(_base_viewport.get_texture(), _base_cache_origin)
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
		var axial := Vector2i(int(parts[0]), int(parts[1]))
		var center := _center_for_axial(axial)
		if center == Vector2.INF:
			center = _hex_center(axial.x, axial.y)
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
	_sync_geometry_state()
	_ensure_geometry_cache()

	var rough_row := int(round((position.y - HEX_ORIGIN.y) / HEX_VERTICAL_SPACING))
	var row_start: int = max(0, rough_row - 1)
	var row_end: int = min(GRID_ROWS - 1, rough_row + 1)
	for row in range(row_start, row_end + 1):
		var row_offset: float = HEX_HORIZONTAL_SPACING * 0.5 if row % 2 == 1 else 0.0
		var rough_column := int(round((position.x - HEX_ORIGIN.x - row_offset) / HEX_HORIZONTAL_SPACING))
		var column_start: int = max(0, rough_column - 1)
		var column_end: int = min(GRID_COLUMNS - 1, rough_column + 1)
		for column in range(column_start, column_end + 1):
			var axial := Vector2i(column, row)
			var corners := _corners_for_axial(axial)
			if corners.is_empty():
				continue
			if Geometry2D.is_point_in_polygon(position, corners):
				return {"q": column, "r": row}
	return {}

func _to_world(screen_position: Vector2) -> Vector2:
	return screen_position - pan_offset

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
	var signature := "%d|%d|%.4f" % [GRID_COLUMNS, GRID_ROWS, HEX_RADIUS]
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
	_hex_geometry_cache.clear()
	_map_axials_packed = PackedVector2Array()

	var min_bound := Vector2(INF, INF)
	var max_bound := Vector2(-INF, -INF)
	for row in range(GRID_ROWS):
		for column in range(GRID_COLUMNS):
			var axial := Vector2i(column, row)
			var center := _hex_center(column, row)
			var corners := _hex_points(center)
			_hex_geometry_cache[axial] = {
				"center": center,
				"corners": corners
			}
			_map_axials_packed.append(Vector2(column, row))
			for corner in corners:
				min_bound.x = min(min_bound.x, corner.x)
				min_bound.y = min(min_bound.y, corner.y)
				max_bound.x = max(max_bound.x, corner.x)
				max_bound.y = max(max_bound.y, corner.y)

	if _map_axials_packed.is_empty():
		min_bound = Vector2.ZERO
		max_bound = Vector2.ZERO

	_base_cache_origin = min_bound.floor()
	var bounds_size := (max_bound - min_bound).ceil() + Vector2.ONE * 2.0
	_base_cache_size = Vector2i(max(1, int(bounds_size.x)), max(1, int(bounds_size.y)))
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
	for packed_axial in _map_axials_packed:
		var axial := Vector2i(int(packed_axial.x), int(packed_axial.y))
		var corners := _corners_for_axial(axial)
		if corners.is_empty():
			continue
		var local := PackedVector2Array()
		local.resize(corners.size())
		for i in range(corners.size()):
			local[i] = corners[i] - cache_origin
		var owner := _owner_for(axial.x, axial.y)
		canvas.draw_colored_polygon(local, _color_for_owner(owner))
		var border := local
		if not border.is_empty():
			border.append(border[0])
		canvas.draw_polyline(border, Color(0.12, 0.12, 0.12, 0.95), 2.0, true)

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
