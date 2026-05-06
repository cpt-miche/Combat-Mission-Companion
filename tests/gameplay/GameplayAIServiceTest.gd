extends Node

const GameplayAIService = preload("res://scripts/systems/gameplay_ai/GameplayAIService.gd")
const OrderSystem = preload("res://scripts/systems/OrderSystem.gd")
const Pathfinding = preload("res://scripts/systems/Pathfinding.gd")

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
	var orders := GameplayAIService.generate_orders(units, 1, _game_state.get("terrain_map"), _game_state.get("operational_ai_state"), {"trace_id": "dig_test", "rng_seed": 202})
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

func _path_has_adjacent_steps(path: Array) -> bool:
	if path.size() < 2:
		return false
	for index in range(1, path.size()):
		if not Pathfinding.are_adjacent(path[index - 1] as Vector2i, path[index] as Vector2i):
			return false
	return true

func _unit(id: String, owner: int, hex: Vector2i) -> Dictionary:
	return {"id": id, "owner": owner, "hex": hex, "formation_size": "company", "status": "alive", "is_alive": true, "initiative": 50}

func _assert_equal(expected: Variant, actual: Variant, message: String) -> void:
	if expected != actual:
		_fail("%s | expected=%s actual=%s" % [message, str(expected), str(actual)])

func _assert_true(value: bool, message: String) -> void:
	if not value:
		_fail(message)

func _fail(message: String) -> void:
	_failures.append(message)
