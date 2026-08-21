extends Node

const GameplayAIService = preload("res://scripts/systems/gameplay_ai/GameplayAIService.gd")
const OrderSystem = preload("res://scripts/systems/OrderSystem.gd")
const Pathfinding = preload("res://scripts/systems/Pathfinding.gd")
const FormationPosturePlanner = preload("res://scripts/systems/gameplay_ai/FormationPosturePlanner.gd")
const ReconSystem = preload("res://scripts/systems/ReconSystem.gd")
const OperationalAIService = preload("res://scripts/systems/operational_ai/OperationalAIService.gd")
const DeploymentDataConverter = preload("res://scripts/domain/deployment_ai/DeploymentDataConverter.gd")
const OperationalMapAnalyzer = preload("res://scripts/systems/operational_ai/OperationalMapAnalyzer.gd")

var _failures: Array[String] = []
var _game_state: Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	await get_tree().process_frame
	_game_state = get_node("/root/GameState")
	_configure_small_map()
	_test_adjacent_enemy_generates_legal_attack_order()
	_test_threatened_unit_generates_legal_dig_in_order()
	_test_unthreatened_unit_generates_legal_move_order()
	_test_hidden_enemy_does_not_trigger_threat_response()
	_test_scouted_enemy_can_trigger_threat_response()
	_test_mismatched_operational_snapshot_is_ignored_for_movement()
	_test_primary_objective_concentrates_same_parent_platoons()
	_test_defensive_doctrine_breaks_company_down_for_frontage()
	_test_battalion_recursively_breaks_down_to_platoons()
	_test_reorganization_cooldown_prevents_immediate_reversal()
	_test_formation_assignment_precedes_generic_movement()
	_test_projected_destinations_allow_legal_concentration_stack()
	_test_concentration_fills_objective_then_adjacent_ring()
	_test_hex_distance_matches_odd_row_grid()
	_test_ai_hex_adjacency_matches_odd_row_grid_on_both_parities()
	_test_movement_preview_reports_illegal_final_stack()
	_test_enemy_contact_memory_decays_without_tracking_hidden_movement()
	_test_operational_snapshot_uses_authored_objectives_and_remembered_contacts()

	if _failures.is_empty():
		print("GameplayAIService tests passed.")
		get_tree().quit(0)
		return

	for failure in _failures:
		push_error(failure)
	get_tree().quit(1)

func _configure_small_map() -> void:
	_game_state.call("reset")
	_game_state.set("players", [
		{"name": "Human", "controller": "human"},
		{"name": "AI", "controller": "ai"}
	])
	_game_state.set("active_player", 1)
	_game_state.call("set_runtime_map_dimensions", 5, 3)
	_game_state.set("terrain_map", {
		"0,0": "light", "1,0": "road", "2,0": "road", "3,0": "light", "4,0": "light",
		"0,1": "light", "1,1": "light", "2,1": "light", "3,1": "light", "4,1": "light",
		"0,2": "light", "1,2": "light", "2,2": "light", "3,2": "light", "4,2": "light"
	})
	_game_state.set("operational_ai_state", {
		"playerIndex": 1,
		"snapshot": {
			"sectors": [{"frontlineHexIds": ["2,0"], "objectiveHexIds": ["2,1"], "contestedHexIds": []}],
			"enemyAdjacentHexes": []
		}
	})

func _test_adjacent_enemy_generates_legal_attack_order() -> void:
	var units := {
		"ai_attacker": _unit("ai_attacker", 1, Vector2i(1, 1)),
		"enemy_adjacent": _unit("enemy_adjacent", 0, Vector2i(2, 1))
	}
	var orders := GameplayAIService.generate_orders(units, 1, _game_state.get("terrain_map"), _game_state.get("operational_ai_state"), {"trace_id": "attack_test", "rng_seed": 101})
	_assert_equal(1, orders.size(), "AI should create one attack order")
	var order := orders.get("ai_attacker", {}) as Dictionary
	_assert_equal(OrderSystem.OrderType.ATTACK, int(order.get("type", -1)), "Adjacent enemy should produce ATTACK")
	_assert_equal("enemy_adjacent", String(order.get("target_unit_id", "")), "Attack should target adjacent enemy")
	_assert_true(Pathfinding.are_adjacent(units["ai_attacker"].get("hex", Vector2i.ZERO), units["enemy_adjacent"].get("hex", Vector2i.ZERO)), "Attack order target should be adjacent and legal")

func _test_threatened_unit_generates_legal_dig_in_order() -> void:
	var units := {
		"ai_defender": _unit("ai_defender", 1, Vector2i(0, 0)),
		"enemy_nearby": _unit("enemy_nearby", 0, Vector2i(2, 0))
	}
	var orders := GameplayAIService.generate_orders(units, 1, _game_state.get("terrain_map"), _game_state.get("operational_ai_state"), {
		"trace_id": "dig_test",
		"rng_seed": 202,
		"scout_intel": {"__unitIntelById": {"enemy_nearby": {"presenceKnown": true}}}
	})
	_assert_equal(1, orders.size(), "AI should create one dig-in order")
	var order := orders.get("ai_defender", {}) as Dictionary
	_assert_equal(OrderSystem.OrderType.DIG_IN, int(order.get("type", -1)), "Threatened unit should produce DIG_IN")
	_assert_true((order.get("path", []) as Array).is_empty(), "Dig-in order should not require movement")

func _test_unthreatened_unit_generates_legal_move_order() -> void:
	var units := {
		"ai_mover": _unit("ai_mover", 1, Vector2i(0, 0)),
		"enemy_far": _unit("enemy_far", 0, Vector2i(4, 0))
	}
	var orders := GameplayAIService.generate_orders(units, 1, _game_state.get("terrain_map"), _game_state.get("operational_ai_state"), {"trace_id": "move_test", "rng_seed": 303})
	_assert_equal(1, orders.size(), "AI should create one move order")
	var order := orders.get("ai_mover", {}) as Dictionary
	_assert_equal(OrderSystem.OrderType.MOVE, int(order.get("type", -1)), "Unthreatened unit should produce MOVE")
	var path := order.get("path", []) as Array
	_assert_true(path.size() >= 2, "Move order should include a non-empty path with movement")
	_assert_true(not path.has(Vector2i(4, 0)), "Move order should not path into the enemy occupied hex")
	_assert_true(_path_has_adjacent_steps(path), "Move order path should contain only adjacent steps")


func _test_hidden_enemy_does_not_trigger_threat_response() -> void:
	var units := {
		"ai_defender": _unit("ai_defender", 1, Vector2i(0, 0)),
		"hidden_enemy": _unit("hidden_enemy", 0, Vector2i(2, 0))
	}
	var orders := GameplayAIService.generate_orders(units, 1, _game_state.get("terrain_map"), _game_state.get("operational_ai_state"), {"trace_id": "hidden_threat_test", "rng_seed": 404})
	var order := orders.get("ai_defender", {}) as Dictionary
	_assert_true(order.is_empty() or int(order.get("type", -1)) != OrderSystem.OrderType.DIG_IN, "Hidden enemies outside direct visibility should not trigger DIG_IN threat response")

func _test_scouted_enemy_can_trigger_threat_response() -> void:
	var units := {
		"ai_defender": _unit("ai_defender", 1, Vector2i(0, 0)),
		"scouted_enemy": _unit("scouted_enemy", 0, Vector2i(2, 0))
	}
	var scout_intel := {
		"__unitIntelById": {
			"scouted_enemy": {"presenceKnown": true}
		}
	}
	var orders := GameplayAIService.generate_orders(units, 1, _game_state.get("terrain_map"), _game_state.get("operational_ai_state"), {"trace_id": "scouted_threat_test", "rng_seed": 505, "scout_intel": scout_intel})
	var order := orders.get("ai_defender", {}) as Dictionary
	_assert_equal(OrderSystem.OrderType.DIG_IN, int(order.get("type", -1)), "Scouted enemies inside threat range should trigger DIG_IN")

func _test_mismatched_operational_snapshot_is_ignored_for_movement() -> void:
	var units := {
		"ai_mover": _unit("ai_mover", 1, Vector2i(0, 0))
	}
	var stale_operational_state := {
		"playerIndex": 0,
		"snapshot": {
			"sectors": [{"frontlineHexIds": ["3,2"], "objectiveHexIds": ["4,2"], "contestedHexIds": []}],
			"enemyAdjacentHexes": []
		}
	}
	var orders := GameplayAIService.generate_orders(units, 1, _game_state.get("terrain_map"), stale_operational_state, {
		"trace_id": "stale_operational_snapshot_test",
		"rng_seed": 606,
		"map_dimensions": Vector2i(5, 3)
	})
	var order := orders.get("ai_mover", {}) as Dictionary
	_assert_equal(OrderSystem.OrderType.MOVE, int(order.get("type", -1)), "Unthreatened AI unit should still produce MOVE without matching operational state")
	var path := order.get("path", []) as Array
	_assert_true(path.size() >= 2, "Move order should include a path when mismatched operational state is ignored")
	var destination := path[path.size() - 1] as Vector2i
	_assert_equal(Vector2i(2, 1), destination, "Mismatched operational snapshot objectives/frontlines should be ignored in favor of fallback movement target")
	_assert_true(destination != Vector2i(4, 2) and destination != Vector2i(3, 2), "Move order destination should not use the other player's stale operational targets")

func _test_primary_objective_concentrates_same_parent_platoons() -> void:
	var root := _formation_root()
	var units := {
		"p1": _formation_unit("p1", 1, Vector2i(1, 1), "platoon"),
		"p2": _formation_unit("p2", 1, Vector2i(1, 1), "platoon"),
		"p3": _formation_unit("p3", 1, Vector2i(3, 1), "platoon")
	}
	var operational_state := _formation_operational_state(["2,1"], ["2,1"], 0.55)
	var result := FormationPosturePlanner.prepare_ai_turn(units, 1, root, operational_state, {"2,1": {"priority": "primary"}}, {"2,1": GameState.TerritoryOwnership.PLAYER_2}, {}, "balanced", 4, {})
	var next_units := result.get("units", {}) as Dictionary
	_assert_equal("concentrate", String(result.get("posture", "")), "A primary objective should trigger force concentration")
	_assert_true(next_units.has("co_a") and next_units.has("p3"), "Two co-located siblings should form a partial company while an absent sibling remains separate")
	_assert_true((result.get("assignments", {}) as Dictionary).has("co_a"), "The combined company should receive the objective assembly assignment and remain able to act")

func _test_defensive_doctrine_breaks_company_down_for_frontage() -> void:
	var root := _formation_root()
	var units := {"co_a": _formation_unit("co_a", 1, Vector2i(0, 1), "company")}
	var operational_state := _formation_operational_state(["0,1", "1,1", "2,1", "3,1"], [], 0.10)
	var result := FormationPosturePlanner.prepare_ai_turn(units, 1, root, operational_state, {}, {}, _game_state.get("terrain_map"), "defensive", 5, {})
	var next_units := result.get("units", {}) as Dictionary
	_assert_equal("spread", String(result.get("posture", "")), "Defensive doctrine should spread an intact company across an under-covered frontage")
	_assert_true(next_units.has("p1") and next_units.has("p2") and next_units.has("p3"), "A company should break down to its platoons in one free reorganization phase")
	_assert_equal(3, (result.get("assignments", {}) as Dictionary).size(), "Every resulting platoon should receive a coverage assignment")

func _test_battalion_recursively_breaks_down_to_platoons() -> void:
	var root := {
		"id": "root", "size": "army", "children": [{
			"id": "bn", "size": "battalion", "status": "alive", "children": [
				{"id": "co_a", "size": "company", "status": "alive", "children": [{"id": "a1", "size": "platoon", "status": "alive", "children": []}, {"id": "a2", "size": "platoon", "status": "alive", "children": []}]},
				{"id": "co_b", "size": "company", "status": "alive", "children": [{"id": "b1", "size": "platoon", "status": "alive", "children": []}, {"id": "b2", "size": "platoon", "status": "alive", "children": []}]}
			]
		}]
	}
	var units := {"bn": _formation_unit("bn", 1, Vector2i(0, 1), "battalion")}
	var result := FormationPosturePlanner.prepare_ai_turn(units, 1, root, _formation_operational_state(["0,1", "1,1"], [], 0.05), {}, {}, _game_state.get("terrain_map"), "defensive", 7, {})
	var next_units := result.get("units", {}) as Dictionary
	_assert_true(next_units.has("a1") and next_units.has("a2") and next_units.has("b1") and next_units.has("b2"), "A battalion should recursively break down through companies to platoons during one feasible free reorganization")
	_assert_equal(4, (result.get("assignments", {}) as Dictionary).size(), "Recursively split platoons should all receive legal frontage assignments")

func _test_reorganization_cooldown_prevents_immediate_reversal() -> void:
	var prior_state := {"lineages": {"co_a": {"mode": "concentrate", "turn": 8, "target_hex": "2,1"}}}
	var result := FormationPosturePlanner.prepare_ai_turn({"co_a": _formation_unit("co_a", 1, Vector2i(0, 1), "company")}, 1, _formation_root(), _formation_operational_state(["0,1", "1,1", "2,1", "3,1"], [], 0.05), {}, {}, _game_state.get("terrain_map"), "defensive", 9, prior_state)
	_assert_true((result.get("units", {}) as Dictionary).has("co_a"), "The two-turn cooldown should prevent a company from splitting one turn after it concentrated")

func _test_formation_assignment_precedes_generic_movement() -> void:
	var units := {"ai_mover": _unit("ai_mover", 1, Vector2i(0, 0))}
	var orders := GameplayAIService.generate_orders(units, 1, _game_state.get("terrain_map"), _game_state.get("operational_ai_state"), {
		"map_dimensions": Vector2i(5, 3),
		"formation_assignments": {"ai_mover": Vector2i(4, 2)}
	})
	var path := (orders.get("ai_mover", {}) as Dictionary).get("path", []) as Array
	_assert_true(not path.is_empty() and path[path.size() - 1] == Vector2i(4, 2), "Formation assembly and coverage assignments should precede generic operational targets")

func _test_projected_destinations_allow_legal_concentration_stack() -> void:
	var units := {
		"c1": _unit("c1", 1, Vector2i(0, 0)),
		"c2": _unit("c2", 1, Vector2i(0, 1)),
		"c3": _unit("c3", 1, Vector2i(0, 2)),
		"c4": _unit("c4", 1, Vector2i(1, 2))
	}
	var assignments := {"c1": Vector2i(3, 1), "c2": Vector2i(3, 1), "c3": Vector2i(3, 1), "c4": Vector2i(3, 1)}
	var orders := GameplayAIService.generate_orders(units, 1, _game_state.get("terrain_map"), {}, {
		"map_dimensions": Vector2i(5, 3),
		"formation_assignments": assignments
	})
	_assert_equal(4, orders.size(), "Projected destination reservations should allow four compatible companies to share an objective")
	for unit_id in units.keys():
		var path := (orders.get(unit_id, {}) as Dictionary).get("path", []) as Array
		_assert_true(not path.is_empty() and path[path.size() - 1] == Vector2i(3, 1), "Every legally stackable company should retain the shared concentration target")

func _test_concentration_fills_objective_then_adjacent_ring() -> void:
	var units := {
		"c1": _unit("c1", 1, Vector2i(0, 0)),
		"c2": _unit("c2", 1, Vector2i(0, 1)),
		"c3": _unit("c3", 1, Vector2i(0, 2)),
		"c4": _unit("c4", 1, Vector2i(1, 0)),
		"c5": _unit("c5", 1, Vector2i(1, 1)),
		"c6": _unit("c6", 1, Vector2i(1, 2))
	}
	var target := Vector2i(4, 1)
	var operational_state := _formation_operational_state(["3,1"], ["4,1"], 1.0)
	var result := FormationPosturePlanner.prepare_ai_turn(units, 1, {}, operational_state, {"4,1": {"priority": "primary"}}, {}, _game_state.get("terrain_map"), "aggressive", 10, {})
	var assignments := result.get("assignments", {}) as Dictionary
	var objective_count := 0
	var ring_count := 0
	for target_variant in assignments.values():
		if target_variant == target:
			objective_count += 1
		elif target_variant is Vector2i and Pathfinding.are_adjacent(target, target_variant as Vector2i):
			ring_count += 1
	_assert_equal(4, objective_count, "Concentration should fill the objective to its four-company capacity")
	_assert_equal(1, ring_count, "Concentration overflow should use a legal adjacent ring tile")

func _test_hex_distance_matches_odd_row_grid() -> void:
	_assert_equal(1, Pathfinding.hex_distance(Vector2i(0, 1), Vector2i(1, 2)), "Odd-row southeast neighbors should be one hex apart")
	_assert_equal(2, Pathfinding.hex_distance(Vector2i(0, 0), Vector2i(1, 1)), "Even-row diagonal coordinates that are not adjacent should be two hexes apart")
	_assert_equal(Pathfinding.hex_distance(Vector2i(4, 2), Vector2i(0, 0)), Pathfinding.hex_distance(Vector2i(0, 0), Vector2i(4, 2)), "Hex distance should be symmetric")

func _test_ai_hex_adjacency_matches_odd_row_grid_on_both_parities() -> void:
	var terrain := {"2,0": "light", "1,1": "light", "2,1": "light", "3,2": "light"}
	var converted := DeploymentDataConverter.map_payload_to_hexes(terrain, {})
	var neighbors_by_id := {}
	for hex_variant in converted:
		var hex := hex_variant as Dictionary
		neighbors_by_id[String(hex.get("id", ""))] = hex.get("neighborIds", [])
	_assert_true((neighbors_by_id.get("2,0", []) as Array).has("1,1"), "Deployment AI should use the even-row southwest neighbor")
	_assert_true((neighbors_by_id.get("2,1", []) as Array).has("3,2"), "Deployment AI should use the odd-row southeast neighbor")
	var sectors := OperationalMapAnalyzer.analyze({
		"2,1": GameState.TerritoryOwnership.PLAYER_2,
		"3,2": GameState.TerritoryOwnership.PLAYER_1
	}, GameState.TerritoryOwnership.PLAYER_2, GameState.TerritoryOwnership.PLAYER_1)
	_assert_true(not sectors.is_empty(), "Operational analysis should produce the AI-owned sector")
	if not sectors.is_empty():
		_assert_true(((sectors[0] as Dictionary).get("frontlineHexIds", []) as Array).has("2,1"), "Operational AI should recognize an enemy on the odd-row southeast neighbor as frontline contact")

func _test_movement_preview_reports_illegal_final_stack() -> void:
	var units := {}
	for index in range(5):
		var unit_id := "stack_%d" % index
		units[unit_id] = _unit(unit_id, 1, Vector2i(0, 0))
	var preview := TurnResolver.preview_movement(units, {})
	_assert_equal(1, (preview.get("stack_violations", []) as Array).size(), "Movement preview should reject a final stack above four company-equivalents")

func _test_enemy_contact_memory_decays_without_tracking_hidden_movement() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	var contact_units := {
		"friendly": _formation_unit("friendly", 1, Vector2i(1, 1), "company"),
		"enemy": _formation_unit("enemy", 0, Vector2i(2, 1), "company")
	}
	var observed := ReconSystem.resolve_turn_start_intel(contact_units, 1, {}, rng, 3)
	var hidden_units := contact_units.duplicate(true)
	(hidden_units["enemy"] as Dictionary)["hex"] = Vector2i(4, 2)
	var remembered := ReconSystem.resolve_turn_start_intel(hidden_units, 1, observed, rng, 4)
	var memory := (remembered.get(ReconSystem.UNIT_INTEL_KEY, {}) as Dictionary).get("enemy", {}) as Dictionary
	_assert_equal("2,1", String(memory.get("lastKnownHex", "")), "Lost contacts should remain at their last observed hex instead of tracking hidden movement")
	_assert_equal(0.7, float(memory.get("memoryConfidence", 0.0)), "A one-turn-old contact should decay to 0.7 confidence")

func _test_operational_snapshot_uses_authored_objectives_and_remembered_contacts() -> void:
	GameState.active_player = 1
	GameState.territory_map = {"0,1": GameState.TerritoryOwnership.PLAYER_2, "1,1": GameState.TerritoryOwnership.PLAYER_1}
	GameState.key_objectives = {"1,1": {"priority": "primary"}}
	GameState.gameplay_units = {
		"ai_unit": _formation_unit("ai_unit", 1, Vector2i(0, 1), "company"),
		"hidden_enemy": _formation_unit("hidden_enemy", 0, Vector2i(4, 2), "company")
	}
	var observer_intel := {ReconSystem.UNIT_INTEL_KEY: {"hidden_enemy": {"lastKnownHex": "1,1", "reportedSize": "company", "memoryConfidence": 0.4}}}
	GameState.scout_intel_by_observer = {"1": observer_intel}
	var by_hex := OperationalAIService._units_by_hex_for_observer(1, 0, observer_intel)
	_assert_true(by_hex.has("1,1") and not by_hex.has("4,2"), "Operational analysis should project a hidden enemy at its remembered hex without reading its actual hidden position")
	var snapshot := OperationalAIService._build_operational_snapshot(1, {"doctrine": "balanced", "difficulty": "medium"})
	var sectors := snapshot.get("sectors", []) as Array
	_assert_true(not sectors.is_empty() and ((sectors[0] as Dictionary).get("objectiveHexIds", []) as Array).has("1,1"), "Operational sectors should include the map author's primary objective")
	_assert_equal(1.0, float((sectors[0] as Dictionary).get("objectiveCriticality", 0.0)), "A primary objective should make its assigned sector fully critical")

func _formation_root() -> Dictionary:
	var platoons := [
		{"id": "p1", "size": "platoon", "status": "alive", "children": []},
		{"id": "p2", "size": "platoon", "status": "alive", "children": []},
		{"id": "p3", "size": "platoon", "status": "alive", "children": []}
	]
	return {"id": "root", "size": "army", "children": [{"id": "bn", "size": "battalion", "status": "alive", "children": [{"id": "co_a", "size": "company", "status": "alive", "children": platoons}]}]}

func _formation_operational_state(frontline: Array[String], objectives: Array[String], pressure: float) -> Dictionary:
	return {
		"playerIndex": 1,
		"snapshot": {"sectors": [{"sectorId": "sector_a", "frontlineHexIds": frontline, "objectiveHexIds": objectives, "pressure": pressure}]},
		"assessment": {"sectorAssessments": [{"sectorId": "sector_a", "urgency": pressure}]}
	}

func _formation_unit(id: String, owner: int, hex: Vector2i, size: String) -> Dictionary:
	return {"id": id, "owner": owner, "hex": hex, "size": size, "type": "infantry", "role": "infantry", "status": "alive", "initiative": 50}

func _path_has_adjacent_steps(path: Array) -> bool:
	if path.size() < 2:
		return false
	for index in range(1, path.size()):
		if not Pathfinding.are_adjacent(path[index - 1] as Vector2i, path[index] as Vector2i):
			return false
	return true

func _unit(id: String, owner: int, hex: Vector2i) -> Dictionary:
	return {"id": id, "owner": owner, "hex": hex, "size": "company", "type": "infantry", "role": "infantry", "status": "alive", "initiative": 50}

func _assert_equal(expected: Variant, actual: Variant, message: String) -> void:
	if expected != actual:
		_fail("%s | expected=%s actual=%s" % [message, str(expected), str(actual)])

func _assert_true(value: bool, message: String) -> void:
	if not value:
		_fail(message)

func _fail(message: String) -> void:
	_failures.append(message)
