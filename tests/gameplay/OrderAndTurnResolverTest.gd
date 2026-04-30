extends SceneTree

const OrderSystem = preload("res://scripts/systems/OrderSystem.gd")
const TurnResolverScript = preload("res://scripts/systems/TurnResolver.gd")
const CombatLog = preload("res://scripts/systems/CombatLog.gd")

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	_test_dig_in_order_creation_shape()
	_test_legal_stacking_move_succeeds()
	_test_illegal_stacking_move_halts_and_logs_anomaly()
	_test_dig_in_modifies_unit_state()

	if _failures.is_empty():
		print("OrderSystem + TurnResolver tests passed.")
		quit(0)
		return

	for failure in _failures:
		push_error(failure)
	quit(1)

func _test_dig_in_order_creation_shape() -> void:
	var order := OrderSystem.create_dig_in_order("u1", {"trace_id": "t1", "session_id": "s1", "created_at_unix": 123})
	_assert_equal("u1", String(order.get("unit_id", "")), "DIG_IN order should set unit_id")
	_assert_equal(OrderSystem.OrderType.DIG_IN, int(order.get("type", -1)), "DIG_IN order should use DIG_IN type")
	_assert_true((order.get("path", []) as Array).is_empty(), "DIG_IN order path should be empty")
	_assert_equal("", String(order.get("target_unit_id", "")), "DIG_IN order target should be empty")
	_assert_true((order.get("trace_events", []) as Array).size() > 0, "DIG_IN order should emit trace event")

func _test_legal_stacking_move_succeeds() -> void:
	var units := {
		"mover": _unit("mover", 0, Vector2i(0, 0), "company"),
		"ally": _unit("ally", 0, Vector2i(1, 0), "company")
	}
	var orders := {
		"mover": OrderSystem.create_move_order("mover", [Vector2i(0, 0), Vector2i(1, 0)])
	}
	var log := CombatLog.new()
	var resolver := TurnResolverScript.new()
	var result: Dictionary = resolver.call("resolve_turn", units, orders, log)
	var moved := result.get("units", {}).get("mover", {}) as Dictionary
	_assert_equal(Vector2i(1, 0), moved.get("hex", Vector2i.ZERO), "Legal stacking move should update mover hex")
	_assert_equal(1, (result.get("execution_queue", []) as Array).size(), "Legal stacking move should queue one move step")
	_assert_equal(0, (result.get("trace_anomalies", []) as Array).size(), "Legal stacking move should not emit anomalies")

func _test_illegal_stacking_move_halts_and_logs_anomaly() -> void:
	var units := {
		"mover": _unit("mover", 0, Vector2i(0, 0), "company"),
		"a": _unit("a", 0, Vector2i(1, 0), "company"),
		"b": _unit("b", 0, Vector2i(1, 0), "company"),
		"c": _unit("c", 0, Vector2i(1, 0), "company"),
		"d": _unit("d", 0, Vector2i(1, 0), "company")
	}
	var orders := {
		"mover": OrderSystem.create_move_order("mover", [Vector2i(0, 0), Vector2i(1, 0)])
	}
	var log := CombatLog.new()
	var resolver := TurnResolverScript.new()
	var result: Dictionary = resolver.call("resolve_turn", units, orders, log)
	var moved := result.get("units", {}).get("mover", {}) as Dictionary
	_assert_equal(Vector2i(0, 0), moved.get("hex", Vector2i.ZERO), "Illegal stacking move should halt before moving")
	_assert_equal(0, (result.get("execution_queue", []) as Array).size(), "Illegal stacking move should not queue movement")
	var anomalies := result.get("trace_anomalies", []) as Array
	_assert_true(anomalies.any(func(a: Dictionary) -> bool: return String(a.get("code", "")) == "illegal_stack_move"), "Illegal stacking move should emit illegal_stack_move anomaly")
	_assert_true(log.entries.any(func(e: Dictionary) -> bool: return String(e.get("summary", "")).contains("halted")), "Illegal stacking move should write halted combat log entry")

func _test_dig_in_modifies_unit_state() -> void:
	var units := {"dug": _unit("dug", 0, Vector2i(2, 2), "company")}
	var orders := {"dug": OrderSystem.create_dig_in_order("dug")}
	var log := CombatLog.new()
	var resolver := TurnResolverScript.new()
	var result: Dictionary = resolver.call("resolve_turn", units, orders, log)
	var unit := result.get("units", {}).get("dug", {}) as Dictionary
	_assert_true(bool(unit.get("dug_in", false)), "DIG_IN should set dug_in=true")
	_assert_true(bool(unit.get("entrenched", false)), "DIG_IN should set entrenched=true")
	_assert_true(log.entries.any(func(e: Dictionary) -> bool: return String(e.get("summary", "")).contains("dug in")), "DIG_IN should log combat entry")

func _unit(id: String, owner: int, hex: Vector2i, size: String) -> Dictionary:
	return {"id": id, "owner": owner, "hex": hex, "size": size, "status": "alive"}

func _assert_equal(expected: Variant, actual: Variant, message: String) -> void:
	if expected != actual:
		_fail("%s | expected=%s actual=%s" % [message, str(expected), str(actual)])

func _assert_true(value: bool, message: String) -> void:
	if not value:
		_fail(message)

func _fail(message: String) -> void:
	_failures.append(message)
