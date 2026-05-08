extends Node

const DEPLOYMENT_SCREEN_SCENE := preload("res://scenes/deployment/DeploymentScreen.tscn")

var _failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	await get_tree().process_frame
	_test_replacing_same_unit_keeps_single_deployment_entry()
	_test_right_click_undeploys_all_units_on_hex()
	_test_four_companies_can_stack_on_one_hex()
	_test_occupied_hex_replacement_still_respects_validation_rules()
	_test_deployed_battalion_can_move_after_company_deployment()
	_test_tree_model_is_hierarchical_and_collapsed_by_default()
	_test_non_deployable_units_stay_blocked()
	_test_finish_deployment_requires_all_deployable_units()
	_test_finish_deployment_allows_subordinates_when_parent_placed()
	_test_same_hex_subordinate_deployment_is_blocked_when_parent_placed()
	_test_finish_deployment_phase_transitions()

	if _failures.is_empty():
		print("DeploymentScreen integration tests passed.")
		get_tree().quit(0)
		return

	for failure in _failures:
		push_error(failure)
	get_tree().quit(1)

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

	_right_click_hex(screen, 0, 0)
	_assert_true(String(screen.status_label.text).contains("No deployed units at 0,0"), "Expected empty hex right-click to explain that nothing was undeployed.")

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
	_assert_equal(1, _deployment_units_at_hex(deployments, "0,0").size(), "Expected parent to remain deployed on original hex.")
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
	_assert_true(String(screen.status_label.text).contains("already covered"), "Expected status to explain that same-hex parent placement is already covered by subordinate.")

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

func _right_click_hex(screen: Control, column: int, row: int) -> void:
	var mouse_event := InputEventMouseButton.new()
	mouse_event.button_index = MOUSE_BUTTON_RIGHT
	mouse_event.pressed = true
	mouse_event.position = screen.hex_map_view._hex_center(column, row) + screen.hex_map_view.pan_offset
	screen.hex_map_view._gui_input(mouse_event)

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

func _root_with_children(children: Array) -> Dictionary:
	return {
		"id": "root",
		"name": "Root",
		"type": "infantry",
		"size": "army",
		"status": "alive",
		"children": children
	}

func _platoon(id: String, name: String) -> Dictionary:
	return {
		"id": id,
		"name": name,
		"type": "infantry",
		"size": "platoon",
		"status": "alive",
		"children": []
	}

func _company(id: String, name: String) -> Dictionary:
	return {
		"id": id,
		"name": name,
		"type": "infantry",
		"size": "company",
		"status": "alive",
		"children": []
	}

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

func _fail(message: String) -> void:
	_failures.append(message)
