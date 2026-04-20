extends RefCounted
class_name TurnResolver

const Pathfinding = preload("res://scripts/systems/Pathfinding.gd")
const OrderSystem = preload("res://scripts/systems/OrderSystem.gd")
const ReconSystem = preload("res://scripts/systems/ReconSystem.gd")

static func resolve_turn(units: Dictionary, orders: Dictionary, combat_log: CombatLog) -> Dictionary:
	var execution_queue: Array[Dictionary] = []
	var known_enemy_units: Array[String] = []
	var own_casualties: Array[Dictionary] = []
	var enemy_casualties: Array[Dictionary] = []

	var order_list: Array[Dictionary] = []
	for order in orders.values():
		if typeof(order) == TYPE_DICTIONARY:
			order_list.append(order)
	order_list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _initiative_score(a, units) > _initiative_score(b, units)
	)

	for order in order_list:
		var unit_id := String(order.get("unit_id", ""))
		if unit_id.is_empty() or not units.has(unit_id):
			continue
		var unit_state := units[unit_id] as Dictionary
		var owner := int(unit_state.get("owner", 0))
		var path := order.get("path", []) as Array[Vector2i]
		if path.size() > 1:
			for i in range(1, path.size()):
				var next_hex: Vector2i = path[i]
				execution_queue.append({"type": "move", "unit_id": unit_id, "to": next_hex})
				unit_state["hex"] = next_hex
				if _is_enemy_adjacent(next_hex, owner, units):
					combat_log.add_entry("%s halted due to enemy proximity at %d,%d." % [unit_id, next_hex.x, next_hex.y])
					break
			units[unit_id] = unit_state

		if int(order.get("type", OrderSystem.OrderType.MOVE)) == OrderSystem.OrderType.ATTACK:
			var target_id := String(order.get("target_unit_id", ""))
			if units.has(target_id):
				var target := units[target_id] as Dictionary
				if Pathfinding.are_adjacent(unit_state.get("hex", Vector2i.ZERO), target.get("hex", Vector2i.ZERO)):
					var recon := ReconSystem.resolve_recon(unit_state, target)
					known_enemy_units.append(target_id)
					combat_log.add_entry("%s attacked %s (%s)." % [unit_id, target_id, recon.get("band", "Unknown")], recon)
					var rng := RandomNumberGenerator.new()
					rng.randomize()
					enemy_casualties.append({"unit_id": target_id, "losses": rng.randi_range(1, 12)})
					own_casualties.append({
						"unit_id": unit_id,
						"children": [
							{"unit_id": "%s/A" % unit_id, "losses": rng.randi_range(0, 4)},
							{"unit_id": "%s/B" % unit_id, "losses": rng.randi_range(0, 4)}
						]
					})

	return {
		"units": units,
		"execution_queue": execution_queue,
		"known_enemy_units": known_enemy_units,
		"own_casualties": own_casualties,
		"enemy_casualties": enemy_casualties
	}

static func _initiative_score(order: Dictionary, units: Dictionary) -> int:
	var unit := units.get(order.get("unit_id", ""), {}) as Dictionary
	var base := int(unit.get("initiative", 50))
	var path := order.get("path", []) as Array[Vector2i]
	return base - path.size()

static func _is_enemy_adjacent(hex: Vector2i, owner: int, units: Dictionary) -> bool:
	for unit in units.values():
		if typeof(unit) != TYPE_DICTIONARY:
			continue
		if int(unit.get("owner", owner)) == owner:
			continue
		if Pathfinding.are_adjacent(hex, unit.get("hex", Vector2i.ZERO)):
			return true
	return false
