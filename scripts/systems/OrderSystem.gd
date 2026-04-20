extends RefCounted
class_name OrderSystem

enum OrderType {
	MOVE,
	ATTACK
}

static func create_move_order(unit_id: String, path: Array[Vector2i]) -> Dictionary:
	return {
		"unit_id": unit_id,
		"type": OrderType.MOVE,
		"path": path.duplicate(),
		"target_unit_id": ""
	}

static func create_attack_order(unit_id: String, path: Array[Vector2i], target_unit_id: String) -> Dictionary:
	return {
		"unit_id": unit_id,
		"type": OrderType.ATTACK,
		"path": path.duplicate(),
		"target_unit_id": target_unit_id
	}

static func upsert_order(order_book: Dictionary, order: Dictionary) -> Dictionary:
	var next := order_book.duplicate(true)
	var unit_id := String(order.get("unit_id", ""))
	if unit_id.is_empty():
		return next
	next[unit_id] = order
	return next

static func delete_order(order_book: Dictionary, unit_id: String) -> Dictionary:
	var next := order_book.duplicate(true)
	next.erase(unit_id)
	return next
