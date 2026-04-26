extends Control
class_name OrgChartView

signal unit_selected(unit: UnitModel)
signal delete_requested(unit: UnitModel)
signal unit_move_requested(unit: UnitModel, new_parent: UnitModel)

const NODE_SIZE := Vector2(160.0, 72.0)
const LEVEL_SPACING := 180.0
const SIBLING_SPACING := 36.0
const MIN_ZOOM := 0.5
const MAX_ZOOM := 2.0
const TOGGLE_SIZE := 16.0

var root_unit: UnitModel
var selected_unit: UnitModel
var _node_rects: Dictionary = {}
var _collapsed_by_unit_id: Dictionary = {}
var _toggle_hitboxes: Dictionary = {}
var _pan_offset := Vector2(80.0, 60.0)
var _zoom := 1.0
var _is_panning := false
var _active_pan_button := -1
var _drag_candidate: UnitModel
var _dragging_unit: UnitModel
var _is_dragging := false
var _drag_mouse_position := Vector2.ZERO
const DRAG_THRESHOLD := 8.0

func set_organization(root: UnitModel, selected: UnitModel) -> void:
	root_unit = root
	selected_unit = selected
	_collapsed_by_unit_id.clear()
	_toggle_hitboxes.clear()
	queue_redraw()

func set_selected_unit(unit: UnitModel) -> void:
	selected_unit = unit
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_MIDDLE:
			if mouse_event.pressed:
				_is_panning = true
				_active_pan_button = MOUSE_BUTTON_MIDDLE
			else:
				_is_panning = false
				_active_pan_button = -1
			accept_event()
			return

		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_event.pressed:
			_zoom = clamp(_zoom + 0.1, MIN_ZOOM, MAX_ZOOM)
			queue_redraw()
			accept_event()
			return

		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_event.pressed:
			_zoom = clamp(_zoom - 0.1, MIN_ZOOM, MAX_ZOOM)
			queue_redraw()
			accept_event()
			return

		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			var toggle_id := _pick_toggle(mouse_event.position)
			if not toggle_id.is_empty():
				if toggle_id != root_unit.id:
					var is_collapsed := bool(_collapsed_by_unit_id.get(toggle_id, false))
					_collapsed_by_unit_id[toggle_id] = not is_collapsed
				queue_redraw()
				accept_event()
				return

			var clicked := _pick_unit(mouse_event.position)
			if clicked != null:
				if clicked == selected_unit:
					_drag_candidate = clicked
					_drag_mouse_position = mouse_event.position
					accept_event()
					return

				_drag_candidate = null
				_dragging_unit = null
				_is_dragging = false
				selected_unit = clicked
				emit_signal("unit_selected", clicked)
				queue_redraw()
				accept_event()
				return


		if mouse_event.button_index == MOUSE_BUTTON_LEFT and not mouse_event.pressed:
			if _is_dragging and _dragging_unit != null:
				var drop_target := _pick_unit(mouse_event.position)
				if drop_target != null and drop_target != _dragging_unit:
					emit_signal("unit_move_requested", _dragging_unit, drop_target)
				accept_event()
			_drag_candidate = null
			_dragging_unit = null
			_is_dragging = false
			queue_redraw()
			return

		if mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
			var clicked_delete := _pick_unit(mouse_event.position)
			if clicked_delete != null:
				emit_signal("delete_requested", clicked_delete)
				accept_event()
			return

	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _is_panning:
			_pan_offset += motion.relative
			queue_redraw()
			accept_event()
			return

		if motion.button_mask & MOUSE_BUTTON_MASK_LEFT and _drag_candidate == null and not _is_dragging:
			_pan_offset += motion.relative
			queue_redraw()
			accept_event()
			return

		if _drag_candidate != null and not _is_dragging:
			if _drag_mouse_position.distance_to(motion.position) >= DRAG_THRESHOLD:
				_dragging_unit = _drag_candidate
				_is_dragging = true

		if _is_dragging:
			_drag_mouse_position = motion.position
			queue_redraw()
			accept_event()

func _draw() -> void:
	_node_rects.clear()
	_toggle_hitboxes.clear()
	if root_unit == null:
		return

	var next_y := 0.0
	_draw_subtree(root_unit, 0, next_y)

func _draw_subtree(unit: UnitModel, depth: int, next_y: float) -> float:
	var has_children := not unit.children.is_empty()
	var is_collapsed := bool(_collapsed_by_unit_id.get(unit.id, false))
	if unit == root_unit:
		is_collapsed = false

	var child_centers: Array[float] = []
	var working_y := next_y

	if has_children and not is_collapsed:
		for child in unit.children:
			if child == null:
				continue
			working_y = _draw_subtree(child, depth + 1, working_y)
			var child_rect: Rect2 = _node_rects.get(child.id, Rect2())
			child_centers.append(child_rect.get_center().y)

	var center_y := 0.0
	if child_centers.is_empty():
		center_y = next_y + NODE_SIZE.y * 0.5
		working_y = next_y + NODE_SIZE.y + SIBLING_SPACING
	else:
		center_y = (child_centers.front() + child_centers.back()) * 0.5

	var rect := Rect2(
		Vector2(float(depth) * LEVEL_SPACING, center_y - NODE_SIZE.y * 0.5),
		NODE_SIZE
	)
	_node_rects[unit.id] = rect
	var screen_rect := _to_screen_rect(rect)
	_draw_unit_node(unit, screen_rect, has_children, is_collapsed)

	if has_children and not is_collapsed:
		for child in unit.children:
			if child == null:
				continue
			var child_rect: Rect2 = _node_rects.get(child.id, Rect2())
			if child_rect.size == Vector2.ZERO:
				continue
			var from := _to_screen_point(Vector2(rect.end.x, rect.get_center().y))
			var to := _to_screen_point(Vector2(child_rect.position.x, child_rect.get_center().y))
			draw_line(from, to, Color(0.65, 0.72, 0.8), 2.0)

	if _is_dragging and _dragging_unit != null and unit == _dragging_unit:
		draw_line(screen_rect.get_center(), _drag_mouse_position, Color(0.27, 0.76, 1.0, 0.8), 2.0)

	return working_y

func _draw_unit_node(unit: UnitModel, rect: Rect2, has_children: bool, is_collapsed: bool) -> void:
	var is_selected := unit == selected_unit
	var border := Color(0.85, 0.89, 0.95)
	var fill := Color(0.14, 0.16, 0.21)
	if is_selected:
		border = Color(0.27, 0.76, 1.0)
		fill = Color(0.12, 0.23, 0.33)

	draw_rect(rect, fill, true)
	draw_rect(rect, border, false, 2.0)
	_draw_nato_symbol(unit, rect)

	if has_children:
		var toggle_rect := Rect2(
			rect.position + Vector2(rect.size.x - TOGGLE_SIZE - 6.0, 6.0),
			Vector2(TOGGLE_SIZE, TOGGLE_SIZE)
		)
		_toggle_hitboxes[unit.id] = toggle_rect
		draw_rect(toggle_rect, Color(0.08, 0.1, 0.14), true)
		draw_rect(toggle_rect, border, false, 1.0)
		var toggle_label := "+" if is_collapsed else "−"
		var label_position := toggle_rect.position + Vector2(4.0, TOGGLE_SIZE - 3.0)
		draw_string(get_theme_default_font(), label_position, toggle_label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, Color.WHITE)

	var title := _display_name_from_template_id(unit.template_id)
	var label := "%s\n%s %s" % [title, UnitSize.display_name(unit.size), UnitType.display_name(unit.type)]
	draw_multiline_string(
		get_theme_default_font(),
		rect.position + Vector2(8.0, rect.size.y - 30.0),
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		rect.size.x - 12.0,
		14,
		2,
		Color.WHITE
	)

func _draw_nato_symbol(unit: UnitModel, rect: Rect2) -> void:
	var inner := rect.grow(-12.0)
	var symbol_rect := Rect2(inner.position + Vector2(0.0, 6.0), Vector2(inner.size.x, 24.0))
	draw_rect(symbol_rect, Color(0.02, 0.03, 0.04), false, 2.0)

	match unit.type:
		UnitType.Value.INFANTRY:
			draw_line(symbol_rect.position, symbol_rect.end, Color.WHITE, 1.8)
			draw_line(Vector2(symbol_rect.end.x, symbol_rect.position.y), Vector2(symbol_rect.position.x, symbol_rect.end.y), Color.WHITE, 1.8)
		UnitType.Value.TANK:
			draw_circle(symbol_rect.get_center(), 8.0, Color.WHITE)
		UnitType.Value.ARTILLERY:
			draw_circle(symbol_rect.get_center(), 4.0, Color.WHITE)
			draw_arc(symbol_rect.get_center(), 9.0, 0.0, TAU, 24, Color.WHITE, 1.5)
		UnitType.Value.RECON:
			draw_polyline([
				symbol_rect.position + Vector2(5.0, symbol_rect.size.y * 0.5),
				symbol_rect.position + Vector2(symbol_rect.size.x - 5.0, symbol_rect.size.y * 0.5)
			], Color.WHITE, 2.0)
		UnitType.Value.HEADQUARTERS:
			draw_line(symbol_rect.get_center(), symbol_rect.get_center() + Vector2(0.0, 16.0), Color.WHITE, 2.0)
		_:
			draw_line(symbol_rect.position + Vector2(6.0, symbol_rect.size.y * 0.5), symbol_rect.end - Vector2(6.0, symbol_rect.size.y * 0.5), Color.WHITE, 2.0)

	var echelon_y := symbol_rect.position.y - 5.0
	var echelon_center := symbol_rect.get_center().x
	match unit.size:
		UnitSize.Value.SQUAD:
			draw_circle(Vector2(echelon_center - 4.0, echelon_y), 2.0, Color.WHITE)
			draw_circle(Vector2(echelon_center + 4.0, echelon_y), 2.0, Color.WHITE)
		UnitSize.Value.SECTION:
			draw_circle(Vector2(echelon_center - 8.0, echelon_y), 2.0, Color.WHITE)
			draw_circle(Vector2(echelon_center, echelon_y), 2.0, Color.WHITE)
			draw_circle(Vector2(echelon_center + 8.0, echelon_y), 2.0, Color.WHITE)
		UnitSize.Value.PLATOON:
			draw_circle(Vector2(echelon_center, echelon_y), 2.2, Color.WHITE)
		UnitSize.Value.COMPANY:
			draw_line(Vector2(echelon_center - 10.0, echelon_y), Vector2(echelon_center + 10.0, echelon_y), Color.WHITE, 2.0)
		UnitSize.Value.BATTALION:
			draw_line(Vector2(echelon_center - 10.0, echelon_y), Vector2(echelon_center + 10.0, echelon_y), Color.WHITE, 2.0)
			draw_line(Vector2(echelon_center, echelon_y - 4.0), Vector2(echelon_center, echelon_y + 4.0), Color.WHITE, 2.0)
		UnitSize.Value.REGIMENT:
			draw_circle(Vector2(echelon_center - 6.0, echelon_y), 2.0, Color.WHITE)
			draw_circle(Vector2(echelon_center + 6.0, echelon_y), 2.0, Color.WHITE)
		UnitSize.Value.DIVISION:
			draw_circle(Vector2(echelon_center - 8.0, echelon_y), 2.0, Color.WHITE)
			draw_circle(Vector2(echelon_center, echelon_y), 2.0, Color.WHITE)
			draw_circle(Vector2(echelon_center + 8.0, echelon_y), 2.0, Color.WHITE)
		UnitSize.Value.ARMY:
			draw_line(Vector2(echelon_center - 12.0, echelon_y), Vector2(echelon_center + 12.0, echelon_y), Color.WHITE, 2.0)
			draw_line(Vector2(echelon_center - 8.0, echelon_y - 4.0), Vector2(echelon_center - 8.0, echelon_y + 4.0), Color.WHITE, 2.0)
			draw_line(Vector2(echelon_center + 8.0, echelon_y - 4.0), Vector2(echelon_center + 8.0, echelon_y + 4.0), Color.WHITE, 2.0)

func _pick_unit(position: Vector2) -> UnitModel:
	for unit_id in _node_rects.keys():
		var rect: Rect2 = _to_screen_rect(_node_rects[unit_id])
		if rect.has_point(position):
			return _find_by_id(root_unit, unit_id)
	return null

func _pick_toggle(position: Vector2) -> String:
	for unit_id in _toggle_hitboxes.keys():
		var rect: Rect2 = _toggle_hitboxes[unit_id]
		if rect.has_point(position):
			return unit_id
	return ""

func _to_screen_rect(rect: Rect2) -> Rect2:
	return Rect2(rect.position * _zoom + _pan_offset, rect.size * _zoom)

func _to_screen_point(point: Vector2) -> Vector2:
	return point * _zoom + _pan_offset

func _find_by_id(node: UnitModel, node_id: String) -> UnitModel:
	if node == null:
		return null
	if node.id == node_id:
		return node
	for child in node.children:
		var found := _find_by_id(child, node_id)
		if found != null:
			return found
	return null

func _display_name_from_template_id(template_id: String) -> String:
	if template_id.is_empty():
		return "Unit"
	var raw := template_id
	var segments := raw.split("_")
	if segments.size() > 1 and String(segments[segments.size() - 1]).is_valid_int():
		segments.remove_at(segments.size() - 1)
	if not segments.is_empty() and segments[0].length() <= 3:
		segments.remove_at(0)
	if segments.is_empty():
		return "Unit"
	var words: Array[String] = []
	for segment in segments:
		words.append(String(segment).capitalize())
	return " ".join(words)
