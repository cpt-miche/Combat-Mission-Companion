extends RefCounted
class_name OrderSystem

enum OrderType {
	MOVE,
	ATTACK
}

static func create_move_order(unit_id: String, path: Array[Vector2i], trace_context: Dictionary = {}) -> Dictionary:
	var trace := _normalize_trace_context(trace_context)
	var order := {
		"unit_id": unit_id,
		"type": OrderType.MOVE,
		"path": path.duplicate(),
		"target_unit_id": "",
		"trace_id": trace.get("trace_id", ""),
		"session_id": trace.get("session_id", ""),
		"created_at_unix": trace.get("created_at_unix", 0),
		"trace_events": []
	}
	var payload := {
		"unit_id": unit_id,
		"path_length": path.size(),
		"path_start": _hex_to_dict(path[0]) if not path.is_empty() else {},
		"path_end": _hex_to_dict(path[path.size() - 1]) if not path.is_empty() else {}
	}
	_add_trace_event(order, "move_order_created", payload)
	if unit_id.is_empty() or path.is_empty():
		_add_trace_anomaly(order, "invalid_order", {
			"reason": "move order missing unit_id or path",
			"unit_id": unit_id,
			"path_length": path.size()
		})
	return order

static func create_attack_order(unit_id: String, path: Array[Vector2i], target_unit_id: String, trace_context: Dictionary = {}) -> Dictionary:
	var trace := _normalize_trace_context(trace_context)
	var order := {
		"unit_id": unit_id,
		"type": OrderType.ATTACK,
		"path": path.duplicate(),
		"target_unit_id": target_unit_id,
		"trace_id": trace.get("trace_id", ""),
		"session_id": trace.get("session_id", ""),
		"created_at_unix": trace.get("created_at_unix", 0),
		"trace_events": []
	}
	var payload := {
		"unit_id": unit_id,
		"target_unit_id": target_unit_id,
		"path_length": path.size(),
		"path_start": _hex_to_dict(path[0]) if not path.is_empty() else {},
		"path_end": _hex_to_dict(path[path.size() - 1]) if not path.is_empty() else {}
	}
	_add_trace_event(order, "attack_order_created", payload)
	if unit_id.is_empty() or target_unit_id.is_empty() or path.is_empty():
		_add_trace_anomaly(order, "invalid_order", {
			"reason": "attack order missing unit_id, target_unit_id, or path",
			"unit_id": unit_id,
			"target_unit_id": target_unit_id,
			"path_length": path.size()
		})
	return order

static func upsert_order(order_book: Dictionary, order: Dictionary) -> Dictionary:
	var next := order_book.duplicate(true)
	var unit_id := String(order.get("unit_id", ""))
	if unit_id.is_empty():
		var invalid_order := order.duplicate(true)
		_add_trace_anomaly(invalid_order, "invalid_order", {
			"reason": "upsert attempted without unit_id"
		})
		return next
	next[unit_id] = order
	return next

static func delete_order(order_book: Dictionary, unit_id: String) -> Dictionary:
	var next := order_book.duplicate(true)
	next.erase(unit_id)
	return next

static func _normalize_trace_context(trace_context: Dictionary) -> Dictionary:
	var context := trace_context.duplicate(true)
	var created_at_unix := int(context.get("created_at_unix", Time.get_unix_time_from_system()))
	var trace_id := String(context.get("trace_id", ""))
	var session_id := String(context.get("session_id", ""))
	if session_id.is_empty():
		session_id = "session_%d" % created_at_unix
	if trace_id.is_empty():
		trace_id = session_id
	return {
		"trace_id": trace_id,
		"session_id": session_id,
		"created_at_unix": created_at_unix
	}

static func _add_trace_event(order: Dictionary, event_type: String, payload: Dictionary) -> void:
	var events := order.get("trace_events", []) as Array
	events.append({
		"timestamp_unix": Time.get_unix_time_from_system(),
		"type": event_type,
		"trace_id": String(order.get("trace_id", "")),
		"session_id": String(order.get("session_id", "")),
		"payload": payload.duplicate(true)
	})
	order["trace_events"] = events

static func _add_trace_anomaly(order: Dictionary, code: String, details: Dictionary) -> void:
	var anomalies := order.get("trace_anomalies", []) as Array
	anomalies.append({
		"timestamp_unix": Time.get_unix_time_from_system(),
		"code": code,
		"trace_id": String(order.get("trace_id", "")),
		"session_id": String(order.get("session_id", "")),
		"details": details.duplicate(true)
	})
	order["trace_anomalies"] = anomalies

static func _hex_to_dict(hex: Vector2i) -> Dictionary:
	return {"q": hex.x, "r": hex.y}
