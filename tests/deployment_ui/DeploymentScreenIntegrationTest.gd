extends Node

const DEPLOYMENT_SCREEN_SCENE := preload("res://scenes/deployment/DeploymentScreen.tscn")
const GAMEPLAY_SCREEN_SCENE := preload("res://scenes/screens/GameplayScreen.tscn")
const DeploymentAIService = preload("res://scripts/systems/deployment_ai/DeploymentAIService.gd")
const AITraceReplay = preload("res://scripts/tools/AITraceReplay.gd")

var _failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	await get_tree().process_frame
	await _test_deployment_sidebar_is_resizable_and_keeps_selection()
	_test_deployment_map_uses_terrain_and_darkens_illegal_hexes()
	_test_map_zoom_clamps_and_keeps_cursor_anchor()
	_test_zoomed_map_placement_and_undeployment_use_correct_hex()
	_test_selected_hex_details_and_card_driven_one_shot_move()
	_test_selected_hex_subunit_attachment_inspector()
	_test_double_click_stack_selection_and_atomic_move()
	_test_fully_represented_parent_is_blocked_and_reconciled()
	_test_deployment_map_receives_objectives()
	_test_replacing_same_unit_keeps_single_deployment_entry()
	_test_right_click_cancels_armed_unit_before_undeploying()
	_test_right_click_undeploys_all_units_on_hex()
	_test_four_companies_can_stack_on_one_hex()
	_test_occupied_hex_replacement_still_respects_validation_rules()
	_test_deployed_battalion_can_move_after_company_deployment()
	_test_tree_model_is_hierarchical_and_collapsed_by_default()
	await _test_specific_role_is_visible_and_preserved_in_snapshots()
	_test_non_deployable_units_stay_blocked()
	_test_platoon_is_absolute_minimum_and_squads_are_hidden()
	_test_finish_deployment_requires_all_deployable_units()
	_test_incomplete_child_warning_propagates_to_all_ancestors()
	_test_finish_deployment_allows_subordinates_when_parent_placed()
	_test_finish_deployment_allows_parent_when_all_subordinates_placed()
	_test_same_hex_subordinate_deployment_is_blocked_when_parent_placed()
	_test_finish_deployment_phase_transitions()
	_test_ai_player_deploys_and_skips_p2_phase()
	_test_ai_deployment_requires_player_two_territory()
	_test_ai_rejects_partial_deployment_transaction()
	_test_starting_scenario_payload_preserves_only_player_deployment()
	_test_default_battalion_headquarters_hierarchy()
	_test_ai_deployments_hydrate_gameplay_units()
	_test_ai_covers_wide_front_with_adaptive_platoons()
	_test_ai_manages_frontline_shortfall_without_large_gaps()
	_test_ai_reinforces_exposed_terrain_after_coverage()
	_test_ai_attaches_weapons_formations_to_combat_stacks()
	_test_ai_spreads_unplanned_combat_units_without_objectives()
	_test_ai_balances_reinforcements_across_authored_objectives()
	_test_ai_trace_json_is_pretty_printed()
	_test_ai_trace_legacy_index_is_reset()
	_test_ai_trace_malformed_index_recovers_with_retention()

	if _failures.is_empty():
		print("DeploymentScreen integration tests passed.")
		get_tree().quit(0)
		return

	for failure in _failures:
		push_error(failure)
	get_tree().quit(1)

func _test_deployment_sidebar_is_resizable_and_keeps_selection() -> void:
	_reset_state(GameState.Phase.DEPLOYMENT_P1)
	var long_name_unit := _platoon("long_name_plt", "A Very Long Platoon Name That Needs More Room")
	GameState.players[0]["division_tree"] = _root_with_children([long_name_unit])
	var screen := _spawn_screen()
	await get_tree().process_frame

	var workspace_split := screen.get_node_or_null("%WorkspaceSplit") as HSplitContainer
	var left_panel := screen.get_node_or_null("%LeftPanel") as PanelContainer
	var center_panel := screen.get_node_or_null("%CenterPanel") as PanelContainer
	var right_panel := screen.get_node_or_null("RootMargin/MainHBox/RightPanel") as VBoxContainer
	_assert_true(workspace_split != null, "Expected a draggable splitter between the deployment unit tree and map.")
	_assert_true(left_panel != null, "Expected the deployment unit-tree panel to remain available through the splitter.")
	_assert_true(center_panel != null, "Expected the deployment map panel to remain available through the splitter.")
	_assert_true(right_panel != null, "Expected right-side deployment controls to remain outside the splitter.")
	if workspace_split == null or left_panel == null or center_panel == null or right_panel == null:
		_cleanup_screen(screen)
		return

	var selected_item := _find_item_by_unit_id(screen.unit_list.get_root(), "long_name_plt")
	_assert_true(selected_item != null, "Expected the long-name unit to appear in the deployment tree.")
	if selected_item != null:
		screen.unit_list.set_selected(selected_item, 0)
		screen._on_unit_item_selected()

	var initial_left_width := left_panel.size.x
	workspace_split.split_offset = int(initial_left_width + 180.0)
	await get_tree().process_frame
	_assert_true(left_panel.size.x > initial_left_width, "Dragging the splitter toward the map should widen the deployment unit tree.")
	_assert_true(left_panel.size.x >= left_panel.custom_minimum_size.x, "Resizing should preserve the unit tree's practical minimum width.")
	_assert_true(center_panel.size.x >= center_panel.custom_minimum_size.x, "Resizing should preserve the map's practical minimum width.")
	_assert_true(right_panel.size.x >= right_panel.custom_minimum_size.x, "Resizing should keep the right-side deployment controls usable.")
	_assert_equal("long_name_plt", screen._selected_unit_id, "Resizing the deployment sidebar should retain the active unit selection.")
	_assert_true(screen.unit_list.get_selected() == selected_item, "Resizing the deployment sidebar should retain the visible tree selection.")

	workspace_split.split_offset = -10000
	await get_tree().process_frame
	_assert_true(left_panel.size.x >= left_panel.custom_minimum_size.x, "The splitter should not shrink the unit tree below its minimum width.")

	workspace_split.split_offset = 10000
	await get_tree().process_frame
	_assert_true(center_panel.size.x >= center_panel.custom_minimum_size.x, "The splitter should not shrink the map below its minimum width.")
	_cleanup_screen(screen)

func _test_specific_role_is_visible_and_preserved_in_snapshots() -> void:
	_reset_state(GameState.Phase.DEPLOYMENT_P1)
	var machine_gun_platoon := _platoon("mg_plt", "Machine Gun Platoon")
	machine_gun_platoon["template_id"] = "usa_heavy_machine_gun_platoon"
	machine_gun_platoon["role"] = "heavy_machine_gun"
	machine_gun_platoon["is_attached"] = true
	GameState.players[0]["division_tree"] = _root_with_children([machine_gun_platoon])
	var screen := _spawn_screen()
	await get_tree().process_frame

	var item := _find_item_by_unit_id(screen.unit_list.get_root(), "mg_plt")
	_assert_true(item != null, "Expected the weapon platoon to appear in the deployment tree")
	if item != null:
		_assert_true(String(item.get_text(0)).contains("Heavy Machine Gun"), "Deployment rows should show the specific unit role")
	var ui_snapshot: Dictionary = screen._unit_snapshot(machine_gun_platoon)
	_assert_equal("heavy_machine_gun", String(ui_snapshot.get("role", "")), "Deployment snapshots should preserve the specific role")
	_assert_equal("heavy", String(ui_snapshot.get("equipment_weight", "")), "Deployment snapshots should resolve the heavy-machine-gun symbol weight without an H overlay")
	_assert_true(bool(ui_snapshot.get("is_attached", false)), "Deployment snapshots should preserve attachment state")
	var ai_snapshot: Dictionary = DeploymentAIService._unit_snapshot_for(machine_gun_platoon)
	_assert_equal("heavy_machine_gun", String(ai_snapshot.get("role", "")), "AI deployment snapshots should preserve the specific role")
	_assert_equal("heavy", String(ai_snapshot.get("equipment_weight", "")), "AI deployment snapshots should preserve resolved equipment weight")
	_assert_equal("infantry", String(ai_snapshot.get("type", "")), "Adding a specific role must not change the broad rules class used by deployment AI")
	_assert_true(bool(ai_snapshot.get("is_attached", false)), "AI deployment snapshots should preserve attachment state")
	var gameplay_snapshot := FormationOperations.gameplay_snapshot(machine_gun_platoon, {"hex": Vector2i.ZERO}, 0)
	_assert_true(bool(gameplay_snapshot.get("is_attached", false)), "Gameplay formation snapshots should preserve attachment state")
	_assert_equal("heavy", String(gameplay_snapshot.get("equipment_weight", "")), "Gameplay formation snapshots should preserve resolved equipment weight")
	_cleanup_screen(screen)

func _test_map_zoom_clamps_and_keeps_cursor_anchor() -> void:
	_reset_state(GameState.Phase.DEPLOYMENT_P1)
	var screen := _spawn_screen()
	var map_view: DeploymentHexMapView = screen.hex_map_view
	map_view.pan_offset = Vector2(43.0, -27.0)
	var cursor := Vector2(360.0, 280.0)
	var anchored_world_position := map_view._to_world(cursor)

	_scroll_map(map_view, cursor, true)
	_assert_true(map_view.zoom_level > 1.0, "Mouse-wheel up should zoom the deployment map in.")
	_assert_vector2_approx(anchored_world_position, map_view._to_world(cursor), "Zoom should keep the world position under the cursor fixed.")

	for _index in range(100):
		_scroll_map(map_view, cursor, true)
	_assert_float_approx(DeploymentHexMapView.MAX_ZOOM, map_view.zoom_level, "Deployment zoom should clamp at its maximum.")
	_assert_vector2_approx(anchored_world_position, map_view._to_world(cursor), "Maximum zoom clamping should preserve the cursor anchor.")

	for _index in range(200):
		_scroll_map(map_view, cursor, false)
	_assert_float_approx(DeploymentHexMapView.MIN_ZOOM, map_view.zoom_level, "Deployment zoom should clamp at its minimum.")
	_assert_vector2_approx(anchored_world_position, map_view._to_world(cursor), "Minimum zoom clamping should preserve the cursor anchor.")

	_cleanup_screen(screen)
	var fresh_screen := _spawn_screen()
	_assert_float_approx(1.0, fresh_screen.hex_map_view.zoom_level, "A newly entered deployment screen should start at default zoom.")
	_cleanup_screen(fresh_screen)

func _test_deployment_map_uses_terrain_and_darkens_illegal_hexes() -> void:
	_reset_state(GameState.Phase.DEPLOYMENT_P1)
	GameState.terrain_map = {"0,0": "woods", "1,0": "urban", "2,0": "road"}
	GameState.territory_map = {
		"0,0": GameState.TerritoryOwnership.PLAYER_1,
		"1,0": GameState.TerritoryOwnership.PLAYER_2,
		"3,0": GameState.TerritoryOwnership.PLAYER_1
	}
	var player_one_screen := _spawn_screen()
	var player_one_map: DeploymentHexMapView = player_one_screen.hex_map_view
	_assert_color_approx(TerrainCatalog.editor_color("woods", 1.0), player_one_map._fill_color_for_hex(0, 0), "Player 1 legal territory should show its authored woods terrain without a blue ownership fill.")
	_assert_color_approx(TerrainCatalog.editor_color("urban", 1.0), player_one_map._fill_color_for_hex(1, 0), "Enemy territory should retain its authored urban terrain beneath the restriction overlay.")
	_assert_color_approx(TerrainCatalog.editor_color("road", 1.0), player_one_map._fill_color_for_hex(2, 0), "Neutral territory should retain its authored road terrain beneath the restriction overlay.")
	_assert_color_approx(TerrainCatalog.editor_color(TerrainCatalog.default_terrain_id(), 1.0), player_one_map._fill_color_for_hex(3, 0), "Missing authored terrain should fall back to unshaded Light Terrain on a legal hex.")
	_assert_color_approx(Color.TRANSPARENT, player_one_map._restriction_overlay_for_hex(0, 0), "A legal Player 1 hex should not receive a restriction overlay.")
	_assert_color_approx(player_one_map.NON_DEPLOYABLE_OVERLAY_COLOR, player_one_map._restriction_overlay_for_hex(1, 0), "Enemy territory should receive the translucent gray restriction overlay.")
	_assert_color_approx(player_one_map.NON_DEPLOYABLE_OVERLAY_COLOR, player_one_map._restriction_overlay_for_hex(2, 0), "Neutral territory should receive the same restriction overlay.")
	_cleanup_screen(player_one_screen)

	_reset_state(GameState.Phase.DEPLOYMENT_P2)
	GameState.terrain_map = {"0,0": "woods", "1,0": "urban"}
	GameState.territory_map = {
		"0,0": GameState.TerritoryOwnership.PLAYER_1,
		"1,0": GameState.TerritoryOwnership.PLAYER_2
	}
	var player_two_screen := _spawn_screen()
	var player_two_map: DeploymentHexMapView = player_two_screen.hex_map_view
	_assert_color_approx(TerrainCatalog.editor_color("woods", 1.0), player_two_map._fill_color_for_hex(0, 0), "Player 1 woods terrain should remain visible beneath Player 2's restriction overlay.")
	_assert_color_approx(TerrainCatalog.editor_color("urban", 1.0), player_two_map._fill_color_for_hex(1, 0), "Player 2 territory should show authored terrain at normal brightness while Player 2 deploys.")
	_assert_color_approx(player_two_map.NON_DEPLOYABLE_OVERLAY_COLOR, player_two_map._restriction_overlay_for_hex(0, 0), "Player 1 territory should receive the gray restriction overlay while Player 2 deploys.")
	_assert_color_approx(Color.TRANSPARENT, player_two_map._restriction_overlay_for_hex(1, 0), "Player 2 legal territory should remain free of the restriction overlay.")
	_cleanup_screen(player_two_screen)

func _test_zoomed_map_placement_and_undeployment_use_correct_hex() -> void:
	_reset_state(GameState.Phase.DEPLOYMENT_P1)
	GameState.territory_map = {"2,3": GameState.TerritoryOwnership.PLAYER_1}
	GameState.players[0]["division_tree"] = _root_with_children([_platoon("zoom_plt", "Zoom Platoon")])
	var screen := _spawn_screen()
	var map_view: DeploymentHexMapView = screen.hex_map_view
	map_view.pan_offset = Vector2(35.0, -40.0)
	map_view._set_zoom_at(Vector2(320.0, 240.0), 1.6)
	_select_unit_by_id(screen, "zoom_plt")

	var target_screen_position := map_view._to_screen(map_view._hex_center(2, 3))
	var transformed_hex := map_view._find_hex(map_view._to_world(target_screen_position))
	_assert_equal(2, int(transformed_hex.get("q", -1)), "Pan-and-zoom conversion should preserve the target hex column.")
	_assert_equal(3, int(transformed_hex.get("r", -1)), "Pan-and-zoom conversion should preserve the target hex row.")
	_left_click_map(map_view, target_screen_position)
	var deployments := (GameState.players[0] as Dictionary).get("deployments", {}) as Dictionary
	_assert_true(deployments.has("2,3"), "Clicking a zoomed and panned map should deploy to the visible target hex.")

	_right_click_hex(screen, 2, 3)
	deployments = (GameState.players[0] as Dictionary).get("deployments", {}) as Dictionary
	_assert_false(deployments.has("2,3"), "Right-clicking a zoomed and panned map should undeploy from the visible target hex.")
	_assert_equal("", screen._selected_unit_id, "Undeploying the selected unit should clear its sidebar selection so warning styling is visible.")
	_assert_true(screen._unplaced_deployable_unit_ids.has("zoom_plt"), "An undeployed unit should return to the unplaced-unit set.")
	var undeployed_item := _find_item_by_unit_id(screen.unit_list.get_root(), "zoom_plt")
	_assert_true(undeployed_item != null, "An undeployed unit should remain visible in the sidebar.")
	if undeployed_item != null:
		_assert_true(undeployed_item.get_custom_color(0) == screen.UNDEPLOYED_WARNING_COLOR, "An undeployed unit should be highlighted red again.")
		_assert_false(String(undeployed_item.get_text(0)).contains("Placed:"), "An undeployed unit should lose its placement annotation.")
	_cleanup_screen(screen)

func _test_replacing_same_unit_keeps_single_deployment_entry() -> void:
	_reset_state(GameState.Phase.DEPLOYMENT_P1)
	GameState.territory_map = {
		"0,0": GameState.TerritoryOwnership.PLAYER_1,
		"0,1": GameState.TerritoryOwnership.PLAYER_1
	}
	var unit := _platoon("u1", "1st Platoon")
	GameState.players[0]["division_tree"] = _root_with_children([unit])

	var screen := _spawn_screen()
	_select_unit_by_id(screen, "u1")
	screen._on_hex_selected(0, 0)
	_select_unit_by_id(screen, "u1")
	screen._on_hex_selected(0, 1)

	var deployments: Dictionary = GameState.players[0].get("deployments", {})
	_assert_equal(1, deployments.size(), "Expected exactly one deployment entry after moving a unit.")
	_assert_true(deployments.has("0,1"), "Expected moved unit to exist at latest target hex.")
	_assert_false(deployments.has("0,0"), "Expected old deployment hex to be cleared after move.")
	_assert_equal(1, _count_unit_id_occurrences(deployments, "u1"), "Expected one deployment record for unit u1.")

	_cleanup_screen(screen)

func _test_right_click_cancels_armed_unit_before_undeploying() -> void:
	_reset_state(GameState.Phase.DEPLOYMENT_P1)
	GameState.territory_map = {"0,0": GameState.TerritoryOwnership.PLAYER_1}
	GameState.players[0]["division_tree"] = _root_with_children([
		_platoon("deployed_plt", "Deployed Platoon"),
		_platoon("pending_plt", "Pending Platoon")
	])

	var screen := _spawn_screen()
	_select_unit_by_id(screen, "deployed_plt")
	screen._on_hex_selected(0, 0)
	var pending_item := _find_item_by_unit_id(screen.unit_list.get_root(), "pending_plt")
	_assert_true(pending_item != null, "Expected the pending unit to remain selectable after placing the first unit.")
	if pending_item == null:
		_cleanup_screen(screen)
		return
	screen.unit_list.set_selected(pending_item, 0)
	screen._on_unit_item_selected()
	_assert_equal("pending_plt", screen.hex_map_view.armed_unit_id, "Selecting a unit should arm it on the deployment map.")

	_right_click_hex(screen, 0, 0)
	var deployments: Dictionary = GameState.players[0].get("deployments", {})
	_assert_true(deployments.has("0,0"), "Right-click cancellation must not undeploy units from the clicked hex.")
	_assert_equal("", screen._selected_unit_id, "Right-clicking while armed should clear the selected deployment unit.")
	_assert_equal("", screen.hex_map_view.armed_unit_id, "Right-clicking while armed should clear the map highlight.")
	_assert_true(screen.unit_list.get_selected() == null, "Right-clicking while armed should deselect the formation-tree row.")
	_assert_true(String(screen.status_label.text).contains("Unit selection cancelled"), "Cancellation should provide status feedback.")

	_right_click_hex(screen, 0, 0)
	deployments = GameState.players[0].get("deployments", {})
	_assert_false(deployments.has("0,0"), "A second right-click with no armed unit should retain normal undeployment behavior.")
	_cleanup_screen(screen)

func _test_right_click_undeploys_all_units_on_hex() -> void:
	_reset_state(GameState.Phase.DEPLOYMENT_P1)
	GameState.territory_map = {
		"0,0": GameState.TerritoryOwnership.PLAYER_1,
		"0,1": GameState.TerritoryOwnership.PLAYER_1
	}
	var companies := [
		_company("co_a", "A Company"),
		_company("co_b", "B Company"),
		_company("co_c", "C Company")
	]
	GameState.players[0]["division_tree"] = _root_with_children(companies)

	var screen := _spawn_screen()
	_select_unit_by_id(screen, "co_a")
	screen._on_hex_selected(0, 0)
	_select_unit_by_id(screen, "co_b")
	screen._on_hex_selected(0, 0)
	_select_unit_by_id(screen, "co_c")
	screen._on_hex_selected(0, 1)

	_right_click_hex(screen, 0, 0)

	var deployments: Dictionary = GameState.players[0].get("deployments", {})
	_assert_false(deployments.has("0,0"), "Expected right-click undeploy to clear every unit assigned to the clicked hex.")
	_assert_true(deployments.has("0,1"), "Expected right-click undeploy to preserve deployments on other hexes.")
	_assert_equal(1, _deployment_units_at_hex(deployments, "0,1").size(), "Expected only the unclicked hex deployment to remain.")
	_assert_true(String(screen.status_label.text).contains("Undeployed 2 units from 0,0"), "Expected undeploy status to include the number of removed units and target hex. actual=%s" % String(screen.status_label.text))
	_assert_equal("", screen._selected_unit_id, "Successful placement should clear the armed unit for safe one-shot movement.")

	_right_click_hex(screen, 0, 0)
	_assert_true(String(screen.status_label.text).contains("No deployed units at 0,0"), "Expected empty hex right-click to explain that nothing was undeployed.")

	_cleanup_screen(screen)

func _test_selected_hex_details_and_card_driven_one_shot_move() -> void:
	_reset_state(GameState.Phase.DEPLOYMENT_P1)
	GameState.territory_map = {
		"0,0": GameState.TerritoryOwnership.PLAYER_1,
		"0,1": GameState.TerritoryOwnership.PLAYER_1,
		"1,0": GameState.TerritoryOwnership.PLAYER_2
	}
	GameState.terrain_map = {"0,0": "woods", "0,1": "light", "1,0": "heavy"}
	var unit := _platoon("move_plt", "M4 Sherman Medium Tank Platoon")
	unit["type"] = "tank"
	unit["role"] = "medium_tank"
	unit["designation"] = {
		"platoon_number": 1,
		"company_letter": "A",
		"battalion_number": 2,
		"regiment_number": 9,
		"division_number": 4
	}
	GameState.players[0]["division_tree"] = _root_with_children([unit])
	GameState.players[0]["deployments"] = {"0,0": unit.duplicate(true)}

	var screen := _spawn_screen()
	screen._on_hex_selected(0, 0)
	_assert_equal(Vector2i(0, 0), screen._selected_hex, "Clicking without an armed unit should still select the deployment hex.")
	_assert_equal("", screen._selected_unit_id, "Inspecting a hex should not arm a unit automatically.")
	_assert_true(String(screen.selected_hex_title_label.text).contains("0,0"), "Selected-hex details should show coordinates.")
	_assert_true(String(screen.selected_hex_ownership_label.text).contains("Friendly"), "Selected-hex details should show territory ownership from the current player's perspective.")
	_assert_true(String(screen.selected_hex_terrain_label.text).contains("Woods"), "Selected-hex details should show terrain.")
	_assert_equal(1, screen.selected_hex_unit_cards.get_child_count(), "An occupied deployment hex should expose one clickable card per unit.")

	var card := screen.selected_hex_unit_cards.get_child(0) as Button
	_assert_true(card != null, "Deployment unit details should be represented by clickable buttons.")
	if card == null:
		_cleanup_screen(screen)
		return
	_assert_true(String(card.text).contains("1/A/2"), "The card should include platoon/company/battalion identity.")
	_assert_false(String(card.text).contains("2-9"), "The card identity should omit regiment ancestry.")
	card.pressed.emit()
	_assert_equal("move_plt", screen._selected_unit_id, "Clicking a deployed-unit card should arm that unit for movement.")
	_assert_equal("move_plt", screen._inspected_deployment_unit_id, "Clicking a deployed-unit card should open its subordinate inspector.")
	_assert_equal("move_plt", screen.hex_map_view.armed_unit_id, "The map should highlight the unit armed from the card.")
	_assert_true(screen.unit_list.get_selected() != null and String(screen.unit_list.get_selected().get_metadata(0).get("unit_id", "")) == "move_plt", "Card selection should synchronize the formation tree.")

	screen._on_hex_selected(1, 0)
	_assert_equal("move_plt", screen._selected_unit_id, "An illegal destination should retain the armed unit.")
	_assert_equal("move_plt", screen._inspected_deployment_unit_id, "An illegal destination should retain the subordinate inspector for retrying the move.")
	_assert_true(GameState.players[0]["deployments"].has("0,0"), "An illegal move should leave the source deployment unchanged.")

	screen._on_hex_selected(0, 1)
	_assert_equal("", screen._selected_unit_id, "A successful card-driven move should clear the armed unit.")
	_assert_equal("", screen._inspected_deployment_unit_id, "A successful move should close the subordinate inspector.")
	_assert_false(GameState.players[0]["deployments"].has("0,0"), "A successful move should clear the source hex.")
	_assert_true(GameState.players[0]["deployments"].has("0,1"), "A successful move should populate the destination hex.")
	_assert_equal(Vector2i(0, 1), screen.hex_map_view.selected_hex, "The successful destination should remain selected for inspection.")

	var moved_card := screen.selected_hex_unit_cards.get_child(0) as Button
	moved_card.pressed.emit()
	screen._on_hex_selected(0, 1)
	_assert_equal("move_plt", screen._selected_unit_id, "Clicking the current source hex should be an inspection no-op and keep the unit armed.")
	var escape_event := InputEventKey.new()
	escape_event.pressed = true
	escape_event.keycode = KEY_ESCAPE
	screen._unhandled_input(escape_event)
	_assert_equal("", screen._selected_unit_id, "Escape should cancel card-driven movement.")
	_assert_equal("", screen.hex_map_view.armed_unit_id, "Escape should clear the map's armed-unit highlight.")
	_cleanup_screen(screen)

func _test_selected_hex_subunit_attachment_inspector() -> void:
	_reset_state(GameState.Phase.DEPLOYMENT_P1)
	GameState.territory_map = {
		"0,0": GameState.TerritoryOwnership.PLAYER_1,
		"0,1": GameState.TerritoryOwnership.PLAYER_1,
		"0,2": GameState.TerritoryOwnership.PLAYER_1,
		"1,0": GameState.TerritoryOwnership.PLAYER_1
	}
	var attached_platoon := _platoon("attached_plt", "1st Platoon")
	attached_platoon["children"] = [_rifle_squad("attached_squad", "1st Squad")]
	var detached_platoon := _platoon("detached_plt", "2nd Platoon")
	var detached_squad := _rifle_squad("detached_squad", "Detached Squad")
	var partial_platoon := _platoon("partial_plt", "3rd Platoon")
	partial_platoon["children"] = [{
		"id": "partial_section",
		"display_name": "Weapons Section",
		"type": "infantry",
		"role": "weapons",
		"size": "section",
		"status": "alive",
		"designation": {},
		"children": [detached_squad]
	}]
	var company := _company("inspect_co", "Able Company")
	company["children"] = [attached_platoon, detached_platoon, partial_platoon]
	GameState.players[0]["division_tree"] = _root_with_children([company])
	GameState.players[0]["deployments"] = {
		"0,0": company.duplicate(true),
		"0,1": detached_platoon.duplicate(true),
		"0,2": detached_squad.duplicate(true)
	}

	var screen := _spawn_screen()
	screen._on_hex_selected(0, 0)
	_assert_equal(1, screen.selected_hex_unit_cards.get_child_count(), "Selecting an occupied hex should initially show only its top-level cards.")
	var company_card := screen.selected_hex_unit_cards.get_child(0) as Button
	company_card.pressed.emit()

	var inspector_text := _control_tree_text(screen.selected_hex_unit_cards)
	_assert_true(inspector_text.contains("Subunits of Able Company"), "The inspector should name the formation whose children are listed.")
	_assert_true(inspector_text.contains("Health: —"), "Subunit rows should reserve room for a future health summary.")
	var attached_card := _find_button_by_meta(screen.selected_hex_unit_cards, "subunit_id", "attached_plt")
	var detached_card := _find_button_by_meta(screen.selected_hex_unit_cards, "subunit_id", "detached_plt")
	var partial_card := _find_button_by_meta(screen.selected_hex_unit_cards, "subunit_id", "partial_plt")
	_assert_true(attached_card != null and String(attached_card.text).contains("Attached"), "A child without its own marker should be listed as attached.")
	_assert_true(detached_card != null and String(detached_card.text).contains("Detached — Hex 0,1"), "A child with its own marker should include its detached hex.")
	_assert_true(partial_card != null and String(partial_card.text).contains("Partially detached") and String(partial_card.text).contains("0,2"), "A child with a deeper independent marker should summarize its branch as partially detached.")

	if attached_card != null:
		attached_card.pressed.emit()
	_assert_equal("attached_plt", screen._inspected_deployment_unit_id, "Clicking an attached child should drill into that child.")
	_assert_equal(Vector2i(0, 0), screen._selected_hex, "Clicking an attached child should keep the deployed ancestor's hex selected.")
	_assert_equal("inspect_co", screen.hex_map_view.armed_unit_id, "An attached child should highlight its nearest deployed ancestor marker.")
	var squad_card := _find_button_by_meta(screen.selected_hex_unit_cards, "subunit_id", "attached_squad")
	_assert_true(squad_card != null and squad_card.disabled, "Below-platoon children should remain visible but disabled.")
	_assert_true(squad_card != null and String(squad_card.text).contains("not independently deployable"), "Disabled internal elements should explain that they cannot be deployed directly.")
	screen._on_hex_selected(1, 0)
	_assert_equal("1,0", screen._deployment_key_for_unit_id(GameState.players[0]["deployments"], "attached_plt"), "Moving an attached child should split it into an independent deployment marker.")
	_assert_equal("", screen._inspected_deployment_unit_id, "Successfully splitting an attached child should close the inspector.")

	screen._on_hex_selected(0, 0)
	company_card = screen.selected_hex_unit_cards.get_child(0) as Button
	company_card.pressed.emit()
	detached_card = _find_button_by_meta(screen.selected_hex_unit_cards, "subunit_id", "detached_plt")
	if detached_card != null:
		detached_card.pressed.emit()
	_assert_equal(Vector2i(0, 1), screen._selected_hex, "Clicking a detached child should jump the selected hex to that child's marker.")
	_assert_equal("detached_plt", screen._selected_unit_id, "Clicking a detached child should arm it for movement.")
	_assert_equal("detached_plt", screen.hex_map_view.armed_unit_id, "A detached child should highlight its own marker.")

	screen._on_deployment_cancel_requested()
	_assert_equal("", screen._inspected_deployment_unit_id, "Cancelling movement should close the subordinate inspector.")
	_assert_equal(1, screen.selected_hex_unit_cards.get_child_count(), "After cancellation, the selected hex should return to top-level cards only.")
	_cleanup_screen(screen)

func _test_double_click_stack_selection_and_atomic_move() -> void:
	_reset_state(GameState.Phase.DEPLOYMENT_P1)
	GameState.territory_map = {
		"0,0": GameState.TerritoryOwnership.PLAYER_1,
		"0,1": GameState.TerritoryOwnership.PLAYER_1
	}
	var company_a := _company("group_a", "Group A")
	var company_b := _company("group_b", "Group B")
	GameState.players[0]["division_tree"] = _root_with_children([company_a, company_b])
	GameState.players[0]["deployments"] = {"0,0": [company_a.duplicate(true), company_b.duplicate(true)]}
	var screen := _spawn_screen()
	_double_click_map(screen.hex_map_view, screen.hex_map_view._to_screen(screen.hex_map_view._hex_center(0, 0)))
	_assert_equal(["group_a", "group_b"], screen._selected_unit_ids, "Double-clicking a deployment stack should select every visible counter on that hex.")
	_assert_equal("group_b", screen._selected_unit_id, "The frontmost deployment counter should become the primary group unit.")
	_assert_equal(["group_a", "group_b"], screen.hex_map_view.armed_unit_ids, "Every selected deployment counter should contribute to the stack highlight.")
	var first_card := screen.selected_hex_unit_cards.get_child(0) as Button
	first_card.pressed.emit()
	_assert_equal(["group_a"], screen._selected_unit_ids, "A normal deployment card click should replace a double-click group with one unit.")
	_double_click_map(screen.hex_map_view, screen.hex_map_view._to_screen(screen.hex_map_view._hex_center(0, 0)))
	screen._on_deployment_cancel_requested()
	_assert_true(screen._selected_unit_ids.is_empty(), "Cancelling deployment should clear the complete selected stack.")
	_double_click_map(screen.hex_map_view, screen.hex_map_view._to_screen(screen.hex_map_view._hex_center(0, 0)))
	screen._on_hex_selected(0, 1)
	var deployments: Dictionary = GameState.players[0]["deployments"]
	_assert_false(deployments.has("0,0"), "A legal atomic group move should clear the complete source stack.")
	_assert_equal(2, _deployment_units_at_hex(deployments, "0,1").size(), "A legal atomic group move should place every selected counter at the destination.")
	_cleanup_screen(screen)

	_reset_state(GameState.Phase.DEPLOYMENT_P1)
	GameState.territory_map = {
		"0,0": GameState.TerritoryOwnership.PLAYER_1,
		"0,1": GameState.TerritoryOwnership.PLAYER_1
	}
	var source_companies := [_company("source_a", "Source A"), _company("source_b", "Source B")]
	var target_companies := [_company("target_a", "Target A"), _company("target_b", "Target B"), _company("target_c", "Target C")]
	var all_companies: Array = []
	all_companies.append_array(source_companies)
	all_companies.append_array(target_companies)
	GameState.players[0]["division_tree"] = _root_with_children(all_companies)
	GameState.players[0]["deployments"] = {"0,0": source_companies.duplicate(true), "0,1": target_companies.duplicate(true)}
	screen = _spawn_screen()
	_double_click_map(screen.hex_map_view, screen.hex_map_view._to_screen(screen.hex_map_view._hex_center(0, 0)))
	screen._on_hex_selected(0, 1)
	deployments = GameState.players[0]["deployments"]
	_assert_equal(2, _deployment_units_at_hex(deployments, "0,0").size(), "An illegal projected stack should leave every selected counter at its source.")
	_assert_equal(3, _deployment_units_at_hex(deployments, "0,1").size(), "An rejected atomic group move should leave the destination unchanged.")
	_assert_true(String(screen.status_label.text).contains("No selected units moved"), "Atomic deployment rejection should explicitly report that the complete group stayed put.")
	_cleanup_screen(screen)

func _test_fully_represented_parent_is_blocked_and_reconciled() -> void:
	_reset_state(GameState.Phase.DEPLOYMENT_P1)
	GameState.territory_map = {
		"0,0": GameState.TerritoryOwnership.PLAYER_1,
		"0,1": GameState.TerritoryOwnership.PLAYER_1,
		"0,2": GameState.TerritoryOwnership.PLAYER_1,
		"1,0": GameState.TerritoryOwnership.PLAYER_1
	}
	var screen := _spawn_screen()
	var german_template := UnitCatalog.get_nation_template("germany", "ger_regimental_infantry_gun_company")
	var infantry_gun_company: Dictionary = screen._division_tree_from_catalog_template(german_template)
	var platoons := infantry_gun_company.get("children", []) as Array
	_assert_equal(3, platoons.size(), "The German infantry gun company regression fixture should contain all three platoons.")
	GameState.players[0]["division_tree"] = _root_with_children([infantry_gun_company])
	GameState.players[0]["deployments"] = {
		"0,0": (platoons[0] as Dictionary).duplicate(true),
		"0,1": (platoons[1] as Dictionary).duplicate(true),
		"0,2": (platoons[2] as Dictionary).duplicate(true)
	}
	screen._build_deployable_unit_list(false)
	var company_id := String(infantry_gun_company.get("id", ""))
	var company_item := _find_item_by_unit_id(screen.unit_list.get_root(), company_id)
	_assert_true(company_item != null and not company_item.is_selectable(0), "A German infantry gun company fully represented by its platoons should be nonselectable.")
	_assert_true(company_item != null and String(company_item.get_text(0)).contains("Covered by subordinates"), "The blocked company should explain that its platoons already represent it.")
	if company_item != null:
		screen._selected_unit_id = company_id
		screen._selected_unit_metadata = (company_item.get_metadata(0) as Dictionary).duplicate(true)
		screen._on_hex_selected(1, 0)
	_assert_equal("", screen._deployment_key_for_unit_id(GameState.players[0]["deployments"], company_id), "A fully represented parent must not receive an additional deployment marker.")
	_cleanup_screen(screen)

	_reset_state(GameState.Phase.DEPLOYMENT_P1)
	GameState.territory_map = {
		"0,0": GameState.TerritoryOwnership.PLAYER_1,
		"0,1": GameState.TerritoryOwnership.PLAYER_1,
		"0,2": GameState.TerritoryOwnership.PLAYER_1
	}
	var first_platoon := _platoon("reconcile_plt_1", "1st Platoon")
	var final_platoon := _platoon("reconcile_plt_2", "2nd Platoon")
	var parent_company := _company("reconcile_company", "Reconcile Company")
	parent_company["children"] = [first_platoon, final_platoon]
	GameState.players[0]["division_tree"] = _root_with_children([parent_company])
	GameState.players[0]["deployments"] = {"0,0": parent_company.duplicate(true), "0,1": first_platoon.duplicate(true)}
	screen = _spawn_screen()
	_select_unit_by_id(screen, "reconcile_plt_2")
	screen._on_hex_selected(0, 2)
	var reconciled_deployments: Dictionary = GameState.players[0]["deployments"]
	_assert_equal("", screen._deployment_key_for_unit_id(reconciled_deployments, "reconcile_company"), "Splitting the final deployable subordinate should remove its redundant parent marker.")
	_assert_equal("0,2", screen._deployment_key_for_unit_id(reconciled_deployments, "reconcile_plt_2"), "The final subordinate should retain its newly created independent marker.")
	_assert_true(String(screen.status_label.text).contains("Removed redundant Reconcile Company"), "Deployment feedback should identify an automatically removed redundant parent.")
	_cleanup_screen(screen)

func _test_deployment_map_receives_objectives() -> void:
	_reset_state(GameState.Phase.DEPLOYMENT_P1)
	GameState.key_objectives = {
		"0,0": {"priority": "primary"},
		"1,1": {"priority": "secondary"}
	}
	var screen := _spawn_screen()
	_assert_equal(GameState.key_objectives, screen.hex_map_view.objective_map, "Deployment should pass all primary and secondary objectives to the map view.")
	screen.hex_map_view.zoom_level = 1.75
	screen.hex_map_view.queue_redraw()
	_assert_equal(1.75, screen.hex_map_view.zoom_level, "Objective overlays should share the deployment map's normal zoom transform.")
	_cleanup_screen(screen)

func _test_four_companies_can_stack_on_one_hex() -> void:
	_reset_state(GameState.Phase.DEPLOYMENT_P1)
	GameState.territory_map = {
		"0,0": GameState.TerritoryOwnership.PLAYER_1
	}
	var companies := [
		_company("co_a", "A Company"),
		_company("co_b", "B Company"),
		_company("co_c", "C Company"),
		_company("co_d", "D Company"),
		_company("co_e", "E Company")
	]
	GameState.players[0]["division_tree"] = _root_with_children(companies)

	var screen := _spawn_screen()
	for unit_id in ["co_a", "co_b", "co_c", "co_d"]:
		_select_unit_by_id(screen, unit_id)
		screen._on_hex_selected(0, 0)

	var deployments: Dictionary = GameState.players[0].get("deployments", {})
	_assert_equal(1, deployments.size(), "Expected stacked companies to share one deployment hex entry.")
	_assert_equal(4, _deployment_units_at_hex(deployments, "0,0").size(), "Expected four companies to stack on the target hex.")

	_select_unit_by_id(screen, "co_e")
	screen._on_hex_selected(0, 0)
	deployments = GameState.players[0].get("deployments", {})
	_assert_equal(4, _deployment_units_at_hex(deployments, "0,0").size(), "Expected fifth company to remain blocked by stacking limit.")
	_assert_true(String(screen.status_label.text).contains("Company limit reached"), "Expected company stacking limit status message.")

	_cleanup_screen(screen)

func _test_occupied_hex_replacement_still_respects_validation_rules() -> void:
	_reset_state(GameState.Phase.DEPLOYMENT_P1)
	GameState.territory_map = {
		"1,0": GameState.TerritoryOwnership.PLAYER_1,
		"2,0": GameState.TerritoryOwnership.PLAYER_1
	}
	var battalion := _battalion("bn_1", "1st Battalion")
	var company_a := _company("co_a", "A Company")
	var company_b := _company("co_b", "B Company")
	GameState.players[0]["division_tree"] = _root_with_children([battalion, company_a, company_b])
	GameState.players[0]["deployments"] = {
		"1,0": company_a,
		"2,0": company_b
	}

	var screen := _spawn_screen()
	_select_unit_by_id(screen, "bn_1")
	screen._on_hex_selected(1, 0)

	var deployments: Dictionary = GameState.players[0].get("deployments", {})
	_assert_equal(2, deployments.size(), "Validation should reject battalion replacement when companies remain deployed.")
	_assert_equal("co_a", _first_deployed_unit_id_at_hex(deployments, "1,0"), "Existing occupied hex entry should remain unchanged when validation fails.")
	_assert_true(String(screen.status_label.text).contains("Cannot place a battalion after companies are deployed"), "Expected validation status message when battalion placement is blocked. actual=%s" % String(screen.status_label.text))

	_cleanup_screen(screen)

func _test_deployed_battalion_can_move_after_company_deployment() -> void:
	_reset_state(GameState.Phase.DEPLOYMENT_P1)
	GameState.territory_map = {
		"0,0": GameState.TerritoryOwnership.PLAYER_1,
		"0,1": GameState.TerritoryOwnership.PLAYER_1,
		"2,0": GameState.TerritoryOwnership.PLAYER_1
	}
	var battalion := _battalion("bn_1", "1st Battalion")
	var company := _company("co_a", "A Company")
	GameState.players[0]["division_tree"] = _root_with_children([battalion, company])
	GameState.players[0]["deployments"] = {
		"0,0": battalion,
		"2,0": company
	}

	var screen := _spawn_screen()
	_select_unit_by_id(screen, "bn_1")
	screen._on_hex_selected(0, 1)

	var deployments: Dictionary = GameState.players[0].get("deployments", {})
	_assert_false(deployments.has("0,0"), "Expected the battalion's old hex to be cleared after moving it.")
	_assert_equal("bn_1", _first_deployed_unit_id_at_hex(deployments, "0,1"), "Expected deployed battalion to move to the selected target hex.")
	_assert_equal("co_a", _first_deployed_unit_id_at_hex(deployments, "2,0"), "Expected existing company deployment to remain in place.")
	_assert_true(String(screen.status_label.text).contains("Moved"), "Expected battalion move to succeed instead of being blocked by deployed companies. actual=%s" % String(screen.status_label.text))

	_cleanup_screen(screen)

func _test_tree_model_is_hierarchical_and_collapsed_by_default() -> void:
	_reset_state(GameState.Phase.DEPLOYMENT_P1)
	var child_platoon := _platoon("child_platoon", "Child Platoon")
	var parent_company := _company("parent_company", "Parent Company")
	parent_company["children"] = [child_platoon]
	GameState.players[0]["division_tree"] = _root_with_children([parent_company])

	var screen := _spawn_screen()
	var parent_item := _find_item_by_unit_id(screen.unit_list.get_root(), "parent_company")
	var child_item := _find_item_by_unit_id(screen.unit_list.get_root(), "child_platoon")

	_assert_true(parent_item != null, "Expected parent formation to exist in deployment tree.")
	_assert_true(child_item != null, "Expected child unit to exist under parent in deployment tree.")
	if parent_item != null:
		_assert_true(parent_item.get_child_count() > 0, "Expected parent item to be expandable with children.")
		_assert_true(parent_item.is_collapsed(), "Expected parent items to default to collapsed state.")

	_cleanup_screen(screen)

func _test_non_deployable_units_stay_blocked() -> void:
	_reset_state(GameState.Phase.DEPLOYMENT_P1)
	var hq := {
		"id": "hq_1",
		"name": "HQ",
		"type": "headquarters",
		"size": "section",
		"status": "alive",
		"children": []
	}
	var dead_platoon := _platoon("dead_plt", "Dead Platoon")
	dead_platoon["status"] = "dead"
	var live_platoon := _platoon("live_plt", "Live Platoon")
	GameState.players[0]["division_tree"] = _root_with_children([hq, dead_platoon, live_platoon])

	var screen := _spawn_screen()
	var hq_item := _find_item_by_unit_id(screen.unit_list.get_root(), "hq_1")
	var dead_item := _find_item_by_unit_id(screen.unit_list.get_root(), "dead_plt")
	var live_item := _find_item_by_unit_id(screen.unit_list.get_root(), "live_plt")

	_assert_true(hq_item != null and not hq_item.is_selectable(0), "Headquarters unit should remain non-selectable.")
	_assert_true(dead_item != null and not dead_item.is_selectable(0), "Dead unit should remain non-selectable.")
	_assert_true(live_item != null and live_item.is_selectable(0), "Deployable platoon should remain selectable.")

	_cleanup_screen(screen)

func _test_platoon_is_absolute_minimum_and_squads_are_hidden() -> void:
	_reset_state(GameState.Phase.DEPLOYMENT_P1)
	GameState.territory_map = {
		"0,0": GameState.TerritoryOwnership.PLAYER_1,
		"0,1": GameState.TerritoryOwnership.PLAYER_1,
		"0,2": GameState.TerritoryOwnership.PLAYER_1
	}
	var gun_a := _anti_tank_unit("at_gun_a", "AT Gun A", "section")
	var gun_b := _anti_tank_unit("at_gun_b", "AT Gun B", "section")
	var squad_c := _anti_tank_unit("at_squad_c", "AT Squad C", "squad")
	var antitank_platoon := _anti_tank_unit("at_platoon", "Anti-Tank Platoon", "platoon")
	antitank_platoon["children"] = [gun_a, gun_b, squad_c]
	var rifle_squad := _rifle_squad("rifle_squad", "Rifle Squad")
	GameState.players[0]["division_tree"] = _root_with_children([antitank_platoon, rifle_squad])

	var screen := _spawn_screen()
	for unit_id in ["at_gun_a", "at_gun_b"]:
		var at_item := _find_item_by_unit_id(screen.unit_list.get_root(), unit_id)
		_assert_true(at_item != null and not at_item.is_selectable(0), "Expected anti-tank section %s to remain visible but non-deployable." % unit_id)
	var at_squad_item := _find_item_by_unit_id(screen.unit_list.get_root(), "at_squad_c")
	_assert_true(at_squad_item == null, "Squad-sized units should be omitted from the deployment tree.")
	var rifle_item := _find_item_by_unit_id(screen.unit_list.get_root(), "rifle_squad")
	_assert_true(rifle_item == null, "All squad-sized units should be omitted regardless of role.")
	var platoon_item := _find_item_by_unit_id(screen.unit_list.get_root(), "at_platoon")
	_assert_true(platoon_item != null and platoon_item.is_selectable(0), "The anti-tank platoon should remain deployable.")
	_select_unit_by_id(screen, "at_platoon")
	screen._on_hex_selected(0, 0)
	screen._on_finish_deployment_pressed()
	_assert_equal(GameState.Phase.DEPLOYMENT_P2, GameState.current_phase, "Deploying the platoon should satisfy its hidden/non-deployable descendants.")

	_cleanup_screen(screen)

func _test_same_hex_subordinate_deployment_is_blocked_when_parent_placed() -> void:
	_reset_state(GameState.Phase.DEPLOYMENT_P1)
	GameState.territory_map = {
		"0,0": GameState.TerritoryOwnership.PLAYER_1,
		"0,1": GameState.TerritoryOwnership.PLAYER_1
	}
	var platoon := _platoon("plt_a", "Platoon A")
	var company := _company("co_a", "A Company")
	company["children"] = [platoon]
	GameState.players[0]["division_tree"] = _root_with_children([company])

	var screen := _spawn_screen()
	_select_unit_by_id(screen, "co_a")
	screen._on_hex_selected(0, 0)
	_select_unit_by_id(screen, "plt_a")
	screen._on_hex_selected(0, 0)

	var deployments: Dictionary = GameState.players[0].get("deployments", {})
	_assert_equal(1, _deployment_units_at_hex(deployments, "0,0").size(), "Expected covered subordinate to remain attached instead of stacking on parent hex.")
	_assert_equal(0, _deployment_units_at_hex(deployments, "0,1").size(), "Expected blocked same-hex placement to leave other hexes unchanged.")
	_assert_true(String(screen.status_label.text).contains("already covered"), "Expected status to explain that same-hex subordinate placement is already covered by parent.")

	_select_unit_by_id(screen, "plt_a")
	screen._on_hex_selected(0, 1)
	deployments = GameState.players[0].get("deployments", {})
	_assert_equal(0, _deployment_units_at_hex(deployments, "0,0").size(), "Detaching the final deployable subordinate should remove the redundant parent marker.")
	_assert_equal(1, _deployment_units_at_hex(deployments, "0,1").size(), "Expected subordinate to still be deployable on a different hex.")
	_cleanup_screen(screen)

	_reset_state(GameState.Phase.DEPLOYMENT_P1)
	GameState.territory_map = {
		"0,0": GameState.TerritoryOwnership.PLAYER_1
	}
	platoon = _platoon("plt_a", "Platoon A")
	company = _company("co_a", "A Company")
	company["children"] = [platoon]
	GameState.players[0]["division_tree"] = _root_with_children([company])
	screen = _spawn_screen()
	_select_unit_by_id(screen, "plt_a")
	screen._on_hex_selected(0, 0)
	_select_unit_by_id(screen, "co_a")
	screen._on_hex_selected(0, 0)
	deployments = GameState.players[0].get("deployments", {})
	_assert_equal(1, _deployment_units_at_hex(deployments, "0,0").size(), "Expected parent placement to be blocked on a hex occupied by its deployed subordinate.")
	_assert_true(String(screen.status_label.text).contains("subordinate"), "Expected status to explain that the parent is already represented by its subordinate deployment.")

	_cleanup_screen(screen)

func _test_finish_deployment_phase_transitions() -> void:
	_reset_state(GameState.Phase.DEPLOYMENT_P1)
	var p1_screen := _spawn_screen()
	p1_screen._on_finish_deployment_pressed()
	_assert_equal(GameState.Phase.DEPLOYMENT_P2, GameState.current_phase, "Finish deployment should advance P1 to DEPLOYMENT_P2.")
	_cleanup_screen(p1_screen)

	_reset_state(GameState.Phase.DEPLOYMENT_P2)
	var p2_screen := _spawn_screen()
	p2_screen._on_finish_deployment_pressed()
	_assert_equal(GameState.Phase.GAMEPLAY, GameState.current_phase, "Finish deployment should advance P2 to GAMEPLAY.")
	_cleanup_screen(p2_screen)

func _test_ai_player_deploys_and_skips_p2_phase() -> void:
	_reset_state(GameState.Phase.DEPLOYMENT_P1)
	_configure_ai_deployment_fixture()

	var screen := _spawn_screen()
	_select_unit_by_id(screen, "p1_plt")
	screen._on_hex_selected(0, 0)
	var p1_deployments: Dictionary = GameState.players[0].get("deployments", {})
	_assert_true(p1_deployments.has("0,0"), "Expected P1 fixture unit to deploy before AI handoff. status=%s" % String(screen.status_label.text))
	screen._on_finish_deployment_pressed()

	var ai_deployments: Dictionary = GameState.players[1].get("deployments", {})
	_assert_equal(GameState.Phase.GAMEPLAY, GameState.current_phase, "Submitting P1 should run AI deployment and skip the manual P2 phase. status=%s" % String(screen.status_label.text))
	_assert_true(ai_deployments.has("1,0"), "Expected AI deployments to use Player 2 territory.")
	_assert_equal(2, _deployment_units_at_hex(ai_deployments, "1,0").size(), "Expected AI deployment to stack legal companies on the available Player 2 hex.")

	_cleanup_screen(screen)

func _test_ai_deployment_requires_player_two_territory() -> void:
	_reset_state(GameState.Phase.DEPLOYMENT_P1)
	_configure_ai_deployment_fixture()
	GameState.territory_map = {
		"0,0": GameState.TerritoryOwnership.PLAYER_1
	}

	var screen := _spawn_screen()
	_select_unit_by_id(screen, "p1_plt")
	screen._on_hex_selected(0, 0)
	var p1_deployments: Dictionary = GameState.players[0].get("deployments", {})
	_assert_true(p1_deployments.has("0,0"), "Expected P1 fixture unit to deploy before missing-territory AI handoff. status=%s" % String(screen.status_label.text))
	screen._on_finish_deployment_pressed()

	var ai_deployments: Dictionary = GameState.players[1].get("deployments", {})
	_assert_equal(GameState.Phase.DEPLOYMENT_P1, GameState.current_phase, "AI deployment should not enter gameplay when Player 2 has no legal territory.")
	_assert_true(ai_deployments.is_empty(), "AI deployments should remain empty when no legal Player 2 hex exists.")
	_assert_true(String(screen.status_label.text).contains("Player 2 needs at least one owned deployment hex"), "Expected blocked AI deployment status to explain the missing Player 2 territory.")

	_cleanup_screen(screen)

func _test_ai_rejects_partial_deployment_transaction() -> void:
	_reset_state(GameState.Phase.DEPLOYMENT_P2)
	GameState.territory_map = {"0,0": GameState.TerritoryOwnership.PLAYER_1, "1,0": GameState.TerritoryOwnership.PLAYER_2}
	GameState.terrain_map = {"0,0": "light", "1,0": "light"}
	var companies: Array = []
	for index in range(5):
		companies.append(_company("capacity_company_%d" % index, "Capacity Company %d" % index))
	var player_two := GameState.players[1] as Dictionary
	player_two["division_tree"] = _root_with_children(companies)
	player_two["deployments"] = {}
	player_two["controller"] = "ai"
	GameState.players[1] = player_two
	var result := DeploymentAIService.run_for_player(1)
	_assert_false(bool(result.get("ok", true)), "AI deployment should fail when any formation cannot be placed")
	_assert_equal("partial_plan", String(result.get("reason", "")), "Capacity failure should be reported as a partial plan")
	_assert_true((GameState.players[1].get("deployments", {}) as Dictionary).is_empty(), "A partial AI plan must not commit any placements")
	_assert_true(not (result.get("candidate_deployments", {}) as Dictionary).is_empty(), "Partial-plan diagnostics should retain the candidate placements")
	_assert_true(not (result.get("unplaced_elements", []) as Array).is_empty(), "Partial-plan diagnostics should identify every unplaced formation")

func _test_starting_scenario_payload_preserves_only_player_deployment() -> void:
	_reset_state(GameState.Phase.DEPLOYMENT_P1)
	GameState.set_runtime_map_dimensions(16, 16)
	GameState.terrain_map = {"0,0": "woods"}
	GameState.key_objectives = {"0,0": {"priority": "primary"}}
	GameState.territory_map = {
		"0,0": GameState.TerritoryOwnership.PLAYER_1,
		"1,0": GameState.TerritoryOwnership.PLAYER_2
	}
	GameState.players[0]["division_tree"] = _root_with_children([_platoon("scenario_p1", "Scenario P1")])
	GameState.players[0]["deployments"] = {"0,0": _platoon("scenario_p1", "Scenario P1")}
	GameState.players[1]["division_tree"] = _root_with_children([_platoon("scenario_p2", "Scenario P2")])
	GameState.players[1]["deployments"] = {"1,0": _platoon("scenario_p2", "Scenario P2")}
	var screen := _spawn_screen()
	_assert_false(screen.save_scenario_button.visible, "Normal deployment should defer scenario creation to the dedicated two-sided editor")
	var payload: Dictionary = screen._build_starting_scenario_payload("Partial setup")
	var players := payload.get("players", []) as Array
	_assert_equal(2, players.size(), "Scenario payload should include both selected force structures")
	if players.size() == 2:
		_assert_true(not ((players[0] as Dictionary).get("deployments", {}) as Dictionary).is_empty(), "Scenario payload should preserve Player 1 placements")
		_assert_true(((players[1] as Dictionary).get("deployments", {}) as Dictionary).is_empty(), "Scenario payload should always remove AI placements")
		_assert_equal("ai", String((players[1] as Dictionary).get("controller", "")), "Scenario payload should identify Player 2 as AI controlled")
	_assert_equal({"0,0": "woods"}, payload.get("terrain", {}), "Scenario payload should preserve map terrain")
	_assert_equal(GameState.key_objectives, payload.get("objectives", {}), "Scenario payload should preserve objective metadata")

	var malformed_payload := payload.duplicate(true)
	malformed_payload["objectives"] = []
	_assert_false(SaveManager.save_scenario("Malformed Objectives Integration", malformed_payload), "Scenario saves should reject objective data with the wrong field type")

	var incomplete_payload := payload.duplicate(true)
	incomplete_payload.erase("objectives")
	_assert_false(SaveManager.save_scenario("Incomplete Objectives Integration", incomplete_payload), "Scenario saves should reject payloads that omit required objectives")

	var invalid_terrain_payload := payload.duplicate(true)
	invalid_terrain_payload["terrain"] = {"0,0": "lava"}
	_assert_false(SaveManager.save_scenario("Invalid Terrain Integration", invalid_terrain_payload), "Scenario saves should reject invalid current-schema terrain IDs")

	var out_of_bounds_payload := payload.duplicate(true)
	out_of_bounds_payload["terrain"] = {"16,0": "light"}
	_assert_false(SaveManager.save_scenario("Out Of Bounds Integration", out_of_bounds_payload), "Scenario saves should reject coordinates outside the declared grid")
	_cleanup_screen(screen)

	_reset_state(GameState.Phase.DEPLOYMENT_P2)
	var p2_screen := _spawn_screen()
	_assert_false(p2_screen.save_scenario_button.visible, "Player 2 deployment should not expose starting-scenario saving")
	_cleanup_screen(p2_screen)

func _test_default_battalion_headquarters_hierarchy() -> void:
	_reset_state(GameState.Phase.DEPLOYMENT_P1)
	var screen := _spawn_screen()
	var fallback_tree := screen._default_division_tree(0) as Dictionary
	var battalion := _find_dictionary_unit(fallback_tree, "P1_infantry_bn")
	_assert_false(battalion.is_empty(), "The fallback structure should contain its infantry battalion")
	if battalion.is_empty():
		_cleanup_screen(screen)
		return
	var direct_children := battalion.get("children", []) as Array
	_assert_equal(5, direct_children.size(), "The fallback U.S.-style battalion should contain five direct companies")
	_assert_true(_find_dictionary_unit(battalion, "P1_bn_hq").is_empty(), "The fallback battalion should not contain a standalone Battalion Headquarters section")
	var headquarters_company := _find_dictionary_unit(battalion, "P1_hq_company")
	_assert_false(headquarters_company.is_empty(), "The fallback battalion should retain Headquarters Company")
	if not headquarters_company.is_empty():
		var hq_children := headquarters_company.get("children", []) as Array
		_assert_equal(2, hq_children.size(), "Fallback Headquarters Company should contain exactly two subordinates")
		_assert_false(_find_dictionary_unit(headquarters_company, "P1_bn_hq_section").is_empty(), "Fallback Headquarters Company should contain the Battalion HQ Section")
		_assert_false(_find_dictionary_unit(headquarters_company, "P1_antitank_platoon").is_empty(), "Fallback Headquarters Company should contain the Antitank Platoon")
		_assert_true(_find_dictionary_unit(headquarters_company, "P1_hq_company_hq").is_empty(), "Fallback Headquarters Company should not contain a redundant Company HQ section")
	_cleanup_screen(screen)

func _test_ai_deployments_hydrate_gameplay_units() -> void:
	_reset_state(GameState.Phase.DEPLOYMENT_P1)
	_configure_ai_deployment_fixture()

	var deployment_screen := _spawn_screen()
	_select_unit_by_id(deployment_screen, "p1_plt")
	deployment_screen._on_hex_selected(0, 0)
	deployment_screen._on_finish_deployment_pressed()
	_cleanup_screen(deployment_screen)

	var gameplay_screen: Control = GAMEPLAY_SCREEN_SCENE.instantiate()
	get_tree().root.add_child(gameplay_screen)
	_assert_equal(2, _gameplay_unit_count_for_owner(1), "Expected AI deployments to hydrate as Player 2 gameplay units.")
	_cleanup_screen(gameplay_screen)

func _test_ai_covers_wide_front_with_adaptive_platoons() -> void:
	_reset_state(GameState.Phase.DEPLOYMENT_P2)
	var companies: Array = []
	for company_index in range(3):
		companies.append(_company_with_platoons("wide_co_%d" % company_index, 3))
	_configure_linear_ai_front(9, companies)

	var result := DeploymentAIService.run_for_player(1)
	var deployments := result.get("deployments", {}) as Dictionary
	var frontage := ((result.get("plan", {}) as Dictionary).get("metadata", {}) as Dictionary).get("frontage", {}) as Dictionary
	var decomposition := ((result.get("plan", {}) as Dictionary).get("metadata", {}) as Dictionary).get("decomposition", {}) as Dictionary

	_assert_true(bool(result.get("ok", false)), "Expected the AI to create a legal wide-front deployment.")
	_assert_equal(9, deployments.size(), "Expected one occupied AI hex across every frontline position.")
	_assert_equal(9, int(frontage.get("coveredFrontlineHexes", -1)), "Expected frontage metadata to report complete coverage.")
	_assert_equal(0, int(frontage.get("manpowerShortfall", -1)), "Expected no frontage shortfall with nine available platoons.")
	_assert_equal(9, int(decomposition.get("selectedCombatElements", -1)), "Expected companies to split adaptively into nine platoons.")
	for q in range(9):
		var units := _deployment_units_at_hex(deployments, "%d,1" % q)
		_assert_equal(1, units.size(), "Expected coverage-first placement to avoid stacking before the front is full at q=%d." % q)
		if not units.is_empty():
			_assert_equal("platoon", String(units[0].get("size", "")), "Expected lower-tier platoons, not intact companies, on the wide front.")

func _test_ai_manages_frontline_shortfall_without_large_gaps() -> void:
	_reset_state(GameState.Phase.DEPLOYMENT_P2)
	var companies: Array = [
		_company_with_platoons("short_co_0", 3),
		_company_with_platoons("short_co_1", 3)
	]
	_configure_linear_ai_front(9, companies)

	var result := DeploymentAIService.run_for_player(1)
	var deployments := result.get("deployments", {}) as Dictionary
	var frontage := ((result.get("plan", {}) as Dictionary).get("metadata", {}) as Dictionary).get("frontage", {}) as Dictionary

	_assert_true(bool(result.get("ok", false)), "Expected insufficient forces to produce a best-effort deployment, not an AI failure.")
	_assert_equal(6, deployments.size(), "Expected all six real platoons to occupy distinct frontage hexes.")
	_assert_false(bool(frontage.get("coverageComplete", true)), "Expected frontage metadata to identify incomplete coverage.")
	_assert_equal(3, int(frontage.get("manpowerShortfall", -1)), "Expected the shortfall to equal the three unoccupied frontage hexes.")
	_assert_true(int(frontage.get("maximumUncoveredDistance", 99)) <= 1, "Expected gap-aware placement to keep every empty hex adjacent to a covered position.")
	var previous_was_empty := false
	for q in range(9):
		var is_empty := _deployment_units_at_hex(deployments, "%d,1" % q).is_empty()
		_assert_false(previous_was_empty and is_empty, "Expected no two consecutive empty hexes in the best-effort frontage screen.")
		previous_was_empty = is_empty

func _test_ai_reinforces_exposed_terrain_after_coverage() -> void:
	_reset_state(GameState.Phase.DEPLOYMENT_P2)
	_configure_linear_ai_front(2, [
		_company("reinforce_co_0", "Reinforcement Company 0"),
		_company("reinforce_co_1", "Reinforcement Company 1"),
		_company("reinforce_co_2", "Reinforcement Company 2")
	])
	GameState.terrain_map["0,1"] = "light"
	GameState.terrain_map["1,1"] = "woods"

	var result := DeploymentAIService.run_for_player(1)
	var deployments := result.get("deployments", {}) as Dictionary

	_assert_true(bool(result.get("ok", false)), "Expected the AI to place all companies in the terrain reinforcement scenario.")
	_assert_equal(2, deployments.size(), "Expected both frontline hexes to be covered before reinforcement.")
	_assert_equal(2, _deployment_units_at_hex(deployments, "0,1").size(), "Expected the extra company to reinforce the more exposed open approach.")
	_assert_equal(1, _deployment_units_at_hex(deployments, "1,1").size(), "Expected the protected rough hex to retain its initial covering company.")

func _test_ai_attaches_weapons_formations_to_combat_stacks() -> void:
	_reset_state(GameState.Phase.DEPLOYMENT_P2)
	var weapons_platoon := _platoon("weapons_plt", "Weapons Platoon")
	weapons_platoon["role"] = "weapons"
	weapons_platoon["type"] = "infantry"
	_configure_linear_ai_front(2, [
		_company("support_co_0", "A Company"),
		_company("support_co_1", "B Company"),
		weapons_platoon
	])

	var result := DeploymentAIService.run_for_player(1)
	var deployments := result.get("deployments", {}) as Dictionary
	var found_weapons := false
	var weapons_has_combat_partner := false
	for hex_id in deployments.keys():
		var deployed_units := _deployment_units_at_hex(deployments, String(hex_id))
		for unit_variant in deployed_units:
			var unit := unit_variant as Dictionary
			if String(unit.get("id", "")) != "weapons_plt":
				continue
			found_weapons = true
			weapons_has_combat_partner = deployed_units.any(func(other: Dictionary) -> bool:
				return String(other.get("id", "")) != "weapons_plt"
			)
	_assert_true(bool(result.get("ok", false)), "Expected the AI to produce a deployment containing a weapons formation.")
	_assert_true(found_weapons, "Expected the AI to retain and deploy its weapons platoon as support.")
	_assert_true(weapons_has_combat_partner, "Weapons formations should attach to a combat stack when one has support capacity.")

func _test_ai_spreads_unplanned_combat_units_without_objectives() -> void:
	_reset_state(GameState.Phase.DEPLOYMENT_P2)
	var companies: Array = []
	var elements: Array[Dictionary] = []
	for company_index in range(8):
		var company := _company("fallback_co_%d" % company_index, "Fallback Company %d" % company_index)
		companies.append(company)
		elements.append(company)
	GameState.territory_map = {}
	GameState.terrain_map = {}
	for q in range(4):
		GameState.territory_map["%d,0" % q] = GameState.TerritoryOwnership.PLAYER_1
		GameState.terrain_map["%d,0" % q] = "light"
		for r in range(1, 4):
			GameState.territory_map["%d,%d" % [q, r]] = GameState.TerritoryOwnership.PLAYER_2
			GameState.terrain_map["%d,%d" % [q, r]] = "light"
	var player_two := GameState.players[1] as Dictionary
	player_two["division_tree"] = _root_with_children(companies)
	GameState.players[1] = player_two
	var sector_model := MapAnalyzer.build_sector_model(
		GameState.territory_map,
		GameState.terrain_map,
		GameState.TerritoryOwnership.PLAYER_2,
		GameState.TerritoryOwnership.PLAYER_1
	)
	var plan := {"orders": []}
	var deployments := DeploymentAIService._deployments_from_plan(1, elements, plan, sector_model)

	_assert_equal(4, deployments.size(), "Objective-free fallback should spread combat formations across the full front.")
	for q in range(4):
		_assert_equal(2, _deployment_units_at_hex(deployments, "%d,1" % q).size(), "Objective-free fallback should balance excess companies instead of doom-stacking one coordinate.")
	for r in range(2, 4):
		for q in range(4):
			_assert_equal(0, _deployment_units_at_hex(deployments, "%d,%d" % [q, r]).size(), "Unplanned combat formations should prefer the frontline over an arbitrary rear hex.")
	_assert_equal(8, (plan.get("fallbackPlacements", []) as Array).size(), "Fallback placements should be explicit in AI plan diagnostics.")
	_assert_equal(0, (plan.get("unplacedElements", []) as Array).size(), "Every legal fallback company should be accounted for.")

func _test_ai_balances_reinforcements_across_authored_objectives() -> void:
	_reset_state(GameState.Phase.DEPLOYMENT_P2)
	var companies: Array = []
	for company_index in range(12):
		companies.append(_company("objective_co_%d" % company_index, "Objective Company %d" % company_index))
	_configure_linear_ai_front(6, companies)
	GameState.key_objectives = {
		"0,1": {"priority": "primary"},
		"5,0": {"priority": "secondary"}
	}

	var classified := DeploymentAIService._deployment_objectives(1)
	_assert_equal(2, classified.size(), "Every authored objective should reach deployment analysis")
	_assert_equal("defend", String(classified[0].get("type", "")), "An AI-owned objective should be classified as defensive")
	_assert_equal(2, int(classified[0].get("priority", 0)), "A primary objective should receive the larger allocation weight")
	_assert_equal("attack", String(classified[1].get("type", "")), "An enemy-owned objective should be classified as an attack direction")

	var result := DeploymentAIService.run_for_player(1)
	var deployments := result.get("deployments", {}) as Dictionary
	var plan := result.get("plan", {}) as Dictionary
	_assert_true(bool(result.get("ok", false)), "Objective-aware AI should produce a legal deployment")
	for q in range(6):
		_assert_true(not _deployment_units_at_hex(deployments, "%d,1" % q).is_empty(), "Objective allocation should cover the full frontage before concentrating at q=%d" % q)
	var left_reinforcements := maxi(_deployment_units_at_hex(deployments, "0,1").size() - 1, 0) + maxi(_deployment_units_at_hex(deployments, "1,1").size() - 1, 0)
	var right_reinforcements := maxi(_deployment_units_at_hex(deployments, "4,1").size() - 1, 0) + maxi(_deployment_units_at_hex(deployments, "5,1").size() - 1, 0)
	_assert_true(left_reinforcements > 0, "Surplus forces should reinforce the AI-owned primary objective axis")
	_assert_true(right_reinforcements > 0, "Surplus forces should also reinforce the hostile objective axis")
	var objective_orders := (plan.get("orders", []) as Array).filter(func(order: Dictionary) -> bool: return not String(order.get("objectiveId", "")).is_empty())
	_assert_true(objective_orders.size() >= 2, "Deployment diagnostics should retain each reinforcement objective assignment")
	_assert_equal(classified, (plan.get("metadata", {}) as Dictionary).get("objectives", []), "Plan metadata should preserve objective classification for diagnostics")
	var debug_entry := GameState.deployment_ai_debug.get("player_1", {}) as Dictionary
	var replay := AITraceReplay.replay_trace(debug_entry)
	_assert_true(bool(replay.get("ok", false)), "An objective-aware deployment trace should remain replayable")
	var replay_summary := (replay.get("diff", {}) as Dictionary).get("summary", {}) as Dictionary
	_assert_equal(0, int(replay_summary.get("different_orders", -1)), "Objective-aware trace replay should reproduce the same deployment orders")

func _test_ai_trace_json_is_pretty_printed() -> void:
	var trace_id := "pretty_trace_integration_%d" % Time.get_ticks_usec()
	var line_entry := "trace-line-%s" % trace_id
	var trace := {
		"trace_id": trace_id,
		"turn": 1,
		"player_id": 1,
		"phase": "deployment_ai",
		"debug_level": 2,
		"events": [{"type": "candidate_scored", "meta": {"objectiveId": "objective_0_1"}}],
		"line_entries": [line_entry]
	}
	_assert_true(SaveManager.save_ai_trace(trace), "AI trace fixture should save successfully")
	var matching_file := ""
	for trace_file in SaveManager.list_ai_traces():
		if String(trace_file).contains(trace_id):
			matching_file = String(trace_file)
			break
	_assert_true(not matching_file.is_empty(), "The saved AI trace should remain indexed")
	if matching_file.is_empty():
		return
	var file := FileAccess.open("%s/%s" % [SaveManager.AI_DEBUG_DIR, matching_file], FileAccess.READ)
	_assert_true(file != null, "The saved AI trace should be readable")
	if file == null:
		return
	var text := file.get_as_text()
	_assert_true(text.contains("\n  \""), "AI trace JSON should use two-space indentation across multiple lines")
	_assert_true(text.ends_with("\n"), "AI trace JSON should end with a trailing newline")
	_assert_true(JSON.parse_string(text) is Dictionary, "Pretty-printed AI trace JSON should remain parseable")

	var index := _read_test_json(SaveManager.AI_TRACE_INDEX_PATH)
	_assert_equal(SaveManager.AI_TRACE_INDEX_VERSION, int(index.get("version", -1)), "AI trace index should use the current schema version")
	var matching_metadata := _trace_metadata_for_id(index, trace_id)
	_assert_false(matching_metadata.is_empty(), "Current trace metadata should be present in the index")
	_assert_false(matching_metadata.has("player"), "Current trace metadata should not write the retired player field")
	for numeric_field in ["timestamp", "turn", "player_id", "debug_level", "size_bytes"]:
		var numeric_value: Variant = matching_metadata.get(numeric_field)
		_assert_true(numeric_value is int or numeric_value is float, "Trace metadata field %s should remain numeric" % numeric_field)
	var line_log := FileAccess.open(SaveManager.AI_TRACE_LINE_LOG_PATH, FileAccess.READ)
	_assert_true(line_log != null and line_log.get_as_text().contains(line_entry), "AI trace line entries should append to the shared line log")

func _test_ai_trace_legacy_index_is_reset() -> void:
	var legacy_trace_file := "ai_trace_1_legacy.json"
	var legacy_temp_file := "ai_trace_1_legacy.json.tmp"
	var unrelated_file := "keep_me.txt"
	_assert_true(_write_test_text("%s/%s" % [SaveManager.AI_DEBUG_DIR, legacy_trace_file], "{}"), "Legacy trace fixture should be writable")
	_assert_true(_write_test_text("%s/%s" % [SaveManager.AI_DEBUG_DIR, legacy_temp_file], "temporary"), "Legacy trace temporary fixture should be writable")
	_assert_true(_write_test_text(SaveManager.AI_TRACE_LINE_LOG_PATH, "legacy line\n"), "Legacy line log fixture should be writable")
	_assert_true(_write_test_text("%s/%s" % [SaveManager.AI_DEBUG_DIR, unrelated_file], "preserve"), "Unrelated debug-directory fixture should be writable")
	var legacy_index := {
		"version": 1,
		"traces": [{
			"file": legacy_trace_file,
			"timestamp": 1,
			"trace_id": "legacy",
			"turn": 1,
			"player": "1",
			"phase": "deployment_ai",
			"debug_level": "L2",
			"size_bytes": 2
		}]
	}
	_assert_true(_write_test_text(SaveManager.AI_TRACE_INDEX_PATH, JSON.stringify(legacy_index)), "Legacy AI trace index fixture should be writable")

	var trace_id := "legacy_reset_%d" % Time.get_ticks_usec()
	_assert_true(SaveManager.save_ai_trace(_ai_trace_fixture(trace_id)), "A legacy index should be reset without dropping the triggering trace")
	_assert_false(FileAccess.file_exists("%s/%s" % [SaveManager.AI_DEBUG_DIR, legacy_trace_file]), "Reset should remove legacy generated trace files")
	_assert_false(FileAccess.file_exists("%s/%s" % [SaveManager.AI_DEBUG_DIR, legacy_temp_file]), "Reset should remove abandoned generated temporary files")
	_assert_true(FileAccess.file_exists("%s/%s" % [SaveManager.AI_DEBUG_DIR, unrelated_file]), "Reset should preserve unrelated files in the debug directory")
	var rebuilt_index := _read_test_json(SaveManager.AI_TRACE_INDEX_PATH)
	_assert_equal(SaveManager.AI_TRACE_INDEX_VERSION, int(rebuilt_index.get("version", -1)), "Legacy index reset should write the current version")
	_assert_equal(1, (rebuilt_index.get("traces", []) as Array).size(), "Rebuilt index should contain only the triggering trace")
	_assert_false(_trace_metadata_for_id(rebuilt_index, trace_id).is_empty(), "Triggering trace should remain indexed after legacy reset")

func _test_ai_trace_malformed_index_recovers_with_retention() -> void:
	var traces_before := SaveManager.list_ai_traces()
	_assert_true(not traces_before.is_empty(), "Legacy reset fixture should leave a trace available for malformed-index recovery")
	var previously_indexed_path := "%s/%s" % [SaveManager.AI_DEBUG_DIR, traces_before[0]]
	_assert_true(_write_test_text(SaveManager.AI_TRACE_INDEX_PATH, "{malformed"), "Malformed AI trace index fixture should be writable")
	var first_trace_id := "malformed_reset_a_%d" % Time.get_ticks_usec()
	var first_trace := _ai_trace_fixture(first_trace_id)
	first_trace["retention_max_files"] = 1
	_assert_true(SaveManager.save_ai_trace(first_trace), "Malformed index should be reset without dropping the triggering trace")
	_assert_false(FileAccess.file_exists(previously_indexed_path), "Malformed-index reset should discard old generated traces")
	var second_trace_id := "malformed_reset_b_%d" % Time.get_ticks_usec()
	var second_trace := _ai_trace_fixture(second_trace_id)
	second_trace["retention_max_files"] = 1
	_assert_true(SaveManager.save_ai_trace(second_trace), "Trace saving should continue after malformed-index recovery")
	var retained_traces := SaveManager.list_ai_traces()
	_assert_equal(1, retained_traces.size(), "Retention should still apply to a rebuilt index")
	var retained_index := _read_test_json(SaveManager.AI_TRACE_INDEX_PATH)
	_assert_equal(1, (retained_index.get("traces", []) as Array).size(), "Rebuilt index retention should match the trace files on disk")

func _ai_trace_fixture(trace_id: String) -> Dictionary:
	return {
		"trace_id": trace_id,
		"turn": 1,
		"player_id": 1,
		"phase": "deployment_ai",
		"debug_level": 2,
		"events": []
	}

func _trace_metadata_for_id(index: Dictionary, trace_id: String) -> Dictionary:
	for metadata_variant in index.get("traces", []) as Array:
		if metadata_variant is Dictionary and String((metadata_variant as Dictionary).get("trace_id", "")) == trace_id:
			return metadata_variant as Dictionary
	return {}

func _read_test_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}

func _write_test_text(path: String, contents: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(contents)
	var write_error := file.get_error()
	file.close()
	return write_error == OK

func _test_finish_deployment_requires_all_deployable_units() -> void:
	_reset_state(GameState.Phase.DEPLOYMENT_P1)
	GameState.territory_map = {
		"0,0": GameState.TerritoryOwnership.PLAYER_1,
		"0,1": GameState.TerritoryOwnership.PLAYER_1
	}
	var platoon_a := _platoon("plt_a", "Platoon A")
	var platoon_b := _platoon("plt_b", "Platoon B")
	GameState.players[0]["division_tree"] = _root_with_children([platoon_a, platoon_b])

	var screen := _spawn_screen()
	_select_unit_by_id(screen, "plt_a")
	screen._on_hex_selected(0, 0)
	screen._on_finish_deployment_pressed()

	_assert_equal(GameState.Phase.DEPLOYMENT_P1, GameState.current_phase, "Finish deployment should not advance phase until all deployable units are placed.")
	_assert_true(String(screen.status_label.text).contains("Place all deployable units before submitting"), "Expected finish action to explain why submission was blocked.")

	var missing_item := _find_item_by_unit_id(screen.unit_list.get_root(), "plt_b")
	_assert_true(missing_item != null, "Expected missing deployable unit to remain visible in deployment tree.")
	if missing_item != null:
		_assert_true(missing_item.get_custom_color(0) == Color(1.0, 0.35, 0.35), "Expected unplaced deployable unit to be highlighted in the sidebar.")

	_cleanup_screen(screen)

func _test_incomplete_child_warning_propagates_to_all_ancestors() -> void:
	_reset_state(GameState.Phase.DEPLOYMENT_P1)
	GameState.territory_map = {
		"0,0": GameState.TerritoryOwnership.PLAYER_1,
		"0,1": GameState.TerritoryOwnership.PLAYER_1
	}
	var platoon_a := _platoon("hq_plt_a", "HQ Platoon A")
	var platoon_b := _platoon("hq_plt_b", "HQ Platoon B")
	var company_hq := _company("company_hq", "Company HQ")
	company_hq["type"] = "headquarters"
	company_hq["role"] = "headquarters"
	company_hq["children"] = [platoon_a, platoon_b]
	GameState.players[0]["division_tree"] = _root_with_children([company_hq])

	var screen := _spawn_screen()
	var company_hq_item := _find_item_by_unit_id(screen.unit_list.get_root(), "company_hq")
	var root_item := _find_item_by_unit_id(screen.unit_list.get_root(), "root")
	_assert_true(company_hq_item != null, "Expected the company HQ to remain visible even though it cannot deploy directly.")
	_assert_true(root_item != null, "Expected the organization root to remain visible in the deployment tree.")
	if company_hq_item != null:
		_assert_true(company_hq_item.get_custom_color(0) == screen.UNDEPLOYED_WARNING_COLOR, "A company HQ should be red while a deployable child is missing.")
	if root_item != null:
		_assert_true(root_item.get_custom_color(0) == screen.UNDEPLOYED_WARNING_COLOR, "An incomplete child warning should propagate through every ancestor.")

	_select_unit_by_id(screen, "hq_plt_a")
	screen._on_hex_selected(0, 0)
	company_hq_item = _find_item_by_unit_id(screen.unit_list.get_root(), "company_hq")
	_assert_true(company_hq_item != null and company_hq_item.get_custom_color(0) == screen.UNDEPLOYED_WARNING_COLOR, "The company HQ should remain red while another child is missing.")

	_select_unit_by_id(screen, "hq_plt_b")
	screen._on_hex_selected(0, 1)
	company_hq_item = _find_item_by_unit_id(screen.unit_list.get_root(), "company_hq")
	root_item = _find_item_by_unit_id(screen.unit_list.get_root(), "root")
	_assert_true(company_hq_item != null and company_hq_item.get_custom_color(0) != screen.UNDEPLOYED_WARNING_COLOR, "The company HQ warning should clear when every deployable child is satisfied.")
	_assert_true(root_item != null and root_item.get_custom_color(0) != screen.UNDEPLOYED_WARNING_COLOR, "Ancestor warnings should clear when the deployment branch is complete.")

	_cleanup_screen(screen)

func _test_finish_deployment_allows_subordinates_when_parent_placed() -> void:
	_reset_state(GameState.Phase.DEPLOYMENT_P1)
	GameState.territory_map = {
		"0,0": GameState.TerritoryOwnership.PLAYER_1
	}
	var platoon := _platoon("plt_a", "Platoon A")
	var company := _company("co_a", "A Company")
	company["children"] = [platoon]
	GameState.players[0]["division_tree"] = _root_with_children([company])

	var screen := _spawn_screen()
	_select_unit_by_id(screen, "co_a")
	screen._on_hex_selected(0, 0)
	screen._on_finish_deployment_pressed()

	_assert_equal(GameState.Phase.DEPLOYMENT_P2, GameState.current_phase, "Deploying a parent formation should satisfy subordinate deployment requirements.")

	_cleanup_screen(screen)

func _test_finish_deployment_allows_parent_when_all_subordinates_placed() -> void:
	_reset_state(GameState.Phase.DEPLOYMENT_P1)
	GameState.territory_map = {
		"0,0": GameState.TerritoryOwnership.PLAYER_1,
		"0,1": GameState.TerritoryOwnership.PLAYER_1
	}
	var company_a := _company("co_a", "A Company")
	var company_b := _company("co_b", "B Company")
	var battalion := _battalion("bn_1", "1st Battalion")
	battalion["children"] = [company_a, company_b]
	GameState.players[0]["division_tree"] = _root_with_children([battalion])

	var screen := _spawn_screen()
	_select_unit_by_id(screen, "co_a")
	screen._on_hex_selected(0, 0)
	_select_unit_by_id(screen, "co_b")
	screen._on_hex_selected(0, 1)

	var battalion_item := _find_item_by_unit_id(screen.unit_list.get_root(), "bn_1")
	_assert_true(battalion_item != null, "Expected battalion to remain visible in deployment tree.")
	if battalion_item != null:
		_assert_true(String(battalion_item.get_text(0)).contains("Covered by subordinates"), "Expected battalion row to show it is satisfied by subordinate placements.")

	screen._on_finish_deployment_pressed()
	_assert_equal(GameState.Phase.DEPLOYMENT_P2, GameState.current_phase, "Deploying every subordinate should satisfy parent deployment requirements.")

	_cleanup_screen(screen)

func _right_click_hex(screen: Control, column: int, row: int) -> void:
	var mouse_event := InputEventMouseButton.new()
	mouse_event.button_index = MOUSE_BUTTON_RIGHT
	mouse_event.pressed = true
	mouse_event.position = screen.hex_map_view._to_screen(screen.hex_map_view._hex_center(column, row))
	screen.hex_map_view._gui_input(mouse_event)

func _left_click_map(map_view: DeploymentHexMapView, position: Vector2) -> void:
	var press_event := InputEventMouseButton.new()
	press_event.button_index = MOUSE_BUTTON_LEFT
	press_event.pressed = true
	press_event.position = position
	map_view._gui_input(press_event)
	var release_event := InputEventMouseButton.new()
	release_event.button_index = MOUSE_BUTTON_LEFT
	release_event.pressed = false
	release_event.position = position
	map_view._gui_input(release_event)

func _double_click_map(map_view: DeploymentHexMapView, position: Vector2) -> void:
	var press_event := InputEventMouseButton.new()
	press_event.button_index = MOUSE_BUTTON_LEFT
	press_event.pressed = true
	press_event.double_click = true
	press_event.position = position
	map_view._gui_input(press_event)
	var release_event := InputEventMouseButton.new()
	release_event.button_index = MOUSE_BUTTON_LEFT
	release_event.pressed = false
	release_event.position = position
	map_view._gui_input(release_event)

func _scroll_map(map_view: DeploymentHexMapView, position: Vector2, zoom_in: bool) -> void:
	var wheel_event := InputEventMouseButton.new()
	wheel_event.button_index = MOUSE_BUTTON_WHEEL_UP if zoom_in else MOUSE_BUTTON_WHEEL_DOWN
	wheel_event.pressed = true
	wheel_event.position = position
	map_view._gui_input(wheel_event)

func _configure_ai_deployment_fixture() -> void:
	GameState.territory_map = {
		"0,0": GameState.TerritoryOwnership.PLAYER_1,
		"1,0": GameState.TerritoryOwnership.PLAYER_2
	}
	var player_one := GameState.players[0]
	player_one["division_tree"] = _root_with_children([_platoon("p1_plt", "P1 Platoon")])
	player_one["deployments"] = {}
	GameState.players[0] = player_one

	var player_two := GameState.players[1]
	player_two["division_tree"] = _root_with_children([
		_company("ai_co_a", "AI Company A"),
		_company("ai_co_b", "AI Company B")
	])
	player_two["deployments"] = {}
	player_two["controller"] = "ai"
	player_two["controller"] = "ai"
	GameState.players[1] = player_two

func _configure_linear_ai_front(front_width: int, companies: Array) -> void:
	GameState.territory_map = {}
	GameState.terrain_map = {}
	for q in range(front_width):
		GameState.territory_map["%d,0" % q] = GameState.TerritoryOwnership.PLAYER_1
		GameState.territory_map["%d,1" % q] = GameState.TerritoryOwnership.PLAYER_2
		GameState.terrain_map["%d,0" % q] = "light"
		GameState.terrain_map["%d,1" % q] = "light"
	var player_two := GameState.players[1]
	player_two["division_tree"] = _root_with_children(companies)
	player_two["deployments"] = {}
	player_two["controller"] = "ai"
	player_two["controller"] = "ai"
	GameState.players[1] = player_two

func _gameplay_unit_count_for_owner(owner: int) -> int:
	var count := 0
	for unit in GameState.gameplay_units.values():
		if typeof(unit) == TYPE_DICTIONARY and int((unit as Dictionary).get("owner", -1)) == owner:
			count += 1
	return count

func _reset_state(phase: int) -> void:
	GameState.reset()
	GameState.set_phase(phase)
	GameState.players = [
		{
			"name": "Player 1",
			"division_tree": _root_with_children([]),
			"deployments": {},
			"controller": "human"
		},
		{
			"name": "Player 2",
			"division_tree": _root_with_children([]),
			"deployments": {},
			"controller": "human"
		}
	]
	GameState.selected_nation_id = "usa"

func _spawn_screen() -> Control:
	var screen: Control = DEPLOYMENT_SCREEN_SCENE.instantiate()
	get_tree().root.add_child(screen)
	return screen

func _cleanup_screen(screen: Control) -> void:
	screen.queue_free()

func _select_unit_by_id(screen: Control, unit_id: String) -> void:
	var target_item := _find_item_by_unit_id(screen.unit_list.get_root(), unit_id)
	if target_item == null:
		_fail("Unable to find unit with id %s in unit tree." % unit_id)
		return
	var metadata: Variant = target_item.get_metadata(0)
	if typeof(metadata) != TYPE_DICTIONARY:
		_fail("Missing metadata for unit id %s." % unit_id)
		return
	screen._selected_unit_metadata = (metadata as Dictionary).duplicate(true)
	screen._selected_unit_id = unit_id

func _find_item_by_unit_id(item: TreeItem, unit_id: String) -> TreeItem:
	if item == null:
		return null
	var metadata: Variant = item.get_metadata(0)
	if typeof(metadata) == TYPE_DICTIONARY:
		if String((metadata as Dictionary).get("unit_id", "")) == unit_id:
			return item

	var child := item.get_first_child()
	while child != null:
		var found := _find_item_by_unit_id(child, unit_id)
		if found != null:
			return found
		child = child.get_next()
	return null

func _find_button_by_meta(root: Node, metadata_key: String, expected_value: String) -> Button:
	if root is Button and root.has_meta(metadata_key) and String(root.get_meta(metadata_key)) == expected_value:
		return root as Button
	for child in root.get_children():
		var found := _find_button_by_meta(child, metadata_key, expected_value)
		if found != null:
			return found
	return null

func _control_tree_text(root: Node) -> String:
	var lines: Array[String] = []
	if root is Label:
		lines.append(String((root as Label).text))
	elif root is Button:
		lines.append(String((root as Button).text))
	for child in root.get_children():
		var child_text := _control_tree_text(child)
		if not child_text.is_empty():
			lines.append(child_text)
	return "\n".join(lines)

func _find_dictionary_unit(node: Dictionary, unit_id: String) -> Dictionary:
	if String(node.get("id", "")) == unit_id:
		return node
	for child_variant in node.get("children", []) as Array:
		if not (child_variant is Dictionary):
			continue
		var found := _find_dictionary_unit(child_variant as Dictionary, unit_id)
		if not found.is_empty():
			return found
	return {}

func _root_with_children(children: Array) -> Dictionary:
	return {
		"id": "root",
		"display_name": "Root",
		"type": "infantry",
		"role": "infantry",
		"size": "army",
		"status": "alive",
		"designation": {},
		"children": children
	}

func _platoon(id: String, name: String) -> Dictionary:
	return {
		"id": id,
		"display_name": name,
		"type": "infantry",
		"role": "infantry",
		"size": "platoon",
		"status": "alive",
		"designation": {},
		"children": []
	}

func _rifle_squad(id: String, name: String) -> Dictionary:
	return {
		"id": id,
		"display_name": name,
		"type": "infantry",
		"role": "rifle",
		"size": "squad",
		"status": "alive",
		"designation": {},
		"children": []
	}

func _anti_tank_unit(id: String, name: String, size: String) -> Dictionary:
	return {
		"id": id,
		"display_name": name,
		"type": "anti_tank",
		"role": "anti_tank",
		"size": size,
		"status": "alive",
		"designation": {},
		"children": []
	}

func _company(id: String, name: String) -> Dictionary:
	return {
		"id": id,
		"display_name": name,
		"type": "infantry",
		"role": "infantry",
		"size": "company",
		"status": "alive",
		"designation": {},
		"children": []
	}

func _company_with_platoons(id: String, platoon_count: int) -> Dictionary:
	var company := _company(id, id.capitalize())
	var platoons: Array = []
	for platoon_index in range(platoon_count):
		platoons.append(_platoon("%s_plt_%d" % [id, platoon_index], "%s Platoon %d" % [id.capitalize(), platoon_index + 1]))
	company["children"] = platoons
	return company

func _battalion(id: String, name: String) -> Dictionary:
	return {
		"id": id,
		"name": name,
		"type": "infantry",
		"size": "battalion",
		"status": "alive",
		"children": []
	}

func _count_unit_id_occurrences(deployments: Dictionary, unit_id: String) -> int:
	var count := 0
	for deployment in deployments.values():
		for deployed_unit in _deployment_units_from_variant(deployment):
			if String(deployed_unit.get("id", "")) == unit_id:
				count += 1
	return count

func _deployment_units_at_hex(deployments: Dictionary, key: String) -> Array[Dictionary]:
	if not deployments.has(key):
		return []
	return _deployment_units_from_variant(deployments[key])

func _deployment_units_from_variant(deployment_variant: Variant) -> Array[Dictionary]:
	var units: Array[Dictionary] = []
	if typeof(deployment_variant) == TYPE_DICTIONARY:
		units.append(deployment_variant as Dictionary)
	elif typeof(deployment_variant) == TYPE_ARRAY:
		for unit_variant in (deployment_variant as Array):
			if typeof(unit_variant) == TYPE_DICTIONARY:
				units.append(unit_variant as Dictionary)
	return units

func _first_deployed_unit_id_at_hex(deployments: Dictionary, key: String) -> String:
	var deployed_units := _deployment_units_at_hex(deployments, key)
	if deployed_units.is_empty():
		return ""
	return String(deployed_units[0].get("id", ""))

func _assert_equal(expected: Variant, actual: Variant, message: String) -> void:
	if expected != actual:
		_fail("%s expected=%s actual=%s" % [message, var_to_str(expected), var_to_str(actual)])

func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)

func _assert_false(condition: bool, message: String) -> void:
	if condition:
		_fail(message)

func _assert_float_approx(expected: float, actual: float, message: String) -> void:
	if not is_equal_approx(expected, actual):
		_fail("%s expected=%f actual=%f" % [message, expected, actual])

func _assert_color_approx(expected: Color, actual: Color, message: String) -> void:
	if not expected.is_equal_approx(actual):
		_fail("%s expected=%s actual=%s" % [message, var_to_str(expected), var_to_str(actual)])

func _assert_vector2_approx(expected: Vector2, actual: Vector2, message: String) -> void:
	if not expected.is_equal_approx(actual):
		_fail("%s expected=%s actual=%s" % [message, var_to_str(expected), var_to_str(actual)])

func _fail(message: String) -> void:
	_failures.append(message)
