extends Control

const OrderSystem = preload("res://scripts/systems/OrderSystem.gd")
const Pathfinding = preload("res://scripts/systems/Pathfinding.gd")
const TurnResolver = preload("res://scripts/systems/TurnResolver.gd")
const CombatLog = preload("res://scripts/systems/CombatLog.gd")
const TerrainCatalog = preload("res://scripts/core/TerrainCatalog.gd")
const Rules = preload("res://scripts/core/Rules.gd")

var GRID_COLUMNS: int = MapGridConfig.default_columns()
var GRID_ROWS: int = MapGridConfig.default_rows()
const HEX_RADIUS := 32.0
const HEX_HORIZONTAL_SPACING := HEX_RADIUS * 1.7320508
const HEX_VERTICAL_SPACING := HEX_RADIUS * 1.5
const HEX_ORIGIN := Vector2(120.0, 220.0)
const PATH_PREVIEW_THROTTLE_MS := 75
const UNIT_MARKER_RADIUS := 16.0
const DRAG_START_THRESHOLD := 6.0
enum OrderMode { MOVE, ATTACK, DIG_IN }

@onready var info_label: Label = %InfoLabel
@onready var log_label: RichTextLabel = %CombatLogLabel
@onready var end_turn_button: Button = %EndTurnButton
@onready var order_action_panel: PanelContainer = %OrderActionPanel
@onready var move_button: Button = %MoveButton
@onready var attack_button: Button = %AttackButton
@onready var dig_in_button: Button = %DigInButton
@onready var hovered_terrain_label: Label = %HoveredTerrainLabel
@onready var animation_timer: Timer = %AnimationTimer
@onready var selected_hex_title_label: Label = %SelectedHexTitleLabel
@onready var selected_hex_terrain_label: Label = %SelectedHexTerrainLabel
@onready var selected_hex_units_label: Label = %SelectedHexUnitsLabel

var _units: Dictionary = {}
var _orders: Dictionary = {}
var _combat_log := CombatLog.new()
var _selected_unit_id := ""
var _active_player := 0
var _execution_queue: Array[Dictionary] = []
var _hex_polygon_cache: Dictionary = {}
var _unit_marker_pool: Array[Dictionary] = []
var _order_arrow_pool: Array[Dictionary] = []
var _active_unit_marker_count := 0
var _active_order_arrow_count := 0
var _preview_target_hex := Vector2i(-9999, -9999)
var _preview_path: Array[Vector2i] = []
var _pending_preview_target_hex := Vector2i(-9999, -9999)
var _preview_recalc_due_at_msec := 0
var _camera_offset := Vector2.ZERO
var _is_panning := false
var _drag_candidate_unit_id := ""
var _dragging_unit_id := ""
var _drag_start_mouse_pos := Vector2.ZERO
var _drag_mouse_pos := Vector2.ZERO
var _hovered_hex := Vector2i(-9999, -9999)
var _selected_hex := Vector2i(-9999, -9999)
var _active_order_mode: OrderMode = OrderMode.MOVE
var _friendly_selection_cycle_by_hex: Dictionary = {}

func _ready() -> void:
	var dimensions := GameState.selected_map_dimensions
	GRID_COLUMNS = maxi(dimensions.x, 1)
	GRID_ROWS = maxi(dimensions.y, 1)
	_active_player = clampi(GameState.active_player, 0, 1)
	_load_or_initialize_units()
	_rebuild_hex_polygon_cache()
	_begin_player_turn()
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	move_button.pressed.connect(_on_move_mode_pressed)
	attack_button.pressed.connect(_on_attack_mode_pressed)
	dig_in_button.pressed.connect(_on_dig_in_mode_pressed)
	animation_timer.timeout.connect(_on_animation_step)
	_refresh_log()
	_update_info_label()
	_update_order_action_panel()
	_update_hovered_terrain_label(TerrainCatalog.default_terrain_id())
	_refresh_selected_hex_panel(_selected_hex)

func _process(_delta: float) -> void:
	if _preview_recalc_due_at_msec <= 0:
		return
	if Time.get_ticks_msec() < _preview_recalc_due_at_msec:
		return
	_preview_recalc_due_at_msec = 0
	_recalculate_preview_path()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		_handle_mouse_motion(motion)
		return

	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				_handle_left_press(mouse_event.position)
			else:
				_handle_left_release(mouse_event.position)
			return

		if not mouse_event.pressed:
			return

		var clicked_hex := _find_hex(mouse_event.position)
		if clicked_hex.is_empty():
			return
		var hex := Vector2i(clicked_hex["q"], clicked_hex["r"])

		if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			if _selected_unit_id.is_empty():
				_update_info_label("Select a friendly unit first.")
				return
			if _active_order_mode == OrderMode.MOVE:
				if _issue_move_order(_selected_unit_id, hex):
					_update_info_label("Move order created for %s." % _selected_unit_id)
					queue_redraw()
				return
			if _active_order_mode == OrderMode.DIG_IN:
				_issue_dig_in_order(_selected_unit_id)
				return
			var target_id := ""
			target_id = _unit_at_hex(hex, 1 - _active_player)
			if target_id.is_empty():
				_update_info_label("Attack orders require an enemy target hex.")
				return
			var start_hex := _units[_selected_unit_id].get("hex", Vector2i.ZERO) as Vector2i
			var blocked := _blocked_cells(_selected_unit_id)
			blocked.erase("%d,%d" % [hex.x, hex.y])
			var path := Pathfinding.find_path(start_hex, hex, GameState.terrain_map, blocked)
			if path.is_empty():
				_update_info_label("No path found.")
				return

			_orders = OrderSystem.upsert_order(_orders, OrderSystem.create_attack_order(_selected_unit_id, path, target_id))
			_update_info_label("Attack order created for %s." % _selected_unit_id)
			_preview_path.clear()
			_preview_target_hex = Vector2i(-9999, -9999)
			queue_redraw()

func _handle_left_press(position: Vector2) -> void:
	_drag_start_mouse_pos = position
	_drag_mouse_pos = position
	_drag_candidate_unit_id = _pick_friendly_unit_at(position)
	_dragging_unit_id = ""
	if _drag_candidate_unit_id.is_empty():
		_is_panning = true

func _handle_left_release(position: Vector2) -> void:
	var total_drag := position.distance_to(_drag_start_mouse_pos)
	if _is_panning:
		_is_panning = false
		if total_drag <= DRAG_START_THRESHOLD:
			var clicked_hex := _find_hex(position)
			if clicked_hex.is_empty():
				return
			var hex := Vector2i(clicked_hex["q"], clicked_hex["r"])
			_selected_hex = hex
			_refresh_selected_hex_panel(_selected_hex)
			var friendly_at_hex := _unit_at_hex(hex, _active_player)
			if _delete_path_at(hex):
				queue_redraw()
				_update_info_label("Order deleted.")
				return
			_selected_unit_id = friendly_at_hex
			_preview_path.clear()
			_preview_target_hex = Vector2i(-9999, -9999)
			if not _selected_unit_id.is_empty():
				_update_info_label("Selected %s" % _selected_unit_id)
			_update_order_action_panel()
			queue_redraw()
		return

	if not _dragging_unit_id.is_empty():
		var dropped_hex_dict := _find_hex(position)
		if dropped_hex_dict.is_empty():
			_update_info_label("Drop on a hex to create a move order.")
		else:
			var dropped_hex := Vector2i(dropped_hex_dict["q"], dropped_hex_dict["r"])
			if _issue_move_order(_dragging_unit_id, dropped_hex):
				_update_info_label("Move order created for %s." % _dragging_unit_id)
		_preview_path.clear()
		_preview_target_hex = Vector2i(-9999, -9999)
		_pending_preview_target_hex = Vector2i(-9999, -9999)
	elif not _drag_candidate_unit_id.is_empty() and total_drag <= DRAG_START_THRESHOLD:
		var clicked_hex := _find_hex(position)
		if not clicked_hex.is_empty():
			_selected_hex = Vector2i(clicked_hex["q"], clicked_hex["r"])
			_refresh_selected_hex_panel(_selected_hex)
		_selected_unit_id = _drag_candidate_unit_id
		_update_info_label("Selected %s" % _selected_unit_id)
	_drag_candidate_unit_id = ""
	_dragging_unit_id = ""
	_update_order_action_panel()
	queue_redraw()

func _refresh_selected_hex_panel(hex: Vector2i) -> void:
	if hex == Vector2i(-9999, -9999):
		selected_hex_title_label.text = "Selected Hex: -, -"
		selected_hex_terrain_label.text = "Terrain: %s" % TerrainCatalog.display_name(TerrainCatalog.default_terrain_id())
		selected_hex_units_label.text = "Units: None"
		return

	var coordinate_key := "%d,%d" % [hex.x, hex.y]
	selected_hex_title_label.text = "Selected Hex: %s" % coordinate_key

	var terrain_id := String(GameState.terrain_map.get(coordinate_key, TerrainCatalog.default_terrain_id()))
	terrain_id = TerrainCatalog.normalize_terrain_id(terrain_id)
	selected_hex_terrain_label.text = "Terrain: %s" % TerrainCatalog.display_name(terrain_id)

	var unit_lines: Array[String] = []
	for entry in _units_at_hex(hex):
		var unit := entry.get("unit", {}) as Dictionary
		var unit_id := String(entry.get("id", ""))
		var line := "%s (owner %d)" % [String(unit.get("id", unit_id)), int(entry.get("owner", -1))]
		if unit.has("unit_type"):
			line += " - %s" % String(unit.get("unit_type", ""))
		if unit.has("status"):
			line += " [%s]" % String(unit.get("status", ""))
		if unit_id == _selected_unit_id:
			line += " [SELECTED]"
		unit_lines.append(line)

	if unit_lines.is_empty():
		selected_hex_units_label.text = "Units: None"
		return
	selected_hex_units_label.text = "Units:\n%s" % "\n".join(unit_lines)

func _handle_mouse_motion(motion: InputEventMouseMotion) -> void:
	if _is_panning:
		_camera_offset += motion.relative
		_update_hovered_hex(motion.position)
		queue_redraw()
		return
	_update_hovered_hex(motion.position)
	_drag_mouse_pos = motion.position
	if _dragging_unit_id.is_empty() and not _drag_candidate_unit_id.is_empty():
		if _drag_start_mouse_pos.distance_to(motion.position) >= DRAG_START_THRESHOLD:
			_dragging_unit_id = _drag_candidate_unit_id
			_selected_unit_id = _dragging_unit_id
			_preview_path.clear()
			_preview_target_hex = Vector2i(-9999, -9999)
	if not _dragging_unit_id.is_empty():
		_handle_path_preview_motion(motion.position)
		queue_redraw()
		return
	_handle_path_preview_motion(motion.position)

func _draw() -> void:
	var visible_rect := Rect2(Vector2.ZERO, size).grow(HEX_RADIUS * 2.0)
	_active_order_arrow_count = 0
	_active_unit_marker_count = 0

	for row in range(GRID_ROWS):
		for column in range(GRID_COLUMNS):
			var axial := Vector2i(column, row)
			var world_center := _hex_center(column, row)
			var center := _world_to_screen(world_center)
			if not visible_rect.has_point(center):
				continue
			var world_points: PackedVector2Array = _hex_polygon_cache.get(axial, _hex_points(world_center)) as PackedVector2Array
			var points := PackedVector2Array()
			for point in world_points:
				points.append(_world_to_screen(point))
			draw_colored_polygon(points, Color(0.15, 0.18, 0.2, 0.9))
			draw_polyline(points + PackedVector2Array([points[0]]), Color(0.35, 0.4, 0.45, 1.0), 1.5)

	for order in _orders.values():
		if typeof(order) != TYPE_DICTIONARY:
			continue
		_collect_order_arrow(order, false)

	if _preview_path.size() >= 2:
		_collect_order_arrow({
			"type": OrderSystem.OrderType.MOVE,
			"path": _preview_path
		}, true)

	for i in range(_active_order_arrow_count):
		_draw_order_arrow(_order_arrow_pool[i])

	for row in range(GRID_ROWS):
		for column in range(GRID_COLUMNS):
			var hex := Vector2i(column, row)
			var stack := _units_at_hex(hex)
			if stack.is_empty():
				continue
			var base_center := _world_to_screen(_hex_center(hex.x, hex.y))
			if not visible_rect.has_point(base_center):
				continue
			for index in range(stack.size()):
				var entry := stack[index] as Dictionary
				var unit := entry.get("unit", {}) as Dictionary
				var unit_id := String(entry.get("id", ""))
				var marker_offset := _stack_offset_for_index(index, stack.size())
				var center := base_center + marker_offset
				var color := Color(0.24, 0.43, 0.92, 1.0) if int(entry.get("owner", 0)) == 0 else Color(0.89, 0.29, 0.27, 1.0)
				if unit_id == _selected_unit_id:
					color = color.lightened(0.25)
				var is_selected := unit_id == _selected_unit_id
				_collect_unit_marker(center, color, unit_id, stack.size(), is_selected)
				if unit.has("status") and String(unit.get("status", "")).to_lower() == "dead":
					continue

	for i in range(_active_unit_marker_count):
		_draw_unit_marker(_unit_marker_pool[i])

	if not _dragging_unit_id.is_empty():
		var drag_color := Color(0.95, 0.95, 0.55, 0.9)
		draw_circle(_drag_mouse_pos, UNIT_MARKER_RADIUS, drag_color)
		draw_string(get_theme_default_font(), _drag_mouse_pos + Vector2(-12, 4), _dragging_unit_id, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)

func _collect_order_arrow(order: Dictionary, is_preview: bool) -> void:
	var path := order.get("path", []) as Array
	if path.size() < 2:
		return
	var idx := _active_order_arrow_count
	if idx >= _order_arrow_pool.size():
		_order_arrow_pool.append({})
	_order_arrow_pool[idx] = {
		"path": path,
		"order_type": int(order.get("type", 0)),
		"is_preview": is_preview
	}
	_active_order_arrow_count += 1

func _draw_order_arrow(entry: Dictionary) -> void:
	var path := entry.get("path", []) as Array
	var order_type := int(entry.get("order_type", 0))
	var is_preview := bool(entry.get("is_preview", false))
	var color := Color(0.45, 0.95, 0.45, 0.9) if order_type == OrderSystem.OrderType.MOVE else Color(0.95, 0.35, 0.35, 0.9)
	var width := 3.0
	if is_preview:
		color = Color(0.95, 0.95, 0.4, 0.85)
		width = 2.0
	for i in range(path.size() - 1):
		var from_hex: Vector2i = path[i]
		var to_hex: Vector2i = path[i + 1]
		draw_line(_world_to_screen(_hex_center(from_hex.x, from_hex.y)), _world_to_screen(_hex_center(to_hex.x, to_hex.y)), color, width)
	if order_type == OrderSystem.OrderType.ATTACK and not is_preview:
		var end_hex: Vector2i = path[path.size() - 1]
		var center := _world_to_screen(_hex_center(end_hex.x, end_hex.y))
		draw_line(center + Vector2(-8, -8), center + Vector2(8, 8), color, 2.0)
		draw_line(center + Vector2(8, -8), center + Vector2(-8, 8), color, 2.0)

func _collect_unit_marker(center: Vector2, color: Color, unit_id: String, stack_size: int, is_selected: bool) -> void:
	var idx := _active_unit_marker_count
	if idx >= _unit_marker_pool.size():
		_unit_marker_pool.append({})
	_unit_marker_pool[idx] = {
		"center": center,
		"color": color,
		"id": unit_id,
		"stack_size": stack_size,
		"is_selected": is_selected
	}
	_active_unit_marker_count += 1

func _draw_unit_marker(marker: Dictionary) -> void:
	var center := marker.get("center", Vector2.ZERO) as Vector2
	var is_selected := bool(marker.get("is_selected", false))
	draw_circle(center, UNIT_MARKER_RADIUS, marker.get("color", Color.WHITE))
	if is_selected:
		draw_arc(center, UNIT_MARKER_RADIUS + 3.0, 0.0, TAU, 24, Color(1.0, 1.0, 0.45, 0.95), 2.5)
	draw_string(get_theme_default_font(), center + Vector2(-12, 4), String(marker.get("id", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
	var stack_size := int(marker.get("stack_size", 1))
	if stack_size > 1:
		var badge_radius := 8.0
		var badge_center := center + Vector2(UNIT_MARKER_RADIUS * 0.7, -UNIT_MARKER_RADIUS * 0.7)
		draw_circle(badge_center, badge_radius, Color(0.07, 0.08, 0.1, 0.95))
		draw_string(get_theme_default_font(), badge_center + Vector2(-4, 4), str(stack_size), HORIZONTAL_ALIGNMENT_LEFT, -1, 11)

func _pick_friendly_unit_at(screen_position: Vector2) -> String:
	var clicked_hex_dict := _find_hex(screen_position)
	if clicked_hex_dict.is_empty():
		return ""
	var clicked_hex := Vector2i(clicked_hex_dict["q"], clicked_hex_dict["r"])
	var friendly_stack := _units_at_hex(clicked_hex, _active_player)
	if friendly_stack.is_empty():
		return ""

	var base_center := _world_to_screen(_hex_center(clicked_hex.x, clicked_hex.y))
	for index in range(friendly_stack.size()):
		var marker_center := base_center + _stack_offset_for_index(index, friendly_stack.size())
		if marker_center.distance_to(screen_position) <= UNIT_MARKER_RADIUS:
			return String((friendly_stack[index] as Dictionary).get("id", ""))

	var marker_center := base_center
	if marker_center.distance_to(screen_position) > UNIT_MARKER_RADIUS * 1.9:
		return ""
	return _next_friendly_unit_for_hex(clicked_hex)

func _issue_move_order(unit_id: String, target_hex: Vector2i) -> bool:
	if unit_id.is_empty() or not _units.has(unit_id):
		return false
	if not GameState.is_unit_alive(_units[unit_id] as Dictionary):
		_update_info_label("%s is dead and cannot receive orders." % unit_id)
		return false
	var start_hex := (_units[unit_id] as Dictionary).get("hex", Vector2i.ZERO) as Vector2i
	var stack_validation := _validate_move_destination_stack(unit_id, target_hex)
	if not bool(stack_validation.get("ok", false)):
		_update_info_label(String(stack_validation.get("reason", "Illegal destination stack.")))
		return false
	var blocked := _blocked_cells(unit_id)
	var path := Pathfinding.find_path(start_hex, target_hex, GameState.terrain_map, blocked)
	if path.is_empty():
		_update_info_label("No path found.")
		return false
	_orders = OrderSystem.upsert_order(_orders, OrderSystem.create_move_order(unit_id, path))
	_preview_path.clear()
	_preview_target_hex = Vector2i(-9999, -9999)
	return true

func _issue_dig_in_order(unit_id: String) -> void:
	if unit_id.is_empty() or not _units.has(unit_id):
		_update_info_label("Select a friendly unit first.")
		return
	var unit := _units[unit_id] as Dictionary
	if int(unit.get("owner", -1)) != _active_player:
		_update_info_label("Only friendly units can dig in.")
		return
	var hex := unit.get("hex", Vector2i.ZERO) as Vector2i
	_orders = OrderSystem.upsert_order(_orders, OrderSystem.create_dig_in_order(unit_id))
	_update_info_label("Dig In order created for %s." % unit_id)
	queue_redraw()

func _update_order_action_panel() -> void:
	var has_friendly_selected := (not _selected_unit_id.is_empty()) and _units.has(_selected_unit_id) and int((_units[_selected_unit_id] as Dictionary).get("owner", -1)) == _active_player
	order_action_panel.visible = has_friendly_selected

func _set_order_mode(mode: OrderMode) -> void:
	_active_order_mode = mode
	_update_info_label()

func _on_move_mode_pressed() -> void:
	_set_order_mode(OrderMode.MOVE)

func _on_attack_mode_pressed() -> void:
	_set_order_mode(OrderMode.ATTACK)

func _on_dig_in_mode_pressed() -> void:
	_set_order_mode(OrderMode.DIG_IN)
	if not _selected_unit_id.is_empty():
		_issue_dig_in_order(_selected_unit_id)

func _order_mode_text() -> String:
	match _active_order_mode:
		OrderMode.ATTACK:
			return "Attack"
		OrderMode.DIG_IN:
			return "Dig In"
		_:
			return "Move"

func _update_info_label(status_message: String = "") -> void:
	var controls := "Mode: %s | Left-click unit to select, drag selected unit to create a move path, click+drag empty space to pan, right-click hex to issue mode action." % _order_mode_text()
	if status_message.is_empty():
		info_label.text = controls
		return
	info_label.text = "%s %s" % [status_message, controls]

func _on_end_turn_pressed() -> void:
	_orders = _prune_orders_for_dead_units(_orders)
	var result := TurnResolver.resolve_turn(_units.duplicate(true), _orders, _combat_log, {
		"scout_intel_by_observer": GameState.scout_intel_by_observer.duplicate(true),
		"active_owner": _active_player
	})
	_units = result.get("units", {})
	GameState.scout_intel_by_observer = result.get("scout_intel_by_observer", GameState.scout_intel_by_observer).duplicate(true)
	_persist_units_to_state()
	_execution_queue = result.get("execution_queue", [])
	GameState.combat_log_entries = _combat_log.entries.duplicate(true)
	GameState.pending_casualties = {
		"own": result.get("own_casualties", []),
		"enemy": result.get("enemy_casualties", []),
		"known_enemy_units": result.get("known_enemy_units", [])
	}
	_orders.clear()
	_preview_path.clear()
	_preview_target_hex = Vector2i(-9999, -9999)
	if _execution_queue.is_empty():
		_refresh_log()
		GameState.set_phase(GameState.Phase.CASUALTY_ENTRY)
		return
	animation_timer.start()
	end_turn_button.disabled = true

func _prune_orders_for_dead_units(orders: Dictionary) -> Dictionary:
	var next_orders := orders.duplicate(true)
	for unit_id in orders.keys():
		if not _units.has(unit_id):
			next_orders.erase(unit_id)
			continue
		var unit := _units[unit_id] as Dictionary
		if not GameState.is_unit_alive(unit):
			next_orders.erase(unit_id)
	return next_orders

func _on_animation_step() -> void:
	if _execution_queue.is_empty():
		animation_timer.stop()
		end_turn_button.disabled = false
		_active_player = 1 - _active_player
		GameState.active_player = _active_player
		GameState.current_turn += 1
		_begin_player_turn()
		_refresh_log()
		GameState.set_phase(GameState.Phase.CASUALTY_ENTRY)
		return
	var step: Dictionary = _execution_queue.pop_front() as Dictionary
	if String(step.get("type", "")) != "move":
		return
	var unit_id := String(step.get("unit_id", ""))
	if not _units.has(unit_id):
		return
	var unit := _units[unit_id] as Dictionary
	unit["hex"] = step.get("to", unit.get("hex", Vector2i.ZERO))
	_units[unit_id] = unit
	_persist_units_to_state()
	queue_redraw()

func _refresh_log() -> void:
	log_label.clear()
	for line in _combat_log.to_feed_lines():
		log_label.append_text("%s\n" % line)

func _persist_units_to_state() -> void:
	GameState.gameplay_units = _units.duplicate(true)

func _load_or_initialize_units() -> void:
	if not GameState.gameplay_units.is_empty():
		_units = _without_headquarters_units(GameState.gameplay_units)
		GameState.gameplay_units = _units.duplicate(true)
		return
	var generated: Dictionary = {}
	for player_index in range(min(GameState.players.size(), 2)):
		var deployments := GameState.players[player_index].get("deployments", {}) as Dictionary
		for key in deployments.keys():
			var split := String(key).split(",")
			if split.size() != 2:
				continue
			var q := int(split[0])
			var r := int(split[1])
			var unit_data := deployments[key] as Dictionary
			if not GameState.is_unit_alive(unit_data):
				continue
			var unit_type := _normalized_unit_type(unit_data.get("type", "infantry"))
			if unit_type == "headquarters":
				continue
			var id := String(unit_data.get("id", "P%d_U_%d_%d" % [player_index + 1, q, r]))
			generated[id] = {
				"id": id,
				"owner": player_index,
				"hex": Vector2i(q, r),
				"initiative": 50,
				"unit_type": unit_type,
				"formation_size": String(unit_data.get("size", "company")),
				"status": String(unit_data.get("status", "alive")).to_lower(),
				"is_alive": bool(unit_data.get("is_alive", String(unit_data.get("status", "alive")).to_lower() != "dead")),
				"recon_bonus": 0 if bool(unit_data.get("is_tank", false)) else 5,
				"concealment": 5
			}
	_units = generated
	GameState.gameplay_units = _units.duplicate(true)

func _without_headquarters_units(units: Dictionary) -> Dictionary:
	var filtered := {}
	for unit_id_variant in units.keys():
		var unit_id := String(unit_id_variant)
		var unit_variant: Variant = units[unit_id_variant]
		if typeof(unit_variant) != TYPE_DICTIONARY:
			continue
		var unit := unit_variant as Dictionary
		var unit_type := _normalized_unit_type(unit.get("unit_type", unit.get("type", "infantry")))
		if unit_type == "headquarters":
			continue
		filtered[unit_id] = unit.duplicate(true)
	return filtered

func _normalized_unit_type(raw_type: Variant) -> String:
	if typeof(raw_type) == TYPE_INT:
		match int(raw_type):
			UnitType.Value.INFANTRY:
				return "infantry"
			UnitType.Value.TANK:
				return "tank"
			UnitType.Value.ENGINEER:
				return "engineer"
			UnitType.Value.ARTILLERY:
				return "artillery"
			UnitType.Value.RECON:
				return "recon"
			UnitType.Value.AIRBORNE:
				return "airborne"
			UnitType.Value.MECHANIZED:
				return "mechanized"
			UnitType.Value.MOTORIZED:
				return "motorized"
			UnitType.Value.ANTI_TANK:
				return "anti_tank"
			UnitType.Value.AIR_DEFENSE:
				return "air_defense"
			UnitType.Value.HEADQUARTERS:
				return "headquarters"
			_:
				return String(raw_type).strip_edges().to_lower()
	return String(raw_type).strip_edges().to_lower()

func _begin_player_turn() -> void:
	_autosave_current_game()

func _autosave_current_game() -> void:
	GameState.active_player = _active_player
	var autosave_payload: Dictionary = {
		"turn_number": GameState.current_turn,
		"active_player": _active_player,
		"map": {
			"grid_columns": GRID_COLUMNS,
			"grid_rows": GRID_ROWS,
			"hex_radius": HEX_RADIUS,
			"hex_origin": {"x": HEX_ORIGIN.x, "y": HEX_ORIGIN.y}
		},
		"terrain": GameState.terrain_map.duplicate(true),
		"territory": GameState.territory_map.duplicate(true),
		"units": _serialize_units(_units),
		"orders": _serialize_orders(_orders),
		"casualties": GameState.pending_casualties.duplicate(true)
	}
	SaveManager.autosave(autosave_payload)

func _serialize_units(units: Dictionary) -> Dictionary:
	var serialized := {}
	for unit_id in units.keys():
		var unit := units[unit_id] as Dictionary
		var hex := unit.get("hex", Vector2i.ZERO) as Vector2i
		var next := unit.duplicate(true)
		next["hex"] = {"x": hex.x, "y": hex.y}
		serialized[unit_id] = next
	return serialized

func _serialize_orders(orders: Dictionary) -> Dictionary:
	var serialized := {}
	for unit_id in orders.keys():
		var order := orders[unit_id] as Dictionary
		var path_payload: Array[Dictionary] = []
		for waypoint in order.get("path", []):
			var hex: Vector2i = waypoint
			path_payload.append({"x": hex.x, "y": hex.y})
		var next := order.duplicate(true)
		next["path"] = path_payload
		serialized[unit_id] = next
	return serialized

func _rebuild_hex_polygon_cache() -> void:
	_hex_polygon_cache.clear()
	for row in range(GRID_ROWS):
		for column in range(GRID_COLUMNS):
			var center := _hex_center(column, row)
			_hex_polygon_cache[Vector2i(column, row)] = _hex_points(center)

func _handle_path_preview_motion(position: Vector2) -> void:
	if _selected_unit_id.is_empty():
		return
	var clicked_hex := _find_hex(position)
	if clicked_hex.is_empty():
		return
	var target := Vector2i(clicked_hex["q"], clicked_hex["r"])
	if target == _pending_preview_target_hex:
		return
	_pending_preview_target_hex = target
	_preview_recalc_due_at_msec = Time.get_ticks_msec() + PATH_PREVIEW_THROTTLE_MS

func _recalculate_preview_path() -> void:
	if _selected_unit_id.is_empty() or not _units.has(_selected_unit_id):
		return
	var target := _pending_preview_target_hex
	if target == Vector2i(-9999, -9999) or target == _preview_target_hex:
		return
	_preview_target_hex = target
	var start_hex := (_units[_selected_unit_id] as Dictionary).get("hex", Vector2i.ZERO) as Vector2i
	var stack_validation := _validate_move_destination_stack(_selected_unit_id, target)
	if not bool(stack_validation.get("ok", false)):
		_preview_path.clear()
		queue_redraw()
		return
	var blocked := _blocked_cells(_selected_unit_id)
	var path := Pathfinding.find_path(start_hex, target, GameState.terrain_map, blocked)
	_preview_path.clear()
	for step in path:
		_preview_path.append(step)
	queue_redraw()

func _blocked_cells(selected_unit_id: String) -> Dictionary:
	var blocked := {}
	for unit_id in _units.keys():
		if String(unit_id) == selected_unit_id:
			continue
		var unit := _units[unit_id] as Dictionary
		if not GameState.is_unit_alive(unit):
			continue
		if int(unit.get("owner", -1)) == _active_player:
			continue
		var hex := unit.get("hex", Vector2i.ZERO) as Vector2i
		blocked["%d,%d" % [hex.x, hex.y]] = true
	return blocked

func _validate_move_destination_stack(unit_id: String, target_hex: Vector2i) -> Dictionary:
	if not _units.has(unit_id):
		return {"ok": false, "reason": "Unknown unit for move order."}
	var moving := _units[unit_id] as Dictionary
	var occupants: Array[Dictionary] = []
	for other_id in _units.keys():
		var other := _units[other_id] as Dictionary
		if not GameState.is_unit_alive(other):
			continue
		if String(other_id) == unit_id:
			continue
		if int(other.get("owner", -1)) != int(moving.get("owner", -1)):
			continue
		if (other.get("hex", Vector2i.ZERO) as Vector2i) != target_hex:
			continue
		occupants.append(other)
	return Rules.can_enter_stack(moving, occupants)

func _delete_path_at(hex: Vector2i) -> bool:
	for unit_id in _orders.keys():
		var order := _orders[unit_id] as Dictionary
		var path := order.get("path", []) as Array[Vector2i]
		if path.has(hex):
			_orders = OrderSystem.delete_order(_orders, String(unit_id))
			return true
	return false


func _units_at_hex(hex: Vector2i, owner: int = -1) -> Array[Dictionary]:
	var units_at_hex: Array[Dictionary] = []
	for unit_id in _units.keys():
		var unit := _units[unit_id] as Dictionary
		if not GameState.is_unit_alive(unit):
			continue
		var unit_owner := int(unit.get("owner", -1))
		if owner >= 0 and unit_owner != owner:
			continue
		if unit.get("hex", Vector2i.ZERO) != hex:
			continue
		units_at_hex.append({
			"id": String(unit_id),
			"owner": unit_owner,
			"unit": unit
		})
	units_at_hex.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("id", "")) < String(b.get("id", ""))
	)
	return units_at_hex

func _unit_at_hex(hex: Vector2i, owner: int) -> String:
	var matches := _units_at_hex(hex, owner)
	if not matches.is_empty():
		return String(matches[0].get("id", ""))
	return ""

func _next_friendly_unit_for_hex(hex: Vector2i) -> String:
	var friendly := _units_at_hex(hex, _active_player)
	if friendly.is_empty():
		return ""
	var key := "%d,%d" % [hex.x, hex.y]
	var previous_index := int(_friendly_selection_cycle_by_hex.get(key, -1))
	var next_index := posmod(previous_index + 1, friendly.size())
	_friendly_selection_cycle_by_hex[key] = next_index
	return String(friendly[next_index].get("id", ""))

func _stack_offset_for_index(index: int, stack_size: int) -> Vector2:
	if stack_size <= 1:
		return Vector2.ZERO
	var columns := mini(stack_size, 3)
	var rows := int(ceil(float(stack_size) / float(columns)))
	var column := index % columns
	var row := index / columns
	var spacing := UNIT_MARKER_RADIUS * 1.1
	var width := float(columns - 1) * spacing
	var height := float(rows - 1) * spacing
	return Vector2((float(column) * spacing) - (width * 0.5), (float(row) * spacing) - (height * 0.5))

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
	var world_position := _screen_to_world(position)
	for row in range(GRID_ROWS):
		for column in range(GRID_COLUMNS):
			if Geometry2D.is_point_in_polygon(world_position, _hex_points(_hex_center(column, row))):
				return {"q": column, "r": row}
	return {}

func _world_to_screen(world_position: Vector2) -> Vector2:
	return world_position + _camera_offset

func _screen_to_world(screen_position: Vector2) -> Vector2:
	return screen_position - _camera_offset


func _update_hovered_hex(position: Vector2) -> void:
	var hovered_hex_dict := _find_hex(position)
	if hovered_hex_dict.is_empty():
		if _hovered_hex == Vector2i(-9999, -9999):
			return
		_hovered_hex = Vector2i(-9999, -9999)
		_update_hovered_terrain_label(TerrainCatalog.default_terrain_id())
		return

	var next_hovered_hex := Vector2i(hovered_hex_dict["q"], hovered_hex_dict["r"])
	if next_hovered_hex == _hovered_hex:
		return
	_hovered_hex = next_hovered_hex
	var coordinate_key := "%d,%d" % [_hovered_hex.x, _hovered_hex.y]
	var terrain_id := TerrainCatalog.normalize_terrain_id(String(GameState.terrain_map.get(coordinate_key, TerrainCatalog.default_terrain_id())))
	_update_hovered_terrain_label(terrain_id)


func _update_hovered_terrain_label(terrain_id: String) -> void:
	hovered_terrain_label.text = "Hovered Terrain: %s" % TerrainCatalog.display_name(terrain_id)
