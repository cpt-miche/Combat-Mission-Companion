extends Node

const GAMEPLAY_SCREEN_SCENE := preload("res://scenes/screens/GameplayScreen.tscn")
const GameplayScreenScript := preload("res://scripts/ui/gameplay/GameplayScreen.gd")
const MAIN_MENU_SCREEN_SCENE := preload("res://scenes/main_menu/MainMenuScreen.tscn")
const DEPLOYMENT_SCREEN_SCENE := preload("res://scenes/deployment/DeploymentScreen.tscn")
const OrderSystem = preload("res://scripts/systems/OrderSystem.gd")
const FormationOperations = preload("res://scripts/domain/units/FormationOperations.gd")
const FormationHierarchy = preload("res://scripts/domain/units/FormationHierarchy.gd")
const NatoUnitSymbolRenderer = preload("res://scripts/ui/shared/NatoUnitSymbolRenderer.gd")

var _failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	await get_tree().process_frame
	_test_main_menu_side_choice_opens_only_after_play()
	_test_map_zoom_clamps_and_keeps_cursor_anchor()
	_test_map_zoom_ignores_wheel_over_visible_controls()
	_test_nato_symbol_specs_and_bounds()
	_test_nato_stack_counter_cycles_and_preserves_drag_target()
	_test_zoomed_map_supports_selection_hover_drag_and_attack()
	_test_selection_exposes_order_actions()
	_test_mode_based_order_issuing()
	_test_left_click_move_tile_issues_move_order()
	_test_order_changes_refresh_autosave_payload()
	_test_stack_cap_feedback()
	_test_attack_order_requires_adjacent_target()
	_test_empty_execution_queue_advances_turn()
	_test_attack_order_starts_battle_resolution_payload()
	_test_engagements_group_by_defender_hex_in_resolver_order()
	_test_territory_colors_remain_distinct_through_fog()
	_test_partial_combine_split_and_verbal_hierarchy()
	_test_formation_split_preserves_current_vehicle_state()
	_test_atomic_split_validation_rejects_illegal_final_stack()
	_test_ai_turn_is_scheduled_once_after_resolution_closes()
	_test_loaded_orders_payload_restores_gameplay_orders()
	_test_starting_scenario_save_filter_and_direct_launch()
	_test_gameplay_uses_unit_notation_for_deployed_generated_ids()
	_test_selected_hex_panel_is_docked_in_right_sidebar()
	_test_selected_unit_inspector_shows_recursive_subordinate_status()
	_test_selected_unit_inspector_uses_combined_components()
	_test_events_accordion_formats_and_preserves_expansion()
	_test_selected_hex_panel_empty_hex()
	_test_selected_hex_panel_friendly_unit_details()
	_test_selected_hex_unit_cards_are_clickable_and_show_orders()
	_test_selected_hex_unit_cards_clear_selection_on_hex_change()
	_test_double_click_selects_living_friendly_stack()
	_test_shift_click_toggles_same_hex_selection_and_primary()
	_test_group_move_is_atomic_and_autosaves_only_complete_groups()
	_test_group_attack_orders_every_selected_unit()
	_test_group_dig_in_keeps_successes_and_reports_dead_unit()
	_test_selected_hex_panel_hides_unscouted_enemy_details()
	_test_selected_hex_panel_uses_recon_for_enemy_contacts()
	_test_selected_hex_panel_debug_shows_full_enemy_details()
	_test_selected_hex_panel_refreshes_after_dig_in_resolution()

	if _failures.is_empty():
		print("GameplayScreen integration tests passed.")
		get_tree().quit(0)
		return

	for failure in _failures:
		push_error(failure)
	get_tree().quit(1)

func _test_main_menu_side_choice_opens_only_after_play() -> void:
	var main_menu: Control = MAIN_MENU_SCREEN_SCENE.instantiate()
	get_tree().root.add_child(main_menu)
	_assert_true(not main_menu.nation_dialog.visible, "The main menu should not ask for a side before Play is pressed")
	main_menu.play_button.pressed.emit()
	_assert_true(main_menu.nation_dialog.visible, "Pressing Play should open the side-selection dialog")
	main_menu.cancel_nation_button.pressed.emit()
	_assert_true(not main_menu.nation_dialog.visible, "Canceling side selection should return to the unobstructed main menu")
	_cleanup_screen(main_menu)

func _test_map_zoom_clamps_and_keeps_cursor_anchor() -> void:
	_reset_state()
	var screen := _spawn_screen()
	screen._camera_offset = Vector2(47.0, -31.0)
	var cursor := Vector2(360.0, 300.0)
	var anchored_world_position: Vector2 = screen._screen_to_world(cursor)

	_scroll_gameplay_map(screen, cursor, true)
	_assert_true(screen._camera_zoom > 1.0, "Mouse-wheel up should zoom the gameplay map in")
	_assert_vector2_approx(anchored_world_position, screen._screen_to_world(cursor), "Gameplay zoom should keep the world position under the cursor fixed")
	for _index in range(100):
		_scroll_gameplay_map(screen, cursor, true)
	_assert_float_approx(screen.MAX_ZOOM, screen._camera_zoom, "Gameplay zoom should clamp at its maximum")
	_assert_vector2_approx(anchored_world_position, screen._screen_to_world(cursor), "Maximum zoom clamping should preserve the cursor anchor")
	for _index in range(200):
		_scroll_gameplay_map(screen, cursor, false)
	_assert_float_approx(screen.MIN_ZOOM, screen._camera_zoom, "Gameplay zoom should clamp at its minimum")
	_assert_vector2_approx(anchored_world_position, screen._screen_to_world(cursor), "Minimum zoom clamping should preserve the cursor anchor")
	_cleanup_screen(screen)

	var fresh_screen := _spawn_screen()
	_assert_float_approx(1.0, fresh_screen._camera_zoom, "A newly entered gameplay screen should start at default zoom")
	_cleanup_screen(fresh_screen)

func _test_map_zoom_ignores_wheel_over_visible_controls() -> void:
	_reset_state()
	var screen := _spawn_screen()
	var initial_zoom: float = screen._camera_zoom
	var sidebar := screen.get_node("%RightSidebar") as PanelContainer
	_scroll_gameplay_map(screen, screen.get_global_transform().affine_inverse() * sidebar.get_global_rect().get_center(), true)
	_assert_float_approx(initial_zoom, screen._camera_zoom, "Mouse-wheel input over the right sidebar should not zoom the combat map")

	screen.order_action_panel.visible = true
	_scroll_gameplay_map(screen, screen.get_global_transform().affine_inverse() * screen.order_action_panel.get_global_rect().get_center(), true)
	_assert_float_approx(initial_zoom, screen._camera_zoom, "Mouse-wheel input over the visible order panel should not zoom the combat map")

	_scroll_gameplay_map(screen, screen.get_global_transform().affine_inverse() * screen.end_turn_button.get_global_rect().get_center(), false)
	_assert_float_approx(initial_zoom, screen._camera_zoom, "Mouse-wheel input over End Turn should not zoom the combat map")

	screen.debug_level_modal.visible = true
	_scroll_gameplay_map(screen, screen.get_global_transform().affine_inverse() * screen.debug_level_modal.get_global_rect().get_center(), true)
	_assert_float_approx(initial_zoom, screen._camera_zoom, "Mouse-wheel input over the debug modal should not zoom the combat map")
	_cleanup_screen(screen)

func _test_nato_symbol_specs_and_bounds() -> void:
	var expected_functions := {
		"infantry": "infantry",
		"mechanized": "mechanized",
		"motorized": "motorized",
		"light_tank": "armor",
		"medium_tank": "armor",
		"heavy_tank": "armor",
		"tank_destroyer": "anti_armor",
		"assault_gun": "assault_gun",
		"anti_tank": "anti_armor",
		"weapons": "machine_gun",
		"heavy_machine_gun": "machine_gun",
		"81mm_mortar": "mortar",
		"105mm_howitzer": "artillery",
		"engineer": "engineer",
		"recon": "recon",
		"airborne": "airborne",
		"air_defense": "air_defense",
		"headquarters": "headquarters"
	}
	for role_variant in expected_functions.keys():
		var role := String(role_variant)
		var spec := NatoUnitSymbolRenderer.build_symbol_spec({"type": "infantry", "role": role, "size": "company"})
		_assert_equal(String(expected_functions[role]), String(spec.get("function", "")), "Expected NATO function mapping for role %s." % role)

	_assert_equal("light", String(NatoUnitSymbolRenderer.build_symbol_spec({"type": "tank", "role": "light_tank"}).get("equipment_weight", "")), "Light armor should carry the unbarred light weight class.")
	_assert_equal("medium", String(NatoUnitSymbolRenderer.build_symbol_spec({"type": "tank", "role": "medium_tank"}).get("equipment_weight", "")), "Medium armor should carry the thin-bar weight class.")
	_assert_equal("heavy", String(NatoUnitSymbolRenderer.build_symbol_spec({"type": "tank", "role": "heavy_tank"}).get("equipment_weight", "")), "Heavy armor should carry the thick-bar weight class.")
	_assert_equal("", String(NatoUnitSymbolRenderer.build_symbol_spec({"type": "tank", "role": "heavy_tank"}).get("qualifier", "")), "Equipment weight should no longer be drawn as an overlapping letter.")
	_assert_equal("heavy", String(NatoUnitSymbolRenderer.build_symbol_spec({"type": "infantry", "role": "heavy_machine_gun"}).get("equipment_weight", "")), "Heavy machine guns should encode weight in the arrow rather than an H overlay.")
	_assert_equal("light", String(NatoUnitSymbolRenderer.build_symbol_spec({"type": "tank", "role": "tank_destroyer", "template_id": "usa_m18_tank_destroyer_platoon"}).get("equipment_weight", "")), "M18 tank destroyers should use the light equipment treatment.")
	_assert_equal("medium", String(NatoUnitSymbolRenderer.build_symbol_spec({"type": "tank", "role": "tank_destroyer", "template_id": "usa_m36_tank_destroyer_platoon"}).get("equipment_weight", "")), "M36 tank destroyers should use the medium equipment treatment.")
	_assert_equal("tracked", String(NatoUnitSymbolRenderer.build_symbol_spec({"type": "tank", "role": "tank_destroyer"}).get("mobility", "")), "Tank destroyers should carry tracked mobility.")
	_assert_equal("1/A/2", String(NatoUnitSymbolRenderer.build_symbol_spec({"type": "infantry", "role": "infantry", "size": "platoon", "designation": {"platoon_number": 1, "company_letter": "A", "battalion_number": 2, "regiment_number": 9, "division_number": 4}}).get("identity_text", "")), "Counter identity should stop at battalion and omit regiment/division ancestry.")

	var echelon_expectations := {
		"squad": ["dot", 1],
		"section": ["dot", 2],
		"platoon": ["dot", 3],
		"company": ["bar", 1],
		"battalion": ["bar", 2],
		"regiment": ["bar", 3],
		"division": ["x", 2],
		"army": ["x", 4]
	}
	for size_variant in echelon_expectations.keys():
		var unit_size := String(size_variant)
		var expected := echelon_expectations[unit_size] as Array
		var echelon := NatoUnitSymbolRenderer.echelon_for_size(unit_size)
		_assert_equal(String(expected[0]), String(echelon.get("kind", "")), "Expected NATO echelon mark kind for %s." % unit_size)
		_assert_equal(int(expected[1]), int(echelon.get("count", 0)), "Expected NATO echelon mark count for %s." % unit_size)

	for radius in [30.0, 32.0]:
		for stack_count in [1, 4]:
			var bounds := NatoUnitSymbolRenderer.symbol_bounds(radius, stack_count)
			for corner in [bounds.position, bounds.position + Vector2(bounds.size.x, 0), bounds.end, bounds.position + Vector2(0, bounds.size.y)]:
				_assert_true(_point_inside_pointy_hex(corner, radius), "A %d-counter NATO stack should fit inside a %.0f px hex." % [stack_count, radius])
		var layout_scale: float = float(radius) / NatoUnitSymbolRenderer.REFERENCE_HEX_RADIUS
		for feature_point in [Vector2(0, -18.5), Vector2(0, 17.3), Vector2(21, -7)]:
			_assert_true(_point_inside_pointy_hex(feature_point * layout_scale, radius), "NATO echelon, mobility, and badge details should remain inside a %.0f px hex." % radius)

func _point_inside_pointy_hex(point: Vector2, radius: float) -> bool:
	var absolute := point.abs()
	if absolute.y > radius:
		return false
	var max_x := sqrt(3.0) * minf(radius * 0.5, radius - absolute.y)
	return absolute.x <= max_x + 0.01

func _test_nato_stack_counter_cycles_and_preserves_drag_target() -> void:
	_reset_state()
	(GameState.gameplay_units["a"] as Dictionary)["hex"] = Vector2i(0, 0)
	var screen := _spawn_screen()
	var counter_center: Vector2 = screen._world_to_screen(screen._hex_center(0, 0))
	screen._handle_left_press(counter_center)
	screen._handle_left_release(counter_center)
	_assert_equal("a", screen._selected_unit_id, "The first stack-counter click should select its deterministic front unit.")
	screen._handle_left_press(counter_center)
	screen._handle_left_release(counter_center)
	_assert_equal("u1", screen._selected_unit_id, "Clicking an already selected stack counter should cycle to the next unit.")
	screen._handle_left_press(counter_center)
	var drag_motion := InputEventMouseMotion.new()
	drag_motion.position = counter_center + Vector2(12, 0)
	drag_motion.relative = Vector2(12, 0)
	screen._handle_mouse_motion(drag_motion)
	_assert_equal("u1", screen._dragging_unit_id, "Dragging a stack counter should retain the selected front unit instead of cycling it.")
	_cleanup_screen(screen)

func _test_zoomed_map_supports_selection_hover_drag_and_attack() -> void:
	_reset_state()
	(GameState.gameplay_units["enemy"] as Dictionary)["hex"] = Vector2i(3, 3)
	var screen := _spawn_screen()
	screen._camera_offset = Vector2(38.0, -44.0)
	screen._set_camera_zoom_at(Vector2(340.0, 270.0), 1.6)
	var unit_position: Vector2 = screen._world_to_screen(screen._hex_center(0, 0))
	screen._handle_left_press(unit_position)
	screen._handle_left_release(unit_position)
	_assert_equal("u1", screen._selected_unit_id, "Clicking a zoomed unit marker should select the correct unit")

	var woods_position: Vector2 = screen._world_to_screen(screen._hex_center(0, 2))
	var hover_motion := InputEventMouseMotion.new()
	hover_motion.position = woods_position
	screen._handle_mouse_motion(hover_motion)
	_assert_equal(Vector2i(0, 2), screen._hovered_hex, "Hover hit testing should resolve the correct zoomed hex")
	_assert_true(String(screen.hovered_terrain_label.text).contains("Woods"), "Zoomed hover should refresh terrain information")

	screen._handle_left_press(unit_position)
	var drag_motion := InputEventMouseMotion.new()
	drag_motion.position = woods_position
	drag_motion.relative = woods_position - unit_position
	screen._handle_mouse_motion(drag_motion)
	screen._handle_left_release(woods_position)
	_assert_true(screen._orders.has("u1"), "Dragging a unit on a zoomed map should create an order")
	if screen._orders.has("u1"):
		var move_order := screen._orders["u1"] as Dictionary
		var move_path := move_order.get("path", []) as Array
		_assert_true(not move_path.is_empty() and move_path[move_path.size() - 1] == Vector2i(0, 2), "Zoomed drag should end at the visible destination hex")
	_cleanup_screen(screen)

	_reset_state()
	screen = _spawn_screen()
	screen._camera_offset = Vector2(-25.0, 52.0)
	screen._set_camera_zoom_at(Vector2(300.0, 250.0), 0.7)
	screen._selected_unit_id = "u1"
	screen._set_order_mode(screen.OrderMode.ATTACK)
	var enemy_position: Vector2 = screen._world_to_screen(screen._hex_center(0, 1))
	_right_click_gameplay_map(screen, enemy_position)
	_assert_true(screen._orders.has("u1"), "Right-clicking a zoomed enemy hex should create an attack order")
	if screen._orders.has("u1"):
		_assert_equal(OrderSystem.OrderType.ATTACK, int((screen._orders["u1"] as Dictionary).get("type", -1)), "Zoomed targeting should preserve attack-order semantics")
	_cleanup_screen(screen)

func _test_selection_exposes_order_actions() -> void:
	_reset_state()
	var screen := _spawn_screen()
	screen._selected_unit_id = "u1"
	screen._update_order_action_panel()
	_assert_true(screen.order_action_panel.visible, "Selecting a friendly unit should show Move/Attack/Dig In panel")
	_assert_equal("Move", screen.move_button.text, "Move button text should be visible")
	_assert_equal("Attack", screen.attack_button.text, "Attack button text should be visible")
	_assert_equal("Dig In", screen.dig_in_button.text, "Dig In button text should be visible")
	_cleanup_screen(screen)

func _test_mode_based_order_issuing() -> void:
	_reset_state()
	var screen := _spawn_screen()
	screen._selected_unit_id = "u1"
	screen._on_dig_in_mode_pressed()
	_assert_true(screen._orders.has("u1"), "Dig In mode should issue order for selected unit")
	_assert_equal(OrderSystem.OrderType.DIG_IN, int((screen._orders["u1"] as Dictionary).get("type", -1)), "Dig In mode should create DIG_IN order")
	_assert_true(String(screen.info_label.text).contains("Dig In order created"), "Dig In mode should show order feedback")
	_cleanup_screen(screen)

func _test_stack_cap_feedback() -> void:
	_reset_state()
	var screen := _spawn_screen()
	screen._selected_unit_id = "u1"
	var succeeded: bool = screen._issue_move_order("u1", Vector2i(1, 0))
	_assert_true(not succeeded, "Move order should be blocked when destination stack cap exceeded")
	_assert_true(String(screen.info_label.text).contains("Stack exceeds"), "Blocked stack move should explain stack-cap feedback")
	_cleanup_screen(screen)


func _test_attack_order_requires_adjacent_target() -> void:
	_reset_state()
	var screen := _spawn_screen()
	screen._selected_unit_id = "u1"
	var adjacent_succeeded: bool = screen._issue_attack_order("u1", Vector2i(0, 1))
	_assert_true(adjacent_succeeded, "Attack order should be allowed for an adjacent enemy target")
	_assert_true(screen._orders.has("u1"), "Adjacent attack should queue an order")
	var adjacent_order := screen._orders["u1"] as Dictionary
	_assert_equal(OrderSystem.OrderType.ATTACK, int(adjacent_order.get("type", -1)), "Adjacent attack should create ATTACK order")
	var adjacent_path := adjacent_order.get("path", []) as Array
	_assert_equal(1, adjacent_path.size(), "Adjacent attack should store only the attacker hex so it cannot look like a movement path")
	screen._active_order_arrow_count = 0
	screen._collect_order_arrow(adjacent_order, false)
	_assert_equal(1, screen._active_order_arrow_count, "Adjacent attack should collect a drawable attack arrow")
	var arrow := screen._order_arrow_pool[0] as Dictionary
	var arrow_path := arrow.get("path", []) as Array
	_assert_equal(2, arrow_path.size(), "Adjacent attack arrow should draw from attacker hex to target_unit_id hex")
	_assert_equal(Vector2i(0, 1), arrow_path[1], "Adjacent attack arrow should use the target unit hex as the endpoint")

	screen._orders.clear()
	GameState.debug_mode_enabled = true
	(screen._units["enemy"] as Dictionary)["hex"] = Vector2i(0, 2)
	var non_adjacent_succeeded: bool = screen._issue_attack_order("u1", Vector2i(0, 2))
	_assert_true(not non_adjacent_succeeded, "Attack order should be blocked for a non-adjacent enemy target")
	_assert_true(not screen._orders.has("u1"), "Blocked non-adjacent attack should not queue an order")
	_assert_true(String(screen.info_label.text).contains("adjacent enemy target"), "Blocked non-adjacent attack should explain adjacency requirement")
	_cleanup_screen(screen)


func _test_empty_execution_queue_advances_turn() -> void:
	_reset_state()
	var screen := _spawn_screen()
	screen._selected_unit_id = "u1"
	screen._on_dig_in_mode_pressed()
	screen._on_end_turn_pressed()
	_assert_true(screen._execution_queue.is_empty(), "Dig-in-only resolution should have no animation steps")
	_assert_equal(1, GameState.active_player, "Dig-in-only resolution should advance to the next player")
	_assert_equal(2, GameState.current_turn, "Dig-in-only resolution should increment the turn counter")
	_assert_equal(GameState.Phase.CASUALTY_ENTRY, GameState.current_phase, "Dig-in-only resolution should still show casualty entry")
	_cleanup_screen(screen)

func _test_left_click_move_tile_issues_move_order() -> void:
	_reset_state()
	var screen := _spawn_screen()
	screen._selected_unit_id = "u1"
	screen._set_order_mode(screen.OrderMode.MOVE)
	var target_hex := Vector2i(0, 2)
	var click_position: Vector2 = screen._world_to_screen(screen._hex_center(target_hex.x, target_hex.y))
	screen._handle_left_press(click_position)
	screen._handle_left_release(click_position)
	_assert_true(screen._orders.has("u1"), "Left-clicking a destination in Move mode should issue a move order for selected unit")
	var order := screen._orders["u1"] as Dictionary
	_assert_equal(OrderSystem.OrderType.MOVE, int(order.get("type", -1)), "Left-click move should create MOVE order")
	var path := order.get("path", []) as Array
	_assert_true(path.size() >= 2, "Left-click move order should include a traversable path")
	_cleanup_screen(screen)


func _test_order_changes_refresh_autosave_payload() -> void:
	_reset_state()
	(GameState.gameplay_units["u1"] as Dictionary)["role"] = "heavy_machine_gun"
	var screen := _spawn_screen()
	var succeeded: bool = screen._issue_move_order("u1", Vector2i(0, 2))
	_assert_true(succeeded, "Issuing a move order should succeed before checking autosave contents")
	_assert_true(GameState.gameplay_orders.has("u1"), "Issuing an order should immediately sync GameState gameplay orders")
	var saved := SaveManager.load_current_game()
	var saved_orders := saved.get("orders", {}) as Dictionary
	var saved_units := saved.get("units", {}) as Dictionary
	_assert_true(saved_orders.has("u1"), "Issuing an order should immediately refresh the autosave order payload")
	_assert_equal("heavy_machine_gun", String((saved_units.get("u1", {}) as Dictionary).get("role", "")), "Autosave should preserve the unit's specific role")
	var saved_move_order := saved_orders["u1"] as Dictionary
	_assert_equal(OrderSystem.OrderType.MOVE, int(saved_move_order.get("type", -1)), "Autosave should store the latest move order type")
	var saved_path := saved_move_order.get("path", []) as Array
	_assert_true(saved_path.size() >= 2, "Autosave should store serialized move path points")
	var saved_target := saved_path[saved_path.size() - 1] as Dictionary
	_assert_equal(0, int(saved_target.get("x", -1)), "Autosave should store the latest move target x")
	_assert_equal(2, int(saved_target.get("y", -1)), "Autosave should store the latest move target y")
	_assert_true(screen._delete_path_at(Vector2i(0, 2)), "Deleting a path point should remove the queued order")
	saved = SaveManager.load_current_game()
	saved_orders = saved.get("orders", {}) as Dictionary
	_assert_true(not saved_orders.has("u1"), "Deleting an order should immediately remove it from autosave")
	screen._issue_dig_in_order("u1")
	saved = SaveManager.load_current_game()
	saved_orders = saved.get("orders", {}) as Dictionary
	_assert_true(saved_orders.has("u1"), "Issuing a dig-in order should immediately refresh the autosave order payload")
	var saved_dig_order := saved_orders["u1"] as Dictionary
	_assert_equal(OrderSystem.OrderType.DIG_IN, int(saved_dig_order.get("type", -1)), "Autosave should store the latest dig-in order type")
	_cleanup_screen(screen)

func _test_loaded_orders_payload_restores_gameplay_orders() -> void:
	_reset_state()
	var main_menu: Control = MAIN_MENU_SCREEN_SCENE.instantiate()
	get_tree().root.add_child(main_menu)
	var payload := {
		"save_version": SaveManager.CURRENT_GAME_SAVE_VERSION,
		"turn_number": 3,
		"active_player": 0,
		"map": {"version": GameState.MAP_PAYLOAD_VERSION_CURRENT, "name": "orders-test", "grid": {"columns": 16, "rows": 16}, "terrain": {}, "territory": {}, "objectives": {}, "ai_doctrine": "balanced", "difficulty": "medium"},
		"players": [{
			"name": "P1",
			"division_tree": {
				"id": "orders_root",
				"display_name": "Orders Division",
				"type": "infantry",
				"role": "infantry",
				"size": "division",
				"status": "alive",
				"designation": {},
				"children": [{
					"id": "u1",
					"template_id": "usa_heavy_machine_gun_platoon",
					"display_name": "Machine Gun Platoon",
					"type": "infantry",
					"role": "heavy_machine_gun",
					"size": "platoon",
					"status": "alive",
					"designation": {},
					"children": []
				}]
			},
			"deployments": {}
		}, {"name": "P2", "controller": "ai", "division_tree": _canonical_unit_tree("orders_enemy_root", "Enemy Army", "army", "headquarters", "headquarters", []), "deployments": {}}],
		"units": {
			"u1": {"id": "u1", "display_name": "Machine Gun Platoon", "designation": {}, "owner": 0, "template_id": "usa_heavy_machine_gun_platoon", "type": "infantry", "role": "heavy_machine_gun", "hex": {"x": 0, "y": 0}, "size": "company", "status": "alive"},
			"enemy": {"id": "enemy", "display_name": "Enemy Company", "designation": {}, "owner": 1, "type": "infantry", "role": "infantry", "hex": {"x": 0, "y": 2}, "size": "company", "status": "alive"}
		},
		"orders": {
			"u1": {
				"unit_id": "u1",
				"type": OrderSystem.OrderType.ATTACK,
				"path": [{"x": 0, "y": 0}, {"x": 0, "y": 1}, {"x": 0, "y": 2}],
				"target_unit_id": "enemy"
			}
		},
		"casualties": {},
		"combat_log_entries": [{"timestamp": "test", "summary": "Saved combat history", "details": {}}],
		"ai_debug": {"enabled": false, "level": 1},
		"ai_formation_state": {},
		"scout_intel_by_observer": {}
	}
	main_menu._apply_loaded_payload(payload)
	var loaded_tree := (GameState.players[0] as Dictionary).get("division_tree", {}) as Dictionary
	var loaded_tree_unit := ((loaded_tree.get("children", []) as Array)[0] as Dictionary)
	_assert_equal("heavy_machine_gun", String(loaded_tree_unit.get("role", "")), "Canonical formation roles should load unchanged")
	_assert_equal("heavy_machine_gun", String((GameState.gameplay_units["u1"] as Dictionary).get("role", "")), "Canonical gameplay roles should load unchanged")
	_assert_true(GameState.gameplay_orders.has("u1"), "Loaded payload should store queued orders in GameState")
	_assert_equal("Saved combat history", String(GameState.combat_log_entries[0].get("summary", "")), "Loaded payload should restore combat history")
	var loaded_order := GameState.gameplay_orders["u1"] as Dictionary
	_assert_equal("u1", String(loaded_order.get("unit_id", "")), "Loaded order should preserve unit id")
	_assert_equal(OrderSystem.OrderType.ATTACK, int(loaded_order.get("type", -1)), "Loaded order should preserve order type")
	_assert_equal("enemy", String(loaded_order.get("target_unit_id", "")), "Loaded attack order should preserve target unit id")
	var loaded_path := loaded_order.get("path", []) as Array
	_assert_equal(3, loaded_path.size(), "Loaded order should preserve path length")
	_assert_equal(Vector2i(0, 1), loaded_path[1], "Loaded order should deserialize saved path points to Vector2i")
	var screen := _spawn_screen()
	_assert_equal("Saved combat history", String(screen._combat_log.entries[0].get("summary", "")), "Gameplay should initialize its combat log from restored state")
	_assert_true(_control_tree_text(screen.events_list).contains("Saved combat history"), "Gameplay should render restored combat history in the events list")
	_assert_true(screen._orders.has("u1"), "Gameplay screen should initialize queued orders from GameState")
	var screen_order := screen._orders["u1"] as Dictionary
	var screen_path := screen_order.get("path", []) as Array
	_assert_equal(Vector2i(0, 2), screen_path[2], "Gameplay screen should receive deserialized Vector2i path points")
	_cleanup_screen(screen)
	_cleanup_screen(main_menu)

func _test_starting_scenario_save_filter_and_direct_launch() -> void:
	const USA_SCENARIO_NAME := "CI starting scenario usa"
	const USA_SCENARIO_FILE := "CI_starting_scenario_usa"
	const GERMANY_SCENARIO_NAME := "CI starting scenario germany"
	const GERMANY_SCENARIO_FILE := "CI_starting_scenario_germany"
	SaveManager.delete_scenario(USA_SCENARIO_FILE)
	SaveManager.delete_scenario(GERMANY_SCENARIO_FILE)
	var usa_payload := _starting_scenario_payload("usa")
	var germany_payload := _starting_scenario_payload("germany")
	_assert_true(SaveManager.save_scenario(USA_SCENARIO_NAME, usa_payload), "Starting scenario should save under a reusable name")
	_assert_true(SaveManager.save_scenario(GERMANY_SCENARIO_NAME, germany_payload), "Second-side scenario should save for filtering coverage")
	_assert_true(SaveManager.scenario_exists(USA_SCENARIO_FILE), "Saved starting scenario should be discoverable")

	var stored := SaveManager.load_scenario(USA_SCENARIO_FILE)
	var stored_players := stored.get("players", []) as Array
	_assert_equal(2, stored_players.size(), "Starting scenario should preserve both selected force structures")
	if stored_players.size() == 2:
		_assert_true(not ((stored_players[0] as Dictionary).get("deployments", {}) as Dictionary).is_empty(), "Starting scenario should preserve Player 1 placements")
		_assert_true(not ((stored_players[1] as Dictionary).get("deployments", {}) as Dictionary).is_empty(), "Starting scenario should preserve Player 2 placements")

	var main_menu: Control = MAIN_MENU_SCREEN_SCENE.instantiate()
	get_tree().root.add_child(main_menu)
	main_menu._pending_nation_id = "usa"
	main_menu._configure_map_mode_selector()
	var scenario_mode_index := -1
	for option_index in range(main_menu.map_mode_selector.item_count):
		if int(main_menu.map_mode_selector.get_item_id(option_index)) == GameState.MapFlow.STARTING_SCENARIO:
			scenario_mode_index = option_index
			break
	_assert_true(scenario_mode_index >= 0, "Play flow should offer Load Starting Scenario")
	if scenario_mode_index >= 0:
		main_menu.map_mode_selector.select(scenario_mode_index)
		main_menu._on_map_mode_selected(scenario_mode_index)
	var listed_usa := false
	var listed_germany := false
	for item_index in range(main_menu.saved_map_selector.item_count):
		var metadata := main_menu.saved_map_selector.get_item_metadata(item_index) as Dictionary
		var scenario_file := String(metadata.get("scenario_id", ""))
		listed_usa = listed_usa or scenario_file == USA_SCENARIO_FILE
		listed_germany = listed_germany or scenario_file == GERMANY_SCENARIO_FILE
	_assert_true(listed_usa, "Scenario selector should show saves matching the chosen player side")
	_assert_true(not listed_germany, "Scenario selector should hide saves for the other player side")
	main_menu._pending_nation_id = "germany"
	main_menu._refresh_saved_scenario_selector()
	var same_nation_sides := {}
	for item_index in range(main_menu.saved_map_selector.item_count):
		var metadata := main_menu.saved_map_selector.get_item_metadata(item_index) as Dictionary
		if String(metadata.get("scenario_id", "")) == GERMANY_SCENARIO_FILE:
			same_nation_sides[int(metadata.get("human_side", -1))] = true
	_assert_equal(2, same_nation_sides.size(), "A same-nation scenario should list a distinct launch entry for each authored side")
	main_menu._pending_nation_id = "usa"

	GameState.gameplay_units = {"stale": {"id": "stale"}}
	GameState.gameplay_orders = {"stale": {"unit_id": "stale"}}
	GameState.combat_log_entries = [{"summary": "stale"}]
	GameState.pending_casualties = {"stale": true}
	_assert_true(main_menu._load_starting_scenario(USA_SCENARIO_FILE, 0), "Valid matching-side scenario should load")
	_assert_equal(GameState.Phase.GAMEPLAY, GameState.current_phase, "Loading a completed starting scenario should enter gameplay directly")
	_assert_equal(GameState.MapFlow.STARTING_SCENARIO, GameState.map_flow, "Loaded match should retain starting-scenario flow")
	_assert_equal(USA_SCENARIO_NAME, GameState.selected_scenario_name, "Loaded scenario should retain its display name for later overwrites")
	_assert_equal(Vector2i(16, 16), GameState.selected_map_dimensions, "Scenario should restore grid dimensions")
	_assert_equal("woods", String(GameState.terrain_map.get("0,0", "")), "Scenario should restore terrain")
	_assert_true(GameState.gameplay_units.is_empty(), "Scenario load should clear runtime gameplay units")
	_assert_true(GameState.gameplay_orders.is_empty(), "Scenario load should clear queued gameplay orders")
	_assert_true(GameState.combat_log_entries.is_empty(), "Scenario load should clear combat history")
	_assert_true(GameState.pending_casualties.is_empty(), "Scenario load should clear casualty workflow state")
	_assert_true(not (GameState.players[0].get("deployments", {}) as Dictionary).is_empty(), "Scenario load should restore Player 1 placement")
	_assert_true(not (GameState.players[1].get("deployments", {}) as Dictionary).is_empty(), "Scenario load should preserve the AI placement")
	_assert_equal("human", String(GameState.players[0].get("controller", "")), "Selected scenario side should be human controlled")
	_assert_equal("ai", String(GameState.players[1].get("controller", "")), "Scenario load should restore Player 2 as AI controlled")
	_cleanup_screen(main_menu)
	_assert_true(SaveManager.delete_scenario(USA_SCENARIO_FILE), "Scenario deletion should remove the selected named save")
	_assert_true(SaveManager.delete_scenario(GERMANY_SCENARIO_FILE), "Scenario deletion should clean up the other-side test save")
	_assert_true(not SaveManager.scenario_exists(USA_SCENARIO_FILE), "Deleted scenario should no longer exist")

func _starting_scenario_payload(nation_id: String) -> Dictionary:
	var opposing_nation := "germany" if nation_id == "usa" else "germany"
	return {
		"scenario_version": SaveManager.SCENARIO_VERSION_CURRENT,
		"version": GameState.MAP_PAYLOAD_VERSION_CURRENT,
		"name": "CI %s scenario" % nation_id,
		"grid": {"columns": 16, "rows": 16},
		"terrain": {"0,0": "woods"},
		"territory": {
			"0,0": GameState.TerritoryOwnership.PLAYER_1,
			"0,1": GameState.TerritoryOwnership.PLAYER_1,
			"1,0": GameState.TerritoryOwnership.PLAYER_2
		},
		"ai_doctrine": "balanced",
		"difficulty": "medium",
		"objectives": {},
		"players": [
			{
				"name": "P1",
				"nation_id": nation_id,
				"division_tree": _canonical_unit_tree("p1_root", "P1 Root", "army", "headquarters", "headquarters", [
					_canonical_unit_tree("scenario_p1", "Scenario Platoon", "platoon", "infantry", "infantry", [])
				]),
				"deployments": {"0,0": _canonical_unit_record("scenario_p1", "Scenario Platoon", "platoon", "infantry", "infantry")}
			},
			{
				"name": "P2",
				"nation_id": opposing_nation,
				"division_tree": _canonical_unit_tree("p2_root", "P2 Root", "army", "headquarters", "headquarters", [
					_canonical_unit_tree("scenario_p2", "Enemy Platoon", "platoon", "infantry", "infantry", [])
				]),
				"deployments": {"1,0": _canonical_unit_record("scenario_p2", "Enemy Platoon", "platoon", "infantry", "infantry")}
			}
		]
	}

func _find_tree_item_by_metadata(item: TreeItem, unit_id: String) -> TreeItem:
	if item == null:
		return null
	var metadata: Variant = item.get_metadata(0)
	if typeof(metadata) == TYPE_DICTIONARY and String((metadata as Dictionary).get("unit_id", "")) == unit_id:
		return item
	if (typeof(metadata) == TYPE_STRING or typeof(metadata) == TYPE_STRING_NAME) and str(metadata) == unit_id:
		return item
	for child_index in range(item.get_child_count()):
		var found := _find_tree_item_by_metadata(item.get_child(child_index), unit_id)
		if found != null:
			return found
	return null

func _test_gameplay_uses_unit_notation_for_deployed_generated_ids() -> void:
	_reset_state()
	GameState.gameplay_units = {}
	var player_one := GameState.players[0] as Dictionary
	var designation := {"division_number": 1, "regiment_number": 3, "battalion_number": 2, "company_letter": "A"}
	var deployed_company := _canonical_unit_tree("unit_101", "Generated Company", "company", "infantry", "infantry", [])
	deployed_company["designation"] = designation
	var battalion := _canonical_unit_tree("battalion_2", "2nd Battalion", "battalion", "infantry", "infantry", [deployed_company])
	battalion["designation"] = designation
	var regiment := _canonical_unit_tree("regiment_3", "3rd Regiment", "regiment", "infantry", "infantry", [battalion])
	regiment["designation"] = designation
	var division := _canonical_unit_tree("division_1", "1st Division", "division", "infantry", "infantry", [regiment])
	division["designation"] = designation
	player_one["division_tree"] = _canonical_unit_tree("army_root", "Army", "army", "headquarters", "headquarters", [division])
	player_one["deployments"] = {
		"0,0": {
			"id": "unit_101",
			"display_name": "Generated Company",
			"short_name": "GC",
			"type": "infantry",
			"size": "company",
			"role": "infantry",
			"status": "alive",
			"designation": {
				"company_letter": "A",
				"battalion_number": 2,
				"regiment_number": 3
			}
		}
	}
	GameState.players[0] = player_one
	var player_two := GameState.players[1] as Dictionary
	player_two["deployments"] = {}
	GameState.players[1] = player_two

	var screen := _spawn_screen()
	_assert_true(screen._units.has("unit_101"), "Gameplay should hydrate deployed generated-id units")
	if screen._units.has("unit_101"):
		var hydrated := screen._units["unit_101"] as Dictionary
		_assert_equal("A/2-3", screen._unit_display_name(hydrated, "unit_101"), "Generated ids with designation data should display as unit notation")
	_select_hex_for_panel(screen, Vector2i(0, 0))
	var panel_text := _selected_hex_card_text(screen)
	_assert_true(panel_text.contains("A/2-3 (Friendly)"), "Selected hex panel should show formatted friendly unit notation")
	_assert_true(not panel_text.contains("unit_101"), "Selected hex panel should not expose generated unit ids")
	screen._set_single_unit_selection("unit_101")
	screen._refresh_selected_hex_panel(Vector2i(0, 0))
	panel_text = _selected_hex_card_text(screen)
	_assert_true(panel_text.contains("Formation: 1st Division, 3rd Regiment, 2nd Battalion, A Company"), "Active unit details should spell out the full military hierarchy")
	_cleanup_screen(screen)

func _test_attack_order_starts_battle_resolution_payload() -> void:
	_reset_state()
	var screen := _spawn_screen()
	screen._orders = {
		"u1": OrderSystem.create_attack_order("u1", [Vector2i(0, 0)], "enemy")
	}
	screen._on_end_turn_pressed()
	_assert_equal(GameState.Phase.CASUALTY_ENTRY, GameState.current_phase, "Declared combat should open the dedicated battle-resolution phase")
	_assert_equal(1, int(GameState.pending_casualties.get("resolving_turn", -1)), "Battle resolution should retain the turn that declared combat")
	var battles := GameState.pending_casualties.get("battles", []) as Array
	_assert_equal(1, battles.size(), "One attacked defender hex should create one battle")
	if not battles.is_empty():
		var battle := battles[0] as Dictionary
		_assert_equal({"q": 0, "r": 1}, battle.get("hex", {}), "Battle payload should identify the defending hex")
		_assert_equal(["u1"], battle.get("attacker_unit_ids", []), "Battle payload should list its attacker")
		_assert_equal(["enemy"], battle.get("defender_unit_ids", []), "Battle payload should list its defender")
	_cleanup_screen(screen)

func _test_engagements_group_by_defender_hex_in_resolver_order() -> void:
	_reset_state()
	var screen := _spawn_screen()
	screen._units["d1"] = _canonical_gameplay_unit("d1", 1, Vector2i(4, 2), "company")
	screen._units["d1_support"] = _canonical_gameplay_unit("d1_support", 1, Vector2i(4, 2), "platoon")
	var battles: Array[Dictionary] = screen._group_engagements_by_defender_hex([
		{"attacker_unit_id": "a1", "defender_unit_id": "d1", "defender_owner": 1, "defender_hex": {"q": 4, "r": 2}},
		{"attacker_unit_id": "a2", "defender_unit_id": "d1", "defender_owner": 1, "defender_hex": {"q": 4, "r": 2}},
		{"attacker_unit_id": "a3", "defender_unit_id": "d2", "defender_owner": 1, "defender_hex": {"q": 1, "r": 7}},
		{"attacker_unit_id": "a1", "defender_unit_id": "d1", "defender_owner": 1, "defender_hex": {"q": 4, "r": 2}}
	])
	_assert_equal(2, battles.size(), "Different defending hexes should create separate battles")
	if battles.size() == 2:
		_assert_equal({"q": 4, "r": 2}, battles[0].get("hex", {}), "Battles should be ordered deterministically by row and column")
		_assert_equal(["a1", "a2"], battles[0].get("attacker_unit_ids", []), "Engagements on one defending hex should combine and deduplicate attackers")
		_assert_equal(["d1", "d1_support"], battles[0].get("defender_unit_ids", []), "A battle should include every defending formation stacked on its hex")
		_assert_equal({"q": 1, "r": 7}, battles[1].get("hex", {}), "The other defending hex should remain a separate battle")
		_assert_equal(["a3"], battles[1].get("attacker_unit_ids", []), "The second battle should contain only its own attackers")
	_cleanup_screen(screen)

func _test_territory_colors_remain_distinct_through_fog() -> void:
	var player_one := GameplayScreenScript.territory_fill_color(GameState.TerritoryOwnership.PLAYER_1, true)
	var player_two := GameplayScreenScript.territory_fill_color(GameState.TerritoryOwnership.PLAYER_2, true)
	var neutral := GameplayScreenScript.territory_fill_color(GameState.TerritoryOwnership.NEUTRAL, true)
	_assert_true(player_one != player_two and player_one != neutral and player_two != neutral, "Territory fills should distinguish both owners from neutral land")
	_assert_true(Vector4(player_one.r, player_one.g, player_one.b, player_one.a).distance_to(Vector4(0.24, 0.43, 0.92, 1.0)) > 0.2, "Player 1 territory should remain visually distinct from its unit marker")
	_assert_true(Vector4(player_two.r, player_two.g, player_two.b, player_two.a).distance_to(Vector4(0.89, 0.29, 0.27, 1.0)) > 0.2, "Player 2 territory should remain visually distinct from its unit marker")
	var fogged_one := GameplayScreenScript.territory_fill_color(GameState.TerritoryOwnership.PLAYER_1, false)
	var fogged_two := GameplayScreenScript.territory_fill_color(GameState.TerritoryOwnership.PLAYER_2, false)
	_assert_true(fogged_one.get_luminance() < player_one.get_luminance() and fogged_two.get_luminance() < player_two.get_luminance(), "Fog should darken ownership colors without hiding ownership")
	_assert_true(fogged_one != fogged_two, "Fogged territory should still reveal which player owns the tile")

func _test_partial_combine_split_and_verbal_hierarchy() -> void:
	var designation := {"regiment_number": 1, "battalion_number": 2, "company_letter": "C", "platoon_number": 1}
	var platoon_one := {"id": "p1", "display_name": "1/C/2-1", "size": "platoon", "designation": designation, "status": "alive", "children": []}
	var platoon_two := {"id": "p2", "display_name": "2/C/2-1", "size": "platoon", "designation": designation.merged({"platoon_number": 2}, true), "status": "alive", "children": []}
	var platoon_three := {"id": "p3", "display_name": "3/C/2-1", "size": "platoon", "designation": designation.merged({"platoon_number": 3}, true), "status": "alive", "children": []}
	var company := {"id": "company_c", "display_name": "C/2-1", "size": "company", "designation": designation, "status": "alive", "children": [platoon_one, platoon_two, platoon_three]}
	var battalion := {"id": "battalion_2", "display_name": "2-1", "size": "battalion", "designation": designation, "status": "alive", "children": [company]}
	var regiment := {"id": "regiment_1", "display_name": "1st Regiment", "size": "regiment", "designation": designation, "status": "alive", "children": [battalion]}
	var division := {"id": "division_1", "display_name": "1st Division", "size": "division", "designation": designation, "status": "alive", "children": [regiment]}
	var root := {"id": "root", "size": "army", "children": [division]}
	var units := {
		"p1": _canonical_gameplay_unit("p1", 0, Vector2i(2, 2), "platoon").merged({"concealment": 5}, true),
		"p2": _canonical_gameplay_unit("p2", 0, Vector2i(2, 2), "platoon").merged({"concealment": 4}, true),
		"p3": _canonical_gameplay_unit("p3", 0, Vector2i(3, 2), "platoon").merged({"concealment": 6}, true)
	}
	var combined := FormationOperations.combine(units, {"p1": {"unit_id": "p1"}}, root, ["p1", "p2"], 0)
	_assert_true(bool(combined.get("ok", false)), "Two same-parent platoons should combine as a partial company")
	var combined_units := combined.get("units", {}) as Dictionary
	_assert_true(combined_units.has("company_c") and combined_units.has("p3"), "A partial combine should preserve the unselected sibling")
	_assert_equal(2, ((combined_units["company_c"] as Dictionary).get("combined_components", []) as Array).size(), "Combined marker should retain exactly the selected components")
	_assert_true(not (combined.get("orders", {}) as Dictionary).has("p1"), "Combining should cancel affected orders")
	var split := FormationOperations.split(combined_units, combined.get("orders", {}) as Dictionary, root, "company_c", 0)
	_assert_true(bool(split.get("ok", false)), "A partial combined company should split successfully")
	_assert_true((split.get("units", {}) as Dictionary).has("p1") and (split.get("units", {}) as Dictionary).has("p2"), "Splitting should restore the stored components")
	var path_text := FormationHierarchy.verbal_path(root, "p1")
	_assert_equal("1st Division, 1st Regiment, 2nd Battalion, C Company, 1st Platoon", path_text, "Gameplay hierarchy should spell out the complete military chain")

func _test_atomic_split_validation_rejects_illegal_final_stack() -> void:
	_reset_state()
	var screen := _spawn_screen()
	var candidate_units := {}
	var created_ids: Array[String] = []
	for index in range(5):
		var unit_id := "split_%d" % index
		created_ids.append(unit_id)
		candidate_units[unit_id] = {"id": unit_id, "owner": 0, "hex": Vector2i(0, 0), "size": "company", "status": "alive"}
	var formation_result := {
		"assignments": {},
		"transaction": {"requires_atomic_validation": true, "created_component_ids": created_ids}
	}
	var validation: Dictionary = screen._validate_atomic_formation_transaction(formation_result, candidate_units, {})
	_assert_true(not bool(validation.get("ok", true)), "An atomic split should be rejected when its projected final state remains overstacked")
	_assert_true(String(validation.get("reason", "")).contains("illegal stack"), "Atomic split rejection should explain the stack failure")
	_cleanup_screen(screen)

func _test_formation_split_preserves_current_vehicle_state() -> void:
	var platoon_one := _canonical_unit_tree("tank_p1", "1st Tank Platoon", "platoon", "tank", "medium_tank", [])
	platoon_one["vehicles"] = [{"id": "p1_tank", "display_name": "P1 Tank", "status": "alive"}]
	var platoon_two := _canonical_unit_tree("tank_p2", "2nd Tank Platoon", "platoon", "tank", "medium_tank", [])
	platoon_two["vehicles"] = [{"id": "p2_tank", "display_name": "P2 Tank", "status": "alive"}]
	var company := _canonical_unit_tree("tank_company", "Tank Company", "company", "tank", "medium_tank", [platoon_one, platoon_two])
	var root := _canonical_unit_tree("tank_root", "Tank Root", "battalion", "tank", "medium_tank", [company])
	var source := {"hex": Vector2i(2, 2), "initiative": 50, "concealment": 5}
	var units := {
		"tank_p1": FormationOperations.gameplay_snapshot(platoon_one, source, 0),
		"tank_p2": FormationOperations.gameplay_snapshot(platoon_two, source, 0)
	}
	var combined := FormationOperations.combine(units, {}, root, ["tank_p1", "tank_p2"], 0)
	_assert_true(bool(combined.get("ok", false)), "Tank platoons should combine before vehicle-state preservation is tested")
	GameState.players[0]["division_tree"] = root
	GameState.gameplay_units = (combined.get("units", {}) as Dictionary).duplicate(true)
	_assert_true(GameState.mark_vehicle_status("tank_p1", "p1_tank", "dead", 0), "A casualty should update a component nested inside a combined marker")
	var split := FormationOperations.split(GameState.gameplay_units, {}, root, "tank_company", 0)
	_assert_true(bool(split.get("ok", false)), "A combined tank company should split after a component casualty")
	var restored := ((split.get("units", {}) as Dictionary).get("tank_p1", {}) as Dictionary)
	_assert_equal(1, (restored.get("vehicles", []) as Array).size(), "Splitting should preserve the platoon's vehicle roster")
	_assert_equal("dead", String(((restored.get("vehicles", []) as Array)[0] as Dictionary).get("status", "")), "Splitting should preserve the current vehicle casualty state")
	_assert_equal(0, int(restored.get("live_sub_units", -1)), "Splitting should preserve recalculated vehicle strength")

func _test_ai_turn_is_scheduled_once_after_resolution_closes() -> void:
	_reset_state()
	var screen := _spawn_screen()
	(GameState.players[1] as Dictionary)["controller"] = "ai"
	GameState.active_player = 1
	GameState.current_turn = 2
	screen._active_player = 1
	GameState.pending_casualties.clear()
	screen._pending_battle_payload.clear()
	screen._sync_after_battle_resolution()
	_assert_equal("2:1", screen._scheduled_ai_turn_key, "Closing battle resolution should schedule the newly active AI player")
	screen._sync_after_battle_resolution()
	_assert_equal("2:1", screen._scheduled_ai_turn_key, "Repeated overlay-close notifications should not queue a duplicate AI turn")
	screen._scheduled_ai_turn_key = ""
	_cleanup_screen(screen)

func _test_selected_hex_panel_is_docked_in_right_sidebar() -> void:
	_reset_state()
	var screen := _spawn_screen()
	var sidebar := screen.get_node_or_null("%RightSidebar") as PanelContainer
	var selected_panel := screen.get_node_or_null("%SelectedHexPanel") as PanelContainer
	var selected_unit_panel := screen.get_node_or_null("%SelectedUnitPanel") as PanelContainer
	var events_panel := screen.get_node_or_null("%EventsPanel") as PanelContainer
	_assert_true(sidebar != null, "Gameplay screen should expose a right sidebar container")
	_assert_true(selected_panel != null, "Gameplay screen should expose the selected hex panel")
	_assert_true(selected_unit_panel != null, "Gameplay screen should expose the active-unit inspector")
	_assert_true(events_panel != null, "Gameplay screen should expose the events accordion")
	if sidebar != null and selected_panel != null:
		_assert_true(sidebar.is_ancestor_of(selected_panel), "Selected hex panel should be docked inside the right sidebar")
		_assert_true(sidebar.is_ancestor_of(selected_unit_panel), "Active-unit inspector should be docked at the top of the right sidebar")
		_assert_true(sidebar.is_ancestor_of(events_panel), "Events accordion should be docked inside the right sidebar")
		_assert_true(not sidebar.is_ancestor_of(screen.order_action_panel), "Move/Attack/Dig In/Combine/Split controls should remain in their upper-left panel")
		_assert_equal(1.0, sidebar.anchor_left, "Right sidebar left anchor should dock to the right edge")
		_assert_equal(1.0, sidebar.anchor_right, "Right sidebar right anchor should dock to the right edge")
		_assert_true(sidebar.offset_left < sidebar.offset_right, "Right sidebar should have positive width from right-edge offsets")
	_cleanup_screen(screen)

func _test_selected_unit_inspector_shows_recursive_subordinate_status() -> void:
	_reset_state()
	var nested_squad := _canonical_unit_tree("u1_s1", "1st Squad", "squad", "infantry", "infantry", [])
	nested_squad["status"] = "dead"
	var first_platoon := _canonical_unit_tree("u1_p1", "1st Platoon", "platoon", "infantry", "infantry", [nested_squad])
	first_platoon["vehicles"] = [
		{"id": "carrier_1", "status": "alive"},
		{"id": "carrier_2", "status": "dead"}
	]
	var second_platoon := _canonical_unit_tree("u1_p2", "2nd Platoon", "platoon", "infantry", "weapons", [])
	second_platoon["status"] = "dead"
	var company := _canonical_unit_tree("u1", "Able Company", "company", "infantry", "infantry", [first_platoon, second_platoon])
	var root := _canonical_unit_tree("p1_root", "P1 Army", "army", "headquarters", "headquarters", [company])
	(GameState.players[0] as Dictionary)["division_tree"] = root
	(GameState.gameplay_units["u1"] as Dictionary)["display_name"] = "Able Company"
	var screen := _spawn_screen()
	screen._orders["u1"] = OrderSystem.create_dig_in_order("u1")
	screen._selected_hex = Vector2i(0, 0)
	screen._set_single_unit_selection("u1")
	screen._refresh_selected_hex_panel(screen._selected_hex)

	_assert_true(String(screen.selected_unit_title_label.text).contains("Able Company"), "Inspector should identify the active unit")
	_assert_true(String(screen.selected_unit_summary_label.text).contains("1/3 subordinate formations"), "Inspector should recursively aggregate living subordinate formations")
	_assert_true(String(screen.selected_unit_summary_label.text).contains("1/2 vehicles"), "Inspector should recursively aggregate vehicle casualties")
	_assert_equal("Order: Dig In", String(screen.selected_unit_order_label.text), "Inspector should show the active unit's current order")
	_assert_true(String(screen.selected_unit_formation_label.text).contains("Able Company"), "Inspector should show the active unit's formation path")
	_assert_equal(2, screen.subordinate_list.get_child_count(), "Inspector should show immediate subordinate rows rather than flattening the hierarchy")
	_assert_true(_control_tree_text(screen.subordinate_list).contains("2nd Platoon"), "Immediate subordinate rows should include names and status")
	_assert_true(_control_tree_text(screen.subordinate_list).contains("Status: Dead"), "Subordinate rows should expose casualty status")

	screen.subordinates_toggle_button.emit_signal("pressed")
	_assert_true(not screen.subordinate_scroll.visible, "Subordinate rows should collapse from their header")
	screen._refresh_selected_hex_panel(screen._selected_hex)
	_assert_true(not screen.subordinate_scroll.visible, "Subordinate expansion should persist across inspector refreshes")
	_cleanup_screen(screen)

func _test_selected_unit_inspector_uses_combined_components() -> void:
	_reset_state()
	var combined := GameState.gameplay_units["u1"] as Dictionary
	combined["display_name"] = "Combined Able Company"
	combined["is_combined_formation"] = true
	combined["combined_components"] = [
		_canonical_unit_tree("combined_p1", "1st Platoon", "platoon", "infantry", "infantry", []),
		_canonical_unit_tree("combined_p2", "Weapons Platoon", "platoon", "infantry", "weapons", [])
	]
	(combined["combined_components"] as Array)[1]["status"] = "dead"
	GameState.gameplay_units["u1"] = combined
	var screen := _spawn_screen()
	screen._selected_hex = Vector2i(0, 0)
	screen._set_single_unit_selection("u1")
	screen._refresh_selected_hex_panel(screen._selected_hex)

	_assert_equal(2, screen.subordinate_list.get_child_count(), "Combined markers should inspect their preserved components")
	_assert_true(_control_tree_text(screen.subordinate_list).contains("Weapons Platoon"), "Combined component names should appear in subordinate rows")
	_assert_true(String(screen.subordinates_toggle_button.text).contains("1/2 operational"), "Combined component status should drive the subordinate aggregate")
	_cleanup_screen(screen)

func _test_events_accordion_formats_and_preserves_expansion() -> void:
	_reset_state()
	(GameState.gameplay_units["u1"] as Dictionary)["display_name"] = "Able Company"
	GameState.combat_log_entries = [
		{"timestamp": "08:00", "summary": "u1 moved.", "details": {}},
		{
			"timestamp": "08:05",
			"summary": "u1 dug in at 2,3.",
			"details": {"unit_id": "u1", "hex": {"q": 2, "r": 3}, "was_dug_in": false, "is_dug_in": true}
		}
	]
	var screen := _spawn_screen()
	_assert_equal("Events (2) ▸", String(screen.events_toggle_button.text), "Events should show their count and start collapsed")
	_assert_true(not screen.events_scroll.visible, "Events should be collapsed by default")

	screen.events_toggle_button.emit_signal("pressed")
	_assert_true(screen.events_scroll.visible, "Events header should expand the chronological event list")
	_assert_equal(2, screen.events_list.get_child_count(), "Every combat log entry should have an event row")
	var second_row := screen.events_list.get_child(1) as VBoxContainer
	var second_header := second_row.get_child(0) as Button
	_assert_true(String(second_header.text).contains("Able Company"), "Event summaries should replace internal unit IDs with display names")
	second_header.emit_signal("pressed")
	var detail_label := second_row.get_child(1) as Label
	_assert_true(detail_label.visible, "Individual event details should expand independently")
	_assert_true(String(detail_label.text).contains("Unit: Able Company"), "Event details should format unit IDs as display names")
	_assert_true(String(detail_label.text).contains("Hex: 2,3"), "Event details should format hex dictionaries as coordinates")
	_assert_true(String(detail_label.text).contains("Previously Dug In: No"), "Event details should format booleans readably")
	_assert_true(not String(detail_label.text).contains("{"), "Event details should not expose raw dictionary serialization")

	screen._refresh_log()
	second_row = screen.events_list.get_child(1) as VBoxContainer
	detail_label = second_row.get_child(1) as Label
	_assert_true(screen.events_scroll.visible and detail_label.visible, "Event and row expansion should persist across log refreshes")
	_cleanup_screen(screen)

func _test_selected_hex_panel_empty_hex() -> void:
	_reset_state()
	var screen := _spawn_screen()
	_select_hex_for_panel(screen, Vector2i(0, 2))
	_assert_true(String(screen.selected_hex_title_label.text).contains("0,2"), "Selected hex panel should show selected coordinates")
	_assert_true(String(screen.selected_hex_ownership_label.text).contains("Neutral"), "Empty neutral hex should show neutral ownership")
	_assert_true(String(screen.selected_hex_terrain_label.text).contains("Woods"), "Selected hex panel should show terrain")
	_assert_equal("Unit Count: 0", String(screen.selected_hex_count_label.text), "Empty hex should show zero units")
	_assert_equal("No units detected.", _selected_hex_card_text(screen), "Empty hex should show no detected units")
	_cleanup_screen(screen)

func _test_selected_hex_panel_friendly_unit_details() -> void:
	_reset_state()
	var screen := _spawn_screen()
	var unit := screen._units["u1"] as Dictionary
	unit["live_sub_units"] = 2
	unit["max_sub_units"] = 3
	unit["dug_in"] = true
	screen._units["u1"] = unit
	_select_hex_for_panel(screen, Vector2i(0, 0))
	var panel_text := _selected_hex_card_text(screen)
	_assert_equal("Unit Count: 1", String(screen.selected_hex_count_label.text), "Friendly occupied hex should show exact friendly count")
	_assert_true(panel_text.contains("u1 (Friendly)"), "Friendly panel should show exact friendly unit id")
	_assert_true(panel_text.contains("Health: 2/3 sub-units"), "Friendly panel should show existing health/sub-unit data")
	_assert_true(panel_text.contains("Dug In"), "Friendly panel should show dug-in status")
	_cleanup_screen(screen)

func _test_selected_hex_unit_cards_are_clickable_and_show_orders() -> void:
	_reset_state()
	var screen := _spawn_screen()
	var stacked_unit := screen._units["a"] as Dictionary
	stacked_unit["hex"] = Vector2i(0, 0)
	stacked_unit["type"] = "infantry"
	stacked_unit["role"] = "heavy_machine_gun"
	stacked_unit["display_name"] = "Heavy Weapons Company"
	screen._units["a"] = stacked_unit
	screen._orders["a"] = OrderSystem.create_dig_in_order("a")
	_select_hex_for_panel(screen, Vector2i(0, 0))

	var unit_cards := _selected_hex_unit_card_buttons(screen)
	_assert_equal(2, unit_cards.size(), "A stacked friendly hex should show one clickable card per living unit")
	var stacked_card := _find_unit_card(screen, "a")
	_assert_true(stacked_card != null, "Expected a card for the stacked friendly unit")
	if stacked_card != null:
		_assert_true(not stacked_card.disabled, "A living friendly unit card should be actionable")
		_assert_true(String(stacked_card.text).contains("Heavy Weapons Company"), "Unit card should show the unit name")
		_assert_true(String(stacked_card.text).contains("Heavy Machine Gun"), "Unit card should show the specific unit role instead of only the broad combat class")
		_assert_true(String(stacked_card.text).contains("Company"), "Unit card should show the unit size")
		_assert_true(String(stacked_card.text).contains("Health:"), "Unit card should show health")
		_assert_true(String(stacked_card.text).contains("Status:"), "Unit card should show current status")
		_assert_true(String(stacked_card.text).contains("Order: Dig In"), "Unit card should show its current order")
		stacked_card.emit_signal("pressed")

	_assert_equal("a", screen._selected_unit_id, "Clicking a living friendly card should make it the active unit")
	_assert_true(screen.order_action_panel.visible, "Selecting a friendly card should expose order controls")
	var refreshed_card := _find_unit_card(screen, "a")
	_assert_true(refreshed_card != null and bool(refreshed_card.get_meta("is_selected", false)), "The selected unit card should be highlighted")
	_assert_true(refreshed_card != null and bool(refreshed_card.get_meta("is_primary", false)), "The active unit card should be marked as primary")
	_assert_true(refreshed_card != null and String(refreshed_card.text).begins_with("ACTIVE UNIT"), "The active card should have a clear text indicator in addition to its highlight")
	_cleanup_screen(screen)

func _test_selected_hex_unit_cards_clear_selection_on_hex_change() -> void:
	_reset_state()
	var screen := _spawn_screen()
	_select_hex_for_panel(screen, Vector2i(0, 0))
	var friendly_card := _find_unit_card(screen, "u1")
	if friendly_card != null:
		friendly_card.emit_signal("pressed")
	_assert_equal("u1", screen._selected_unit_id, "Friendly card selection should be established before changing hexes")

	var empty_hex_position: Vector2 = screen._world_to_screen(screen._hex_center(0, 2))
	screen._handle_left_press(empty_hex_position)
	screen._handle_left_release(empty_hex_position)
	_assert_equal("", screen._selected_unit_id, "Selecting a different hex should clear the previous hex's unit selection")
	_assert_true(not screen.order_action_panel.visible, "Changing hexes should hide order controls when no new unit is selected")
	_assert_equal("No units detected.", _selected_hex_card_text(screen), "Changing hexes should rebuild cards for the new empty hex")
	_cleanup_screen(screen)

func _test_shift_click_toggles_same_hex_selection_and_primary() -> void:
	_reset_state()
	var screen := _spawn_screen()
	for unit_id in ["a", "b"]:
		var unit := screen._units[unit_id] as Dictionary
		unit["hex"] = Vector2i(0, 0)
		screen._units[unit_id] = unit
	_select_hex_for_panel(screen, Vector2i(0, 0))

	screen._on_unit_card_pressed("u1")
	screen._on_unit_card_pressed("a", true)
	screen._on_unit_card_pressed("b", true)
	_assert_equal(["u1", "a", "b"], screen._selected_unit_ids, "Shift-click should add same-hex living friendly units without clearing earlier selections")
	_assert_equal("b", screen._selected_unit_id, "The most recently Shift-clicked selected unit should become primary")
	for unit_id in ["u1", "a", "b"]:
		var card := _find_unit_card(screen, unit_id)
		_assert_true(card != null and bool(card.get_meta("is_selected", false)), "Every selected unit should retain a highlighted card")
	var primary_card := _find_unit_card(screen, "b")
	_assert_true(primary_card != null and bool(primary_card.get_meta("is_primary", false)), "The newest selected unit should have the primary card highlight")

	screen._on_unit_card_pressed("b", true)
	_assert_equal(["u1", "a"], screen._selected_unit_ids, "Shift-clicking a selected unit should remove it from the group")
	_assert_equal("a", screen._selected_unit_id, "Removing the primary unit should promote the most recently added remaining unit")
	screen._on_unit_card_pressed("b")
	_assert_equal(["b"], screen._selected_unit_ids, "A normal card click should replace the group with only that unit")
	_assert_equal("b", screen._selected_unit_id, "A normal card click should make its sole selection primary")

	screen._on_unit_card_pressed("enemy", true)
	_assert_equal(["b"], screen._selected_unit_ids, "An enemy outside the selected friendly hex should never enter the actionable group")
	_select_hex_for_panel(screen, Vector2i(0, 2))
	_assert_true(screen._selected_unit_ids.is_empty(), "Changing hexes should clear the complete multi-selection group")
	_assert_equal("", screen._selected_unit_id, "Changing hexes should clear the primary unit")
	_cleanup_screen(screen)

func _test_double_click_selects_living_friendly_stack() -> void:
	_reset_state()
	var screen := _spawn_screen()
	screen._units.clear()
	screen._units["friendly_a"] = _canonical_gameplay_unit("friendly_a", 0, Vector2i(0, 0), "company")
	screen._units["friendly_b"] = _canonical_gameplay_unit("friendly_b", 0, Vector2i(0, 0), "platoon")
	var dead_friendly := _canonical_gameplay_unit("dead_friendly", 0, Vector2i(0, 0), "platoon")
	dead_friendly["status"] = "dead"
	screen._units["dead_friendly"] = dead_friendly
	screen._units["enemy_here"] = _canonical_gameplay_unit("enemy_here", 1, Vector2i(0, 0), "company")
	var position: Vector2 = screen._world_to_screen(screen._hex_center(0, 0))
	var press_event := InputEventMouseButton.new()
	press_event.button_index = MOUSE_BUTTON_LEFT
	press_event.pressed = true
	press_event.double_click = true
	press_event.position = position
	screen._gui_input(press_event)
	var release_event := InputEventMouseButton.new()
	release_event.button_index = MOUSE_BUTTON_LEFT
	release_event.pressed = false
	release_event.position = position
	screen._gui_input(release_event)
	_assert_equal(["friendly_a", "friendly_b"], screen._selected_unit_ids, "Gameplay double-click should select every living friendly counter and exclude dead or enemy units.")
	_assert_equal("friendly_a", screen._selected_unit_id, "The frontmost friendly counter should remain the active inspector unit.")
	_assert_true(String(screen.info_label.text).contains("Selected 2 units"), "Gameplay should report the complete double-click group selection.")
	_cleanup_screen(screen)

func _test_group_move_is_atomic_and_autosaves_only_complete_groups() -> void:
	_reset_state()
	var screen := _spawn_screen()
	screen._units.clear()
	var group_ids: Array[String] = []
	for index in range(5):
		var unit_id := "move_%d" % index
		group_ids.append(unit_id)
		screen._units[unit_id] = _canonical_gameplay_unit(unit_id, 0, Vector2i(0, 0), "company")
	screen._selected_hex = Vector2i(0, 0)
	screen._selected_unit_ids = group_ids.duplicate()
	screen._selected_unit_id = group_ids[group_ids.size() - 1]
	var result: Dictionary = screen._issue_group_move_orders(group_ids, Vector2i(2, 0))

	var successful_ids := result.get("successful_unit_ids", []) as Array
	var skipped := result.get("skipped", []) as Array
	_assert_equal(0, successful_ids.size(), "A projected stack-limit failure should reject every move in the selected group")
	_assert_equal(5, skipped.size(), "Atomic group rejection should account for every selected company")
	_assert_equal(0, screen._orders.size(), "An illegal atomic group move must not queue partial orders")
	_assert_true(String(screen.info_label.text).contains("group cancelled"), "Group move feedback should report atomic cancellation")
	_assert_true(String(screen.info_label.text).contains("Stack exceeds"), "Group move feedback should include the readable stack-limit reason")

	var saved := SaveManager.load_current_game()
	var saved_orders := saved.get("orders", {}) as Dictionary
	_assert_equal(0, saved_orders.size(), "An atomic group rejection must not autosave partial movement orders")
	_cleanup_screen(screen)

	_reset_state()
	screen = _spawn_screen()
	screen._units.clear()
	group_ids.clear()
	for index in range(4):
		var unit_id := "legal_move_%d" % index
		group_ids.append(unit_id)
		screen._units[unit_id] = _canonical_gameplay_unit(unit_id, 0, Vector2i(0, 0), "company")
	screen._selected_hex = Vector2i(0, 0)
	screen._selected_unit_ids = group_ids.duplicate()
	screen._selected_unit_id = group_ids[0]
	result = screen._issue_group_move_orders(group_ids, Vector2i(2, 0))
	_assert_equal(4, (result.get("successful_unit_ids", []) as Array).size(), "A fully legal group should receive every requested movement order")
	_assert_equal(4, screen._orders.size(), "A legal atomic group move should queue the complete order set")
	for unit_id in group_ids:
		var order := screen._orders[unit_id] as Dictionary
		var path := order.get("path", []) as Array
		_assert_true(not path.is_empty() and path[path.size() - 1] == Vector2i(2, 0), "Every legal group order should use the shared destination")
	saved = SaveManager.load_current_game()
	saved_orders = saved.get("orders", {}) as Dictionary
	_assert_equal(4, saved_orders.size(), "A legal group move should autosave every movement order together")
	_cleanup_screen(screen)

func _test_group_attack_orders_every_selected_unit() -> void:
	_reset_state()
	var screen := _spawn_screen()
	var second_attacker := screen._units["a"] as Dictionary
	second_attacker["hex"] = Vector2i(0, 0)
	screen._units["a"] = second_attacker
	screen._selected_hex = Vector2i(0, 0)
	screen._set_single_unit_selection("u1")
	screen._toggle_unit_selection("a")
	var result: Dictionary = screen._issue_group_attack_orders(screen._selected_unit_ids, Vector2i(0, 1))

	_assert_equal(2, (result.get("successful_unit_ids", []) as Array).size(), "Every eligible selected attacker should receive the group attack order")
	_assert_equal(0, (result.get("skipped", []) as Array).size(), "Adjacent same-hex attackers should not be skipped")
	for unit_id in ["u1", "a"]:
		_assert_true(screen._orders.has(unit_id), "Group attack should queue an order for %s" % unit_id)
		if screen._orders.has(unit_id):
			var order := screen._orders[unit_id] as Dictionary
			_assert_equal(OrderSystem.OrderType.ATTACK, int(order.get("type", -1)), "Group attack should preserve ATTACK order type for %s" % unit_id)
			_assert_equal("enemy", String(order.get("target_unit_id", "")), "Every group attacker should share the same enemy target")
	_assert_true(String(screen.info_label.text).contains("2 succeeded, 0 skipped"), "Group attack feedback should report a complete success")
	_cleanup_screen(screen)

func _test_group_dig_in_keeps_successes_and_reports_dead_unit() -> void:
	_reset_state()
	var screen := _spawn_screen()
	var second_unit := screen._units["a"] as Dictionary
	second_unit["hex"] = Vector2i(0, 0)
	screen._units["a"] = second_unit
	screen._selected_hex = Vector2i(0, 0)
	screen._set_single_unit_selection("u1")
	screen._toggle_unit_selection("a")
	second_unit["status"] = "dead"
	screen._units["a"] = second_unit
	var result: Dictionary = screen._issue_group_dig_in_orders(screen._selected_unit_ids)

	_assert_equal(["u1"], result.get("successful_unit_ids", []), "Group dig-in should keep the eligible living unit's order")
	_assert_equal(1, (result.get("skipped", []) as Array).size(), "Group dig-in should skip a unit that died after selection")
	_assert_true(screen._orders.has("u1"), "The living selected unit should receive a dig-in order")
	_assert_true(not screen._orders.has("a"), "The dead selected unit should not receive a dig-in order")
	_assert_true(String(screen.info_label.text).contains("1 succeeded, 1 skipped"), "Partial group dig-in feedback should report both outcomes")
	_assert_true(String(screen.info_label.text).contains("dead"), "Partial group dig-in feedback should explain why the unit was skipped")
	var saved := SaveManager.load_current_game()
	_assert_true((saved.get("orders", {}) as Dictionary).has("u1"), "Autosave should preserve the successful dig-in order from a partial group action")
	_assert_true(not (saved.get("orders", {}) as Dictionary).has("a"), "Autosave should omit the rejected dead-unit order")
	_cleanup_screen(screen)

func _test_selected_hex_panel_hides_unscouted_enemy_details() -> void:
	_reset_state()
	var screen := _spawn_screen()
	_select_hex_for_panel(screen, Vector2i(0, 1))
	var panel_text := _selected_hex_card_text(screen)
	_assert_true(String(screen.selected_hex_ownership_label.text).contains("Enemy Territory"), "Enemy-owned hex should be labelled from active player's perspective")
	_assert_equal("Unit Count: 0", String(screen.selected_hex_count_label.text), "Unscouted enemy units should not be counted exactly")
	_assert_true(panel_text.contains("no current recon contact"), "Unscouted enemy hex should explain that no recon contact exists")
	_assert_true(not panel_text.contains("enemy ("), "Unscouted enemy hex should not reveal exact enemy unit id/details")
	_cleanup_screen(screen)

func _test_selected_hex_panel_uses_recon_for_enemy_contacts() -> void:
	_reset_state()
	(GameState.gameplay_units["enemy"] as Dictionary)["role"] = "heavy_machine_gun"
	GameState.scout_intel_by_observer = {
		"0": {
			"0,1": {
				"hexId": "0,1",
				"scoutLevel": 3,
				"knownEnemyUnits": [{
					"unitId": "enemy",
					"presenceKnown": true,
					"reportedType": "infantry",
					"typeKnown": true,
					"reportedSize": "company",
					"sizeKnown": true
				}]
			}
		}
	}
	var screen := _spawn_screen()
	_select_hex_for_panel(screen, Vector2i(0, 1))
	var panel_text := _selected_hex_card_text(screen)
	_assert_true(String(screen.selected_hex_count_label.text).contains("1 enemy contact"), "Recon-known enemy hex should show reported contact count")
	_assert_true(panel_text.contains("enemy | Type: Infantry | Size: Company | Scout Level: 3"), "Recon-known enemy hex should show reported type/size and scout level")
	_assert_true(not panel_text.contains("Heavy Machine Gun"), "Recon contacts should not leak the enemy's specific role before it is fully revealed")
	_assert_true(not panel_text.contains("Health:"), "Recon-limited enemy line should not reveal full health details")
	var contact_cards := _selected_hex_unit_card_buttons(screen)
	_assert_equal(1, contact_cards.size(), "A recon-known enemy should render as one contact card")
	_assert_true(contact_cards[0].disabled, "Recon contact cards should be read-only")
	_assert_true(not bool(contact_cards[0].get_meta("actionable", true)), "Recon contact cards should never be actionable selections")
	_cleanup_screen(screen)

func _test_selected_hex_panel_debug_shows_full_enemy_details() -> void:
	_reset_state()
	(GameState.gameplay_units["enemy"] as Dictionary)["role"] = "heavy_machine_gun"
	GameState.debug_mode_enabled = true
	var screen := _spawn_screen()
	_select_hex_for_panel(screen, Vector2i(0, 1))
	var panel_text := _selected_hex_card_text(screen)
	_assert_equal("Unit Count: 1 (0 friendly, 1 enemy)", String(screen.selected_hex_count_label.text), "Debug selected hex panel should show exact enemy count")
	_assert_true(panel_text.contains("enemy (Enemy)"), "Debug selected hex panel should show exact enemy unit id")
	_assert_true(panel_text.contains("Heavy Machine Gun"), "Fully revealed enemy details should show the unit's specific role")
	_assert_true(panel_text.contains("Health: Alive"), "Debug selected hex panel should show enemy health")
	var enemy_card := _find_unit_card(screen, "enemy")
	_assert_true(enemy_card != null and enemy_card.disabled, "Even fully revealed debug enemy cards should remain read-only")
	if enemy_card != null:
		enemy_card.emit_signal("pressed")
	_assert_equal("", screen._selected_unit_id, "Enemy cards should not become active when clicked")
	GameState.debug_mode_enabled = false
	_cleanup_screen(screen)

func _test_selected_hex_panel_refreshes_after_dig_in_resolution() -> void:
	_reset_state()
	GameState.debug_mode_enabled = true
	var screen := _spawn_screen()
	_select_hex_for_panel(screen, Vector2i(0, 0))
	screen._selected_unit_id = "u1"
	screen._on_dig_in_mode_pressed()
	screen._on_end_turn_pressed()
	var panel_text := _selected_hex_card_text(screen)
	_assert_true(panel_text.contains("Dug In"), "Selected hex panel should refresh after turn resolution to show dug-in status")
	GameState.debug_mode_enabled = false
	_cleanup_screen(screen)

func _reset_state() -> void:
	GameState.reset()
	GameState.set_phase(GameState.Phase.GAMEPLAY)
	GameState.active_player = 0 # GameplayScreen reads GameState.active_player in _ready(); keep deterministic active side for tests.
	GameState.players = [
		{"name":"P1","division_tree":_canonical_unit_tree("p1_root", "P1 Army", "army", "headquarters", "headquarters", []),"deployments":{},"controller":"human"},
		{"name":"P2","division_tree":_canonical_unit_tree("p2_root", "P2 Army", "army", "headquarters", "headquarters", []),"deployments":{},"controller":"human"}
	]
	GameState.gameplay_units = {
		"u1": _canonical_gameplay_unit("u1", 0, Vector2i(0, 0), "company"),
		"a": _canonical_gameplay_unit("a", 0, Vector2i(1, 0), "company"),
		"b": _canonical_gameplay_unit("b", 0, Vector2i(1, 0), "company"),
		"c": _canonical_gameplay_unit("c", 0, Vector2i(1, 0), "company"),
		"d": _canonical_gameplay_unit("d", 0, Vector2i(1, 0), "company"),
		"enemy": _canonical_gameplay_unit("enemy", 1, Vector2i(0, 1), "company")
	}
	GameState.terrain_map = {
		"0,2": "woods"
	}
	GameState.territory_map = {
		"0,0": GameState.TerritoryOwnership.PLAYER_1,
		"0,1": GameState.TerritoryOwnership.PLAYER_2,
		"0,2": GameState.TerritoryOwnership.NEUTRAL,
		"1,0": GameState.TerritoryOwnership.PLAYER_1
	}

func _canonical_unit_record(id: String, display_name: String, size: String, type: String, role: String) -> Dictionary:
	return {
		"id": id,
		"display_name": display_name,
		"designation": {},
		"type": type,
		"role": role,
		"size": size,
		"status": "alive"
	}

func _canonical_unit_tree(id: String, display_name: String, size: String, type: String, role: String, children: Array) -> Dictionary:
	return _canonical_unit_record(id, display_name, size, type, role).merged({"children": children, "vehicles": []}, true)

func _canonical_gameplay_unit(id: String, owner: int, hex: Vector2i, size: String) -> Dictionary:
	return _canonical_unit_record(id, id, size, "infantry", "infantry").merged({"owner": owner, "hex": hex}, true)

func _spawn_screen() -> Control:
	var screen: Control = GAMEPLAY_SCREEN_SCENE.instantiate()
	get_tree().root.add_child(screen)
	return screen

func _select_hex_for_panel(screen: Control, hex: Vector2i) -> void:
	if hex != screen._selected_hex:
		screen._clear_unit_selection()
	screen._selected_hex = hex
	screen._refresh_selected_hex_panel(hex)

func _selected_hex_card_text(screen: Control) -> String:
	var lines: Array[String] = []
	for child in screen.selected_hex_unit_cards.get_children():
		if child is Button:
			lines.append(String((child as Button).text))
		elif child is Label:
			lines.append(String((child as Label).text))
	return "\n".join(lines)

func _selected_hex_unit_card_buttons(screen: Control) -> Array[Button]:
	var cards: Array[Button] = []
	for child in screen.selected_hex_unit_cards.get_children():
		if child is Button:
			cards.append(child as Button)
	return cards

func _find_unit_card(screen: Control, unit_id: String) -> Button:
	for card in _selected_hex_unit_card_buttons(screen):
		if String(card.get_meta("unit_id", "")) == unit_id:
			return card
	return null

func _control_tree_text(root: Control) -> String:
	var lines: Array[String] = []
	for child in root.get_children():
		if child is Label:
			lines.append(String((child as Label).text))
		elif child is Button:
			lines.append(String((child as Button).text))
		if child is Control:
			var nested := _control_tree_text(child as Control)
			if not nested.is_empty():
				lines.append(nested)
	return "\n".join(lines)

func _cleanup_screen(screen: Control) -> void:
	screen.queue_free()

func _scroll_gameplay_map(screen: Control, position: Vector2, zoom_in: bool) -> void:
	var wheel_event := InputEventMouseButton.new()
	wheel_event.button_index = MOUSE_BUTTON_WHEEL_UP if zoom_in else MOUSE_BUTTON_WHEEL_DOWN
	wheel_event.pressed = true
	wheel_event.position = position
	screen._gui_input(wheel_event)

func _right_click_gameplay_map(screen: Control, position: Vector2) -> void:
	var mouse_event := InputEventMouseButton.new()
	mouse_event.button_index = MOUSE_BUTTON_RIGHT
	mouse_event.pressed = true
	mouse_event.position = position
	screen._gui_input(mouse_event)

func _assert_equal(expected: Variant, actual: Variant, message: String) -> void:
	if expected != actual:
		_fail("%s | expected=%s actual=%s" % [message, str(expected), str(actual)])

func _assert_true(value: bool, message: String) -> void:
	if not value:
		_fail(message)

func _assert_float_approx(expected: float, actual: float, message: String) -> void:
	if not is_equal_approx(expected, actual):
		_fail("%s | expected=%f actual=%f" % [message, expected, actual])

func _assert_vector2_approx(expected: Vector2, actual: Vector2, message: String) -> void:
	if not expected.is_equal_approx(actual):
		_fail("%s | expected=%s actual=%s" % [message, str(expected), str(actual)])

func _fail(message: String) -> void:
	_failures.append(message)
