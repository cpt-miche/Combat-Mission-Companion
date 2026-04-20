extends Control

const OrderSystem = preload("res://scripts/systems/OrderSystem.gd")
const Pathfinding = preload("res://scripts/systems/Pathfinding.gd")
const TurnResolver = preload("res://scripts/systems/TurnResolver.gd")
const CombatLog = preload("res://scripts/systems/CombatLog.gd")

const GRID_COLUMNS := 8
const GRID_ROWS := 6
const HEX_RADIUS := 32.0
const HEX_HORIZONTAL_SPACING := HEX_RADIUS * 1.7320508
const HEX_VERTICAL_SPACING := HEX_RADIUS * 1.5
const HEX_ORIGIN := Vector2(120.0, 220.0)

@onready var info_label: Label = %InfoLabel
@onready var log_label: RichTextLabel = %CombatLogLabel
@onready var end_turn_button: Button = %EndTurnButton
@onready var animation_timer: Timer = %AnimationTimer

var _units: Dictionary = {}
var _orders: Dictionary = {}
var _combat_log := CombatLog.new()
var _selected_unit_id := ""
var _active_player := 0
var _execution_queue: Array[Dictionary] = []

func _ready() -> void:
	_load_or_initialize_units()
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	animation_timer.timeout.connect(_on_animation_step)
	_refresh_log()
	info_label.text = "Right-click to issue move. Ctrl+Right-click to issue attack."

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var mouse_event := event as InputEventMouseButton
		var clicked_hex := _find_hex(mouse_event.position)
		if clicked_hex.is_empty():
			return
		var hex := Vector2i(clicked_hex["q"], clicked_hex["r"])

		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if _delete_path_at(hex):
				queue_redraw()
				info_label.text = "Order deleted."
				return
			_selected_unit_id = _unit_at_hex(hex, _active_player)
			if not _selected_unit_id.is_empty():
				info_label.text = "Selected %s" % _selected_unit_id
			queue_redraw()
			return

		if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			if _selected_unit_id.is_empty():
				info_label.text = "Select a friendly unit first."
				return
			var start_hex := _units[_selected_unit_id].get("hex", Vector2i.ZERO) as Vector2i
			var is_attack := Input.is_key_pressed(KEY_CTRL)
			var target_id := ""
			if is_attack:
				target_id = _unit_at_hex(hex, 1 - _active_player)
				if target_id.is_empty():
					info_label.text = "Attack orders require an enemy target hex."
					return
			var blocked := _blocked_cells(_selected_unit_id)
			if is_attack:
				blocked.erase("%d,%d" % [hex.x, hex.y])
			var path := Pathfinding.find_path(start_hex, hex, GameState.terrain_map, blocked)
			if path.is_empty():
				info_label.text = "No path found."
				return

			if is_attack:
				_orders = OrderSystem.upsert_order(_orders, OrderSystem.create_attack_order(_selected_unit_id, path, target_id))
				info_label.text = "Attack order created for %s." % _selected_unit_id
			else:
				_orders = OrderSystem.upsert_order(_orders, OrderSystem.create_move_order(_selected_unit_id, path))
				info_label.text = "Move order created for %s." % _selected_unit_id
			queue_redraw()

func _draw() -> void:
	for row in range(GRID_ROWS):
		for column in range(GRID_COLUMNS):
			var center := _hex_center(column, row)
			var points := _hex_points(center)
			draw_colored_polygon(points, Color(0.15, 0.18, 0.2, 0.9))
			draw_polyline(points + PackedVector2Array([points[0]]), Color(0.35, 0.4, 0.45, 1.0), 1.5)

	for order in _orders.values():
		if typeof(order) != TYPE_DICTIONARY:
			continue
		_draw_order(order)

	for unit_id in _units.keys():
		var unit := _units[unit_id] as Dictionary
		var hex := unit.get("hex", Vector2i.ZERO) as Vector2i
		var center := _hex_center(hex.x, hex.y)
		var color := Color(0.24, 0.43, 0.92, 1.0) if int(unit.get("owner", 0)) == 0 else Color(0.89, 0.29, 0.27, 1.0)
		if String(unit_id) == _selected_unit_id:
			color = color.lightened(0.25)
		draw_circle(center, 16.0, color)
		draw_string(get_theme_default_font(), center + Vector2(-12, 4), String(unit_id), HORIZONTAL_ALIGNMENT_LEFT, -1, 12)

func _draw_order(order: Dictionary) -> void:
	var path := order.get("path", []) as Array[Vector2i]
	if path.size() < 2:
		return
	var color := Color.GREEN if int(order.get("type", 0)) == OrderSystem.OrderType.MOVE else Color.RED
	for i in range(path.size() - 1):
		var from_center := _hex_center(path[i].x, path[i].y)
		var to_center := _hex_center(path[i + 1].x, path[i + 1].y)
		draw_line(from_center, to_center, color, 3.0)
	if int(order.get("type", 0)) == OrderSystem.OrderType.ATTACK:
		var end_hex: Vector2i = path[path.size() - 1]
		var c := _hex_center(end_hex.x, end_hex.y)
		draw_line(c + Vector2(-8, -8), c + Vector2(8, 8), color, 2.0)
		draw_line(c + Vector2(8, -8), c + Vector2(-8, 8), color, 2.0)

func _on_end_turn_pressed() -> void:
	var result := TurnResolver.resolve_turn(_units.duplicate(true), _orders, _combat_log)
	_units = result.get("units", {})
	_persist_units_to_state()
	_execution_queue = result.get("execution_queue", [])
	GameState.combat_log_entries = _combat_log.entries.duplicate(true)
	GameState.pending_casualties = {
		"own": result.get("own_casualties", []),
		"enemy": result.get("enemy_casualties", []),
		"known_enemy_units": result.get("known_enemy_units", [])
	}
	_orders.clear()
	if _execution_queue.is_empty():
		_refresh_log()
		GameState.set_phase(GameState.Phase.CASUALTY_ENTRY)
		return
	animation_timer.start()
	end_turn_button.disabled = true

func _on_animation_step() -> void:
	if _execution_queue.is_empty():
		animation_timer.stop()
		end_turn_button.disabled = false
		_active_player = 1 - _active_player
		GameState.current_turn += 1
		_refresh_log()
		GameState.set_phase(GameState.Phase.CASUALTY_ENTRY)
		return
	var step := _execution_queue.pop_front()
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
		_units = GameState.gameplay_units.duplicate(true)
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
			var id := String(unit_data.get("id", "P%d_U_%d_%d" % [player_index + 1, q, r]))
			generated[id] = {
				"id": id,
				"owner": player_index,
				"hex": Vector2i(q, r),
				"initiative": 50,
				"recon_bonus": 0 if bool(unit_data.get("is_tank", false)) else 5,
				"concealment": 5
			}
	_units = generated
	GameState.gameplay_units = _units.duplicate(true)

func _blocked_cells(selected_unit_id: String) -> Dictionary:
	var blocked := {}
	for unit_id in _units.keys():
		if String(unit_id) == selected_unit_id:
			continue
		var hex := (_units[unit_id] as Dictionary).get("hex", Vector2i.ZERO) as Vector2i
		blocked["%d,%d" % [hex.x, hex.y]] = true
	return blocked

func _delete_path_at(hex: Vector2i) -> bool:
	for unit_id in _orders.keys():
		var order := _orders[unit_id] as Dictionary
		var path := order.get("path", []) as Array[Vector2i]
		if path.has(hex):
			_orders = OrderSystem.delete_order(_orders, String(unit_id))
			return true
	return false

func _unit_at_hex(hex: Vector2i, owner: int) -> String:
	for unit_id in _units.keys():
		var unit := _units[unit_id] as Dictionary
		if int(unit.get("owner", -1)) != owner:
			continue
		if unit.get("hex", Vector2i.ZERO) == hex:
			return String(unit_id)
	return ""

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
