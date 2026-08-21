extends Control
class_name DeploymentHexMapView

const NatoUnitSymbolRenderer = preload("res://scripts/ui/shared/NatoUnitSymbolRenderer.gd")
const DeploymentValidator = preload("res://scripts/domain/units/DeploymentValidator.gd")
const TerrainCatalog = preload("res://scripts/core/TerrainCatalog.gd")

class BaseCacheLayer extends Control:
	var owner_view: DeploymentHexMapView
	var cache_origin := Vector2.ZERO

	func _draw() -> void:
		if owner_view == null:
			return
		owner_view._draw_base_cache_into(self, cache_origin)

signal hex_selected(column: int, row: int)
signal hex_stack_selected(column: int, row: int)
signal hex_undeploy_requested(column: int, row: int)
signal deployment_cancel_requested

const SQRT3 := 1.7320508075688772
var GRID_COLUMNS: int = MapGridConfig.default_columns()
var GRID_ROWS: int = MapGridConfig.default_rows()
const HEX_RADIUS := 30.0
const HEX_HORIZONTAL_SPACING := HEX_RADIUS * SQRT3
const HEX_VERTICAL_SPACING := HEX_RADIUS * 1.5
const HEX_ORIGIN := Vector2(80.0, 120.0)
const MIN_ZOOM := 0.5
const MAX_ZOOM := 2.0
const ZOOM_FACTOR := 1.15
const NON_DEPLOYABLE_OVERLAY_COLOR := Color(0.32, 0.32, 0.32, 0.42)

var terrain_map: Dictionary = {}
var territory_map: Dictionary = {}
var objective_map: Dictionary = {}
var placements_by_player: Dictionary = {}
var visible_player_index := 0
var deploy_mode := true
var pan_offset := Vector2.ZERO
var zoom_level := 1.0
var selected_hex := Vector2i(-1, -1)
var armed_unit_id := ""
var armed_unit_ids: Array[String] = []
var _is_panning := false
var _drag_distance := 0.0
var _suppress_left_release := false
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

func configure(new_terrain_map: Dictionary, new_territory_map: Dictionary, new_placements: Dictionary, player_index: int, is_deploy_mode: bool = true, new_objective_map: Dictionary = {}) -> void:
	terrain_map = new_terrain_map.duplicate(true)
	territory_map = new_territory_map.duplicate(true)
	objective_map = new_objective_map.duplicate(true)
	placements_by_player = new_placements.duplicate(true)
	visible_player_index = player_index
	deploy_mode = is_deploy_mode
	_mark_base_cache_dirty()
	queue_redraw()

func _draw() -> void:
	_sync_geometry_state()
	_ensure_geometry_cache()
	_ensure_base_cache()

	draw_set_transform(pan_offset, 0.0, Vector2.ONE * zoom_level)
	if _base_viewport != null and _base_cache_size.x > 0 and _base_cache_size.y > 0:
		draw_texture(_base_viewport.get_texture(), _base_cache_origin)
	_draw_visible_placements()
	_draw_objectives()
	_draw_selected_hex()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_zoom_at(mouse_button.position, zoom_level * ZOOM_FACTOR)
			accept_event()
			return
		if mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_zoom_at(mouse_button.position, zoom_level / ZOOM_FACTOR)
			accept_event()
			return
	if not deploy_mode:
		return
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_LEFT and mouse_button.pressed:
			if mouse_button.double_click:
				_is_panning = false
				_drag_distance = 0.0
				_suppress_left_release = true
				var double_clicked_coordinate := _find_hex(_to_world(mouse_button.position))
				if not double_clicked_coordinate.is_empty():
					emit_signal("hex_stack_selected", int(double_clicked_coordinate["q"]), int(double_clicked_coordinate["r"]))
				accept_event()
				return
			_is_panning = true
			_drag_distance = 0.0
			accept_event()
			return
		if mouse_button.button_index == MOUSE_BUTTON_LEFT and not mouse_button.pressed:
			if _suppress_left_release:
				_suppress_left_release = false
				accept_event()
				return
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
		if mouse_button.button_index == MOUSE_BUTTON_RIGHT and mouse_button.pressed:
			if not armed_unit_ids.is_empty() or not armed_unit_id.is_empty():
				emit_signal("deployment_cancel_requested")
				accept_event()
				return
			var coordinate := _find_hex(_to_world(mouse_button.position))
			if not coordinate.is_empty():
				emit_signal("hex_undeploy_requested", int(coordinate["q"]), int(coordinate["r"]))
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
		var placed_units := _placement_units_from_variant(placements[key])
		if placed_units.is_empty():
			continue
		var front_unit := placed_units[placed_units.size() - 1]
		var stack_has_armed_unit := false
		for unit in placed_units:
			var unit_id := String(unit.get("id", ""))
			if armed_unit_ids.has(unit_id) or unit_id == armed_unit_id:
				stack_has_armed_unit = true
			if unit_id == armed_unit_id:
				front_unit = unit
		NatoUnitSymbolRenderer.draw_stack(
			self,
			center,
			front_unit,
			visible_player_index,
			placed_units.size(),
			get_theme_default_font(),
			HEX_RADIUS / NatoUnitSymbolRenderer.REFERENCE_HEX_RADIUS,
			stack_has_armed_unit,
			stack_has_armed_unit,
			1.0,
			zoom_level * HEX_RADIUS / NatoUnitSymbolRenderer.REFERENCE_HEX_RADIUS
		)

func set_selected_hex(hex: Vector2i) -> void:
	selected_hex = hex
	queue_redraw()

func set_armed_unit(unit_id: String) -> void:
	armed_unit_id = unit_id
	armed_unit_ids.clear()
	if not unit_id.is_empty():
		armed_unit_ids.append(unit_id)
	queue_redraw()

func set_armed_units(unit_ids: Array[String], primary_unit_id: String = "") -> void:
	armed_unit_ids.clear()
	for unit_id in unit_ids:
		if not unit_id.is_empty() and not armed_unit_ids.has(unit_id):
			armed_unit_ids.append(unit_id)
	armed_unit_id = primary_unit_id if armed_unit_ids.has(primary_unit_id) else (armed_unit_ids[armed_unit_ids.size() - 1] if not armed_unit_ids.is_empty() else "")
	queue_redraw()

func _draw_objectives() -> void:
	for key_variant in objective_map.keys():
		var parts := String(key_variant).split(",")
		if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
			continue
		var axial := Vector2i(int(parts[0]), int(parts[1]))
		if axial.x < 0 or axial.y < 0 or axial.x >= GRID_COLUMNS or axial.y >= GRID_ROWS:
			continue
		var objective_variant: Variant = objective_map[key_variant]
		if typeof(objective_variant) != TYPE_DICTIONARY:
			continue
		var priority := String((objective_variant as Dictionary).get("priority", ""))
		if priority not in ["primary", "secondary"]:
			continue
		var primary := priority == "primary"
		var center := _center_for_axial(axial)
		if center == Vector2.INF:
			center = _hex_center(axial.x, axial.y)
		var color := Color(1.0, 0.72, 0.12, 0.95) if primary else Color(0.68, 0.82, 1.0, 0.9)
		var radius := HEX_RADIUS * (0.78 if primary else 0.68)
		var width := 3.0 if primary else 2.0
		draw_arc(center, radius, 0.0, TAU, 28, color, width, true)
		var tick_length := HEX_RADIUS * 0.12
		var directions: Array[Vector2] = [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]
		for direction in directions:
			var start: Vector2 = center + direction * (radius - tick_length)
			var finish: Vector2 = center + direction * (radius + tick_length)
			draw_line(start, finish, color, width, true)

func _draw_selected_hex() -> void:
	if selected_hex.x < 0 or selected_hex.y < 0 or selected_hex.x >= GRID_COLUMNS or selected_hex.y >= GRID_ROWS:
		return
	var corners := _corners_for_axial(selected_hex)
	if corners.is_empty():
		return
	var outline := corners.duplicate()
	outline.append(corners[0])
	draw_polyline(outline, Color(1.0, 0.86, 0.24, 0.95), 3.0, true)

func _placement_units_from_variant(placement_variant: Variant) -> Array[Dictionary]:
	var units: Array[Dictionary] = []
	if typeof(placement_variant) == TYPE_DICTIONARY:
		units.append(placement_variant as Dictionary)
	elif typeof(placement_variant) == TYPE_ARRAY:
		for unit_variant in (placement_variant as Array):
			if typeof(unit_variant) == TYPE_DICTIONARY:
				units.append(unit_variant as Dictionary)
	return units

func _placement_label(placed_units: Array[Dictionary]) -> String:
	if placed_units.size() == 1:
		return String(placed_units[0].get("label", "U"))
	return "%s×%d" % [String(placed_units[0].get("label", "U")), placed_units.size()]

func _placement_color(player_index: int) -> Color:
	if player_index == 0:
		return Color(0.18, 0.34, 0.86, 0.95)
	return Color(0.83, 0.24, 0.2, 0.95)

func _owner_for(column: int, row: int) -> int:
	return int(territory_map.get("%d,%d" % [column, row], GameState.TerritoryOwnership.NEUTRAL))

func _fill_color_for_hex(column: int, row: int) -> Color:
	var key := "%d,%d" % [column, row]
	var terrain_id := TerrainCatalog.normalize_terrain_id(String(terrain_map.get(key, TerrainCatalog.default_terrain_id())))
	return TerrainCatalog.editor_color(terrain_id, 1.0)

func _restriction_overlay_for_hex(column: int, row: int) -> Color:
	if deploy_mode and not DeploymentValidator.can_deploy_in_territory(_owner_for(column, row), visible_player_index):
		return NON_DEPLOYABLE_OVERLAY_COLOR
	return Color.TRANSPARENT

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
	return (screen_position - pan_offset) / zoom_level

func _to_screen(world_position: Vector2) -> Vector2:
	return world_position * zoom_level + pan_offset

func _set_zoom_at(screen_position: Vector2, requested_zoom: float) -> void:
	var next_zoom := clampf(requested_zoom, MIN_ZOOM, MAX_ZOOM)
	if is_equal_approx(next_zoom, zoom_level):
		return
	var anchored_world_position := _to_world(screen_position)
	zoom_level = next_zoom
	pan_offset = screen_position - anchored_world_position * zoom_level
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
		canvas.draw_colored_polygon(local, _fill_color_for_hex(axial.x, axial.y))
		var restriction_overlay := _restriction_overlay_for_hex(axial.x, axial.y)
		if restriction_overlay.a > 0.0:
			canvas.draw_colored_polygon(local, restriction_overlay)
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
