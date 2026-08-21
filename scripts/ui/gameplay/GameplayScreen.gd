extends Control

const OrderSystem = preload("res://scripts/systems/OrderSystem.gd")
const Pathfinding = preload("res://scripts/systems/Pathfinding.gd")
const TurnResolver = preload("res://scripts/systems/TurnResolver.gd")
const GameplayAIService = preload("res://scripts/systems/gameplay_ai/GameplayAIService.gd")
const OperationalAIService = preload("res://scripts/systems/operational_ai/OperationalAIService.gd")
const FormationPosturePlanner = preload("res://scripts/systems/gameplay_ai/FormationPosturePlanner.gd")
const CombatLog = preload("res://scripts/systems/CombatLog.gd")
const TerrainCatalog = preload("res://scripts/core/TerrainCatalog.gd")
const Rules = preload("res://scripts/core/Rules.gd")
const UnitNotationFormatter = preload("res://scripts/domain/units/UnitNotationFormatter.gd")
const UnitHealthFormatter = preload("res://scripts/domain/units/UnitHealthFormatter.gd")
const FormationHierarchy = preload("res://scripts/domain/units/FormationHierarchy.gd")
const FormationOperations = preload("res://scripts/domain/units/FormationOperations.gd")
const NatoUnitSymbolRenderer = preload("res://scripts/ui/shared/NatoUnitSymbolRenderer.gd")

var GRID_COLUMNS: int = MapGridConfig.default_columns()
var GRID_ROWS: int = MapGridConfig.default_rows()
const HEX_RADIUS := 32.0
const HEX_HORIZONTAL_SPACING := HEX_RADIUS * 1.7320508
const HEX_VERTICAL_SPACING := HEX_RADIUS * 1.5
const HEX_ORIGIN := Vector2(120.0, 220.0)
const PATH_PREVIEW_THROTTLE_MS := 75
const UNIT_MARKER_RADIUS := 16.0
const DRAG_START_THRESHOLD := 6.0
const MIN_ZOOM := 0.5
const MAX_ZOOM := 2.0
const ZOOM_FACTOR := 1.15
const NEUTRAL_TERRITORY_COLOR := Color(0.15, 0.18, 0.2, 0.9)
const PLAYER_1_TERRITORY_COLOR := Color(0.20, 0.31, 0.43, 0.9)
const PLAYER_2_TERRITORY_COLOR := Color(0.43, 0.24, 0.23, 0.9)
enum OrderMode { MOVE, ATTACK, DIG_IN }

@onready var info_label: Label = %InfoLabel
@onready var end_turn_button: Button = %EndTurnButton
@onready var order_action_panel: PanelContainer = %OrderActionPanel
@onready var right_sidebar: PanelContainer = %RightSidebar
@onready var move_button: Button = %MoveButton
@onready var attack_button: Button = %AttackButton
@onready var dig_in_button: Button = %DigInButton
@onready var combine_button: Button = %CombineButton
@onready var split_button: Button = %SplitButton
@onready var hovered_terrain_label: Label = %HoveredTerrainLabel
@onready var animation_timer: Timer = %AnimationTimer
@onready var selected_hex_title_label: Label = %SelectedHexTitleLabel
@onready var selected_hex_ownership_label: Label = %SelectedHexOwnershipLabel
@onready var selected_hex_terrain_label: Label = %SelectedHexTerrainLabel
@onready var selected_hex_count_label: Label = %SelectedHexCountLabel
@onready var selected_hex_unit_cards: VBoxContainer = %SelectedHexUnitCards
@onready var selected_unit_title_label: Label = %SelectedUnitTitleLabel
@onready var selected_unit_summary_label: Label = %SelectedUnitSummaryLabel
@onready var selected_unit_order_label: Label = %SelectedUnitOrderLabel
@onready var selected_unit_formation_label: Label = %SelectedUnitFormationLabel
@onready var subordinates_toggle_button: Button = %SubordinatesToggleButton
@onready var subordinate_scroll: ScrollContainer = %SubordinateScroll
@onready var subordinate_list: VBoxContainer = %SubordinateList
@onready var events_toggle_button: Button = %EventsToggleButton
@onready var events_scroll: ScrollContainer = %EventsScroll
@onready var events_list: VBoxContainer = %EventsList
@onready var debug_level_modal: DebugLevelModal = %DebugLevelModal
@onready var debug_status_container: PanelContainer = %DebugStatusContainer
@onready var debug_status_label: Label = %DebugStatusLabel

var _units: Dictionary = {}
var _orders: Dictionary = {}
var _combat_log := CombatLog.new()
var _selected_unit_id := ""
var _selected_unit_ids: Array[String] = []
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
var _camera_zoom := 1.0
var _is_panning := false
var _drag_candidate_unit_id := ""
var _dragging_unit_id := ""
var _drag_start_mouse_pos := Vector2.ZERO
var _drag_mouse_pos := Vector2.ZERO
var _drag_candidate_was_selected := false
var _suppress_left_release := false
var _hovered_hex := Vector2i(-9999, -9999)
var _selected_hex := Vector2i(-9999, -9999)
var _active_order_mode: OrderMode = OrderMode.MOVE
var _friendly_selection_cycle_by_hex: Dictionary = {}
var _pending_battle_payload: Dictionary = {}
var _battle_highlight_hexes: Array[Vector2i] = []
var _battle_resolution_input_blocked := false
var _controls_disabled_before_battle_resolution := {}
var _scheduled_ai_turn_key := ""
var _subordinates_expanded := true
var _events_expanded := false
var _expanded_event_keys: Dictionary = {}

func _ready() -> void:
	var dimensions := GameState.selected_map_dimensions
	GRID_COLUMNS = maxi(dimensions.x, 1)
	GRID_ROWS = maxi(dimensions.y, 1)
	_active_player = clampi(GameState.active_player, 0, 1)
	_load_or_initialize_units()
	_combat_log.entries = GameState.combat_log_entries.duplicate(true)
	_orders = GameState.gameplay_orders.duplicate(true)
	_rebuild_hex_polygon_cache()
	_begin_player_turn()
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	move_button.pressed.connect(_on_move_mode_pressed)
	attack_button.pressed.connect(_on_attack_mode_pressed)
	dig_in_button.pressed.connect(_on_dig_in_mode_pressed)
	combine_button.pressed.connect(_on_combine_pressed)
	split_button.pressed.connect(_on_split_pressed)
	subordinates_toggle_button.pressed.connect(_on_subordinates_toggle_pressed)
	events_toggle_button.pressed.connect(_on_events_toggle_pressed)
	animation_timer.timeout.connect(_on_animation_step)
	_refresh_log()
	_update_info_label()
	_update_order_action_panel()
	_update_hovered_terrain_label(TerrainCatalog.default_terrain_id())
	_refresh_selected_hex_panel(_selected_hex)
	debug_level_modal.level_selected.connect(_on_debug_level_selected)
	debug_level_modal.canceled.connect(_on_debug_level_canceled)
	if not GameState.is_connected("debug_mode_changed", _on_debug_mode_changed):
		GameState.debug_mode_changed.connect(_on_debug_mode_changed)
	_refresh_debug_status_hud()
	_sync_battle_map_context()

func _process(_delta: float) -> void:
	if _battle_resolution_input_blocked:
		return
	if _preview_recalc_due_at_msec <= 0:
		return
	if Time.get_ticks_msec() < _preview_recalc_due_at_msec:
		return
	_preview_recalc_due_at_msec = 0
	_recalculate_preview_path()


func _unhandled_input(event: InputEvent) -> void:
	if _battle_resolution_input_blocked:
		return
	if event.is_action_pressed("debug_toggle"):
		_handle_debug_toggle()
		get_viewport().set_input_as_handled()

func _handle_debug_toggle() -> void:
	if GameState.debug_mode_enabled:
		GameState.disable_debug_mode()
		return
	debug_level_modal.open_modal()

func _on_debug_level_selected(level: int) -> void:
	GameState.enable_debug_mode(level)

func _on_debug_level_canceled() -> void:
	GameState.disable_debug_mode()

func _on_debug_mode_changed(enabled: bool, level: int) -> void:
	_refresh_debug_status_hud()
	_refresh_selected_hex_panel(_selected_hex)
	queue_redraw()
	if enabled:
		_update_info_label("Debug mode L%d" % level)
		return
	_update_info_label("Debug mode OFF")

func _refresh_debug_status_hud() -> void:
	debug_status_container.visible = GameState.debug_mode_enabled
	if not GameState.debug_mode_enabled:
		debug_status_label.text = ""
		return
	debug_status_label.text = "DEBUG L%d" % clampi(GameState.debug_mode_level, 1, 3)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if _battle_resolution_input_blocked:
		return
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		_handle_mouse_motion(motion)
		return

	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if _is_pointer_over_map_input_blocker(mouse_event.position):
				accept_event()
				return
			_set_camera_zoom_at(mouse_event.position, _camera_zoom * ZOOM_FACTOR)
			return
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if _is_pointer_over_map_input_blocker(mouse_event.position):
				accept_event()
				return
			_set_camera_zoom_at(mouse_event.position, _camera_zoom / ZOOM_FACTOR)
			return
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				if mouse_event.double_click:
					_suppress_left_release = true
					_handle_hex_stack_double_click(mouse_event.position)
				else:
					_handle_left_press(mouse_event.position)
			else:
				if _suppress_left_release:
					_suppress_left_release = false
					_reset_drag_input_state()
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
			var selected_unit_ids := _selected_order_unit_ids()
			if selected_unit_ids.is_empty():
				_update_info_label("Select a friendly unit first.")
				return
			if _active_order_mode == OrderMode.MOVE:
				_issue_group_move_orders(selected_unit_ids, hex)
				return
			if _active_order_mode == OrderMode.DIG_IN:
				_issue_group_dig_in_orders(selected_unit_ids)
				return
			_issue_group_attack_orders(selected_unit_ids, hex)

func _is_pointer_over_map_input_blocker(screen_position: Vector2) -> bool:
	var global_position: Vector2 = get_global_transform() * screen_position
	for control in [right_sidebar, order_action_panel, end_turn_button, debug_level_modal]:
		if control != null and control.is_visible_in_tree() and control.get_global_rect().has_point(global_position):
			return true
	return false

func _handle_left_press(position: Vector2) -> void:
	_drag_start_mouse_pos = position
	_drag_mouse_pos = position
	_drag_candidate_unit_id = _pick_friendly_unit_at(position)
	_drag_candidate_was_selected = _is_unit_selected(_drag_candidate_unit_id)
	_dragging_unit_id = ""
	if _drag_candidate_unit_id.is_empty():
		_is_panning = true

func _handle_hex_stack_double_click(position: Vector2) -> void:
	_reset_drag_input_state()
	var clicked_hex := _find_hex(position)
	if clicked_hex.is_empty():
		return
	_selected_hex = Vector2i(clicked_hex["q"], clicked_hex["r"])
	_clear_unit_selection()
	var friendly_stack := _units_at_hex(_selected_hex, _active_player, true)
	for entry in friendly_stack:
		var unit_id := String(entry.get("id", ""))
		if not unit_id.is_empty():
			_selected_unit_ids.append(unit_id)
	if not _selected_unit_ids.is_empty():
		_selected_unit_id = _selected_unit_ids[0]
	_preview_path.clear()
	_preview_target_hex = Vector2i(-9999, -9999)
	_pending_preview_target_hex = Vector2i(-9999, -9999)
	_update_order_action_panel()
	_refresh_selected_hex_panel(_selected_hex)
	_update_info_label(_unit_selection_status_text(_selected_unit_id))
	queue_redraw()

func _reset_drag_input_state() -> void:
	_is_panning = false
	_drag_candidate_unit_id = ""
	_drag_candidate_was_selected = false
	_dragging_unit_id = ""

func _handle_left_release(position: Vector2) -> void:
	var total_drag := position.distance_to(_drag_start_mouse_pos)
	if _is_panning:
		_is_panning = false
		if total_drag <= DRAG_START_THRESHOLD:
			var clicked_hex := _find_hex(position)
			if clicked_hex.is_empty():
				return
			var hex := Vector2i(clicked_hex["q"], clicked_hex["r"])
			var previously_selected_unit_ids := _selected_order_unit_ids()
			if hex != _selected_hex:
				_clear_unit_selection()
			_selected_hex = hex
			_refresh_selected_hex_panel(_selected_hex)
			if _delete_path_at(hex):
				_refresh_selected_hex_panel(_selected_hex)
				_update_order_action_panel()
				queue_redraw()
				_update_info_label("Order deleted.")
				return
			var friendly_at_hex := _unit_at_hex(hex, _active_player)
			if not previously_selected_unit_ids.is_empty() and _active_order_mode == OrderMode.MOVE and friendly_at_hex.is_empty():
				_issue_group_move_orders(previously_selected_unit_ids, hex)
				return
			_set_single_unit_selection(friendly_at_hex)
			_preview_path.clear()
			_preview_target_hex = Vector2i(-9999, -9999)
			if not _selected_unit_id.is_empty():
				_update_info_label("Selected %s" % _unit_display_name_by_id(_selected_unit_id))
			_update_order_action_panel()
			_refresh_selected_hex_panel(_selected_hex)
			queue_redraw()
		return

	if not _dragging_unit_id.is_empty():
		var dropped_hex_dict := _find_hex(position)
		if dropped_hex_dict.is_empty():
			_update_info_label("Drop on a hex to create a move order.")
		else:
			var dropped_hex := Vector2i(dropped_hex_dict["q"], dropped_hex_dict["r"])
			_issue_group_move_orders(_selected_order_unit_ids(), dropped_hex)
		_preview_path.clear()
		_preview_target_hex = Vector2i(-9999, -9999)
		_pending_preview_target_hex = Vector2i(-9999, -9999)
	elif not _drag_candidate_unit_id.is_empty() and total_drag <= DRAG_START_THRESHOLD:
		var clicked_hex := _find_hex(position)
		var clicked_unit_id := _drag_candidate_unit_id
		if not clicked_hex.is_empty():
			var unit_hex := Vector2i(clicked_hex["q"], clicked_hex["r"])
			if unit_hex != _selected_hex:
				_clear_unit_selection()
			_selected_hex = unit_hex
			_refresh_selected_hex_panel(_selected_hex)
			if _drag_candidate_was_selected:
				clicked_unit_id = _next_friendly_unit_after(unit_hex, _drag_candidate_unit_id)
		_set_single_unit_selection(clicked_unit_id)
		_update_info_label("Selected %s" % _unit_display_name_by_id(_selected_unit_id))
	_drag_candidate_unit_id = ""
	_drag_candidate_was_selected = false
	_dragging_unit_id = ""
	_update_order_action_panel()
	_refresh_selected_hex_panel(_selected_hex)
	queue_redraw()

func _refresh_selected_hex_panel(hex: Vector2i) -> void:
	_refresh_selected_unit_inspector()
	_clear_selected_hex_unit_cards()
	if hex == Vector2i(-9999, -9999):
		selected_hex_title_label.text = "Selected Hex: -, -"
		selected_hex_ownership_label.text = "Owner: None"
		selected_hex_terrain_label.text = "Terrain: %s" % TerrainCatalog.display_name(TerrainCatalog.default_terrain_id())
		selected_hex_count_label.text = "Unit Count: 0"
		_add_selected_hex_empty_state("No hex selected.")
		return

	var coordinate_key := "%d,%d" % [hex.x, hex.y]
	selected_hex_title_label.text = "Selected Hex: %s" % coordinate_key
	selected_hex_ownership_label.text = _selected_hex_ownership_text(coordinate_key)

	var terrain_id := String(GameState.terrain_map.get(coordinate_key, TerrainCatalog.default_terrain_id()))
	terrain_id = TerrainCatalog.normalize_terrain_id(terrain_id)
	selected_hex_terrain_label.text = "Terrain: %s" % TerrainCatalog.display_name(terrain_id)

	var friendly_entries := _units_at_hex(hex, _active_player, false)
	var enemy_entries := _enemy_units_at_hex(hex)
	var known_enemy_units := _known_enemy_units_for_hex(hex)
	var enemy_presence_reported := _enemy_presence_reported_for_hex(hex, known_enemy_units)
	selected_hex_count_label.text = _selected_hex_count_text(friendly_entries.size(), enemy_entries.size(), known_enemy_units, enemy_presence_reported)

	for entry in friendly_entries:
		var unit := entry.get("unit", {}) as Dictionary
		var unit_id := String(entry.get("id", ""))
		_add_unit_card(_friendly_unit_card_text(unit, unit_id, int(entry.get("owner", -1))), "friendly", unit_id, true, _is_unit_selected(unit_id), unit_id == _selected_unit_id)

	if GameState.debug_mode_enabled:
		for entry in enemy_entries:
			var unit := entry.get("unit", {}) as Dictionary
			var unit_id := String(entry.get("id", ""))
			_add_unit_card(_unit_summary_line(unit, unit_id, int(entry.get("owner", -1))), "enemy", unit_id)
	else:
		for contact_line in _recon_enemy_summary_lines(hex, known_enemy_units):
			_add_unit_card(contact_line, "contact")

	if selected_hex_unit_cards.get_child_count() == 0:
		_add_selected_hex_empty_state("No units detected.")

func _refresh_selected_unit_inspector() -> void:
	_clear_control_children(subordinate_list)
	var unit_id := _selected_unit_id
	if unit_id.is_empty() or not _units.has(unit_id):
		selected_unit_title_label.text = "Active Unit"
		selected_unit_summary_label.text = "Select a friendly unit card to inspect its formation."
		selected_unit_order_label.visible = false
		selected_unit_formation_label.visible = false
		subordinates_toggle_button.visible = false
		subordinate_scroll.visible = false
		return

	var unit := _units[unit_id] as Dictionary
	if int(unit.get("owner", -1)) != _active_player:
		selected_unit_title_label.text = "Active Unit"
		selected_unit_summary_label.text = "No friendly unit selected."
		selected_unit_order_label.visible = false
		selected_unit_formation_label.visible = false
		subordinates_toggle_button.visible = false
		subordinate_scroll.visible = false
		return

	var owner := int(unit.get("owner", _active_player))
	var subordinates := _selected_unit_subordinates(unit, unit_id, owner)
	var selected_tree_node := FormationHierarchy.find_node(_division_tree_for_owner(owner), unit_id)
	var totals := {
		"formations_alive": 0,
		"formations_total": 0,
		"vehicles_alive": 0,
		"vehicles_total": 0
	}
	_count_vehicle_statuses(unit if unit.has("vehicles") else selected_tree_node, totals)
	for subordinate in subordinates:
		_count_subordinate_statuses(subordinate, totals)

	selected_unit_title_label.text = _unit_display_name(unit, unit_id)
	var summary_lines: Array[String] = [
		"%s — %s" % [_friendly_unit_type_label(String(unit.get("size", ""))), _unit_role_display_name(unit)],
		"Status: %s | %s" % [_friendly_state_summary(unit), _unit_health_summary(unit)],
		"Strength: %d/%d subordinate formations; %d/%d vehicles" % [
			int(totals["formations_alive"]),
			int(totals["formations_total"]),
			int(totals["vehicles_alive"]),
			int(totals["vehicles_total"])
		]
	]
	var selected_count := _selected_order_unit_ids().size()
	if selected_count > 1:
		summary_lines.append("%d units selected; showing the active unit." % selected_count)
	selected_unit_summary_label.text = "\n".join(summary_lines)

	var order_summary := _unit_order_summary(unit_id)
	selected_unit_order_label.text = order_summary if not order_summary.is_empty() else "Order: None"
	selected_unit_order_label.visible = true
	var formation_path := _formation_path_text(owner, unit_id)
	selected_unit_formation_label.text = "Formation: %s" % (formation_path if not formation_path.is_empty() else "Independent")
	selected_unit_formation_label.visible = true

	subordinates_toggle_button.visible = true
	subordinates_toggle_button.disabled = false
	subordinates_toggle_button.text = "Subordinates (%d/%d operational) %s" % [
		int(totals["formations_alive"]),
		int(totals["formations_total"]),
		("▾" if _subordinates_expanded else "▸")
	]
	subordinate_scroll.visible = _subordinates_expanded
	if subordinates.is_empty():
		_add_subordinate_empty_state("No subordinate formations.")
		return
	for subordinate in subordinates:
		_add_subordinate_row(subordinate)

func _selected_unit_subordinates(unit: Dictionary, unit_id: String, owner: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var combined_components_variant: Variant = unit.get("combined_components", [])
	if typeof(combined_components_variant) == TYPE_ARRAY and not (combined_components_variant as Array).is_empty():
		for component_variant in combined_components_variant as Array:
			if component_variant is Dictionary:
				result.append((component_variant as Dictionary).duplicate(true))
		return result

	var tree_node := FormationHierarchy.find_node(_division_tree_for_owner(owner), unit_id)
	var children_variant: Variant = tree_node.get("children", [])
	if typeof(children_variant) != TYPE_ARRAY:
		return result
	for child_variant in children_variant as Array:
		if child_variant is Dictionary:
			result.append(_live_inspector_node(child_variant as Dictionary))
	return result

func _division_tree_for_owner(owner: int) -> Dictionary:
	if owner < 0 or owner >= GameState.players.size():
		return {}
	return (GameState.players[owner] as Dictionary).get("division_tree", {}) as Dictionary

func _live_inspector_node(tree_node: Dictionary) -> Dictionary:
	var result := tree_node.duplicate(true)
	var unit_id := String(tree_node.get("id", ""))
	if unit_id.is_empty() or not _units.has(unit_id):
		return result
	var runtime_unit := _units[unit_id] as Dictionary
	for key_variant in runtime_unit.keys():
		var key := String(key_variant)
		if key == "children":
			continue
		result[key_variant] = runtime_unit[key_variant]
	return result

func _count_subordinate_statuses(unit: Dictionary, totals: Dictionary) -> void:
	totals["formations_total"] = int(totals.get("formations_total", 0)) + 1
	if GameState.is_unit_alive(unit):
		totals["formations_alive"] = int(totals.get("formations_alive", 0)) + 1
	_count_vehicle_statuses(unit, totals)
	var children_variant: Variant = unit.get("children", [])
	if typeof(children_variant) != TYPE_ARRAY:
		return
	for child_variant in children_variant as Array:
		if child_variant is Dictionary:
			_count_subordinate_statuses(_live_inspector_node(child_variant as Dictionary), totals)

func _count_vehicle_statuses(unit: Dictionary, totals: Dictionary) -> void:
	if unit.is_empty():
		return
	var vehicles_variant: Variant = unit.get("vehicles", [])
	if typeof(vehicles_variant) != TYPE_ARRAY:
		return
	for vehicle_variant in vehicles_variant as Array:
		if not (vehicle_variant is Dictionary):
			continue
		totals["vehicles_total"] = int(totals.get("vehicles_total", 0)) + 1
		if GameState.is_unit_alive(vehicle_variant as Dictionary):
			totals["vehicles_alive"] = int(totals.get("vehicles_alive", 0)) + 1

func _add_subordinate_row(unit: Dictionary) -> void:
	var unit_id := String(unit.get("id", ""))
	var label := Label.new()
	label.text = "%s — %s — %s\n%s | Status: %s" % [
		_unit_display_name(unit, unit_id),
		_friendly_unit_type_label(String(unit.get("size", ""))),
		_unit_role_display_name(unit),
		_unit_health_summary(unit),
		_friendly_state_summary(unit)
	]
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.set_meta("unit_id", unit_id)
	subordinate_list.add_child(label)

func _add_subordinate_empty_state(message: String) -> void:
	var label := Label.new()
	label.text = message
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	subordinate_list.add_child(label)

func _on_subordinates_toggle_pressed() -> void:
	_subordinates_expanded = not _subordinates_expanded
	_refresh_selected_unit_inspector()

func _clear_control_children(container: Control) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()

func _clear_selected_hex_unit_cards() -> void:
	for child in selected_hex_unit_cards.get_children():
		selected_hex_unit_cards.remove_child(child)
		child.queue_free()

func _add_selected_hex_empty_state(message: String) -> void:
	var label := Label.new()
	label.text = message
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selected_hex_unit_cards.add_child(label)

func _add_unit_card(text: String, kind: String, unit_id: String = "", actionable: bool = false, is_selected: bool = false, is_primary: bool = false) -> void:
	var card := Button.new()
	card.text = text
	card.alignment = HORIZONTAL_ALIGNMENT_LEFT
	card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.custom_minimum_size = Vector2(0.0, 72.0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.disabled = not actionable
	card.focus_mode = Control.FOCUS_ALL if actionable else Control.FOCUS_NONE
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if actionable else Control.CURSOR_ARROW
	card.set_meta("card_kind", kind)
	card.set_meta("unit_id", unit_id)
	card.set_meta("actionable", actionable)
	card.set_meta("is_selected", is_selected)
	card.set_meta("is_primary", is_primary)
	_apply_unit_card_theme(card, kind, is_selected, is_primary)
	if actionable:
		card.pressed.connect(_on_unit_card_button_pressed.bind(unit_id))
	selected_hex_unit_cards.add_child(card)

func _apply_unit_card_theme(card: Button, kind: String, is_selected: bool, is_primary: bool) -> void:
	var background := Color(0.10, 0.13, 0.17, 0.98)
	var border := Color(0.34, 0.40, 0.48, 0.9)
	var border_width := 1
	if kind == "enemy":
		background = Color(0.18, 0.09, 0.09, 0.98)
		border = Color(0.60, 0.25, 0.25, 0.9)
	elif kind == "contact":
		background = Color(0.17, 0.14, 0.07, 0.98)
		border = Color(0.62, 0.50, 0.20, 0.9)
	elif is_selected:
		background = Color(0.19, 0.22, 0.11, 0.98)
		border = Color(0.78, 0.82, 0.34, 1.0)
		border_width = 2
	if is_primary:
		background = Color(0.24, 0.20, 0.07, 0.98)
		border = Color(1.0, 0.86, 0.28, 1.0)
		border_width = 2

	card.add_theme_stylebox_override("normal", _unit_card_style(background, border, border_width))
	card.add_theme_stylebox_override("disabled", _unit_card_style(background, border, border_width))
	card.add_theme_stylebox_override("hover", _unit_card_style(background.lightened(0.08), border, border_width))
	card.add_theme_stylebox_override("pressed", _unit_card_style(background.darkened(0.05), border, border_width))
	card.add_theme_color_override("font_color", Color(0.94, 0.96, 1.0))
	card.add_theme_color_override("font_hover_color", Color.WHITE)
	card.add_theme_color_override("font_pressed_color", Color.WHITE)
	card.add_theme_color_override("font_disabled_color", Color(0.86, 0.86, 0.84))

func _unit_card_style(background: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(4)
	style.content_margin_left = 8.0
	style.content_margin_top = 6.0
	style.content_margin_right = 8.0
	style.content_margin_bottom = 6.0
	return style

func _friendly_unit_card_text(unit: Dictionary, unit_id: String, owner: int) -> String:
	var summary := _unit_summary_line(unit, unit_id, owner)
	if unit_id == _selected_unit_id:
		summary = "ACTIVE UNIT\n%s" % summary
	elif _is_unit_selected(unit_id):
		summary = "SELECTED UNIT\n%s" % summary
	var order_summary := _unit_order_summary(unit_id)
	if not order_summary.is_empty():
		summary += "\n%s" % order_summary
	if unit_id == _selected_unit_id:
		var formation_path := _formation_path_text(owner, unit_id)
		if not formation_path.is_empty():
			summary += "\nFormation: %s" % formation_path
	return summary

func _formation_path_text(owner: int, unit_id: String) -> String:
	if owner < 0 or owner >= GameState.players.size():
		return ""
	var root := (GameState.players[owner] as Dictionary).get("division_tree", {}) as Dictionary
	return FormationHierarchy.verbal_path(root, unit_id)

func _unit_order_summary(unit_id: String) -> String:
	if not _orders.has(unit_id) or not (_orders[unit_id] is Dictionary):
		return ""
	var order := _orders[unit_id] as Dictionary
	match int(order.get("type", -1)):
		OrderSystem.OrderType.MOVE:
			return "Order: Move"
		OrderSystem.OrderType.ATTACK:
			return "Order: Attack"
		OrderSystem.OrderType.DIG_IN:
			return "Order: Dig In"
		_:
			return "Order: Unknown"

func _on_unit_card_button_pressed(unit_id: String) -> void:
	_on_unit_card_pressed(unit_id, Input.is_key_pressed(KEY_SHIFT))

func _on_unit_card_pressed(unit_id: String, shift_pressed: bool = false) -> void:
	if unit_id.is_empty() or not _units.has(unit_id):
		return
	var unit := _units[unit_id] as Dictionary
	if int(unit.get("owner", -1)) != _active_player or not GameState.is_unit_alive(unit):
		return
	if unit.get("hex", Vector2i.ZERO) as Vector2i != _selected_hex:
		return
	if shift_pressed:
		_toggle_unit_selection(unit_id)
	else:
		_set_single_unit_selection(unit_id)
	_preview_path.clear()
	_preview_target_hex = Vector2i(-9999, -9999)
	_pending_preview_target_hex = Vector2i(-9999, -9999)
	_update_order_action_panel()
	_update_info_label(_unit_selection_status_text(unit_id))
	_refresh_selected_hex_panel(_selected_hex)
	queue_redraw()

func _clear_unit_selection() -> void:
	_selected_unit_ids.clear()
	_selected_unit_id = ""

func _set_single_unit_selection(unit_id: String) -> void:
	_selected_unit_ids.clear()
	_selected_unit_id = unit_id
	if not unit_id.is_empty():
		_selected_unit_ids.append(unit_id)

func _toggle_unit_selection(unit_id: String) -> void:
	var selected_index := _selected_unit_ids.find(unit_id)
	if selected_index >= 0:
		_selected_unit_ids.remove_at(selected_index)
		if _selected_unit_id == unit_id:
			_selected_unit_id = _selected_unit_ids[_selected_unit_ids.size() - 1] if not _selected_unit_ids.is_empty() else ""
		return
	_selected_unit_ids.append(unit_id)
	_selected_unit_id = unit_id

func _is_unit_selected(unit_id: String) -> bool:
	if _selected_unit_ids.has(unit_id):
		return true
	return _selected_unit_ids.is_empty() and unit_id == _selected_unit_id

func _selected_order_unit_ids() -> Array[String]:
	var selected: Array[String] = []
	for unit_id in _selected_unit_ids:
		if not unit_id.is_empty() and not selected.has(unit_id):
			selected.append(unit_id)
	if selected.is_empty() and not _selected_unit_id.is_empty():
		selected.append(_selected_unit_id)
	return selected

func _unit_selection_status_text(last_clicked_unit_id: String) -> String:
	var selected := _selected_order_unit_ids()
	if selected.is_empty():
		return "No units selected."
	if selected.size() == 1:
		return "Selected %s" % _unit_display_name_by_id(selected[0])
	return "Selected %d units; active unit is %s." % [selected.size(), _unit_display_name_by_id(_selected_unit_id if not _selected_unit_id.is_empty() else last_clicked_unit_id)]

func _unit_summary_line(unit: Dictionary, fallback_unit_id: String, owner: int) -> String:
	var unit_name := _unit_display_name(unit, fallback_unit_id)
	var relation := "Friendly" if owner == _active_player else "Enemy"
	var unit_role := _unit_role_display_name(unit)
	var unit_size := _friendly_unit_type_label(String(unit.get("size", "")))
	return "%s (%s) — %s — %s | %s | Status: %s" % [
		unit_name,
		relation,
		unit_size,
		unit_role,
		_unit_health_summary(unit),
		_friendly_state_summary(unit)
	]

func _unit_role_display_name(unit: Dictionary) -> String:
	var broad_type: Variant = unit.get("type", "")
	var role := UnitRole.normalize(unit.get("role", ""), broad_type)
	return UnitRole.display_name(role, broad_type)

func _friendly_unit_type_label(unit_type: String) -> String:
	var normalized := unit_type.strip_edges().to_lower().replace("_", " ")
	if normalized.is_empty():
		return "Unknown"
	return normalized.capitalize()

func _friendly_status_text(status: String) -> String:
	var normalized := status.strip_edges().to_lower()
	if normalized.is_empty():
		return "Unknown"
	return normalized.capitalize()

func _friendly_state_summary(unit: Dictionary) -> String:
	var states: Array[String] = []
	var status := String(unit.get("status", "")).strip_edges()
	states.append(_friendly_status_text(status))
	if bool(unit.get("dug_in", false)):
		states.append("Dug In")
	if unit.has("moved"):
		states.append("Moved: %s" % ("Yes" if bool(unit.get("moved", false)) else "No"))
	if unit.has("acted"):
		states.append("Acted: %s" % ("Yes" if bool(unit.get("acted", false)) else "No"))
	if unit.has("concealment"):
		states.append("Concealment: %d" % int(unit.get("concealment", 0)))
	if states.is_empty():
		return "No extra state"
	return ", ".join(states)

func _unit_hp_value(unit: Dictionary) -> int:
	var hp_keys := ["hp", "health", "strength", "current_hp", "current_health"]
	for key in hp_keys:
		if unit.has(key):
			return maxi(0, int(unit.get(key, 0)))
	return int(unit.get("steps", 0))

func _unit_max_hp_value(unit: Dictionary) -> int:
	var max_hp_keys := ["max_hp", "max_health", "hp_max", "health_max", "max_strength"]
	for key in max_hp_keys:
		if unit.has(key):
			return maxi(0, int(unit.get(key, 0)))
	var hp_value := _unit_hp_value(unit)
	return maxi(hp_value, int(unit.get("steps", hp_value)))

func _unit_health_summary(unit: Dictionary) -> String:
	return UnitHealthFormatter.summary(unit)

func _unit_display_name_by_id(unit_id: String) -> String:
	if unit_id.is_empty():
		return "Unknown Unit"
	if _units.has(unit_id):
		return _unit_display_name(_units[unit_id] as Dictionary, unit_id)
	for player_variant in GameState.players:
		if not (player_variant is Dictionary):
			continue
		var root := (player_variant as Dictionary).get("division_tree", {}) as Dictionary
		var tree_unit := FormationHierarchy.find_node(root, unit_id)
		if not tree_unit.is_empty():
			return _unit_display_name(tree_unit, unit_id)
	if _is_presentable_unit_name(unit_id):
		return unit_id
	return "Unknown Unit"

func _unit_display_name(unit: Dictionary, fallback_unit_id: String) -> String:
	if _unit_has_notation_context(unit):
		var formatted := UnitNotationFormatter.format_unit(_unit_notation_payload(unit, fallback_unit_id)).strip_edges()
		if _is_presentable_unit_name(formatted):
			return formatted
	for key in ["display_name", "short_name"]:
		var candidate := String(unit.get(key, "")).strip_edges()
		if _is_presentable_unit_name(candidate):
			return candidate
	if _is_presentable_unit_name(fallback_unit_id):
		return fallback_unit_id
	var unit_size := _friendly_unit_type_label(String(unit.get("size", "")))
	var unit_role := _unit_role_display_name(unit)
	if unit_size == "Unknown" and unit_role == "Unknown":
		return "Unnamed Unit"
	if unit_size == "Unknown":
		return unit_role
	if unit_role == "Unknown":
		return unit_size
	return "%s %s" % [unit_size, unit_role]

func _unit_has_notation_context(unit: Dictionary) -> bool:
	var designation := _unit_designation_payload(unit)
	if maxi(int(designation.get("battalion_number", 0)), 0) > 0:
		return true
	if maxi(int(designation.get("regiment_number", 0)), 0) > 0:
		return true
	if maxi(int(designation.get("platoon_number", 0)), 0) > 0:
		return true
	if not String(designation.get("company_letter", "")).strip_edges().is_empty():
		return true
	return false

func _unit_notation_payload(unit: Dictionary, fallback_unit_id: String) -> Dictionary:
	var payload := {
		"id": String(unit.get("id", fallback_unit_id)),
		"type": unit.get("type", ""),
		"size": unit.get("size", ""),
		"display_name": String(unit.get("display_name", "")),
		"short_name": String(unit.get("short_name", unit.get("display_name", ""))),
		"is_attached": bool(unit.get("is_attached", false))
	}
	var designation := _unit_designation_payload(unit)
	if not designation.is_empty():
		payload["designation"] = designation
	return payload

func _unit_designation_payload(unit: Dictionary) -> Dictionary:
	var designation_variant: Variant = unit.get("designation", {})
	if typeof(designation_variant) == TYPE_DICTIONARY:
		return (designation_variant as Dictionary).duplicate(true)
	return {}

func _is_presentable_unit_name(candidate: String) -> bool:
	var text := candidate.strip_edges()
	return not text.is_empty() and not text.begins_with("unit_")

func _unit_has_any_key(unit: Dictionary, keys: Array) -> bool:
	for key in keys:
		if unit.has(key):
			return true
	return false

func _selected_hex_ownership_text(coordinate_key: String) -> String:
	var owner := int(GameState.territory_map.get(coordinate_key, GameState.TerritoryOwnership.NEUTRAL))
	if owner == GameState.TerritoryOwnership.NEUTRAL:
		return "Owner: Neutral"
	var owner_name := _territory_owner_name(owner)
	var perspective := "Friendly Territory" if owner == _territory_owner_for_player(_active_player) else "Enemy Territory"
	return "Owner: %s (%s)" % [owner_name, perspective]

func _territory_owner_name(owner: int) -> String:
	match owner:
		GameState.TerritoryOwnership.PLAYER_1:
			return "Player 1"
		GameState.TerritoryOwnership.PLAYER_2:
			return "Player 2"
		_:
			return "Neutral"

func _territory_owner_for_player(player_index: int) -> int:
	return GameState.TerritoryOwnership.PLAYER_1 if player_index == 0 else GameState.TerritoryOwnership.PLAYER_2

func _selected_hex_count_text(friendly_count: int, exact_enemy_count: int, known_enemy_units: Array, enemy_presence_reported: bool) -> String:
	if GameState.debug_mode_enabled:
		return "Unit Count: %d (%d friendly, %d enemy)" % [friendly_count + exact_enemy_count, friendly_count, exact_enemy_count]
	var known_enemy_count := _known_enemy_unit_count(known_enemy_units)
	if known_enemy_count > 0:
		return "Unit Count: %d friendly, %d enemy contact(s) reported" % [friendly_count, known_enemy_count]
	if enemy_presence_reported:
		return "Unit Count: %d friendly, enemy presence reported" % friendly_count
	return "Unit Count: %d" % friendly_count

func _enemy_units_at_hex(hex: Vector2i) -> Array[Dictionary]:
	var enemy_entries: Array[Dictionary] = []
	for unit_id in _units.keys():
		var unit := _units[unit_id] as Dictionary
		if not GameState.is_unit_alive(unit):
			continue
		var unit_owner := int(unit.get("owner", -1))
		if unit_owner == _active_player:
			continue
		if unit.get("hex", Vector2i.ZERO) != hex:
			continue
		enemy_entries.append({
			"id": String(unit_id),
			"owner": unit_owner,
			"unit": unit
		})
	enemy_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("id", "")) < String(b.get("id", ""))
	)
	return enemy_entries

func _known_enemy_units_for_hex(hex: Vector2i) -> Array:
	var hex_intel := _hex_scout_intel(hex)
	if hex_intel.is_empty():
		return []
	var known_variant: Variant = hex_intel.get("knownEnemyUnits", [])
	if known_variant is Array:
		return (known_variant as Array).duplicate(true)
	return []

func _hex_scout_intel(hex: Vector2i) -> Dictionary:
	var hex_key := "%d,%d" % [hex.x, hex.y]
	var scout_intel := _active_player_scout_intel()
	if scout_intel.has(hex_key) and scout_intel[hex_key] is Dictionary:
		return (scout_intel[hex_key] as Dictionary).duplicate(true)
	return {}

func _enemy_presence_reported_for_hex(hex: Vector2i, known_enemy_units: Array) -> bool:
	if not known_enemy_units.is_empty():
		for known_variant in known_enemy_units:
			if known_variant is Dictionary and bool((known_variant as Dictionary).get("presenceKnown", true)):
				return true
	var hex_intel := _hex_scout_intel(hex)
	return int(hex_intel.get("scoutLevel", 0)) > 0 and bool(hex_intel.get("presenceKnown", false))

func _known_enemy_unit_count(known_enemy_units: Array) -> int:
	var count := 0
	for known_variant in known_enemy_units:
		if not (known_variant is Dictionary):
			continue
		var known := known_variant as Dictionary
		var unit_id := String(known.get("unitId", "")).strip_edges()
		if not unit_id.is_empty():
			count += 1
	return count

func _recon_enemy_summary_lines(hex: Vector2i, known_enemy_units: Array) -> Array[String]:
	var lines: Array[String] = []
	var hex_intel := _hex_scout_intel(hex)
	if hex_intel.is_empty():
		if _is_enemy_territory_hex(hex):
			lines.append("Enemy territory: no current recon contact.")
		return lines
	var scout_level := int(hex_intel.get("scoutLevel", 0))
	if known_enemy_units.is_empty():
		if _enemy_presence_reported_for_hex(hex, known_enemy_units):
			lines.append("Enemy presence reported | Scout Level: %d" % scout_level)
		elif _is_enemy_territory_hex(hex):
			lines.append("Enemy territory: no enemy units identified.")
		return lines

	var contact_index := 1
	for known_variant in known_enemy_units:
		if not (known_variant is Dictionary):
			continue
		var known := known_variant as Dictionary
		var unit_id := String(known.get("unitId", "")).strip_edges()
		var contact_label := unit_id if not unit_id.is_empty() else "Enemy contact %d" % contact_index
		var reported_type := _recon_reported_value(known.get("reportedType", ""))
		var reported_size := _recon_reported_value(known.get("reportedSize", ""))
		lines.append("%s | Type: %s | Size: %s | Scout Level: %d" % [
			contact_label,
			reported_type,
			reported_size,
			scout_level
		])
		contact_index += 1
	return lines

func _recon_reported_value(raw_value: Variant) -> String:
	var value := String(raw_value).strip_edges()
	if value.is_empty():
		return "Unknown"
	return _friendly_unit_type_label(value)

func _is_enemy_territory_hex(hex: Vector2i) -> bool:
	var key := "%d,%d" % [hex.x, hex.y]
	var owner := int(GameState.territory_map.get(key, GameState.TerritoryOwnership.NEUTRAL))
	if owner == GameState.TerritoryOwnership.NEUTRAL:
		return false
	return owner != _territory_owner_for_player(_active_player)

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
			if _is_unit_selected(_dragging_unit_id):
				_selected_unit_id = _dragging_unit_id
			else:
				_set_single_unit_selection(_dragging_unit_id)
			_preview_path.clear()
			_preview_target_hex = Vector2i(-9999, -9999)
	if not _dragging_unit_id.is_empty():
		_handle_path_preview_motion(motion.position)
		queue_redraw()
		return
	_handle_path_preview_motion(motion.position)

func _draw() -> void:
	var visible_rect := Rect2(Vector2.ZERO, size).grow(HEX_RADIUS * _camera_zoom * 2.0)
	_active_order_arrow_count = 0
	_active_unit_marker_count = 0

	for row in range(GRID_ROWS):
		for column in range(GRID_COLUMNS):
			var axial := Vector2i(column, row)
			var tile_visible := _is_hex_visible_to_active_player(axial)
			var world_center := _hex_center(column, row)
			var center := _world_to_screen(world_center)
			if not visible_rect.has_point(center):
				continue
			var world_points: PackedVector2Array = _hex_polygon_cache.get(axial, _hex_points(world_center)) as PackedVector2Array
			var points := PackedVector2Array()
			for point in world_points:
				points.append(_world_to_screen(point))
			var territory_owner := int(GameState.territory_map.get("%d,%d" % [column, row], GameState.TerritoryOwnership.NEUTRAL))
			var fill_color := territory_fill_color(territory_owner, tile_visible)
			var edge_color := Color(0.35, 0.4, 0.45, 1.0) if tile_visible else Color(0.14, 0.15, 0.16, 0.95)
			draw_colored_polygon(points, fill_color)
			draw_polyline(points + PackedVector2Array([points[0]]), edge_color, maxf(1.0, 1.5 * _camera_zoom))

	_draw_key_objectives(visible_rect)

	for battle_hex in _battle_highlight_hexes:
		var world_points: PackedVector2Array = _hex_polygon_cache.get(battle_hex, _hex_points(_hex_center(battle_hex.x, battle_hex.y))) as PackedVector2Array
		var points := PackedVector2Array()
		for point in world_points:
			points.append(_world_to_screen(point))
		draw_colored_polygon(points, Color(0.88, 0.16, 0.08, 0.28))
		draw_polyline(points + PackedVector2Array([points[0]]), Color(1.0, 0.78, 0.18, 1.0), maxf(3.0, 4.0 * _camera_zoom))

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
			var stack := _units_at_hex(hex, -1, true)
			if stack.is_empty():
				continue
			var base_center := _world_to_screen(_hex_center(hex.x, hex.y))
			if not visible_rect.has_point(base_center):
				continue
			var entry := _front_entry_for_stack(stack)
			var unit := entry.get("unit", {}) as Dictionary
			var unit_id := String(entry.get("id", ""))
			var any_selected := false
			for stack_entry_variant in stack:
				var stack_entry := stack_entry_variant as Dictionary
				if _is_unit_selected(String(stack_entry.get("id", ""))):
					any_selected = true
					break
			_collect_unit_marker(base_center, unit, int(entry.get("owner", 0)), unit_id, stack.size(), any_selected, unit_id == _selected_unit_id)

	for i in range(_active_unit_marker_count):
		_draw_unit_marker(_unit_marker_pool[i])

	if not _dragging_unit_id.is_empty():
		var dragged_unit := _units.get(_dragging_unit_id, {}) as Dictionary
		NatoUnitSymbolRenderer.draw_stack(
			self,
			_drag_mouse_pos,
			dragged_unit,
			int(dragged_unit.get("owner", _active_player)),
			1,
			get_theme_default_font(),
			_camera_zoom,
			true,
			true,
			0.82
		)

func _draw_key_objectives(visible_rect: Rect2) -> void:
	for key_variant in GameState.key_objectives.keys():
		var parts := String(key_variant).split(",")
		if parts.size() != 2:
			continue
		var hex := Vector2i(int(parts[0]), int(parts[1]))
		var center := _world_to_screen(_hex_center(hex.x, hex.y))
		if not visible_rect.has_point(center):
			continue
		var entry := GameState.key_objectives[key_variant] as Dictionary
		var primary := String(entry.get("priority", "secondary")) == "primary"
		var color := Color(1.0, 0.72, 0.12, 0.9) if primary else Color(0.68, 0.82, 1.0, 0.78)
		var radius := HEX_RADIUS * _camera_zoom * (0.34 if primary else 0.25)
		draw_circle(center, radius, Color(color, 0.14))
		draw_arc(center, radius, 0.0, TAU, 24, color, maxf(2.0, 3.0 * _camera_zoom if primary else 2.0 * _camera_zoom), true)

func _collect_order_arrow(order: Dictionary, is_preview: bool) -> void:
	var path := _drawable_order_path(order)
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


func _drawable_order_path(order: Dictionary) -> Array[Vector2i]:
	var raw_path := order.get("path", []) as Array
	var path: Array[Vector2i] = []
	for point in raw_path:
		if point is Vector2i:
			path.append(point as Vector2i)
		elif point is Dictionary:
			path.append(Vector2i(int(point.get("x", 0)), int(point.get("y", 0))))
	if path.size() >= 2:
		return path
	if int(order.get("type", 0)) != OrderSystem.OrderType.ATTACK:
		return path
	var target_id := String(order.get("target_unit_id", ""))
	if target_id.is_empty() or not _units.has(target_id):
		return path
	var target_unit := _units[target_id] as Dictionary
	if not GameState.is_unit_alive(target_unit):
		return path
	var target_hex := target_unit.get("hex", Vector2i.ZERO) as Vector2i
	if path.is_empty():
		var unit_id := String(order.get("unit_id", ""))
		if unit_id.is_empty() or not _units.has(unit_id):
			return path
		var source_unit := _units[unit_id] as Dictionary
		path.append(source_unit.get("hex", Vector2i.ZERO) as Vector2i)
	if path[0] == target_hex:
		return path
	path.append(target_hex)
	return path

func _draw_order_arrow(entry: Dictionary) -> void:
	var path := entry.get("path", []) as Array
	var order_type := int(entry.get("order_type", 0))
	var is_preview := bool(entry.get("is_preview", false))
	var color := Color(0.45, 0.95, 0.45, 0.9) if order_type == OrderSystem.OrderType.MOVE else Color(0.95, 0.35, 0.35, 0.9)
	var width := 3.0 * _camera_zoom
	if is_preview:
		color = Color(0.95, 0.95, 0.4, 0.85)
		width = 2.0 * _camera_zoom
	for i in range(path.size() - 1):
		var from_hex: Vector2i = path[i]
		var to_hex: Vector2i = path[i + 1]
		draw_line(_world_to_screen(_hex_center(from_hex.x, from_hex.y)), _world_to_screen(_hex_center(to_hex.x, to_hex.y)), color, width)
	if order_type == OrderSystem.OrderType.ATTACK and not is_preview:
		var end_hex: Vector2i = path[path.size() - 1]
		var center := _world_to_screen(_hex_center(end_hex.x, end_hex.y))
		var cross_offset := Vector2(8, 8) * _camera_zoom
		draw_line(center - cross_offset, center + cross_offset, color, 2.0 * _camera_zoom)
		draw_line(center + Vector2(cross_offset.x, -cross_offset.y), center + Vector2(-cross_offset.x, cross_offset.y), color, 2.0 * _camera_zoom)

func _collect_unit_marker(center: Vector2, unit: Dictionary, owner: int, unit_id: String, stack_size: int, is_selected: bool, is_primary: bool = false) -> void:
	var idx := _active_unit_marker_count
	if idx >= _unit_marker_pool.size():
		_unit_marker_pool.append({})
	_unit_marker_pool[idx] = {
		"center": center,
		"unit": unit,
		"owner": owner,
		"id": unit_id,
		"stack_size": stack_size,
		"is_selected": is_selected,
		"is_primary": is_primary
	}
	_active_unit_marker_count += 1

func _draw_unit_marker(marker: Dictionary) -> void:
	var center := marker.get("center", Vector2.ZERO) as Vector2
	var is_selected := bool(marker.get("is_selected", false))
	var is_primary := bool(marker.get("is_primary", false))
	NatoUnitSymbolRenderer.draw_stack(
		self,
		center,
		marker.get("unit", {}) as Dictionary,
		int(marker.get("owner", 0)),
		int(marker.get("stack_size", 1)),
		get_theme_default_font(),
		_camera_zoom,
		is_selected,
		is_primary
	)
	if bool(GameState.debug_mode_enabled):
		_draw_debug_unit_overlay(center, String(marker.get("id", "")))

func _draw_debug_unit_overlay(center: Vector2, unit_id: String) -> void:
	if unit_id.is_empty() or not _units.has(unit_id):
		return
	var unit := _units[unit_id] as Dictionary
	var status_text := _friendly_status_text(String(unit.get("status", "alive")))
	var sub_units_text := _live_sub_units_summary(unit)
	var status_badge_center := center + Vector2(0, -UNIT_MARKER_RADIUS - 12.0) * _camera_zoom
	draw_circle(status_badge_center, 10.0 * _camera_zoom, Color(0.08, 0.09, 0.11, 0.94))
	draw_string(get_theme_default_font(), status_badge_center + Vector2(-8, 4) * _camera_zoom, status_text.left(2), HORIZONTAL_ALIGNMENT_LEFT, -1, _scaled_font_size(10))
	if not sub_units_text.is_empty():
		var sub_units_badge_center := center + Vector2(0, UNIT_MARKER_RADIUS + 12.0) * _camera_zoom
		draw_circle(sub_units_badge_center, 14.0 * _camera_zoom, Color(0.08, 0.09, 0.11, 0.94))
		draw_string(get_theme_default_font(), sub_units_badge_center + Vector2(-12, 4) * _camera_zoom, sub_units_text, HORIZONTAL_ALIGNMENT_LEFT, -1, _scaled_font_size(10))

func _scaled_unit_marker_radius() -> float:
	return UNIT_MARKER_RADIUS * _camera_zoom

func _scaled_font_size(base_size: int) -> int:
	return maxi(1, roundi(float(base_size) * _camera_zoom))

func _live_sub_units_summary(unit: Dictionary) -> String:
	var live_keys := ["live_sub_units", "sub_units_alive", "alive_sub_units", "current_sub_units"]
	var max_keys := ["max_sub_units", "sub_units_max", "total_sub_units"]
	var live_value: Variant = _first_int_for_keys(unit, live_keys)
	var max_value: Variant = _first_int_for_keys(unit, max_keys)
	if live_value == null or max_value == null:
		return ""
	return "%d/%d" % [maxi(0, int(live_value)), maxi(0, int(max_value))]

func _first_int_for_keys(unit: Dictionary, keys: Array) -> Variant:
	for key in keys:
		if unit.has(key):
			return int(unit.get(key, 0))
	return null

func _pick_friendly_unit_at(screen_position: Vector2) -> String:
	var clicked_hex_dict := _find_hex(screen_position)
	if clicked_hex_dict.is_empty():
		return ""
	var clicked_hex := Vector2i(clicked_hex_dict["q"], clicked_hex_dict["r"])
	var friendly_stack := _units_at_hex(clicked_hex, _active_player)
	if friendly_stack.is_empty():
		return ""

	var base_center := _world_to_screen(_hex_center(clicked_hex.x, clicked_hex.y))
	if not NatoUnitSymbolRenderer.contains_point(base_center, screen_position, _camera_zoom):
		return ""
	for entry_variant in friendly_stack:
		var entry := entry_variant as Dictionary
		var unit_id := String(entry.get("id", ""))
		if _is_unit_selected(unit_id):
			return unit_id
	return String((friendly_stack[0] as Dictionary).get("id", ""))

func _issue_move_order(unit_id: String, target_hex: Vector2i) -> bool:
	if unit_id.is_empty() or not _units.has(unit_id):
		return false
	if not GameState.is_unit_alive(_units[unit_id] as Dictionary):
		_update_info_label("%s is dead and cannot receive orders." % _unit_display_name_by_id(unit_id))
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
	_upsert_order_and_autosave(OrderSystem.create_move_order(unit_id, path))
	_preview_path.clear()
	_preview_target_hex = Vector2i(-9999, -9999)
	_refresh_selected_hex_panel(_selected_hex)
	return true

func _issue_attack_order(unit_id: String, target_hex: Vector2i) -> bool:
	if unit_id.is_empty() or not _units.has(unit_id):
		return false
	if not GameState.is_unit_alive(_units[unit_id] as Dictionary):
		_update_info_label("%s is dead and cannot receive orders." % _unit_display_name_by_id(unit_id))
		return false
	var target_id := _unit_at_hex(target_hex, 1 - _active_player)
	if target_id.is_empty():
		_update_info_label("Attack orders require an enemy target hex.")
		return false
	var start_hex := (_units[unit_id] as Dictionary).get("hex", Vector2i.ZERO) as Vector2i
	if not Pathfinding.are_adjacent(start_hex, target_hex):
		_update_info_label("Attack orders require an adjacent enemy target hex.")
		return false
	var attack_path: Array[Vector2i] = [start_hex]
	_upsert_order_and_autosave(OrderSystem.create_attack_order(unit_id, attack_path, target_id))
	_preview_path.clear()
	_preview_target_hex = Vector2i(-9999, -9999)
	_refresh_selected_hex_panel(_selected_hex)
	return true

func _issue_dig_in_order(unit_id: String) -> bool:
	if unit_id.is_empty() or not _units.has(unit_id):
		_update_info_label("Select a friendly unit first.")
		return false
	var unit := _units[unit_id] as Dictionary
	if int(unit.get("owner", -1)) != _active_player:
		_update_info_label("Only friendly units can dig in.")
		return false
	if not GameState.is_unit_alive(unit):
		_update_info_label("%s is dead and cannot receive orders." % _unit_display_name_by_id(unit_id))
		return false
	_upsert_order_and_autosave(OrderSystem.create_dig_in_order(unit_id))
	_refresh_selected_hex_panel(_selected_hex)
	_update_info_label("Dig In order created for %s." % _unit_display_name_by_id(unit_id))
	queue_redraw()
	return true

func _issue_group_move_orders(unit_ids: Array[String], target_hex: Vector2i) -> Dictionary:
	var result := _new_group_order_result(unit_ids)
	var source_hex := _group_source_hex(unit_ids)
	var selected_lookup := {}
	for unit_id in unit_ids:
		selected_lookup[unit_id] = true
	var projected_occupants: Array[Dictionary] = []
	for other_id in _units.keys():
		var other := _units[other_id] as Dictionary
		if selected_lookup.has(String(other_id)) or not GameState.is_unit_alive(other):
			continue
		if int(other.get("owner", -1)) != _active_player:
			continue
		if (other.get("hex", Vector2i.ZERO) as Vector2i) == target_hex:
			projected_occupants.append(other)

	for unit_id in unit_ids:
		var eligibility := _group_order_eligibility(unit_id, source_hex)
		if not bool(eligibility.get("ok", false)):
			_reject_atomic_group_move(result, unit_ids, unit_id, String(eligibility.get("reason", "Unit is not eligible.")))
			_finalize_group_order_result("Move", result)
			return result
		var moving := _units[unit_id] as Dictionary
		projected_occupants.append(moving)

	var stack_validation := Rules.validate_stack(projected_occupants)
	if not bool(stack_validation.get("ok", false)):
		_reject_atomic_group_move(result, unit_ids, "", String(stack_validation.get("reason", "Illegal destination stack.")))
		_finalize_group_order_result("Move", result)
		return result

	for unit_id in unit_ids:
		var moving := _units[unit_id] as Dictionary
		var start_hex := moving.get("hex", Vector2i.ZERO) as Vector2i
		var path := Pathfinding.find_path(start_hex, target_hex, GameState.terrain_map, _blocked_cells(unit_id))
		if path.is_empty():
			_reject_atomic_group_move(result, unit_ids, unit_id, "No path found.")
			_finalize_group_order_result("Move", result)
			return result
		(result["orders"] as Array).append(OrderSystem.create_move_order(unit_id, path))
		(result["successful_unit_ids"] as Array).append(unit_id)

	_finalize_group_order_result("Move", result)
	return result

func _reject_atomic_group_move(result: Dictionary, unit_ids: Array[String], failing_unit_id: String, reason: String) -> void:
	(result["orders"] as Array).clear()
	(result["successful_unit_ids"] as Array).clear()
	(result["skipped"] as Array).clear()
	result["atomic_failure_reason"] = reason
	for unit_id in unit_ids:
		_add_group_order_skip(result, unit_id, reason if unit_id == failing_unit_id or failing_unit_id.is_empty() else "Group move cancelled because another selected unit was ineligible.")

func _issue_group_attack_orders(unit_ids: Array[String], target_hex: Vector2i) -> Dictionary:
	var result := _new_group_order_result(unit_ids)
	var source_hex := _group_source_hex(unit_ids)
	var target_id := _unit_at_hex(target_hex, 1 - _active_player)
	for unit_id in unit_ids:
		var eligibility := _group_order_eligibility(unit_id, source_hex)
		if not bool(eligibility.get("ok", false)):
			_add_group_order_skip(result, unit_id, String(eligibility.get("reason", "Unit is not eligible.")))
			continue
		if target_id.is_empty():
			_add_group_order_skip(result, unit_id, "Attack orders require an enemy target hex.")
			continue
		var start_hex := (_units[unit_id] as Dictionary).get("hex", Vector2i.ZERO) as Vector2i
		if not Pathfinding.are_adjacent(start_hex, target_hex):
			_add_group_order_skip(result, unit_id, "Attack orders require an adjacent enemy target hex.")
			continue
		var attack_path: Array[Vector2i] = [start_hex]
		(result["orders"] as Array).append(OrderSystem.create_attack_order(unit_id, attack_path, target_id))
		(result["successful_unit_ids"] as Array).append(unit_id)

	_finalize_group_order_result("Attack", result)
	return result

func _issue_group_dig_in_orders(unit_ids: Array[String]) -> Dictionary:
	var result := _new_group_order_result(unit_ids)
	var source_hex := _group_source_hex(unit_ids)
	for unit_id in unit_ids:
		var eligibility := _group_order_eligibility(unit_id, source_hex)
		if not bool(eligibility.get("ok", false)):
			_add_group_order_skip(result, unit_id, String(eligibility.get("reason", "Unit is not eligible.")))
			continue
		(result["orders"] as Array).append(OrderSystem.create_dig_in_order(unit_id))
		(result["successful_unit_ids"] as Array).append(unit_id)

	_finalize_group_order_result("Dig In", result)
	return result

func _new_group_order_result(unit_ids: Array[String]) -> Dictionary:
	return {
		"attempted": unit_ids.size(),
		"orders": [],
		"successful_unit_ids": [],
		"skipped": []
	}

func _group_source_hex(unit_ids: Array[String]) -> Vector2i:
	for unit_id in unit_ids:
		if _units.has(unit_id) and ((_units[unit_id] as Dictionary).get("hex", Vector2i.ZERO) as Vector2i) == _selected_hex:
			return _selected_hex
	for unit_id in unit_ids:
		if _units.has(unit_id):
			return (_units[unit_id] as Dictionary).get("hex", Vector2i.ZERO) as Vector2i
	return Vector2i(-9999, -9999)

func _group_order_eligibility(unit_id: String, source_hex: Vector2i) -> Dictionary:
	if unit_id.is_empty() or not _units.has(unit_id):
		return {"ok": false, "reason": "Unknown unit."}
	var unit := _units[unit_id] as Dictionary
	if int(unit.get("owner", -1)) != _active_player:
		return {"ok": false, "reason": "Only friendly units can receive orders."}
	if not GameState.is_unit_alive(unit):
		return {"ok": false, "reason": "Unit is dead and cannot receive orders."}
	if (unit.get("hex", Vector2i.ZERO) as Vector2i) != source_hex:
		return {"ok": false, "reason": "Unit is no longer on the selected hex."}
	return {"ok": true, "reason": ""}

func _add_group_order_skip(result: Dictionary, unit_id: String, reason: String) -> void:
	(result["skipped"] as Array).append({
		"unit_id": unit_id,
		"reason": reason
	})

func _finalize_group_order_result(action_name: String, result: Dictionary) -> void:
	var orders := result.get("orders", []) as Array
	for order_variant in orders:
		if order_variant is Dictionary:
			_orders = OrderSystem.upsert_order(_orders, order_variant as Dictionary)
	if not orders.is_empty():
		_autosave_current_game()
	_preview_path.clear()
	_preview_target_hex = Vector2i(-9999, -9999)
	_pending_preview_target_hex = Vector2i(-9999, -9999)
	_update_order_action_panel()
	_refresh_selected_hex_panel(_selected_hex)
	_update_info_label(_group_order_feedback(action_name, result))
	queue_redraw()

func _group_order_feedback(action_name: String, result: Dictionary) -> String:
	var atomic_failure_reason := String(result.get("atomic_failure_reason", ""))
	if not atomic_failure_reason.is_empty():
		return "%s group cancelled: %s No move orders were created." % [action_name, atomic_failure_reason]
	var attempted := int(result.get("attempted", 0))
	var successful_unit_ids := result.get("successful_unit_ids", []) as Array
	var skipped := result.get("skipped", []) as Array
	if attempted == 1:
		if successful_unit_ids.size() == 1:
			return "%s order created for %s." % [action_name, _unit_display_name_by_id(String(successful_unit_ids[0]))]
		if not skipped.is_empty():
			return String((skipped[0] as Dictionary).get("reason", "%s order was skipped." % action_name))
		return "%s order was skipped." % action_name

	var feedback := "%s orders: %d succeeded, %d skipped." % [action_name, successful_unit_ids.size(), skipped.size()]
	if skipped.is_empty():
		return feedback
	var skipped_reasons: Array[String] = []
	for skipped_variant in skipped:
		if not (skipped_variant is Dictionary):
			continue
		var skipped_entry := skipped_variant as Dictionary
		var unit_id := String(skipped_entry.get("unit_id", ""))
		skipped_reasons.append("%s: %s" % [_unit_display_name_by_id(unit_id), String(skipped_entry.get("reason", "Not eligible."))])
	return "%s Skipped: %s" % [feedback, "; ".join(skipped_reasons)]


func _upsert_order_and_autosave(order: Dictionary) -> void:
	_orders = OrderSystem.upsert_order(_orders, order)
	_autosave_current_game()

func _update_order_action_panel() -> void:
	var has_friendly_selected := false
	for unit_id in _selected_order_unit_ids():
		if not _units.has(unit_id):
			continue
		var unit := _units[unit_id] as Dictionary
		if int(unit.get("owner", -1)) == _active_player and GameState.is_unit_alive(unit):
			has_friendly_selected = true
			break
	order_action_panel.visible = has_friendly_selected
	if not has_friendly_selected:
		return
	var selected_ids := _selected_order_unit_ids()
	combine_button.disabled = selected_ids.size() < 2
	split_button.disabled = selected_ids.size() != 1

func _on_combine_pressed() -> void:
	if _battle_resolution_input_blocked:
		return
	var selected_ids := _selected_order_unit_ids()
	var result := FormationOperations.combine(_units, _orders, _active_division_tree(), selected_ids, _active_player)
	_apply_formation_operation_result(result)

func _on_split_pressed() -> void:
	if _battle_resolution_input_blocked:
		return
	var selected_ids := _selected_order_unit_ids()
	if selected_ids.size() != 1:
		_update_info_label("Select one company or battalion to split.")
		return
	var result := FormationOperations.split(_units, _orders, _active_division_tree(), selected_ids[0], _active_player)
	_apply_formation_operation_result(result)

func _active_division_tree() -> Dictionary:
	if _active_player < 0 or _active_player >= GameState.players.size():
		return {}
	return (GameState.players[_active_player] as Dictionary).get("division_tree", {}) as Dictionary

func _apply_formation_operation_result(result: Dictionary) -> void:
	if not bool(result.get("ok", false)):
		_update_info_label(String(result.get("reason", "Formation operation failed.")))
		return
	_units = (result.get("units", {}) as Dictionary).duplicate(true)
	_orders = (result.get("orders", {}) as Dictionary).duplicate(true)
	_selected_unit_ids.clear()
	for unit_id_variant in result.get("selected_ids", []) as Array:
		var unit_id := String(unit_id_variant)
		if not unit_id.is_empty():
			_selected_unit_ids.append(unit_id)
	_selected_unit_id = _selected_unit_ids[0] if not _selected_unit_ids.is_empty() else ""
	_persist_units_to_state()
	GameState.gameplay_orders = _orders.duplicate(true)
	_autosave_current_game()
	_update_order_action_panel()
	_refresh_selected_hex_panel(_selected_hex)
	_update_info_label(String(result.get("reason", "Formation updated.")))
	queue_redraw()

func _set_order_mode(mode: OrderMode) -> void:
	_active_order_mode = mode
	_update_info_label()

func _on_move_mode_pressed() -> void:
	if _battle_resolution_input_blocked:
		return
	_set_order_mode(OrderMode.MOVE)

func _on_attack_mode_pressed() -> void:
	if _battle_resolution_input_blocked:
		return
	_set_order_mode(OrderMode.ATTACK)

func _on_dig_in_mode_pressed() -> void:
	if _battle_resolution_input_blocked:
		return
	_set_order_mode(OrderMode.DIG_IN)
	var selected_unit_ids := _selected_order_unit_ids()
	if not selected_unit_ids.is_empty():
		_issue_group_dig_in_orders(selected_unit_ids)

func _order_mode_text() -> String:
	match _active_order_mode:
		OrderMode.ATTACK:
			return "Attack"
		OrderMode.DIG_IN:
			return "Dig In"
		_:
			return "Move"

func _update_info_label(status_message: String = "") -> void:
	var controls := "Mode: %s | Double-click a hex to select its friendly stack, click a unit card to select, Shift-click cards to adjust a same-hex group, drag selected units to move, click+drag empty space to pan, mouse wheel to zoom, right-click hex to issue mode action." % _order_mode_text()
	if status_message.is_empty():
		info_label.text = controls
		return
	info_label.text = "%s %s" % [status_message, controls]

func _on_end_turn_pressed() -> void:
	if _battle_resolution_input_blocked:
		return
	_scheduled_ai_turn_key = ""
	if _is_active_player_ai_controlled():
		_generate_ai_orders_for_active_player()
	_orders = _prune_orders_for_dead_units(_orders)
	var resolving_player := _active_player
	var result := TurnResolver.resolve_turn(_units.duplicate(true), _orders, _combat_log, {
		"scout_intel_by_observer": GameState.scout_intel_by_observer.duplicate(true),
		"active_owner": _active_player,
		"map_dimensions": Vector2i(GRID_COLUMNS, GRID_ROWS),
		"scout_intel": _active_player_scout_intel(),
		"ignore_visibility": _is_fog_visibility_overridden()
	})
	_units = result.get("units", {})
	GameState.scout_intel_by_observer = result.get("scout_intel_by_observer", GameState.scout_intel_by_observer).duplicate(true)
	_persist_units_to_state()
	_refresh_selected_hex_panel(_selected_hex)
	_execution_queue = _typed_execution_queue(result.get("execution_queue", []))
	GameState.combat_log_entries = _combat_log.entries.duplicate(true)
	_pending_battle_payload = {
		"resolving_player": resolving_player,
		"resolving_turn": GameState.current_turn,
		"own": result.get("own_casualties", []),
		"enemy": result.get("enemy_casualties", []),
		"known_enemy_units": result.get("known_enemy_units", []),
		"engagements": result.get("engagements", []),
		"battles": _group_engagements_by_defender_hex(result.get("engagements", []) as Array),
		"current_battle_index": 0,
		"results": [],
		"workflow_stage": "announcement" if not (result.get("engagements", []) as Array).is_empty() else "summary"
	}
	_orders.clear()
	GameState.gameplay_orders.clear()
	_preview_path.clear()
	_preview_target_hex = Vector2i(-9999, -9999)
	if _execution_queue.is_empty():
		_complete_resolved_turn()
		return
	animation_timer.start()
	end_turn_button.disabled = true


func _typed_execution_queue(raw_queue: Variant) -> Array[Dictionary]:
	var typed_queue: Array[Dictionary] = []
	if typeof(raw_queue) != TYPE_ARRAY:
		return typed_queue
	for step_variant in raw_queue as Array:
		if typeof(step_variant) == TYPE_DICTIONARY:
			typed_queue.append((step_variant as Dictionary).duplicate(true))
	return typed_queue

func _is_active_player_ai_controlled() -> bool:
	if _active_player < 0 or _active_player >= GameState.players.size():
		return false
	var player := GameState.players[_active_player] as Dictionary
	return String(player.get("controller", "human")).strip_edges().to_lower() == "ai"

func _generate_ai_orders_for_active_player() -> void:
	var operational_state_for_orders: Dictionary = {}
	_persist_units_to_state()
	OperationalAIService.run_for_active_player({
		"trace_id": "operational_ai_refresh_turn_%d_player_%d" % [int(GameState.current_turn), _active_player],
		"session_id": "gameplay_ai_turn_%d" % int(GameState.current_turn)
	})
	if int(GameState.operational_ai_state.get("playerIndex", -1)) == _active_player:
		operational_state_for_orders = GameState.operational_ai_state.duplicate(true)
	var player_state_key := str(_active_player)
	var original_units := _units.duplicate(true)
	var original_formation_state := (GameState.ai_formation_state.get(player_state_key, {}) as Dictionary).duplicate(true)
	var formation_result := FormationPosturePlanner.prepare_ai_turn(
		_units,
		_active_player,
		_active_division_tree(),
		operational_state_for_orders,
		GameState.key_objectives,
		GameState.territory_map,
		GameState.terrain_map,
		GameState.selected_ai_doctrine,
		GameState.current_turn,
		original_formation_state
	)
	var candidate_units := (formation_result.get("units", _units) as Dictionary).duplicate(true)
	var candidate_orders := GameplayAIService.generate_orders(candidate_units.duplicate(true), _active_player, GameState.terrain_map.duplicate(true), operational_state_for_orders, _ai_order_trace_context(formation_result))
	var transaction_validation := _validate_atomic_formation_transaction(formation_result, candidate_units, candidate_orders)
	if bool(transaction_validation.get("ok", false)):
		_units = candidate_units
		_orders = candidate_orders
		var transaction := (formation_result.get("transaction", {}) as Dictionary).duplicate(true)
		if bool(transaction.get("changed", false)):
			transaction["committed"] = true
			formation_result["transaction"] = transaction
		GameState.ai_formation_state[player_state_key] = (formation_result.get("state", {}) as Dictionary).duplicate(true)
	else:
		_units = original_units
		GameState.ai_formation_state[player_state_key] = original_formation_state
		var rejection_reason := String(transaction_validation.get("reason", "formation split could not be completed legally"))
		var decisions := (formation_result.get("decisions", []) as Array).duplicate(true)
		decisions.append({"action": "split_rejected", "reason": rejection_reason, "atomic_rollback": true})
		formation_result["decisions"] = decisions
		formation_result["units"] = _units.duplicate(true)
		formation_result["assignments"] = {}
		formation_result["state"] = original_formation_state.duplicate(true)
		formation_result["posture"] = "hold"
		var rejected_transaction := (formation_result.get("transaction", {}) as Dictionary).duplicate(true)
		rejected_transaction["committed"] = false
		rejected_transaction["rejection_reason"] = rejection_reason
		formation_result["transaction"] = rejected_transaction
		_orders = GameplayAIService.generate_orders(_units.duplicate(true), _active_player, GameState.terrain_map.duplicate(true), operational_state_for_orders, _ai_order_trace_context(formation_result))
	GameState.gameplay_units = _units.duplicate(true)
	var ai_debug_key := "player_%d" % _active_player
	var ai_debug := GameState.operational_ai_debug.get(ai_debug_key, {}) as Dictionary
	var trace_outputs := (ai_debug.get("outputs", {}) as Dictionary).duplicate(true)
	trace_outputs["formation_posture"] = formation_result.duplicate(true)
	ai_debug["outputs"] = trace_outputs
	GameState.operational_ai_debug[ai_debug_key] = ai_debug
	_update_info_label("AI generated %d order(s) for Player %d." % [_orders.size(), _active_player + 1])
	queue_redraw()

func _ai_order_trace_context(formation_result: Dictionary) -> Dictionary:
	return {
		"trace_id": "gameplay_ai_turn_%d_player_%d" % [int(GameState.current_turn), _active_player],
		"session_id": "gameplay_ai_turn_%d" % int(GameState.current_turn),
		"active_owner": _active_player,
		"map_dimensions": Vector2i(GRID_COLUMNS, GRID_ROWS),
		"scout_intel": _active_player_scout_intel(),
		"ignore_visibility": _is_fog_visibility_overridden(),
		"formation_assignments": formation_result.get("assignments", {}),
		"formation_defending": bool(formation_result.get("defending", false))
	}

func _validate_atomic_formation_transaction(formation_result: Dictionary, candidate_units: Dictionary, candidate_orders: Dictionary) -> Dictionary:
	var transaction := formation_result.get("transaction", {}) as Dictionary
	if not bool(transaction.get("requires_atomic_validation", false)):
		return {"ok": true, "reason": ""}
	var preview := TurnResolver.preview_movement(candidate_units, candidate_orders)
	var violations := preview.get("stack_violations", []) as Array
	if not violations.is_empty():
		return {"ok": false, "reason": "projected split leaves an illegal stack: %s" % String((violations[0] as Dictionary).get("reason", "stack violation"))}
	var projected_units := preview.get("units", {}) as Dictionary
	var assignments := formation_result.get("assignments", {}) as Dictionary
	for unit_id_variant in transaction.get("created_component_ids", []) as Array:
		var unit_id := String(unit_id_variant)
		if not assignments.has(unit_id) or not (assignments[unit_id] is Vector2i):
			return {"ok": false, "reason": "split component %s has no legal coverage assignment" % unit_id}
		if not projected_units.has(unit_id):
			return {"ok": false, "reason": "split component %s is missing from the movement preview" % unit_id}
		var assigned_hex := assignments[unit_id] as Vector2i
		var final_hex := (projected_units[unit_id] as Dictionary).get("hex", Vector2i.ZERO) as Vector2i
		if final_hex != assigned_hex:
			return {"ok": false, "reason": "split component %s cannot reach its assigned coverage hex" % unit_id}
	return {"ok": true, "reason": ""}


func _active_player_scout_intel() -> Dictionary:
	var key := str(_active_player)
	var by_observer := GameState.scout_intel_by_observer
	if by_observer.has(key) and by_observer[key] is Dictionary:
		return (by_observer[key] as Dictionary).duplicate(true)
	return {}

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

func _complete_resolved_turn() -> void:
	animation_timer.stop()
	end_turn_button.disabled = false
	_clear_unit_selection()
	_active_player = 1 - _active_player
	GameState.active_player = _active_player
	GameState.current_turn += 1
	_refresh_log()
	_update_order_action_panel()
	_refresh_selected_hex_panel(_selected_hex)
	_finish_pending_battle()

func _group_engagements_by_defender_hex(engagements: Array) -> Array[Dictionary]:
	var battles_by_hex := {}
	for engagement_variant in engagements:
		if typeof(engagement_variant) != TYPE_DICTIONARY:
			continue
		var engagement := engagement_variant as Dictionary
		var defender_hex := engagement.get("defender_hex", {}) as Dictionary
		var q := int(defender_hex.get("q", 0))
		var r := int(defender_hex.get("r", 0))
		var hex_key := "%d,%d" % [q, r]
		if not battles_by_hex.has(hex_key):
			battles_by_hex[hex_key] = {
				"hex": {"q": q, "r": r},
				"engagements": [],
				"attacker_unit_ids": [],
				"defender_unit_ids": []
			}
		var battle := battles_by_hex[hex_key] as Dictionary
		(battle["engagements"] as Array).append(engagement.duplicate(true))
		_append_unique_string(battle["attacker_unit_ids"] as Array, String(engagement.get("attacker_unit_id", "")))
		_append_unique_string(battle["defender_unit_ids"] as Array, String(engagement.get("defender_unit_id", "")))
		battles_by_hex[hex_key] = battle
	var battles: Array[Dictionary] = []
	var sorted_keys: Array = battles_by_hex.keys()
	sorted_keys.sort_custom(func(a: String, b: String) -> bool:
		var a_parts := a.split(",")
		var b_parts := b.split(",")
		var a_q := int(a_parts[0])
		var b_q := int(b_parts[0])
		var a_r := int(a_parts[1])
		var b_r := int(b_parts[1])
		return a_r < b_r or (a_r == b_r and a_q < b_q)
	)
	for hex_key in sorted_keys:
		var battle := (battles_by_hex[hex_key] as Dictionary).duplicate(true)
		_append_all_defenders_on_battle_hex(battle)
		battles.append(battle)
	return battles

func _append_all_defenders_on_battle_hex(battle: Dictionary) -> void:
	var hex_data := battle.get("hex", {}) as Dictionary
	var battle_hex := Vector2i(int(hex_data.get("q", 0)), int(hex_data.get("r", 0)))
	var defender_owners := {}
	for engagement_variant in battle.get("engagements", []) as Array:
		if engagement_variant is Dictionary:
			var engagement := engagement_variant as Dictionary
			var defender_owner := int(engagement.get("defender_owner", -1))
			if defender_owner >= 0:
				defender_owners[defender_owner] = true
	var defender_ids := battle.get("defender_unit_ids", []) as Array
	for unit_id_variant in _units.keys():
		var unit_id := String(unit_id_variant)
		var unit := _units[unit_id] as Dictionary
		if not GameState.is_unit_alive(unit) or (unit.get("hex", Vector2i.ZERO) as Vector2i) != battle_hex:
			continue
		var owner := int(unit.get("owner", -1))
		if not defender_owners.is_empty() and not defender_owners.has(owner):
			continue
		_append_unique_string(defender_ids, unit_id)
	defender_ids.sort()
	battle["defender_unit_ids"] = defender_ids

func _append_unique_string(values: Array, value: String) -> void:
	if not value.is_empty() and not values.has(value):
		values.append(value)

func _finish_pending_battle() -> void:
	if _pending_battle_payload.is_empty():
		return
	GameState.pending_casualties = _pending_battle_payload.duplicate(true)
	_pending_battle_payload.clear()
	_sync_battle_map_context()
	_autosave_current_game()
	GameState.set_phase(GameState.Phase.CASUALTY_ENTRY)

func _sync_battle_map_context() -> void:
	_battle_highlight_hexes.clear()
	if GameState.pending_casualties.is_empty():
		queue_redraw()
		return
	var battles := GameState.pending_casualties.get("battles", []) as Array
	var battle_index := int(GameState.pending_casualties.get("current_battle_index", 0))
	if battle_index >= 0 and battle_index < battles.size() and battles[battle_index] is Dictionary:
		var hex_data := (battles[battle_index] as Dictionary).get("hex", {}) as Dictionary
		var battle_hex := Vector2i(int(hex_data.get("q", 0)), int(hex_data.get("r", 0)))
		if not hex_data.is_empty():
			_battle_highlight_hexes.append(battle_hex)
	_focus_camera_on_battle_hexes()
	queue_redraw()

func sync_battle_resolution_context() -> void:
	_units = GameState.gameplay_units.duplicate(true)
	_refresh_selected_hex_panel(_selected_hex)
	_sync_battle_map_context()

static func territory_fill_color(owner: int, visible: bool) -> Color:
	var color := NEUTRAL_TERRITORY_COLOR
	if owner == GameState.TerritoryOwnership.PLAYER_1:
		color = PLAYER_1_TERRITORY_COLOR
	elif owner == GameState.TerritoryOwnership.PLAYER_2:
		color = PLAYER_2_TERRITORY_COLOR
	if visible:
		return color
	return Color(color.r * 0.32, color.g * 0.32, color.b * 0.32, 0.97)

func _focus_camera_on_battle_hexes() -> void:
	if _battle_highlight_hexes.is_empty():
		return
	var minimum := _hex_center(_battle_highlight_hexes[0].x, _battle_highlight_hexes[0].y)
	var maximum := minimum
	for battle_hex in _battle_highlight_hexes:
		var center := _hex_center(battle_hex.x, battle_hex.y)
		minimum.x = minf(minimum.x, center.x)
		minimum.y = minf(minimum.y, center.y)
		maximum.x = maxf(maximum.x, center.x)
		maximum.y = maxf(maximum.y, center.y)
	var map_view_size := Vector2(maxf(size.x - 416.0, 320.0), maxf(size.y, 240.0))
	var bounds_size := maximum - minimum + Vector2(HEX_RADIUS * 4.0, HEX_RADIUS * 4.0)
	var fit_zoom := minf(map_view_size.x / maxf(bounds_size.x, 1.0), map_view_size.y / maxf(bounds_size.y, 1.0))
	_camera_zoom = clampf(minf(fit_zoom, 1.5), MIN_ZOOM, MAX_ZOOM)
	var map_view_center := Vector2(map_view_size.x * 0.5, map_view_size.y * 0.5)
	_camera_offset = map_view_center - ((minimum + maximum) * 0.5) * _camera_zoom

func set_battle_resolution_overlay_active(active: bool) -> void:
	if _battle_resolution_input_blocked == active:
		return
	_battle_resolution_input_blocked = active
	if active:
		_controls_disabled_before_battle_resolution = {
			"end_turn": end_turn_button.disabled,
			"move": move_button.disabled,
			"attack": attack_button.disabled,
			"dig_in": dig_in_button.disabled,
			"combine": combine_button.disabled,
			"split": split_button.disabled
		}
		end_turn_button.disabled = true
		move_button.disabled = true
		attack_button.disabled = true
		dig_in_button.disabled = true
		combine_button.disabled = true
		split_button.disabled = true
		_is_panning = false
		_drag_candidate_unit_id = ""
		_dragging_unit_id = ""
		_preview_recalc_due_at_msec = 0
		return

	end_turn_button.disabled = bool(_controls_disabled_before_battle_resolution.get("end_turn", false))
	move_button.disabled = bool(_controls_disabled_before_battle_resolution.get("move", false))
	attack_button.disabled = bool(_controls_disabled_before_battle_resolution.get("attack", false))
	dig_in_button.disabled = bool(_controls_disabled_before_battle_resolution.get("dig_in", false))
	combine_button.disabled = bool(_controls_disabled_before_battle_resolution.get("combine", false))
	split_button.disabled = bool(_controls_disabled_before_battle_resolution.get("split", false))
	_controls_disabled_before_battle_resolution.clear()
	_sync_after_battle_resolution()

func is_battle_resolution_overlay_active() -> bool:
	return _battle_resolution_input_blocked

func autosave_battle_resolution_state() -> void:
	_units = GameState.gameplay_units.duplicate(true)
	_orders = GameState.gameplay_orders.duplicate(true)
	_autosave_current_game()

func _sync_after_battle_resolution() -> void:
	_units = GameState.gameplay_units.duplicate(true)
	_orders = GameState.gameplay_orders.duplicate(true)
	_clear_unit_selection()
	_refresh_selected_hex_panel(_selected_hex)
	_update_order_action_panel()
	_refresh_log()
	_sync_battle_map_context()
	queue_redraw()
	_begin_player_turn()

func _on_animation_step() -> void:
	if _execution_queue.is_empty():
		_complete_resolved_turn()
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
	_refresh_selected_hex_panel(_selected_hex)
	queue_redraw()

func _refresh_log() -> void:
	_clear_control_children(events_list)
	events_toggle_button.text = "Events (%d) %s" % [_combat_log.entries.size(), ("▾" if _events_expanded else "▸")]
	events_scroll.visible = _events_expanded
	var valid_event_keys := {}
	if _combat_log.entries.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No events yet."
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		events_list.add_child(empty_label)
		_expanded_event_keys.clear()
		return

	for index in range(_combat_log.entries.size()):
		var entry := _combat_log.entries[index] as Dictionary
		var event_key := _event_key(index, entry)
		valid_event_keys[event_key] = true
		_add_event_row(index, entry, event_key)
	for expanded_key_variant in _expanded_event_keys.keys():
		if not valid_event_keys.has(expanded_key_variant):
			_expanded_event_keys.erase(expanded_key_variant)
	if _events_expanded:
		call_deferred("_scroll_events_to_latest")

func _on_events_toggle_pressed() -> void:
	_events_expanded = not _events_expanded
	_refresh_log()

func _event_key(index: int, entry: Dictionary) -> String:
	return "%d|%s|%s" % [index, String(entry.get("timestamp", "--")), String(entry.get("summary", ""))]

func _add_event_row(index: int, entry: Dictionary, event_key: String) -> void:
	var details := entry.get("details", {}) as Dictionary
	var expanded := bool(_expanded_event_keys.get(event_key, false))
	var expansion_marker := "•" if details.is_empty() else ("▾" if expanded else "▸")
	var row := VBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.set_meta("event_index", index)
	row.set_meta("event_key", event_key)

	var header := Button.new()
	header.text = "%s [%s] %s" % [
		expansion_marker,
		String(entry.get("timestamp", "--")),
		_display_log_summary(String(entry.get("summary", "")))
	]
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.disabled = details.is_empty()
	header.set_meta("event_key", event_key)
	header.set_meta("summary_text", "[%s] %s" % [String(entry.get("timestamp", "--")), _display_log_summary(String(entry.get("summary", "")))])
	row.add_child(header)

	var detail_label := Label.new()
	detail_label.text = _format_event_details(details)
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_label.visible = expanded and not details.is_empty()
	detail_label.set_meta("event_details", true)
	row.add_child(detail_label)
	if not details.is_empty():
		header.pressed.connect(_on_event_row_pressed.bind(event_key, header, detail_label))
	events_list.add_child(row)

func _on_event_row_pressed(event_key: String, header: Button, detail_label: Label) -> void:
	var expanded := not bool(_expanded_event_keys.get(event_key, false))
	_expanded_event_keys[event_key] = expanded
	detail_label.visible = expanded
	header.text = "%s %s" % [("▾" if expanded else "▸"), String(header.get_meta("summary_text", ""))]

func _format_event_details(details: Dictionary) -> String:
	var keys: Array[String] = []
	for key_variant in details.keys():
		keys.append(String(key_variant))
	keys.sort()
	var lines: Array[String] = []
	for key in keys:
		lines.append("%s: %s" % [_event_detail_label(key), _event_detail_value(key, details.get(key))])
	return "\n".join(lines)

func _event_detail_label(key: String) -> String:
	match key:
		"unit_id": return "Unit"
		"attacker_unit_id": return "Attacker"
		"defender_unit_id": return "Defender"
		"attacker_owner": return "Attacker Player"
		"defender_owner": return "Defender Player"
		"attacker_hex": return "Attacker Hex"
		"defender_hex": return "Defender Hex"
		"recon_band": return "Recon"
		"was_dug_in": return "Previously Dug In"
		"is_dug_in": return "Now Dug In"
	return key.replace("_", " ").capitalize()

func _event_detail_value(key: String, value: Variant) -> String:
	if value is bool:
		return "Yes" if bool(value) else "No"
	if value is Vector2i:
		var coordinate := value as Vector2i
		return "%d,%d" % [coordinate.x, coordinate.y]
	if value is Dictionary:
		var dictionary := value as Dictionary
		if dictionary.has("q") and dictionary.has("r"):
			return "%d,%d" % [int(dictionary.get("q", 0)), int(dictionary.get("r", 0))]
		var nested_parts: Array[String] = []
		var nested_keys: Array[String] = []
		for nested_key_variant in dictionary.keys():
			nested_keys.append(String(nested_key_variant))
		nested_keys.sort()
		for nested_key in nested_keys:
			nested_parts.append("%s: %s" % [_event_detail_label(nested_key), _event_detail_value(nested_key, dictionary.get(nested_key))])
		return "; ".join(nested_parts) if not nested_parts.is_empty() else "None"
	if value is Array:
		var values: Array[String] = []
		for item in value as Array:
			values.append(_event_detail_value(key, item))
		return ", ".join(values) if not values.is_empty() else "None"
	if key.to_lower().contains("unit_id"):
		return _unit_display_name_by_id(str(value))
	if key.to_lower().ends_with("owner") and typeof(value) == TYPE_INT:
		return "Player %d" % (int(value) + 1)
	return str(value)

func _scroll_events_to_latest() -> void:
	if not _events_expanded or not is_instance_valid(events_scroll):
		return
	var scroll_bar := events_scroll.get_v_scroll_bar()
	events_scroll.scroll_vertical = int(scroll_bar.max_value)

func _display_log_summary(summary: String) -> String:
	var display_summary := summary
	var unit_ids: Array[String] = []
	for unit_id_variant in _units.keys():
		unit_ids.append(String(unit_id_variant))
	unit_ids.sort_custom(func(a: String, b: String) -> bool:
		return a.length() > b.length()
	)
	for unit_id in unit_ids:
		var display_name := _unit_display_name_by_id(unit_id)
		if display_name != unit_id:
			display_summary = display_summary.replace(unit_id, display_name)
	return display_summary

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
			for unit_data in _deployment_units_from_variant(deployments[key]):
				if not GameState.is_unit_alive(unit_data):
					continue
				var unit_type := _normalized_unit_type(unit_data.get("type", "infantry"))
				if unit_type == "headquarters":
					continue
				var id := String(unit_data.get("id", "P%d_U_%d_%d" % [player_index + 1, q, r]))
				var designation := _unit_designation_payload(unit_data)
				var gameplay_unit := {
					"id": id,
					"template_id": String(unit_data.get("template_id", "")),
					"display_name": String(unit_data.get("display_name", "")),
					"short_name": String(unit_data.get("short_name", "")),
					"designation": designation,
					"owner": player_index,
					"hex": Vector2i(q, r),
					"initiative": 50,
					"type": unit_type,
					"role": UnitRole.normalize(unit_data.get("role", ""), unit_type),
					"size": String(unit_data.get("size", "company")),
					"is_attached": bool(unit_data.get("is_attached", false)),
					"status": String(unit_data.get("status", "alive")).to_lower(),
					"recon_bonus": 0 if unit_type == "tank" else 5,
					"concealment": 5
				}
				var vehicles := unit_data.get("vehicles", []) as Array
				if not vehicles.is_empty():
					gameplay_unit["vehicles"] = vehicles.duplicate(true)
					gameplay_unit["live_sub_units"] = _living_vehicle_count(vehicles)
					gameplay_unit["max_sub_units"] = vehicles.size()
				generated[id] = gameplay_unit
	_units = generated
	GameState.gameplay_units = _units.duplicate(true)

func _living_vehicle_count(vehicles: Array) -> int:
	var living := 0
	for vehicle_variant in vehicles:
		if vehicle_variant is Dictionary and GameState.is_unit_alive(vehicle_variant as Dictionary):
			living += 1
	return living

func _deployment_units_from_variant(deployment_variant: Variant) -> Array[Dictionary]:
	var units: Array[Dictionary] = []
	if typeof(deployment_variant) == TYPE_DICTIONARY:
		units.append(deployment_variant as Dictionary)
	elif typeof(deployment_variant) == TYPE_ARRAY:
		for unit_variant in (deployment_variant as Array):
			if typeof(unit_variant) == TYPE_DICTIONARY:
				units.append(unit_variant as Dictionary)
	return units

func _without_headquarters_units(units: Dictionary) -> Dictionary:
	var filtered := {}
	for unit_id_variant in units.keys():
		var unit_id := String(unit_id_variant)
		var unit_variant: Variant = units[unit_id_variant]
		if typeof(unit_variant) != TYPE_DICTIONARY:
			continue
		var unit := unit_variant as Dictionary
		var unit_type := _normalized_unit_type(unit.get("type", "infantry"))
		if unit_type == "headquarters":
			continue
		filtered[unit_id] = unit.duplicate(true)
	return filtered

func _normalized_unit_type(raw_type: Variant) -> String:
	return String(raw_type).strip_edges().to_lower()

func _begin_player_turn() -> void:
	_autosave_current_game()
	if not _pending_battle_payload.is_empty() or not GameState.pending_casualties.is_empty():
		return
	if not _is_active_player_ai_controlled():
		return
	var turn_key := "%d:%d" % [GameState.current_turn, _active_player]
	if _scheduled_ai_turn_key == turn_key:
		return
	_scheduled_ai_turn_key = turn_key
	call_deferred("_run_ai_turn_if_still_active", turn_key)

func _run_ai_turn_if_still_active(turn_key: String = "") -> void:
	if not turn_key.is_empty() and _scheduled_ai_turn_key != turn_key:
		return
	_scheduled_ai_turn_key = ""
	if GameState.current_phase != GameState.Phase.GAMEPLAY:
		return
	if _active_player != GameState.active_player:
		return
	if not _is_active_player_ai_controlled():
		return
	if not GameState.pending_casualties.is_empty():
		return
	if end_turn_button.disabled:
		return
	_on_end_turn_pressed()

func _autosave_current_game() -> bool:
	GameState.active_player = _active_player
	GameState.gameplay_orders = _orders.duplicate(true)
	var autosave_payload: Dictionary = {
		"turn_number": GameState.current_turn,
		"active_player": _active_player,
		"players": GameState.players.duplicate(true),
		"ai_debug": {
			"enabled": GameState.debug_mode_enabled,
			"level": GameState.debug_mode_level
		},
		"map": {
			"version": GameState.MAP_PAYLOAD_VERSION_CURRENT,
			"name": String(GameState.selected_map_name),
			"grid": {"columns": GRID_COLUMNS, "rows": GRID_ROWS},
			"terrain": GameState.terrain_map.duplicate(true),
			"territory": GameState.territory_map.duplicate(true),
			"objectives": GameState.key_objectives.duplicate(true),
			"ai_doctrine": String(GameState.selected_ai_doctrine),
			"difficulty": String(GameState.selected_difficulty)
		},
		"ai_formation_state": GameState.ai_formation_state.duplicate(true),
		"scout_intel_by_observer": GameState.scout_intel_by_observer.duplicate(true),
		"units": _serialize_units(_units),
		"orders": _serialize_orders(_orders),
		"casualties": GameState.pending_casualties.duplicate(true),
		"combat_log_entries": _combat_log.entries.duplicate(true)
	}
	var saved := SaveManager.autosave(autosave_payload)
	if not saved:
		push_error("Autosave failed. The current turn state was not persisted.")
		_update_info_label("Autosave failed. Check the Godot log for details.")
	return saved

func _serialize_units(units: Dictionary) -> Dictionary:
	var serialized := {}
	for unit_id in units.keys():
		serialized[unit_id] = _serialize_unit_snapshot(units[unit_id] as Dictionary)
	return serialized

func _serialize_unit_snapshot(unit: Dictionary) -> Dictionary:
	var next := unit.duplicate(true)
	var hex_variant: Variant = unit.get("hex", Vector2i.ZERO)
	if hex_variant is Vector2i:
		var hex := hex_variant as Vector2i
		next["hex"] = {"x": hex.x, "y": hex.y}
	var serialized_components: Array[Dictionary] = []
	for component_variant in unit.get("combined_components", []) as Array:
		if component_variant is Dictionary:
			serialized_components.append(_serialize_unit_snapshot(component_variant as Dictionary))
	if unit.has("combined_components"):
		next["combined_components"] = serialized_components
	return next

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
	if _active_order_mode != OrderMode.MOVE:
		return
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
	if _active_order_mode != OrderMode.MOVE:
		_preview_path.clear()
		_preview_target_hex = Vector2i(-9999, -9999)
		_pending_preview_target_hex = Vector2i(-9999, -9999)
		queue_redraw()
		return
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
			_autosave_current_game()
			_refresh_selected_hex_panel(_selected_hex)
			return true
	return false


func _units_at_hex(hex: Vector2i, owner: int = -1, apply_visibility_filter: bool = false) -> Array[Dictionary]:
	var units_at_hex: Array[Dictionary] = []
	var hex_visible := _is_hex_visible_to_active_player(hex)
	for unit_id in _units.keys():
		var unit := _units[unit_id] as Dictionary
		if not GameState.is_unit_alive(unit):
			continue
		var unit_owner := int(unit.get("owner", -1))
		if apply_visibility_filter and not _is_unit_visible_to_active_player(unit_owner, hex_visible):
			continue
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

func _is_fog_visibility_overridden() -> bool:
	return bool(GameState.debug_mode_enabled)

func _is_hex_visible_to_active_player(hex: Vector2i) -> bool:
	if _is_fog_visibility_overridden():
		return true
	for unit in _units.values():
		if not (unit is Dictionary):
			continue
		var unit_dict := unit as Dictionary
		if not GameState.is_unit_alive(unit_dict):
			continue
		if int(unit_dict.get("owner", -1)) != _active_player:
			continue
		var friendly_hex := unit_dict.get("hex", Vector2i.ZERO) as Vector2i
		if friendly_hex == hex:
			return true
		if Pathfinding.are_adjacent(friendly_hex, hex):
			return true
	return false

func _is_unit_visible_to_active_player(unit_owner: int, hex_visible: bool) -> bool:
	if unit_owner == _active_player:
		return true
	if _is_fog_visibility_overridden():
		return true
	return hex_visible

func _unit_at_hex(hex: Vector2i, owner: int) -> String:
	var matches := _units_at_hex(hex, owner, true)
	if not matches.is_empty():
		return String(matches[0].get("id", ""))
	return ""

func _front_entry_for_stack(stack: Array[Dictionary]) -> Dictionary:
	for entry in stack:
		if String(entry.get("id", "")) == _selected_unit_id:
			return entry
	for entry in stack:
		if _is_unit_selected(String(entry.get("id", ""))):
			return entry
	return stack[0] if not stack.is_empty() else {}

func _next_friendly_unit_after(hex: Vector2i, current_unit_id: String) -> String:
	var friendly := _units_at_hex(hex, _active_player)
	if friendly.is_empty():
		return ""
	for index in range(friendly.size()):
		if String((friendly[index] as Dictionary).get("id", "")) == current_unit_id:
			return String((friendly[(index + 1) % friendly.size()] as Dictionary).get("id", ""))
	return String((friendly[0] as Dictionary).get("id", ""))

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
	return Vector2((float(column) * spacing) - (width * 0.5), (float(row) * spacing) - (height * 0.5)) * _camera_zoom

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
	return world_position * _camera_zoom + _camera_offset

func _screen_to_world(screen_position: Vector2) -> Vector2:
	return (screen_position - _camera_offset) / _camera_zoom

func _set_camera_zoom_at(screen_position: Vector2, requested_zoom: float) -> void:
	var next_zoom := clampf(requested_zoom, MIN_ZOOM, MAX_ZOOM)
	if is_equal_approx(next_zoom, _camera_zoom):
		return
	var anchored_world_position := _screen_to_world(screen_position)
	_camera_zoom = next_zoom
	_camera_offset = screen_position - anchored_world_position * _camera_zoom
	_update_hovered_hex(screen_position)
	queue_redraw()


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
